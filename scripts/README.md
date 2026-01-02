# Deployment Scripts

Scripts untuk deployment dan maintenance aplikasi golink-shorner di EC2.

## Scripts

### `setup-alb-ssl.sh` ⭐ NEW

**Purpose:** Setup SSL certificate and HTTPS listener for Application Load Balancer

**Usage:**
```bash
# From your local machine (with AWS CLI configured)
chmod +x scripts/setup-alb-ssl.sh
./scripts/setup-alb-ssl.sh
```

**What it does:**
1. Requests SSL certificate from ACM for `onjourney.link` and `*.onjourney.link`
2. Waits for certificate validation (requires DNS CNAME records)
3. Creates HTTPS (443) listener on ALB
4. Updates HTTP (80) listener to redirect to HTTPS
5. Provides instructions for DNS CNAME setup

**Requirements:**
- AWS CLI configured with appropriate permissions
- ALB already created (`onjourney-golink-shortner-alb`)
- Domain `onjourney.link` DNS access for validation records
- IAM permissions: `acm:RequestCertificate`, `acm:DescribeCertificate`, `elbv2:CreateListener`, `elbv2:ModifyListener`

**Environment Variables:**
- `AWS_REGION` (default: `ap-southeast-1`)
- `ALB_NAME` (default: `onjourney-golink-shortner-alb`)
- `DOMAIN_NAME` (default: `onjourney.link`)
- `TARGET_GROUP_NAME` (default: `onjourney-golink-shortner-tg`)

**Example:**
```bash
export DOMAIN_NAME="onjourney.link"
export ALB_NAME="onjourney-golink-shortner-alb"
./scripts/setup-alb-ssl.sh
```

**After running script:**
1. Add CNAME records to DNS provider (onjourney.link) as instructed
2. Wait for certificate validation (5-15 minutes)
3. Add CNAME record pointing `onjourney.link` to ALB DNS name
4. Test: `curl -I https://onjourney.link/health`

---

### `validate-alb-config.sh` ⭐ NEW

**Purpose:** Validate ALB, Target Group, and ASG configuration to diagnose why instances are not appearing

**Usage:**
```bash
# From your local machine (with AWS CLI configured)
chmod +x scripts/validate-alb-config.sh
./scripts/validate-alb-config.sh
```

**What it checks:**
1. ALB status and listeners
2. Target Group port configuration (should be 3000, not 80)
3. Registered targets in Target Group
4. ASG instances and capacity
5. Security group configuration
6. Port mismatches

**Common Issues Detected:**
- ❌ Target Group port mismatch (80 vs 3000)
- ❌ No instances in ASG
- ❌ ASG Target Group not attached
- ❌ Health check configuration issues

**Example Output:**
```
❌ ISSUE 1: Target Group port mismatch
   Current: 80
   Expected: 3000
   Fix: Update Target Group port to 3000
```

**Requirements:**
- AWS CLI configured
- IAM permissions: `elbv2:Describe*`, `autoscaling:Describe*`, `ec2:Describe*`

---

### `setup-nginx-reverse-proxy.sh` ⭐ NEW

**Purpose:** Setup nginx reverse proxy on EC2 instance to forward port 80 to 3000

**Usage:**
```bash
# On EC2 instance (via SSM or SSH)
sudo ./scripts/setup-nginx-reverse-proxy.sh
```

**What it does:**
1. Installs nginx
2. Creates reverse proxy configuration (port 80 → 3000)
3. Configures health check forwarding
4. Starts and enables nginx service

**Why needed:**
- Target Group uses port 80 (cannot be changed after creation)
- Application runs on port 3000
- Nginx forwards traffic from 80 to 3000

**Note:** This is already included in user data script for new instances. Use this script only for existing instances that don't have nginx configured.

---

### `setup-parameter-store.sh` ⭐ NEW

**Purpose:** Setup AWS Systems Manager Parameter Store untuk menyimpan database credentials secara aman.

**Usage:**
```bash
# From your local machine (with AWS CLI configured)
chmod +x scripts/setup-parameter-store.sh
./scripts/setup-parameter-store.sh
```

**What it does:**
- Prompts untuk input database credentials (password di-mask saat input)
- Creates semua required parameters di Parameter Store
- Stores password sebagai SecureString (encrypted)
- Verifies bahwa parameters berhasil dibuat

**Security:**
- ✅ Password tidak muncul di terminal (masked input)
- ✅ Tidak ada credentials di command history
- ✅ Password disimpan sebagai SecureString (encrypted dengan KMS)

**Required Parameters:**
- `/golink-shorner/db/host` - Database host
- `/golink-shorner/db/port` - Database port
- `/golink-shorner/db/user` - Database user
- `/golink-shorner/db/password` - Database password (SecureString)
- `/golink-shorner/db/name` - Database name

**Note:** Script ini harus di-run **SEBELUM** instance di-launch, atau instance akan fail karena tidak ada credentials.

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
