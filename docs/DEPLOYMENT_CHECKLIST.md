# Deployment Checklist - golink-shorner

Checklist untuk tracking progress deployment ke AWS dengan Auto Scaling Group.

**Project:** golink-shorner  
**Region:** ap-southeast-1  
**Started:** 2025-12-30

---

## ✅ Phase 1: AWS Resources Setup

### 1. ECR Repository ✅ COMPLETED

**Status:** ✅ Completed  
**Date:** 2025-12-30  
**Repository Name:** `onjourney-golink-shortner`

**Details:**
- **Repository ARN:** `arn:aws:ecr:ap-southeast-1:577638371164:repository/onjourney-golink-shortner`
- **Registry ID:** `577638371164`
- **Repository URI:** `577638371164.dkr.ecr.ap-southeast-1.amazonaws.com/onjourney-golink-shortner`
- **Image Scanning:** ✅ Enabled
- **Tag Mutability:** MUTABLE
- **Encryption:** AES256

**Notes:**
- Repository name: `onjourney-golink-shortner` (perhatikan: berbeda dengan dokumentasi default `golink-shorner`)
- Update workflow dan scripts untuk menggunakan nama repository ini

---

### 2. RDS PostgreSQL Database ✅ COMPLETED

**Status:** ✅ Completed  
**Date:** 2025-12-30  
**DB Instance Identifier:** `rds-onj-primary`

**Required Information:**
- [x] Database endpoint: `rds-onj-primary.c7qw6oy402sj.ap-southeast-1.rds.amazonaws.com`
- [x] Port: `5432` (default)
- [x] Database name: `onjourney_link` ⚠️ (berbeda dari default `link_shorner`)
- [x] Username: `onjourney` ⚠️ (berbeda dari default `postgres`)
- [x] Password: `R8o3Y3aLQWVb` ✅ **UPDATED** (simpan dengan aman!)
- [x] Security Group ID: `sg-0a6af115df3e43cdc` (db-security-group)

**Configuration:**
- [x] Engine: PostgreSQL
- [x] Availability Zone: `ap-southeast-1a`
- [x] VPC: `VPC-ONJ` (vpc-07bbbdd4033765409)
- [x] Subnet group: `onj-subnetgroup`
- [x] Subnets: 
  - `subnet-0552727603c822147`
  - `subnet-0df928651bfbae02b`
- [x] Network type: IPv4
- [x] Public access: No ✅
- [x] Certificate: rds-ca-rsa2048-g1
- [x] Certificate expiration: August 28, 2026

**⚠️ Important Notes:**
- Database name: `onjourney_link` (bukan `link_shorner` seperti di dokumentasi)
- Username: `onjourney` (bukan `postgres`)
- Password: `R8o3Y3aLQWVb` ✅ **UPDATED 2025-12-30**
- Perlu update konfigurasi aplikasi untuk menggunakan nama database dan username yang benar
- VPC: `VPC-ONJ` - pastikan EC2 instances juga di VPC yang sama
- Security group: `db-security-group` - perlu allow access dari EC2 security group

**Output:**
```
Endpoint: rds-onj-primary.c7qw6oy402sj.ap-southeast-1.rds.amazonaws.com
Username: onjourney
Password: R8o3Y3aLQWVb (Updated 2025-12-30)
Database: onjourney_link
VPC: vpc-07bbbdd4033765409 (VPC-ONJ)
Security Group: sg-0a6af115df3e43cdc (db-security-group)
Subnets: subnet-0552727603c822147, subnet-0df928651bfbae02b
Public Access: No
```

---

### 3. Application Load Balancer (ALB) ✅ COMPLETED

**Status:** ✅ Completed (Status: Provisioning → akan berubah ke Active)  
**Date:** 2025-12-30, 23:11 (UTC+08:00)  
**ALB Name:** `onjourney-golink-shortner-alb`

**Required Information:**
- [x] ALB ARN: `arn:aws:elasticloadbalancing:ap-southeast-1:577638371164:loadbalancer/app/onjourney-golink-shortner-alb/2ad555672cd7e3c6`
- [x] ALB DNS Name: `onjourney-golink-shortner-alb-1532011075.ap-southeast-1.elb.amazonaws.com`
- [x] Security Group ID: `sg-0ad2cbd7ab9780644` (alb-security-group) ✅
- [x] VPC ID: `vpc-07bbbdd4033765409` (VPC-ONJ) ✅ Same as RDS and Target Group
- [x] Subnet IDs: 
  - `subnet-07c21a6b00297f3c9` (ap-southeast-1a)
  - `subnet-09b382f4141ee1399` (ap-southeast-1b)
  - ⚠️ Berbeda dari RDS subnets, tapi masih di VPC yang sama ✅

**Configuration:**
- [x] Load balancer type: Application
- [x] Scheme: Internet-facing
- [x] IP address type: IPv4
- [x] Status: Provisioning (akan berubah ke Active setelah selesai)
- [x] Hosted zone: `Z1LMS91P8CMLE5`
- [x] Listeners: HTTP (80) → Forward to target group ✅ **COMPLETED**
  - Forward to: `onjourney-golink-shortner-tg`
  - Weight: 100% (1 rule)
  - Target group stickiness: Off
- [x] Target group: `onjourney-golink-shortner-tg` ✅ (sudah dibuat)
- [x] Target Group ARN: `arn:aws:elasticloadbalancing:ap-southeast-1:577638371164:targetgroup/onjourney-golink-shortner-tg/5374847abd875d01`

**⚠️ Important Notes:**
- ALB subnets berbeda dari RDS subnets, tapi masih di VPC yang sama ✅
- Status masih "Provisioning" - tunggu sampai "Active" sebelum testing
- Listener sudah dikonfigurasi ✅ (HTTP 80 → Target Group)
- DNS name: `onjourney-golink-shortner-alb-1532011075.ap-southeast-1.elb.amazonaws.com`

**Output:**
```
Load Balancer Name: onjourney-golink-shortner-alb
Type: Application
Scheme: Internet-facing
Status: Provisioning (akan berubah ke Active)
ARN: arn:aws:elasticloadbalancing:ap-southeast-1:577638371164:loadbalancer/app/onjourney-golink-shortner-alb/2ad555672cd7e3c6
DNS Name: onjourney-golink-shortner-alb-1532011075.ap-southeast-1.elb.amazonaws.com
Hosted Zone: Z1LMS91P8CMLE5
Security Group: sg-0ad2cbd7ab9780644 (alb-security-group)
VPC: vpc-07bbbdd4033765409 (VPC-ONJ)
Availability Zones:
  - subnet-07c21a6b00297f3c9 (ap-southeast-1a)
  - subnet-09b382f4141ee1399 (ap-southeast-1b)
IP Address Type: IPv4
Date Created: December 30, 2025, 23:11 (UTC+08:00)

Listener Configuration:
  - HTTP:80 → Forward to onjourney-golink-shortner-tg
  - Weight: 100% (1 rule)
  - Target group stickiness: Off
```

---

### 4. Target Group ✅ COMPLETED

**Status:** ✅ Completed  
**Date:** 2025-12-30  
**Target Group Name:** `onjourney-golink-shortner-tg`

**Required Information:**
- [x] Target Group ARN: `arn:aws:elasticloadbalancing:ap-southeast-1:577638371164:targetgroup/onjourney-golink-shortner-tg/5374847abd875d01`
- [x] VPC ID: `vpc-07bbbdd4033765409` (VPC-ONJ) ✅ Same as RDS

