#!/bin/bash
# scripts/quick-start.sh - Quick start with minimal setup

set -e

echo " Quick Start for MLOps Platform"

# Create minimal structure
mkdir -p terraform/eks-cluster

# Create minimal eks-cluster module
cat > terraform/eks-cluster/main.tf << 'EOF'
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

locals {
  vpc_id = var.vpc_id != "" ? var.vpc_id : ""
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 19.0"
  
  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version
  
  vpc_id     = local.vpc_id
  subnet_ids = var.subnet_ids
  
  eks_managed_node_groups = var.node_groups
  
  tags = {
    Project = "MLOps-Platform"
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
}

variable "node_groups" {
  type = any
}
EOF

echo " Quick-start files created. Run: cd terraform && terraform init"