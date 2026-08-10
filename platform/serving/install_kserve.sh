#!/usr/bin/env bash
set -euo pipefail

echo "Installing cert-manager..."
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.5/cert-manager.yaml

echo "Waiting for cert-manager..."
kubectl wait --for=condition=available deployment --all -n cert-manager --timeout=300s

echo "Installing Knative Serving CRDs and core..."
kubectl apply -f https://github.com/knative/serving/releases/download/knative-v1.14.1/serving-crds.yaml
kubectl apply -f https://github.com/knative/serving/releases/download/knative-v1.14.1/serving-core.yaml

echo "Installing Kourier networking layer..."
kubectl apply -f https://github.com/knative/net-kourier/releases/download/knative-v1.14.0/kourier.yaml

kubectl patch configmap/config-network \
  --namespace knative-serving \
  --type merge \
  --patch '{"data":{"ingress-class":"kourier.ingress.networking.knative.dev"}}'

echo "Installing KServe..."
kubectl apply -f https://github.com/kserve/kserve/releases/download/v0.13.0/kserve.yaml
kubectl apply -f https://github.com/kserve/kserve/releases/download/v0.13.0/kserve-cluster-resources.yaml

echo "Waiting for KServe controller..."
kubectl wait --for=condition=available deployment/kserve-controller-manager -n kserve --timeout=300s || true

echo "KServe installation complete."
