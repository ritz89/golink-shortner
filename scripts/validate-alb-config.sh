#!/bin/bash
# Script to validate ALB, Target Group, and ASG configuration
# This script checks for common misconfigurations that prevent instances from being registered

set -e

AWS_REGION="${AWS_REGION:-ap-southeast-1}"
ALB_NAME="${ALB_NAME:-onjourney-golink-shortner-alb}"
TG_NAME="${TARGET_GROUP_NAME:-onjourney-golink-shortner-tg}"
ASG_NAME="${ASG_NAME:-onjourney-golink-asg}"

echo "=========================================="
echo "Validating ALB Configuration"
echo "=========================================="
echo ""

# Check ALB
echo "1. Checking ALB: $ALB_NAME"
ALB_ARN=$(aws elbv2 describe-load-balancers \
    --names "$ALB_NAME" \
    --region $AWS_REGION \
    --query 'LoadBalancers[0].LoadBalancerArn' \
    --output text 2>/dev/null)

if [ -z "$ALB_ARN" ] || [ "$ALB_ARN" == "None" ]; then
    echo "❌ ALB not found: $ALB_NAME"
    exit 1
fi

ALB_STATE=$(aws elbv2 describe-load-balancers \
    --load-balancer-arns "$ALB_ARN" \
    --region $AWS_REGION \
    --query 'LoadBalancers[0].State.Code' \
    --output text 2>/dev/null)

echo "   ALB ARN: $ALB_ARN"
echo "   State: $ALB_STATE"
if [ "$ALB_STATE" != "active" ]; then
    echo "   ⚠️  Warning: ALB is not in active state"
fi
echo ""

# Check Listeners
echo "2. Checking ALB Listeners"
HTTP_LISTENER=$(aws elbv2 describe-listeners \
    --load-balancer-arn "$ALB_ARN" \
    --region $AWS_REGION \
    --query "Listeners[?Port==\`80\`].ListenerArn" \
    --output text 2>/dev/null | head -1)

HTTPS_LISTENER=$(aws elbv2 describe-listeners \
    --load-balancer-arn "$ALB_ARN" \
    --region $AWS_REGION \
    --query "Listeners[?Port==\`443\`].ListenerArn" \
    --output text 2>/dev/null | head -1)

if [ -n "$HTTP_LISTENER" ] && [ "$HTTP_LISTENER" != "None" ]; then
    echo "   ✅ HTTP (80) listener exists: $HTTP_LISTENER"
    HTTP_TG=$(aws elbv2 describe-listeners \
        --listener-arns "$HTTP_LISTENER" \
        --region $AWS_REGION \
        --query 'Listeners[0].DefaultActions[0].TargetGroupArn' \
        --output text 2>/dev/null)
    if [ -n "$HTTP_TG" ] && [ "$HTTP_TG" != "None" ]; then
        echo "      → Forwarding to: $HTTP_TG"
    else
        ACTION_TYPE=$(aws elbv2 describe-listeners \
            --listener-arns "$HTTP_LISTENER" \
            --region $AWS_REGION \
            --query 'Listeners[0].DefaultActions[0].Type' \
            --output text 2>/dev/null)
        echo "      → Action: $ACTION_TYPE"
    fi
else
    echo "   ❌ HTTP (80) listener not found"
fi

if [ -n "$HTTPS_LISTENER" ] && [ "$HTTPS_LISTENER" != "None" ]; then
    echo "   ✅ HTTPS (443) listener exists: $HTTPS_LISTENER"
else
    echo "   ⚠️  HTTPS (443) listener not found (optional, but recommended)"
fi
echo ""

# Check Target Group
echo "3. Checking Target Group: $TG_NAME"
TG_ARN=$(aws elbv2 describe-target-groups \
    --names "$TG_NAME" \
    --region $AWS_REGION \
    --query 'TargetGroups[0].TargetGroupArn' \
    --output text 2>/dev/null)

if [ -z "$TG_ARN" ] || [ "$TG_ARN" == "None" ]; then
    echo "   ❌ Target Group not found: $TG_NAME"
    exit 1
fi

TG_PORT=$(aws elbv2 describe-target-groups \
    --target-group-arns "$TG_ARN" \
    --region $AWS_REGION \
    --query 'TargetGroups[0].Port' \
    --output text 2>/dev/null)

