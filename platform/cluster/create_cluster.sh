#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CONFIG="${ROOT}/platform/cluster/kind-config.yaml"

echo "Deleting existing mlops cluster (if any)..."
kind delete cluster --name mlops 2>/dev/null || true

echo "Creating Kind cluster 'mlops'..."
kind create cluster --name mlops --config "$CONFIG"

echo
kubectl cluster-info
kubectl get nodes
