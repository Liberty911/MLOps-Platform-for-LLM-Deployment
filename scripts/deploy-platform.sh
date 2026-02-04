#!/bin/bash
# scripts/deploy-platform.sh - Deploys all MLOps components

set -e
echo "🛠️  Deploying MLOps Platform Components..."

# 1. Create namespaces
kubectl apply -f kubernetes/namespaces/

# 2. Install NVIDIA GPU Operator (Required for GPU nodes)
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
helm repo update
helm install --wait --generate-name nvidia/gpu-operator -n gpu-operator --create-namespace

# 3. Install KServe (for serverless inference)
./kserve/install-kserve.sh

# 4. Deploy Triton Inference Server
kubectl apply -f triton/deployment/

# 5. Deploy Monitoring Stack (Prometheus, Grafana)
kubectl apply -f kubernetes/monitoring/

# 6. Deploy Weights & Biases operator
kubectl apply -f wandb/

echo "✅ All core MLOps components deployed!"
echo "Access Dashboards:"
echo "  - Grafana:    kubectl port-forward svc/grafana 3000:3000 -n monitoring"
echo "  - KServe:     kubectl get inferenceservices -n model-serving"