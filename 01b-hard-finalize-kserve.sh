#!/usr/bin/env bash
set -euo pipefail
NS="kserve"

echo "==> Confirm namespace exists"
kubectl get ns "$NS" >/dev/null

echo "==> Dump finalizers (before)"
kubectl get ns "$NS" -o jsonpath='{.spec.finalizers}{"\n"}' || true

echo "==> Hard finalize namespace (remove spec.finalizers)"
kubectl get ns "$NS" -o json \
| sed 's/"finalizers":[[:space:]]*\[[^]]*\]/"finalizers":[]/g' \
| kubectl replace --raw "/api/v1/namespaces/${NS}/finalize" -f -

echo "==> Wait until namespace is gone"
for i in {1..30}; do
  kubectl get ns "$NS" >/dev/null 2>&1 || { echo "✅ Namespace deleted"; exit 0; }
  echo "  ...still terminating ($i/30)"
  sleep 2
done

echo "⚠️ Still present. Show conditions:"
kubectl get ns "$NS" -o yaml | sed -n '1,120p'
