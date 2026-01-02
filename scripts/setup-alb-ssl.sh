#!/bin/bash
# Script to setup SSL certificate and HTTPS listener for ALB
# This script will:
# 1. Request SSL certificate from ACM for onjourney.link domain
# 2. Add HTTPS listener to ALB
# 3. Configure HTTP to HTTPS redirect
# Run this from your local machine with AWS CLI configured

set -e

AWS_REGION="${AWS_REGION:-ap-southeast-1}"
ALB_NAME="${ALB_NAME:-onjourney-golink-shortner-alb}"
DOMAIN_NAME="${DOMAIN_NAME:-onjourney.link}"
TARGET_GROUP_NAME="${TARGET_GROUP_NAME:-onjourney-golink-shortner-tg}"

echo "=========================================="
echo "Setting up SSL for ALB: $ALB_NAME"
echo "Domain: $DOMAIN_NAME"
echo "=========================================="
echo ""

# Step 1: Request SSL certificate from ACM
echo "Step 1: Requesting SSL certificate from ACM..."
echo ""

# Check if certificate already exists
EXISTING_CERT=$(aws acm list-certificates \
    --region $AWS_REGION \
    --query "CertificateSummaryList[?DomainName=='$DOMAIN_NAME' || DomainName=='*.$DOMAIN_NAME'].CertificateArn" \
    --output text 2>/dev/null | head -1)

if [ -n "$EXISTING_CERT" ] && [ "$EXISTING_CERT" != "None" ]; then
    echo "✅ Certificate already exists: $EXISTING_CERT"
    CERT_ARN="$EXISTING_CERT"
    
    # Check certificate status
    CERT_STATUS=$(aws acm describe-certificate \
        --certificate-arn "$CERT_ARN" \
        --region $AWS_REGION \
        --query 'Certificate.Status' \
        --output text 2>/dev/null)
    
    echo "   Certificate Status: $CERT_STATUS"
    
    if [ "$CERT_STATUS" != "ISSUED" ]; then
        echo "⚠️  Warning: Certificate is not yet issued (Status: $CERT_STATUS)"
        echo "   Please complete DNS validation in ACM console"
        echo "   Certificate ARN: $CERT_ARN"
        echo ""
        echo "   To complete validation:"
        echo "   1. Go to AWS Certificate Manager (ACM) console"
        echo "   2. Find certificate: $CERT_ARN"
        echo "   3. Add CNAME records to your DNS provider (onjourney.link)"
        echo "   4. Wait for validation to complete"
        echo ""
        read -p "Press Enter to continue after validation is complete, or Ctrl+C to exit..."
    fi
else
    echo "Requesting new certificate for $DOMAIN_NAME and *.$DOMAIN_NAME..."
    
    CERT_ARN=$(aws acm request-certificate \
        --domain-name "$DOMAIN_NAME" \
        --subject-alternative-names "*.$DOMAIN_NAME" \
        --validation-method DNS \
        --region $AWS_REGION \
        --query 'CertificateArn' \
        --output text 2>/dev/null)
    
    if [ -z "$CERT_ARN" ] || [ "$CERT_ARN" == "None" ]; then
        echo "❌ Error: Failed to request certificate"
        exit 1
    fi
    
    echo "✅ Certificate requested: $CERT_ARN"
    echo ""
    echo "⚠️  IMPORTANT: Certificate validation required!"
    echo "   You need to add CNAME records to your DNS provider ($DOMAIN_NAME)"
    echo ""
    echo "   To get validation records, run:"
    echo "   aws acm describe-certificate --certificate-arn $CERT_ARN --region $AWS_REGION --query 'Certificate.DomainValidationOptions'"
    echo ""
    echo "   Or check in ACM console:"
    echo "   https://console.aws.amazon.com/acm/home?region=$AWS_REGION#/certificates/$CERT_ARN"
    echo ""
    read -p "Press Enter after adding DNS validation records and validation is complete, or Ctrl+C to exit..."
fi

# Verify certificate is issued
CERT_STATUS=$(aws acm describe-certificate \
    --certificate-arn "$CERT_ARN" \
    --region $AWS_REGION \
    --query 'Certificate.Status' \
    --output text 2>/dev/null)

if [ "$CERT_STATUS" != "ISSUED" ]; then
    echo "❌ Error: Certificate is not issued yet (Status: $CERT_STATUS)"
    echo "   Please complete DNS validation first"
    exit 1
fi

echo "✅ Certificate is issued and ready"
echo ""

# Step 2: Get ALB ARN
echo "Step 2: Getting ALB information..."
ALB_ARN=$(aws elbv2 describe-load-balancers \
    --names "$ALB_NAME" \
    --region $AWS_REGION \
    --query 'LoadBalancers[0].LoadBalancerArn' \
    --output text 2>/dev/null)

if [ -z "$ALB_ARN" ] || [ "$ALB_ARN" == "None" ]; then
    echo "❌ Error: ALB '$ALB_NAME' not found"
    exit 1
fi

echo "✅ ALB ARN: $ALB_ARN"
echo ""

# Step 3: Get Target Group ARN
echo "Step 3: Getting Target Group information..."
TG_ARN=$(aws elbv2 describe-target-groups \
    --names "$TARGET_GROUP_NAME" \
    --region $AWS_REGION \
    --query 'TargetGroups[0].TargetGroupArn' \
    --output text 2>/dev/null)

