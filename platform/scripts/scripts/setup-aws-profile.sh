#!/bin/bash
# scripts/setup-aws-profile.sh

set -e

echo "🔧 Setting up AWS profile for wemo..."

# Check if credentials exist
if [ ! -f ~/.aws/credentials ]; then
    echo "Creating ~/.aws/credentials file..."
    mkdir -p ~/.aws
fi

# Configure AWS profile
cat > ~/.aws/credentials << EOF
[wemo]
aws_access_key_id = ${AWS_ACCESS_KEY_ID}
aws_secret_access_key = ${AWS_SECRET_ACCESS_KEY}
region = us-east-1
output = json
EOF

cat > ~/.aws/config << EOF
[profile wemo]
region = us-east-1
output = json
EOF

# Set permissions
chmod 600 ~/.aws/credentials
chmod 600 ~/.aws/config

echo "✅ AWS profile 'wemo' configured successfully!"
echo ""
echo "To test the configuration:"
echo "aws sts get-caller-identity --profile wemo"