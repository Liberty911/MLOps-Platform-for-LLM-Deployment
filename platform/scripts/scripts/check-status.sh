#!/bin/bash
# check-status.sh - Quick status check for MLOps platform

echo "=========================================="
echo "MLOps Platform Status Check"
echo "=========================================="

echo ""
echo "🔍 1. Cluster info:"
kubectl cluster-info 2>/dev/null || echo "Cannot connect to cluster"

echo ""
echo "📊 2. Nodes:"
kubectl get nodes 2>/dev/null || echo "No nodes found"

echo ""
echo "📦 3. KServe CRDs:"
kubectl get crd 2>/dev/null | grep -E "(inferenceservice|trainedmodel)" || echo "No KServe CRDs found"

echo ""
echo "🏗️  4. Namespaces:"
kubectl get namespaces 2>/dev/null | grep -E "(mlops|model|kserve|triton|monitoring)" || echo "No MLOps namespaces found"

echo ""
echo "🚀 5. Pods (all namespaces):"
kubectl get pods -A 2>/dev/null | head -20

echo ""
echo "🔧 6. Services:"
kubectl get svc -A 2>/dev/null | grep -E "(LoadBalancer|ingress)" || echo "No external services found"

echo ""
echo "=========================================="
echo "✅ Status check complete"
echo "=========================================="
echo ""
echo "If KServe CRDs are missing, run:"
echo "  kubectl apply -f https://github.com/kserve/kserve/releases/download/v0.11.2/kserve.yaml"
echo ""
echo "To install a test model:"
echo "  ./scripts/deploy-test-model.sh"