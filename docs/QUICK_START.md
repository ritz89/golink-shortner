# Quick Start Guide - AWS Deployment

Panduan cepat untuk deploy golink-shorner ke AWS dalam 15 menit.

## Prerequisites Checklist

- [ ] AWS Account
- [ ] GitHub repository
- [ ] AWS CLI installed (optional)
- [ ] SSH key pair

## Step 1: Create ECR Repository (2 menit)

```bash
aws ecr create-repository \
    --repository-name golink-shorner \
    --region ap-southeast-1 \
    --image-scanning-configuration scanOnPush=true
```

**Catat ECR URL:** `<account-id>.dkr.ecr.ap-southeast-1.amazonaws.com/golink-shorner`

## Step 2: Create RDS Database (5 menit)

Via AWS Console:
1. RDS → Create database
2. PostgreSQL 15.x
3. Template: Free tier
4. Instance: **db.t4g.micro** (ARM)
5. DB name: `link_shorner`
6. Username: `postgres`
7. Password: **Simpan dengan aman!**
8. Create

**Catat:** Endpoint, Port (5432), Database name, Username, Password

## Step 3: Create Application Load Balancer (3 menit)

Via AWS Console:
1. EC2 → Load Balancers → Create Load Balancer
2. Type: **Application Load Balancer**
3. Name: `golink-shorner-alb`
4. Scheme: **Internet-facing**
5. VPC: Pilih VPC
6. Availability Zones: Pilih minimal 2 AZ
7. Security group: Allow HTTP (80) from 0.0.0.0/0
8. Create

**Catat:** ALB DNS name

## Step 4: Create Target Group (2 menit)

Via AWS Console:
1. EC2 → Target Groups → Create target group
2. Type: **Instances**
3. Name: `golink-shorner-tg`
4. Protocol: **HTTP**, Port: **3000**
5. Health check path: `/health`
6. Create

**Catat:** Target Group ARN

## Step 5: Create Launch Template (3 menit)

Via AWS Console:
1. EC2 → Launch Templates → Create launch template
2. Name: `golink-shorner-template`
3. AMI: **Amazon Linux 2023 (ARM64)**
4. Instance: **t4g.small**
5. Key pair: Pilih key pair
6. Security group: Allow SSH (22) from Your IP, HTTP (3000) from ALB security group
7. IAM role: Create dengan ECR + Parameter Store access
8. User data: Copy dari AWS_SETUP.md section 4
9. Create

## Step 6: Create Auto Scaling Group (3 menit)

Via AWS Console:
1. EC2 → Auto Scaling Groups → Create Auto Scaling group
2. Name: `golink-shorner-asg`
3. Launch template: `golink-shorner-template`
4. VPC: Pilih VPC dengan 2+ subnets
5. Load balancing: Attach to `golink-shorner-tg`
6. Health check: **ELB**
7. Group size:
   - Desired: **1**
   - Min: **1**
   - Max: **2**
8. Create

**Catat:** ASG name: `golink-shorner-asg`

## Step 7: Setup Systems Manager Parameter Store (2 menit)

Via AWS Console:
1. Systems Manager → Parameter Store → Create parameter
2. Create parameters:
   - `/golink-shorner/db/host`: Database endpoint
   - `/golink-shorner/db/password`: Database password (SecureString)
   - `/golink-shorner/db/user`: `postgres`
   - `/golink-shorner/db/name`: `link_shorner`

## Step 8: Setup GitHub Actions (2 menit)

1. GitHub → Settings → Secrets and variables → Actions
2. Add secrets:
   - `AWS_ACCESS_KEY_ID`
   - `AWS_SECRET_ACCESS_KEY`
   - `ASG_NAME`: `golink-shorner-asg`
   - `EC2_HOST` (opsional, untuk fallback)
   - `EC2_USER`: `ec2-user`
   - `EC2_SSH_KEY` (private key content)
   - `ALB_DNS` (opsional, untuk health check verification)

**Note:** Deploy script akan di-copy otomatis via Launch Template user data, atau bisa di-copy manual ke instance pertama.

## Step 9: First Deployment

**Option 1: Via GitHub Actions (Recommended)**
```bash
# Push to main branch
git push origin main

# Monitor di GitHub Actions tab
```

**Option 2: Manual**
```bash
# Di EC2
export ECR_REGISTRY="<account-id>.dkr.ecr.ap-southeast-1.amazonaws.com"
cd /home/ec2-user/scripts
./deploy.sh
```

## Step 10: Verify

```bash
# Health check via ALB
curl http://<alb-dns-name>/health

# Should return: {"status":"ok"}

# Check target group health
aws elbv2 describe-target-health \
    --target-group-arn <target-group-arn>

# Check ASG instances
aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names golink-shorner-asg
```

## Troubleshooting

### Container tidak start
```bash
docker logs golink-shorner
```

### Database connection error
- Check security group: RDS harus allow dari EC2 security group
- Verify .env file credentials

### GitHub Actions failed
- Check secrets sudah di-set
- Verify SSH key sudah di-copy ke EC2 authorized_keys

## Next Steps

- [x] Setup Application Load Balancer - **DONE**
- [x] Setup Auto Scaling Group - **DONE**
- [ ] Setup CloudWatch monitoring
- [ ] Configure custom domain
- [ ] Setup SSL certificate (HTTPS)
- [ ] Enable automated backups
- [ ] Setup auto-scaling policies (CPU-based)

## Cost Estimate

**Base (1 instance):**
- EC2 t4g.small: ~$15/month
- Application Load Balancer: ~$20/month
- RDS db.t4g.micro: ~$15/month
- ECR: ~$1/month
- **Total: ~$50-55/month**

**Peak (2 instances):**
- EC2 t4g.small (2x): ~$30/month
- Application Load Balancer: ~$20/month
- RDS db.t4g.micro: ~$15/month
- ECR: ~$1/month
- **Total: ~$65-70/month**

## Full Documentation

Untuk dokumentasi lengkap, lihat: [AWS_SETUP.md](AWS_SETUP.md)

---

**Selamat! Aplikasi Anda sudah live di AWS! 🚀**

