#!/bin/bash
# Deploy script untuk Auto Scaling Group
# Deploy ke semua instances di ASG

set -e

ASG_NAME="${ASG_NAME:-golink-shorner-asg}"
REGION="${AWS_REGION:-ap-southeast-1}"
ECR_REGISTRY="${ECR_REGISTRY}"
IMAGE_NAME="${IMAGE_NAME:-onjourney-golink-shortner}"
IMAGE_TAG="${IMAGE_TAG:-latest}"

echo "=========================================="
echo "Deploying to Auto Scaling Group: $ASG_NAME"
echo "=========================================="

# Check if ECR_REGISTRY is set
if [ -z "$ECR_REGISTRY" ]; then
    echo "Error: ECR_REGISTRY environment variable is not set"
    exit 1
fi

# Get all instances in ASG
echo "Getting instances from ASG..."
INSTANCES=$(aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names $ASG_NAME \
    --region $REGION \
    --query 'AutoScalingGroups[0].Instances[?LifecycleState==`InService`].InstanceId' \
    --output text)

if [ -z "$INSTANCES" ]; then
    echo "No instances found in ASG: $ASG_NAME"
    exit 1
fi

echo "Found instances: $INSTANCES"

# Deploy to each instance
SUCCESS_COUNT=0
FAIL_COUNT=0

for INSTANCE_ID in $INSTANCES; do
    echo ""
    echo "=========================================="
    echo "Deploying to instance: $INSTANCE_ID"
    echo "=========================================="
    
    # Get instance IP
    INSTANCE_IP=$(aws ec2 describe-instances \
        --instance-ids $INSTANCE_ID \
        --region $REGION \
        --query 'Reservations[0].Instances[0].PublicIpAddress' \
        --output text)
    
    if [ -z "$INSTANCE_IP" ] || [ "$INSTANCE_IP" == "None" ]; then
        echo "Warning: Could not get public IP for instance $INSTANCE_ID"
        echo "Trying private IP..."
        INSTANCE_IP=$(aws ec2 describe-instances \
            --instance-ids $INSTANCE_ID \
            --region $REGION \
            --query 'Reservations[0].Instances[0].PrivateIpAddress' \
            --output text)
    fi
    
    if [ -z "$INSTANCE_IP" ] || [ "$INSTANCE_IP" == "None" ]; then
        echo "Error: Could not get IP for instance $INSTANCE_ID"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        continue
    fi
    
    echo "Instance IP: $INSTANCE_IP"
    
    # Deploy via SSH
    if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
        ec2-user@$INSTANCE_IP << EOF
        export ECR_REGISTRY="$ECR_REGISTRY"
        export IMAGE_NAME="$IMAGE_NAME"
        export IMAGE_TAG="$IMAGE_TAG"
        export AWS_REGION="$REGION"
        
        if [ -f /home/ec2-user/scripts/deploy.sh ]; then
            /home/ec2-user/scripts/deploy.sh
        else
            echo "Deploy script not found, deploying directly..."
            aws ecr get-login-password --region $REGION | \
                docker login --username AWS --password-stdin $ECR_REGISTRY
            docker pull $ECR_REGISTRY/$IMAGE_NAME:$IMAGE_TAG
            docker stop golink-shorner 2>/dev/null || true
            docker rm golink-shorner 2>/dev/null || true
            docker run -d \
                --name golink-shorner \
                --restart unless-stopped \
                -p 3000:3000 \
                --env-file /home/ec2-user/.env \
                $ECR_REGISTRY/$IMAGE_NAME:$IMAGE_TAG
            sleep 5
            curl -f http://localhost:3000/health || exit 1
        fi
EOF
    then
        echo "✅ Deployment successful for instance $INSTANCE_ID"
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
        echo "❌ Deployment failed for instance $INSTANCE_ID"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
done

echo ""
echo "=========================================="
echo "Deployment Summary"
echo "=========================================="
echo "Total instances: $(echo $INSTANCES | wc -w)"
echo "Successful: $SUCCESS_COUNT"
echo "Failed: $FAIL_COUNT"
echo "=========================================="

if [ $FAIL_COUNT -gt 0 ]; then
    exit 1
fi

