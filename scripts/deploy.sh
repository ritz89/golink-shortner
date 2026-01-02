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

# Always retrieve credentials from Parameter Store and replace .env file
echo "Retrieving database credentials from Parameter Store..."
mkdir -p /home/ec2-user

# Try to retrieve from Parameter Store
if aws ssm get-parameter --name /golink-shorner/db/host --region $REGION --query 'Parameter.Value' --output text 2>/dev/null > /dev/null; then
    echo "✅ Parameter Store accessible, retrieving all credentials..."
    DB_HOST=$(aws ssm get-parameter --name /golink-shorner/db/host --region $REGION --query 'Parameter.Value' --output text 2>/dev/null || echo "")
    DB_PORT=$(aws ssm get-parameter --name /golink-shorner/db/port --region $REGION --query 'Parameter.Value' --output text 2>/dev/null || echo "5432")
    DB_USER=$(aws ssm get-parameter --name /golink-shorner/db/user --region $REGION --query 'Parameter.Value' --output text 2>/dev/null || echo "onjourney")
    DB_PASSWORD=$(aws ssm get-parameter --name /golink-shorner/db/password --with-decryption --region $REGION --query 'Parameter.Value' --output text 2>/dev/null || echo "")
    DB_NAME=$(aws ssm get-parameter --name /golink-shorner/db/name --region $REGION --query 'Parameter.Value' --output text 2>/dev/null || echo "onjourney_link")
    
    # Validate required values
    if [ -z "$DB_HOST" ] || [ -z "$DB_PASSWORD" ]; then
        echo "❌ ERROR: Failed to retrieve required credentials from Parameter Store"
        echo "   DB_HOST: ${DB_HOST:-MISSING}"
        echo "   DB_PASSWORD: ${DB_PASSWORD:+SET}${DB_PASSWORD:-MISSING}"
        exit 1
    fi
    
    # Always replace .env file with values from Parameter Store
    echo "Updating .env file with credentials from Parameter Store..."
    cat > /home/ec2-user/.env << EOF
# Database Configuration (retrieved from Parameter Store - auto-updated on each deploy)
DB_HOST=${DB_HOST}
DB_PORT=${DB_PORT}
DB_USER=${DB_USER}
DB_PASSWORD=${DB_PASSWORD}
DB_NAME=${DB_NAME}
DB_SSLMODE=require
EOF
    
    chmod 600 /home/ec2-user/.env
    
    echo "✅ Successfully updated .env file from Parameter Store"
    echo "   DB_HOST: $DB_HOST"
    echo "   DB_PORT: $DB_PORT"
    echo "   DB_USER: $DB_USER"
    echo "   DB_NAME: $DB_NAME"
    echo "   DB_PASSWORD: [REDACTED]"
else
    echo "❌ ERROR: Parameter Store not accessible"
    echo "Please ensure:"
    echo "  1. Parameter Store is configured (see docs/AWS_SETUP.md section 6)"
    echo "  2. IAM role has Parameter Store access (SecretsManagerReadWrite policy)"
    echo "  3. Parameters exist: /golink-shorner/db/*"
    exit 1
fi

# Verify .env file was created correctly
if [ ! -f /home/ec2-user/.env ]; then
    echo "❌ ERROR: .env file was not created"
    exit 1
fi

# Validate that all required values are set
if ! grep -q "^DB_HOST=" /home/ec2-user/.env || \
   ! grep -q "^DB_PASSWORD=" /home/ec2-user/.env || \
   grep -q "^DB_PASSWORD=$" /home/ec2-user/.env; then
    echo "❌ ERROR: .env file is incomplete or invalid"
    echo "Current .env content:"
    cat /home/ec2-user/.env | sed 's/DB_PASSWORD=.*/DB_PASSWORD=[REDACTED]/'
    exit 1
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

# Ensure nginx is configured and running
echo "Ensuring nginx is configured and running..."

# Check if nginx config exists, if not create it
if [ ! -f /etc/nginx/conf.d/golink-shorner.conf ]; then
    echo "Nginx config not found, creating it..."
    sudo tee /etc/nginx/conf.d/golink-shorner.conf > /dev/null <<'NGINXEOF'
upstream golink_shorner {
    server localhost:3000;
    keepalive 32;
}

server {
    listen 80;
    server_name _;

    # Health check endpoint
    location /health {
        proxy_pass http://golink_shorner/health;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        access_log off;
    }

    # All other requests
    location / {
        proxy_pass http://golink_shorner;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
}
NGINXEOF
    echo "✅ Nginx config created"
fi

# Test nginx configuration
echo "Testing nginx configuration..."
if ! sudo nginx -t; then
    echo "❌ ERROR: Nginx configuration test failed"
    echo "Checking nginx config files..."
    sudo nginx -T 2>&1 | head -50
    exit 1
fi

# Start or reload nginx
if ! systemctl is-active nginx > /dev/null 2>&1; then
    echo "Starting nginx..."
    sudo systemctl start nginx
    sudo systemctl enable nginx
else
    echo "Reloading nginx configuration..."
    sudo systemctl reload nginx || sudo systemctl restart nginx
fi

# Verify nginx is running
if ! systemctl is-active nginx > /dev/null 2>&1; then
    echo "⚠️  Warning: nginx failed to start. Checking status..."
    sudo systemctl status nginx --no-pager | head -10
    echo "⚠️  Continuing deployment, but nginx may need manual intervention"
else
    echo "✅ Nginx is running"
fi

# Health check
echo "Performing health check..."
MAX_RETRIES=10
RETRY_COUNT=0

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    # First check direct app (port 3000)
    if curl -f -s http://localhost:$PORT/health > /dev/null 2>&1; then
        echo "✅ Application health check passed (port $PORT)"
        
        # Then check via nginx (port 80)
        if curl -f -s http://localhost/health > /dev/null 2>&1; then
            echo "✅ Nginx health check passed (port 80)"
            echo "=========================================="
            echo "✅ Deployment successful!"
            echo "=========================================="
            echo "Container: $CONTAINER_NAME"
            echo "Image: $FULL_IMAGE"
            echo "Port: $PORT"
            echo "Health check: OK (both app and nginx)"
            exit 0
        else
            echo "⚠️  Application OK but nginx not responding on port 80"
            echo "   Checking nginx status..."
            sudo systemctl status nginx --no-pager | head -5
            RETRY_COUNT=$((RETRY_COUNT + 1))
            echo "   Retrying nginx health check... ($RETRY_COUNT/$MAX_RETRIES)"
            sleep 3
        fi
    else
        RETRY_COUNT=$((RETRY_COUNT + 1))
        echo "Health check failed, retrying... ($RETRY_COUNT/$MAX_RETRIES)"
        sleep 3
    fi
done

echo "=========================================="
echo "❌ Deployment failed - Health check timeout"
echo "=========================================="
echo "Checking container logs..."
docker logs $CONTAINER_NAME --tail 50
echo ""
echo "Checking nginx status..."
sudo systemctl status nginx --no-pager | head -10
echo ""
echo "Checking nginx error logs..."
sudo tail -20 /var/log/nginx/error.log 2>/dev/null || echo "No nginx error logs"
exit 1

