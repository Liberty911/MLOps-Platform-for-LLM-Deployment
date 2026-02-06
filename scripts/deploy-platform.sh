#!/bin/bash
# deploy-platform.sh - Complete MLOps Platform Deployment
# Robust, fault-tolerant deployment with retries and health checks

set -e

echo "=========================================="
echo "MLOps Platform for LLM Deployment"
echo "=========================================="

# Color codes for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function for colored output
print_status() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

# Function to check prerequisites
check_prerequisite() {
    if ! command -v $1 &> /dev/null; then
        print_error "$1 is not installed. Please install it first."
        return 1
    fi
    print_status "$1 is installed"
    return 0
}

# Function to retry a command
retry_command() {
    local cmd="$1"
    local max_attempts=${2:-3}
    local delay=${3:-10}
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        echo "Attempt $attempt of $max_attempts: $cmd"
        if eval "$cmd"; then
            return 0
        fi
        print_warning "Command failed, retrying in ${delay} seconds..."
        sleep $delay
        attempt=$((attempt + 1))
    done
    print_error "Command failed after $max_attempts attempts"
    return 1
}

# Function to wait for resources
wait_for_resource() {
    local resource_type="$1"
    local resource_name="$2"
    local namespace="${3:-}"
    local timeout="${4:-300}"
    
    local cmd="kubectl"
    [ -n "$namespace" ] && cmd="$cmd -n $namespace"
    cmd="$cmd wait --for=condition=ready $resource_type/$resource_name --timeout=${timeout}s"
    
    print_status "Waiting for $resource_type/$resource_name to be ready..."
    if retry_command "$cmd" 3 5; then
        print_status "$resource_type/$resource_name is ready"
    else
        print_error "$resource_type/$resource_name failed to become ready"
        return 1
    fi
}

echo "🔍 Step 1: Checking prerequisites..."
check_prerequisite kubectl || exit 1
check_prerequisite helm || exit 1
check_prerequisite aws || exit 1

echo ""
echo "🔗 Step 2: Verifying cluster access..."
if ! kubectl cluster-info &> /dev/null; then
    print_error "Cannot connect to Kubernetes cluster"
    print_warning "Trying to reconfigure kubectl..."
    aws eks update-kubeconfig --region us-east-1 --name mlops-llm-platform --profile wemo
fi

kubectl cluster-info
echo ""

echo "📊 Step 3: Checking cluster nodes..."
if ! kubectl get nodes &> /dev/null; then
    print_error "No nodes found in cluster"
    echo "Waiting for nodes to become available..."
    sleep 30
fi

kubectl get nodes
echo ""

echo "🚀 Step 4: Starting MLOps Platform deployment..."
echo "This will deploy all components in sequence with health checks."
echo ""

# Create namespaces first
print_status "Deploying namespaces..."
kubectl apply -f kubernetes/namespaces/mlops-namespaces.yaml || {
    print_warning "Namespaces already exist, continuing..."
}

# Deploy Metrics Server
print_status "Deploying Metrics Server..."
retry_command "kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml" 3 10
wait_for_resource deployment metrics-server kube-system 120

# Deploy NVIDIA GPU Operator (optional, continues on failure)
print_status "Deploying NVIDIA GPU Operator..."
if helm repo add nvidia https://helm.ngc.nvidia.com/nvidia 2>/dev/null; then
    helm repo update
    helm install gpu-operator nvidia/gpu-operator \
        --namespace gpu-operator \
        --create-namespace \
        --set driver.enabled=false \
        --set toolkit.enabled=true \
        --wait || {
        print_warning "GPU Operator installation had issues (non-critical)"
    }
else
    print_warning "Failed to add NVIDIA Helm repo (skipping GPU Operator)"
fi

# Deploy EFS CSI Driver
print_status "Deploying EFS CSI Driver..."
retry_command "kubectl apply -k 'github.com/kubernetes-sigs/aws-efs-csi-driver/deploy/kubernetes/overlays/stable/?ref=release-1.5'" 3 10

