#!/usr/bin/env bash
set -euo pipefail

KSERVE_VER="${KSERVE_VER:-v0.16.0}"
NS_APP="mlops-demo"

say(){ printf "\n==> %s\n" "$*"; }

say "0) Precheck"
kubectl get nodes
kubectl get ns cert-manager >/dev/null 2>&1 || \
  kubectl apply -f https://github.com/cert-manager/cert-manager/releases/latest/download/cert-manager.yaml

kubectl -n cert-manager rollout status deploy/cert-manager --timeout=10m || true
kubectl -n cert-manager rollout status deploy/cert-manager-webhook --timeout=10m || true
kubectl -n cert-manager rollout status deploy/cert-manager-cainjector --timeout=10m || true

say "1) Cleanup any broken kserve webhooks (cluster-scoped, can block installs)"
kubectl get validatingwebhookconfigurations | grep -i kserve || true
kubectl get mutatingwebhookconfigurations   | grep -i kserve || true
# best-effort delete by common name patterns
kubectl get validatingwebhookconfigurations -o name | grep -i kserve | xargs -r kubectl delete --ignore-not-found
kubectl get mutatingwebhookconfigurations   -o name | grep -i kserve | xargs -r kubectl delete --ignore-not-found

say "2) Apply KServe core YAML (server-side required; CRD is large)"
# KServe docs recommend --server-side here. :contentReference[oaicite:2]{index=2}
kubectl apply --server-side -f "https://github.com/kserve/kserve/releases/download/${KSERVE_VER}/kserve.yaml"

say "3) Apply KServe built-in runtimes/resources"
kubectl apply --server-side -f "https://github.com/kserve/kserve/releases/download/${KSERVE_VER}/kserve-cluster-resources.yaml"

say "4) Wait for KServe controller"
kubectl -n kserve rollout status deploy/kserve-controller-manager --timeout=15m

say "5) Deploy test model (Iris) into ${NS_APP}"
kubectl create ns "${NS_APP}" --dry-run=client -o yaml | kubectl apply -f -

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
echo "Next: test inference"
echo "  kubectl -n ${NS_APP} get svc | grep iris-model"
echo "  kubectl -n ${NS_APP} port-forward svc/iris-model-predictor 8080:80"
echo "  curl -sS -X POST http://127.0.0.1:8080/v1/models/iris-model:predict -H 'Content-Type: application/json' -d '{\"instances\": [[5.1,3.5,1.4,0.2]]}'"
