#!/bin/bash
# Script to ensure all instances in Target Group are healthy
# Deploys to unhealthy instances and verifies health status

set -e

AWS_REGION="${AWS_REGION:-ap-southeast-1}"
TG_NAME="${TARGET_GROUP_NAME:-onjourney-golink-shortner-tg}"
ASG_NAME="${ASG_NAME:-onjourney-golink-asg}"
ECR_REGISTRY="${ECR_REGISTRY}"
IMAGE_NAME="${IMAGE_NAME:-onjourney-golink-shortner}"
IMAGE_TAG="${IMAGE_TAG:-latest}"

echo "=========================================="
echo "Ensuring All Instances Are Healthy"
echo "=========================================="
echo "Target Group: $TG_NAME"
echo "Auto Scaling Group: $ASG_NAME"
echo "Region: $AWS_REGION"
echo ""

# Get Target Group ARN
TG_ARN=$(aws elbv2 describe-target-groups \
    --names "$TG_NAME" \
    --region "$AWS_REGION" \
    --query 'TargetGroups[0].TargetGroupArn' \
    --output text 2>/dev/null)

if [ -z "$TG_ARN" ] || [ "$TG_ARN" == "None" ]; then
    echo "❌ Error: Target Group '$TG_NAME' not found"
    exit 1
fi

echo "Target Group ARN: $TG_ARN"
echo ""

# Get all targets and their health status
echo "1. Checking Target Group Health Status..."
TARGETS=$(aws elbv2 describe-target-health \
    --target-group-arn "$TG_ARN" \
    --region "$AWS_REGION" \
    --query 'TargetHealthDescriptions[*].[Target.Id,TargetHealth.State]' \
    --output text 2>/dev/null)

if [ -z "$TARGETS" ]; then
    echo "   ⚠️  No targets found in Target Group"
    echo "   Checking ASG instances..."
    
    ASG_INSTANCES=$(aws autoscaling describe-auto-scaling-groups \
        --auto-scaling-group-names "$ASG_NAME" \
        --region "$AWS_REGION" \
        --query 'AutoScalingGroups[0].Instances[?LifecycleState==`InService`].InstanceId' \
        --output text 2>/dev/null)
    
    if [ -z "$ASG_INSTANCES" ]; then
        echo "   ❌ No instances found in ASG"
        exit 1
    fi
    
    echo "   Found instances in ASG (not yet registered in Target Group):"
    for INSTANCE_ID in $ASG_INSTANCES; do
        echo "   - $INSTANCE_ID"
    done
    echo ""
    echo "   These instances need to be registered in Target Group"
    echo "   They should be automatically registered by ASG"
    echo "   Waiting 30 seconds for registration..."
    sleep 30
    
    # Re-check targets
    TARGETS=$(aws elbv2 describe-target-health \
        --target-group-arn "$TG_ARN" \
        --region "$AWS_REGION" \
        --query 'TargetHealthDescriptions[*].[Target.Id,TargetHealth.State]' \
        --output text 2>/dev/null)
fi

if [ -z "$TARGETS" ]; then
    echo "   ❌ Still no targets found after waiting"
    exit 1
fi

# Parse targets
HEALTHY_INSTANCES=""
UNHEALTHY_INSTANCES=""
INITIAL_INSTANCES=""
DRAINING_INSTANCES=""

while IFS=$'\t' read -r INSTANCE_ID STATE; do
    case "$STATE" in
        healthy)
            HEALTHY_INSTANCES="$HEALTHY_INSTANCES $INSTANCE_ID"
            ;;
        unhealthy)
            UNHEALTHY_INSTANCES="$UNHEALTHY_INSTANCES $INSTANCE_ID"
            ;;
        initial)
            INITIAL_INSTANCES="$INITIAL_INSTANCES $INSTANCE_ID"
            ;;
        draining)
            DRAINING_INSTANCES="$DRAINING_INSTANCES $INSTANCE_ID"
            ;;
    esac
done <<< "$TARGETS"

# Remove leading spaces
HEALTHY_INSTANCES=$(echo $HEALTHY_INSTANCES | xargs)
UNHEALTHY_INSTANCES=$(echo $UNHEALTHY_INSTANCES | xargs)
INITIAL_INSTANCES=$(echo $INITIAL_INSTANCES | xargs)
DRAINING_INSTANCES=$(echo $DRAINING_INSTANCES | xargs)

echo "   Healthy instances: ${HEALTHY_INSTANCES:-none}"
echo "   Unhealthy instances: ${UNHEALTHY_INSTANCES:-none}"
echo "   Initial instances: ${INITIAL_INSTANCES:-none}"
echo "   Draining instances: ${DRAINING_INSTANCES:-none}"
echo ""

