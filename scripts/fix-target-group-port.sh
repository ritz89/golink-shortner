#!/bin/bash
# Script to fix Target Group port issue
# Solution: Setup nginx reverse proxy (port 80 → 3000) instead of creating new Target Group

set -e

AWS_REGION="${AWS_REGION:-ap-southeast-1}"
TG_NAME="${TARGET_GROUP_NAME:-onjourney-golink-shortner-tg}"
NEW_PORT=3000

echo "=========================================="
echo "Fixing Target Group Port Configuration"
echo "=========================================="
echo ""

# Get Target Group ARN
echo "1. Getting Target Group information..."
TG_ARN=$(aws elbv2 describe-target-groups \
    --names "$TG_NAME" \
    --region $AWS_REGION \
    --query 'TargetGroups[0].TargetGroupArn' \
    --output text 2>/dev/null)

if [ -z "$TG_ARN" ] || [ "$TG_ARN" == "None" ]; then
    echo "❌ Error: Target Group '$TG_NAME' not found"
    exit 1
fi

CURRENT_PORT=$(aws elbv2 describe-target-groups \
    --target-group-arns "$TG_ARN" \
    --region $AWS_REGION \
    --query 'TargetGroups[0].Port' \
    --output text 2>/dev/null)

echo "   Target Group ARN: $TG_ARN"
echo "   Current Port: $CURRENT_PORT"
echo "   Required Port: $NEW_PORT"
echo ""

if [ "$CURRENT_PORT" == "$NEW_PORT" ]; then
    echo "✅ Target Group port is already correct ($NEW_PORT)"
    echo "   No changes needed"
    exit 0
fi

echo "⚠️  WARNING: Target Group port mismatch detected!"
echo "   Current: $CURRENT_PORT"
echo "   Required: $NEW_PORT (application runs on port 3000)"
echo ""
echo "   This will cause:"
echo "   - Health check failures"
echo "   - Instances not registered in Target Group"
echo "   - ASG terminating instances due to health check failures"
echo ""
read -p "Do you want to update Target Group port to $NEW_PORT? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "❌ Update cancelled"
    exit 1
fi

echo ""
echo "2. Updating Target Group port..."

# Note: AWS CLI doesn't support modifying Target Group port directly
# We need to use modify-target-group-attributes
# However, port cannot be changed after creation - we need to create a new Target Group

echo "⚠️  IMPORTANT: AWS does not allow changing Target Group port after creation"
echo "   You need to create a new Target Group with port 3000"
echo ""
echo "   Steps to fix:"
echo "   1. Create new Target Group with port 3000"
echo "   2. Update ALB listener to use new Target Group"
echo "   3. Update ASG to use new Target Group"
echo "   4. Delete old Target Group (after verification)"
echo ""
echo "   Or use AWS Console:"
echo "   1. EC2 → Target Groups → Create target group"
echo "   2. Port: 3000 (not 80!)"
echo "   3. Health check path: /health"
echo "   4. Update ALB listener to forward to new Target Group"
echo "   5. Update ASG to attach to new Target Group"
echo ""

# Provide manual instructions
echo "=========================================="
echo "Manual Fix Instructions"
echo "=========================================="
echo ""
echo "Option 1: Via AWS Console (Recommended)"
echo "----------------------------------------"
echo "1. EC2 Console → Target Groups"
echo "2. Create new target group:"
echo "   - Name: onjourney-golink-shortner-tg-v2"
echo "   - Protocol: HTTP"
echo "   - Port: 3000 ✅ (IMPORTANT: not 80!)"
echo "   - VPC: Same as current"
echo "   - Health check: /health"
echo "3. Update ALB listener (HTTP 80):"
echo "   - Edit listener"
echo "   - Change target group to new one"
echo "4. Update ASG:"
echo "   - Edit ASG"
echo "   - Attach new Target Group"
echo "5. Wait for instances to register"
echo "6. Delete old Target Group (after verification)"
echo ""
echo "Option 2: Via AWS CLI"
echo "---------------------"
echo "# Create new Target Group"
echo "aws elbv2 create-target-group \\"
echo "    --name onjourney-golink-shortner-tg-v2 \\"
echo "    --protocol HTTP \\"
echo "    --port 3000 \\"
echo "    --vpc-id vpc-07bbbdd4033765409 \\"
echo "    --health-check-path /health \\"
echo "    --health-check-interval-seconds 30 \\"
echo "    --healthy-threshold-count 2 \\"
echo "    --unhealthy-threshold-count 3 \\"
echo "    --health-check-timeout-seconds 5 \\"
echo "    --region $AWS_REGION"
echo ""
echo "# Get new Target Group ARN and update ALB listener"
echo "# Then update ASG to use new Target Group"
echo ""

