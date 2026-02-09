#!/usr/bin/env bash
set -euo pipefail

NS="kserve"

echo "==> Current namespace state"
kubectl get ns "$NS" -o yaml || exit 0

echo "==> List resources in namespace (best effort)"
kubectl api-resources --verbs=list --namespaced -o name \
| while read -r r; do
    kubectl -n "$NS" get "$r" --ignore-not-found --no-headers 2>/dev/null | head -n 3 | sed "s/^/${r} /" || true
  done

echo "==> Remove finalizers from all namespaced resources (best effort)"
kubectl api-resources --verbs=list --namespaced -o name \
| while read -r r; do
    kubectl -n "$NS" get "$r" -o name --ignore-not-found 2>/dev/null \
    | while read -r obj; do
        kubectl -n "$NS" patch "$obj" -p '{"metadata":{"finalizers":[]}}' --type=merge >/dev/null 2>&1 || true
      done
  done

echo "==> Remove finalizers from the namespace itself"
kubectl get ns "$NS" -o json \
| jq 'del(.spec.finalizers)' \
| kubectl replace --raw "/api/v1/namespaces/$NS/finalize" -f - >/dev/null 2>&1 || true

echo "==> Force delete namespace"
kubectl delete ns "$NS" --grace-period=0 --force --ignore-not-found=true

echo "==> Wait until namespace is gone"
for i in {1..60}; do
  kubectl get ns "$NS" >/dev/null 2>&1 || { echo "✅ Namespace deleted"; exit 0; }
  echo "  ...still terminating ($i/60)"
  sleep 5
done

echo "⚠️ Still stuck. Show namespace finalizers:"
kubectl get ns "$NS" -o jsonpath='{.spec.finalizers}{"\n"}' || true
