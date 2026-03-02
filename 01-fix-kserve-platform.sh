#!/bin/bash
set -e

echo ">>> Fetching and patching KServe inferenceservice-config..."
kubectl get configmap inferenceservice-config -n kserve -o yaml > /tmp/inferenceservice-config.yaml

# Patch the malformed 'cpuModelcar' and 'memoryModelcar' keys to valid Kubernetes resource requests/limits
sed -i 's/cpuModelcar/cpuRequest/g' /tmp/inferenceservice-config.yaml
sed -i 's/memoryModelcar/memoryRequest/g' /tmp/inferenceservice-config.yaml
sed -i 's/cpuLimitcar/cpuLimit/g' /tmp/inferenceservice-config.yaml
sed -i 's/memoryLimitcar/memoryLimit/g' /tmp/inferenceservice-config.yaml

# Apply the corrected configuration
kubectl apply -f /tmp/inferenceservice-config.yaml

echo ">>> Restarting KServe Controller Manager to apply configuration..."
kubectl rollout restart deployment kserve-controller-manager -n kserve

echo ">>> Waiting for KServe Controller to be fully ready..."
kubectl rollout status deployment kserve-controller-manager -n kserve --timeout=120s

echo "Platform configuration successfully patched."