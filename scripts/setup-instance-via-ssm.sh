#!/bin/bash
# Script to setup EC2 instance via SSM (for existing instances that weren't setup via User Data)

set -e

INSTANCE_ID="${1:-}"
AWS_REGION="${AWS_REGION:-ap-southeast-1}"
S3_BUCKET="${S3_BUCKET:-onjourney-asset-bucket}"

if [ -z "$INSTANCE_ID" ]; then
  echo "Usage: $0 <instance-id> [region] [s3-bucket]"
  echo "Example: $0 i-0123456789abcdef0 ap-southeast-1 onjourney-asset-bucket"
  exit 1
fi

echo "=========================================="
echo "Setting up EC2 Instance via SSM"
echo "=========================================="
echo "Instance ID: $INSTANCE_ID"
echo "Region: $AWS_REGION"
echo "S3 Bucket: $S3_BUCKET"
echo ""

# Check instance state
INSTANCE_STATE=$(aws ec2 describe-instances \
  --instance-ids "$INSTANCE_ID" \
  --region "$AWS_REGION" \
  --query 'Reservations[0].Instances[0].State.Name' \
  --output text 2>/dev/null || echo "Unknown")

if [ "$INSTANCE_STATE" != "running" ]; then
  echo "❌ Instance is not running. Current state: $INSTANCE_STATE"
  exit 1
fi

# Check SSM agent
echo "Checking SSM agent status..."
SSM_STATUS=$(aws ssm describe-instance-information \
  --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
  --region "$AWS_REGION" \
  --query 'InstanceInformationList[0].PingStatus' \
  --output text 2>/dev/null || echo "Unknown")

if [ "$SSM_STATUS" != "Online" ]; then
  echo "⚠️  SSM agent is not online. Status: $SSM_STATUS"
  echo "   Waiting for SSM agent to be ready..."
  for i in {1..18}; do
    sleep 10
    SSM_STATUS=$(aws ssm describe-instance-information \
      --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
      --region "$AWS_REGION" \
      --query 'InstanceInformationList[0].PingStatus' \
      --output text 2>/dev/null || echo "Unknown")
    if [ "$SSM_STATUS" == "Online" ]; then
      echo "✅ SSM agent is now online"
      break
    fi
    echo "  Attempt $i/18: SSM agent not ready yet..."
  done
  
  if [ "$SSM_STATUS" != "Online" ]; then
    echo "❌ SSM agent is not online after waiting. Status: $SSM_STATUS"
    exit 1
  fi
fi

echo "✅ SSM agent is online"
echo ""

# Setup commands - download and run setup-ec2.sh from S3
SETUP_COMMANDS="
echo '==========================================' && \
echo 'Starting EC2 Instance Setup' && \
echo '==========================================' && \
echo '' && \
echo '1. Creating directories...' && \
mkdir -p /home/ec2-user/scripts && \
echo '✅ Directories created' && \
echo '' && \
echo '2. Downloading setup-ec2.sh from S3...' && \
if aws s3 cp s3://${S3_BUCKET}/scripts/setup-ec2.sh /home/ec2-user/scripts/setup-ec2.sh 2>/dev/null; then \
  chmod +x /home/ec2-user/scripts/setup-ec2.sh && \
  echo '✅ setup-ec2.sh downloaded and made executable' && \
  echo '' && \
  echo '3. Running setup-ec2.sh...' && \
  /home/ec2-user/scripts/setup-ec2.sh && \
  echo '' && \
  echo '✅ Setup completed successfully!' && \
  echo '' && \
  echo '4. Verifying setup...' && \
  echo '   Docker:' && \
  docker --version && \
  echo '   AWS CLI:' && \
  aws --version && \
  echo '   jq:' && \
  jq --version && \
  echo '   Nginx:' && \
  systemctl status nginx --no-pager -l | head -5 || echo '   Nginx not running (this is OK if not configured yet)' && \
  echo '' && \
  echo '✅ Verification complete!' && \
  echo '=========================================='; \
else \
  echo '❌ Failed to download setup-ec2.sh from S3' && \
  echo '   Bucket: ${S3_BUCKET}' && \
  echo '   Path: scripts/setup-ec2.sh' && \
  echo '   Please ensure the file exists in S3' && \
  exit 1; \
fi
"

# Create temp file for SSM command
PARAMS_FILE=$(mktemp)
if command -v jq &> /dev/null; then
  jq -n --arg cmd "$SETUP_COMMANDS" '{commands: [$cmd]}' > "$PARAMS_FILE"
else
  python3 -c "import json, sys; json.dump({'commands': [sys.argv[1]]}, sys.stdout)" "$SETUP_COMMANDS" > "$PARAMS_FILE"
fi

# Send command via SSM
echo "Sending setup command via SSM..."
COMMAND_ID=$(aws ssm send-command \
  --instance-ids "$INSTANCE_ID" \
  --document-name "AWS-RunShellScript" \
  --parameters file://"$PARAMS_FILE" \
  --region "$AWS_REGION" \
  --query 'Command.CommandId' \
  --output text 2>&1)

rm -f "$PARAMS_FILE"

if [[ ! "$COMMAND_ID" =~ ^[a-f0-9-]{36}$ ]]; then
  echo "❌ Failed to send SSM command: $COMMAND_ID"
  exit 1
fi

echo "✅ Command sent successfully: $COMMAND_ID"
echo "Waiting for setup to complete (this may take 2-5 minutes)..."
echo ""

# Wait for command to complete
STATUS="InProgress"
for i in {1..60}; do
  sleep 5
  STATUS=$(aws ssm get-command-invocation \
    --command-id "$COMMAND_ID" \
    --instance-id "$INSTANCE_ID" \
    --region "$AWS_REGION" \
    --query 'Status' \
    --output text 2>/dev/null || echo "InProgress")
  
  if [ "$STATUS" == "Success" ] || [ "$STATUS" == "Failed" ] || [ "$STATUS" == "Cancelled" ] || [ "$STATUS" == "TimedOut" ]; then
    break
  fi
  
  if [ $((i % 6)) -eq 0 ]; then
    echo "  Still running... ($i/60 - Status: $STATUS)"
  fi
done

# Get output
echo ""
echo "=========================================="
echo "Setup Output:"
echo "=========================================="
OUTPUT=$(aws ssm get-command-invocation \
  --command-id "$COMMAND_ID" \
  --instance-id "$INSTANCE_ID" \
  --region "$AWS_REGION" \
  --query 'StandardOutputContent' \
  --output text 2>/dev/null || echo "No output")
echo "$OUTPUT"

echo ""
echo "=========================================="
echo "Error Output (if any):"
echo "=========================================="
ERROR_OUTPUT=$(aws ssm get-command-invocation \
  --command-id "$COMMAND_ID" \
  --instance-id "$INSTANCE_ID" \
  --region "$AWS_REGION" \
  --query 'StandardErrorContent' \
  --output text 2>/dev/null || echo "No errors")
echo "$ERROR_OUTPUT"

echo ""
echo "=========================================="
echo "Status: $STATUS"
echo "=========================================="

if [ "$STATUS" == "Success" ]; then
  echo "✅ Instance setup completed successfully!"
  echo ""
  echo "Next steps:"
  echo "  1. Verify setup: ./scripts/verify-instance-setup.sh $INSTANCE_ID"
  echo "  2. Deploy application: Trigger GitHub Actions workflow or run deployment manually"
else
  echo "❌ Instance setup failed. Please check the error output above."
  exit 1
fi
