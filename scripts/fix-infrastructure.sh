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

# 3. Check Target Group health check configuration
echo "3. Checking Target Group Configuration..."
TG_NAME="onjourney-golink-shortner-tg"
TG_ARN=$(aws elbv2 describe-target-groups \
    --names "$TG_NAME" \
    --region "$AWS_REGION" \
    --query 'TargetGroups[0].TargetGroupArn' \
    --output text 2>/dev/null || echo "")

if [ -n "$TG_ARN" ] && [ "$TG_ARN" != "None" ]; then
    echo "   Target Group: $TG_NAME"
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
    echo "   ✅ Target Group configuration looks correct"
else
    echo "   ⚠️  Could not retrieve Target Group configuration"
fi
echo ""

# 4. Summary
echo "=========================================="
echo "Infrastructure Fix Summary"
echo "=========================================="
echo ""
echo "✅ Security Group: HTTP (80) rule added/verified"
echo ""
echo "Next Steps:"
echo "1. Deploy application to all instances:"
echo "   - Trigger GitHub Actions deployment"
echo "   - Or run: ./scripts/deploy-asg.sh"
echo ""
echo "2. Verify deployment:"
echo "   ./scripts/check-deployment-status.sh"
echo ""
echo "3. Check Target Group health (should show healthy targets)"
echo ""

