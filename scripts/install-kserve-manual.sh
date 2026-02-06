#!/bin/bash
# install-kserve-manual.sh - Manual KServe installation with verification

echo "=========================================="
echo "Manual KServe Installation"
echo "=========================================="

echo ""
echo "📦 Step 1: Create kserve namespace..."
kubectl create namespace kserve --dry-run=client -o yaml | kubectl apply -f -

echo ""
echo "🔧 Step 2: Install KServe CRDs..."
echo "Downloading and applying KServe manifests..."
curl -L https://github.com/kserve/kserve/releases/download/v0.11.2/kserve.yaml -o /tmp/kserve.yaml

echo ""
echo "Applying KServe CRDs (this may take a moment)..."
kubectl apply -f /tmp/kserve.yaml

echo ""
echo "⏳ Step 3: Wait for CRDs to register..."
echo "Checking every 10 seconds for 2 minutes..."

for i in {1..12}; do
    echo "Attempt $i/12: Checking KServe CRDs..."
    
    if kubectl get crd inferenceservices.serving.kserve.io &> /dev/null; then
        echo "✅ KServe CRDs are registered!"
        break
    fi
    
    if [ $i -eq 12 ]; then
        echo "❌ KServe CRDs still not registered after 2 minutes"
        echo "You may need to check:"
        echo "1. Network connectivity"
        echo "2. Kubernetes API server logs"
        echo "3. Try installing cert-manager first"
        exit 1
    fi
    
    sleep 10
done

echo ""
echo "🚀 Step 4: Check KServe controller..."
echo "Waiting for controller pod to start..."

for i in {1..10}; do
    echo "Checking controller pods (attempt $i/10)..."
    kubectl get pods -n kserve
    
    if kubectl get pods -n kserve -l control-plane=kserve-controller-manager --no-headers 2>/dev/null | grep -q Running; then
        echo "✅ KServe controller is running!"
        break
    fi
    
    sleep 10
done

echo ""
echo "📊 Step 5: Verify installation..."
echo ""
echo "List of KServe CRDs:"
kubectl get crd | grep kserve

echo ""
echo "KServe pods:"
kubectl get pods -n kserve

echo ""
echo "=========================================="
echo "✅ KServe installation complete!"
echo "=========================================="
echo ""
echo "To deploy a test model:"
echo "  ./scripts/deploy-test-model.sh"
echo ""
echo "To check KServe status:"
echo "  kubectl get crd | grep kserve"
echo "  kubectl get pods -n kserve"