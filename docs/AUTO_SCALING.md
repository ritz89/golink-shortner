# Auto Scaling Group Configuration

Dokumentasi untuk konfigurasi Auto Scaling Group dengan Application Load Balancer.

## Architecture Overview

```
Internet
   ↓
Application Load Balancer (ALB)
   ↓
Target Group (Health Check: /health)
   ↓
Auto Scaling Group (Min: 1, Max: 2)
   ├── Instance 1 (t4g.small)
   └── Instance 2 (t4g.small) [optional]
```

## Benefits

1. **High Availability**: Jika 1 instance down, ALB route traffic ke instance lain
2. **Auto Recovery**: ASG otomatis replace unhealthy instances
3. **Load Distribution**: ALB distribute traffic secara merata
4. **Zero Downtime Deployment**: Deploy ke instances secara rolling

## Configuration Summary

### Auto Scaling Group
- **Name**: `golink-shorner-asg`
- **Min Size**: 1
- **Desired Capacity**: 1
- **Max Size**: 2
- **Health Check Type**: ELB (ALB health check)
- **Health Check Grace Period**: 300 seconds (5 minutes)

### Launch Template
- **Name**: `golink-shorner-template`
- **AMI**: Amazon Linux 2023 (ARM64)
- **Instance Type**: t4g.small
- **User Data**: Setup script untuk install Docker, AWS CLI, dll

### Application Load Balancer
- **Name**: `golink-shorner-alb`
- **Scheme**: Internet-facing
- **Listeners**: HTTP (80), HTTPS (443) optional
- **Target Group**: `golink-shorner-tg`
- **Health Check**: HTTP GET /health on port 3000

### Target Group
- **Name**: `golink-shorner-tg`
- **Protocol**: HTTP
- **Port**: 3000
- **Health Check Path**: `/health`
- **Health Check Interval**: 30 seconds
- **Healthy Threshold**: 2
- **Unhealthy Threshold**: 3

## Deployment Flow

1. **GitHub Actions** build & push Docker image ke ECR
2. **Get ASG Instances**: Query semua instances di ASG
3. **Deploy to Each Instance**: 
   - SSH ke setiap instance
   - Pull latest image dari ECR
   - Restart container
   - Health check
4. **Verify ALB**: Check ALB health endpoint

## Manual Scaling

### Scale Up (Add Instance)

```bash
# Scale to 2 instances
aws autoscaling set-desired-capacity \
    --auto-scaling-group-name golink-shorner-asg \
    --desired-capacity 2 \
    --honor-cooldown
```

### Scale Down (Remove Instance)

```bash
# Scale to 1 instance
aws autoscaling set-desired-capacity \
    --auto-scaling-group-name golink-shorner-asg \
    --desired-capacity 1 \
    --honor-cooldown
```

## Auto-Scaling Policies (Optional)

### CPU-Based Scaling

```bash
# Create CloudWatch alarm for high CPU
aws cloudwatch put-metric-alarm \
    --alarm-name golink-shorner-high-cpu \
    --alarm-description "Scale up when CPU > 70%" \
    --metric-name CPUUtilization \
    --namespace AWS/EC2 \
    --statistic Average \
    --period 300 \
    --evaluation-periods 2 \
    --threshold 70 \
    --comparison-operator GreaterThanThreshold \
    --dimensions Name=AutoScalingGroupName,Value=golink-shorner-asg

# Attach scale-up policy
aws autoscaling put-scaling-policy \
    --auto-scaling-group-name golink-shorner-asg \
    --policy-name scale-up-cpu \
    --policy-type SimpleScaling \
    --scaling-adjustment 1 \
    --adjustment-type ChangeInCapacity \
    --cooldown 300
```

## Health Checks

### ALB Health Check
- **Path**: `/health`
- **Port**: 3000
- **Protocol**: HTTP
- **Interval**: 30 seconds
- **Timeout**: 5 seconds
- **Healthy Threshold**: 2 consecutive successes
- **Unhealthy Threshold**: 3 consecutive failures

### Instance Health Check
- **Type**: ELB (uses ALB health check)
- **Grace Period**: 300 seconds (5 minutes)
- Unhealthy instances akan di-terminate dan di-replace otomatis

## Monitoring

### Check ASG Status

```bash
# List instances
aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names golink-shorner-asg \
    --query 'AutoScalingGroups[0].Instances[*].[InstanceId,HealthStatus,LifecycleState]' \
    --output table
```

### Check Target Group Health

```bash
# Get target group ARN
TG_ARN=$(aws elbv2 describe-target-groups \
    --names golink-shorner-tg \
    --query 'TargetGroups[0].TargetGroupArn' \
    --output text)

# Check health
aws elbv2 describe-target-health \
    --target-group-arn $TG_ARN \
    --query 'TargetHealthDescriptions[*].[Target.Id,TargetHealth.State,TargetHealth.Reason]' \
    --output table
```

### Check ALB Status

```bash
# Get ALB DNS
ALB_DNS=$(aws elbv2 describe-load-balancers \
    --names golink-shorner-alb \
    --query 'LoadBalancers[0].DNSName' \
    --output text)

# Health check
curl http://$ALB_DNS/health
```

## Troubleshooting

### Instance tidak healthy

```bash
# Check instance logs
ssh ec2-user@<instance-ip>
docker logs golink-shorner

# Check health endpoint
curl http://localhost:3000/health

# Check target group health
aws elbv2 describe-target-health --target-group-arn <arn>
```

### ASG tidak scale up

- Check CloudWatch alarms
- Verify scaling policies attached
- Check ASG activity history:
  ```bash
  aws autoscaling describe-scaling-activities \
      --auto-scaling-group-name golink-shorner-asg
  ```

### Deployment failed ke beberapa instances

- Check SSH connectivity
- Verify IAM role permissions
- Check ECR access
- Review GitHub Actions logs

## Best Practices

1. ✅ **Always deploy via ALB DNS**, bukan direct instance IP
2. ✅ **Monitor target group health** sebelum dan setelah deployment
3. ✅ **Use rolling deployment** untuk zero downtime
4. ✅ **Test health endpoint** sebelum marking instance healthy
5. ✅ **Setup CloudWatch alarms** untuk monitoring
6. ✅ **Keep min=1** untuk cost efficiency
7. ✅ **Max=2** untuk high availability tanpa over-provisioning

## Cost Optimization

- **Min=1**: Always running 1 instance (~$15/month)
- **Max=2**: Scale up hanya saat diperlukan
- **ALB**: Fixed cost ~$20/month (tidak naik dengan instances)
- **Total Base**: ~$35/month (1 instance + ALB)
- **Total Peak**: ~$50/month (2 instances + ALB)

---

Untuk setup lengkap, lihat [AWS_SETUP.md](AWS_SETUP.md)

