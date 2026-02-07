#!/bin/bash
# scripts/init-infrastructure.sh
set -e

echo "Initializing MLOps Platform Infrastructure..."

# Create necessary directories
echo "Creating Terraform module directories..."
mkdir -p terraform/eks-cluster

# Copy the eks-cluster module files
echo "Setting up eks-cluster module..."
cat > terraform/eks-cluster/main.tf << 'EOF'
# terraform/eks-cluster/main.tf
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

# Rest of the file as provided above...
EOF

cat > terraform/eks-cluster/variables.tf << 'EOF'
# terraform/eks-cluster/variables.tf
variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes cluster version"
  type        = string
  default     = "1.28"
}

variable "vpc_id" {
  description = "VPC ID to use for the cluster. If empty, a new VPC will be created"
  type        = string
  default     = ""
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
}

variable "node_groups" {
  description = "Map of node group definitions"
  type        = any
  default     = {}
}

variable "enable_cluster_autoscaler" {
  description = "Enable cluster autoscaler"
  type        = bool
  default     = true
}

variable "enable_irsa" {
  description = "Enable IAM Roles for Service Accounts"
  type        = bool
  default     = true
}
EOF

cat > terraform/eks-cluster/outputs.tf << 'EOF'
# terraform/eks-cluster/outputs.tf
output "cluster_id" {
  description = "EKS cluster ID"
  value       = module.eks.cluster_id
}

output "cluster_endpoint" {
  description = "Endpoint for EKS control plane"
  value       = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data required to communicate with the cluster"
  value       = module.eks.cluster_certificate_authority_data
}

output "cluster_name" {
  description = "Kubernetes cluster name"
  value       = module.eks.cluster_name
}

output "cluster_oidc_issuer_url" {
  description = "URL for the OIDC issuer"
  value       = module.eks.cluster_oidc_issuer_url
}

output "node_group_role_name" {
  description = "IAM role name for EKS node groups"
  value       = module.eks.eks_managed_node_groups["cpu_ondemand"].iam_role_name
}

output "vpc_id" {
  description = "VPC ID"
  value       = local.vpc_id
}

output "vpc_cidr_block" {
  description = "VPC CIDR block"
  value       = local.vpc_cidr_block
}

output "private_subnet_ids" {
  description = "List of private subnet IDs"
  value       = aws_subnet.private[*].id
}

output "public_subnet_ids" {
  description = "List of public subnet IDs"
  value       = aws_subnet.public[*].id
}
EOF

echo "Terraform module setup complete!"