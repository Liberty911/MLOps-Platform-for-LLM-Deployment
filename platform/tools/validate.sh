#!/usr/bin/env bash
set -euo pipefail

echo
echo "=================================="
echo " Platform Validation"
echo "=================================="

echo
echo "Namespaces"
kubectl get ns

echo
echo "Nodes"
kubectl get nodes -o wide

echo
echo "Pods"
kubectl get pods -A

echo
echo "Services"
kubectl get svc -A

echo
echo "Inference Services"
kubectl get isvc -A 2>/dev/null || true

echo
echo "Ingress"
kubectl get ingress -A 2>/dev/null || true

echo
echo "Validation completed."
