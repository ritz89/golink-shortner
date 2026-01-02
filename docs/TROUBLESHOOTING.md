# Troubleshooting Guide

Panduan troubleshooting untuk masalah umum pada deployment golink-shorner.

## Issue: EC2 Instances Tidak Muncul di ASG

### Gejala
- Auto Scaling Group menunjukkan 0 instances
- Target Group tidak memiliki registered targets
- Health checks selalu failed
- Instances di-launch tapi langsung di-terminate

### Penyebab Umum

#### 1. Target Group Port Mismatch ⚠️ **MOST COMMON - CHECK THIS FIRST!**

**Problem:** Target Group dikonfigurasi untuk port 80, tapi aplikasi berjalan di port 3000.

**✅ Solution:** Setup nginx reverse proxy di instance untuk forward port 80 ke 3000 (sudah di-include di user data script).

**Check:**
```bash
aws elbv2 describe-target-groups \
    --names onjourney-golink-shortner-tg \
    --region ap-southeast-1 \
    --query 'TargetGroups[0].Port' \
    --output text
```

**Expected:** `3000`  
**Jika hasilnya:** `80` → **INI MASALAHNYA!**

**Why this causes empty instances (if nginx not configured):**
1. ASG launches instance
2. Instance starts, application runs on port 3000
3. Target Group health check tries port 80 → **FAILS** (no service on port 80)
4. ASG sees instance as unhealthy
5. ASG terminates instance
6. Cycle repeats → No instances remain

**✅ Fix: Setup Nginx Reverse Proxy (No need to create new Target Group!)**

**Method 1: Update User Data Script in Launch Template (Recommended for new instances)**

1. Buka **EC2 Console** → **Target Groups**
2. Klik **Create target group**
3. Configuration:
   - Target type: **Instances**
   - Name: `onjourney-golink-shortner-tg-v2` (atau nama lain)
   - Protocol: **HTTP**
   - Port: **3000** ✅ **CRITICAL: Must be 3000, not 80!**
   - VPC: Same as current (`vpc-07bbbdd4033765409`)
   - Health checks:
     - Protocol: **HTTP**
     - Path: `/health`
     - Port: **traffic-port** (akan menggunakan 3000)
     - Healthy threshold: **2**
     - Unhealthy threshold: **3**
     - Timeout: **5 seconds**
     - Interval: **30 seconds**
4. Klik **Create target group**
5. Update ALB Listener:
   - EC2 → Load Balancers → Pilih ALB
   - Tab **Listeners** → Edit HTTP (80) listener
   - Change target group ke yang baru
6. Update ASG:
   - EC2 → Auto Scaling Groups → Pilih ASG
   - Tab **Details** → Edit
   - Attach new Target Group
   - Remove old Target Group
7. Wait for instances to register (5-10 minutes)
8. Verify: Check Target Group → Targets tab → Should see instances as "healthy"

**Fix (AWS CLI):**
```bash
# Create new Target Group with port 3000
aws elbv2 create-target-group \
    --name onjourney-golink-shortner-tg-v2 \
    --protocol HTTP \
    --port 3000 \
    --vpc-id vpc-07bbbdd4033765409 \
    --health-check-path /health \
    --health-check-interval-seconds 30 \
    --healthy-threshold-count 2 \
    --unhealthy-threshold-count 3 \
    --health-check-timeout-seconds 5 \
    --region ap-southeast-1

# Get new TG ARN and update ALB listener
# Then update ASG
```

**Or use fix script:**
```bash
./scripts/fix-target-group-port.sh
```

**Verification:**
```bash
# Check Target Group port
aws elbv2 describe-target-groups \
    --names onjourney-golink-shortner-tg-v2 \
    --region ap-southeast-1 \
    --query 'TargetGroups[0].Port' \
    --output text
# Should return: 3000

# Check registered targets
aws elbv2 describe-target-health \
    --target-group-arn <new-tg-arn> \
    --region ap-southeast-1
```

---

#### 2. Parameter Store Tidak Dikonfigurasi

**Problem:** User data script gagal karena Parameter Store tidak ada.

**Check:**
```bash
aws ssm get-parameter \
    --name /golink-shorner/db/host \
    --region ap-southeast-1 \
    --query 'Parameter.Value' \
    --output text
```

**Jika error:** Parameter tidak ditemukan → **INI MASALAHNYA!**

**Fix:**
```bash
# Run setup script
./scripts/setup-parameter-store.sh
```

**Verification:**
```bash
# List all parameters
aws ssm describe-parameters \
    --filters "Key=Name,Values=/golink-shorner/db/" \
    --region ap-southeast-1
```

---

#### 3. IAM Role Missing Permissions

**Problem:** EC2 instance tidak bisa akses ECR atau Parameter Store.

**Check IAM Role:**
```bash
# Get instance profile
aws ec2 describe-instances \
    --instance-ids <instance-id> \
    --region ap-southeast-1 \
    --query 'Reservations[0].Instances[0].IamInstanceProfile.Arn' \
    --output text
```

**Required Policies:**
- `AmazonEC2ContainerRegistryReadOnly` (untuk ECR)
- `SecretsManagerReadWrite` atau custom policy untuk Parameter Store
- `AmazonSSMManagedInstanceCore` (untuk SSM)