TG_PROTOCOL=$(aws elbv2 describe-target-groups \
    --target-group-arns "$TG_ARN" \
    --region $AWS_REGION \
    --query 'TargetGroups[0].Protocol' \
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

echo "   Target Group ARN: $TG_ARN"
echo "   Protocol: $TG_PROTOCOL"
echo "   Port: $TG_PORT"
echo "   Health Check Path: $TG_HEALTH_PATH"
echo "   Health Check Port: $TG_HEALTH_PORT"
echo ""

# Check registered targets
echo "4. Checking Registered Targets"
TARGETS=$(aws elbv2 describe-target-health \
    --target-group-arn "$TG_ARN" \
    --region $AWS_REGION \
    --query 'TargetHealthDescriptions[*].[Target.Id,TargetHealth.State,TargetHealth.Reason]' \
    --output table 2>/dev/null)

if [ -n "$TARGETS" ]; then
    echo "$TARGETS"
else
    echo "   ⚠️  No targets registered in Target Group"
fi
echo ""

# Check ASG
echo "5. Checking Auto Scaling Group: $ASG_NAME"
ASG_ARN=$(aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names "$ASG_NAME" \
    --region $AWS_REGION \
    --query 'AutoScalingGroups[0].AutoScalingGroupARN' \
    --output text 2>/dev/null)

if [ -z "$ASG_ARN" ] || [ "$ASG_ARN" == "None" ]; then
    echo "   ❌ Auto Scaling Group not found: $ASG_NAME"
    exit 1
fi

ASG_DESIRED=$(aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names "$ASG_NAME" \
    --region $AWS_REGION \
    --query 'AutoScalingGroups[0].DesiredCapacity' \
    --output text 2>/dev/null)

ASG_MIN=$(aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names "$ASG_NAME" \
    --region $AWS_REGION \
    --query 'AutoScalingGroups[0].MinSize' \
    --output text 2>/dev/null)

ASG_MAX=$(aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names "$ASG_NAME" \
    --region $AWS_REGION \
    --query 'AutoScalingGroups[0].MaxSize' \
    --output text 2>/dev/null)

ASG_INSTANCES=$(aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names "$ASG_NAME" \
    --region $AWS_REGION \
    --query 'AutoScalingGroups[0].Instances[*].InstanceId' \
    --output text 2>/dev/null)

ASG_HEALTH_TYPE=$(aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names "$ASG_NAME" \
    --region $AWS_REGION \
    --query 'AutoScalingGroups[0].HealthCheckType' \
    --output text 2>/dev/null)

ASG_TG=$(aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names "$ASG_NAME" \
    --region $AWS_REGION \
    --query 'AutoScalingGroups[0].TargetGroupARNs[0]' \
    --output text 2>/dev/null)

echo "   ASG ARN: $ASG_ARN"
echo "   Desired Capacity: $ASG_DESIRED"
echo "   Min Size: $ASG_MIN"
echo "   Max Size: $ASG_MAX"
echo "   Health Check Type: $ASG_HEALTH_TYPE"
echo "   Target Group: $ASG_TG"

if [ -z "$ASG_INSTANCES" ] || [ "$ASG_INSTANCES" == "None" ]; then
    echo "   ❌ No instances running in ASG"
    echo ""
    echo "   ⚠️  Possible issues:"
    echo "      - ASG desired capacity is 0"
    echo "      - Instances failed to launch"
    echo "      - Instances were terminated due to health check failures"
    echo "      - Launch Template has issues"
    echo "      - IAM role missing permissions"
    echo "      - Parameter Store not configured"
else
    echo "   ✅ Instances: $ASG_INSTANCES"
    echo ""
    echo "   Checking instance details..."
    for INSTANCE_ID in $ASG_INSTANCES; do
        INSTANCE_STATE=$(aws ec2 describe-instances \
            --instance-ids "$INSTANCE_ID" \
            --region $AWS_REGION \
            --query 'Reservations[0].Instances[0].State.Name' \
            --output text 2>/dev/null)
        echo "      - $INSTANCE_ID: $INSTANCE_STATE"
    done
fi
echo ""

# Check if Target Group port matches application port
echo "6. Port Configuration Check"
echo "   ⚠️  IMPORTANT: Verify Target Group port matches application port"
echo "   Target Group Port: $TG_PORT"
echo "   Application runs on: Port 3000 (from Docker container)"
echo ""
if [ "$TG_PORT" == "80" ]; then
    echo "   ⚠️  WARNING: Target Group port is 80, but application runs on 3000"
    echo "   This will cause health check failures!"
    echo "   Solution: Update Target Group port to 3000"
elif [ "$TG_PORT" == "3000" ]; then
    echo "   ✅ Target Group port matches application port (3000)"
else
    echo "   ⚠️  Target Group port is $TG_PORT (expected: 3000)"
fi
echo ""

# Check Security Groups
echo "7. Security Group Check"
ALB_SG=$(aws elbv2 describe-load-balancers \
    --load-balancer-arns "$ALB_ARN" \
    --region $AWS_REGION \
    --query 'LoadBalancers[0].SecurityGroups[0]' \
    --output text 2>/dev/null)

echo "   ALB Security Group: $ALB_SG"
echo "   Expected: sg-0ad2cbd7ab9780644 (alb-security-group)"
echo ""

# Summary
echo "=========================================="
echo "Validation Summary"
echo "=========================================="
echo ""

ISSUES=0

if [ "$TG_PORT" != "3000" ]; then
    echo "❌ ISSUE 1: Target Group port mismatch"
    echo "   Current: $TG_PORT"
    echo "   Expected: 3000"
    echo "   Fix: Update Target Group port to 3000"
    echo ""
    ISSUES=$((ISSUES + 1))
fi

if [ -z "$ASG_INSTANCES" ] || [ "$ASG_INSTANCES" == "None" ]; then
    echo "❌ ISSUE 2: No instances in ASG"
    echo "   Desired: $ASG_DESIRED"
    echo "   Possible causes:"
    echo "   - Launch Template user data script failed"
    echo "   - Parameter Store not configured"
    echo "   - IAM role missing permissions"
    echo "   - Health checks failing"
    echo ""
    ISSUES=$((ISSUES + 1))
fi

if [ "$ASG_TG" != "$TG_ARN" ]; then
    echo "❌ ISSUE 3: ASG Target Group mismatch"
    echo "   ASG Target Group: $ASG_TG"
    echo "   Expected: $TG_ARN"
    echo "   Fix: Update ASG to use correct Target Group"
    echo ""
    ISSUES=$((ISSUES + 1))
fi

if [ $ISSUES -eq 0 ]; then
    echo "✅ No obvious configuration issues found"
    echo ""
    echo "If instances are still not appearing, check:"
    echo "1. CloudWatch Logs for user data script errors"
    echo "2. EC2 instance console output"
    echo "3. ASG activity history"
    echo "4. Target Group health check status"
else
    echo "⚠️  Found $ISSUES potential issue(s) - please review and fix"
fi
echo ""

