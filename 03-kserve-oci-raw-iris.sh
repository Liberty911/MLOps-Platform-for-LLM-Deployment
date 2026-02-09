#!/usr/bin/env bash
set -euo pipefail

NS_KSERVE="kserve"
NS_APP="mlops-demo"

say(){ printf "\n==> %s\n" "$*"; }

say "0) Precheck connectivity"
kubectl get nodes
kubectl get ns

say "1) Clean old KServe namespace (if any)"

say "2) Ensure cert-manager is healthy"
kubectl get ns cert-manager >/dev/null 2>&1 || \
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/latest/download/cert-manager.yaml

kubectl -n cert-manager rollout status deploy/cert-manager --timeout=10m
kubectl -n cert-manager rollout status deploy/cert-manager-webhook --timeout=10m
kubectl -n cert-manager rollout status deploy/cert-manager-cainjector --timeout=10m

say "3) Create namespaces"
kubectl create ns "${NS_KSERVE}" --dry-run=client -o yaml | kubectl apply -f -
kubectl create ns "${NS_APP}" --dry-run=client -o yaml | kubectl apply -f -

say "4) Install KServe via OCI charts (official method)"
# Works with helm v3.8+ with OCI support enabled by default.
helm upgrade --install kserve-crd oci://ghcr.io/kserve/charts/kserve-crd \
  -n "${NS_KSERVE}" \
  --wait --timeout 15m

helm upgrade --install kserve oci://ghcr.io/kserve/charts/kserve \
  -n "${NS_KSERVE}" \
  --set kserve.controller.deploymentMode=RawDeployment \
  --wait --timeout 15m

say "5) Deploy Iris model"
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

say "6) Wait for model Ready"
kubectl -n "${NS_APP}" wait --for=condition=Ready isvc/iris-model --timeout=20m
kubectl -n "${NS_APP}" get isvc iris-model

say "DONE ✅"
echo
echo "Test:"
echo "  kubectl -n ${NS_APP} get svc | grep iris-model"
echo "  kubectl -n ${NS_APP} port-forward svc/iris-model-predictor 8080:80"
echo "  curl -sS -X POST http://127.0.0.1:8080/v1/models/iris-model:predict -H 'Content-Type: application/json' -d '{\"instances\": [[5.1,3.5,1.4,0.2]]}'"
