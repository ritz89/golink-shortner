# Pentingnya User Data di Launch Template

## Kenapa User Data WAJIB diisi?

User Data script di Launch Template adalah **cara terbaik** untuk memastikan instance ter-setup dengan benar saat pertama kali di-launch.

### ✅ Benefits User Data:

1. **Otomatis Setup**
   - Berjalan **otomatis** saat instance pertama kali di-launch
   - Tidak perlu setup manual via SSM
   - Instance siap untuk deployment tanpa intervensi manual

2. **Konsistensi**
   - Semua instance baru dari ASG akan memiliki setup yang sama
   - Tidak ada perbedaan konfigurasi antar instance
   - Memastikan semua dependencies terinstall

3. **Reliability**
   - Setup berjalan sebelum instance digunakan
   - Tidak ada race condition dengan deployment
   - Instance sudah siap saat ASG health check dimulai

4. **Maintainability**
   - Update sekali di Launch Template, semua instance baru dapat update
   - Centralized configuration
   - Version control via Launch Template versions

## Apa yang Harus Ada di User Data?

User Data script harus menginstall dan configure:

- [x] **Docker** - untuk run container
- [x] **AWS CLI** - untuk access ECR dan Parameter Store
- [x] **jq** - untuk JSON parsing
- [x] **Nginx** - untuk reverse proxy (port 80 → 3000)
- [x] **Directories** - `/home/ec2-user/scripts/`, `/home/ec2-user/app/`
- [x] **.env file** - dari Parameter Store
- [x] **Nginx configuration** - reverse proxy setup
- [x] **Deploy script** - download dari S3

## Pendekatan User Data

### Opsi 1: Download setup-ec2.sh dari S3 (Recommended)

**Pros:**
- ✅ Lebih maintainable - update script di S3, instance baru otomatis dapat update
- ✅ Script terpusat - tidak perlu update Launch Template setiap kali ada perubahan
- ✅ Reusable - script yang sama bisa digunakan untuk manual setup

**Cons:**
- ⚠️ Requires S3 access
- ⚠️ Requires setup-ec2.sh sudah di-upload ke S3

**Implementation:**
```bash
#!/bin/bash
# Download dan run setup-ec2.sh dari S3
aws s3 cp s3://onjourney-asset-bucket/scripts/setup-ec2.sh /home/ec2-user/scripts/setup-ec2.sh
chmod +x /home/ec2-user/scripts/setup-ec2.sh
/home/ec2-user/scripts/setup-ec2.sh
```

### Opsi 2: Include Setup Langsung di User Data

**Pros:**
- ✅ Tidak perlu S3 access
- ✅ Semua setup langsung di User Data

**Cons:**
- ⚠️ Perlu update Launch Template jika ada perubahan setup
- ⚠️ User Data script menjadi panjang
- ⚠️ Tidak reusable untuk manual setup

## Generate User Data Script

Gunakan helper script untuk generate User Data:

```bash
# Generate User Data script
chmod +x scripts/generate-user-data.sh
./scripts/generate-user-data.sh onjourney-asset-bucket ap-southeast-1 > user-data.txt

# Copy output ke Launch Template User Data field
```

## Update Launch Template User Data

### Via AWS Console:

1. Buka **EC2 Console** → **Launch Templates**
2. Pilih Launch Template `onjourney-golink-shortner`
3. Klik **Actions** → **Modify template (Create new version)**
4. Scroll ke **Advanced details** → **User data**
5. Paste User Data script
6. Klik **Create template version**
7. Set sebagai **Default version** jika perlu

### Via AWS CLI:

```bash
# Generate User Data script
./scripts/generate-user-data.sh onjourney-asset-bucket ap-southeast-1 > user-data.txt

# Base64 encode (required by AWS)
base64 -i user-data.txt > user-data-base64.txt

# Update Launch Template
aws ec2 create-launch-template-version \
    --launch-template-id lt-02dc4a959747d21b5 \
    --launch-template-data file://user-data-base64.txt \
    --source-version 1 \
    --region ap-southeast-1
```

## Verification

Setelah instance di-launch dengan User Data:

```bash
# Verify setup via SSM
./scripts/verify-instance-setup.sh <instance-id>
```

Expected output:
- ✅ Docker installed dan running
- ✅ AWS CLI installed
- ✅ jq installed
- ✅ Nginx installed dan configured
- ✅ Directories created
- ✅ .env file exists dengan credentials
- ✅ Deploy script downloaded

## Troubleshooting

### User Data tidak berjalan:

1. **Check User Data di Launch Template:**
   ```bash
   aws ec2 describe-launch-template-versions \
       --launch-template-id lt-02dc4a959747d21b5 \
       --query 'LaunchTemplateVersions[0].LaunchTemplateData.UserData' \
       --output text | base64 -d
   ```

2. **Check User Data logs:**
   ```bash
   # Connect via SSM
   aws ssm start-session --target <instance-id>
   
   # Check logs
   sudo cat /var/log/cloud-init-output.log
   sudo cat /var/log/cloud-init.log
   ```

3. **Check instance metadata:**
   ```bash
   curl http://169.254.169.254/latest/user-data
   ```

### User Data gagal:

- Check error di `/var/log/cloud-init-output.log`
- Verify S3 access (jika menggunakan Opsi 1)
- Verify Parameter Store access
- Check IAM role permissions

## Best Practices

1. **Always include User Data** di Launch Template
2. **Test User Data** dengan launch test instance
3. **Version control** User Data script
4. **Monitor logs** untuk instance baru
5. **Verify setup** setelah instance di-launch
6. **Update Launch Template** jika ada perubahan setup

## Summary

**User Data di Launch Template adalah WAJIB** untuk memastikan:
- ✅ Instance ter-setup otomatis saat di-launch
- ✅ Semua dependencies terinstall
- ✅ Instance siap untuk deployment
- ✅ Konsistensi antar instance
- ✅ Tidak perlu setup manual

**Tanpa User Data:**
- ❌ Instance kosong saat di-launch
- ❌ Perlu setup manual via SSM
- ❌ Tidak konsisten antar instance
- ❌ Deployment akan gagal karena dependencies tidak ada
