#!/usr/bin/env bash
set -euo pipefail

# ========= CONFIG =========
N_MON="monitoring"
N_KSERVE="kserve"
N_APP="mlops-demo"

# If you don't have a LoadBalancer, we will port-forward.
GRAFANA_LOCAL_PORT="3000"
PROM_LOCAL_PORT="9090"

# ========== HELPERS ==========
say(){ printf "\n\033[1;32m==>\033[0m %s\n" "$*"; }
need(){ command -v "$1" >/dev/null 2>&1 || { echo "Missing $1"; exit 1; }; }

need kubectl
need helm

# ========= PRECHECK =========
say "Precheck: cluster access"
kubectl version --client >/dev/null
kubectl get nodes >/dev/null

# ========= 1) Monitoring stack =========
say "1) Install kube-prometheus-stack (Prometheus + Grafana + Alertmanager)"
kubectl get ns "$N_MON" >/dev/null 2>&1 || kubectl create ns "$N_MON"

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null
helm repo update >/dev/null

# Install/upgrade monitoring stack
helm upgrade --install kube-prom-stack prometheus-community/kube-prometheus-stack \
  -n "$N_MON" \
  --set grafana.enabled=true \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
  --set prometheus.prometheusSpec.podMonitorSelectorNilUsesHelmValues=false

say "Wait for monitoring pods"
kubectl -n "$N_MON" rollout status deploy/kube-prom-stack-grafana --timeout=10m
kubectl -n "$N_MON" rollout status deploy/kube-prom-stack-kube-promptheus-sta-operator --timeout=10m || true

# ========= 2) KServe dependencies =========
say "2) Install cert-manager (required by KServe webhook certs)"
kubectl get ns cert-manager >/dev/null 2>&1 || kubectl create ns cert-manager

# Use the official cert-manager manifest (version can change; update if needed)
# KServe docs note cert-manager is required and specifies minimum version guidance. :contentReference[oaicite:2]{index=2}
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/latest/download/cert-manager.yaml

say "Wait for cert-manager"
kubectl -n cert-manager rollout status deploy/cert-manager --timeout=10m
kubectl -n cert-manager rollout status deploy/cert-manager-webhook --timeout=10m
kubectl -n cert-manager rollout status deploy/cert-manager-cainjector --timeout=10m

say "3) Install Istio (KServe commonly runs with Istio ingress)"
# Lightweight Istio install via istioctl is common, but to keep this script self-contained,
# we deploy Istio using the upstream operator-less "istio-base + istiod" charts.
helm repo add istio https://istio-release.storage.googleapis.com/charts >/dev/null
helm repo update >/dev/null

kubectl get ns istio-system >/dev/null 2>&1 || kubectl create ns istio-system

helm upgrade --install istio-base istio/base -n istio-system
helm upgrade --install istiod istio/istiod -n istio-system --wait

# Install Istio ingress gateway
helm upgrade --install istio-ingress istio/gateway -n istio-system --wait

say "4) Install KServe"
kubectl get ns "$N_KSERVE" >/dev/null 2>&1 || kubectl create ns "$N_KSERVE"

# KServe installation follows the official Kubernetes deployment guide. :contentReference[oaicite:3]{index=3}
# Use official OCI Helm chart (stable method used by KServe project).
helm upgrade --install kserve oci://ghcr.io/kserve/charts/kserve -n "$N_KSERVE" --wait

# Optional: enable Prometheus scraping in KServe (needed for some dashboards)
# See example enabling scraping. :contentReference[oaicite:4]{index=4}
helm upgrade kserve oci://ghcr.io/kserve/charts/kserve -n "$N_KSERVE" --reuse-values \
  --set metricsaggregator.enablePrometheusScraping=true

say "Wait for KServe control plane"
kubectl -n "$N_KSERVE" get pods

# ========= 3) Deploy test model (Iris sklearn) =========
say "5) Deploy test model (KServe sklearn Iris InferenceService)"
kubectl get ns "$N_APP" >/dev/null 2>&1 || kubectl create ns "$N_APP"

cat > /tmp/iris-isvc.yaml <<'YAML'
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: sklearn-iris
  namespace: mlops-demo
  annotations:
    # enable scraping where supported (helps runtime metrics)
    serving.kserve.io/enable-prometheus-scraping: "true"