if [ -z "$TG_ARN" ] || [ "$TG_ARN" == "None" ]; then
    echo "❌ Error: Target Group '$TARGET_GROUP_NAME' not found"
    exit 1
fi

echo "✅ Target Group ARN: $TG_ARN"
echo ""

# Step 4: Check existing listeners
echo "Step 4: Checking existing listeners..."
HTTP_LISTENER=$(aws elbv2 describe-listeners \
    --load-balancer-arn "$ALB_ARN" \
    --region $AWS_REGION \
    --query "Listeners[?Port==\`80\`].ListenerArn" \
    --output text 2>/dev/null | head -1)

HTTPS_LISTENER=$(aws elbv2 describe-listeners \
    --load-balancer-arn "$ALB_ARN" \
    --region $AWS_REGION \
    --query "Listeners[?Port==\`443\`].ListenerArn" \
    --output text 2>/dev/null | head -1)

# Step 5: Create HTTPS listener
if [ -z "$HTTPS_LISTENER" ] || [ "$HTTPS_LISTENER" == "None" ]; then
    echo "Step 5: Creating HTTPS (443) listener..."
    
    HTTPS_LISTENER_ARN=$(aws elbv2 create-listener \
        --load-balancer-arn "$ALB_ARN" \
        --protocol HTTPS \
        --port 443 \
        --certificates CertificateArn="$CERT_ARN" \
        --default-actions Type=forward,TargetGroupArn="$TG_ARN" \
        --region $AWS_REGION \
        --query 'Listeners[0].ListenerArn' \
        --output text 2>/dev/null)
    
    if [ -z "$HTTPS_LISTENER_ARN" ] || [ "$HTTPS_LISTENER_ARN" == "None" ]; then
        echo "❌ Error: Failed to create HTTPS listener"
        exit 1
    fi
    
    echo "✅ HTTPS listener created: $HTTPS_LISTENER_ARN"
else
    echo "✅ HTTPS listener already exists: $HTTPS_LISTENER"
    HTTPS_LISTENER_ARN="$HTTPS_LISTENER"
fi
echo ""

# Step 6: Update HTTP listener to redirect to HTTPS
if [ -n "$HTTP_LISTENER" ] && [ "$HTTP_LISTENER" != "None" ]; then
    echo "Step 6: Updating HTTP listener to redirect to HTTPS..."
    
    # Check current default action
    CURRENT_ACTION=$(aws elbv2 describe-listeners \
        --listener-arns "$HTTP_LISTENER" \
        --region $AWS_REGION \
        --query 'Listeners[0].DefaultActions[0].Type' \
        --output text 2>/dev/null)
    
    if [ "$CURRENT_ACTION" != "redirect" ]; then
        aws elbv2 modify-listener \
            --listener-arn "$HTTP_LISTENER" \
            --default-actions Type=redirect,RedirectConfig='{Protocol=HTTPS,Port=443,StatusCode=HTTP_301}' \
            --region $AWS_REGION > /dev/null
        
        echo "✅ HTTP listener updated to redirect to HTTPS"
    else
        echo "✅ HTTP listener already configured to redirect to HTTPS"
    fi
else
    echo "⚠️  Warning: HTTP listener not found. Creating HTTP listener with redirect..."
    
    HTTP_LISTENER_ARN=$(aws elbv2 create-listener \
        --load-balancer-arn "$ALB_ARN" \
        --protocol HTTP \
        --port 80 \
        --default-actions Type=redirect,RedirectConfig='{Protocol=HTTPS,Port=443,StatusCode=HTTP_301}' \
        --region $AWS_REGION \
        --query 'Listeners[0].ListenerArn' \
        --output text 2>/dev/null)
    
    echo "✅ HTTP listener created with HTTPS redirect: $HTTP_LISTENER_ARN"
fi
echo ""

# Step 7: Summary
echo "=========================================="
echo "✅ SSL Setup Complete!"
echo "=========================================="
echo ""
echo "ALB Configuration:"
echo "  - ALB Name: $ALB_NAME"
echo "  - ALB ARN: $ALB_ARN"
echo "  - Certificate ARN: $CERT_ARN"
echo "  - HTTPS Listener: $HTTPS_LISTENER_ARN"
echo "  - HTTP Listener: Redirects to HTTPS"
echo ""
echo "Next Steps:"
echo "1. Get ALB DNS name:"
echo "   aws elbv2 describe-load-balancers --names $ALB_NAME --region $AWS_REGION --query 'LoadBalancers[0].DNSName' --output text"
echo ""
echo "2. Add CNAME record in your DNS provider (onjourney.link):"
echo "   Type: CNAME"
echo "   Name: @ (or leave blank for root domain)"
echo "   Value: <ALB_DNS_NAME>"
echo "   TTL: 300 (or your preference)"
echo ""
echo "3. (Optional) Add CNAME for www subdomain:"
echo "   Type: CNAME"
echo "   Name: www"
echo "   Value: <ALB_DNS_NAME>"
echo "   TTL: 300"
echo ""
echo "4. Wait for DNS propagation (usually 5-15 minutes)"
echo ""
echo "5. Test HTTPS:"
echo "   curl -I https://$DOMAIN_NAME/health"
echo ""