**Configuration:**
- [x] Target type: Instances
- [x] Protocol: HTTP
- [x] Port: `80` ⚠️ (berbeda dari dokumentasi yang menggunakan port 3000)
- [x] Protocol version: HTTP1
- [x] IP address type: IPv4
- [ ] Health check path: `/health` (perlu verify)
- [ ] Health check interval: (perlu verify)
- [ ] Healthy threshold: (perlu verify)
- [ ] Unhealthy threshold: (perlu verify)
- [ ] Timeout: (perlu verify)
- [x] Load balancer: ✅ Attached to ALB `onjourney-golink-shortner-alb` via listener
- [ ] Total targets: 0 (belum ada instances - akan di-register otomatis oleh ASG)

**⚠️ Important Notes:**
- Target Group name: `onjourney-golink-shortner-tg` (bukan `golink-shorner-tg`)
- Port: `80` (perlu verify apakah ini port untuk health check atau port aplikasi)
  - Jika aplikasi berjalan di port 3000, mungkin perlu update target group port ke 3000
  - Atau ALB akan forward dari port 80 ke port 3000 di instances
- VPC: Same as RDS (vpc-07bbbdd4033765409) ✅
- ✅ Sudah di-attach ke ALB via listener (HTTP 80 → Target Group)
- Belum ada targets (akan di-register otomatis oleh ASG setelah instances launched)

**Output:**
```
Target Group Name: onjourney-golink-shortner-tg
ARN: arn:aws:elasticloadbalancing:ap-southeast-1:577638371164:targetgroup/onjourney-golink-shortner-tg/5374847abd875d01
Target Type: Instance
Protocol:Port: HTTP: 80
Protocol Version: HTTP1
VPC: vpc-07bbbdd4033765409 (VPC-ONJ)
IP Address Type: IPv4
Load Balancer: 0 (not attached)
Total Targets: 0
```

---

### 5. Launch Template ✅ COMPLETED

**Status:** ✅ Completed  
**Date:** 2025-12-31  
**Template Name:** `onjourney-golink-shortner`

**Required Information:**
- [x] Launch Template ID: `lt-02dc4a959747d21b5`
- [x] Launch Template Name: `onjourney-golink-shortner`
- [x] Default Version: 1
- [x] Description: "Initial version for onjourney-golink-shortner"
- [x] Date Created: 2025-12-31T01:15:00.000Z
- [x] Created by: `arn:aws:iam::577638371164:user/harits`

**Configuration:**
- [x] AMI ID: `ami-0083aa2b4fd35d431`
- [x] Instance type: `t4g.small` ✅ (ARM64/Graviton)
- [x] Key pair: `onjourney-link-keypair`
- [x] Security group IDs: `sg-083aa1a4be548f2ff`
- [ ] IAM role: `EC2RoleForSSM` ⚠️ **VERIFY REQUIRED** (perlu verify apakah sudah di-attach ke Launch Template)
- [ ] User data: (perlu verify apakah sudah di-configure)

**Output:**
```
Launch Template ID: lt-02dc4a959747d21b5
Launch Template Name: onjourney-golink-shortner
Default Version: 1
Owner: arn:aws:iam::577638371164:user/harits

Version Details:
  Version: 1
  Description: Initial version for onjourney-golink-shortner
  Date created: 2025-12-31T01:15:00.000Z
  Created by: arn:aws:iam::577638371164:user/harits

Configuration:
  AMI ID: ami-0083aa2b4fd35d431
  Instance type: t4g.small
  Key pair name: onjourney-link-keypair
  Security group IDs: sg-083aa1a4be548f2ff
```

**⚠️ Important Notes:**
- Launch Template name: `onjourney-golink-shortner` (bukan `golink-shorner-template`)
- Security Group: `sg-083aa1a4be548f2ff` (perlu verify apakah ini EC2 security group yang benar)
- Instance type: `t4g.small` ✅ (ARM64/Graviton - sesuai dengan Dockerfile yang sudah di-build untuk ARM64)
- Key pair: `onjourney-link-keypair` (perlu pastikan private key sudah disimpan untuk SSH access)
- IAM Role: `EC2RoleForSSM` ✅ (sudah tersedia dengan semua policies yang diperlukan)
  - Perlu verify apakah role ini sudah di-attach ke Launch Template
- Perlu verify User data script untuk initial setup

---

### 6. Auto Scaling Group ✅ COMPLETED

**Status:** ✅ Completed  
**Date:** 2026-01-02  
**ASG Name:** `onjourney-golink-asg`

**Required Information:**
- [x] ASG ARN: `arn:aws:autoscaling:ap-southeast-1:577638371164:autoScalingGroup:091b21fc-8aab-4d7d-9515-77e0e5fd406f:autoScalingGroupName/onjourney-golink-asg`
- [x] Launch Template: `onjourney-golink-shortner` ✅ (sudah dibuat)
- [x] Launch Template ID: `lt-02dc4a959747d21b5` ✅
- [x] Target Group: `onjourney-golink-shortner-tg` ✅ (sudah dibuat)
- [x] Target Group ARN: `arn:aws:elasticloadbalancing:ap-southeast-1:577638371164:targetgroup/onjourney-golink-shortner-tg/5374847abd875d01`

**Configuration:**
- [x] Min size: 1
- [x] Desired capacity: 1
- [x] Max size: 2
- [x] Health check type: EC2, ELB ✅
- [x] Health check grace period: 300 seconds
- [x] VPC: `vpc-07bbbdd4033765409` (VPC-ONJ) ✅ (sama dengan RDS dan Target Group)
- [x] Subnets: 
  - `subnet-07c21a6b00297f3c9` (ap-southeast-1a / apse1-az2)
  - `subnet-09b382f4141ee1399` (ap-southeast-1b / apse1-az1)
- [x] Availability Zone distribution: Balanced best effort
- [x] Instance maintenance policy: Terminate and launch
- [x] Min healthy percentage: 80%
- [x] Max healthy percentage: 100%
- [x] Default cooldown: 300 seconds
- [x] Service-linked role: `arn:aws:iam::577638371164:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling`

**Output:**
```
Auto Scaling Group Name: onjourney-golink-asg
ARN: arn:aws:autoscaling:ap-southeast-1:577638371164:autoScalingGroup:091b21fc-8aab-4d7d-9515-77e0e5fd406f:autoScalingGroupName/onjourney-golink-asg
Date Created: Fri Jan 02 2026 10:33:07 GMT+0800 (Central Indonesia Time)

Capacity:
  Desired: 1
  Min: 1
  Max: 2

Launch Template:
  ID: lt-02dc4a959747d21b5
  Name: onjourney-golink-shortner
  Version: Default
  AMI ID: ami-0083aa2b4fd35d431
  Instance Type: t4g.small
  Security Groups: sg-083aa1a4be548f2ff
  Key Pair: onjourney-link-keypair

Network:
  Availability Zones:
    - apse1-az2 (ap-southeast-1a): subnet-07c21a6b00297f3c9
    - apse1-az1 (ap-southeast-1b): subnet-09b382f4141ee1399
  Distribution: Balanced best effort

Health Checks:
  Type: EC2, ELB
  Grace Period: 300 seconds

Instance Maintenance:
  Replacement behavior: Terminate and launch
  Min healthy percentage: 80%
  Max healthy percentage: 100%
```

