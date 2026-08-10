# MLOps Platform for LLM Deployment

A working local MLOps platform for deploying and serving machine learning models on Kubernetes using **Kind**, **KServe**, **Knative**, and **Prometheus/Grafana**.

This repository started as an incomplete skeleton and has been completed into a functional local platform.

## What works today

- Local Kubernetes cluster with Kind
- KServe + Knative Serving + Kourier
- Prometheus + Grafana monitoring stack
- End-to-end model serving (sklearn Iris demo)
- Live inference via REST (`/v1/models/<name>:predict`)

## Quick Start

### Prerequisites

- Docker or Podman
- [kind](https://kind.sigs.k8s.io/)
- kubectl
- Helm 3

Recommended: ≥ 8 GB RAM

### Deploy

```bash
git clone https://github.com/Liberty911/MLOps-Platform-for-LLM-Deployment.git
cd MLOps-Platform-for-LLM-Deployment

make bootstrap   # optional
make deploy
Validate
make validate
kubectl get isvc -A
kubectl get pods -A
Test the Iris model
cat > README.md << 'EOF'
# MLOps Platform for LLM Deployment

A working local MLOps platform for deploying and serving machine learning models on Kubernetes using **Kind**, **KServe**, **Knative**, and **Prometheus/Grafana**.

This repository started as an incomplete skeleton and has been completed into a functional local platform.

## What works today

- Local Kubernetes cluster with Kind
- KServe + Knative Serving + Kourier
- Prometheus + Grafana monitoring stack
- End-to-end model serving (sklearn Iris demo)
- Live inference via REST (`/v1/models/<name>:predict`)

## Quick Start

### Prerequisites

- Docker or Podman
- [kind](https://kind.sigs.k8s.io/)
- kubectl
- Helm 3

Recommended: ≥ 8 GB RAM

### Deploy

```bash
git clone https://github.com/Liberty911/MLOps-Platform-for-LLM-Deployment.git
cd MLOps-Platform-for-LLM-Deployment

make bootstrap   # optional
make deploy
Validate
make validate
kubectl get isvc -A
kubectl get pods -A
Test the Iris model


# Port-forward the private service
kubectl port-forward svc/iris-predictor-00002-private 8080:80

In another terminal:
curl -X POST http://localhost:8080/v1/models/iris:predict \
  -H "Content-Type: application/json" \
  -d '{"instances":[[5.1, 3.5, 1.4, 0.2]]}'

Expected response:
{"predictions":[0]}

Monitoring
Grafana

kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
URL: http://localhost:3000
User: admin / Password: admin

Prometheus
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
URL: http://localhost:9090

Clean up
make clean

Project Structure
.
├── deploy.sh
├── Makefile
├── platform/
│   ├── cluster/          # Kind cluster + namespaces
│   ├── serving/          # KServe install + model YAMLs
│   ├── observability/    # Prometheus / Grafana
│   ├── distributed/      # Ray stubs
│   ├── examples/         # Client examples
│   └── tools/            # bootstrap, validate, lint


Notes

The InferenceService may show READY=Unknown on Kind. This is expected because Kind has no real cloud LoadBalancer. The model still serves correctly via port-forward.
Real LLM serving (LLaMA, Triton, GPUs, EKS) remains as future work / stubs.
This platform is intended for local development and demonstration.


License
MIT
