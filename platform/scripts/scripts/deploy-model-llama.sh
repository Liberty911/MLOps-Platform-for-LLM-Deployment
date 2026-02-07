#!/bin/bash
# scripts/deploy-model-llama.sh - Deploys a Llama2 model

set -e
MODEL_NAME=${1:-"llama2-7b"}

echo "🤖 Deploying model: $MODEL_NAME"

# Apply the inference service configuration
kubectl apply -f kserve/inference-service/${MODEL_NAME}.yaml

# Wait for the service to be ready
echo "Waiting for model to be ready..."
kubectl wait --for=condition=ready inferenceservice ${MODEL_NAME} -n model-serving --timeout=300s

SERVICE_URL=$(kubectl get inferenceservice ${MODEL_NAME} -n model-serving -o jsonpath='{.status.url}')
echo "✅ Model deployed!"
echo "Inference endpoint: $SERVICE_URL"