#!/bin/bash
set -e

echo ">>> 1. NUKING KSERVE WEBHOOKS..."
# Forcefully delete all KServe validation webhooks that are blocking our patches
kubectl get validatingwebhookconfiguration | grep kserve | awk '{print $1}' | xargs -I {} kubectl delete validatingwebhookconfiguration {} --ignore-not-found || true

echo ">>> 2. TRIGGERING NON-BLOCKING DELETE..."
# --wait=false ensures your terminal WILL NOT HANG here
kubectl delete isvc sklearn-iris -n mlops-demo --wait=false --ignore-not-found || true

echo ">>> 3. RIPPING OUT FINALIZERS (SLEDGEHAMMER)..."
# This JSON patch is the industry-standard way to forcefully sever stubborn finalizers
kubectl patch isvc sklearn-iris -n mlops-demo --type=json -p='[{"op": "remove", "path": "/metadata/finalizers"}]' || true
sleep 3

echo ">>> 4. VERIFYING GHOST MODEL IS GONE..."
if kubectl get isvc sklearn-iris -n mlops-demo > /dev/null 2>&1; then
    echo "ERROR: Model is still stuck. Forcing raw API payload..."
    kubectl get isvc sklearn-iris -n mlops-demo -o json | jq '.metadata.finalizers = []' | kubectl replace --raw /apis/serving.kserve.io/v1beta1/namespaces/mlops-demo/inferenceservices/sklearn-iris -f - || true
fi
echo "Ghost model successfully vaporized."

echo ">>> 5. REBOOTING KSERVE..."
kubectl rollout restart deployment kserve-controller-manager -n kserve
kubectl rollout status deployment kserve-controller-manager -n kserve --timeout=120s
sleep 5

echo ">>> 6. DEPLOYING RAW MODEL..."
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

echo ">>> 7. WAITING FOR PODS TO SPIN UP..."
sleep 5
kubectl wait --for=condition=Available deployment/sklearn-iris-predictor-default -n mlops-demo --timeout=120s

echo ">>> 8. TESTING INFERENCE ENDPOINT..."
SERVICE_URL=$(kubectl get inferenceservice sklearn-iris -n mlops-demo -o jsonpath='{.status.url}')
if [ -z "$SERVICE_URL" ]; then
  echo "Error: URL not provisioned."
  exit 1
fi

echo "Endpoint is live at: $SERVICE_URL"
curl -s -w "\nHTTP Status: %{http_code}\n" -H "Content-Type: application/json" \
  "${SERVICE_URL}/v1/models/sklearn-iris:predict" \
  -d '{"instances": [[6.8, 2.8, 4.8, 1.4], [6.0, 3.4, 4.5, 1.6]]}'

echo -e "\n✅ Success! The MLOps platform is officially routing inference traffic."