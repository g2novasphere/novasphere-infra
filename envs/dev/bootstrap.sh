#!/bin/bash
dnf install -y httpd && systemctl enable --now httpd
T=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
IID=$(curl -s -H "X-aws-ec2-metadata-token: $T" http://169.254.169.254/latest/meta-data/instance-id)
AZ=$(curl -s -H "X-aws-ec2-metadata-token: $T" http://169.254.169.254/latest/meta-data/placement/availability-zone)
SEC=$(aws ssm get-parameter --name "/novasphere/dev/app_secret" --with-decryption --query "Parameter.Value" --output text --region eu-west-3)
HASH=$(echo -n "$SEC" | sha256sum | cut -d' ' -f1)
echo "<h1>NovaSphere Dev</h1><p>ID: $IID | Zone: $AZ | Empreinte: $HASH</p>" > /var/www/html/index.html