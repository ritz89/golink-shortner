#!/bin/bash
# Script to check deployment status and diagnose 504 Gateway Timeout issues
# Run this from your local machine with AWS CLI configured

set -e

AWS_REGION="${AWS_REGION:-ap-southeast-1}"
ALB_NAME="${ALB_NAME:-onjourney-golink-shortner-alb}"
TG_NAME="${TARGET_GROUP_NAME:-onjourney-golink-shortner-tg}"
ASG_NAME="${ASG_NAME:-onjourney-golink-asg}"
DOMAIN="${DOMAIN:-onjourney.link}"

echo "=========================================="
echo "Deployment Status Check"
echo "=========================================="
echo ""

# 1. Check ASG Instances
echo "1. Checking Auto Scaling Group Instances..."
ASG_INSTANCES=$(aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names "$ASG_NAME" \
    --region $AWS_REGION \
    --query 'AutoScalingGroups[0].Instances[*].InstanceId' \
    --output text 2>/dev/null)

if [ -z "$ASG_INSTANCES" ] || [ "$ASG_INSTANCES" == "None" ]; then
    echo "   ❌ No instances in ASG!"
    echo "   → This is the problem - no instances to serve traffic"
    exit 1
fi

echo "   ✅ Found instances:"
for INSTANCE_ID in $ASG_INSTANCES; do
    INSTANCE_STATE=$(aws ec2 describe-instances \
        --instance-ids "$INSTANCE_ID" \
        --region $AWS_REGION \
        --query 'Reservations[0].Instances[0].State.Name' \
        --output text 2>/dev/null)
    echo "      - $INSTANCE_ID: $INSTANCE_STATE"
done
echo ""

# 2. Check Target Group Health
echo "2. Checking Target Group Health..."
TG_ARN=$(aws elbv2 describe-target-groups \
    --names "$TG_NAME" \
    --region $AWS_REGION \
    --query 'TargetGroups[0].TargetGroupArn' \
    --output text 2>/dev/null)

if [ -z "$TG_ARN" ] || [ "$TG_ARN" == "None" ]; then
    echo "   ❌ Target Group not found!"
    exit 1
fi

TG_HEALTH=$(aws elbv2 describe-target-health \
    --target-group-arn "$TG_ARN" \
    --region $AWS_REGION \
    --query 'TargetHealthDescriptions[*].[Target.Id,TargetHealth.State,TargetHealth.Reason,TargetHealth.Description]' \
    --output table 2>/dev/null)

echo "$TG_HEALTH"
echo ""

# Check if any targets are healthy
HEALTHY_COUNT=$(aws elbv2 describe-target-health \
    --target-group-arn "$TG_ARN" \
    --region $AWS_REGION \
    --query 'TargetHealthDescriptions[?TargetHealth.State==`healthy`] | length(@)' \
    --output text 2>/dev/null)

if [ "$HEALTHY_COUNT" == "0" ] || [ -z "$HEALTHY_COUNT" ]; then
    echo "   ❌ No healthy targets in Target Group!"
    echo "   → This causes 504 Gateway Timeout"
    echo ""
    echo "   Checking individual instances..."
    echo ""
    
    # 3. Check each instance via SSM
    for INSTANCE_ID in $ASG_INSTANCES; do
        INSTANCE_STATE=$(aws ec2 describe-instances \
            --instance-ids "$INSTANCE_ID" \
            --region $AWS_REGION \
            --query 'Reservations[0].Instances[0].State.Name' \
            --output text 2>/dev/null)
        
        if [ "$INSTANCE_STATE" != "running" ]; then
            echo "   ⚠️  Instance $INSTANCE_ID is not running (state: $INSTANCE_STATE)"
            continue
        fi
        
        echo "   Checking instance: $INSTANCE_ID"
        
        # Check SSM agent status
        SSM_STATUS=$(aws ssm describe-instance-information \
            --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
            --region $AWS_REGION \
            --query 'InstanceInformationList[0].PingStatus' \
            --output text 2>/dev/null || echo "Unknown")
        
        if [ "$SSM_STATUS" != "Online" ]; then
            echo "      ⚠️  SSM agent not online (status: $SSM_STATUS) - cannot check instance"
            continue
        fi
        
        echo "      ✅ SSM agent online"
        echo "      Running diagnostics via SSM..."
        
        # Create diagnostic script file
        DIAG_SCRIPT=$(mktemp)
        cat > "$DIAG_SCRIPT" <<'DIAGEOF'
