#!/bin/bash
# scripts/setup-eks.sh - Deploys the EKS cluster

set -e
echo " Deploying EKS Cluster..."

cd terraform
terraform init
terraform apply -auto-approve

# Configure kubectl
CLUSTER_NAME=$(terraform output -raw cluster_name)
aws eks update-kubeconfig --region us-east-1 --name $CLUSTER_NAME --profile wemo

echo " EKS cluster '$CLUSTER_NAME' is ready!"
kubectl cluster-info