#!/bin/bash
# deploy-test-model.sh - Deploy a simple test model to verify KServe

set -e

echo "=========================================="
echo "Deploying Test Model to KServe"
echo "=========================================="

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

print_status() { echo -e "${GREEN}[✓]${NC} $1"; }
print_error() { echo -e "${RED}[✗]${NC} $1"; }

# Check if KServe is installed
echo ""
echo "🔍 Checking KServe installation..."
if ! kubectl get crd inferenceservices.serving.kserve.io &> /dev/null; then
    print_error "KServe CRDs not found!"
    echo ""
    echo "To install KServe, run:"
    echo "  kubectl apply -f https://github.com/kserve/kserve/releases/download/v0.11.2/kserve.yaml"
    echo ""
    echo "Then wait 30 seconds and run this script again."
    exit 1
fi

print_status "KServe CRDs are installed"

# Create namespace if needed
echo ""
echo "📁 Setting up namespace..."
if ! kubectl get namespace model-serving &> /dev/null; then
    kubectl create namespace model-serving
    print_status "Created namespace: model-serving"
else
    print_status "Namespace exists: model-serving"
fi

echo ""
echo "🚀 Deploying sklearn iris model (simple test)..."
cat <<EOF | kubectl apply -f -
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: sklearn-iris
  namespace: model-serving
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

print_status "Test model deployed: sklearn-iris"

echo ""
echo "⏳ Waiting for model to be ready..."
for i in {1..30}; do
    STATUS=$(kubectl get inferenceservice sklearn-iris -n model-serving -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
    
    if [ "$STATUS" = "True" ]; then
        print_status "Model is ready!"
        break
    elif [ "$STATUS" = "False" ]; then
        print_error "Model failed to deploy"
        kubectl describe inferenceservice sklearn-iris -n model-serving
        exit 1
    else
        echo "  Status: $STATUS (attempt $i/30)"
        sleep 5
    fi
done

if [ "$STATUS" != "True" ]; then
    print_error "Model not ready after 2.5 minutes"
    kubectl describe inferenceservice sklearn-iris -n model-serving
fi

echo ""
echo "📊 Model status:"
kubectl get inferenceservice sklearn-iris -n model-serving

echo ""
echo "🔗 Service URL:"
URL=$(kubectl get inferenceservice sklearn-iris -n model-serving -o jsonpath='{.status.url}' 2>/dev/null || echo "Not available")
echo "  $URL"

echo ""
echo "🐍 Creating Python test script..."
cat > test-kserve.py << 'EOF'
#!/usr/bin/env python3
# Test script for KServe sklearn-iris model

import requests
import json
import sys

def test_sklearn_iris():
    # This is a simple test for the sklearn iris model
    # Note: The external URL might not be accessible yet
    # We'll test using port-forwarding
    
    print("Testing KServe sklearn-iris model...")
    print("Note: You may need to port-forward to access the service")
    print("Run: kubectl port-forward svc/sklearn-iris-predictor-default -n model-serving 8080:80")
    print("")
    
    # Test data for iris classification
    payload = {
        "instances": [
            [6.8, 2.8, 4.8, 1.4],
            [6.0, 3.4, 4.5, 1.6]
        ]
    }
    
    headers = {"Content-Type": "application/json"}
    
    try:
        # Try local port-forward first
        response = requests.post(
            "http://localhost:8080/v1/models/sklearn-iris:predict",
            headers=headers,
            json=payload,
            timeout=10
        )
        
        if response.status_code == 200:
            print("✅ Success! Model is responding.")
            print(f"Predictions: {response.json()}")
            return True
        else:
            print(f"⚠️  Model returned status: {response.status_code}")
            print(f"Response: {response.text}")
            
    except requests.exceptions.ConnectionError:
        print("⚠️  Could not connect to localhost:8080")
        print("Make sure to run: kubectl port-forward svc/sklearn-iris-predictor-default -n model-serving 8080:80")
    except Exception as e:
        print(f"❌ Error: {e}")
    
    return False

if __name__ == "__main__":
    if test_sklearn_iris():
        sys.exit(0)
    else:
        sys.exit(1)
EOF

chmod +x test-kserve.py
print_status "Created test script: test-kserve.py"

echo ""
echo "=========================================="
print_status "✅ Test model deployed successfully!"
echo "=========================================="
echo ""
echo "📋 Next steps:"
echo "1. Check model pods: kubectl get pods -n model-serving"
echo "2. Test the model: ./test-kserve.py"
echo "3. View logs: kubectl logs -n model-serving -l serving.kserve.io/inferenceservice=sklearn-iris"
echo ""
echo "🔧 Troubleshooting:"
echo "  If test fails, run: kubectl describe inferenceservice sklearn-iris -n model-serving"
echo ""
echo "🗑️  To clean up:"
echo "  kubectl delete inferenceservice sklearn-iris -n model-serving"