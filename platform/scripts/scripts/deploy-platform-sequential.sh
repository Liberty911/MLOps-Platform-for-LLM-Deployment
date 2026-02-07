#!/bin/bash
# deploy-platform-sequential.sh - Deploy MLOps Platform in correct order

set -e

echo "=========================================="
echo "MLOps Platform - Sequential Deployment"
echo "=========================================="

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_status() { echo -e "${GREEN}[✓]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
print_error() { echo -e "${RED}[✗]${NC} $1"; }

# Check prerequisites
echo "🔍 Checking prerequisites..."
check_command() {
    if ! command -v $1 &> /dev/null; then
        print_error "$1 is not installed"
        return 1
    fi
    print_status "$1 is installed"
    return 0
}

check_command kubectl || exit 1
check_command helm || exit 1

echo ""
print_status "Step 1: Verify cluster access..."
kubectl cluster-info
kubectl get nodes
echo ""

print_status "Step 2: Create namespaces..."
cat > /tmp/mlops-namespaces.yaml << 'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: mlops-platform
  labels:
    name: mlops-platform
---
apiVersion: v1
kind: Namespace
metadata:
  name: model-serving
  labels:
    name: model-serving
---
apiVersion: v1
kind: Namespace
metadata:
  name: ray-cluster
  labels:
    name: ray-cluster
---
apiVersion: v1
kind: Namespace
metadata:
  name: monitoring
  labels:
    name: monitoring
---
apiVersion: v1
kind: Namespace
metadata:
  name: kserve
  labels:
    name: kserve
---
apiVersion: v1
kind: Namespace
metadata:
  name: triton
  labels:
    name: triton
---
apiVersion: v1
kind: Namespace
metadata:
  name: wandb
  labels:
    name: wandb
---
apiVersion: v1
kind: Namespace
metadata:
  name: cert-manager
  labels:
    name: cert-manager
EOF

kubectl apply -f /tmp/mlops-namespaces.yaml
rm -f /tmp/mlops-namespaces.yaml

print_status "Step 3: Install Cert-Manager (KServe prerequisite)..."
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.1/cert-manager.yaml
echo "Waiting for cert-manager to be ready..."
kubectl wait --for=condition=available deployment/cert-manager -n cert-manager --timeout=180s

print_status "Step 4: Install KServe CRDs..."
# Install KServe CRDs first
kubectl apply -f https://github.com/kserve/kserve/releases/download/v0.11.2/kserve.yaml
echo "Waiting for KServe controller..."
sleep 30  # Give time for CRDs to register
kubectl wait --for=condition=ready pod -l control-plane=kserve-controller-manager -n kserve --timeout=180s

print_status "Step 5: Install KServe built-in runtimes..."
kubectl apply -f https://github.com/kserve/kserve/releases/download/v0.11.2/kserve-runtimes.yaml

print_status "Step 6: Deploy Metrics Server..."
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

print_status "Step 7: Deploy NVIDIA GPU Operator (optional)..."
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia 2>/dev/null || true
helm repo update
helm install gpu-operator nvidia/gpu-operator \
  --namespace gpu-operator \
  --create-namespace \
  --set driver.enabled=false \
  --set toolkit.enabled=true \
  --wait || print_warning "GPU Operator installation skipped/partial"

print_status "Step 8: Deploy Triton Inference Server..."
cat > /tmp/triton-deployment.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: triton-inference-server
  namespace: triton
spec:
  replicas: 1
  selector:
    matchLabels:
      app: triton-inference
  template:
    metadata:
      labels:
        app: triton-inference
    spec:
      containers:
      - name: triton
        image: nvcr.io/nvidia/tritonserver:23.10-py3
        ports:
        - containerPort: 8000
          name: http
        - containerPort: 8001
          name: grpc
        env:
        - name: MODEL_REPOSITORY
          value: "/models"
        resources:
          requests:
            cpu: "1"
            memory: "2Gi"
          limits:
            cpu: "2"
            memory: "4Gi"
---
apiVersion: v1
kind: Service
metadata:
  name: triton-service
  namespace: triton
spec:
  selector:
    app: triton-inference
  ports:
  - name: http
    port: 8000
    targetPort: 8000
  type: ClusterIP
EOF

kubectl apply -f /tmp/triton-deployment.yaml
rm -f /tmp/triton-deployment.yaml

print_status "Step 9: Deploy Ray Operator..."
kubectl apply -k "github.com/ray-project/kuberay/ray-operator/config/default?ref=v1.0.0"
sleep 20

print_status "Step 10: Deploy Monitoring Stack..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
helm repo update
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --set grafana.adminPassword=admin \
  --wait

print_status "Step 11: Deploy NGINX Ingress Controller..."
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.1/deploy/static/provider/aws/deploy.yaml

echo ""
echo "=========================================="
print_status "✅ Platform deployment initiated!"
echo "=========================================="
echo ""
echo "⏳ Waiting for all components to be ready..."
echo ""

# Wait for key components
print_status "Waiting for KServe..."
kubectl wait --for=condition=ready pod -l control-plane=kserve-controller-manager -n kserve --timeout=300s

print_status "Waiting for Ingress Controller..."
kubectl wait --for=condition=available deployment/ingress-nginx-controller -n ingress-nginx --timeout=300s

print_status "Checking pod status..."
kubectl get pods -A

echo ""
echo "=========================================="
print_status "🚀 Platform is ready for model deployment!"
echo "=========================================="
echo ""
echo "To deploy your first model:"
echo "  ./scripts/deploy-model-kserve.sh --model llama2-7b"
echo ""
echo "To test KServe installation:"
echo "  kubectl get crd | grep inferenceservice"
echo "  kubectl get pods -n kserve"
echo ""
echo "For troubleshooting:"
echo "  kubectl logs -n kserve -l control-plane=kserve-controller-manager"