**⚠️ Important Notes:**
- ASG name: `onjourney-golink-asg` (bukan `golink-shorner-asg`)
- Subnets berbeda dari RDS subnets, tapi masih di VPC yang sama ✅
- Subnets sama dengan ALB subnets ✅
- Health check type: EC2, ELB (akan check health dari kedua sources)
- Instance akan di-launch otomatis sesuai desired capacity (1 instance)
- Instances akan otomatis di-register ke Target Group

**Initial Instances:**
- [x] Instance 1 ID: `i-0f57d90d42538d286` ✅ (Running, 3/3 checks passed, ap-southeast-1a)
- [ ] Instance 1 Name: ⚠️ **MISSING** - Perlu add tag Name untuk identifikasi
- [ ] Instance 1 IP: (perlu get dari AWS Console)
- [x] Instance 1 Status: Running ✅
- [x] Instance 1 Status Check: 3/3 checks passed ✅
- [x] Instance 1 Availability Zone: ap-southeast-1a ✅

**⚠️ Issues Found:**
- ❌ Instance tidak memiliki Name tag - sulit untuk identifikasi
- ⚠️ Ada lebih dari 1 instance (ditemukan 3-4 instances dengan t4g.small)
  - Instance IDs yang terdeteksi:
    - `i-0f57d90d42538d286` (Running, 3/3 checks passed, ap-southeast-1a)
    - `i-03c464d5361ec294f` (Running, Initializing, ap-southeast-1b)
    - `i-0e9781b9762435b1d` (Running, 3/3 checks passed, ap-southeast-1b)
  - **Action Required:** 
    - Verify apakah semua instances ini dari ASG `onjourney-golink-asg`
    - Check desired capacity di ASG (seharusnya 1)
    - Terminate instances yang tidak diperlukan jika ada instances lain yang tidak dari ASG kita

**Action Items:**
1. **Add Name Tag ke Launch Template atau ASG:**
   - Via Launch Template: Add tag `Name` dengan value `golink-shortner-{{instance-id}}` atau `golink-shortner-{{launch-time}}`
   - Via ASG Tags: Add tag `Name` dengan value `golink-shortner` (akan propagate ke semua instances)
   
2. **Verify Instance Count:**
   - Check ASG desired capacity: `aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names onjourney-golink-asg --query 'AutoScalingGroups[0].DesiredCapacity'`
   - List instances di ASG: `aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names onjourney-golink-asg --query 'AutoScalingGroups[0].Instances[*].[InstanceId,LifecycleState,HealthStatus]' --output table`
   - Jika ada instances yang tidak dari ASG, terminate instances yang tidak diperlukan

---

### 7. Systems Manager Parameter Store ⏳ PENDING

**Status:** ⏳ Pending

**Required Parameters:**
- [ ] `/golink-shorner/db/host`: `rds-onj-primary.c7qw6oy402sj.ap-southeast-1.rds.amazonaws.com`
- [ ] `/golink-shorner/db/port`: `5432`
- [ ] `/golink-shorner/db/user`: `onjourney` ⚠️ (bukan `postgres`)
- [ ] `/golink-shorner/db/password`: `R8o3Y3aLQWVb` (SecureString) ✅ **UPDATED**
- [ ] `/golink-shorner/db/name`: `onjourney_link` ⚠️ (bukan `link_shorner`)

**⚠️ Note:** Pastikan menggunakan nilai yang benar untuk username dan database name.

**Output:**
```
[Paste output dari AWS Console atau CLI di sini setelah membuat parameters]
```

---

### 8. Security Groups ⏳ PENDING

**Status:** ⏳ Pending

#### ALB Security Group (`alb-security-group`)
- [x] Security Group ID: `sg-0ad2cbd7ab9780644` (alb-security-group) ✅
- [x] Security Group Name: `alb-security-group` ✅
- [x] Description: Security group for ALB ✅
- [x] VPC: `vpc-07bbbdd4033765409` (VPC-ONJ) ✅
- [x] Inbound: HTTP (80) from 0.0.0.0/0 ✅ **CONFIGURED**
  - Rule ID: `sgr-09d17b1b579583f77`
  - Description: HTTP access
- [x] Inbound: HTTPS (443) from 0.0.0.0/0 ✅ **CONFIGURED**
  - Rule ID: `sgr-02603d29ffead489b`
  - Description: HTTPS access
- [x] Inbound: Custom TCP (8080) from 0.0.0.0/0 ⚠️ (mungkin tidak diperlukan, tapi sudah ada)
  - Rule ID: `sgr-0a8fb88fd9f4f2f14`
- [x] ALB: `onjourney-golink-shortner-alb` ✅ (sudah dibuat)

**Output:**
```
Security Group Name: alb-security-group
Security Group ID: sg-0ad2cbd7ab9780644
Description: Security group for ALB
VPC: vpc-07bbbdd4033765409 (VPC-ONJ)
Owner: 577638371164

Inbound Rules (3):
  1. HTTP (TCP 80) from 0.0.0.0/0
     Rule ID: sgr-09d17b1b579583f77
     Description: HTTP access
  
  2. HTTPS (TCP 443) from 0.0.0.0/0
     Rule ID: sgr-02603d29ffead489b
     Description: HTTPS access
  
  3. Custom TCP (TCP 8080) from 0.0.0.0/0
     Rule ID: sgr-0a8fb88fd9f4f2f14
     (Note: Mungkin tidak diperlukan, bisa di-remove jika tidak digunakan)

Outbound Rules: 1 entry (All traffic allowed)
```

**⚠️ Important:**
- Security Group: `sg-0ad2cbd7ab9780644` (alb-security-group) ✅
- ✅ Inbound rules untuk HTTP (80) dan HTTPS (443) sudah dikonfigurasi
- ✅ Traffic dari internet (0.0.0.0/0) sudah di-allow untuk HTTP dan HTTPS
- ⚠️ Port 8080 juga di-allow (mungkin tidak diperlukan, bisa di-remove untuk security)

#### EC2 Security Group (`onjourney-golink-shortner-sg`)
- [x] Security Group ID: `sg-083aa1a4be548f2ff` ✅ (dari Launch Template)
- [x] Security Group Name: `onjourney-golink-shortner-sg` ✅
- [x] Description: `for access on onjourney link` ✅
- [x] VPC: `vpc-07bbbdd4033765409` (VPC-ONJ) ✅
- [x] Owner: `577638371164` ✅
- [x] Inbound: HTTP (3000) from ALB security group (`sg-0ad2cbd7ab9780644`) ✅ **CONFIGURED**
  - Rule ID: `sgr-0736260d2b9ad10a5`
  - Description: From ALB security group
- [x] SSH (22): **NOT REQUIRED** ✅ **USING SSM INSTEAD**
  - SSH rule sudah dihapus karena menggunakan AWS Systems Manager Session Manager
  - **More Secure:** SSM tidak memerlukan port SSH terbuka ke internet
  - **Access Method:** `aws ssm start-session --target <instance-id>`
  - **IAM Permission:** Sudah ada di `EC2RoleForSSM` (`AmazonSSMManagedInstanceCore` policy)

