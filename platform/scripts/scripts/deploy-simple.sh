#!/bin/bash
# deploy-simple.sh - Simplified but robust MLOps platform deployment

set -e

echo "=========================================="
echo "MLOps Platform - Simple Deployment"
echo "=========================================="

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_status() { echo -e "${GREEN}[✓]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
print_error() { echo -e "${RED}[✗]${NC} $1"; }

# Function to wait with timeout
wait_for_deployment() {
    local namespace=$1
    local deployment=$2
    local timeout=${3:-300}
    
    print_status "Waiting for $deployment in $namespace..."
    
    local end_time=$((SECONDS + timeout))
    
    while [ $SECONDS -lt $end_time ]; do
        if kubectl get deployment "$deployment" -n "$namespace" &> /dev/null; then
            if kubectl rollout status deployment/"$deployment" -n "$namespace" --timeout=60s &> /dev/null; then
                print_status "$deployment is ready"
                return 0
            fi
        fi
        echo "  Still waiting... ($((end_time - SECONDS))s remaining)"
        sleep 10
    done
    
    print_warning "$deployment not ready after $timeout seconds"
    return 1
}

echo ""
echo "🔍 Step 1: Check cluster..."
kubectl cluster-info
kubectl get nodes

echo ""
echo "📁 Step 2: Create namespaces (skip if exist)..."
for ns in mlops-platform model-serving monitoring kserve triton; do
    if ! kubectl get namespace "$ns" &> /dev/null; then
        kubectl create namespace "$ns"
        print_status "Created namespace: $ns"
    else
        print_status "Namespace exists: $ns"
    fi
done

echo ""
echo "📦 Step 3: Install KServe directly (simplified)..."
print_status "Installing KServe CRDs..."

# Method 1: Try direct KServe installation
if kubectl apply -f https://github.com/kserve/kserve/releases/download/v0.11.2/kserve.yaml; then
    print_status "KServe CRDs installed"
else
    print_warning "Failed to install KServe CRDs, trying alternative..."
    
    # Method 2: Install cert-manager first if needed
    print_status "Installing cert-manager..."
    kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.1/cert-manager.yaml
    
    # Don't wait too long, continue with KServe
    sleep 30
    
    # Try KServe again
    if kubectl apply -f https://github.com/kserve/kserve/releases/download/v0.11.2/kserve.yaml; then
        print_status "KServe installed after cert-manager"
    else
        print_error "Failed to install KServe"
        echo "You may need to check network connectivity or use offline installation"
        exit 1
    fi
fi

echo ""
echo "⏳ Step 4: Wait for KServe controller..."
sleep 30  # Give time for CRDs to register

# Check if KServe controller pod exists
if kubectl get pods -n kserve -l control-plane=kserve-controller-manager --no-headers 2>/dev/null | grep -q Running; then
    print_status "KServe controller is running"
else
    print_warning "KServe controller not running yet, checking..."
    kubectl get pods -n kserve
    sleep 30
fi

echo ""
echo "🚀 Step 5: Install KServe runtimes..."
kubectl apply -f https://github.com/kserve/kserve/releases/download/v0.11.2/kserve-runtimes.yaml || {
    print_warning "Failed to install runtimes, continuing..."
}

echo ""
echo "📊 Step 6: Verify KServe installation..."
echo "Checking CRDs..."
kubectl get crd | grep kserve || {
    print_warning "No KServe CRDs found, retrying..."
    sleep 30
    kubectl get crd | grep kserve || print_error "KServe CRDs still not found"
}

echo ""
echo "🔧 Step 7: Deploy essential components..."

# Metrics server
print_status "Installing Metrics Server..."
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml || {
    print_warning "Metrics server installation failed, continuing..."
}

# Triton (simplified)
print_status "Deploying Triton Inference Server..."
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: triton
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: triton-test
  namespace: triton
spec:
  replicas: 1
  selector:
    matchLabels:
      app: triton-test
  template:
    metadata:
      labels:
        app: triton-test
    spec:
      containers:
      - name: triton
        image: nvcr.io/nvidia/tritonserver:23.10-py3
        args: ["tritonserver", "--model-repository=/models", "--strict-model-config=false"]
        ports:
        - containerPort: 8000
        - containerPort: 8001
        resources:
          requests:
            cpu: "500m"
            memory: "1Gi"
          limits:
            cpu: "1"
            memory: "2Gi"
EOF

echo ""
echo "📈 Step 8: Deploy monitoring..."
print_status "Setting up monitoring namespace..."
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

# Simple monitoring with just Prometheus
print_status "Installing Prometheus..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
helm repo update

helm upgrade --install prometheus prometheus-community/prometheus \
  --namespace monitoring \
  --set alertmanager.persistentVolume.enabled=false \
  --set server.persistentVolume.enabled=false \
  --set server.retention=1h \
  --wait || {
    print_warning "Prometheus installation had issues"
}

echo ""
echo "🌐 Step 9: Deploy ingress..."
print_status "Installing NGINX Ingress..."
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.1/deploy/static/provider/aws/deploy.yaml || {
    print_warning "Ingress installation failed, continuing..."
}

echo ""
echo "=========================================="
print_status "✅ Deployment completed (with possible warnings)"
echo "=========================================="
echo ""
echo "🔍 Verification steps:"
echo "1. Check KServe: kubectl get crd | grep inferenceservice"
echo "2. Check pods: kubectl get pods -A"
echo "3. Check services: kubectl get svc -A"
echo ""
echo "🚀 Next: Deploy a test model:"
echo "  ./scripts/deploy-test-model.sh"
echo ""
echo "📋 Or check detailed status:"
echo "  ./scripts/check-status.sh"