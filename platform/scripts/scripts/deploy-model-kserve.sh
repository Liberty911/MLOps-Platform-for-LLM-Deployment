#!/bin/bash
# deploy-model-kserve.sh - Deploy models to KServe

set -e

echo "=========================================="
echo "KServe Model Deployment"
echo "=========================================="

# Default values
MODEL="llama2-7b"
NAMESPACE="model-serving"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --model)
            MODEL="$2"
            shift 2
            ;;
        --namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [--model <name>] [--namespace <name>]"
            echo "Models: llama2-7b, falcon-7b, mistral-7b"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_status() { echo -e "${GREEN}[✓]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
print_error() { echo -e "${RED}[✗]${NC} $1"; }

# Validate model
case $MODEL in
    llama2-7b|falcon-7b|mistral-7b)
        MODEL_NAME="$MODEL"
        ;;
    *)
        print_error "Unknown model: $MODEL"
        echo "Available models: llama2-7b, falcon-7b, mistral-7b"
        exit 1
        ;;
esac

# Check if KServe CRDs are installed
print_status "Checking KServe installation..."
if ! kubectl get crd inferenceservices.serving.kserve.io &> /dev/null; then
    print_error "KServe CRDs not found. Please install KServe first."
    echo "Run: ./scripts/deploy-platform-sequential.sh"
    exit 1
fi

print_status "KServe CRDs are installed"

# Create namespace if it doesn't exist
if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
    print_warning "Creating namespace: $NAMESPACE"
    kubectl create namespace "$NAMESPACE"
fi

# Create model configuration
CONFIG_DIR="kserve/inference-service"
CONFIG_FILE="$CONFIG_DIR/${MODEL_NAME}.yaml"
mkdir -p "$CONFIG_DIR"

print_status "Creating configuration for $MODEL_NAME..."

cat > "$CONFIG_FILE" << EOF
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: $MODEL_NAME
  namespace: $NAMESPACE
  annotations:
    sidecar.istio.io/inject: "false"
spec:
  predictor:
    model:
      modelFormat:
        name: pytorch
      storageUri: gs://kfserving-examples/models/torchserve/image_classifier
      resources:
        requests:
          cpu: "1"
          memory: "2Gi"
        limits:
          cpu: "2"
          memory: "4Gi"
EOF

print_status "Deploying $MODEL_NAME..."
kubectl apply -f "$CONFIG_FILE"

echo ""
print_status "Waiting for model to be ready..."
for i in {1..30}; do
    STATUS=$(kubectl get inferenceservice $MODEL_NAME -n $NAMESPACE -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
    
    if [ "$STATUS" = "True" ]; then
        print_status "$MODEL_NAME is ready!"
        break
    elif [ "$STATUS" = "False" ]; then
        print_error "$MODEL_NAME failed to deploy"
        kubectl describe inferenceservice $MODEL_NAME -n $NAMESPACE
        exit 1
    else
        echo "  Status: $STATUS (attempt $i/30)"
        sleep 10
    fi
done

if [ "$STATUS" != "True" ]; then
    print_warning "$MODEL_NAME still not ready after 5 minutes"
    kubectl describe inferenceservice $MODEL_NAME -n $NAMESPACE
fi

# Get service information
echo ""
print_status "Deployment successful!"
echo "=============================="
kubectl get inferenceservice $MODEL_NAME -n $NAMESPACE

SERVICE_URL=$(kubectl get inferenceservice $MODEL_NAME -n $NAMESPACE -o jsonpath='{.status.url}' 2>/dev/null || echo "")
if [ -n "$SERVICE_URL" ]; then
    echo ""
    print_status "Inference URL: $SERVICE_URL"
    
    # Create test script
    TEST_SCRIPT="examples/test-${MODEL_NAME}.py"
    cat > "$TEST_SCRIPT" << EOF
#!/usr/bin/env python3
# Test script for $MODEL_NAME on KServe

import requests
import json

def test_kserve_model():
    # Note: For internal testing, use the service name
    # External URL: $SERVICE_URL
    # Internal DNS: http://$MODEL_NAME.$NAMESPACE.svc.cluster.local
    
    headers = {"Content-Type": "application/json"}
    
    # Simple test payload
    payload = {
        "instances": [
            {"data": "Test input for $MODEL_NAME"}
        ]
    }
    
    try:
        print(f"Testing $MODEL_NAME on KServe...")
        
        # Try internal service first
        internal_url = f"http://$MODEL_NAME-predictor-default.$NAMESPACE.svc.cluster.local"
        
        response = requests.post(
            f"{internal_url}/v1/models/$MODEL_NAME:predict",
            headers=headers,
            json=payload,
            timeout=10
        )
        
        if response.status_code == 200:
            print("✅ KServe inference successful!")
            print(f"Response: {response.json()}")
            return True
        else:
            print(f"⚠️  KServe returned status: {response.status_code}")
            print(f"Response: {response.text}")
            
    except Exception as e:
        print(f"❌ Error testing KServe: {e}")
    
    return False

if __name__ == "__main__":
    test_kserve_model()
EOF
    
    chmod +x "$TEST_SCRIPT"
    print_status "Created test script: $TEST_SCRIPT"
fi

echo ""
print_status "Next steps:"
echo "=============="
echo "1. Check model status:"
echo "   kubectl get inferenceservice -n $NAMESPACE"
echo ""
echo "2. View model pods:"
echo "   kubectl get pods -n $NAMESPACE -l serving.kserve.io/inferenceservice=$MODEL_NAME"
echo ""
echo "3. Check logs:"
echo "   kubectl logs -n $NAMESPACE -l serving.kserve.io/inferenceservice=$MODEL_NAME"
echo ""
echo "4. Test inference:"
echo "   python $TEST_SCRIPT"
echo ""
echo "5. Delete model:"
echo "   kubectl delete inferenceservice $MODEL_NAME -n $NAMESPACE"