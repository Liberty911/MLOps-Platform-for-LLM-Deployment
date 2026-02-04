# terraform/main.tf - Core EKS configuration
terraform {
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

# Use subnets that support EKS (avoid us-east-1e)
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "19.0"

  cluster_name    = "mlops-llm-platform"
  cluster_version = "1.28"

  vpc_id     = "vpc-0139260591160d53e" # Your default VPC
  subnet_ids = [
    "subnet-03e6e13b3bcfee847", # us-east-1a
    "subnet-0221df9f57aa0d368", # us-east-1c
    "subnet-008749496bbb35603", # us-east-1f
  ]

  eks_managed_node_groups = {
    general = {
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