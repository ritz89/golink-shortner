#!/bin/bash
# Script to setup nginx reverse proxy on EC2 instance
# This allows Target Group to use port 80 while application runs on port 3000
# Run this on EC2 instance via SSM or add to user data script

set -e

echo "=========================================="
echo "Setting up Nginx Reverse Proxy"
echo "=========================================="
echo ""

# Install nginx
echo "1. Installing nginx..."
sudo yum install -y nginx

# Create nginx configuration for reverse proxy
echo "2. Creating nginx configuration..."
sudo tee /etc/nginx/conf.d/golink-shorner.conf > /dev/null <<'EOF'
upstream golink_shorner {
    server localhost:3000;
    keepalive 32;
}

server {
    listen 80;
    server_name _;

    # Health check endpoint
    location /health {
        proxy_pass http://golink_shorner/health;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # Health check specific
        access_log off;
    }

    # All other requests
    location / {
        proxy_pass http://golink_shorner;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
}
EOF

# Test nginx configuration
echo "3. Testing nginx configuration..."
sudo nginx -t

# Enable and start nginx
echo "4. Starting nginx..."
sudo systemctl enable nginx
sudo systemctl restart nginx

# Check nginx status
echo "5. Checking nginx status..."
sudo systemctl status nginx --no-pager | head -10

echo ""
echo "=========================================="
echo "✅ Nginx Reverse Proxy Setup Complete!"
echo "=========================================="
echo ""
echo "Configuration:"
echo "  - Nginx listens on: Port 80"
echo "  - Forwards to: localhost:3000 (application)"
echo "  - Health check: /health → http://localhost:3000/health"
echo ""
echo "Test:"
echo "  curl http://localhost/health"
echo ""

