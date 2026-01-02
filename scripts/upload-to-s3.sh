#!/bin/bash
# Upload deployment scripts to S3 bucket
# Usage: ./scripts/upload-to-s3.sh

set -e

BUCKET_NAME="onjourney-asset-bucket"
REGION="ap-southeast-1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "=========================================="
echo "Uploading scripts to S3: $BUCKET_NAME"
echo "=========================================="

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo "❌ Error: AWS CLI is not installed"
    echo "Please install AWS CLI first: https://aws.amazon.com/cli/"
    exit 1
fi

# Check if bucket exists
if ! aws s3 ls "s3://$BUCKET_NAME" --region "$REGION" &> /dev/null; then
    echo "⚠️  Bucket $BUCKET_NAME not found. Creating bucket..."
    aws s3 mb "s3://$BUCKET_NAME" --region "$REGION"
fi

# Upload setup script
echo "Uploading setup-ec2.sh..."
aws s3 cp "$SCRIPT_DIR/setup-ec2.sh" \
    "s3://$BUCKET_NAME/scripts/setup-ec2.sh" \
    --region "$REGION" \
    --content-type "text/x-shellscript"

# Upload deploy script
if [ -f "$SCRIPT_DIR/deploy.sh" ]; then
    echo "Uploading deploy.sh..."
    aws s3 cp "$SCRIPT_DIR/deploy.sh" \
        "s3://$BUCKET_NAME/scripts/deploy.sh" \
        --region "$REGION" \
        --content-type "text/x-shellscript"
fi

# Upload deploy-asg script
if [ -f "$SCRIPT_DIR/deploy-asg.sh" ]; then
    echo "Uploading deploy-asg.sh..."
    aws s3 cp "$SCRIPT_DIR/deploy-asg.sh" \
        "s3://$BUCKET_NAME/scripts/deploy-asg.sh" \
        --region "$REGION" \
        --content-type "text/x-shellscript"
fi

echo "=========================================="
echo "✅ Scripts uploaded successfully!"
echo "=========================================="
echo ""
echo "S3 URLs:"
echo "  - Setup script: s3://$BUCKET_NAME/scripts/setup-ec2.sh"
echo "  - Deploy script: s3://$BUCKET_NAME/scripts/deploy.sh"
echo "  - Deploy ASG script: s3://$BUCKET_NAME/scripts/deploy-asg.sh"
echo ""
echo "To download on EC2 instance:"
echo "  aws s3 cp s3://$BUCKET_NAME/scripts/setup-ec2.sh /tmp/setup-ec2.sh"
echo ""

