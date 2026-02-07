#!/bin/bash
# test-kserve.sh - Test KServe installation and functionality

set -e

echo "=========================================="
echo "KServe Test Suite"
echo "=========================================="

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

test_passed() { echo -e "${GREEN}[PASS]${NC} $1"; }
test_failed() { echo -e "${RED}[FAIL]${NC} $1"; }
test_warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }

echo ""
echo "🔍 Test 1: Check KServe CRDs..."
if kubectl get crd inferenceservices.serving.kserve.io &> /dev/null; then
    test_passed "KServe InferenceService CRD exists"
else
    test_failed "KServe InferenceService CRD not found"
    exit 1
fi

echo ""
echo "🔍 Test 2: Check KServe controller..."
if kubectl get deployment kserve-controller-manager -n kserve &> /dev/null; then
    test_passed "KServe controller deployment exists"
    
    # Check if controller is ready
    if kubectl get deployment kserve-controller-manager -n kserve -o jsonpath='{.status.readyReplicas}' | grep -q 1; then
        test_passed "KServe controller is ready"
    else
        test_warning "KServe controller not ready yet"
    fi
else
    test_failed "KServe controller not found"
fi

echo ""
echo "🔍 Test 3: Create test namespace..."
kubectl create namespace kserve-test --dry-run=client -o yaml | kubectl apply -f - &> /dev/null
test_passed "Created test namespace"

echo ""
echo "🔍 Test 4: Deploy test InferenceService..."
cat > /tmp/test-kserve.yaml << 'EOF'
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: sklearn-iris
  namespace: kserve-test
spec:
  predictor:
    model:
      modelFormat:
        name: sklearn
      storageUri: gs://kfserving-examples/models/sklearn/1.0/model
      resources:
        requests:
          cpu: "100m"
          memory: "256Mi"
        limits:
          cpu: "500m"
          memory: "512Mi"
EOF

kubectl apply -f /tmp/test-kserve.yaml &> /dev/null
test_passed "Test InferenceService created"

echo ""
echo "🔍 Test 5: Wait for test service to be ready..."
for i in {1..20}; do
    STATUS=$(kubectl get inferenceservice sklearn-iris -n kserve-test -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
    
    if [ "$STATUS" = "True" ]; then
        test_passed "Test InferenceService is ready"
        break
    elif [ "$STATUS" = "False" ]; then
        test_failed "Test InferenceService failed"
        kubectl describe inferenceservice sklearn-iris -n kserve-test
        break
    else
        echo "  Waiting... (attempt $i/20)"
        sleep 10
    fi
done

echo ""
echo "🔍 Test 6: Cleanup test resources..."
kubectl delete inferenceservice sklearn-iris -n kserve-test --ignore-not-found &> /dev/null
kubectl delete namespace kserve-test --ignore-not-found &> /dev/null
test_passed "Test resources cleaned up"

echo ""
echo "=========================================="
echo "✅ KServe Test Suite Complete"
echo "=========================================="
echo ""
echo "Next: Deploy your LLM models:"
echo "  ./scripts/deploy-model-kserve.sh --model llama2-7b"