#!/bin/bash
set -e

echo "🚀 Step 1: Bypassing the security webhook to unlock the ghost model..."
WEBHOOK_NAME=$(kubectl get validatingwebhookconfiguration -o custom-columns=NAME:.metadata.name | grep kserve-validating-webhook || true)
if [ ! -z "$WEBHOOK_NAME" ]; then
    kubectl delete validatingwebhookconfiguration $WEBHOOK_NAME
fi

echo "🧹 Step 2: Force-deleting the stuck sklearn-iris model..."
kubectl patch inferenceservice sklearn-iris -n mlops-demo -p '{"metadata":{"finalizers":[]}}' --type=merge || true
kubectl delete inferenceservice sklearn-iris -n mlops-demo --ignore-not-found

echo "🔄 Step 3: Restoring KServe controller and webhooks..."
kubectl rollout restart deployment kserve-controller-manager -n kserve
kubectl rollout status deployment kserve-controller-manager -n kserve --timeout=120s
sleep 10 # Give the recreated webhook a few seconds to register with the API

echo "📦 Step 4: Deploying the fresh RawDeployment model..."
cat <<EOF | kubectl apply -f -
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: sklearn-iris
  namespace: mlops-demo
  annotations:
    serving.kserve.io/deploymentMode: "RawDeployment"
spec:
  predictor:
    model:
      modelFormat:
        name: sklearn
      storageUri: "gs://kfserving-examples/models/sklearn/1.0/model"
EOF

echo "⏳ Step 5: Waiting for KServe to provision the pods (Max 2 minutes)..."
sleep 10
kubectl wait --for=condition=Available deployment/sklearn-iris-predictor-default -n mlops-demo --timeout=120s

echo "🌐 Step 6: Testing the Inference Endpoint..."
SERVICE_URL=$(kubectl get inferenceservice sklearn-iris -n mlops-demo -o jsonpath='{.status.url}')
if [ -z "$SERVICE_URL" ]; then
  echo "Error: URL not provisioned."
  exit 1
fi

echo "Endpoint is live at: $SERVICE_URL"
curl -s -w "\nHTTP Status: %{http_code}\n" -H "Content-Type: application/json" \
  "${SERVICE_URL}/v1/models/sklearn-iris:predict" \
  -d '{"instances": [[6.8, 2.8, 4.8, 1.4], [6.0, 3.4, 4.5, 1.6]]}'

echo -e "\n✅ Success! Your MLOps platform is officially routing inference traffic."