# Count instances
HEALTHY_COUNT=$(echo $HEALTHY_INSTANCES | wc -w | xargs)
UNHEALTHY_COUNT=$(echo $UNHEALTHY_INSTANCES | wc -w | xargs)
INITIAL_COUNT=$(echo $INITIAL_INSTANCES | wc -w | xargs)
TOTAL_COUNT=$((HEALTHY_COUNT + UNHEALTHY_COUNT + INITIAL_COUNT))

echo "2. Summary:"
echo "   Total targets: $TOTAL_COUNT"
echo "   Healthy: $HEALTHY_COUNT"
echo "   Unhealthy: $UNHEALTHY_COUNT"
echo "   Initial: $INITIAL_COUNT"
echo ""

if [ "$UNHEALTHY_COUNT" -eq 0 ] && [ "$INITIAL_COUNT" -eq 0 ]; then
    echo "✅ All instances are healthy!"
    exit 0
fi

# Deploy to unhealthy instances
if [ -n "$UNHEALTHY_INSTANCES" ]; then
    echo "3. Deploying to unhealthy instances..."
    
    if [ -z "$ECR_REGISTRY" ]; then
        echo "   ⚠️  ECR_REGISTRY not set, getting from AWS..."
        AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
        ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
    fi
    
    for INSTANCE_ID in $UNHEALTHY_INSTANCES; do
        echo "   Deploying to: $INSTANCE_ID"
        
        # Check if instance is running
        INSTANCE_STATE=$(aws ec2 describe-instances \
            --instance-ids "$INSTANCE_ID" \
            --region "$AWS_REGION" \
            --query 'Reservations[0].Instances[0].State.Name' \
            --output text 2>/dev/null || echo "unknown")
        
        if [ "$INSTANCE_STATE" != "running" ]; then
            echo "      ⚠️  Instance is not running (state: $INSTANCE_STATE), skipping..."
            continue
        fi
        
        # Check SSM agent
        SSM_STATUS=$(aws ssm describe-instance-information \
            --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
            --region "$AWS_REGION" \
            --query 'InstanceInformationList[0].PingStatus' \
            --output text 2>/dev/null || echo "Unknown")
        
        if [ "$SSM_STATUS" != "Online" ]; then
            echo "      ⚠️  SSM agent not online (status: $SSM_STATUS), waiting..."
            for i in {1..12}; do
                sleep 10
                SSM_STATUS=$(aws ssm describe-instance-information \
                    --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
                    --region "$AWS_REGION" \
                    --query 'InstanceInformationList[0].PingStatus' \
                    --output text 2>/dev/null || echo "Unknown")
                if [ "$SSM_STATUS" == "Online" ]; then
                    echo "      ✅ SSM agent is now online"
                    break
                fi
            done
        fi
        
        if [ "$SSM_STATUS" != "Online" ]; then
            echo "      ❌ SSM agent not ready, skipping deployment"
            continue
        fi
        
        # Deploy using deploy.sh from S3
        DEPLOY_COMMAND="mkdir -p /home/ec2-user/scripts && aws s3 cp s3://onjourney-asset-bucket/scripts/deploy.sh /home/ec2-user/scripts/deploy.sh && chmod +x /home/ec2-user/scripts/deploy.sh && export ECR_REGISTRY='$ECR_REGISTRY' && export IMAGE_NAME='$IMAGE_NAME' && export IMAGE_TAG='$IMAGE_TAG' && export AWS_REGION='$AWS_REGION' && /home/ec2-user/scripts/deploy.sh"
        
        # Create JSON parameters file
        PARAMS_FILE=$(mktemp)
        if command -v jq &> /dev/null; then
            jq -n --arg cmd "$DEPLOY_COMMAND" '{commands: [$cmd]}' > "$PARAMS_FILE"
        else
            python3 -c "import json, sys; json.dump({'commands': [sys.argv[1]]}, sys.stdout)" "$DEPLOY_COMMAND" > "$PARAMS_FILE"
        fi
        
        # Send SSM command
        COMMAND_ID=$(aws ssm send-command \
            --instance-ids "$INSTANCE_ID" \
            --document-name "AWS-RunShellScript" \
            --parameters file://"$PARAMS_FILE" \
            --region "$AWS_REGION" \
            --output-s3-bucket-name "onjourney-asset-bucket" \
            --output-s3-key-prefix "ssm-commands" \
            --query 'Command.CommandId' \
            --output text 2>/dev/null)
        
        rm -f "$PARAMS_FILE"
        
        if [ -z "$COMMAND_ID" ] || [[ ! "$COMMAND_ID" =~ ^[a-f0-9-]{36}$ ]]; then
            echo "      ❌ Failed to send SSM command"
            continue
        fi
        
        echo "      Command ID: $COMMAND_ID"
        echo "      Waiting for deployment to complete..."
        
        # Wait for command to complete
        STATUS="InProgress"
        for i in {1..30}; do
            sleep 10
            STATUS=$(aws ssm get-command-invocation \
                --command-id "$COMMAND_ID" \
                --instance-id "$INSTANCE_ID" \
                --region "$AWS_REGION" \
                --query 'Status' \
                --output text 2>/dev/null || echo "InProgress")
            
            if [ "$STATUS" == "Success" ]; then
                echo "      ✅ Deployment successful"
                break
            elif [ "$STATUS" == "Failed" ] || [ "$STATUS" == "Cancelled" ] || [ "$STATUS" == "TimedOut" ]; then
                echo "      ❌ Deployment failed (Status: $STATUS)"
                aws ssm get-command-invocation \
                    --command-id "$COMMAND_ID" \
                    --instance-id "$INSTANCE_ID" \
                    --region "$AWS_REGION" \
                    --query 'StandardErrorContent' \
                    --output text 2>/dev/null | head -20
                break
            fi
        done
    done
    echo ""