**Fix:** Attach missing policies ke IAM role `EC2RoleForSSM`

---

#### 4. Health Check Failing

**Problem:** Instances di-launch tapi langsung di-terminate karena health check failed.

**Check Target Group Health:**
```bash
aws elbv2 describe-target-health \
    --target-group-arn <target-group-arn> \
    --region ap-southeast-1
```

**Common Issues:**
- Health check path salah (harus `/health`)
- Health check port salah (harus `3000`)
- Security group tidak allow traffic dari ALB
- Application tidak running di container

**Fix:**
1. Verify health check path: `/health`
2. Verify health check port: `3000` (atau `traffic-port`)
3. Check security group: Allow HTTP (3000) from ALB security group
4. Check container logs: `docker logs golink-shorner`

---

#### 5. Launch Template User Data Script Error

**Problem:** User data script gagal, instance tidak bisa setup.

**Check Instance Console Output:**
```bash
# Via SSM Session Manager
aws ssm start-session --target <instance-id> --region ap-southeast-1

# Check user data logs
sudo cat /var/log/cloud-init-output.log
sudo cat /var/log/cloud-init.log
```

**Common Errors:**
- Parameter Store tidak accessible
- Docker installation failed
- AWS CLI installation failed
- Script download from S3 failed

**Fix:** Perbaiki user data script atau setup Parameter Store terlebih dahulu.

---

#### 6. ASG Desired Capacity = 0

**Problem:** ASG tidak launch instances karena desired capacity = 0.

**Check:**
```bash
aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names onjourney-golink-asg \
    --region ap-southeast-1 \
    --query 'AutoScalingGroups[0].DesiredCapacity' \
    --output text
```

**Expected:** `1` (atau lebih)

**Fix:**
```bash
aws autoscaling set-desired-capacity \
    --auto-scaling-group-name onjourney-golink-asg \
    --desired-capacity 1 \
    --region ap-southeast-1
```

---

### Validation Script

Gunakan script untuk validasi otomatis:

```bash
./scripts/validate-alb-config.sh
```

Script akan check:
- ✅ ALB status
- ✅ Listeners configuration
- ✅ Target Group port (should be 3000)
- ✅ Registered targets
- ✅ ASG instances
- ✅ Security groups
- ✅ Port mismatches

---

## Issue: Health Check Always Failing

### Check List

1. **Target Group Port:**
   ```bash
   aws elbv2 describe-target-groups \
       --names onjourney-golink-shortner-tg \
       --region ap-southeast-1 \
       --query 'TargetGroups[0].Port' \
       --output text
   ```
   Must be: `3000`

2. **Health Check Path:**
   ```bash
   aws elbv2 describe-target-groups \
       --names onjourney-golink-shortner-tg \
       --region ap-southeast-1 \
       --query 'TargetGroups[0].HealthCheckPath' \
       --output text
   ```
   Must be: `/health`

3. **Application Running:**
   ```bash
   # Via SSM
   docker ps | grep golink-shorner
   curl http://localhost:3000/health
   ```

4. **Security Group:**
   - EC2 Security Group harus allow HTTP (3000) from ALB Security Group
   - ALB Security Group harus allow HTTP (80) and HTTPS (443) from 0.0.0.0/0

---

## Issue: Container Tidak Start

### Check Container Logs

```bash
# Via SSM Session Manager
aws ssm start-session --target <instance-id> --region ap-southeast-1

# Check container
docker ps -a
docker logs golink-shorner --tail 100
```

### Common Errors

1. **Database Connection Failed:**
   - Check `.env` file: `cat /home/ec2-user/.env`
   - Verify Parameter Store: `aws ssm get-parameter --name /golink-shorner/db/host --region ap-southeast-1`
   - Test connection: `psql -h <db-host> -U <db-user> -d <db-name>`

2. **ECR Access Denied:**
   - Check IAM role: `aws sts get-caller-identity`
   - Verify ECR policy: `AmazonEC2ContainerRegistryReadOnly`

3. **Port Already in Use:**
   - Check: `sudo netstat -tulpn | grep 3000`
   - Kill process: `sudo kill -9 <pid>`

---

## Quick Diagnostic Commands

```bash
# 1. Check ASG instances
aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names onjourney-golink-asg \
    --region ap-southeast-1 \
    --query 'AutoScalingGroups[0].Instances[*].[InstanceId,LifecycleState,HealthStatus]' \
    --output table

# 2. Check Target Group health
aws elbv2 describe-target-health \
    --target-group-arn <target-group-arn> \
    --region ap-southeast-1

# 3. Check ALB listeners
aws elbv2 describe-listeners \
    --load-balancer-arn <alb-arn> \
    --region ap-southeast-1

# 4. Check instance console output (via SSM)
aws ssm start-session --target <instance-id> --region ap-southeast-1
# Then: sudo cat /var/log/cloud-init-output.log

# 5. Validate configuration
./scripts/validate-alb-config.sh
```

---

## Next Steps

Jika masalah masih terjadi setelah mengikuti troubleshooting di atas:

1. Check CloudWatch Logs untuk error messages
2. Review ASG activity history
3. Check EC2 instance console output
4. Verify semua konfigurasi sesuai dengan dokumentasi di `docs/AWS_SETUP.md`
