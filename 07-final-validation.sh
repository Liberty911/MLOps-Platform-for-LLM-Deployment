#!/bin/bash
set -e

NAMESPACE="mlops-demo"
MODEL_NAME="sklearn-iris"

echo ">>> 1. WAITING FOR DEPLOYMENT OBJECT TO BE CREATED..."
while ! kubectl get deployment ${MODEL_NAME}-predictor-default -n ${NAMESPACE} > /dev/null 2>&1; do 
    echo -n "."
    sleep 2
done
echo -e "\nDeployment object found!"

echo ">>> 2. WAITING FOR PODS TO BE READY..."
kubectl wait --for=condition=Available deployment/${MODEL_NAME}-predictor-default -n ${NAMESPACE} --timeout=120s

echo ">>> 3. FETCHING SERVICE URL..."
SERVICE_URL=$(kubectl get inferenceservice ${MODEL_NAME} -n ${NAMESPACE} -o jsonpath='{.status.url}')

if [ -z "$SERVICE_URL" ]; then
  echo "Error: Service URL not found. The model is not reporting a URL yet."
  exit 1
fi
echo "Endpoint: $SERVICE_URL"

echo ">>> 4. SENDING TEST PAYLOAD..."
curl -s -w "\nHTTP Status: %{http_code}\n" -H "Content-Type: application/json" \
  "${SERVICE_URL}/v1/models/${MODEL_NAME}:predict" \
  -d '{"instances": [[6.8, 2.8, 4.8, 1.4], [6.0, 3.4, 4.5, 1.6]]}'

echo -e "\n✅ DONE! Take a screenshot of the output above for your LinkedIn post."
