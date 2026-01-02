# Deployment Scripts

Scripts untuk deployment dan maintenance aplikasi golink-shorner di EC2.

## Scripts

### `upload-to-s3.sh`

Script untuk upload deployment scripts ke S3 bucket. Karena repository private, scripts perlu di-upload ke S3 terlebih dahulu sebelum bisa di-download di EC2 instance.

**Usage:**
```bash
chmod +x scripts/upload-to-s3.sh
./scripts/upload-to-s3.sh
```

**What it does:**
- Upload `setup-ec2.sh` ke `s3://onjourney-asset-bucket/scripts/`
- Upload `deploy.sh` ke S3
- Upload `deploy-asg.sh` ke S3
- Create bucket jika belum ada

**Prerequisites:**
- AWS CLI installed and configured
- Access to `onjourney-asset-bucket` S3 bucket
- Scripts berada di `scripts/` directory

**Note:** Script ini harus dijalankan dari local machine sebelum deployment ke EC2.

### `setup-ec2.sh`

Script untuk initial setup EC2 instance. Run sekali pada fresh EC2 instance.

**Usage:**
```bash
chmod +x setup-ec2.sh
./setup-ec2.sh
```

**What it does:**
- Update system packages
- Install Docker
- Install AWS CLI
- Install jq
- Create app directories
- Create .env template
- Configure Docker log rotation

### `deploy.sh`

Script untuk deploy aplikasi dari ECR ke EC2 instance (single instance).

**Usage:**
```bash
export ECR_REGISTRY="<account-id>.dkr.ecr.<region>.amazonaws.com"
export IMAGE_NAME="golink-shorner"
export IMAGE_TAG="latest"
export AWS_REGION="ap-southeast-1"

chmod +x deploy.sh
./deploy.sh
```

**What it does:**
- Login to ECR
- Pull latest Docker image
- Stop old container
- Start new container
- Health check

**Environment Variables:**
- `ECR_REGISTRY` (required): ECR registry URL
- `IMAGE_NAME` (optional, default: golink-shorner): Image name
- `IMAGE_TAG` (optional, default: latest): Image tag
- `AWS_REGION` (optional, default: ap-southeast-1): AWS region
- `CONTAINER_NAME` (optional, default: golink-shorner): Container name
- `PORT` (optional, default: 3000): Application port

### `deploy-asg.sh`

Script untuk deploy aplikasi ke semua instances di Auto Scaling Group.

**Usage:**
```bash
export ASG_NAME="golink-shorner-asg"
export ECR_REGISTRY="<account-id>.dkr.ecr.<region>.amazonaws.com"
export IMAGE_NAME="golink-shorner"
export IMAGE_TAG="latest"
export AWS_REGION="ap-southeast-1"

chmod +x deploy-asg.sh
./deploy-asg.sh
```

**What it does:**
- Get all instances from ASG
- Deploy to each instance via SSH
- Report deployment summary

**Environment Variables:**
- `ASG_NAME` (optional, default: golink-shorner-asg): Auto Scaling Group name
- `ECR_REGISTRY` (required): ECR registry URL
- `IMAGE_NAME` (optional, default: golink-shorner): Image name
- `IMAGE_TAG` (optional, default: latest): Image tag
- `AWS_REGION` (optional, default: ap-southeast-1): AWS region

## Manual Deployment

### Single Instance

Jika GitHub Actions tidak tersedia, Anda bisa deploy manual:

```bash
# 1. Login to ECR
aws ecr get-login-password --region ap-southeast-1 | \
    docker login --username AWS --password-stdin <ecr-registry>

# 2. Pull image
docker pull <ecr-registry>/golink-shorner:latest

# 3. Stop old container
docker stop golink-shorner || true
docker rm golink-shorner || true

# 4. Run new container
docker run -d \
    --name golink-shorner \
    --restart unless-stopped \
    -p 3000:3000 \
    --env-file /home/ec2-user/.env \
    <ecr-registry>/golink-shorner:latest

# 5. Health check
curl http://localhost:3000/health
```

### Auto Scaling Group

Untuk deploy ke semua instances di ASG:

```bash
# Use deploy-asg.sh script
./deploy-asg.sh

# Or manually
INSTANCES=$(aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names golink-shorner-asg \
    --query 'AutoScalingGroups[0].Instances[*].InstanceId' \
    --output text)

for INSTANCE_ID in $INSTANCES; do
    INSTANCE_IP=$(aws ec2 describe-instances \
        --instance-ids $INSTANCE_ID \
        --query 'Reservations[0].Instances[0].PublicIpAddress' \
        --output text)
    
    ssh ec2-user@$INSTANCE_IP 'export ECR_REGISTRY="..."; /home/ec2-user/scripts/deploy.sh'
done
```

## Troubleshooting

### Container tidak start
```bash
# Check logs
docker logs golink-shorner

# Check environment
docker inspect golink-shorner | grep Env
```

### ECR access denied
```bash
# Verify IAM role
aws sts get-caller-identity

# Test ECR login
aws ecr get-login-password --region ap-southeast-1 | \
    docker login --username AWS --password-stdin <ecr-registry>
```

### Health check failed
```bash
# Check container status
docker ps -a

# Check logs
docker logs golink-shorner --tail 100

# Test manually
docker run --rm --env-file /home/ec2-user/.env <image> ./app -prod
```

### ASG deployment failed
```bash
# Check ASG instances
aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names golink-shorner-asg

# Check instance health
aws elbv2 describe-target-health \
    --target-group-arn <target-group-arn>
```
