# Menambahkan Name Tag ke EC2 Instances

## Masalah
Instances yang di-launch oleh Auto Scaling Group tidak memiliki Name tag, sehingga sulit untuk diidentifikasi di EC2 console.

## Solusi

### Option 1: Update Auto Scaling Group Tags (Recommended)

Tags di ASG akan otomatis di-apply ke semua instances yang di-launch oleh ASG.

#### Via AWS Console:
1. Buka **EC2 Console** → **Auto Scaling Groups**
2. Pilih ASG `onjourney-golink-asg`
3. Klik tab **Tags**
4. Klik **Add tag**
5. Isi:
   - **Key:** `Name`
   - **Value:** `golink-shortner` (atau `onjourney-golink-shortner`)
   - **Tag new instances:** ✅ (centang ini)
6. Klik **Save**

#### Via AWS CLI:
```bash
aws autoscaling create-or-update-tags \
    --tags "ResourceId=onjourney-golink-asg,ResourceType=auto-scaling-group,Key=Name,Value=golink-shortner,PropagateAtLaunch=true" \
    --region ap-southeast-1
```

### Option 2: Update Launch Template Tags

Tags di Launch Template akan di-apply ke instances yang di-launch, tapi bisa di-override oleh ASG tags.

#### Via AWS Console:
1. Buka **EC2 Console** → **Launch Templates**
2. Pilih Launch Template `onjourney-golink-shortner` (ID: `lt-02dc4a959747d21b5`)
3. Klik **Actions** → **Modify template (Create new version)**
4. Scroll ke bagian **Tags**
5. Klik **Add tag**
6. Isi:
   - **Key:** `Name`
   - **Value:** `golink-shortner`
7. Klik **Create template version**
8. Set sebagai default version jika diperlukan

### Option 3: Add Tag Manual ke Instances yang Sudah Ada

Untuk instances yang sudah di-launch, bisa add tag manual.

#### Via AWS Console:
1. Buka **EC2 Console** → **Instances**
2. Pilih instance yang ingin di-tag (misalnya `i-0f57d90d42538d286`)
3. Klik **Actions** → **Instance settings** → **Manage tags**
4. Klik **Add tag**
5. Isi:
   - **Key:** `Name`
   - **Value:** `golink-shortner-1` (atau sesuai kebutuhan)
6. Klik **Save**

#### Via AWS CLI:
```bash
# Tag single instance
aws ec2 create-tags \
    --resources i-0f57d90d42538d286 \
    --tags Key=Name,Value=golink-shortner-1 \
    --region ap-southeast-1

# Tag multiple instances
aws ec2 create-tags \
    --resources i-0f57d90d42538d286 i-03c464d5361ec294f i-0e9781b9762435b1d \
    --tags Key=Name,Value=golink-shortner \
    --region ap-southeast-1
```

## Verify Instance Count

Jika ada lebih dari 1 instance padahal desired capacity adalah 1, perlu verify:

### Check ASG Desired Capacity:
```bash
aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names onjourney-golink-asg \
    --query 'AutoScalingGroups[0].[DesiredCapacity,MinSize,MaxSize]' \
    --output table \
    --region ap-southeast-1
```

### List Instances di ASG:
```bash
aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names onjourney-golink-asg \
    --query 'AutoScalingGroups[0].Instances[*].[InstanceId,LifecycleState,HealthStatus,AvailabilityZone]' \
    --output table \
    --region ap-southeast-1
```

### List All Instances dengan t4g.small:
```bash
aws ec2 describe-instances \
    --filters "Name=instance-type,Values=t4g.small" "Name=instance-state-name,Values=running" \
    --query 'Reservations[*].Instances[*].[InstanceId,Tags[?Key==`Name`].Value|[0],LaunchTemplate.LaunchTemplateId]' \
    --output table \
    --region ap-southeast-1
```

### Check Instance Launch Template:
```bash
# Check apakah instance dari Launch Template kita
aws ec2 describe-instances \
    --instance-ids i-0f57d90d42538d286 \
    --query 'Reservations[0].Instances[0].[InstanceId,LaunchTemplate.LaunchTemplateId,LaunchTemplate.LaunchTemplateName]' \
    --output table \
    --region ap-southeast-1
```

## Terminate Instances yang Tidak Diperlukan

Jika ada instances yang tidak dari ASG kita atau tidak diperlukan:

```bash
# Hati-hati! Pastikan instance ID yang benar
aws ec2 terminate-instances \
    --instance-ids i-xxxxx \
    --region ap-southeast-1
```

**⚠️ Warning:** Pastikan instance yang akan di-terminate bukan dari ASG kita atau sudah di-backup jika diperlukan.

## Recommended Approach

**Best Practice:** Gunakan Option 1 (ASG Tags) karena:
- ✅ Tag otomatis di-apply ke semua instances baru
- ✅ Konsisten untuk semua instances
- ✅ Tidak perlu update manual setiap kali instance baru di-launch
- ✅ Bisa menggunakan dynamic values seperti `{{instance-id}}` atau `{{launch-time}}`

