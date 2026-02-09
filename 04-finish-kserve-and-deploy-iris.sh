#!/usr/bin/env bash
set -euo pipefail

KSERVE_VER="${KSERVE_VER:-v0.16.0}"
NS_APP="${NS_APP:-mlops-demo}"

say(){ printf "\n==> %s\n" "$*"; }

say "0) Precheck"
kubectl get nodes
kubectl get crd | grep -E 'inferenceservices\.serving\.kserve\.io|llminferenceserviceconfigs\.serving\.kserve\.io' >/dev/null
kubectl get ns kserve >/dev/null

say "1) Re-apply KServe core (now CRDs exist, this should succeed)"
kubectl apply --server-side -f "https://github.com/kserve/kserve/releases/download/${KSERVE_VER}/kserve.yaml"

say "2) Apply KServe default runtimes/resources"
kubectl apply --server-side -f "https://github.com/kserve/kserve/releases/download/${KSERVE_VER}/kserve-cluster-resources.yaml"

say "3) Wait for KServe deployments"
kubectl -n kserve rollout status deploy/kserve-controller-manager --timeout=15m
kubectl -n kserve rollout status deploy/kserve-localmodel-controller-manager --timeout=15m || true
kubectl -n kserve rollout status deploy/llmisvc-controller-manager --timeout=15m || true

say "4) Ensure app namespace exists"
kubectl create ns "${NS_APP}" --dry-run=client -o yaml | kubectl apply -f -

say "5) Deploy Iris sklearn InferenceService"
cat <<'YAML' | kubectl apply -f -
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: iris-model
  namespace: mlops-demo
spec:
  predictor:
    sklearn:
      storageUri: gs://kfserving-examples/models/sklearn/iris
YAML

say "6) Wait for model ready"
kubectl -n "${NS_APP}" wait --for=condition=Ready isvc/iris-model --timeout=20m
kubectl -n "${NS_APP}" get isvc iris-model

say "7) Show the predictor Service name (use THIS for port-forward)"
kubectl -n "${NS_APP}" get svc | grep -i iris || true

say "DONE ✅"
echo
echo "Next:"
echo "  # pick the service name from the list above"
echo "  kubectl -n ${NS_APP} port-forward svc/<PASTE_SERVICE_NAME_HERE> 8080:80"
echo "  curl -sS -X POST http://127.0.0.1:8080/v1/models/iris-model:predict -H 'Content-Type: application/json' -d '{\"instances\": [[5.1,3.5,1.4,0.2]]}'"
