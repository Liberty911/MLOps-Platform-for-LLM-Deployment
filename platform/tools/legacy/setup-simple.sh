#!/bin/bash
# setup-simple.sh - Simple one-step setup

set -e

echo "======================================="
echo "Simple MLOps Platform Setup"
echo "======================================="

# Check AWS credentials
echo " Checking AWS credentials..."
if ! aws sts get-caller-identity --profile wemo > /dev/null 2>&1; then
    echo " AWS credentials not working for profile 'wemo'"
    echo "Please run: aws configure --profile wemo"
    exit 1
fi

echo " AWS credentials verified"

# Clean up and create Terraform directory
echo " Cleaning up Terraform directory..."
cd ~/DevOps5/MLOps-Platform-for-LLM-Deployment
mkdir -p terraform
cd terraform

# Remove any existing files
rm -f *.tf *.tfvars
rm -rf .terraform/

# Create minimal main.tf
echo " Creating Terraform configuration..."
cat > main.tf << 'EOF'
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  backend "local" {}
}

provider "aws" {
  region  = "us-east-1"
  profile = "wemo"
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "19.0"
  
  cluster_name    = "mlops-platform"
  cluster_version = "1.28"
  
  vpc_id     = data.aws_vpc.default.id
  subnet_ids = data.aws_subnets.default.ids
  
  eks_managed_node_groups = {
    main = {
      instance_types = ["t3.medium"]
      min_size       = 2
      max_size       = 4
      desired_size   = 2
      disk_size      = 50
    }
  }
}

output "endpoint" {
  value = module.eks.cluster_endpoint
}

output "cluster_name" {
  value = module.eks.cluster_name
}
EOF

# Initialize Terraform
echo " Initializing Terraform..."
terraform init

# Apply configuration
echo " Creating EKS cluster..."
terraform apply -auto-approve

# Get outputs
CLUSTER_NAME=$(terraform output -raw cluster_name 2>/dev/null || echo "mlops-platform")

echo ""
echo " EKS cluster created successfully!"
echo ""
echo " Next steps:"
echo "1. Configure kubectl:"
echo "   aws eks update-kubeconfig --region us-east-1 --name ${CLUSTER_NAME} --profile wemo"
echo ""
echo "2. Verify cluster access:"
echo "   kubectl cluster-info"
echo "   kubectl get nodes"
echo ""
echo "3. Deploy platform components:"
echo "   ./scripts/deploy-platform.sh"