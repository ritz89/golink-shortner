#!/bin/bash
# Script to setup AWS Systems Manager Parameter Store for database credentials
# Run this from your local machine with AWS CLI configured

set -e

AWS_REGION="${AWS_REGION:-ap-southeast-1}"
PARAMETER_PREFIX="/golink-shorner/db"

echo "=========================================="
echo "Setting up Parameter Store for golink-shorner"
echo "=========================================="
echo ""

# Prompt for database credentials
echo "Enter database credentials (will be stored securely in Parameter Store):"
echo ""

read -p "Database Host [rds-onj-primary.c7qw6oy402sj.ap-southeast-1.rds.amazonaws.com]: " DB_HOST
DB_HOST=${DB_HOST:-rds-onj-primary.c7qw6oy402sj.ap-southeast-1.rds.amazonaws.com}

read -p "Database Port [5432]: " DB_PORT
DB_PORT=${DB_PORT:-5432}

read -p "Database User [onjourney]: " DB_USER
DB_USER=${DB_USER:-onjourney}

read -sp "Database Password: " DB_PASSWORD
echo ""
if [ -z "$DB_PASSWORD" ]; then
    echo "❌ Error: Database password is required"
    exit 1
fi

read -p "Database Name [onjourney_link]: " DB_NAME
DB_NAME=${DB_NAME:-onjourney_link}

echo ""
echo "Creating parameters in Parameter Store..."
echo ""

# Create database host parameter
echo "Creating /golink-shorner/db/host..."
aws ssm put-parameter \
    --name "${PARAMETER_PREFIX}/host" \
    --type "String" \
    --value "$DB_HOST" \
    --description "RDS database endpoint for golink-shorner" \
    --region "$AWS_REGION" \
    --overwrite 2>/dev/null && echo "✅ Created/Updated" || echo "⚠️  Already exists (use --overwrite to update)"

# Create database port parameter
echo "Creating /golink-shorner/db/port..."
aws ssm put-parameter \
    --name "${PARAMETER_PREFIX}/port" \
    --type "String" \
    --value "$DB_PORT" \
    --description "PostgreSQL port" \
    --region "$AWS_REGION" \
    --overwrite 2>/dev/null && echo "✅ Created/Updated" || echo "⚠️  Already exists (use --overwrite to update)"

# Create database user parameter
echo "Creating /golink-shorner/db/user..."
aws ssm put-parameter \
    --name "${PARAMETER_PREFIX}/user" \
    --type "String" \
    --value "$DB_USER" \
    --description "Database username" \
    --region "$AWS_REGION" \
    --overwrite 2>/dev/null && echo "✅ Created/Updated" || echo "⚠️  Already exists (use --overwrite to update)"

# Create database password parameter (SecureString) - IMPORTANT
echo "Creating /golink-shorner/db/password (SecureString)..."
aws ssm put-parameter \
    --name "${PARAMETER_PREFIX}/password" \
    --type "SecureString" \
    --value "$DB_PASSWORD" \
    --description "Database password (encrypted)" \
    --region "$AWS_REGION" \
    --overwrite 2>/dev/null && echo "✅ Created/Updated (encrypted)" || echo "⚠️  Already exists (use --overwrite to update)"

# Create database name parameter
echo "Creating /golink-shorner/db/name..."
aws ssm put-parameter \
    --name "${PARAMETER_PREFIX}/name" \
    --type "String" \
    --value "$DB_NAME" \
    --description "Database name" \
    --region "$AWS_REGION" \
    --overwrite 2>/dev/null && echo "✅ Created/Updated" || echo "⚠️  Already exists (use --overwrite to update)"

echo ""
echo "=========================================="
echo "✅ Parameter Store setup completed!"
echo "=========================================="
echo ""
echo "Verifying parameters..."
echo ""

# Verify parameters
aws ssm describe-parameters \
    --filters "Key=Name,Values=${PARAMETER_PREFIX}/" \
    --region "$AWS_REGION" \
    --query 'Parameters[*].[Name,Type,LastModifiedDate]' \
    --output table

echo ""
echo "✅ All parameters created successfully!"
echo ""
echo "Next steps:"
echo "1. Verify IAM role EC2RoleForSSM has Parameter Store access (SecretsManagerReadWrite policy)"
echo "2. New instances will automatically retrieve credentials from Parameter Store"
echo "3. Update existing instances by running setup-ec2.sh script"
echo ""

