#!/bin/bash
# Generate User Data script for Launch Template
# This script generates a User Data script that downloads and runs setup-ec2.sh from S3

set -e

S3_BUCKET="${1:-onjourney-asset-bucket}"
REGION="${2:-ap-southeast-1}"

cat << USERDATA
#!/bin/bash
# User data script untuk Auto Scaling Group
# Download dan run setup-ec2.sh dari S3 untuk memastikan semua terinstall

set -e

# Wait for instance metadata service to be ready
# IP 169.254.169.254 is AWS EC2 Instance Metadata Service (IMDS)
# - Link-local address (RFC 3927), only accessible from within the instance
# - Provides instance metadata (ID, type, IAM role credentials, etc.)
# - Must be ready before using AWS CLI (which needs IAM role credentials)
until curl -s http://169.254.169.254/latest/meta-data/instance-id > /dev/null; do
    sleep 1
done

# Create directories
mkdir -p /home/ec2-user/scripts
mkdir -p /home/ec2-user/app

# Download setup script from S3
echo "=========================================="
echo "Downloading setup-ec2.sh from S3..."
echo "=========================================="
aws s3 cp s3://${S3_BUCKET}/scripts/setup-ec2.sh /home/ec2-user/scripts/setup-ec2.sh || {
    echo "⚠️  Failed to download setup-ec2.sh from S3"
    echo "   Instance will need manual setup via SSM"
    exit 1
}

# Make executable and run
chmod +x /home/ec2-user/scripts/setup-ec2.sh
echo "Running setup-ec2.sh..."
/home/ec2-user/scripts/setup-ec2.sh

# Download deploy script from S3
echo "Downloading deploy.sh from S3..."
aws s3 cp s3://${S3_BUCKET}/scripts/deploy.sh /home/ec2-user/scripts/deploy.sh 2>/dev/null && \
    chmod +x /home/ec2-user/scripts/deploy.sh || \
    echo "⚠️  Failed to download deploy.sh (will be downloaded during deployment)"

echo "=========================================="
echo "✅ User data script completed successfully"
echo "=========================================="
USERDATA
