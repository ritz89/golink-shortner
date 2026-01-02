# Quick Fix: Setup Instance yang Belum di-Setup

## Masalah
- File project tidak ada di instance
- `docker ps` tidak menampilkan container
- Instance belum di-setup dengan benar

## Solusi Cepat

### Step 1: Upload Scripts ke S3

```bash
# Pastikan scripts sudah di-upload ke S3
chmod +x scripts/upload-to-s3.sh
./scripts/upload-to-s3.sh
```

### Step 2: Verifikasi Instance

```bash
# Cek status instance
chmod +x scripts/verify-instance-setup.sh
./scripts/verify-instance-setup.sh <instance-id>

# Contoh:
./scripts/verify-instance-setup.sh i-056ebd5ce69f0004d
```

### Step 3: Setup Instance

```bash
# Setup instance via SSM
chmod +x scripts/setup-instance-via-ssm.sh
./scripts/setup-instance-via-ssm.sh <instance-id> <region> <s3-bucket>

# Contoh:
./scripts/setup-instance-via-ssm.sh i-056ebd5ce69f0004d ap-southeast-1 onjourney-asset-bucket
```

Script ini akan:
1. ✅ Install Docker
2. ✅ Install AWS CLI
3. ✅ Install jq
4. ✅ Install dan configure Nginx
5. ✅ Create directories
6. ✅ Setup `.env` file dari Parameter Store

### Step 4: Verifikasi Setup

```bash
# Verifikasi setup berhasil
./scripts/verify-instance-setup.sh <instance-id>
```

### Step 5: Deploy Application

Setelah setup selesai, deploy aplikasi:

**Via GitHub Actions:**
- Push ke branch `main` untuk trigger deployment

**Atau Manual:**
```bash
# Connect via SSM
aws ssm start-session --target <instance-id>

# Di dalam session
cd /home/ec2-user/scripts
export ECR_REGISTRY="<your-ecr-registry>"
export IMAGE_NAME="onjourney-golink-shortner"
export IMAGE_TAG="latest"
export AWS_REGION="ap-southeast-1"
./deploy.sh
```

## Checklist

Setelah setup, pastikan:
- [ ] Docker installed dan running
- [ ] AWS CLI installed
- [ ] jq installed
- [ ] Nginx installed dan configured
- [ ] Directory `/home/ec2-user/scripts/` exists
- [ ] File `/home/ec2-user/.env` exists dengan credentials
- [ ] SSM agent online

## Troubleshooting

Lihat `docs/INSTANCE_SETUP_TROUBLESHOOTING.md` untuk troubleshooting lengkap.
