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

# Simple configuration that works with existing cluster
resource "aws_eks_cluster" "mlops_llm_platform" {
  name    = "mlops-llm-platform"
  version = "1.29" # Current cluster version

  role_arn = aws_iam_role.eks_cluster.arn

  vpc_config {
    subnet_ids = [
      "subnet-008749496bbb35603", # us-east-1f
      "subnet-0221df9f57aa0d368", # us-east-1c
      "subnet-03e6e13b3bcfee847", # us-east-1a
    ]
    endpoint_public_access = true
  }

  tags = {
    Project = "MLOps-Platform"
  }
}

resource "aws_iam_role" "eks_cluster" {
  name = "mlops-llm-platform-cluster"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "eks.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster.name
}

resource "aws_iam_role_policy_attachment" "eks_vpc_resource_controller" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
  role       = aws_iam_role.eks_cluster.name
}

output "cluster_endpoint" {
  value = aws_eks_cluster.mlops_llm_platform.endpoint
}

output "cluster_name" {
  value = aws_eks_cluster.mlops_llm_platform.name
}

output "setup_commands" {
  value = <<-EOT
    # Configure kubectl:
    aws eks update-kubeconfig --region us-east-1 --name mlops-llm-platform --profile wemo
    
    # Verify:
    kubectl cluster-info
    kubectl get nodes
  EOT
}
