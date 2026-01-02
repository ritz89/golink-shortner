# AWS Setup Guide - golink-shorner

Panduan lengkap untuk setup aplikasi golink-shorner di AWS menggunakan EC2 (ARM/Graviton) dengan CI/CD GitHub Actions.

## 📋 Daftar Isi

1. [Prerequisites](#prerequisites)
2. [Setup AWS Resources](#setup-aws-resources)
   - [Setup ECR](#1-setup-ecr-elastic-container-registry)
   - [Setup RDS PostgreSQL](#2-setup-rds-postgresql-database)
   - [Setup Application Load Balancer](#3-setup-application-load-balancer-alb)
   - [Setup Launch Template](#4-setup-launch-template)
   - [Setup Auto Scaling Group](#5-setup-auto-scaling-group)
   - [Setup Systems Manager Parameter Store](#6-setup-systems-manager-parameter-store-recommended)
   - [Setup Security Groups](#7-setup-security-groups)
   - [Setup IAM Role untuk EC2](#4-setup-iam-role-untuk-ec2)
3. [Setup EC2 Instance (via Auto Scaling Group)](#setup-ec2-instance-via-auto-scaling-group)
4. [Setup ECR (Elastic Container Registry)](#setup-ecr)
5. [Setup GitHub Actions](#setup-github-actions)
6. [Setup Database (RDS PostgreSQL)](#setup-database-rds-postgresql)
7. [Deployment](#deployment)
8. [Monitoring & Maintenance](#monitoring--maintenance)
9. [Troubleshooting](#troubleshooting)
10. [Cost Estimation](#cost-estimation)
11. [Security Best Practices](#security-best-practices)

---

## ⚠️ Important Configuration Notes

**Sebelum memulai, perhatikan konfigurasi berikut yang sudah di-setup:**

- **ECR Repository:** `onjourney-golink-shortner` (bukan `golink-shorner`)
- **RDS Database:**
  - Database name: `onjourney_link` (bukan `link_shorner`)
  - Username: `onjourney` (bukan `postgres`)
  - Endpoint: `rds-onj-primary.c7qw6oy402sj.ap-southeast-1.rds.amazonaws.com`
  - Security Group: `db-security-group` (sg-0a6af115df3e43cdc)
- **ALB:** `onjourney-golink-shortner-alb`
  - Security Group: `alb-security-group` (sg-0ad2cbd7ab9780644)
  - DNS: `onjourney-golink-shortner-alb-1532011075.ap-southeast-1.elb.amazonaws.com`
- **Target Group:** `onjourney-golink-shortner-tg`
  - Port: `80` ✅ (nginx reverse proxy di instance forward ke port 3000)
- **Launch Template:** `onjourney-golink-shortner` (ID: `lt-02dc4a959747d21b5`)
  - Security Group: `sg-083aa1a4be548f2ff`
  - Key Pair: `onjourney-link-keypair`
- **IAM Role:** `EC2RoleForSSM` (sudah memiliki semua policies yang diperlukan)

---

## Prerequisites

Sebelum memulai, pastikan Anda memiliki:

- ✅ AWS Account dengan akses ke:
  - EC2
  - ECR (Elastic Container Registry)
  - RDS (untuk database)
  - IAM (untuk roles dan policies)
- ✅ GitHub repository untuk project ini
- ✅ AWS CLI terinstall di local machine (opsional, untuk testing)
- ✅ Basic knowledge tentang Docker dan AWS

---

## Setup AWS Resources

### 1. Setup ECR (Elastic Container Registry)

ECR digunakan untuk menyimpan Docker images.

#### Via AWS Console:

1. Buka **Amazon ECR** di AWS Console
2. Klik **Create repository**
3. Repository name: `onjourney-golink-shortner`
4. Visibility: **Private**
5. Tag immutability: **Enabled** (recommended)
6. Scan on push: **Enabled** (untuk security scanning)
7. Klik **Create repository**

#### Via AWS CLI:

```bash
aws ecr create-repository \
    --repository-name onjourney-golink-shortner \
    --region ap-southeast-1 \
    --image-scanning-configuration scanOnPush=true \
    --image-tag-mutability MUTABLE
```

**Catat ECR Registry URL:**
```
<account-id>.dkr.ecr.<region>.amazonaws.com/onjourney-golink-shortner
```

---

### 2. Setup RDS PostgreSQL (Database)

#### Via AWS Console:

1. Buka **Amazon RDS** di AWS Console
2. Klik **Create database**
3. Database creation method: **Standard create**
4. Engine: **PostgreSQL**
5. Version: **15.x** atau terbaru
6. Template: **Free tier** (untuk development) atau **Production**
7. DB instance identifier: `rds-onj-primary` (atau sesuai kebutuhan)
8. Master username: `onjourney` ⚠️ **PENTING: Bukan `postgres`**
9. Master password: **Buat password yang kuat** (simpan dengan aman!)
10. DB instance class: **db.t4g.micro** (ARM, cost-effective)
11. Storage: **20 GB** (General Purpose SSD)
12. VPC: Pilih VPC yang sama dengan EC2 (VPC-ONJ: `vpc-07bbbdd4033765409`)
13. Public access: **No** (lebih aman)
14. VPC security group: Buat baru atau gunakan existing (`db-security-group`)
15. Database name: `onjourney_link` ⚠️ **PENTING: Bukan `link_shorner`**
16. Backup: **Enable automated backups** (recommended)
17. Klik **Create database**

**Catat:**
- Endpoint: `rds-onj-primary.c7qw6oy402sj.ap-southeast-1.rds.amazonaws.com`
- Port: `5432`
- Database name: `onjourney_link` ⚠️
- Username: `onjourney` ⚠️ (bukan `postgres`)
- Password: (yang Anda buat - contoh: `R8o3Y3aLQWVb`)
- VPC: `VPC-ONJ` (vpc-07bbbdd4033765409)
- Security Group: `db-security-group` (sg-0a6af115df3e43cdc)

#### Setup Security Group untuk RDS:

1. Buka **EC2 Console** → **Security Groups**
2. Pilih security group yang digunakan RDS
3. **Inbound rules** → **Edit inbound rules**
4. Add rule:
   - Type: **PostgreSQL**
   - Port: **5432**
   - Source: Pilih security group EC2 instance (bukan IP address)
5. Save rules

---

### 3. Setup Application Load Balancer (ALB)

ALB diperlukan untuk load balancing dan health checks untuk Auto Scaling Group.

#### Via AWS Console:

1. Buka **EC2 Console** → **Load Balancers**
2. Klik **Create Load Balancer**
3. Pilih **Application Load Balancer**
4. Name: `onjourney-golink-shortner-alb`
5. Scheme: **Internet-facing**
6. IP address type: **IPv4**
7. VPC: Pilih VPC yang sama dengan RDS
8. Availability Zones: Pilih minimal 2 AZ (untuk high availability)
   - Subnet: `subnet-07c21a6b00297f3c9` (ap-southeast-1a)
   - Subnet: `subnet-09b382f4141ee1399` (ap-southeast-1b)
9. Security groups: Pilih atau buat security group:
   - Security Group Name: `alb-security-group`
   - Security Group ID: `sg-0ad2cbd7ab9780644` (jika sudah ada)
   - Allow HTTP (80) from 0.0.0.0/0
   - Allow HTTPS (443) from 0.0.0.0/0 (jika menggunakan SSL)
   - **Note:** SSH tidak diperlukan untuk ALB security group (hanya untuk EC2)
10. Listeners:
    - Listener 1: HTTP (80) → Forward to target group `onjourney-golink-shortner-tg` (akan di-update ke redirect HTTPS setelah SSL setup)
    - Listener 2: HTTPS (443) → Akan ditambahkan setelah SSL certificate setup (lihat section 3.1)
11. Target group: Akan dibuat di step berikutnya (atau pilih existing `onjourney-golink-shortner-tg`)
12. Klik **Create load balancer**

**⚠️ Important:** 
- Setelah ALB dibuat, pastikan listener HTTP (80) sudah dikonfigurasi untuk forward ke target group `onjourney-golink-shortner-tg`
- **SSL Setup:** Setelah ALB dibuat, lanjutkan ke section 3.1 untuk setup SSL certificate dan HTTPS listener

**Catat:**
- ALB DNS name: `onjourney-golink-shortner-alb-1532011075.ap-southeast-1.elb.amazonaws.com`
- ALB ARN: `arn:aws:elasticloadbalancing:ap-southeast-1:577638371164:loadbalancer/app/onjourney-golink-shortner-alb/2ad555672cd7e3c6`
- Security Group: `alb-security-group` (sg-0ad2cbd7ab9780644)
- VPC: `VPC-ONJ` (vpc-07bbbdd4033765409)

#### Create Target Group:

1. Buka **EC2 Console** → **Target Groups**
2. Klik **Create target group**
3. Target type: **Instances**
4. Name: `onjourney-golink-shortner-tg`
5. Protocol: **HTTP**
6. Port: **80** ✅ **IMPORTANT:** Gunakan port 80 (nginx akan forward ke port 3000)
7. VPC: Pilih VPC yang sama
8. Health checks:
   - Protocol: **HTTP**
   - Path: `/health`
   - Port: **traffic-port** (akan menggunakan 80)
   - **Note:** Nginx reverse proxy di instance akan forward ke aplikasi di port 3000
   - Healthy threshold: **2**
   - Unhealthy threshold: **3**
   - Timeout: **5 seconds**
   - Interval: **30 seconds**
   - Success codes: **200**
9. Register targets: Skip (akan di-register otomatis oleh ASG)
10. Klik **Create target group**

**Catat Target Group ARN** untuk digunakan di Auto Scaling Group.

---

#### 3.1. Setup SSL Certificate and HTTPS Listener (Required for Production)

**Status:** ⚠️ **REQUIRED** - Setup SSL untuk production dengan domain `onjourney.link`

**Why SSL?**
- ✅ Secure HTTPS connection
- ✅ Required for production
- ✅ Better SEO ranking
- ✅ User trust and security

**Method 1: Using Setup Script (Recommended)**

Gunakan script yang sudah disediakan untuk setup SSL secara otomatis:

```bash
# From your local machine (with AWS CLI configured)
cd /path/to/golink-shorner
chmod +x scripts/setup-alb-ssl.sh
./scripts/setup-alb-ssl.sh
```

Script akan:
1. ✅ Request SSL certificate dari ACM untuk `onjourney.link` dan `*.onjourney.link`
2. ✅ Menambahkan HTTPS (443) listener ke ALB
3. ✅ Mengupdate HTTP (80) listener untuk redirect ke HTTPS
4. ✅ Memberikan instruksi untuk setup CNAME di DNS provider

**Method 2: Manual Setup via AWS Console**

**Step 1: Request SSL Certificate from ACM**

1. Buka **AWS Certificate Manager (ACM)** → **Certificates**
2. Klik **Request a certificate**
3. Request a public certificate
4. Domain names:
   - `onjourney.link`
   - `*.onjourney.link` (wildcard untuk subdomain)
5. Validation method: **DNS validation** (recommended)
6. Klik **Request**
7. **⚠️ IMPORTANT:** Copy CNAME records yang diberikan dan tambahkan ke DNS provider Anda
8. Tunggu sampai status berubah menjadi **Issued** (biasanya 5-15 menit setelah DNS records ditambahkan)

**Step 2: Add HTTPS Listener to ALB**

1. Buka **EC2 Console** → **Load Balancers**
2. Pilih ALB: `onjourney-golink-shortner-alb`
3. Klik tab **Listeners**
4. Klik **Add listener**
5. Protocol: **HTTPS**
6. Port: **443**
7. Default action: **Forward to** → Pilih target group: `onjourney-golink-shortner-tg`
8. Certificate: Pilih certificate yang sudah di-request (untuk `onjourney.link`)
9. Security policy: **ELBSecurityPolicy-TLS-1-2-2017-01** (default, recommended)
10. Klik **Add**

**Step 3: Update HTTP Listener to Redirect to HTTPS**

1. Di tab **Listeners**, klik **Edit** pada HTTP (80) listener
2. Change default action dari **Forward to** menjadi **Redirect to**
3. Protocol: **HTTPS**
4. Port: **443**
5. Status code: **301 - Permanently moved**
6. Klik **Save changes**

**Step 4: Setup CNAME Record in DNS Provider**

1. Get ALB DNS name:
   ```bash
   aws elbv2 describe-load-balancers \
       --names onjourney-golink-shortner-alb \
       --region ap-southeast-1 \
       --query 'LoadBalancers[0].DNSName' \
       --output text
   ```

2. Di DNS provider untuk domain `onjourney.link`, tambahkan CNAME record:
   - **Type:** CNAME
   - **Name:** `@` (atau kosongkan untuk root domain)
   - **Value:** `<ALB_DNS_NAME>` (dari step 1)
   - **TTL:** 300 (atau sesuai preferensi)

3. (Optional) Untuk www subdomain:
   - **Type:** CNAME
   - **Name:** `www`
   - **Value:** `<ALB_DNS_NAME>`
   - **TTL:** 300

4. Tunggu DNS propagation (biasanya 5-15 menit)

**Step 5: Verify SSL Setup**

```bash
# Test HTTPS connection
curl -I https://onjourney.link/health

# Should return HTTP 200 OK
```

**✅ Expected Result:**
- ✅ HTTPS (443) listener aktif di ALB
- ✅ HTTP (80) redirect ke HTTPS (301)
- ✅ SSL certificate valid untuk `onjourney.link`
- ✅ Domain `onjourney.link` resolve ke ALB DNS
- ✅ HTTPS connection berhasil

**⚠️ Important Notes:**
- SSL certificate harus di-request di region yang sama dengan ALB (`ap-southeast-1`)
- Certificate validation memerlukan CNAME records di DNS provider
- DNS propagation bisa memakan waktu 5-15 menit
- Pastikan security group ALB mengizinkan inbound HTTPS (443) dari 0.0.0.0/0

---

### 4. Setup Launch Template

Launch Template digunakan oleh Auto Scaling Group untuk launch instances baru.

#### Via AWS Console:

1. Buka **EC2 Console** → **Launch Templates**
2. Klik **Create launch template**
3. Name: `onjourney-golink-shortner`
4. Template version description: `Initial version for onjourney-golink-shortner`
5. AMI: **Amazon Linux 2023** (ARM64)
   - Pilih: `Amazon Linux 2023 AMI 2023.x.x arm64`
6. Instance type: **t4g.small**
7. Key pair: Pilih key pair (opsional, karena kita menggunakan SSM untuk access)
8. Network settings:
   - VPC: Pilih VPC yang sama
   - Subnet: Pilih subnet (akan di-override oleh ASG)
   - Security groups: Pilih security group yang sudah dibuat:
     - **Security Group ID**: `sg-083aa1a4be548f2ff`
     - **Inbound Rules** (perlu verify):
       - HTTP (80): From ALB security group (`sg-0ad2cbd7ab9780644`) ✅ **REQUIRED** (nginx listens on port 80)
       - **Note:** SSH (22) tidak diperlukan karena menggunakan SSM untuk access
     - **Outbound Rules**:
       - All traffic: 0.0.0.0/0
9. Storage: **20 GB** (gp3)
10. **Tags (IMPORTANT untuk identifikasi instances):**
    - Klik **Add tag**
    - Key: `Name`
    - Value: `golink-shortner` (atau `onjourney-golink-shortner`)
    - **Note:** Tag ini akan otomatis di-apply ke semua instances yang di-launch dari template ini
11. Advanced details:
    - IAM instance profile: Pilih `EC2RoleForSSM` (sudah memiliki ECR access dan Parameter Store access)
    - User data: (akan dibuat di step berikutnya)
12. Klik **Create launch template**

**⚠️ Important:** Pastikan menambahkan tag `Name` di Launch Template agar instances mudah diidentifikasi di EC2 console. Lihat `docs/ADD_INSTANCE_NAME_TAG.md` untuk detail lebih lanjut.

#### User Data Script untuk Launch Template:

**⚠️ CRITICAL:** User Data script **WAJIB** diisi untuk memastikan instance ter-setup dengan benar saat pertama kali di-launch. 

**Kenapa User Data Penting:**
- ✅ Berjalan **otomatis** saat instance pertama kali di-launch
- ✅ Memastikan semua dependencies terinstall **sebelum** instance digunakan
- ✅ Instance siap untuk deployment tanpa setup manual
- ✅ Konsisten untuk semua instance baru dari ASG

**Opsi 1: Download dan Run setup-ec2.sh dari S3 (Recommended)**

Copy script berikut ke **User data** field di Launch Template:

```bash
#!/bin/bash
# User data script untuk Auto Scaling Group
# Download dan run setup-ec2.sh dari S3 untuk memastikan semua terinstall

set -e

# Wait for instance metadata service to be ready
until curl -s http://169.254.169.254/latest/meta-data/instance-id > /dev/null; do
    sleep 1
done

# Create directories
mkdir -p /home/ec2-user/scripts
mkdir -p /home/ec2-user/app

# Download setup script from S3
echo "Downloading setup-ec2.sh from S3..."
aws s3 cp s3://onjourney-asset-bucket/scripts/setup-ec2.sh /home/ec2-user/scripts/setup-ec2.sh || {
    echo "⚠️  Failed to download setup-ec2.sh from S3"
    echo "   Will continue with inline setup..."
}

# Make executable and run
if [ -f /home/ec2-user/scripts/setup-ec2.sh ]; then
    chmod +x /home/ec2-user/scripts/setup-ec2.sh
    echo "Running setup-ec2.sh..."
    /home/ec2-user/scripts/setup-ec2.sh
else
    echo "Running inline setup (fallback)..."
    # Fallback: Run setup inline if S3 download fails
    yum update -y
    yum install -y docker jq nginx
    systemctl start docker
    systemctl enable docker
    usermod -aG docker ec2-user
    
    # Install AWS CLI v2 if not present
    if ! command -v aws &> /dev/null; then
        curl "https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip" -o /tmp/awscliv2.zip
        unzip /tmp/awscliv2.zip -d /tmp
        /tmp/aws/install
        rm -rf /tmp/aws /tmp/awscliv2.zip
    fi
    
    # Setup .env from Parameter Store
    if aws ssm get-parameter --name /golink-shorner/db/host --region ap-southeast-1 --query 'Parameter.Value' --output text 2>/dev/null > /dev/null; then
        DB_HOST=$(aws ssm get-parameter --name /golink-shorner/db/host --region ap-southeast-1 --query 'Parameter.Value' --output text 2>/dev/null || echo "")
        DB_PORT=$(aws ssm get-parameter --name /golink-shorner/db/port --region ap-southeast-1 --query 'Parameter.Value' --output text 2>/dev/null || echo "5432")
        DB_USER=$(aws ssm get-parameter --name /golink-shorner/db/user --region ap-southeast-1 --query 'Parameter.Value' --output text 2>/dev/null || echo "onjourney")
        DB_PASSWORD=$(aws ssm get-parameter --name /golink-shorner/db/password --with-decryption --region ap-southeast-1 --query 'Parameter.Value' --output text 2>/dev/null || echo "")
        DB_NAME=$(aws ssm get-parameter --name /golink-shorner/db/name --region ap-southeast-1 --query 'Parameter.Value' --output text 2>/dev/null || echo "onjourney_link")
        
        cat > /home/ec2-user/.env << EOF
DB_HOST=${DB_HOST}
DB_PORT=${DB_PORT}
DB_USER=${DB_USER}
DB_PASSWORD=${DB_PASSWORD}
DB_NAME=${DB_NAME}
DB_SSLMODE=require
EOF
        chmod 600 /home/ec2-user/.env
    fi
    
    # Configure nginx
    tee /etc/nginx/conf.d/golink-shorner.conf > /dev/null <<'NGINXEOF'
upstream golink_shorner {
    server localhost:3000;
    keepalive 32;
}
server {
    listen 80;
    server_name _;
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
    nginx -t
    systemctl enable nginx
    systemctl start nginx
fi

# Download deploy script from S3
echo "Downloading deploy.sh from S3..."
aws s3 cp s3://onjourney-asset-bucket/scripts/deploy.sh /home/ec2-user/scripts/deploy.sh 2>/dev/null && \
    chmod +x /home/ec2-user/scripts/deploy.sh || \
    echo "⚠️  Failed to download deploy.sh (will be downloaded during deployment)"

echo "User data script completed successfully"
```

**Opsi 2: Include Setup Langsung di User Data (Alternative)**

Jika ingin semua setup langsung di User Data tanpa download dari S3:

# Note: curl-minimal is already installed on Amazon Linux 2023
# No need to install curl separately - curl-minimal is sufficient for our needs
# If you need full curl features, use: yum install -y curl --allowerasing

# Create directories
mkdir -p /home/ec2-user/app
mkdir -p /home/ec2-user/scripts

# Create .env file - Try to retrieve from Parameter Store first, fallback to template
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
DB_TIMEZONE=Asia/Jakarta
EOF
    
    if [ -z "$DB_HOST" ] || [ -z "$DB_PASSWORD" ]; then
        echo "⚠️  Warning: Some parameters missing from Parameter Store. Please verify."
    else
        echo "✅ Successfully retrieved credentials from Parameter Store"
    fi
else
    # Parameter Store not configured - fail with clear error message
    echo "❌ ERROR: Parameter Store not configured!"
    echo "Please setup Parameter Store before launching instances."
    echo "See section 6 for setup instructions."
    # Exit with error - instance should not start without credentials
    exit 1
fi

chmod 600 /home/ec2-user/.env

# Configure Docker log rotation
mkdir -p /etc/docker
cat > /etc/docker/daemon.json << 'DOCKEREOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
DOCKEREOF

systemctl restart docker

# Setup nginx reverse proxy (port 80 → 3000)
# This allows Target Group to use port 80 while application runs on port 3000
cat > /etc/nginx/conf.d/golink-shorner.conf << 'NGINXEOF'
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

# Test and start nginx
nginx -t
systemctl enable nginx
systemctl start nginx

# Download deploy script dari S3 (setelah di-upload dari local)
aws s3 cp s3://onjourney-asset-bucket/scripts/deploy.sh /home/ec2-user/scripts/deploy.sh
chmod +x /home/ec2-user/scripts/deploy.sh

echo "User data script completed"
```

**Note:** Untuk production, lebih baik simpan database credentials di **AWS Systems Manager Parameter Store** dan retrieve via user data script.

---

### 5. Setup Auto Scaling Group

#### Via AWS Console:

1. Buka **EC2 Console** → **Auto Scaling Groups**
2. Klik **Create Auto Scaling group**
3. Name: `golink-shorner-asg` (atau sesuai kebutuhan)
4. Launch template: Pilih `onjourney-golink-shortner` (Launch Template ID: `lt-02dc4a959747d21b5`)
5. Version: **Latest**
6. VPC: Pilih VPC yang sama
7. Availability Zones and subnets: Pilih minimal 2 subnets di different AZ
8. Load balancing:
   - Attach to an existing load balancer: **Yes**
   - Choose a target group: Pilih `onjourney-golink-shortner-tg`
   - Health check type: **ELB** (recommended untuk ALB)
   - Health check grace period: **300 seconds** (5 menit)
9. Group size:
   - Desired capacity: **1**
   - Minimum capacity: **1**
   - Maximum capacity: **2**
10. Scaling policies (optional):
    - Add scaling policy jika ingin auto-scale berdasarkan metrics
    - Contoh: Scale up jika CPU > 70% untuk 2 minutes
    - Scale down jika CPU < 30% untuk 5 minutes
11. Add notifications (optional): Setup SNS untuk notifications
12. **Tags (IMPORTANT untuk identifikasi instances):**
    - Klik **Add tag**
    - Key: `Name`
    - Value: `golink-shortner` (atau `onjourney-golink-shortner`)
    - **Tag new instances:** ✅ (centang ini agar tag di-apply ke instances baru)
    - **Note:** Tag ini akan otomatis di-apply ke semua instances yang di-launch oleh ASG
    - **Additional tags (optional):**
      - Key: `Environment`, Value: `production`
      - Key: `Project`, Value: `golink-shortner`
      - Key: `ManagedBy`, Value: `AutoScalingGroup`
13. Klik **Create Auto Scaling group**

**⚠️ Important:** 
- Pastikan menambahkan tag `Name` di ASG dengan option "Tag new instances" di-check
- Tag ini akan membantu identifikasi instances di EC2 console
- Jika tag sudah ada di Launch Template, tag di ASG akan override tag di Launch Template
- Lihat `docs/ADD_INSTANCE_NAME_TAG.md` untuk detail lebih lanjut dan troubleshooting

#### Via AWS CLI:

```bash
# Create Auto Scaling Group
aws autoscaling create-auto-scaling-group \
    --auto-scaling-group-name golink-shorner-asg \
    --launch-template LaunchTemplateId=lt-02dc4a959747d21b5,Version='$Latest' \
    --min-size 1 \
    --max-size 2 \
    --desired-capacity 1 \
    --vpc-zone-identifier "subnet-0552727603c822147,subnet-0df928651bfbae02b" \
    --target-group-arns "arn:aws:elasticloadbalancing:ap-southeast-1:577638371164:targetgroup/onjourney-golink-shortner-tg/5374847abd875d01" \
    --health-check-type ELB \
    --health-check-grace-period 300
```

---

### 6. Setup Systems Manager Parameter Store (Recommended) ⚠️ ACTION REQUIRED

**Status:** ⏳ **PENDING** - Perlu di-setup sebelum deployment

**Why Parameter Store?**
- ✅ Centralized credential management
- ✅ Secure storage (encrypted with KMS)
- ✅ Automatic retrieval by new instances
- ✅ No hardcoded credentials in user data scripts
- ✅ Easy to update (update once, all new instances get update)

#### 6.1. Create Parameters via AWS Console:

1. Buka **Systems Manager** → **Parameter Store**
2. Klik **Create parameter** untuk setiap parameter berikut:

**Parameter 1: Database Host**
- **Name:** `/golink-shorner/db/host`
- **Type:** `String`
- **Value:** `rds-onj-primary.c7qw6oy402sj.ap-southeast-1.rds.amazonaws.com`
- **Description:** `RDS database endpoint for golink-shorner`

**Parameter 2: Database Port**
- **Name:** `/golink-shorner/db/port`
- **Type:** `String`
- **Value:** `5432`
- **Description:** `PostgreSQL port`

**Parameter 3: Database User**
- **Name:** `/golink-shorner/db/user`
- **Type:** `String`
- **Value:** `onjourney` ⚠️ (bukan `postgres`)
- **Description:** `Database username`

**Parameter 4: Database Password** (⚠️ **IMPORTANT: Use SecureString**)
- **Name:** `/golink-shorner/db/password`
- **Type:** `SecureString` ⚠️ **PENTING: Pilih SecureString, bukan String**
- **Value:** `R8o3Y3aLQWVb` (password database Anda)
- **KMS key:** `alias/aws/ssm` (default) atau custom KMS key
- **Description:** `Database password (encrypted)`

**Parameter 5: Database Name**
- **Name:** `/golink-shorner/db/name`
- **Type:** `String`
- **Value:** `onjourney_link` ⚠️ (bukan `link_shorner`)
- **Description:** `Database name`

#### 6.2. Create Parameters via Script (Recommended - Secure):

**✅ Easiest & Most Secure Method:** Gunakan script yang sudah disediakan:

```bash
# From your local machine (with AWS CLI configured)
cd /path/to/golink-shorner
chmod +x scripts/setup-parameter-store.sh
./scripts/setup-parameter-store.sh
```

**Benefits:**
- ✅ Password di-input secara secure (masked, tidak muncul di terminal)
- ✅ Tidak ada credentials di command history
- ✅ Automatic verification setelah setup
- ✅ Handles all parameters in one go

Script akan prompt untuk:
- Database Host (default: `rds-onj-primary.c7qw6oy402sj.ap-southeast-1.rds.amazonaws.com`)
- Database Port (default: `5432`)
- Database User (default: `onjourney`)
- Database Password (masked input - **tidak akan muncul di terminal**)
- Database Name (default: `onjourney_link`)

#### 6.2.1. Create Parameters via AWS CLI (Manual):

Jika lebih suka manual, gunakan commands berikut:

```bash
# Set region
export AWS_REGION="ap-southeast-1"

# Create database host parameter
aws ssm put-parameter \
    --name "/golink-shorner/db/host" \
    --type "String" \
    --value "rds-onj-primary.c7qw6oy402sj.ap-southeast-1.rds.amazonaws.com" \
    --description "RDS database endpoint for golink-shorner" \
    --region $AWS_REGION

# Create database port parameter
aws ssm put-parameter \
    --name "/golink-shorner/db/port" \
    --type "String" \
    --value "5432" \
    --description "PostgreSQL port" \
    --region $AWS_REGION

# Create database user parameter
aws ssm put-parameter \
    --name "/golink-shorner/db/user" \
    --type "String" \
    --value "onjourney" \
    --description "Database username" \
    --region $AWS_REGION

# Create database password parameter (SecureString) ⚠️ IMPORTANT
# ⚠️ SECURITY: Use read -sp to prompt password securely (masked input)
read -sp "Enter database password: " DB_PASSWORD
echo ""
aws ssm put-parameter \
    --name "/golink-shorner/db/password" \
    --type "SecureString" \
    --value "$DB_PASSWORD" \
    --description "Database password (encrypted)" \
    --region $AWS_REGION

# Create database name parameter
aws ssm put-parameter \
    --name "/golink-shorner/db/name" \
    --type "String" \
    --value "onjourney_link" \
    --description "Database name" \
    --region $AWS_REGION
```

**⚠️ Security Best Practice:**
- ❌ **JANGAN** hardcode password di command line (akan muncul di shell history)
- ✅ **GUNAKAN** `read -sp` untuk prompt password (masked input)
- ✅ **ATAU** gunakan script `setup-parameter-store.sh` yang sudah handle ini dengan aman
- ✅ Password akan disimpan sebagai `SecureString` (encrypted dengan KMS)

#### 6.3. Verify Parameters:

```bash
# List all parameters
aws ssm describe-parameters \
    --filters "Key=Name,Values=/golink-shorner/db/" \
    --region ap-southeast-1

# Get a parameter value (non-secure)
aws ssm get-parameter \
    --name "/golink-shorner/db/host" \
    --region ap-southeast-1 \
    --query 'Parameter.Value' \
    --output text

# Get secure parameter (password)
aws ssm get-parameter \
    --name "/golink-shorner/db/password" \
    --with-decryption \
    --region ap-southeast-1 \
    --query 'Parameter.Value' \
    --output text
```

#### 6.4. IAM Permission untuk Parameter Store:

**✅ Good News:** IAM role `EC2RoleForSSM` sudah memiliki policy `SecretsManagerReadWrite` yang memberikan akses ke Parameter Store.

**Verify IAM Role:**
- Role: `EC2RoleForSSM`
- Policy: `SecretsManagerReadWrite` ✅ (sudah attached)
- Permissions: `ssm:GetParameter`, `ssm:GetParameters`, `ssm:GetParametersByPath`

**Jika perlu menambahkan permission manual:**

Tambahkan policy berikut ke IAM role EC2 (`EC2RoleForSSM`):

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": [
      "ssm:GetParameter",
      "ssm:GetParameters",
      "ssm:GetParametersByPath"
    ],
    "Resource": "arn:aws:ssm:ap-southeast-1:577638371164:parameter/golink-shorner/*"
  }]
}
```

**Note:** Policy `SecretsManagerReadWrite` sudah memberikan akses ini, jadi tidak perlu menambahkan manual jika role sudah memiliki policy tersebut.

#### 6.5. How It Works:

Setelah Parameter Store di-setup:

1. **User Data Script** (di Launch Template) akan otomatis retrieve credentials dari Parameter Store saat instance pertama kali di-launch
2. **Setup Script** (`setup-ec2.sh`) juga akan retrieve dari Parameter Store jika tersedia
3. File `.env` akan otomatis ter-populate dengan credentials yang benar
4. Instance baru yang di-launch oleh ASG akan otomatis memiliki `.env` file yang lengkap

**✅ Benefits:**
- ✅ Credentials tidak hardcoded di user data script
- ✅ Centralized management - update sekali, semua instance baru akan dapat update
- ✅ Secure - password disimpan sebagai SecureString (encrypted)
- ✅ Audit trail - semua akses ke Parameter Store tercatat di CloudTrail

**⚠️ Important:**
- Pastikan Parameter Store di-setup **SEBELUM** instance baru di-launch
- Atau setup manual `.env` file di instance yang sudah running
- Password harus menggunakan type `SecureString` (bukan `String`)

**✅ User Data Script & Setup Script:**
- User data script di Launch Template sudah di-update untuk retrieve dari Parameter Store (lihat section 4.1)
- Setup script (`scripts/setup-ec2.sh`) juga sudah di-update untuk retrieve dari Parameter Store
- Jika Parameter Store tidak tersedia, script akan fallback ke hardcoded values (untuk development/testing)

---

### 7. Setup Security Groups

#### ALB Security Group (`alb-security-group`):

**Security Group ID:** `sg-0ad2cbd7ab9780644`

**Inbound:**
- HTTP (80): 0.0.0.0/0 ✅ **REQUIRED** (untuk redirect ke HTTPS)
- HTTPS (443): 0.0.0.0/0 ✅ **REQUIRED** (untuk SSL/HTTPS)

**Outbound:**
- All traffic: 0.0.0.0/0

#### EC2 Security Group:

**Security Group ID:** `sg-083aa1a4be548f2ff` (dari Launch Template)

**Inbound:**
- HTTP (80): From ALB security group (source: `sg-0ad2cbd7ab9780644`) ✅ **REQUIRED** (nginx listens on port 80)
- **Note:** SSH (22) tidak diperlukan karena menggunakan SSM untuk access (lebih aman)

**Outbound:**
- All traffic: 0.0.0.0/0

#### RDS Security Group (`db-security-group`):

**Security Group ID:** `sg-0a6af115df3e43cdc`

**Inbound:**
- PostgreSQL (5432): From EC2 security group (`sg-083aa1a4be548f2ff`) ⚠️ **ACTION REQUIRED**

---

### 4. Setup IAM Role untuk EC2

EC2 instance perlu akses ke ECR untuk pull Docker images dan Parameter Store untuk database credentials.

#### Existing IAM Role: `EC2RoleForSSM`

**Role sudah tersedia dengan semua policies yang diperlukan:**

- **IAM Role ARN:** `arn:aws:iam::577638371164:role/EC2RoleForSSM`
- **Instance Profile ARN:** `arn:aws:iam::577638371164:instance-profile/EC2RoleForSSM`
- **Creation Date:** August 27, 2025, 16:51 (UTC+08:00)

**Policies Attached (9 managed policies):**
- ✅ `AmazonEC2ContainerRegistryReadOnly` - ECR read access
- ✅ `AmazonEC2RoleforAWSCodeDeploy` - CodeDeploy support
- ✅ `AmazonSSMManagedInstanceCore` - SSM access
- ✅ `AWSCodeDeployRole` - CodeDeploy role
- ✅ `AWSXRayDaemonWriteAccess` - X-Ray daemon access
- ✅ `AWSXrayFullAccess` - X-Ray full access
- ✅ `CloudWatchAgentServerPolicy` - CloudWatch monitoring
- ✅ `codepipeline-artifact-role` - CodePipeline artifacts (Customer inline)
- ✅ `SecretsManagerReadWrite` - Parameter Store / Secrets Manager access

#### Attach Role ke Launch Template:

**Via AWS Console:**
1. Buka **EC2 Console** → **Launch Templates**
2. Pilih Launch Template `onjourney-golink-shortner` (ID: `lt-02dc4a959747d21b5`)
3. Klik **Actions** → **Modify template (Create new version)**
4. Di bagian **IAM instance profile**, pilih `EC2RoleForSSM`
5. Klik **Create template version**

**Note:** Role ini sudah memiliki semua permissions yang diperlukan, termasuk ECR access dan Parameter Store access.

---

## Setup EC2 Instance (via Auto Scaling Group)

Dengan Auto Scaling Group, instances akan di-launch otomatis. Setup manual hanya diperlukan untuk initial configuration atau troubleshooting.

### 1. Connect ke EC2 Instance

Untuk connect ke instance di ASG:

```bash
# List instances di ASG
aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names golink-shorner-asg \
    --query 'AutoScalingGroups[0].Instances[*].[InstanceId,HealthStatus,LifecycleState]' \
    --output table

# Get instance IP
aws ec2 describe-instances \
    --instance-ids <instance-id> \
    --query 'Reservations[0].Instances[0].PublicIpAddress' \
    --output text

# Via AWS Systems Manager Session Manager (Recommended - lebih aman, tidak perlu SSH key)
aws ssm start-session --target <instance-id>

# Atau via SSH (jika SSH port masih dibuka - tidak disarankan untuk production)
# ssh -i your-key.pem ec2-user@<ec2-public-ip>
```

### 2. Initial Setup (First Instance)

#### 2.1. Upload Scripts ke S3 (Dari Local Machine)

Karena repository private, upload scripts ke S3 terlebih dahulu:

```bash
# Dari local machine, upload scripts ke S3
cd /path/to/golink-shorner

# Make upload script executable
chmod +x scripts/upload-to-s3.sh

# Upload semua scripts ke S3 bucket
./scripts/upload-to-s3.sh
```

**Atau upload manual:**

```bash
# Upload setup script
aws s3 cp scripts/setup-ec2.sh \
    s3://onjourney-asset-bucket/scripts/setup-ec2.sh \
    --region ap-southeast-1

# Upload deploy script
aws s3 cp scripts/deploy.sh \
    s3://onjourney-asset-bucket/scripts/deploy.sh \
    --region ap-southeast-1

# Upload deploy-asg script
aws s3 cp scripts/deploy-asg.sh \
    s3://onjourney-asset-bucket/scripts/deploy-asg.sh \
    --region ap-southeast-1
```

#### 2.2. Download dan Run Setup Script (Via SSM)

Setelah scripts di-upload ke S3, connect ke instance via SSM dan download:

```bash
# Connect ke instance via SSM
aws ssm start-session --target <instance-id>

# Setelah masuk ke instance, download setup script dari S3
aws s3 cp s3://onjourney-asset-bucket/scripts/setup-ec2.sh /tmp/setup-ec2.sh

# Make executable
chmod +x /tmp/setup-ec2.sh

# Run setup
/tmp/setup-ec2.sh
```

**Atau manual setup:**

```bash
# Update system
sudo yum update -y

# Install Docker
sudo yum install -y docker
sudo systemctl start docker
sudo systemctl enable docker
sudo usermod -aG docker ec2-user

# Install AWS CLI (if needed)
curl "https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# Logout and login again for Docker group to take effect
```

### 3. Configure Environment Variables

Edit file `.env`:

```bash
nano /home/ec2-user/.env
```

Isi dengan konfigurasi database:

```env
# Database Configuration
DB_HOST=rds-onj-primary.c7qw6oy402sj.ap-southeast-1.rds.amazonaws.com
DB_PORT=5432
DB_USER=onjourney
DB_PASSWORD=R8o3Y3aLQWVb
DB_NAME=onjourney_link
DB_SSLMODE=require
DB_TIMEZONE=Asia/Jakarta
```

Set permissions:

```bash
chmod 600 /home/ec2-user/.env
```

### 4. Copy Deploy Script

**Download dari S3 (setelah di-upload dari local):**

```bash
# Create scripts directory
mkdir -p /home/ec2-user/scripts

# Download deploy script dari S3
aws s3 cp s3://onjourney-asset-bucket/scripts/deploy.sh /home/ec2-user/scripts/deploy.sh

# Make executable
chmod +x /home/ec2-user/scripts/deploy.sh
```

**Note:** Pastikan scripts sudah di-upload ke S3 terlebih dahulu menggunakan `scripts/upload-to-s3.sh` dari local machine.

### 5. Test ECR Access

```bash
# Get ECR registry URL
ECR_REGISTRY="<account-id>.dkr.ecr.ap-southeast-1.amazonaws.com"

# Login to ECR
aws ecr get-login-password --region ap-southeast-1 | \
    docker login --username AWS --password-stdin $ECR_REGISTRY

# Test pull (after first push)
docker pull $ECR_REGISTRY/onjourney-golink-shortner:latest
```

---

## Setup GitHub Actions

### 1. Setup GitHub Secrets

**⚠️ Important:** Secrets bisa dikonfigurasi di 2 tempat. **Pilih salah satu:**

#### Option 1: Repository-level Secrets (Simple setup)

Di GitHub repository, buka **Settings** → **Secrets and variables** → **Actions** → **Repository secrets**

**Note:** Jika menggunakan Repository secrets, workflow tidak perlu `environment:` di job level (workflow sudah dikonfigurasi untuk support ini).

#### Option 2: Environment-level Secrets (Recommended untuk production dengan protection rules)

Di GitHub repository, buka **Settings** → **Environments** → **production** (atau create environment baru) → **Environment secrets**

**⚠️ Important:** Jika menggunakan Environment secrets, workflow **HARUS** menggunakan `environment: production` di job level. Workflow sudah dikonfigurasi dengan `environment: production` di job `build-and-push`.

**Secrets yang perlu dikonfigurasi (sama untuk kedua opsi):**

| Secret Name | Value | Description |
|------------|-------|-------------|
| `AWS_ACCESS_KEY_ID` | Your AWS Access Key | Untuk akses AWS dari GitHub Actions |
| `AWS_SECRET_ACCESS_KEY` | Your AWS Secret Key | Untuk akses AWS dari GitHub Actions |
| `ASG_NAME` | `onjourney-golink-asg` | Auto Scaling Group name (untuk multi-instance deployment) |
| `ALB_DNS` | `onjourney-golink-shortner-alb-1532011075.ap-southeast-1.elb.amazonaws.com` | ALB DNS name (opsional, untuk health check verification) |

**Note:** 
- ✅ **Tidak perlu SSH secrets** karena kita menggunakan **AWS Systems Manager (SSM)** untuk akses ke instances
- ✅ **Tidak perlu `EC2_HOST`** karena deployment dilakukan via ASG, bukan single instance
- ✅ Instances di ASG sudah memiliki IAM role `EC2RoleForSSM` yang memungkinkan akses via SSM
- ⚠️ **Jika secrets dikonfigurasi di Environment, pastikan workflow menggunakan `environment: production`** (sudah dikonfigurasi)

#### Generate AWS Access Keys:

1. Buka **IAM Console** → **Users**
2. Create user atau pilih existing user (misalnya: `github-actions-user`)
3. Attach custom policies yang sudah dibuat:
   - `github-actions-deploy-prod` (Customer managed policy)
   - Atau attach policies berikut jika belum ada custom policy:
     - `AmazonEC2ContainerRegistryFullAccess` (untuk push ke ECR)
     - `AmazonEC2ReadOnlyAccess` (untuk query ASG instances dan EC2 details)
     - Custom policy untuk SSM (lihat contoh di bawah)

**Custom Policy (sudah dibuat sebagai `github-actions-deploy-prod`):**

Policy yang sudah di-update dengan semua permissions yang diperlukan:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ECRLoginAndPushPull",
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload",
        "ecr:PutImage",
        "autoscaling:DescribeAutoScalingGroups",
        "autoscaling:DescribeAutoScalingInstances",
        "ec2:DescribeInstances",
        "ec2:DescribeInstanceStatus"
      ],
      "Resource": "*"
    },
    {
      "Sid": "SSMSendCommandPermissions",
      "Effect": "Allow",
      "Action": [
        "ssm:SendCommand",
        "ssm:ListCommands",
        "ssm:ListCommandInvocations",
        "ssm:GetCommandInvocation"
      ],
      "Resource": [
        "arn:aws:ec2:ap-southeast-1:577638371164:instance/*",
        "arn:aws:ssm:ap-southeast-1::document/AWS-RunShellScript",
        "arn:aws:ssm:ap-southeast-1:577638371164:command/*"
      ]
    }
  ]
}
```

**✅ Policy sudah lengkap dengan:**
- ✅ ECR permissions (login, push, pull)
- ✅ ASG permissions (DescribeAutoScalingGroups, DescribeAutoScalingInstances)
- ✅ EC2 permissions (DescribeInstances, DescribeInstanceStatus)
- ✅ SSM permissions (SendCommand, ListCommands, ListCommandInvocations, GetCommandInvocation)

**Tambahkan permissions berikut ke policy atau attach additional policy:**

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ASGAndEC2ReadPermissions",
      "Effect": "Allow",
      "Action": [
        "autoscaling:DescribeAutoScalingGroups",
        "autoscaling:DescribeAutoScalingInstances",
        "ec2:DescribeInstances",
        "ec2:DescribeInstanceStatus"
      ],
      "Resource": "*"
    }
  ]
}
```

4. **Security credentials** → **Create access key**
5. Copy Access Key ID dan Secret Access Key
6. **Simpan dengan aman!** Secret key hanya ditampilkan sekali

**⚠️ Important:** Policy yang Anda tunjukkan hanya memiliki satu statement. **Pastikan SSM permissions statement juga ditambahkan:**

Policy lengkap harus memiliki **2 statements**:

1. **Statement 1:** ECR + ASG + EC2 permissions (sudah ada ✅)
2. **Statement 2:** SSM permissions (perlu ditambahkan ⚠️)

#### Cara Menambahkan SSM Permissions Statement:

**Via AWS Console:**

1. Buka **IAM Console** → **Policies**
2. Cari policy `github-actions-deploy-prod`
3. Klik policy name untuk membuka detail
4. Klik tab **JSON**
5. Klik **Edit**
6. Tambahkan statement kedua setelah statement pertama (setelah closing brace `}` dari statement pertama, tambahkan koma `,` lalu statement baru):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ECRLoginAndPushPull",
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload",
        "ecr:PutImage",
        "autoscaling:DescribeAutoScalingGroups",
        "autoscaling:DescribeAutoScalingInstances",
        "ec2:DescribeInstances",
        "ec2:DescribeInstanceStatus"
      ],
      "Resource": "*"
    },
    {
      "Sid": "SSMSendCommandPermissions",
      "Effect": "Allow",
      "Action": [
        "ssm:SendCommand",
        "ssm:ListCommands",
        "ssm:ListCommandInvocations",
        "ssm:GetCommandInvocation"
      ],
      "Resource": [
        "arn:aws:ec2:ap-southeast-1:577638371164:instance/*",
        "arn:aws:ssm:ap-southeast-1::document/AWS-RunShellScript",
        "arn:aws:ssm:ap-southeast-1:577638371164:command/*"
      ]
    }
  ]
}
```

7. Klik **Next** → **Save changes**

**Via AWS CLI:**

```bash
# Download current policy
aws iam get-policy-version \
  --policy-arn arn:aws:iam::577638371164:policy/github-actions-deploy-prod \
  --version-id v1 \
  --query 'PolicyVersion.Document' > current-policy.json

# Edit file untuk menambahkan SSM statement (tambahkan koma dan statement baru)
# ... edit current-policy.json ...

# Create new policy version
aws iam create-policy-version \
  --policy-arn arn:aws:iam::577638371164:policy/github-actions-deploy-prod \
  --policy-document file://current-policy.json \
  --set-as-default
```

**Note:** 
- ✅ **Tidak perlu SSH key** karena kita menggunakan **AWS Systems Manager (SSM)** untuk deployment
- ✅ Instances di ASG sudah memiliki IAM role `EC2RoleForSSM` yang memungkinkan SSM access
- ✅ GitHub Actions akan menggunakan SSM `SendCommand` untuk menjalankan deployment script di instances
- ✅ Policy `github-actions-deploy-prod` sudah di-update dengan ASG dan EC2 permissions
- ⚠️ **Pastikan SSM permissions statement juga ditambahkan** untuk deployment via SSM bisa berjalan

### 2. GitHub Actions Workflow

Workflow file sudah ada di `.github/workflows/deploy.yml`. Pastikan:

- ✅ Branch trigger: `main` (sesuaikan jika berbeda)
- ✅ AWS region: `ap-southeast-1` (sesuaikan dengan region Anda)
- ✅ ECR repository name: `onjourney-golink-shortner`

### 3. Test Workflow

1. Push code ke branch `main`
2. Buka **Actions** tab di GitHub
3. Monitor workflow execution
4. Check logs jika ada error

---

## Setup Database (RDS PostgreSQL)

### 1. Connect ke Database

```bash
# Install PostgreSQL client (di local machine atau EC2)
sudo yum install -y postgresql15

# Connect ke RDS
psql -h rds-onj-primary.c7qw6oy402sj.ap-southeast-1.rds.amazonaws.com \
     -U onjourney \
     -d onjourney_link
```

### 2. Verify Database

```sql
-- Check database exists
\l

-- Check tables (akan dibuat otomatis oleh aplikasi)
\dt
```

### 3. Initial Setup

Database akan di-migrate otomatis saat aplikasi pertama kali dijalankan. Pastikan:

- ✅ Database `onjourney_link` sudah dibuat
- ✅ User `onjourney` memiliki akses
- ✅ Security group mengizinkan akses dari EC2

---

## Deployment

### First Deployment (Manual)

```bash
# Di EC2 instance
cd /home/ec2-user/scripts

# Set environment variables
export ECR_REGISTRY="<account-id>.dkr.ecr.ap-southeast-1.amazonaws.com"
export IMAGE_NAME="onjourney-golink-shortner"
export IMAGE_TAG="latest"
export AWS_REGION="ap-southeast-1"

# Run deploy script
./deploy.sh
```

### Automated Deployment via GitHub Actions

1. Push code ke branch `main`
2. GitHub Actions akan:
   - Run tests
   - Build Docker image untuk ARM64
   - Push ke ECR
   - **Deploy ke semua instances di ASG** via **AWS Systems Manager (SSM)**
   - Run health check di setiap instance
   - Verify ALB health (jika ALB_DNS di-set)

**Note:** Deployment dilakukan via SSM `SendCommand`, bukan SSH. Ini lebih aman karena:
- ✅ Tidak perlu expose SSH port
- ✅ IAM-based access control
- ✅ CloudTrail audit trail
- ✅ Tidak perlu manage SSH keys

### Verify Deployment

```bash
# Check ALB health (recommended - via load balancer)
ALB_DNS="onjourney-golink-shortner-alb-1532011075.ap-southeast-1.elb.amazonaws.com"
curl http://$ALB_DNS/health

# Check target group health
aws elbv2 describe-target-health \
    --target-group-arn <target-group-arn> \
    --query 'TargetHealthDescriptions[*].[Target.Id,TargetHealth.State,TargetHealth.Reason]' \
    --output table

# Check instances di ASG
aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names golink-shorner-asg \
    --query 'AutoScalingGroups[0].Instances[*].[InstanceId,HealthStatus,LifecycleState]' \
    --output table

# Check container status (di specific instance via SSM)
aws ssm start-session --target <instance-id>
# Setelah masuk ke instance:
docker ps
docker logs golink-shorner

# Atau via SSM command langsung (tanpa masuk ke instance):
aws ssm send-command \
  --instance-ids <instance-id> \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["docker ps", "docker logs golink-shorner --tail 50"]' \
  --query 'Command.CommandId' \
  --output text
curl http://localhost:3000/health
```

---

## Monitoring & Maintenance

### 1. View Logs

```bash
# Docker logs
docker logs golink-shorner
docker logs golink-shorner --follow  # Follow logs

# System logs
sudo journalctl -u docker -f
```

### 2. Container Management

```bash
# Restart container (di specific instance)
docker restart golink-shorner

# Stop container
docker stop golink-shorner

# Start container
docker start golink-shorner

# Remove container
docker stop golink-shorner
docker rm golink-shorner
```

### 3. Update Application

**Via GitHub Actions (Recommended):**
- Push ke `main` branch
- GitHub Actions akan deploy otomatis ke **semua instances** di ASG

**Manual untuk ASG:**
```bash
# Deploy ke semua instances di ASG
./scripts/deploy-asg.sh

# Atau deploy ke single instance
cd /home/ec2-user/scripts
./deploy.sh
```

### 4. Scale Auto Scaling Group

**Via AWS Console:**
1. EC2 → Auto Scaling Groups
2. Pilih `golink-shorner-asg`
3. Edit → Group size
4. Update desired capacity (1-2)
5. Save

**Via AWS CLI:**
```bash
# Scale to 2 instances
aws autoscaling set-desired-capacity \
    --auto-scaling-group-name golink-shorner-asg \
    --desired-capacity 2

# Scale to 1 instance
aws autoscaling set-desired-capacity \
    --auto-scaling-group-name golink-shorner-asg \
    --desired-capacity 1
```

### 5. Database Backup

RDS melakukan automated backup otomatis. Untuk manual backup:

```bash
# Via AWS Console: RDS → Snapshots → Take snapshot
# Via CLI:
aws rds create-db-snapshot \
    --db-instance-identifier golink-shorner-db \
    --db-snapshot-identifier golink-shorner-manual-$(date +%Y%m%d)
```

### 6. Monitoring

**CloudWatch Metrics:**
- EC2: CPU, Memory, Network
- RDS: CPU, Connections, Storage
- ECR: Image count, storage

**Application Health:**
- Health endpoint: `http://<ec2-ip>:3000/health`
- Setup CloudWatch alarm untuk health check

### 7. Scaling

**Vertical Scaling (Resize Instance):**
- EC2: Change instance type (t4g.small → t4g.medium)
- RDS: Modify instance class

**Horizontal Scaling (Add Instances):**
- Tambah EC2 instances
- Setup Application Load Balancer
- Update GitHub Actions untuk deploy ke multiple instances

---

## Troubleshooting

### Container tidak start

```bash
# Check logs
docker logs golink-shorner

# Check environment variables
docker inspect golink-shorner | grep Env

# Test run manually
docker run --rm --env-file /home/ec2-user/.env golink-shorner:latest
```

### Database connection error

```bash
# Test connection dari EC2
psql -h rds-onj-primary.c7qw6oy402sj.ap-southeast-1.rds.amazonaws.com -U onjourney -d onjourney_link

# Check security group rules
# Pastikan RDS security group mengizinkan akses dari EC2 security group
```

### ECR access denied

```bash
# Check IAM role
aws sts get-caller-identity

# Test ECR login
aws ecr get-login-password --region ap-southeast-1 | \
    docker login --username AWS --password-stdin <ecr-registry>
```

### GitHub Actions deployment failed

#### Error: "Credentials could not be loaded"

**Penyebab:** Secrets dikonfigurasi di GitHub Environment, tapi workflow tidak menggunakan environment.

**Solusi:**

**Option 1: Gunakan Environment (Recommended jika secrets sudah di Environment)**
- Pastikan workflow menggunakan `environment: production` di job level (sudah dikonfigurasi)
- Verify secrets ada di **Settings** → **Environments** → **production** → **Environment secrets**

**Option 2: Pindahkan secrets ke Repository level**
- Copy secrets dari Environment ke **Settings** → **Secrets and variables** → **Actions** → **Repository secrets**
- Remove `environment: production` dari workflow file

**Verification:**
1. Check workflow logs di GitHub
2. Verify semua secrets sudah di-set dengan benar (di Environment atau Repository level)
3. Pastikan workflow menggunakan `environment:` jika secrets di Environment
4. Test SSM access manual:
   ```bash
   # Test SSM access ke instance
   aws ssm start-session --target <instance-id>
   
   # Atau test SSM command
   aws ssm send-command \
     --instance-ids <instance-id> \
     --document-name "AWS-RunShellScript" \
     --parameters 'commands=["echo test"]' \
     --query 'Command.CommandId' \
     --output text
   ```
4. Verify IAM policy memiliki SSM permissions
5. Verify instance memiliki IAM role dengan SSM permissions

---

## Cost Estimation

**Monthly Cost (ap-southeast-1):**

- EC2 t4g.small: ~$15
- RDS db.t4g.micro: ~$15-20
- ECR storage (10GB): ~$1
- Data transfer: ~$5-10
- **Total: ~$35-50/bulan**

**Dengan optimasi:**
- Reserved Instances: -30-40%
- Spot Instances: -70% (tidak recommended untuk production)

---

## Security Best Practices

1. ✅ **Never commit `.env` file** - Gunakan GitHub Secrets
2. ✅ **Use IAM roles** - Jangan hardcode AWS credentials
3. ✅ **Enable RDS encryption** - Encrypt database at rest
4. ✅ **Use VPC** - Jangan expose database ke public internet
5. ✅ **Regular updates** - Update AMI dan Docker images
6. ✅ **Monitor logs** - Setup CloudWatch Logs
7. ✅ **Backup regularly** - Automated RDS backups
8. ✅ **Use HTTPS** - Setup ALB dengan SSL certificate

---

## Next Steps

1. ✅ Setup Application Load Balancer (ALB) - **DONE**
2. ✅ Setup Auto Scaling Group - **DONE**
3. ✅ Setup CloudWatch alarms untuk monitoring
4. ✅ Setup automated backups
5. ✅ Implement Redis caching untuk performance
6. ✅ Setup CDN (CloudFront) untuk static assets
7. ✅ Setup SSL certificate untuk HTTPS
8. ✅ Configure custom domain untuk ALB

---

## Support

Jika ada masalah, check:
- GitHub Actions logs
- Docker logs: `docker logs golink-shorner`
- CloudWatch logs
- RDS logs (di CloudWatch)

---

**Selamat! Setup selesai. Aplikasi Anda sekarang berjalan di AWS dengan CI/CD otomatis! 🚀**


#### Generate User Data Script (Helper Script):

Untuk generate User Data script dengan mudah:

```bash
# Generate User Data script
chmod +x scripts/generate-user-data.sh
./scripts/generate-user-data.sh [s3-bucket] [region]

# Contoh:
./scripts/generate-user-data.sh onjourney-asset-bucket ap-southeast-1 > user-data-script.sh

# Copy output ke Launch Template User Data field
```

**Atau copy langsung dari section di atas (Opsi 1 - Recommended).**

---

#### Update Launch Template User Data:

**Via AWS Console:**
1. Buka **EC2 Console** → **Launch Templates**
2. Pilih Launch Template `onjourney-golink-shortner` (ID: `lt-02dc4a959747d21b5`)
3. Klik **Actions** → **Modify template (Create new version)**
4. Scroll ke bagian **Advanced details**
5. Paste User Data script ke field **User data**
6. Klik **Create template version**
7. Set sebagai **Default version** jika perlu

**Via AWS CLI:**
```bash
# Generate User Data script
./scripts/generate-user-data.sh onjourney-asset-bucket ap-southeast-1 > user-data.txt

# Update Launch Template
aws ec2 create-launch-template-version \
    --launch-template-id lt-02dc4a959747d21b5 \
    --launch-template-data file://user-data.txt \
    --source-version 1 \
    --region ap-southeast-1
```

**⚠️ Important:**
- Pastikan script `setup-ec2.sh` sudah di-upload ke S3 sebelum instance di-launch
- Pastikan IAM role `EC2RoleForSSM` memiliki S3 read permissions untuk bucket `onjourney-asset-bucket`
- User Data script akan berjalan saat instance pertama kali di-launch (hanya sekali)
- Maximum execution time: 10 minutes (untuk Amazon Linux)

**Verification setelah instance di-launch:**
```bash
# Verify setup via SSM
./scripts/verify-instance-setup.sh <instance-id>
```

