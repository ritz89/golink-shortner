#!/bin/bash
# Script to fix infrastructure issues identified by diagnostics
# Fixes Security Group rules and other infrastructure problems

set -e

AWS_REGION="${AWS_REGION:-ap-southeast-1}"
EC2_SG_ID="${EC2_SG_ID:-sg-083aa1a4be548f2ff}"
ALB_SG_ID="${ALB_SG_ID:-sg-0ad2cbd7ab9780644}"

echo "=========================================="
echo "Fixing Infrastructure Issues"
echo "=========================================="
echo "Region: $AWS_REGION"
echo "EC2 Security Group: $EC2_SG_ID"
echo "ALB Security Group: $ALB_SG_ID"
echo ""

# 1. Fix Security Group: Allow HTTP (80) from ALB to EC2
echo "1. Fixing Security Group Rules..."
echo "   Checking current inbound rules..."

# Check if rule already exists
EXISTING_RULE=$(aws ec2 describe-security-groups \
    --group-ids "$EC2_SG_ID" \
    --region "$AWS_REGION" \
    --query "SecurityGroups[0].IpPermissions[?FromPort==\`80\` && IpProtocol==\`tcp\` && UserIdGroupPairs[0].GroupId==\`$ALB_SG_ID\`]" \
    --output text 2>/dev/null || echo "")

if [ -n "$EXISTING_RULE" ]; then
    echo "   ✅ Rule already exists: HTTP (80) from ALB SG"
else
    echo "   ❌ Missing rule: HTTP (80) from ALB SG"
    echo "   Adding rule..."
    
    aws ec2 authorize-security-group-ingress \
        --group-id "$EC2_SG_ID" \
        --protocol tcp \
        --port 80 \
        --source-group "$ALB_SG_ID" \
        --region "$AWS_REGION" \
        --output text
    
    if [ $? -eq 0 ]; then
        echo "   ✅ Successfully added HTTP (80) rule"
    else
        echo "   ❌ Failed to add rule"
        exit 1
    fi
fi
echo ""

# 2. Verify Security Group rules
echo "2. Verifying Security Group Rules..."
echo "   EC2 Security Group inbound rules:"
aws ec2 describe-security-groups \
    --group-ids "$EC2_SG_ID" \
    --region "$AWS_REGION" \
    --query 'SecurityGroups[0].IpPermissions[?FromPort==`80`].[IpProtocol,FromPort,ToPort,UserIdGroupPairs[0].GroupId,UserIdGroupPairs[0].GroupName]' \
    --output table || echo "   Could not retrieve rules"
echo ""

# 3. Fix Target Group health check protocol (HTTPS -> HTTP)
echo "3. Fixing Target Group Health Check Protocol..."
TG_NAME="onjourney-golink-shortner-tg"
TG_ARN=$(aws elbv2 describe-target-groups \
    --names "$TG_NAME" \
    --region "$AWS_REGION" \
    --query 'TargetGroups[0].TargetGroupArn' \
    --output text 2>/dev/null || echo "")

if [ -n "$TG_ARN" ] && [ "$TG_ARN" != "None" ]; then
    echo "   Target Group: $TG_NAME"
    
    # Check current health check protocol
    CURRENT_PROTOCOL=$(aws elbv2 describe-target-groups \
        --target-group-arns "$TG_ARN" \
        --region "$AWS_REGION" \
        --query 'TargetGroups[0].HealthCheckProtocol' \
        --output text 2>/dev/null || echo "")
    
    echo "   Current Health Check Protocol: $CURRENT_PROTOCOL"
    
    if [ "$CURRENT_PROTOCOL" == "HTTPS" ]; then
        echo "   [ERROR] Health check protocol is HTTPS, but application only serves HTTP"
        echo "   Changing health check protocol to HTTP..."
        
        aws elbv2 modify-target-group \
            --target-group-arn "$TG_ARN" \
            --health-check-protocol HTTP \
            --region "$AWS_REGION" \
            --output text > /dev/null
        
        if [ $? -eq 0 ]; then
            echo "   [OK] Successfully changed health check protocol to HTTP"
        else
            echo "   [ERROR] Failed to change health check protocol"
            exit 1
        fi
    elif [ "$CURRENT_PROTOCOL" == "HTTP" ]; then
        echo "   [OK] Health check protocol is already HTTP (correct)"
    else
        echo "   [WARN] Unknown health check protocol: $CURRENT_PROTOCOL"
    fi
    
    # Display current configuration
    echo "   Health Check Path: $(aws elbv2 describe-target-groups \
        --target-group-arns "$TG_ARN" \
        --region "$AWS_REGION" \
        --query 'TargetGroups[0].HealthCheckPath' \
        --output text)"
    echo "   Health Check Port: $(aws elbv2 describe-target-groups \
        --target-group-arns "$TG_ARN" \
        --region "$AWS_REGION" \
        --query 'TargetGroups[0].HealthCheckPort' \
        --output text)"
else
    echo "   [ERROR] Could not retrieve Target Group ARN"
    exit 1
fi
echo ""

# 4. Summary
echo "=========================================="
echo "Infrastructure Fix Summary"
echo "=========================================="
echo ""
echo "✅ Security Group: HTTP (80) rule added/verified"
echo "✅ Target Group: Health check protocol fixed (HTTPS -> HTTP)"
echo ""
echo "Next Steps:"
echo "1. Deploy application to all instances:"
echo "   - Trigger GitHub Actions deployment"
echo "   - Or run: ./scripts/deploy-asg.sh"
echo ""
echo "2. Wait for health checks to pass (may take 1-2 minutes)"
echo ""
echo "3. Verify deployment:"
echo "   ./scripts/check-deployment-status.sh"
echo ""
echo "4. Check Target Group health (should show healthy targets)"
echo ""

