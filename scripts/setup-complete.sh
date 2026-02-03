#!/bin/bash
# scripts/setup-complete.sh - Complete setup with AWS configuration

set -e

echo "=========================================="
echo "MLOps Platform Complete Setup"
echo "=========================================="

# Check if AWS credentials are provided
if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
    echo "❌ AWS credentials not found in environment variables"
    echo "Please set:"
    echo "  export AWS_ACCESS_KEY_ID='your-access-key'"
    echo "  export AWS_SECRET_ACCESS_KEY='your-secret-key'"
    
    # Try to use existing AWS configuration
    echo ""
    echo "Checking existing AWS configuration..."
    if aws configure list --profile wemo 2>/dev/null; then
        echo "✅ Found existing AWS profile 'wemo'"
    else
        echo "❌ No AWS profile found. Please configure AWS credentials first."
        exit 1
    fi
fi

# Setup AWS profile
echo "🔧 Setting up AWS profile..."
./scripts/setup-aws-profile.sh

# Verify AWS credentials
echo "🔍 Verifying AWS credentials..."
if ! aws sts get-caller-identity --profile wemo > /dev/null 2>&1; then
    echo "❌ AWS credentials verification failed"
    echo "Please check your credentials and try again."
    exit 1
fi

echo "✅ AWS credentials verified successfully!"

# Initialize infrastructure
echo "📁 Creating project structure..."
mkdir -p terraform/eks-cluster
mkdir -p {kubernetes/{namespaces,storage/{pvc},ingress,monitoring,certificates},kserve/{inference-service,transformers},triton/{deployment,models/{llama-2-7b,falcon-7b,mistral-7b},client},ray/{examples},wandb/{experiment-tracking},scripts,examples/{llm-inference,fine-tuning},docker/{triton,custom-transformer,ray-worker},helm/templates,docs}

# Setup eks-cluster module
echo "🏗️ Setting up eks-cluster module..."
cat > terraform/eks-cluster/main.tf << 'EOF'
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Simple EKS module for initial setup
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 19.0"
  
  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version
  
  cluster_endpoint_public_access = true
  
  vpc_id     = var.vpc_id
  subnet_ids = var.subnet_ids
  
  eks_managed_node_groups = var.node_groups
  
  tags = {
    Environment = var.environment
    Project     = "MLOps-Platform"
  }
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  value = module.eks.cluster_certificate_authority_data
}

output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_oidc_issuer_url" {
  value = module.eks.cluster_oidc_issuer_url
}

output "vpc_id" {
  value = var.vpc_id
}
EOF

cat > terraform/eks-cluster/variables.tf << 'EOF'
variable "cluster_name" {
  type = string
}

variable "cluster_version" {
  default = "1.28"
}

variable "vpc_id" {
  default = ""
}

variable "subnet_ids" {
  type = list(string)
  default = []
}

variable "node_groups" {
  type = any
  default = {}
}

variable "environment" {
  default = "production"
}
EOF

# Initialize Terraform
echo "🔧 Initializing Terraform..."
cd terraform

# Use local backend for initial testing to avoid S3 issues
cat > backend-local.tf << 'EOF'
terraform {
  backend "local" {}
}
EOF

terraform init

# Create terraform.tfvars for your specific configuration
cat > terraform.tfvars << EOF
aws_region = "us-east-1"
cluster_name = "mlops-platform"
environment = "production"
EOF

echo "✅ Setup completed successfully!"
echo ""
echo "Next steps:"
echo "1. Plan the infrastructure: terraform plan"
echo "2. Apply the infrastructure: terraform apply"
echo "3. Deploy the platform: ./scripts/deploy-platform.sh"