#!/bin/bash

# KServe Installation Script for MLOps Platform

set -e

echo "🚀 Installing KServe on Kubernetes cluster..."

# Add KServe repository
helm repo add kserve https://kserve.github.io/helm-charts
helm repo update

# Install KServe with NVIDIA GPU support
helm install kserve kserve/kserve \
  --namespace kserve \
  --create-namespace \
  --set kserveController.enabled=true \
  --set kserveController.image.nvidiaGPU=true \
  --set kserveController.resources.requests.cpu=100m \
  --set kserveController.resources.requests.memory=256Mi \
  --set kserveController.resources.limits.cpu=500m \
  --set kserveController.resources.limits.memory=1Gi \
  --set kserveController.serviceAccount.create=true \
  --set kserveController.serviceAccount.name=kserve-controller \
  --wait

# Install Knative Serving
kubectl apply -f https://github.com/knative/serving/releases/download/knative-v1.11.0/serving-crds.yaml
kubectl apply -f https://github.com/knative/serving/releases/download/knative-v1.11.0/serving-core.yaml

# Install Knative Kourier ingress
kubectl apply -f https://github.com/knative/net-kourier/releases/download/knative-v1.11.0/kourier.yaml

# Configure DNS
kubectl patch configmap/config-domain \
  --namespace knative-serving \
  --type merge \
  --patch '{"data":{"example.com":""}}'

echo "✅ KServe installation completed!"
echo ""
echo "Next steps:"
echo "1. Deploy a sample inference service:"
echo "   kubectl apply -f kserve/inference-service/llama2-inference-service.yaml"
echo ""
echo "2. Check KServe pods:"
echo "   kubectl get pods -n kserve"