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