#!/bin/bash
echo "=== Container Status ==="
docker ps -a | grep golink-shorner || echo "Container not found"
echo ""
echo "=== Nginx Status ==="
sudo systemctl status nginx --no-pager | head -5 || echo "Nginx not running"
echo ""
echo "=== Application Health Check (direct port 3000) ==="
curl -s -m 5 http://localhost:3000/health || echo "App not responding on port 3000"
echo ""
echo "=== Nginx Health Check (port 80) ==="
curl -s -m 5 http://localhost/health || echo "Nginx not responding on port 80"
echo ""
echo "=== Container Logs (last 30 lines) ==="
docker logs golink-shorner --tail 30 2>&1 || echo "Cannot get logs"
echo ""
echo "=== Nginx Error Logs (last 10 lines) ==="
sudo tail -10 /var/log/nginx/error.log 2>&1 || echo "No nginx error logs"
echo ""
echo "=== Nginx Access Logs (last 5 lines) ==="
sudo tail -5 /var/log/nginx/access.log 2>&1 || echo "No nginx access logs"
echo ""
echo "=== Port 80 Listener ==="
sudo netstat -tulpn | grep :80 || echo "Nothing listening on port 80"
echo ""
echo "=== Port 3000 Listener ==="
sudo netstat -tulpn | grep :3000 || echo "Nothing listening on port 3000"
echo ""
echo "=== .env file check ==="
if [ -f /home/ec2-user/.env ]; then
    echo "File exists"
    grep -v PASSWORD /home/ec2-user/.env | head -5
else
    echo ".env file not found"
fi
echo ""
echo "=== Nginx Config Check ==="
sudo nginx -t 2>&1 || echo "Nginx config test failed"
DIAGEOF
        
        # Upload script to S3 first, then download on instance
        aws s3 cp "$DIAG_SCRIPT" "s3://onjourney-asset-bucket/scripts/diagnostic.sh" --region $AWS_REGION 2>/dev/null || true
        
        # Create SSM command
        SSM_COMMAND="aws s3 cp s3://onjourney-asset-bucket/scripts/diagnostic.sh /tmp/diagnostic.sh && chmod +x /tmp/diagnostic.sh && /tmp/diagnostic.sh"
        
        # Use jq or Python for JSON escaping
        if command -v jq &> /dev/null; then
            PARAMS_FILE=$(mktemp)
            jq -n --arg cmd "$SSM_COMMAND" '{commands: [$cmd]}' > "$PARAMS_FILE"
        else
            PARAMS_FILE=$(mktemp)
            python3 -c "import json, sys; json.dump({'commands': [sys.argv[1]]}, sys.stdout)" "$SSM_COMMAND" > "$PARAMS_FILE"
        fi
        
        # Send command via SSM
        COMMAND_ID=$(aws ssm send-command \
            --instance-ids "$INSTANCE_ID" \
            --document-name "AWS-RunShellScript" \
            --parameters file://"$PARAMS_FILE" \
            --region $AWS_REGION \
            --output-s3-bucket-name "onjourney-asset-bucket" \
            --output-s3-key-prefix "diagnostics" \
            --query 'Command.CommandId' \
            --output text 2>/dev/null)
        
        rm -f "$DIAG_SCRIPT" "$PARAMS_FILE"
        
        if [ -n "$COMMAND_ID" ] && [ "$COMMAND_ID" != "None" ]; then
            echo "      Command ID: $COMMAND_ID"
            echo "      Waiting for command to complete..."
            
            # Wait for command (max 30 seconds)
            for i in {1..6}; do
                sleep 5
                STATUS=$(aws ssm get-command-invocation \
                    --command-id "$COMMAND_ID" \
                    --instance-id "$INSTANCE_ID" \
                    --region $AWS_REGION \
                    --query 'Status' \
                    --output text 2>/dev/null || echo "InProgress")
                
                if [ "$STATUS" == "Success" ]; then
                    echo "      ✅ Command completed"
                    echo ""
                    echo "      Diagnostic Output:"
                    aws ssm get-command-invocation \
                        --command-id "$COMMAND_ID" \
                        --instance-id "$INSTANCE_ID" \
                        --region $AWS_REGION \
                        --query 'StandardOutputContent' \
                        --output text 2>/dev/null | sed 's/^/         /'
                    echo ""
                    break
                elif [ "$STATUS" == "Failed" ] || [ "$STATUS" == "Cancelled" ] || [ "$STATUS" == "TimedOut" ]; then
                    echo "      ❌ Command failed (Status: $STATUS)"
                    aws ssm get-command-invocation \
                        --command-id "$COMMAND_ID" \
                        --instance-id "$INSTANCE_ID" \
                        --region $AWS_REGION \
                        --query 'StandardErrorContent' \
                        --output text 2>/dev/null | sed 's/^/         /' || true
                    break
                fi
            done
        else
            echo "      ⚠️  Could not send SSM command"
        fi
        
        echo ""
    done