**Output:**
```
Security Group Name: onjourney-golink-shortner-sg
Security Group ID: sg-083aa1a4be548f2ff
Description: for access on onjourney link
VPC: vpc-07bbbdd4033765409 (VPC-ONJ)
Owner: 577638371164

Inbound Rules (1):
  1. Custom TCP (3000) from sg-0ad2cbd7ab9780644 (alb-security-group)
     Rule ID: sgr-0736260d2b9ad10a5
     Description: From ALB security group
     ✅ CORRECT - HTTP traffic from ALB

Note: SSH (22) rule removed - Using AWS Systems Manager Session Manager instead
  ✅ More Secure: No SSH port exposed to internet
  ✅ Access via: `aws ssm start-session --target <instance-id>`
  ✅ IAM Permission: Already configured in EC2RoleForSSM

Outbound Rules (1):
  - All traffic to 0.0.0.0/0
    Rule ID: sgr-0a78598299483710d
```

**✅ SECURITY CONFIGURATION:**
- SSH (22) rule sudah dihapus - **MORE SECURE APPROACH**
- Menggunakan AWS Systems Manager Session Manager untuk akses ke EC2 instances
- **Benefits:**
  - ✅ Tidak perlu membuka port SSH ke internet
  - ✅ Tidak perlu manage SSH keys
  - ✅ Access via IAM permissions (lebih aman)
  - ✅ Audit trail melalui CloudTrail
- **Access Method:** `aws ssm start-session --target <instance-id>`
- **IAM Permission:** Sudah ada di `EC2RoleForSSM` dengan policy `AmazonSSMManagedInstanceCore`

#### RDS Security Group
- [x] Security Group ID: `sg-0a6af115df3e43cdc` (db-security-group) ✅
- [x] Security Group Name: `db-security-group` ✅
- [x] Description: Security group for DB ✅
- [x] VPC: `vpc-07bbbdd4033765409` (VPC-ONJ) ✅
- [x] Owner: `577638371164` ✅
- [x] Inbound: PostgreSQL (5432) from EC2 security group (`sg-083aa1a4be548f2ff`) ✅ **CONFIGURED**
  - Rule ID: `sgr-098f52df5acbac853`
  - Source: `sg-083aa1a4be548f2ff` (onjourney-golink-shortner-sg)
  - Description: Access PostgreSQL from golink

**Output:**
```
Security Group Name: db-security-group
Security Group ID: sg-0a6af115df3e43cdc
Description: Security group for DB
VPC: vpc-07bbbdd4033765409 (VPC-ONJ)
Owner: 577638371164

Inbound Rules (4):
  1. PostgreSQL (5432) from sg-0fc9f6d79768d6492 (codebuild-securitygroup)
     Rule ID: sgr-06b2f393585ae0b38
     Description: Access PostgreSQL from CodeBuild
  
  2. PostgreSQL (5432) from sg-083aa1a4be548f2ff (onjourney-golink-shortner-sg)
     Rule ID: sgr-098f52df5acbac853
     Description: Access PostgreSQL from golink
     ✅ CORRECT - EC2 instances can access RDS
  
  3. PostgreSQL (5432) from sg-09339bf3be5513b5c (taskqueue-security-group)
     Rule ID: sgr-031ed5356ac734a70
     Description: Access PostgreSQL from Task Queue
  
  4. PostgreSQL (5432) from sg-0dd48ad20ee4afe10 (webapp-security-group)
     Rule ID: sgr-0f0443f8ed647a769
     Description: Access PostgreSQL from WebApp

Outbound Rules (1):
  - All traffic allowed
```

**✅ Configuration Status:**
- ✅ RDS security group sudah dikonfigurasi untuk allow access dari EC2 security group
- ✅ PostgreSQL (5432) dari `sg-083aa1a4be548f2ff` (onjourney-golink-shortner-sg) sudah di-allow
- ✅ Security best practice: Hanya allow dari specific security groups, bukan dari 0.0.0.0/0

---

### 9. IAM Role untuk EC2 ✅ COMPLETED

**Status:** ✅ Completed  
**Role Name:** `EC2RoleForSSM`

**Required Information:**
- [x] IAM Role ARN: `arn:aws:iam::577638371164:role/EC2RoleForSSM`
- [x] Instance Profile ARN: `arn:aws:iam::577638371164:instance-profile/EC2RoleForSSM`
- [x] Creation Date: August 27, 2025, 16:51 (UTC+08:00)
- [x] Maximum Session Duration: 1 hour

**Policies Attached (9 managed policies):**
- [x] `AmazonEC2ContainerRegistryReadOnly` ✅ (untuk ECR access)
- [x] `AmazonEC2RoleforAWSCodeDeploy` ✅
- [x] `AmazonSSMManagedInstanceCore` ✅ (untuk SSM access)
- [x] `AWSCodeDeployRole` ✅
- [x] `AWSXRayDaemonWriteAccess` ✅
- [x] `AWSXrayFullAccess` ✅
- [x] `CloudWatchAgentServerPolicy` ✅ (untuk CloudWatch monitoring)
- [x] `codepipeline-artifact-role` ✅ (Customer inline)
- [x] `SecretsManagerReadWrite` ✅ (untuk Parameter Store access)

**Output:**
```
IAM Role: EC2RoleForSSM
ARN: arn:aws:iam::577638371164:role/EC2RoleForSSM
Instance Profile ARN: arn:aws:iam::577638371164:instance-profile/EC2RoleForSSM
Creation Date: August 27, 2025, 16:51 (UTC+08:00)
Maximum Session Duration: 1 hour

Summary: Allows EC2 instances to call AWS services on your behalf.

Policies (9 managed policies):
  ✅ AmazonEC2ContainerRegistryReadOnly - ECR read access
  ✅ AmazonEC2RoleforAWSCodeDeploy - CodeDeploy support
  ✅ AmazonSSMManagedInstanceCore - SSM access
  ✅ AWSCodeDeployRole - CodeDeploy role
  ✅ AWSXRayDaemonWriteAccess - X-Ray daemon access
  ✅ AWSXrayFullAccess - X-Ray full access
  ✅ CloudWatchAgentServerPolicy - CloudWatch monitoring
  ✅ codepipeline-artifact-role - CodePipeline artifacts (Customer inline)
  ✅ SecretsManagerReadWrite - Parameter Store / Secrets Manager access
```

**⚠️ Important Notes:**
- IAM Role: `EC2RoleForSSM` (bukan `EC2-ECR-Access-Role` seperti di dokumentasi)
- Role ini sudah memiliki semua policies yang diperlukan:
  - ✅ ECR access (`AmazonEC2ContainerRegistryReadOnly`)
  - ✅ Parameter Store access (`SecretsManagerReadWrite`)
  - ✅ SSM access (`AmazonSSMManagedInstanceCore`)
  - ✅ CloudWatch monitoring (`CloudWatchAgentServerPolicy`)
- Perlu verify apakah role ini sudah di-attach ke Launch Template
- Instance Profile sudah tersedia: `EC2RoleForSSM`

---

## ✅ Phase 2: EC2 Instance Setup

### 10. Connect to First Instance ✅ COMPLETED

**Status:** ✅ Completed  
**Date:** 2026-01-02  
**Instance ID:** `i-0f57d90d42538d286`

- [x] Instance ID: `i-0f57d90d42538d286` ✅
- [ ] Instance IP: (perlu get dari AWS Console atau `aws ec2 describe-instances`)
- [x] SSM connection: ✅ Tested and Working
  - Session ID: `harits-ak9xsd3z3yp4parruk88y9uexi`
  - Access method: AWS Systems Manager Session Manager
  - User: `root@ip-172-20-1-251`

