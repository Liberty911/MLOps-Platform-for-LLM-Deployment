#!/bin/bash
# setup.sh - Complete MLOps Platform Setup

set -e

echo "=========================================="
echo "MLOps Platform for LLM Deployment - Setup"
echo "=========================================="

# Check prerequisites
echo "🔍 Checking prerequisites..."
check_command() {
    if ! command -v $1 &> /dev/null; then
        echo " $1 is not installed. Please install it first."
        exit 1
    fi
}

check_command aws
check_command kubectl
check_command helm
check_command terraform

# Set environment
export AWS_PROFILE=wemo
export AWS_REGION=us-east-1
export CLUSTER_NAME=mlops-platform

# Create complete project structure
echo " Creating complete project structure..."
mkdir -p terraform/eks-cluster
mkdir -p kubernetes/{namespaces,storage/{pvc},ingress,monitoring,certificates}
mkdir -p kserve/{inference-service,transformers}
mkdir -p triton/{deployment,models/{llama-2-7b,falcon-7b,mistral-7b},client}
mkdir -p ray/{examples}
mkdir -p wandb/{experiment-tracking}
mkdir -p scripts
mkdir -p examples/{llm-inference,fine-tuning}
mkdir -p docker/{triton,custom-transformer,ray-worker}
mkdir -p helm/templates
mkdir -p docs

# Initialize infrastructure
echo " Initializing infrastructure modules..."
./scripts/init-infrastructure.sh

# Initialize Terraform
echo " Initializing Terraform..."
cd terraform
terraform init

# Deploy infrastructure
echo " Deploying AWS infrastructure..."
terraform apply -auto-approve \
  -var="aws_region=${AWS_REGION}" \
  -var="cluster_name=${CLUSTER_NAME}" \
  -var="wandb_api_key=${WANDB_API_KEY:-dummy-key-for-now}" \
  -var="environment=production"

# Configure kubectl
echo " Configuring kubectl..."
aws eks update-kubeconfig \
  --region ${AWS_REGION} \
  --name ${CLUSTER_NAME}

# Verify cluster access
echo " Verifying cluster access..."
kubectl cluster-info

cd ..

echo ""
echo " Infrastructure setup completed!"
echo ""
echo "Next steps:"
echo "1. Deploy platform components: ./scripts/deploy-platform.sh"
echo "2. Or run complete deployment: make deploy"

# Make scripts executable
chmod +x scripts/*.sh
chmod +x kserve/*.sh 2>/dev/null || true