#!/bin/bash
# Quick diagnostic script for unhealthy targets
# Uses check-deployment-status.sh which already has comprehensive diagnostics

TARGET_GROUP_NAME="${1:-onjourney-golink-shortner-tg}"

echo "=========================================="
echo "Quick Diagnosis: Unhealthy Targets"
echo "=========================================="
echo ""
echo "For comprehensive diagnostics, use:"
echo "  ./scripts/check-deployment-status.sh"
echo ""
echo "Quick fixes for 'Request timed out':"
echo "=========================================="
echo ""
echo "1. Check if nginx is running on unhealthy instances:"
echo "   aws ssm send-command --instance-ids <instance-id> \\"
echo "     --document-name 'AWS-RunShellScript' \\"
echo "     --parameters 'commands=[\"systemctl status nginx\"]'"
echo ""
echo "2. If nginx not installed/running, setup via SSM:"
echo "   ./scripts/setup-instance-via-ssm.sh <instance-id> ap-southeast-1 onjourney-asset-bucket"
echo ""
echo "3. If nginx config missing, run setup script:"
echo "   aws ssm send-command --instance-ids <instance-id> \\"
echo "     --document-name 'AWS-RunShellScript' \\"
echo "     --parameters 'commands=[\"aws s3 cp s3://onjourney-asset-bucket/scripts/setup-nginx-reverse-proxy.sh /tmp/setup-nginx.sh && chmod +x /tmp/setup-nginx.sh && sudo /tmp/setup-nginx.sh\"]'"
echo ""
echo "4. Re-deploy application:"
echo "   Trigger GitHub Actions deployment or run deploy.sh manually"
echo ""
echo "Getting unhealthy target details..."
TG_ARN=$(aws elbv2 describe-target-groups \
    --names "$TARGET_GROUP_NAME" \
    --region ap-southeast-1 \
    --query 'TargetGroups[0].TargetGroupArn' \
    --output text 2>/dev/null)

if [ -z "$TG_ARN" ] || [ "$TG_ARN" == "None" ]; then
    echo "❌ Target Group not found: $TARGET_GROUP_NAME"
    exit 1
fi

echo "Target Group ARN: $TG_ARN"
echo ""
echo "Unhealthy targets:"
aws elbv2 describe-target-health \
    --target-group-arn "$TG_ARN" \
    --region ap-southeast-1 \
    --query 'TargetHealthDescriptions[?TargetHealth.State==`unhealthy`].[Target.Id,TargetHealth.Reason,TargetHealth.Description]' \
    --output table

echo ""
echo "For detailed diagnostics on each instance, run:"
echo "  ./scripts/check-deployment-status.sh"
echo ""