else
    echo "   ✅ Found $HEALTHY_COUNT healthy target(s)"
fi
echo ""

# 4. Check ALB Configuration
echo "3. Checking ALB Configuration..."
ALB_ARN=$(aws elbv2 describe-load-balancers \
    --names "$ALB_NAME" \
    --region $AWS_REGION \
    --query 'LoadBalancers[0].LoadBalancerArn' \
    --output text 2>/dev/null)

if [ -z "$ALB_ARN" ] || [ "$ALB_ARN" == "None" ]; then
    echo "   ❌ ALB not found!"
    exit 1
fi

ALB_DNS=$(aws elbv2 describe-load-balancers \
    --load-balancer-arns "$ALB_ARN" \
    --region $AWS_REGION \
    --query 'LoadBalancers[0].DNSName' \
    --output text 2>/dev/null)

ALB_STATE=$(aws elbv2 describe-load-balancers \
    --load-balancer-arns "$ALB_ARN" \
    --region $AWS_REGION \
    --query 'LoadBalancers[0].State.Code' \
    --output text 2>/dev/null)

echo "   ALB DNS: $ALB_DNS"
echo "   ALB State: $ALB_STATE"

if [ "$ALB_STATE" != "active" ]; then
    echo "   ⚠️  ALB is not active (state: $ALB_STATE)"
fi
echo ""

# 5. Check Listeners
echo "4. Checking ALB Listeners..."
LISTENERS=$(aws elbv2 describe-listeners \
    --load-balancer-arn "$ALB_ARN" \
    --region $AWS_REGION \
    --query 'Listeners[*].[Port,Protocol,DefaultActions[0].Type]' \
    --output table 2>/dev/null)

echo "$LISTENERS"
echo ""

# 6. Test ALB Health Endpoint
echo "5. Testing ALB Health Endpoint..."
if [ -n "$ALB_DNS" ]; then
    echo "   Testing: http://$ALB_DNS/health"
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "http://$ALB_DNS/health" 2>/dev/null || echo "000")
    
    if [ "$HTTP_CODE" == "200" ]; then
        echo "   ✅ ALB health check: OK (HTTP $HTTP_CODE)"
        RESPONSE=$(curl -s --max-time 10 "http://$ALB_DNS/health" 2>/dev/null || echo "")
        echo "   Response: $RESPONSE"
    elif [ "$HTTP_CODE" == "504" ]; then
        echo "   ❌ ALB health check: Gateway Timeout (HTTP $HTTP_CODE)"
        echo "   → This confirms the 504 error"
    elif [ "$HTTP_CODE" == "000" ]; then
        echo "   ❌ ALB health check: Connection failed"
    else
        echo "   ⚠️  ALB health check: HTTP $HTTP_CODE"
    fi
else
    echo "   ⚠️  Cannot test - ALB DNS not found"
fi
echo ""

# 7. Test Domain
echo "6. Testing Domain: $DOMAIN..."
if [ -n "$DOMAIN" ]; then
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "http://$DOMAIN/health" 2>/dev/null || echo "000")
    
    if [ "$HTTP_CODE" == "200" ]; then
        echo "   ✅ Domain health check: OK (HTTP $HTTP_CODE)"
    elif [ "$HTTP_CODE" == "504" ]; then
        echo "   ❌ Domain health check: Gateway Timeout (HTTP $HTTP_CODE)"
    elif [ "$HTTP_CODE" == "000" ]; then
        echo "   ⚠️  Domain health check: Connection failed (DNS may not be configured)"
    else
        echo "   ⚠️  Domain health check: HTTP $HTTP_CODE"
    fi
fi
echo ""

# 8. Check Security Groups
echo "7. Checking Security Groups..."
EC2_SG=$(aws ec2 describe-instances \
    --instance-ids $(echo $ASG_INSTANCES | cut -d' ' -f1) \
    --region $AWS_REGION \
    --query 'Reservations[0].Instances[0].SecurityGroups[0].GroupId' \
    --output text 2>/dev/null)

