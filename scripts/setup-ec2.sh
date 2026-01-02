#!/bin/bash
# Initial EC2 setup script
# Run this once on a fresh EC2 instance

set -e

echo "=========================================="
echo "Setting up EC2 instance for golink-shorner"
echo "=========================================="

# Update system
echo "Updating system packages..."
sudo yum update -y

# Install Docker
echo "Installing Docker..."
sudo yum install -y docker
sudo systemctl start docker
sudo systemctl enable docker
sudo usermod -aG docker ec2-user

# Install AWS CLI v2 (if not already installed)
if ! command -v aws &> /dev/null; then
    echo "Installing AWS CLI..."
    curl "https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip" -o "awscliv2.zip"
    unzip awscliv2.zip
    sudo ./aws/install
    rm -rf aws awscliv2.zip
fi

# Install jq for JSON parsing
echo "Installing jq..."
sudo yum install -y jq

# curl-minimal is already installed by default on Amazon Linux 2023
# No need to install curl separately, curl-minimal is sufficient
# If you need full curl features, use: sudo yum install -y curl --allowerasing
echo "curl-minimal is already installed (sufficient for our needs)"

# Create app directory
echo "Creating application directory..."
mkdir -p /home/ec2-user/app
mkdir -p /home/ec2-user/scripts

# Create .env file - Try to retrieve from Parameter Store first, fallback to template
if [ ! -f /home/ec2-user/.env ]; then
    echo "Creating .env file..."
    
    # Try to retrieve from Parameter Store (if configured)
    if aws ssm get-parameter --name /golink-shorner/db/host --region ap-southeast-1 --query 'Parameter.Value' --output text 2>/dev/null > /dev/null; then
        echo "Retrieving database credentials from Parameter Store..."
        DB_HOST=$(aws ssm get-parameter --name /golink-shorner/db/host --region ap-southeast-1 --query 'Parameter.Value' --output text 2>/dev/null || echo "")
        DB_PORT=$(aws ssm get-parameter --name /golink-shorner/db/port --region ap-southeast-1 --query 'Parameter.Value' --output text 2>/dev/null || echo "5432")
        DB_USER=$(aws ssm get-parameter --name /golink-shorner/db/user --region ap-southeast-1 --query 'Parameter.Value' --output text 2>/dev/null || echo "onjourney")
        DB_PASSWORD=$(aws ssm get-parameter --name /golink-shorner/db/password --with-decryption --region ap-southeast-1 --query 'Parameter.Value' --output text 2>/dev/null || echo "")
        DB_NAME=$(aws ssm get-parameter --name /golink-shorner/db/name --region ap-southeast-1 --query 'Parameter.Value' --output text 2>/dev/null || echo "onjourney_link")
        
        # Create .env file with retrieved values
        cat > /home/ec2-user/.env << EOF
# Database Configuration (retrieved from Parameter Store)
DB_HOST=${DB_HOST}
DB_PORT=${DB_PORT}
DB_USER=${DB_USER}
DB_PASSWORD=${DB_PASSWORD}
DB_NAME=${DB_NAME}
DB_SSLMODE=require
EOF
        
        if [ -z "$DB_HOST" ] || [ -z "$DB_PASSWORD" ]; then
            echo "⚠️  Warning: Some parameters missing from Parameter Store. Please verify."
        else
            echo "✅ Successfully retrieved credentials from Parameter Store"
        fi
    else
        # Parameter Store not configured - fail with clear error message
        echo "❌ ERROR: Parameter Store not configured!"
        echo ""
        echo "Please setup Parameter Store before running this script:"
        echo "  1. Run: ./scripts/setup-parameter-store.sh (from local machine)"
        echo "  2. Or setup manually via AWS Console: Systems Manager → Parameter Store"
        echo "  3. Required parameters:"
        echo "     - /golink-shorner/db/host"
        echo "     - /golink-shorner/db/port"
        echo "     - /golink-shorner/db/user"
        echo "     - /golink-shorner/db/password (SecureString)"
        echo "     - /golink-shorner/db/name"
        echo ""
        echo "See docs/AWS_SETUP.md section 6 for detailed instructions."
        exit 1
    fi
fi

# Set permissions
chmod 600 /home/ec2-user/.env
chmod +x /home/ec2-user/scripts/*.sh 2>/dev/null || true

# Configure log rotation for Docker
echo "Configuring Docker log rotation..."
sudo mkdir -p /etc/docker
sudo tee /etc/docker/daemon.json > /dev/null <<EOF
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF

sudo systemctl restart docker

echo "=========================================="
echo "✅ EC2 setup completed!"
echo "=========================================="
echo ""
echo "Next steps:"
echo "1. Edit /home/ec2-user/.env with your database credentials"
echo "2. Configure IAM role for EC2 to access ECR"
echo "3. Test ECR login: aws ecr get-login-password --region ap-southeast-1 | docker login --username AWS --password-stdin <your-ecr-registry>"
echo "4. Run deploy script: /home/ec2-user/scripts/deploy.sh"
echo ""
echo "Note: You may need to log out and log back in for Docker group changes to take effect"

