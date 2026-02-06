#!/bin/bash
# test-platform.sh - Comprehensive platform health check

set -e

echo "=========================================="
echo "MLOps Platform Health Check"
echo "=========================================="

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

SUCCESS=0
WARNING=0
ERROR=0

check() {
    if eval "$1"; then
        echo -e "${GREEN}[✓]${NC} $2"
        ((SUCCESS++))
        return 0
    else
        echo -e "${RED}[✗]${NC} $2"
        ((ERROR++))
        return 1
    fi
}

warn() {
    echo -e "${YELLOW}[!]${NC} $1"
    ((WARNING++))
}

echo ""
echo "🔍 Checking cluster connectivity..."
check "kubectl cluster-info &> /dev/null" "Kubernetes cluster accessible"
check "kubectl get nodes &> /dev/null" "Nodes accessible"

echo ""
echo "📊 Checking node status..."
NODE_COUNT=$(kubectl get nodes --no-headers | wc -l)
if [ "$NODE_COUNT" -gt 0 ]; then
    echo -e "${GREEN}[✓]${NC} Found $NODE_COUNT node(s)"
    ((SUCCESS++))
    
    # Check node readiness
    READY_NODES=$(kubectl get nodes --no-headers | grep -c Ready)
    if [ "$READY_NODES" -eq "$NODE_COUNT" ]; then
        echo -e "${GREEN}[✓]${NC} All nodes are Ready"
        ((SUCCESS++))
    else
        warn "Only $READY_NODES of $NODE_COUNT nodes are Ready"
    fi
else
    echo -e "${RED}[✗]${NC} No nodes found"
    ((ERROR++))
fi

echo ""
echo "🏗️  Checking namespace deployment..."
NAMESPACES=("mlops-platform" "model-serving" "monitoring" "kserve" "triton" "ray-cluster" "wandb")
for ns in "${NAMESPACES[@]}"; do
    if kubectl get namespace "$ns" &> /dev/null; then
        echo -e "${GREEN}[✓]${NC} Namespace $ns exists"
        ((SUCCESS++))
    else
        warn "Namespace $ns does not exist"
    fi
done

echo ""
echo "🚀 Checking core services..."
SERVICES=(
    "deployment metrics-server kube-system"
    "deployment prometheus-kube-prometheus-operator monitoring"
    "deployment prometheus-grafana monitoring"
    "deployment ingress-nginx-controller ingress-nginx"
)

for service in "${SERVICES[@]}"; do
    read -r resource name namespace <<< "$service"
    if kubectl get "$resource" "$name" -n "$namespace" &> /dev/null; then
        echo -e "${GREEN}[✓]${NC} $resource/$name in $namespace"
        ((SUCCESS++))
    else
        warn "$resource/$name not found in $namespace"
    fi
done

echo ""
echo "🤖 Checking ML components..."
# Check KServe
if kubectl get deployment kserve-controller-manager -n kserve &> /dev/null; then
    echo -e "${GREEN}[✓]${NC} KServe controller is running"
    ((SUCCESS++))
else
    warn "KServe controller not found"
fi

# Check Triton
if kubectl get deployment triton-inference-server -n triton &> /dev/null; then
    echo -e "${GREEN}[✓]${NC} Triton Inference Server is running"
    ((SUCCESS++))
else
    warn "Triton Inference Server not found"
fi

# Check Ray
if kubectl get raycluster ray-cluster -n ray-cluster &> /dev/null; then
    echo -e "${GREEN}[✓]${NC} Ray cluster is running"
    ((SUCCESS++))
else
    warn "Ray cluster not found"
fi

echo ""
echo "📈 Checking pod status..."
TOTAL_PODS=$(kubectl get pods -A --no-headers 2>/dev/null | wc -l || echo "0")
RUNNING_PODS=$(kubectl get pods -A --no-headers 2>/dev/null | grep -c Running || echo "0")

if [ "$TOTAL_PODS" -gt 0 ]; then
    echo -e "${GREEN}[✓]${NC} Found $TOTAL_PODS total pods"
    ((SUCCESS++))
    
    if [ "$RUNNING_PODS" -eq "$TOTAL_PODS" ]; then
        echo -e "${GREEN}[✓]${NC} All $RUNNING_PODS pods are Running"
        ((SUCCESS++))
    else
        warn "Only $RUNNING_PODS of $TOTAL_PODS pods are Running"
        
        # Show non-running pods
        echo ""
        echo "Non-running pods:"
        kubectl get pods -A --no-headers | grep -v Running | head -10
    fi
else
    warn "No pods found in cluster"
fi

echo ""
echo "=========================================="
echo "📊 Health Check Summary"
echo "=========================================="
echo -e "${GREEN}Successful checks:${NC} $SUCCESS"
echo -e "${YELLOW}Warnings:${NC} $WARNING"
echo -e "${RED}Errors:${NC} $ERROR"
echo ""

if [ $ERROR -eq 0 ]; then
    echo -e "${GREEN}✅ Platform is healthy!${NC}"
    
    echo ""
    echo "🚀 Next actions:"
    echo "1. Deploy a model: ./scripts/deploy-model.sh --model llama2-7b"
    echo "2. Access monitoring:"
    echo "   - Grafana: kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80"
    echo "   - Prometheus: kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090"
    echo "3. View all resources: kubectl get all -A"
    
    exit 0
else
    echo -e "${RED}❌ Platform has issues that need attention${NC}"
    
    echo ""
    echo "🔧 Troubleshooting steps:"
    echo "1. Check cluster events: kubectl get events -A --sort-by='.lastTimestamp'"
    echo "2. Check pod logs for errors"
    echo "3. Verify node resources and networking"
    echo "4. Run deployment again: ./scripts/deploy-platform.sh"
    
    exit 1
fi