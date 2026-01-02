# Disable Public IP untuk EC2 Instances di belakang ALB

## Mengapa Instance Tidak Perlu Public IP?

Ketika instance berada di belakang Application Load Balancer (ALB):

1. **ALB sudah memiliki IP publik** - Traffic dari internet masuk ke ALB
2. **Instance hanya perlu private IP** - ALB berkomunikasi dengan instance via private network (VPC)
3. **Security** - Instance tidak langsung accessible dari internet (lebih aman)
4. **Cost** - Sedikit menghemat cost (meskipun kecil)
5. **Best Practice** - AWS best practice untuk instance di belakang load balancer

## Cara Disable Public IP di Launch Template

### Via AWS Console

1. Buka **EC2 Console** → **Launch Templates**
2. Pilih Launch Template: `onjourney-golink-shortner` (lt-02dc4a959747d21b5)
3. Klik **Actions** → **Modify template (Create new version)**
4. Di bagian **Network settings**:
   - **Auto-assign public IP**: Pilih **Disable** ✅
5. Klik **Create template version**
6. Set versi baru sebagai **Default version**

### Via AWS CLI

```bash
# Get current Launch Template configuration
aws ec2 describe-launch-template-versions \
    --launch-template-id lt-02dc4a959747d21b5 \
    --region ap-southeast-1 \
    --query 'LaunchTemplateVersions[0].LaunchTemplateData' \
    --output json > current-lt-config.json

# Modify the JSON to disable public IP
# Set: "NetworkInterfaces[0].AssociatePublicIpAddress": false
# Or remove "AssociatePublicIpAddress" field entirely

# Create new version
aws ec2 create-launch-template-version \
    --launch-template-id lt-02dc4a959747d21b5 \
    --source-version '$Latest' \
    --launch-template-data file://modified-lt-config.json \
    --region ap-southeast-1

# Set as default version
aws ec2 modify-launch-template \
    --launch-template-id lt-02dc4a959747d21b5 \
    --default-version <new-version-number> \
    --region ap-southeast-1
```

### Via Script (Recommended)

```bash
# Script untuk disable public IP di Launch Template
./scripts/disable-public-ip-launch-template.sh
```

## Verifikasi

Setelah update Launch Template:

1. **Check Launch Template version:**
```bash
aws ec2 describe-launch-template-versions \
    --launch-template-id lt-02dc4a959747d21b5 \
    --region ap-southeast-1 \
    --query 'LaunchTemplateVersions[0].LaunchTemplateData.NetworkInterfaces[0].AssociatePublicIpAddress' \
    --output text
```

**Expected:** `false` atau `None` (tidak ada field)

2. **Check existing instances:**
```bash
# Existing instances mungkin masih punya public IP
# Instance baru yang di-launch setelah update akan tidak punya public IP
aws ec2 describe-instances \
    --instance-ids <instance-id> \
    --region ap-southeast-1 \
    --query 'Reservations[0].Instances[0].[PublicIpAddress,PrivateIpAddress]' \
    --output table
```

3. **Test connectivity:**
- Instance tanpa public IP masih bisa:
  - ✅ Akses internet via NAT Gateway (jika ada)
  - ✅ Download dari S3, ECR, Parameter Store
  - ✅ Diterima traffic dari ALB
  - ✅ SSM Session Manager tetap bekerja

## Important Notes

### NAT Gateway Requirement

Jika instance perlu akses internet (untuk download dari S3, ECR, dll), pastikan:

1. **Subnet memiliki NAT Gateway** - Instance di private subnet perlu NAT Gateway untuk akses internet
2. **Route Table** - Subnet route table harus route `0.0.0.0/0` ke NAT Gateway (bukan Internet Gateway)

**Check:**
```bash
# Check subnet route table
aws ec2 describe-route-tables \
    --filters "Name=association.subnet-id,Values=subnet-07c21a6b00297f3c9" \
    --region ap-southeast-1 \
    --query 'RouteTables[0].Routes[*].[DestinationCidrBlock,GatewayId]' \
    --output table
```

### SSM Session Manager

SSM Session Manager **tidak memerlukan public IP**. SSM agent berkomunikasi dengan AWS via:
- Private network → NAT Gateway → Internet → AWS SSM service
- Atau via VPC endpoints (jika configured)

### ECR Access

ECR access via NAT Gateway atau VPC endpoints:
- Instance di private subnet bisa pull images dari ECR via NAT Gateway
- Atau via VPC endpoints untuk ECR (lebih cost-effective untuk high traffic)

## Migration Strategy

Jika instance existing masih punya public IP:

1. **Update Launch Template** - Disable public IP untuk instance baru
2. **Existing instances** - Biarkan saja (akan diganti saat ASG scale in/out)
3. **Atau replace manually:**
   - Terminate instance dengan public IP
   - ASG akan launch instance baru tanpa public IP

## Summary

✅ **Disable Public IP** untuk instance di belakang ALB adalah:
- ✅ Best practice
- ✅ Lebih secure
- ✅ Menghemat cost sedikit
- ✅ Tidak mempengaruhi functionality (dengan NAT Gateway)

❌ **Jangan disable jika:**
- ❌ Subnet tidak punya NAT Gateway
- ❌ Instance perlu direct internet access tanpa NAT Gateway
- ❌ Ada requirement khusus untuk public IP

