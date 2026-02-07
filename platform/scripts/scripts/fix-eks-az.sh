#!/bin/bash
# scripts/fix-eks-az.sh - Fix EKS AZ issues

set -e

echo " Fixing EKS Availability Zone issue..."

cd ~/DevOps5/MLOps-Platform-for-LLM-Deployment/terraform

# Backup existing main.tf
if [ -f main.tf ]; then
    cp main.tf main.tf.backup
fi

# Create new main.tf with AZ fix
cat > main.tf << 'EOF'
terraform {
  required_version = ">= 1.0.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  
  backend "local" {
    path = "terraform.tfstate"
  }
}

provider "aws" {
  region  = "us-east-1"
  profile = "wemo"
}

# Get default VPC
data "aws_vpc" "default" {
  default = true
}

# Get all subnets
data "aws_subnets" "all" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Get subnet details
data "aws_subnet" "details" {
  for_each = toset(data.aws_subnets.all.ids)
  id       = each.value
}

# Filter out subnets in us-east-1e (not supported for EKS control plane)
locals {
  # Create map of subnet -> AZ
  subnet_az_map = {
    for subnet in data.aws_subnet.details :
    subnet.id => subnet.availability_zone
  }
  
  # Filter subnets (exclude us-east-1e)
  eks_supported_subnets = [
    for subnet_id, az in local.subnet_az_map :
    subnet_id
    if az != "us-east-1e"
  ]
  
  # Use first 3 supported subnets
  selected_subnets = slice(local.eks_supported_subnets, 0, min(3, length(local.eks_supported_subnets)))
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "19.0"
  
  cluster_name    = "mlops-platform"
  cluster_version = "1.28"
  
  cluster_endpoint_public_access = true
  
  vpc_id     = data.aws_vpc.default.id
  subnet_ids = local.selected_subnets
  
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

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "cluster_name" {
  value = module.eks.cluster_name
}

output "selected_subnets_info" {
  value = {
    selected_count = length(local.selected_subnets)
    selected_subnets = local.selected_subnets
    all_subnets_count = length(data.aws_subnets.all.ids)
  }
}
EOF

echo " Configuration updated!"
echo ""
echo "To apply the fix:"
echo "1. terraform init (if not already done)"
echo "2. terraform plan"
echo "3. terraform apply -auto-approve"