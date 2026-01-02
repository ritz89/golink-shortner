#!/bin/bash
# Script to verify EC2 instance setup via SSM

set -e

INSTANCE_ID="${1:-}"
AWS_REGION="${AWS_REGION:-ap-southeast-1}"

if [ -z "$INSTANCE_ID" ]; then
  echo "Usage: $0 <instance-id>"
  echo "Example: $0 i-0123456789abcdef0"
  exit 1
fi

echo "=========================================="
echo "Verifying EC2 Instance Setup"
echo "=========================================="
echo "Instance ID: $INSTANCE_ID"
echo "Region: $AWS_REGION"
echo ""

# Check instance state
echo "1. Checking instance state..."
INSTANCE_STATE=$(aws ec2 describe-instances \
  --instance-ids "$INSTANCE_ID" \
  --region "$AWS_REGION" \
  --query 'Reservations[0].Instances[0].State.Name' \
  --output text 2>/dev/null || echo "Unknown")

echo "   Instance state: $INSTANCE_STATE"

if [ "$INSTANCE_STATE" != "running" ]; then
  echo "   ⚠️  Instance is not running. Current state: $INSTANCE_STATE"
  exit 1
fi

# Check SSM agent
echo ""
echo "2. Checking SSM agent status..."
SSM_STATUS=$(aws ssm describe-instance-information \
  --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
  --region "$AWS_REGION" \
  --query 'InstanceInformationList[0].PingStatus' \
  --output text 2>/dev/null || echo "Unknown")

echo "   SSM Status: $SSM_STATUS"

if [ "$SSM_STATUS" != "Online" ]; then
  echo "   ⚠️  SSM agent is not online. Status: $SSM_STATUS"
  echo "   This might take 1-2 minutes for new instances."
fi

# Run verification commands via SSM
echo ""
echo "3. Running verification commands via SSM..."
echo "=========================================="

VERIFY_COMMANDS="
echo '=== OS Information ===' && \
cat /etc/os-release | head -5 && \
echo '' && \
echo '=== Docker Status ===' && \
docker --version 2>/dev/null || echo 'Docker not installed' && \
docker ps -a 2>/dev/null || echo 'Docker not running' && \
echo '' && \
echo '=== AWS CLI Status ===' && \
aws --version 2>/dev/null || echo 'AWS CLI not installed' && \
echo '' && \
echo '=== jq Status ===' && \
jq --version 2>/dev/null || echo 'jq not installed' && \
echo '' && \
echo '=== Directory Structure ===' && \
ls -la /home/ec2-user/ 2>/dev/null || echo '/home/ec2-user/ does not exist' && \
echo '' && \
echo '=== Scripts Directory ===' && \
ls -la /home/ec2-user/scripts/ 2>/dev/null || echo '/home/ec2-user/scripts/ does not exist' && \
echo '' && \
echo '=== .env File ===' && \
if [ -f /home/ec2-user/.env ]; then \
  echo '.env file exists' && \
  ls -la /home/ec2-user/.env && \
  echo 'Content (without sensitive data):' && \
  cat /home/ec2-user/.env | sed 's/PASSWORD=.*/PASSWORD=***/' || true; \
else \
  echo '.env file does NOT exist'; \
fi && \
echo '' && \
echo '=== Nginx Status ===' && \
systemctl status nginx --no-pager -l 2>/dev/null | head -10 || echo 'Nginx not installed or not running' && \
echo '' && \
echo '=== Container Status ===' && \
docker ps -a | grep golink-shorner || echo 'No golink-shorner container found' && \
echo '' && \
echo '=== Disk Space ===' && \
df -h / && \
echo '' && \
echo '=== Memory ===' && \
free -h
"

# Create temp file for SSM command
PARAMS_FILE=$(mktemp)
if command -v jq &> /dev/null; then
  jq -n --arg cmd "$VERIFY_COMMANDS" '{commands: [$cmd]}' > "$PARAMS_FILE"
else
  python3 -c "import json, sys; json.dump({'commands': [sys.argv[1]]}, sys.stdout)" "$VERIFY_COMMANDS" > "$PARAMS_FILE"
fi

# Send command via SSM
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

echo "Command ID: $COMMAND_ID"
echo "Waiting for command to complete..."
echo ""

# Wait for command to complete
for i in {1..30}; do
  sleep 2
  STATUS=$(aws ssm get-command-invocation \
    --command-id "$COMMAND_ID" \
    --instance-id "$INSTANCE_ID" \
    --region "$AWS_REGION" \
    --query 'Status' \
    --output text 2>/dev/null || echo "InProgress")
  
  if [ "$STATUS" == "Success" ] || [ "$STATUS" == "Failed" ]; then
    break
  fi
done

# Get output
echo "=========================================="
echo "Verification Output:"
echo "=========================================="
aws ssm get-command-invocation \
  --command-id "$COMMAND_ID" \
  --instance-id "$INSTANCE_ID" \
  --region "$AWS_REGION" \
  --query 'StandardOutputContent' \
  --output text 2>/dev/null || echo "No output"

echo ""
echo "=========================================="
echo "Error Output (if any):"
echo "=========================================="
aws ssm get-command-invocation \
  --command-id "$COMMAND_ID" \
  --instance-id "$INSTANCE_ID" \
  --region "$AWS_REGION" \
  --query 'StandardErrorContent' \
  --output text 2>/dev/null || echo "No errors"

echo ""
echo "=========================================="
echo "Status: $STATUS"
echo "=========================================="
