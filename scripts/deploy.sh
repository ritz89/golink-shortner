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

# Check if .env file exists
if [ ! -f /home/ec2-user/.env ]; then
    echo "Warning: .env file not found at /home/ec2-user/.env"
    echo "Container will run without environment file"
    ENV_FILE_ARG=""
else
    ENV_FILE_ARG="--env-file /home/ec2-user/.env"
fi

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

