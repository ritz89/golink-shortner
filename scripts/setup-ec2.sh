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

# Create .env file template
if [ ! -f /home/ec2-user/.env ]; then
    echo "Creating .env file template..."
    cat > /home/ec2-user/.env << 'EOF'
# Database Configuration
DB_HOST=your-db-host.rds.amazonaws.com
DB_PORT=5432
DB_USER=postgres
DB_PASSWORD=your_password_here
DB_NAME=link_shorner
DB_SSLMODE=require
DB_TIMEZONE=Asia/Jakarta
EOF
    echo "⚠️  Please edit /home/ec2-user/.env with your actual database credentials"
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