**Connection Method:**
```bash
# Via Systems Manager (Recommended - More Secure)
aws ssm start-session --target i-0f57d90d42538d286

# Output:
# Starting session with SessionId: harits-ak9xsd3z3yp4parruk88y9uexi
# sh-5.2$ sudo su
# [root@ip-172-20-1-251 bin]#
```

**⚠️ Important Notes:**
- ✅ SSM access berhasil - IAM role `EC2RoleForSSM` sudah bekerja dengan baik
- Instance hostname: `ip-172-20-1-251` (private IP: 172.20.1.251)
- User sudah switch ke root untuk setup
- Next: Perlu verify setup dan run initial setup script

---

### 11. Initial Setup Script ⏳ IN PROGRESS

**Status:** ⏳ In Progress  
**Date:** 2026-01-02  
**Instance:** `i-0b4fff801195417e3` (ip-172-20-1-227)

- [x] Scripts uploaded to S3: `s3://onjourney-asset-bucket/scripts/` ✅
- [x] Setup script downloaded from S3 ✅
- [x] Setup script executed: `setup-ec2.sh` ⏳ **RUNNING**
- [ ] Docker installed: ⏳
- [ ] AWS CLI installed: ⏳
- [ ] jq installed: ⏳
- [ ] Directories created: ⏳

**Upload Scripts to S3 (From Local Machine):**
```bash
# Make upload script executable
chmod +x scripts/upload-to-s3.sh

# Upload all scripts to S3
./scripts/upload-to-s3.sh
```

**Download and Run Setup Script (On EC2 Instance via SSM):**
```bash
# Connect to instance
aws ssm start-session --target <instance-id>

# Download setup script from S3
aws s3 cp s3://onjourney-asset-bucket/scripts/setup-ec2.sh /tmp/setup-ec2.sh

# Make executable
chmod +x /tmp/setup-ec2.sh

# Run setup
/tmp/setup-ec2.sh
```

**Commands Executed:**
```bash
# Connect to instance
aws ssm start-session --target i-0b4fff801195417e3

# Download setup script from S3
aws s3 cp s3://onjourney-asset-bucket/scripts/setup-ec2.sh /tmp/setup-ec2.sh
# Output: download: s3://onjourney-asset-bucket/scripts/setup-ec2.sh to ../../tmp/setup-ec2.sh

# Make executable and run
chmod +x /tmp/setup-ec2.sh
./setup-ec2.sh
# ⏳ Script is currently running...
```

**Output:**
```
[Paste output dari setup script di sini setelah selesai]
```

**Expected Output:**
- System packages updated
- Docker installed and started
- AWS CLI v2 installed (if not already)
- jq installed
- Directories created: `/home/ec2-user/app`, `/home/ec2-user/scripts`
- .env template created (if not exists)
- Docker log rotation configured

---

### 12. Environment Variables Configuration ✅ COMPLETED

**Status:** ✅ Completed  
**Date:** 2026-01-02  
**Instance:** `i-0f57d90d42538d286` (ip-172-20-1-227)

- [x] `.env` file created at `/home/ec2-user/.env`
- [x] Database credentials configured
- [x] File permissions set (chmod 600)

**Configuration:**
```env
DB_HOST=rds-onj-primary.c7qw6oy402sj.ap-southeast-1.rds.amazonaws.com
DB_PORT=5432
DB_USER=onjourney
DB_PASSWORD=R8o3Y3aLQWVb
DB_NAME=onjourney_link
DB_SSLMODE=require
DB_TIMEZONE=Asia/Jakarta
```

**⚠️ Important:**
- Database name: `onjourney_link` (bukan `link_shorner`)
- Username: `onjourney` (bukan `postgres`)
- Password: `R8o3Y3aLQWVb` ✅ **UPDATED 2025-12-30**
- Pastikan security group `db-security-group` allow access dari EC2 security group

**Notes:**
```
✅ .env file sudah dibuat dan di-edit dengan nano
✅ File sudah ada di /home/ec2-user/.env
✅ Database credentials sudah dikonfigurasi
✅ Instance: ip-172-20-1-227 (i-0f57d90d42538d286)
```

---

### 13. Deploy Script Setup ✅ DONE

**Status:** ⏳ In Progress  
**Date:** 2026-01-02

- [x] Scripts uploaded to S3: `s3://onjourney-asset-bucket/scripts/`
- [x] `deploy.sh` downloaded from S3 to `/home/ec2-user/scripts/`
- [x] Script executable (chmod +x)
- [x] ECR access tested ✅ **COMPLETED**

**Upload Scripts to S3 (From Local Machine):**
```bash
# Make upload script executable
chmod +x scripts/upload-to-s3.sh

# Upload all scripts to S3
./scripts/upload-to-s3.sh
```

**Download Deploy Script (On EC2 Instance via SSM):**
```bash
# Download from S3
aws s3 cp s3://onjourney-asset-bucket/scripts/deploy.sh /home/ec2-user/scripts/deploy.sh

# Make executable
chmod +x /home/ec2-user/scripts/deploy.sh
```

**Test ECR Login:**
```bash
aws ecr get-login-password --region ap-southeast-1 | \
    docker login --username AWS --password-stdin 577638371164.dkr.ecr.ap-southeast-1.amazonaws.com
```

**Output:**
```
✅ Login Succeeded
WARNING! Your password will be stored unencrypted in /root/.docker/config.json.
Configure a credential helper to remove this warning.

Instance: ip-172-20-1-227 (i-0f57d90d42538d286)
Date: 2026-01-02
```

---

## ✅ Phase 3: GitHub Actions Setup

### 14. GitHub Secrets Configuration ✅ COMPLETED

**Status:** ✅ Completed  
**Date:** 2026-01-02

**Secrets Configured:**
- [x] `AWS_ACCESS_KEY_ID`: ✅ **CONFIGURED** (updated 6 minutes ago)
- [x] `AWS_SECRET_ACCESS_KEY`: ✅ **CONFIGURED** (updated 5 minutes ago, masked)
- [x] `ASG_NAME`: `onjourney-golink-asg` ✅ **CONFIGURED** (updated now)
- [x] `ALB_DNS`: `onjourney-golink-shortner-alb-1532011075.ap-southeast-1.elb.amazonaws.com` ✅ **CONFIGURED** (updated now)

**Note:** 
- ✅ **Tidak perlu SSH secrets** (`EC2_HOST`, `EC2_USER`, `EC2_SSH_KEY`) karena menggunakan **AWS Systems Manager (SSM)** untuk deployment
- ✅ Deployment dilakukan via SSM `SendCommand`, bukan SSH
- ✅ Instances di ASG sudah memiliki IAM role `EC2RoleForSSM` yang memungkinkan SSM access
- ✅ Semua required secrets sudah dikonfigurasi di GitHub Environment

**IAM Policy Status:**
- ✅ Policy `github-actions-deploy-prod` sudah dibuat
- ✅ ECR permissions: ✅ Complete (GetAuthorizationToken, BatchCheckLayerAvailability, BatchGetImage, PutImage, dll)
- ✅ SSM permissions: ✅ Complete (SendCommand, ListCommands, ListCommandInvocations, GetCommandInvocation)
- ⚠️ **Missing permissions:** `autoscaling:DescribeAutoScalingGroups`, `ec2:DescribeInstances` (perlu ditambahkan)