spec:
  predictor:
    sklearn:
      # KServe "first InferenceService" uses the Iris model example. :contentReference[oaicite:5]{index=5}
      storageUri: "gs://kfserving-examples/models/sklearn/iris"
YAML

kubectl apply -f /tmp/iris-isvc.yaml

say "Wait for InferenceService to be Ready"
# This can take a few minutes because Knative/KServe pulls images and downloads the model.
for i in {1..60}; do
  READY="$(kubectl -n "$N_APP" get isvc sklearn-iris -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)"
  [[ "$READY" == "True" ]] && break
  echo "  ...waiting ($i/60)"
  sleep 10
done

kubectl -n "$N_APP" get isvc sklearn-iris

# ========= 4) Smoke test inference =========
say "6) Smoke test: run an in-cluster curl pod and call the model"
kubectl -n "$N_APP" delete pod curl --ignore-not-found >/dev/null 2>&1 || true
kubectl -n "$N_APP" run curl --image=curlimages/curl:8.6.0 --restart=Never -- sleep 3600

# Find the predictor URL (KServe/Knative route)
PRED_URL="$(kubectl -n "$N_APP" get isvc sklearn-iris -o jsonpath='{.status.url}' | sed 's|https\?://||')"
echo "Inference URL host: $PRED_URL"

# For Istio ingress: get gateway IP/hostname
GW_SVC="istio-ingress"
GW_NS="istio-system"
GW_HOST="$(kubectl -n "$GW_NS" get svc "$GW_SVC" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"
GW_IP="$(kubectl -n "$GW_NS" get svc "$GW_SVC" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)"

if [[ -n "$GW_HOST" ]]; then
  INGRESS="$GW_HOST"
elif [[ -n "$GW_IP" ]]; then
  INGRESS="$GW_IP"
else
  INGRESS=""
fi

if [[ -n "$INGRESS" ]]; then
  say "Calling through Istio ingress (LoadBalancer found: $INGRESS)"
  kubectl -n "$N_APP" exec curl -- sh -c "curl -sS -H 'Host: ${PRED_URL}' http://${INGRESS}/v1/models/sklearn-iris:predict -d '{\"instances\": [[5.1, 3.5, 1.4, 0.2]]}'"
else
  warn "No LoadBalancer ingress detected for istio gateway. Use port-forward instead."
  warn "Run in another terminal:"
  echo "kubectl -n istio-system port-forward svc/istio-ingress 8080:80"
  echo "Then run:"
  echo "curl -H 'Host: ${PRED_URL}' http://127.0.0.1:8080/v1/models/sklearn-iris:predict -d '{\"instances\": [[5.1,3.5,1.4,0.2]]}'"
fi

# ========= 5) Observability access instructions =========
say "7) How to view dashboards + metrics (port-forward)"
echo
echo "Grafana:"
echo "  kubectl -n ${N_MON} port-forward svc/kube-prom-stack-grafana ${GRAFANA_LOCAL_PORT}:80"
echo "  Then open: http://127.0.0.1:${GRAFANA_LOCAL_PORT}"
echo "  Get password:"
echo "  kubectl -n ${N_MON} get secret kube-prom-stack-grafana -o jsonpath='{.data.admin-password}' | base64 -d; echo"
echo "  Username: admin"
echo
echo "Prometheus:"
echo "  kubectl -n ${N_MON} port-forward svc/kube-prom-stack-kube-promptheus-sta-prometheus ${PROM_LOCAL_PORT}:9090"
echo "  Then open: http://127.0.0.1:${PROM_LOCAL_PORT}"
echo
echo "KServe metrics guidance (Prometheus) is documented in KServe samples. :contentReference[oaicite:6]{index=6}"
echo
echo "Useful PromQL queries (paste in Prometheus UI):"
echo "  - Knative request rate:"
echo "      sum(rate(activator_request_count[2m]))"
echo "  - Per-service request rate (queue-proxy):"
echo "      sum by (configuration, revision) (rate(istio_requests_total[2m]))"
echo "  - KServe runtime metrics often appear once scraping is enabled; see dashboards if using vLLM etc. :contentReference[oaicite:7]{index=7}"
echo
say "Deployment complete ✅"
echo "Cleanup script: ./02-mlops-demo-cleanup.sh"
