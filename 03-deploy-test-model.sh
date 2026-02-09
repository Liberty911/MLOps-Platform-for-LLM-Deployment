#!/usr/bin/env bash
set -euo pipefail

NS_KSERVE="kserve"
NS_APP="mlops-demo"

echo "==> Ensure namespaces"
kubectl create ns "$NS_KSERVE" --dry-run=client -o yaml | kubectl apply -f -
kubectl create ns "$NS_APP" --dry-run=client -o yaml | kubectl apply -f -

echo "==> Ensure cert-manager"
kubectl get ns cert-manager >/dev/null 2>&1 || \
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/latest/download/cert-manager.yaml

kubectl -n cert-manager rollout status deploy/cert-manager --timeout=10m || true
kubectl -n cert-manager rollout status deploy/cert-manager-webhook --timeout=10m || true

echo "==> Install / Upgrade KServe"
helm repo add kserve https://kserve.github.io/helm-charts >/dev/null || true
helm repo update >/dev/null

helm upgrade --install kserve kserve/kserve \
  -n "$NS_KSERVE" \
  --set metricsAggregator.enabled=true \
  --wait \
  --timeout 15m

echo "==> Deploy Iris model (InferenceService)"
cat <<'YAML' | kubectl apply -f -
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: iris-model
  namespace: mlops-demo
spec:
  predictor:
    sklearn:
      storageUri: "gs://kfserving-examples/models/sklearn/iris"
YAML

echo "==> Waiting for model to become READY"
kubectl -n "$NS_APP" wait --for=condition=Ready isvc/iris-model --timeout=15m

echo "==> Model deployed successfully"
kubectl -n "$NS_APP" get isvc iris-model