**📋 Panduan Menambahkan Missing Permissions:**

Lihat panduan lengkap di section **"15.1. Menambahkan Missing Permissions ke IAM Policy"** di bawah.

**Notes:**
```
✅ All GitHub secrets configured successfully
✅ Using SSM-based deployment (no SSH required)
✅ Secrets are stored in GitHub Environment (encrypted)
⚠️ IAM policy perlu ditambahkan ASG dan EC2 read permissions untuk workflow bisa query instances
```

---

### 15. IAM Policy Verification ✅ COMPLETED

**Status:** ✅ Completed  
**Date:** 2026-01-02

**Policy:** `github-actions-deploy-prod` (Customer managed)

**Policy ARN:** `arn:aws:iam::577638371164:policy/github-actions-deploy-prod`

**Policy Status:** ✅ **UPDATED** - Policy berhasil di-update dengan 2 statements

**Current Permissions:**

---

### 15.1. Menambahkan Missing Permissions ke IAM Policy ⚠️ ACTION REQUIRED

**Status:** ⚠️ **PENDING** - Perlu ditambahkan  
**Date:** 2026-01-02

**Missing Permissions:**
- `autoscaling:DescribeAutoScalingGroups` - Untuk query instances di ASG
- `ec2:DescribeInstances` - Untuk mendapatkan detail instances

**📋 Step-by-Step Guide:**

#### Step 1: Buka IAM Policy di AWS Console

1. Login ke **AWS Console**
2. Buka **IAM** → **Policies**
3. Search policy: `github-actions-deploy-prod`
4. Klik policy name untuk membuka detail

#### Step 2: Edit Policy JSON

1. Di policy detail page, klik tab **"JSON"**
2. Klik button **"Edit"**
3. Policy JSON akan muncul di editor

#### Step 3: Tambahkan Permissions ke Statement yang Sudah Ada

**Option A: Tambahkan ke Statement ECR yang Sudah Ada (Recommended)**

Cari statement dengan `"Sid": "ECRPermissions"` atau statement pertama, lalu tambahkan actions berikut ke array `Action`:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ECRPermissions",
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:BatchGetImage",
        "ecr:CompleteLayerUpload",
        "ecr:DescribeImages",
        "ecr:DescribeRepositories",
        "ecr:GetDownloadUrlForLayer",
        "ecr:InitiateLayerUpload",
        "ecr:PutImage",
        "ecr:UploadLayerPart",
        "autoscaling:DescribeAutoScalingGroups",      
        "ec2:DescribeInstances"                        
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

**Option B: Buat Statement Baru (Alternatif)**

