#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

echo "Creating namespaces..."
kubectl apply -f "${ROOT}/platform/cluster/kubernetes/namespaces/mlops-namespaces.yaml" 2>/dev/null || \
kubectl create namespace model-serving --dry-run=client -o yaml | kubectl apply -f -

echo "Deploying sample Iris sklearn InferenceService (lightweight, no GPU needed)..."
kubectl apply -f "${ROOT}/platform/serving/kserve/iris.yaml"

echo
echo "Waiting for InferenceService to be ready (this can take a few minutes)..."
kubectl wait --for=condition=Ready isvc/iris --timeout=300s 2>/dev/null || \
  echo "Note: isvc may still be initializing. Check with: kubectl get isvc -A"

echo
kubectl get isvc -A
