#!/bin/bash
# Script to disable public IP assignment in Launch Template
# This is recommended for instances behind ALB

set -e

AWS_REGION="${AWS_REGION:-ap-southeast-1}"
LAUNCH_TEMPLATE_ID="${LAUNCH_TEMPLATE_ID:-lt-02dc4a959747d21b5}"
LAUNCH_TEMPLATE_NAME="${LAUNCH_TEMPLATE_NAME:-onjourney-golink-shortner}"

echo "=========================================="
echo "Disable Public IP in Launch Template"
echo "=========================================="
echo "Launch Template ID: $LAUNCH_TEMPLATE_ID"
echo "Launch Template Name: $LAUNCH_TEMPLATE_NAME"
echo "Region: $AWS_REGION"
echo ""

# Get current Launch Template configuration
echo "1. Getting current Launch Template configuration..."
CURRENT_CONFIG=$(aws ec2 describe-launch-template-versions \
    --launch-template-id "$LAUNCH_TEMPLATE_ID" \
    --region "$AWS_REGION" \
    --query 'LaunchTemplateVersions[0].LaunchTemplateData' \
    --output json)

if [ -z "$CURRENT_CONFIG" ] || [ "$CURRENT_CONFIG" == "null" ]; then
    echo "❌ Error: Could not retrieve Launch Template configuration"
    exit 1
fi

# Check current public IP setting
CURRENT_PUBLIC_IP=$(echo "$CURRENT_CONFIG" | jq -r '.NetworkInterfaces[0].AssociatePublicIpAddress // .NetworkInterfaces[0]?.AssociatePublicIpAddress // "not-set"' 2>/dev/null || echo "not-set")

echo "   Current Public IP setting: $CURRENT_PUBLIC_IP"
echo ""

if [ "$CURRENT_PUBLIC_IP" == "false" ] || [ "$CURRENT_PUBLIC_IP" == "null" ] || [ "$CURRENT_PUBLIC_IP" == "not-set" ]; then
    echo "✅ Public IP is already disabled or not set"
    echo "   No changes needed"
    exit 0
fi

# Modify configuration to disable public IP
echo "2. Modifying configuration to disable public IP..."

# Use jq to modify the JSON
MODIFIED_CONFIG=$(echo "$CURRENT_CONFIG" | jq '
    if .NetworkInterfaces then
        .NetworkInterfaces[0].AssociatePublicIpAddress = false
    else
        .NetworkInterfaces = [{
            "AssociatePublicIpAddress": false,
            "DeviceIndex": 0
        }]
    end
' 2>/dev/null)

if [ -z "$MODIFIED_CONFIG" ]; then
    echo "❌ Error: Failed to modify configuration"
    echo "   Trying alternative method..."
    
    # Alternative: Create config file and modify
    TEMP_CONFIG=$(mktemp)
    echo "$CURRENT_CONFIG" > "$TEMP_CONFIG"
    
    # Use Python for more reliable JSON modification
    MODIFIED_CONFIG=$(python3 << PYTHON_SCRIPT
import json
import sys

try:
    with open("$TEMP_CONFIG", "r") as f:
        config = json.load(f)
    
    # Ensure NetworkInterfaces exists
    if "NetworkInterfaces" not in config:
        config["NetworkInterfaces"] = []
    
    if len(config["NetworkInterfaces"]) == 0:
        config["NetworkInterfaces"].append({})
    
    # Set AssociatePublicIpAddress to false
    config["NetworkInterfaces"][0]["AssociatePublicIpAddress"] = False
    config["NetworkInterfaces"][0]["DeviceIndex"] = 0
    
    print(json.dumps(config))
except Exception as e:
    print(f"Error: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_SCRIPT
)
    
    rm -f "$TEMP_CONFIG"
fi

if [ -z "$MODIFIED_CONFIG" ]; then
    echo "❌ Error: Failed to modify configuration"
    exit 1
fi

# Save modified config to temp file
TEMP_FILE=$(mktemp)
echo "$MODIFIED_CONFIG" > "$TEMP_FILE"

echo "   Configuration modified successfully"
echo ""

# Create new Launch Template version
echo "3. Creating new Launch Template version..."
NEW_VERSION=$(aws ec2 create-launch-template-version \
    --launch-template-id "$LAUNCH_TEMPLATE_ID" \
    --source-version '$Latest' \
    --launch-template-data "file://$TEMP_FILE" \
    --region "$AWS_REGION" \
    --query 'LaunchTemplateVersion.VersionNumber' \
    --output text 2>/dev/null)

rm -f "$TEMP_FILE"

if [ -z "$NEW_VERSION" ] || [ "$NEW_VERSION" == "None" ]; then
    echo "❌ Error: Failed to create new Launch Template version"
    exit 1
fi

echo "   ✅ New version created: $NEW_VERSION"
echo ""

# Set as default version
echo "4. Setting new version as default..."
aws ec2 modify-launch-template \
    --launch-template-id "$LAUNCH_TEMPLATE_ID" \
    --default-version "$NEW_VERSION" \
    --region "$AWS_REGION" \
    --output text > /dev/null

if [ $? -eq 0 ]; then
    echo "   ✅ New version set as default"
else
    echo "   ❌ Failed to set as default version"
    exit 1
fi
echo ""

# Verify
echo "5. Verifying configuration..."
VERIFY_PUBLIC_IP=$(aws ec2 describe-launch-template-versions \
    --launch-template-id "$LAUNCH_TEMPLATE_ID" \
    --version-number "$NEW_VERSION" \
    --region "$AWS_REGION" \
    --query 'LaunchTemplateVersions[0].LaunchTemplateData.NetworkInterfaces[0].AssociatePublicIpAddress' \
    --output text 2>/dev/null || echo "not-set")

echo "   Public IP setting in new version: $VERIFY_PUBLIC_IP"
echo ""

if [ "$VERIFY_PUBLIC_IP" == "False" ] || [ "$VERIFY_PUBLIC_IP" == "not-set" ]; then
    echo "=========================================="
    echo "✅ SUCCESS: Public IP Disabled"
    echo "=========================================="
    echo ""
    echo "Next steps:"
    echo "1. New instances launched by ASG will NOT have public IP"
    echo "2. Existing instances with public IP will remain unchanged"
    echo "3. To replace existing instances:"
    echo "   - Terminate them manually, or"
    echo "   - Wait for ASG to scale in/out"
    echo ""
    echo "Important:"
    echo "- Ensure subnet has NAT Gateway for internet access"
    echo "- SSM Session Manager will still work (via NAT Gateway)"
    echo "- ECR access will work via NAT Gateway"
    echo ""
else
    echo "⚠️  Warning: Verification shows public IP might still be enabled"
    echo "   Please check manually in AWS Console"
fi
