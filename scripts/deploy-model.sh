#!/bin/bash
# deploy-model.sh - Deploy LLM models with health checks and validation

set -e

# Default values
MODEL="llama2-7b"
GPU_TYPE=""
NAMESPACE="model-serving"
TIMEOUT=300
RETRIES=3

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --model)
            MODEL="$2"
            shift 2
            ;;
        --gpu)
            GPU_TYPE="$2"
            shift 2
            ;;
        --namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        --timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        --retries)
            RETRIES="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --model <name>      Model to deploy (default: llama2-7b)"
            echo "  --gpu <type>        GPU type (a10g, v100, a100)"
            echo "  --namespace <name>  Kubernetes namespace (default: model-serving)"
            echo "  --timeout <sec>     Timeout in seconds (default: 300)"
            echo "  --retries <num>     Number of retries (default: 3)"
            echo "  --help, -h          Show this help message"
            echo ""
            echo "Available models: llama2-7b, falcon-7b, mistral-7b"
            exit 0
            ;;
        *)
            echo "Error: Unknown option $1"
            echo "Use --help for usage information"
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
        CONFIG_FILE="kserve/inference-service/${MODEL}-inference-service.yaml"
        ;;
    *)
        print_error "Unknown model: $MODEL"
        echo "Available models: llama2-7b, falcon-7b, mistral-7b"
        exit 1
        ;;
esac

echo "=========================================="
echo "Deploying Model: $MODEL_NAME"
echo "=========================================="

# Check if namespace exists
if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
    print_warning "Namespace $NAMESPACE does not exist, creating..."
    kubectl create namespace "$NAMESPACE"
fi

# Check if config file exists, create if not
if [ ! -f "$CONFIG_FILE" ]; then
    print_warning "Config file not found: $CONFIG_FILE"
    print_status "Creating default configuration..."
    
    mkdir -p "$(dirname "$CONFIG_FILE")"
    
    # Create default configuration
    cat > "$CONFIG_FILE" << EOF
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: $MODEL_NAME
  namespace: $NAMESPACE
  annotations:
    autoscaling.knative.dev/minScale: "1"
    autoscaling.knative.dev/maxScale: "10"
    autoscaling.knative.dev/target: "80"
    sidecar.istio.io/inject: "false"
spec:
  predictor:
    model:
      modelFormat:
        name: huggingface
      runtime: kserve-tritonserver
      runtimeVersion: 22.12-py3
      storageUri: s3://mlops-platform-models-916697696148/$MODEL_NAME/
      resources:
        requests:
          cpu: "4"
          memory: 16Gi
          nvidia.com/gpu: "1"
        limits:
          cpu: "8"
          memory: 32Gi
          nvidia.com/gpu: "1"
      env:
        - name: HF_MODEL_ID
          value: "$MODEL_NAME"
        - name: TRITON_MAX_BATCH_SIZE
          value: "8"
        - name: TRITON_GPU_MEMORY_BYTE_SIZE
          value: "34359738368"
    minReplicas: 1
    maxReplicas: 5
    scaleTarget: 80
    scaleMetric: cpu
EOF
    
    print_status "Created default configuration at: $CONFIG_FILE"
fi

# Update GPU type if specified
if [ -n "$GPU_TYPE" ]; then
    print_status "Configuring GPU type: $GPU_TYPE"
    sed -i "s/nvidia.com\/gpu: \"1\"/nvidia.com\/gpu: \"1\"/g" "$CONFIG_FILE"
fi

# Deploy the model
print_status "Deploying $MODEL_NAME to namespace: $NAMESPACE"
kubectl apply -f "$CONFIG_FILE"

# Wait for deployment with retries
print_status "Waiting for $MODEL_NAME to be ready (timeout: ${TIMEOUT}s)..."
for ((i=1; i<=RETRIES; i++)); do
    echo "Attempt $i of $RETRIES..."
    
    if kubectl wait --for=condition=ready "inferenceservice/$MODEL_NAME" \
        -n "$NAMESPACE" \
        --timeout="${TIMEOUT}s" 2>/dev/null; then
        print_status "$MODEL_NAME is ready!"
        break
    fi
    
    if [ $i -lt $RETRIES ]; then
        print_warning "$MODEL_NAME not ready yet, retrying in 10 seconds..."
        sleep 10
    else
        print_error "$MODEL_NAME failed to become ready after $RETRIES attempts"
        
        # Show detailed error information
        echo ""
        print_warning "Troubleshooting information:"
        kubectl describe inferenceservice "$MODEL_NAME" -n "$NAMESPACE"
        echo ""
        kubectl get pods -n "$NAMESPACE" -l "serving.kserve.io/inferenceservice=$MODEL_NAME"
        echo ""
        kubectl logs -n "$NAMESPACE" -l "serving.kserve.io/inferenceservice=$MODEL_NAME" --tail=20
        
        exit 1
    fi
done

# Get service information
print_status "Deployment successful! Service information:"
echo "=========================================="
kubectl get inferenceservice "$MODEL_NAME" -n "$NAMESPACE"

# Get the service URL
SERVICE_URL=$(kubectl get inferenceservice "$MODEL_NAME" -n "$NAMESPACE" -o jsonpath='{.status.url}' 2>/dev/null || echo "")
if [ -n "$SERVICE_URL" ]; then
    echo ""
    print_status "Inference URL: $SERVICE_URL"
    
    # Create a test script for this model
    TEST_SCRIPT="examples/test-$MODEL_NAME.py"
    cat > "$TEST_SCRIPT" << EOF
#!/usr/bin/env python3
# Test script for $MODEL_NAME

import requests
import json
import sys

def test_model():
    # Remove http:// prefix if present
    url = "$SERVICE_URL"
    if url.startswith("http://"):
        url = url[7:]
    elif url.startswith("https://"):
        url = url[8:]
    
    # For internal testing, use cluster DNS
    internal_url = f"http://$MODEL_NAME.$NAMESPACE.svc.cluster.local:8080"
    
    headers = {"Content-Type": "application/json"}
    payload = {
        "inputs": [{
            "name": "text_input",
            "shape": [1],
            "datatype": "BYTES",
            "data": ["Explain machine learning in simple terms:"]
        }]
    }
    
    try:
        print(f"Testing $MODEL_NAME at {internal_url}")
        response = requests.post(
            f"{internal_url}/v2/models/$MODEL_NAME/infer",
            headers=headers,
            json=payload,
            timeout=30
        )
        
        if response.status_code == 200:
            print("✅ Inference successful!")
            result = response.json()
            print(f"Response shape: {result['outputs'][0]['shape']}")
            return True
        else:
            print(f"❌ Inference failed: {response.status_code}")
            print(f"Response: {response.text}")
            return False
            
    except Exception as e:
        print(f"❌ Error: {e}")
        return False

if __name__ == "__main__":
    if test_model():
        sys.exit(0)
    else:
        sys.exit(1)
EOF
    
    chmod +x "$TEST_SCRIPT"
    print_status "Created test script: $TEST_SCRIPT"
fi

echo ""
print_status "Next steps:"
echo "=============="
echo "1. Test the model:"
echo "   python $TEST_SCRIPT"
echo ""
echo "2. Check model logs:"
echo "   kubectl logs -n $NAMESPACE -l serving.kserve.io/inferenceservice=$MODEL_NAME"
echo ""
echo "3. Monitor model performance:"
echo "   kubectl get pods -n $NAMESPACE -w"
echo ""
echo "4. Delete the model:"
echo "   kubectl delete inferenceservice $MODEL_NAME -n $NAMESPACE"
echo "=========================================="