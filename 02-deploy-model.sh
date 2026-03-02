#!/bin/bash
set -e

NAMESPACE="mlops-demo"
MODEL_NAME="sklearn-iris"

echo ">>> Purging blocked InferenceService to bypass webhook validation errors..."
kubectl delete inferenceservice $MODEL_NAME -n $NAMESPACE --ignore-not-found
echo ">>> Waiting for termination to clear..."
sleep 5 

echo ">>> Deploying $MODEL_NAME InferenceService in RawDeployment Mode..."
cat <<EOF | kubectl apply -f -
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: $MODEL_NAME
  namespace: $NAMESPACE
  annotations:
    # Bypassing Knative to use standard Kubernetes Deployments
    serving.kserve.io/deploymentMode: "RawDeployment"
spec:
  predictor:
    model:
      modelFormat:
        name: sklearn
      storageUri: "gs://kfserving-examples/models/sklearn/1.0/model"
EOF

echo ">>> Waiting for InferenceService pods to initialize..."
# Wait for the actual Kubernetes deployment to spin up
kubectl wait --for=condition=Available deployment/${MODEL_NAME}-predictor-default -n $NAMESPACE --timeout=300s

echo ">>> Waiting for InferenceService to report Ready status..."
kubectl wait --for=condition=Ready inferenceservice/$MODEL_NAME -n $NAMESPACE --timeout=300s

echo "Model successfully deployed and ready for traffic."