Jika lebih suka memisahkan permissions, tambahkan statement baru setelah statement SSM:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ECRPermissions",
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:BatchGetImage",
        "ecr:CompleteLayerUpload",
        "ecr:DescribeImages",
        "ecr:DescribeRepositories",
        "ecr:GetDownloadUrlForLayer",
        "ecr:InitiateLayerUpload",
        "ecr:PutImage",
        "ecr:UploadLayerPart"
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
    },
    {
      "Sid": "ASGAndEC2ReadPermissions",              // ← STATEMENT BARU
      "Effect": "Allow",
      "Action": [
        "autoscaling:DescribeAutoScalingGroups",
        "ec2:DescribeInstances"
      ],
      "Resource": "*"
    }
  ]
}
```

#### Step 4: Validasi dan Simpan

1. Klik button **"Next"** atau **"Review policy"**
2. AWS akan validate JSON syntax
3. Jika ada error, perbaiki sesuai error message
4. Jika valid, klik **"Save changes"**

#### Step 5: Verifikasi

1. Refresh policy page
2. Klik tab **"JSON"** lagi
3. Verify bahwa permissions sudah ditambahkan:
   - `autoscaling:DescribeAutoScalingGroups` ada di salah satu statement
   - `ec2:DescribeInstances` ada di salah satu statement

#### Step 6: Test dari GitHub Actions

1. Re-run workflow di GitHub Actions
2. Check step **"Get ASG Instances"** - seharusnya tidak error lagi
3. Jika masih error, check:
   - Policy sudah di-attach ke IAM user yang digunakan GitHub Actions
   - Policy version sudah ter-update (AWS auto-create new version)

**✅ Expected Result:**

Setelah menambahkan permissions, workflow seharusnya bisa:
- ✅ Query instances dari ASG tanpa error
- ✅ Get instance details untuk deployment
- ✅ Deploy ke instances via SSM

**📝 Notes:**
- Policy changes berlaku immediately setelah save
- Tidak perlu re-attach policy ke user (jika sudah attached)
- AWS auto-create new policy version setiap kali di-edit

---

**Current Permissions (Before Update):**
- ✅ ECR permissions: Complete
  - GetAuthorizationToken, BatchCheckLayerAvailability, BatchGetImage
  - GetDownloadUrlForLayer, InitiateLayerUpload, UploadLayerPart
  - CompleteLayerUpload, PutImage
- ✅ ASG permissions: Complete ✅ **ADDED**
  - DescribeAutoScalingGroups, DescribeAutoScalingInstances
- ✅ EC2 permissions: Complete ✅ **ADDED**
  - DescribeInstances, DescribeInstanceStatus
- ✅ SSM permissions: Complete ✅ **ADDED**
  - SendCommand, ListCommands, ListCommandInvocations, GetCommandInvocation
  - Resources: `arn:aws:ec2:ap-southeast-1:577638371164:instance/*`
  - Document: `arn:aws:ssm:ap-southeast-1::document/AWS-RunShellScript`
  - Commands: `arn:aws:ssm:ap-southeast-1:577638371164:command/*`

**Policy Structure:**
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

**Notes:**
```
✅ Policy sudah lengkap dengan 2 statements
✅ Statement 1 (VisualEditor0): ECR + ASG + EC2 permissions
✅ Statement 2 (SSMSendCommandPermissions): SSM permissions
✅ Policy berhasil di-update dan siap digunakan untuk GitHub Actions workflow
✅ Semua permissions yang diperlukan sudah ada
✅ Status: "Policy github-actions-deploy-prod updated" - CONFIRMED
```

- [ ] SSH key pair generated
- [ ] Public key copied to all ASG instances
- [ ] Private key added to GitHub Secrets

**SSH Key Details:**
- [ ] Key file: `github-actions-key`
- [ ] Key type: RSA 4096
- [ ] Instances configured: `___________________________`

**Output:**
```
[Paste output dari ssh-copy-id atau notes di sini]
```

---

### 16. GitHub Actions Workflow Configuration ⏳ PENDING

**Status:** ⏳ Pending

**Workflow File:** `.github/workflows/deploy.yml`

**Configuration Check:**
- [ ] Branch trigger: `main` ✅
- [ ] AWS region: `ap-southeast-1` ✅
- [ ] ECR repository: `onjourney-golink-shortner` ⚠️ (perlu update dari default)
- [ ] ASG name: `golink-shorner-asg` ✅

**⚠️ Action Required:**
Update workflow file untuk menggunakan ECR repository name yang benar:
- Current: `golink-shorner`
- Should be: `onjourney-golink-shortner`

**Notes:**
```
[Any notes about workflow configuration]
```

---

## ✅ Phase 4: Database Setup

### 17. Database Connection Test ⏳ PENDING

**Status:** ⏳ Pending

- [ ] PostgreSQL client installed
- [ ] Connection tested from EC2
- [ ] Database `onjourney_link` exists ⚠️ (bukan `link_shorner`)

**Connection Test:**
```bash
# Test connection (dari EC2 atau local dengan VPN/bastion)
psql -h rds-onj-primary.c7qw6oy402sj.ap-southeast-1.rds.amazonaws.com \
     -U onjourney \
     -d onjourney_link

# Atau test dengan password
PGPASSWORD='R8o3Y3aLQWVb' psql \
  -h rds-onj-primary.c7qw6oy402sj.ap-southeast-1.rds.amazonaws.com \
  -U onjourney \
  -d onjourney_link
```

**⚠️ Important:**
- Username: `onjourney` (bukan `postgres`)
- Database: `onjourney_link` (bukan `link_shorner`)
- Pastikan security group sudah di-update untuk allow access

**Output:**
```
[Paste output dari connection test di sini]
```

---

### 18. Database Migration ⏳ PENDING

**Status:** ⏳ Pending

- [ ] Auto-migration executed on first app start
- [ ] Tables created:
  - [ ] `admin_users`
  - [ ] `api_tokens`
  - [ ] `links`
- [ ] Default admin user seeded

**Output:**
```
[Paste output dari application logs atau database query di sini]
```

---

## ✅ Phase 5: First Deployment

### 19. Manual Deployment Test ⏳ PENDING

**Status:** ⏳ Pending

- [ ] ECR image built and pushed
- [ ] Image pulled to EC2
- [ ] Container started
- [ ] Health check passed

**Deployment Command:**
```bash
export ECR_REGISTRY="577638371164.dkr.ecr.ap-southeast-1.amazonaws.com"
export IMAGE_NAME="onjourney-golink-shortner"
export IMAGE_TAG="latest"
./deploy.sh
```

**Output:**
```
[Paste output dari deployment di sini]
```

---

### 20. Health Check Verification ⏳ PENDING

**Status:** ⏳ Pending

**Health Checks:**
- [ ] Instance health: `curl http://localhost:3000/health`
- [ ] ALB health: `curl http://<alb-dns>/health`
- [ ] Target group health: All targets healthy

**Output:**
```
[Paste health check results di sini]
```

---

### 21. GitHub Actions Deployment Test ⏳ PENDING

**Status:** ⏳ Pending

- [ ] Code pushed to `main` branch
- [ ] GitHub Actions workflow triggered
- [ ] Tests passed
- [ ] Image built and pushed to ECR
- [ ] Deployed to all ASG instances
- [ ] Health checks passed

**Workflow Run:**
- [ ] Run ID: `___________________________`
- [ ] Status: `___________________________`
- [ ] Duration: `___________________________`

**Output:**
```
[Paste workflow logs atau notes di sini]
```

---

## ✅ Phase 6: Verification & Testing

### 22. Application Functionality Test ⏳ PENDING

**Status:** ⏳ Pending

**Tests:**
- [ ] Health endpoint: `GET /health` ✅
- [ ] Admin login: `GET /admin/login` ✅
- [ ] Create short link via API: `POST /api/v1/links` ✅
- [ ] Redirect test: `GET /:code` ✅
- [ ] Admin panel access: `GET /admin/dashboard` ✅

**Test Results:**
```
[Paste test results di sini]
```

---

### 23. Load Balancer Verification ⏳ PENDING

**Status:** ⏳ Pending

- [ ] ALB DNS accessible
- [ ] Traffic distributed to instances
- [ ] Health checks working
- [ ] SSL certificate (jika HTTPS): `___________________________`

**ALB Details:**
- [ ] DNS Name: `___________________________`
- [ ] Target Group: All targets healthy
- [ ] Active instances: `___________________________`

**Output:**
```
[Paste ALB verification results di sini]
```

---

### 24. Auto Scaling Test ⏳ PENDING

**Status:** ⏳ Pending

**Scale Up Test:**
- [ ] Desired capacity set to 2
- [ ] Second instance launched
- [ ] Instance healthy in target group
- [ ] Traffic distributed to both instances

**Scale Down Test:**
- [ ] Desired capacity set to 1
- [ ] One instance terminated gracefully
- [ ] Remaining instance healthy

**Output:**
```
[Paste scaling test results di sini]
```

---

## ✅ Phase 7: Monitoring & Optimization

### 25. CloudWatch Setup ⏳ PENDING

**Status:** ⏳ Pending

**Alarms Created:**
- [ ] High CPU utilization (>70%)
- [ ] Low target group healthy count
- [ ] High error rate
- [ ] Database connection issues

**Output:**
```
[Paste CloudWatch alarm configurations di sini]
```

---

### 26. Backup Configuration ⏳ PENDING

**Status:** ⏳ Pending

- [ ] RDS automated backups enabled
- [ ] Backup retention: `___________________________` days
- [ ] Backup window: `___________________________`
- [ ] Manual snapshot tested

**Output:**
```
[Paste backup configuration di sini]
```

---

## 📝 Notes & Issues

### Important Notes:
- **ECR repository name:** `onjourney-golink-shortner` (bukan `golink-shorner`)
  - ✅ Workflow dan scripts sudah di-update
  
- **RDS Database Configuration:**
  - Database name: `onjourney_link` (bukan `link_shorner` seperti di dokumentasi)
  - Username: `onjourney` (bukan `postgres`)
  - Password: `R8o3Y3aLQWVb` ✅ Updated 2025-12-30
  - Endpoint: `rds-onj-primary.c7qw6oy402sj.ap-southeast-1.rds.amazonaws.com`
  - VPC: `VPC-ONJ` (vpc-07bbbdd4033765409)
  - Security Group: `db-security-group` (sg-0a6af115df3e43cdc)
  
- **Target Group Configuration:**
  - Target Group name: `onjourney-golink-shortner-tg` (bukan `golink-shorner-tg`)
  - ARN: `arn:aws:elasticloadbalancing:ap-southeast-1:577638371164:targetgroup/onjourney-golink-shortner-tg/5374847abd875d01`
  - Protocol:Port: HTTP: 80 ⚠️ (perlu verify apakah perlu update ke port 3000)
  - VPC: `VPC-ONJ` (vpc-07bbbdd4033765409) ✅ Same as RDS
  - ✅ Sudah di-attach ke ALB via listener
  
- **Application Load Balancer Configuration:**
  - ALB name: `onjourney-golink-shortner-alb` (bukan `golink-shorner-alb`)
  - ARN: `arn:aws:elasticloadbalancing:ap-southeast-1:577638371164:loadbalancer/app/onjourney-golink-shortner-alb/2ad555672cd7e3c6`
  - DNS: `onjourney-golink-shortner-alb-1532011075.ap-southeast-1.elb.amazonaws.com`
  - Security Group: `sg-0ad2cbd7ab9780644` (alb-security-group) ✅
  - VPC: `VPC-ONJ` (vpc-07bbbdd4033765409) ✅ Same as RDS and Target Group
  - Subnets: `subnet-07c21a6b00297f3c9`, `subnet-09b382f4141ee1399` (sama dengan ASG subnets) ✅
  - Status: Provisioning (tunggu sampai Active)
  - ✅ Listener configured: HTTP (80) → Forward to `onjourney-golink-shortner-tg` (Weight: 100%, Stickiness: Off)
  
- **Auto Scaling Group Configuration:**
  - ASG name: `onjourney-golink-asg` (bukan `golink-shorner-asg`)
  - ARN: `arn:aws:autoscaling:ap-southeast-1:577638371164:autoScalingGroup:091b21fc-8aab-4d7d-9515-77e0e5fd406f:autoScalingGroupName/onjourney-golink-asg`
  - Launch Template: `onjourney-golink-shortner` (lt-02dc4a959747d21b5) ✅
  - Capacity: Min 1, Desired 1, Max 2 ✅
  - Health check: EC2, ELB ✅
  - Health check grace period: 300 seconds ✅
  - VPC: `VPC-ONJ` (vpc-07bbbdd4033765409) ✅ Same as RDS, Target Group, and ALB
  - Subnets: `subnet-07c21a6b00297f3c9` (ap-southeast-1a), `subnet-09b382f4141ee1399` (ap-southeast-1b) ✅ Same as ALB subnets
  - Target Group: `onjourney-golink-shortner-tg` ✅ Attached
  - Date created: Fri Jan 02 2026 10:33:07 GMT+0800
  
- **⚠️ Action Required:**
  - ✅ Configure ALB listener (HTTP 80 → Target Group) - **COMPLETED**
  - ✅ Setup Launch Template - **COMPLETED** (`lt-02dc4a959747d21b5`)
  - ✅ IAM Role - **COMPLETED** (`EC2RoleForSSM` dengan semua policies yang diperlukan)
  - ✅ Setup Auto Scaling Group - **COMPLETED** (`onjourney-golink-asg`)
  - **Wait for Instance Launch** - ASG akan launch instance otomatis (desired capacity: 1)
  - **Verify Instance Registration** - Pastikan instance ter-register ke Target Group setelah launch
  - **Verify Launch Template IAM Role** - Pastikan `EC2RoleForSSM` sudah di-attach ke Launch Template
  - ✅ EC2 Security Group (`sg-083aa1a4be548f2ff`) - **CONFIGURED CORRECTLY**
    - ✅ HTTP (3000) from ALB security group (`sg-0ad2cbd7ab9780644`) - **CONFIGURED CORRECTLY**
    - ✅ SSH (22) rule removed - **USING SSM INSTEAD** (more secure)
    - **Access Method:** AWS Systems Manager Session Manager (`aws ssm start-session --target <instance-id>`)
    - **IAM Permission:** Already configured in `EC2RoleForSSM` (`AmazonSSMManagedInstanceCore` policy)
  - ✅ Update RDS security group - **COMPLETED** (PostgreSQL 5432 from EC2 security group configured)
  - Pastikan EC2 instances di VPC yang sama (VPC-ONJ) ✅ (sudah di-configure di ASG)
  - Update aplikasi untuk menggunakan database name dan username yang benar
  - Verify Target Group port (80 vs 3000) - mungkin perlu update ke 3000 jika aplikasi berjalan di port 3000
  - ✅ Verify ALB Security Group Rules - **COMPLETED** (HTTP 80 dan HTTPS 443 configured)
  - Wait for ALB status to change from "Provisioning" to "Active"
  - Verify Launch Template User data script
  - ✅ Port 8080 di ALB security group digunakan oleh aplikasi lain (tidak perlu dihapus)

### Issues Encountered:
```
[Document any issues or errors encountered during deployment]
```

### Solutions Applied:
```
- Updated workflow dan scripts untuk menggunakan ECR repository name yang benar
- Documented RDS configuration dengan database name dan username yang berbeda
```

### Next Steps:
- [ ] Update workflow untuk menggunakan ECR repository name yang benar
- [ ] Setup custom domain (opsional)
- [ ] Setup SSL certificate untuk HTTPS (opsional)
- [ ] Configure auto-scaling policies (opsional)
- [ ] Setup CloudWatch dashboards (opsional)

---

## 📊 Progress Summary

**Overall Progress:** 9/26 steps completed (34.6%)

**Phase Completion:**
- ✅ Phase 1 (AWS Resources): 7/9 (78%)
  - ✅ ECR Repository
  - ✅ RDS Database
  - ✅ Target Group
  - ✅ Application Load Balancer
  - ✅ Launch Template
  - ✅ IAM Role untuk EC2
  - ✅ Auto Scaling Group
- ⏳ Phase 2 (EC2 Setup): 1/4 (25%)
  - ✅ Connect to First Instance
- ⏳ Phase 3 (GitHub Actions): 2/3 (67%)
  - ✅ GitHub Secrets Configuration
  - ✅ IAM Policy Verification
- ⏳ Phase 4 (Database): 0/2 (0%)
- ⏳ Phase 5 (Deployment): 0/3 (0%)
- ⏳ Phase 6 (Verification): 0/3 (0%)
- ⏳ Phase 7 (Monitoring): 0/2 (0%)

**Last Updated:** 2026-01-02

**Next Steps:**
1. ✅ **Configure ALB Listener** - **COMPLETED** (HTTP 80 → Target Group)
2. ✅ **Setup Launch Template** - **COMPLETED** (`lt-02dc4a959747d21b5`)
3. ✅ **IAM Role** - **COMPLETED** (`EC2RoleForSSM` dengan semua policies yang diperlukan)
4. ✅ **Setup Auto Scaling Group** - **COMPLETED** (`onjourney-golink-asg`)
5. **Wait for Instance Launch** - ASG akan launch instance otomatis (desired capacity: 1)
6. **Verify Instance Registration** - Pastikan instance ter-register ke Target Group
7. **Verify Launch Template IAM Role** - Pastikan `EC2RoleForSSM` sudah di-attach ke Launch Template
8. **Verify ALB Status** - Tunggu sampai status berubah dari "Provisioning" ke "Active"
9. ✅ **Verify ALB Security Group Rules** - **COMPLETED** (HTTP 80 dan HTTPS 443 sudah configured)
10. ✅ **Verify EC2 Security Group Rules** - **COMPLETED**
    - ✅ HTTP (3000) from ALB security group - **CONFIGURED CORRECTLY**
    - ✅ SSH (22) rule removed - **USING SSM INSTEAD** (more secure approach)
    - **Access Method:** AWS Systems Manager Session Manager
    - **Command:** `aws ssm start-session --target <instance-id>`
    - **Benefits:** No SSH port exposed, IAM-based access, CloudTrail audit trail
11. ✅ Update RDS security group - **COMPLETED** (PostgreSQL 5432 from EC2 security group configured)
12. Verify Target Group port configuration (80 vs 3000)
13. Setup Systems Manager Parameter Store
14. Perform initial setup script on EC2 instance
15. Copy deploy script to EC2 instance
16. Perform first deployment

---

## 🔧 Quick Commands Reference

```bash
# Check ASG instances
aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names golink-shorner-asg

# Check target group health
aws elbv2 describe-target-health \
    --target-group-arn <target-group-arn>

# Check ALB
aws elbv2 describe-load-balancers \
    --names golink-shorner-alb

# Scale ASG
aws autoscaling set-desired-capacity \
    --auto-scaling-group-name golink-shorner-asg \
    --desired-capacity 2
```

---

**Tips:**
- Update checklist ini setiap kali menyelesaikan step
- Paste output dari setiap command untuk referensi
- Document issues dan solutions untuk troubleshooting
- Check progress summary secara berkala

