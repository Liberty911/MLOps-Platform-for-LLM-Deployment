#!/bin/bash
# setup-final.sh - Complete MLOps Platform Setup

set -e

echo "==========================================="
echo "MLOps Platform for LLM Deployment - Setup"
echo "==========================================="

# Check AWS credentials
echo " Checking AWS credentials..."
if ! aws sts get-caller-identity --profile wemo > /dev/null 2>&1; then
    echo " AWS credentials not working for profile 'wemo'"
    echo "Please configure AWS credentials first."
    exit 1
fi
echo " AWS credentials verified"

# Clean up and prepare
echo " Cleaning up previous Terraform state..."
cd ~/DevOps5/MLOps-Platform-for-LLM-Deployment
rm -rf terraform/.terraform* terraform/terraform.tfstate* 2>/dev/null || true

# Create project structure
echo " Creating project structure..."
mkdir -p {terraform,kubernetes/{namespaces,storage,ingress,monitoring},kserve,triton/{models,deployment},ray,wandb,scripts,examples,docker,docs}

# Create the final main.tf
echo " Creating Terraform configuration..."
cat > terraform/main.tf << 'EOF'
terraform {
  required_version = ">= 1.0.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region  = "us-east-1"
  profile = "wemo"
}

# Use only subnets that support EKS control plane
# From investigation: us-east-1a, 1c, 1f are safe (avoid us-east-1e)
locals {
  eks_subnets = [
    "subnet-03e6e13b3bcfee847",  # us-east-1a
    "subnet-0221df9f57aa0d368",  # us-east-1c
    "subnet-008749496bbb35603",  # us-east-1f
  ]
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "19.0"
  
  cluster_name    = "mlops-llm-platform"
  cluster_version = "1.28"
  
  cluster_endpoint_public_access = true
  
  vpc_id     = "vpc-0139260591160d53e"
  subnet_ids = local.eks_subnets
  
  eks_managed_node_groups = {
    main = {
      instance_types = ["t3.medium"]
      min_size       = 2
      max_size       = 4
      desired_size   = 2
      disk_size      = 50
    }
  }
  
  tags = {
    Project = "MLOps-Platform"
  }
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "cluster_name" {
  value = module.eks.cluster_name
}

output "kubectl_setup" {
  value = <<-EOT
    To configure kubectl:
    aws eks update-kubeconfig --region us-east-1 --name ${module.eks.cluster_name} --profile wemo
  EOT
}
EOF

# Deploy EKS cluster
echo " Deploying EKS cluster..."
cd terraform
terraform init
terraform apply -auto-approve

# Get cluster name
CLUSTER_NAME=$(terraform output -raw cluster_name 2>/dev/null || echo "mlops-llm-platform")

echo ""
echo " EKS cluster created successfully!"
echo ""

# Configure kubectl
echo " Configuring kubectl..."
aws eks update-kubeconfig \
  --region us-east-1 \
  --name $CLUSTER_NAME \
  --profile wemo

# Verify cluster
echo " Verifying cluster access..."
kubectl cluster-info
kubectl get nodes

echo ""
echo " MLOps Platform infrastructure is ready!"
echo ""
echo "Next steps:"
echo "1. Deploy MLOps components: ./scripts/deploy-platform.sh"
echo "2. Or run complete deployment: make deploy"
echo ""
echo "Cluster Name: $CLUSTER_NAME"
echo "Access configured to profile: wemo"