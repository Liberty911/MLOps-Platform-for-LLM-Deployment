#!/bin/bash

# Deploy MLOps Platform on Kubernetes
set -e

echo "🚀 Deploying MLOps Platform..."

# Create namespaces
echo "📁 Creating namespaces..."
kubectl apply -f kubernetes/namespaces/

# Install NVIDIA GPU Operator
echo "🎮 Installing NVIDIA GPU Operator..."
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
helm repo update
helm install gpu-operator nvidia/gpu-operator \
  --namespace gpu-operator \
  --create-namespace \
  --set driver.enabled=false \
  --set toolkit.enabled=true \
  --wait

# Deploy storage
echo "💾 Deploying storage..."
kubectl apply -f kubernetes/storage/

# Install KServe
echo "⚡ Installing KServe..."
./kserve/install-kserve.sh

# Deploy Triton Inference Server
echo "🤖 Deploying Triton Inference Server..."
kubectl apply -f triton/deployment/

# Deploy Ray Operator
echo "🌀 Deploying Ray Operator..."
kubectl apply -k "github.com/ray-project/kuberay/ray-operator/config/default?ref=v1.0.0"
kubectl apply -f ray/ray-cluster.yaml

# Deploy Weights & Biases secret
echo "📊 Deploying Weights & Biases..."
kubectl apply -f wandb/wandb-secret.yaml

# Deploy monitoring stack
echo "📈 Deploying monitoring..."
kubectl apply -f kubernetes/monitoring/

# Deploy ingress controller
echo "🌐 Deploying ingress..."
kubectl apply -f kubernetes/ingress/

# Wait for all deployments
echo "⏳ Waiting for deployments to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment -n kserve --all
kubectl wait --for=condition=ready --timeout=300s pod -n model-serving --all

echo ""
echo "🎉 MLOps Platform deployment completed!"
echo ""
echo "Access URLs:"
echo "============"
echo "KServe Dashboard: http://kserve-dashboard.mlops-platform.local"
echo "Ray Dashboard: http://ray-dashboard.mlops-platform.local"
echo "Grafana: http://grafana.mlops-platform.local"
echo ""
echo "Next steps:"
echo "1. Deploy models: ./scripts/model-deploy.sh --model llama2-7b"
echo "2. Run fine-tuning: kubectl apply -f wandb/experiment-tracking/"