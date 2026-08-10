#!/usr/bin/env bash
set -euo pipefail

echo
echo "==========================================="
echo " MLOps Platform Deployment (Local Kind)"
echo "==========================================="
echo

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

echo "Checking required tools..."
MISSING=0
for cmd in kubectl helm kind; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "  ✗ $cmd not installed"
    MISSING=1
  else
    echo "  ✓ $cmd found"
  fi
done
if [ "$MISSING" -eq 1 ]; then
  echo
  echo "Please install missing tools and re-run."
  echo "  - kind: https://kind.sigs.k8s.io/docs/user/quick-start/#installation"
  echo "  - kubectl: https://kubernetes.io/docs/tasks/tools/"
  echo "  - helm: https://helm.sh/docs/intro/install/"
  exit 1
fi

echo
echo "1/4 Creating Kubernetes cluster (Kind)..."
bash platform/cluster/create_cluster.sh

echo
echo "2/4 Installing monitoring stack..."
bash platform/observability/install_monitoring.sh

echo
echo "3/4 Installing KServe + Knative..."
bash platform/serving/install_kserve.sh

echo
echo "4/4 Deploying sample model (Iris sklearn)..."
bash platform/serving/deploy_model.sh

echo
echo "Running validation..."
bash platform/tools/validate.sh

echo
echo "==========================================="
echo " Deployment completed!"
echo "==========================================="
echo
echo "Useful commands:"
echo "  kubectl get isvc -A"
echo "  kubectl get pods -A"
echo "  kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80"
echo "    (Grafana: admin / admin)"
echo
echo "To test the Iris model (after READY):"
echo "  kubectl port-forward svc/iris-predictor 8080:80"
echo "  curl -X POST http://localhost:8080/v1/models/iris:predict -H 'Content-Type: application/json' -d '{\"instances\":[[5.1,3.5,1.4,0.2]]}'"
echo
