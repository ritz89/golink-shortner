# GitHub Actions Workflows

## deploy.yml

Workflow untuk automated deployment ke AWS EC2.

### Trigger

- Push ke branch `main`
- Manual trigger via `workflow_dispatch`

### Jobs

1. **test**: Run Go tests
2. **build-and-push**: Build Docker image untuk ARM64 dan push ke ECR
3. **deploy**: 
   - Get instances dari Auto Scaling Group (jika ASG_NAME di-set)
   - Deploy ke semua instances di ASG via SSH
   - Atau deploy ke single EC2 (fallback jika ASG_NAME tidak di-set)
   - Verify ALB health (jika ALB_DNS di-set)

### Required Secrets

Setup di GitHub → Settings → Secrets and variables → Actions:

| Secret | Description |
|--------|-------------|
| `AWS_ACCESS_KEY_ID` | AWS access key untuk akses ECR dan ASG |
| `AWS_SECRET_ACCESS_KEY` | AWS secret key |
| `ASG_NAME` | Auto Scaling Group name (e.g., `golink-shorner-asg`) |
| `EC2_HOST` | EC2 public IP atau hostname (fallback untuk single instance) |
| `EC2_USER` | SSH username (biasanya `ec2-user`) |
| `EC2_SSH_KEY` | Private SSH key content (dari .pem file) |
| `ALB_DNS` | ALB DNS name (opsional, untuk health check verification) |

### Setup SSH Key

```bash
# Generate SSH key
ssh-keygen -t rsa -b 4096 -C "github-actions" -f github-actions-key

# Copy public key ke EC2
ssh-copy-id -i github-actions-key.pub ec2-user@<ec2-ip>

# Copy private key untuk GitHub Secret
cat github-actions-key
# Copy seluruh output termasuk -----BEGIN dan -----END
```

### Customization

Edit `.github/workflows/deploy.yml` untuk:
- Change AWS region
- Change ECR repository name
- Change branch trigger
- Add additional steps

### Troubleshooting

**Workflow failed:**
- Check secrets sudah di-set dengan benar
- Verify SSH key format (harus include BEGIN/END lines)
- Check EC2 security group allows SSH from GitHub Actions IPs
- Verify IAM permissions untuk ECR access

**Deployment failed:**
- Check EC2 logs: `docker logs golink-shorner`
- Verify .env file exists di EC2
- Check database connectivity
- Verify ECR image exists
- Check ASG instances status
- Verify SSH key works untuk semua instances
- Check target group health di ALB

**ASG Deployment:**
- Workflow akan otomatis detect semua instances di ASG
- Deploy ke setiap instance secara sequential
- Jika salah satu instance gagal, workflow akan fail
- Check GitHub Actions logs untuk detail per instance

