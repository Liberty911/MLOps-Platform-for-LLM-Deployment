#!/bin/bash
# setup-final-complete.sh - Complete MLOps Platform Setup

set -e

echo "===================================================="
echo "MLOps Platform for LLM Deployment - Complete Setup"
echo "===================================================="

# 1. Clean up Terraform directory
echo "🧹 Step 1: Cleaning Terraform directory..."
cd ~/DevOps5/MLOps-Platform-for-LLM-Deployment/terraform
rm -rf .terraform* terraform.tfstate* *.backup 2>/dev/null || true

# 2. Create final main.tf
echo "📝 Step 2: Creating Terraform configuration..."
cat > main.tf << 'EOF'
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
  name     = "mlops-llm-platform"
  version  = "1.29"  # Current cluster version
  
  role_arn = aws_iam_role.eks_cluster.arn
  
  vpc_config {
    subnet_ids = [
      "subnet-008749496bbb35603",  # us-east-1f
      "subnet-0221df9f57aa0d368",  # us-east-1c
      "subnet-03e6e13b3bcfee847",  # us-east-1a
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
EOF

# 3. Initialize Terraform
echo "🔧 Step 3: Initializing Terraform..."
terraform init

# 4. Import existing resources
echo "📥 Step 4: Importing existing EKS cluster..."
terraform import aws_eks_cluster.mlops_llm_platform mlops-llm-platform

# 5. Apply configuration
echo "🚀 Step 5: Applying configuration..."
terraform apply -auto-approve

# 6. Configure kubectl
echo "🔗 Step 6: Configuring kubectl..."
aws eks update-kubeconfig \
  --region us-east-1 \
  --name mlops-llm-platform \
  --profile wemo

# 7. Verify cluster
echo "🔍 Step 7: Verifying cluster access..."
kubectl cluster-info
kubectl get nodes

echo ""
echo "===================================================="
echo "✅ MLOps Platform EKS Cluster Successfully Configured!"
echo "===================================================="
echo ""
echo "🎉 Your cluster is ready for MLOps platform deployment!"
echo ""
echo "📋 Cluster Information:"
echo "   • Name: mlops-llm-platform"
echo "   • Version: 1.29"
echo "   • Region: us-east-1"
echo "   • Profile: wemo"
echo ""
echo "🚀 Next Steps:"
echo "   1. Deploy platform components: ./scripts/deploy-platform.sh"
echo "   2. Or check project README for complete deployment guide"
echo ""
echo "💡 To manage cluster with Terraform:"
echo "   • Plan: cd terraform && terraform plan"
echo "   • Apply: cd terraform && terraform apply"
echo "   • Destroy: cd terraform && terraform destroy"
echo ""
echo "🔧 To update kubectl configuration:"
echo "   aws eks update-kubeconfig --region us-east-1 --name mlops-llm-platform --profile wemo"
echo "===================================================="