fi

# Wait for health checks (may take 1-2 minutes)
if [ -n "$UNHEALTHY_INSTANCES" ] || [ -n "$INITIAL_INSTANCES" ]; then
    echo "4. Waiting for health checks to complete..."
    echo "   (Health check interval: 30s, Healthy threshold: 5 consecutive successes)"
    echo "   This may take 2-3 minutes..."
    echo ""
    
    MAX_WAIT=180  # 3 minutes
    ELAPSED=0
    INTERVAL=15
    
    while [ $ELAPSED -lt $MAX_WAIT ]; do
        sleep $INTERVAL
        ELAPSED=$((ELAPSED + INTERVAL))
        
        # Re-check health status
        TARGETS=$(aws elbv2 describe-target-health \
            --target-group-arn "$TG_ARN" \
            --region "$AWS_REGION" \
            --query 'TargetHealthDescriptions[*].[Target.Id,TargetHealth.State]' \
            --output text 2>/dev/null)
        
        HEALTHY_COUNT=0
        UNHEALTHY_COUNT=0
        
        while IFS=$'\t' read -r INSTANCE_ID STATE; do
            if [ "$STATE" == "healthy" ]; then
                HEALTHY_COUNT=$((HEALTHY_COUNT + 1))
            elif [ "$STATE" == "unhealthy" ]; then
                UNHEALTHY_COUNT=$((UNHEALTHY_COUNT + 1))
            fi
        done <<< "$TARGETS"
        
        TOTAL=$((HEALTHY_COUNT + UNHEALTHY_COUNT))
        
        echo "   [$ELAPSED/${MAX_WAIT}s] Healthy: $HEALTHY_COUNT/$TOTAL"
        
        if [ $UNHEALTHY_COUNT -eq 0 ] && [ $TOTAL -gt 0 ]; then
            echo ""
            echo "✅ All instances are now healthy!"
            break
        fi
    done
    echo ""
fi

# Final status check
echo "5. Final Health Status:"
FINAL_TARGETS=$(aws elbv2 describe-target-health \
    --target-group-arn "$TG_ARN" \
    --region "$AWS_REGION" \
    --query 'TargetHealthDescriptions[*].[Target.Id,TargetHealth.State,TargetHealth.Reason]' \
    --output table 2>/dev/null)

echo "$FINAL_TARGETS"
echo ""

# Final summary
HEALTHY_FINAL=$(aws elbv2 describe-target-health \
    --target-group-arn "$TG_ARN" \
    --region "$AWS_REGION" \
    --query 'TargetHealthDescriptions[?TargetHealth.State==`healthy`] | length(@)' \
    --output text 2>/dev/null || echo "0")

UNHEALTHY_FINAL=$(aws elbv2 describe-target-health \
    --target-group-arn "$TG_ARN" \
    --region "$AWS_REGION" \
    --query 'TargetHealthDescriptions[?TargetHealth.State==`unhealthy`] | length(@)' \
    --output text 2>/dev/null || echo "0")

TOTAL_FINAL=$((HEALTHY_FINAL + UNHEALTHY_FINAL))

echo "=========================================="
echo "Final Summary"
echo "=========================================="
echo "Total targets: $TOTAL_FINAL"
echo "Healthy: $HEALTHY_FINAL"
echo "Unhealthy: $UNHEALTHY_FINAL"
echo ""

if [ "$UNHEALTHY_FINAL" -eq 0 ] && [ "$TOTAL_FINAL" -gt 0 ]; then
    echo "✅ SUCCESS: All instances are healthy!"
    exit 0
else
    echo "⚠️  Some instances are still unhealthy"
    echo "   Run diagnostic: ./scripts/check-deployment-status.sh"
    exit 1
fi