ALB_SG=$(aws elbv2 describe-load-balancers \
    --load-balancer-arns "$ALB_ARN" \
    --region $AWS_REGION \
    --query 'LoadBalancers[0].SecurityGroups[0]' \
    --output text 2>/dev/null)

echo "   EC2 Security Group: $EC2_SG"
echo "   ALB Security Group: $ALB_SG"

# Check EC2 SG inbound rules for port 80
EC2_SG_RULES=$(aws ec2 describe-security-groups \
    --group-ids "$EC2_SG" \
    --region $AWS_REGION \
    --query 'SecurityGroups[0].IpPermissions[?FromPort==`80`]' \
    --output json 2>/dev/null)

if echo "$EC2_SG_RULES" | grep -q "$ALB_SG"; then
    echo "   ✅ EC2 SG allows HTTP (80) from ALB SG"
else
    echo "   ❌ EC2 SG does NOT allow HTTP (80) from ALB SG!"
    echo "   → This will cause 504 Gateway Timeout"
    echo ""
    echo "   Fix: Add inbound rule to EC2 Security Group:"
    echo "   - Type: HTTP"
    echo "   - Port: 80"
    echo "   - Source: $ALB_SG (ALB Security Group)"
fi
echo ""

# 9. Check Target Group Configuration
echo "8. Checking Target Group Configuration..."
TG_PORT=$(aws elbv2 describe-target-groups \
    --target-group-arns "$TG_ARN" \
    --region $AWS_REGION \
    --query 'TargetGroups[0].Port' \
    --output text 2>/dev/null)

TG_HEALTH_PATH=$(aws elbv2 describe-target-groups \
    --target-group-arns "$TG_ARN" \
    --region $AWS_REGION \
    --query 'TargetGroups[0].HealthCheckPath' \
    --output text 2>/dev/null)

TG_HEALTH_PORT=$(aws elbv2 describe-target-groups \
    --target-group-arns "$TG_ARN" \
    --region $AWS_REGION \
    --query 'TargetGroups[0].HealthCheckPort' \
    --output text 2>/dev/null)

echo "   Target Group Port: $TG_PORT"
echo "   Health Check Path: $TG_HEALTH_PATH"
echo "   Health Check Port: $TG_HEALTH_PORT"

if [ "$TG_PORT" == "80" ]; then
    echo "   ✅ Target Group port is 80 (correct for nginx)"
else
    echo "   ⚠️  Target Group port is $TG_PORT (expected: 80 for nginx)"
fi

if [ "$TG_HEALTH_PATH" == "/health" ]; then
    echo "   ✅ Health check path is /health (correct)"
else
    echo "   ⚠️  Health check path is $TG_HEALTH_PATH (expected: /health)"
fi
echo ""

# 10. Summary
echo "=========================================="
echo "Summary & Recommendations"
echo "=========================================="
echo ""

if [ "$HEALTHY_COUNT" == "0" ] || [ -z "$HEALTHY_COUNT" ]; then
    echo "❌ ISSUE FOUND: No healthy targets in Target Group"
    echo ""
    echo "This is causing the 504 Gateway Timeout!"
    echo ""
    echo "Common causes:"
    echo "  1. ❌ Nginx not running on instances"
    echo "     Fix: sudo systemctl start nginx"
    echo ""
    echo "  2. ❌ Application container not running"
    echo "     Fix: Check deploy.sh or run deployment manually"
    echo ""
    echo "  3. ❌ Application not responding on port 3000"
    echo "     Fix: Check container logs and database connection"
    echo ""
    echo "  4. ❌ Security group blocking traffic"
    echo "     Fix: Allow HTTP (80) from ALB Security Group to EC2 Security Group"
    echo ""
    echo "  5. ❌ Health check path/port incorrect"
    echo "     Fix: Verify Target Group health check configuration"
    echo ""
    echo "Next steps:"
    echo "  1. Review diagnostic output above for each instance"
    echo "  2. Fix issues found in diagnostics"
    echo "  3. Re-run this script to verify fixes"
else
    echo "✅ Target Group has $HEALTHY_COUNT healthy target(s)"
    echo ""
    if [ "$HTTP_CODE" == "504" ]; then
        echo "⚠️  But ALB returns 504 - possible issues:"
        echo "  1. All healthy targets are draining"
        echo "  2. Application responding but very slow (timeout)"
        echo "  3. Nginx timeout configuration too short"
        echo "  4. Check ALB listener configuration"
        echo "  5. Check if domain DNS is pointing to correct ALB"
    else
        echo "✅ ALB health check returns HTTP $HTTP_CODE"
    fi
fi
echo ""
