# EC2 Instance Setup Troubleshooting

## Masalah: Instance belum di-setup (file project tidak ada, container tidak jalan)

Jika saat dicek via SSM:
- File project belum ada
- `docker ps` tidak menampilkan container
- Scripts directory tidak ada

Ini berarti instance **belum di-setup** dengan benar.

## Penyebab

1. **User Data tidak berjalan** - Instance baru yang dibuat tanpa User Data script
2. **User Data gagal** - User Data script error atau timeout
3. **Instance dari ASG** - ASG mungkin tidak mengirim User Data dengan benar

## Solusi

### Opsi 1: Setup Manual via SSM (Recommended)

Gunakan script `setup-instance-via-ssm.sh` untuk setup instance yang sudah running:

```bash
# Pastikan script sudah executable
chmod +x scripts/setup-instance-via-ssm.sh

# Setup instance
./scripts/setup-instance-via-ssm.sh <instance-id> <region> <s3-bucket>

# Contoh:
./scripts/setup-instance-via-ssm.sh i-0123456789abcdef0 ap-southeast-1 onjourney-asset-bucket
```

Script ini akan:
1. Download `setup-ec2.sh` dari S3
2. Install Docker, AWS CLI, jq
3. Setup Nginx
4. Create directories
5. Setup `.env` file dari Parameter Store

### Opsi 2: Verifikasi Setup Instance

Gunakan script `verify-instance-setup.sh` untuk cek status instance:

```bash
chmod +x scripts/verify-instance-setup.sh
./scripts/verify-instance-setup.sh <instance-id>
```

Script ini akan menampilkan:
- OS information
- Docker status
- AWS CLI status
- Directory structure
- `.env` file status
- Nginx status
- Container status

### Opsi 3: Pastikan Scripts di S3

Pastikan semua script sudah di-upload ke S3:

```bash
# Upload semua scripts ke S3
./scripts/upload-to-s3.sh
```

Scripts yang harus ada di S3:
- `s3://onjourney-asset-bucket/scripts/setup-ec2.sh`
- `s3://onjourney-asset-bucket/scripts/deploy.sh`
- `s3://onjourney-asset-bucket/scripts/setup-nginx-reverse-proxy.sh`

### Opsi 4: Setup via SSM Manual

Jika script tidak tersedia, setup manual via SSM:

```bash
# 1. Connect via SSM
aws ssm start-session --target <instance-id>

# 2. Di dalam session, jalankan:
sudo su
mkdir -p /home/ec2-user/scripts
cd /home/ec2-user/scripts

# 3. Download setup script
aws s3 cp s3://onjourney-asset-bucket/scripts/setup-ec2.sh .
chmod +x setup-ec2.sh
./setup-ec2.sh
```

## Checklist Setup Instance

Setelah setup, instance harus memiliki:

- [ ] Docker installed dan running
- [ ] AWS CLI installed
- [ ] jq installed
- [ ] Nginx installed dan configured
- [ ] Directory `/home/ec2-user/scripts/` exists
- [ ] File `/home/ec2-user/.env` exists dengan credentials dari Parameter Store
- [ ] SSM agent online

## Verifikasi Setup

```bash
# Via SSM command
aws ssm send-command \
  --instance-ids <instance-id> \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["docker --version", "aws --version", "jq --version", "ls -la /home/ec2-user/"]' \
  --region ap-southeast-1

# Check command output
aws ssm get-command-invocation \
  --command-id <command-id> \
  --instance-id <instance-id> \
  --region ap-southeast-1 \
  --query 'StandardOutputContent' \
  --output text
```

## Update Launch Template User Data

Untuk instance baru, pastikan Launch Template memiliki User Data yang benar:

```bash
# Lihat User Data saat ini
aws ec2 describe-launch-template-versions \
  --launch-template-id <launch-template-id> \
  --region ap-southeast-1 \
  --query 'LaunchTemplateVersions[0].LaunchTemplateData.UserData' \
  --output text | base64 -d
```

User Data harus:
1. Download `setup-ec2.sh` dari S3
2. Run setup script
3. Setup `.env` dari Parameter Store

Lihat `docs/AWS_SETUP.md` untuk contoh User Data script yang lengkap.