# Deploy KServe
print_status "Deploying KServe..."
if [ -f "kserve/install-kserve.sh" ]; then
    bash kserve/install-kserve.sh
else
    print_warning "KServe install script not found, installing directly..."
    # Install cert-manager first
    kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.1/cert-manager.yaml
    wait_for_resource deployment cert-manager cert-manager 180
    
    # Install KServe
    kubectl apply -f https://github.com/kserve/kserve/releases/download/v0.11.2/kserve.yaml
    wait_for_resource deployment kserve-controller-manager kserve 180
fi

# Deploy Triton Inference Server
print_status "Deploying Triton Inference Server..."
if [ -f "triton/deployment/triton-deployment.yaml" ]; then
    kubectl apply -f triton/deployment/triton-deployment.yaml
    wait_for_resource deployment triton-inference-server triton 180
else
    print_warning "Triton deployment file not found, skipping..."
fi

# Deploy Ray Operator
print_status "Deploying Ray Operator..."
retry_command "kubectl apply -k 'github.com/ray-project/kuberay/ray-operator/config/default?ref=v1.0.0'" 3 10
sleep 20  # Wait for operator to initialize

# Deploy Ray Cluster
print_status "Deploying Ray Cluster..."
if [ -f "ray/ray-cluster.yaml" ]; then
    kubectl apply -f ray/ray-cluster.yaml
    wait_for_resource raycluster ray-cluster ray-cluster 180
else
    print_warning "Ray cluster configuration not found, skipping..."
fi

# Deploy Monitoring Stack
print_status "Deploying Monitoring Stack (Prometheus & Grafana)..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
helm repo update
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
    --namespace monitoring \
    --create-namespace \
    --set grafana.adminPassword=admin \
    --set prometheus.prometheusSpec.resources.requests.memory=512Mi \
    --set prometheus.prometheusSpec.resources.requests.cpu=500m \
    --wait || {
    print_warning "Monitoring stack installation had issues"
}

# Deploy Weights & Biases
print_status "Deploying Weights & Biases..."
if [ -f "wandb/wandb-secret.yaml" ]; then
    kubectl apply -f wandb/
else
    print_warning "W&B configuration not found, skipping..."
fi

# Deploy NGINX Ingress Controller
print_status "Deploying NGINX Ingress Controller..."
retry_command "kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.1/deploy/static/provider/aws/deploy.yaml" 3 10
wait_for_resource deployment ingress-nginx-controller ingress-nginx 180

echo ""
echo "=========================================="
echo "✅ MLOps Platform Deployment Complete!"
echo "=========================================="
echo ""

# Show deployment status
print_status "Deployment Summary:"
echo "======================"
kubectl get pods -A --show-labels | grep -E "(NAME|mlops|model-serving|ray|monitoring|kserve|triton|wandb)"

echo ""
print_status "Access Information:"
echo "======================"
echo "Grafana Dashboard:"
echo "  kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80"
echo "  Username: admin, Password: admin"
echo ""
echo "Prometheus:"
echo "  kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090"
echo ""
echo "Ray Dashboard:"
echo "  kubectl port-forward -n ray-cluster svc/ray-dashboard 8265:8265"
echo ""
echo "To test KServe (after deploying a model):"
echo "  kubectl get inferenceservices -n model-serving"
echo ""
print_status "Next Steps:"
echo "=============="
echo "1. Deploy your first model:"
echo "   ./scripts/deploy-model.sh --model llama2-7b"
echo ""
echo "2. Test the deployment:"
echo "   ./scripts/test-platform.sh"
echo ""
echo "3. Monitor the platform:"
echo "   watch kubectl get pods -A"
echo ""
echo "4. Check logs if issues:"
echo "   kubectl get events -A --sort-by='.lastTimestamp'"
echo "=========================================="