#!/bin/bash

# Setup AWS Infrastructure for MLOps Platform
set -e

echo "🚀 Setting up AWS Infrastructure for MLOps Platform..."

# Check AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo "❌ AWS CLI is not installed. Please install it first."
    exit 1
fi

# Check kubectl is installed
if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl is not installed. Please install it first."
    exit 1
fi

# Check terraform is installed
if ! command -v terraform &> /dev/null; then
    echo "❌ Terraform is not installed. Please install it first."
    exit 1
fi

# Configure AWS credentials
echo "🔧 Configuring AWS credentials..."
export AWS_PROFILE=wemo
export AWS_REGION=us-east-1

# Initialize Terraform
echo "🏗️ Initializing Terraform..."
cd terraform
terraform init

# Apply Terraform configuration
echo "🚧 Applying Terraform configuration..."
terraform apply -auto-approve \
  -var="aws_region=${AWS_REGION}" \
  -var="cluster_name=mlops-platform" \
  -var="wandb_api_key=${WANDB_API_KEY}"

# Update kubeconfig
echo "🔗 Updating kubeconfig..."
aws eks update-kubeconfig \
  --region ${AWS_REGION} \
  --name mlops-platform

# Verify cluster access
echo "✅ Verifying cluster access..."
kubectl cluster-info

# Output important information
echo ""
echo "🎉 AWS Infrastructure setup completed!"
echo ""
echo "Important Information:"
echo "======================"
terraform output
echo ""
echo "Next steps:"
echo "1. Run: ./scripts/deploy-platform.sh"
echo "2. Configure storage: kubectl apply -f kubernetes/storage/"
echo "3. Deploy monitoring: kubectl apply -f kubernetes/monitoring/"