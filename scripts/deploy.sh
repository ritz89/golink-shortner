#!/bin/bash
# Deploy script for EC2 instance
# This script can be run manually or via GitHub Actions

set -e

REGION="${AWS_REGION:-ap-southeast-1}"
ECR_REGISTRY="${ECR_REGISTRY}"
IMAGE_NAME="${IMAGE_NAME:-onjourney-golink-shortner}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
CONTAINER_NAME="golink-shorner"
PORT=3000

echo "=========================================="
echo "Starting deployment..."
echo "=========================================="

# Check if ECR_REGISTRY is set
if [ -z "$ECR_REGISTRY" ]; then
    echo "Error: ECR_REGISTRY environment variable is not set"
    echo "Please set it to your ECR registry URL (e.g., 123456789012.dkr.ecr.ap-southeast-1.amazonaws.com)"
    exit 1
fi

FULL_IMAGE="$ECR_REGISTRY/$IMAGE_NAME:$IMAGE_TAG"

# Login to ECR
echo "Logging in to Amazon ECR..."
aws ecr get-login-password --region $REGION | \
    docker login --username AWS --password-stdin $ECR_REGISTRY

# Pull latest image
echo "Pulling latest image: $FULL_IMAGE"
docker pull $FULL_IMAGE

# Stop and remove old container
echo "Stopping old container..."
docker stop $CONTAINER_NAME 2>/dev/null || true
docker rm $CONTAINER_NAME 2>/dev/null || true

# Check if .env file exists, if not try to retrieve from Parameter Store
if [ ! -f /home/ec2-user/.env ]; then
    echo "⚠️  .env file not found, attempting to retrieve from Parameter Store..."
    
    # Try to retrieve from Parameter Store
    if aws ssm get-parameter --name /golink-shorner/db/host --region $REGION --query 'Parameter.Value' --output text 2>/dev/null > /dev/null; then
        echo "Retrieving database credentials from Parameter Store..."
        DB_HOST=$(aws ssm get-parameter --name /golink-shorner/db/host --region $REGION --query 'Parameter.Value' --output text 2>/dev/null || echo "")
        DB_PORT=$(aws ssm get-parameter --name /golink-shorner/db/port --region $REGION --query 'Parameter.Value' --output text 2>/dev/null || echo "5432")
        DB_USER=$(aws ssm get-parameter --name /golink-shorner/db/user --region $REGION --query 'Parameter.Value' --output text 2>/dev/null || echo "onjourney")
        DB_PASSWORD=$(aws ssm get-parameter --name /golink-shorner/db/password --with-decryption --region $REGION --query 'Parameter.Value' --output text 2>/dev/null || echo "")
        DB_NAME=$(aws ssm get-parameter --name /golink-shorner/db/name --region $REGION --query 'Parameter.Value' --output text 2>/dev/null || echo "onjourney_link")
        
        # Create .env file with retrieved values
        mkdir -p /home/ec2-user
        cat > /home/ec2-user/.env << EOF
# Database Configuration (retrieved from Parameter Store)
DB_HOST=${DB_HOST}
DB_PORT=${DB_PORT}
DB_USER=${DB_USER}
DB_PASSWORD=${DB_PASSWORD}
DB_NAME=${DB_NAME}
DB_SSLMODE=require
DB_TIMEZONE=Asia/Jakarta
EOF
        
        chmod 600 /home/ec2-user/.env
        
        if [ -z "$DB_HOST" ] || [ -z "$DB_PASSWORD" ]; then
            echo "❌ ERROR: Failed to retrieve credentials from Parameter Store"
            echo "   Missing DB_HOST or DB_PASSWORD"
            exit 1
        else
            echo "✅ Successfully retrieved credentials from Parameter Store"
        fi
    else
        echo "❌ ERROR: .env file not found and Parameter Store not accessible"
        echo "Please create .env file with database credentials before deploying."
        exit 1
    fi
fi

# Validate that DB_PASSWORD is set in .env file
if ! grep -q "^DB_PASSWORD=" /home/ec2-user/.env || grep -q "^DB_PASSWORD=$" /home/ec2-user/.env || grep -q "^DB_PASSWORD=your_password" /home/ec2-user/.env; then
    echo "⚠️  DB_PASSWORD is not set in .env file, attempting to retrieve from Parameter Store..."
    
    # Try to retrieve password from Parameter Store
    DB_PASSWORD=$(aws ssm get-parameter --name /golink-shorner/db/password --with-decryption --region $REGION --query 'Parameter.Value' --output text 2>/dev/null || echo "")
    
    if [ -n "$DB_PASSWORD" ]; then
        echo "✅ Retrieved DB_PASSWORD from Parameter Store, updating .env file..."
        # Update DB_PASSWORD in .env file
        if grep -q "^DB_PASSWORD=" /home/ec2-user/.env; then
            sed -i "s|^DB_PASSWORD=.*|DB_PASSWORD=$DB_PASSWORD|" /home/ec2-user/.env
        else
            echo "DB_PASSWORD=$DB_PASSWORD" >> /home/ec2-user/.env
        fi
        echo "✅ DB_PASSWORD updated in .env file"
    else
        echo "❌ ERROR: DB_PASSWORD is not set in /home/ec2-user/.env and could not retrieve from Parameter Store"
        echo "Please edit /home/ec2-user/.env and set DB_PASSWORD to your actual database password."
        exit 1
    fi
fi

ENV_FILE_ARG="--env-file /home/ec2-user/.env"
echo "✅ .env file found and validated"

# Run new container
echo "Starting new container..."
docker run -d \
    --name $CONTAINER_NAME \
    --restart unless-stopped \
    -p $PORT:$PORT \
    $ENV_FILE_ARG \
    $FULL_IMAGE

# Wait for container to start
echo "Waiting for container to start..."
sleep 5

# Health check
echo "Performing health check..."
MAX_RETRIES=5
RETRY_COUNT=0

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if curl -f http://localhost:$PORT/health > /dev/null 2>&1; then
        echo "=========================================="
        echo "✅ Deployment successful!"
        echo "=========================================="
        echo "Container: $CONTAINER_NAME"
        echo "Image: $FULL_IMAGE"
        echo "Port: $PORT"
        echo "Health check: OK"
        exit 0
    fi
    
    RETRY_COUNT=$((RETRY_COUNT + 1))
    echo "Health check failed, retrying... ($RETRY_COUNT/$MAX_RETRIES)"
    sleep 3
done

echo "=========================================="
echo "❌ Deployment failed - Health check timeout"
echo "=========================================="
echo "Checking container logs..."
docker logs $CONTAINER_NAME --tail 50
exit 1

