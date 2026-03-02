#!/bin/bash
set -e

echo ">>> 1. APPLYING YOUR FIXED CONFIGURATIONS..."
# Apply the fixed config directly from your repository if it exists
if [ -f "fixed-inferenceservice-config.yaml" ]; then
    kubectl apply -f fixed-inferenceservice-config.yaml
else
    # Fallback: forcefully rewrite the JSON block using jq
    kubectl get cm inferenceservice-config -n kserve -o json | jq '.data.storageInitializer = (.data.storageInitializer | fromjson | del(.cpuModelcar, .memoryModelcar, .cpuLimitcar, .memoryLimitcar) | .cpuRequest="100m" | .cpuLimit="1" | .memoryRequest="200Mi" | .memoryLimit="1Gi" | tojson)' | kubectl apply -f -
fi

echo ">>> 2. HARD-KILLING KSERVE CONTROLLER (DUMPING CACHE)..."
# A graceful 'rollout restart' clearly isn't dropping the cache. We execute a hard kill to force a cold boot.
kubectl delete pod -n kserve -l control-plane=kserve-controller-manager

echo ">>> 3. WAITING FOR KSERVE TO BOOT COLD..."
sleep 5
kubectl wait --for=condition=Ready pod -n kserve -l control-plane=kserve-controller-manager --timeout=120s

echo ">>> 4. KICKSTARTING THE MODEL PIPELINE..."
# We inject a dummy timestamp annotation to force Kubernetes to instantly re-process the model
kubectl annotate isvc sklearn-iris -n mlops-demo kubectl.kubernetes.io/restartedAt="$(date +%s)" --overwrite

echo ">>> 5. WAITING FOR THE PODS TO SPIN UP..."
# We wait patiently for the KServe controller to finally generate the deployment
while ! kubectl get deployment sklearn-iris-predictor-default -n mlops-demo > /dev/null 2>&1; do 
    echo -n "."
    sleep 2
done
echo -e "\nDeployment generated!"

kubectl wait --for=condition=Available deployment/sklearn-iris-predictor-default -n mlops-demo --timeout=120s

echo ">>> 6. TESTING THE INFERENCE ENDPOINT..."
SERVICE_URL=$(kubectl get inferenceservice sklearn-iris -n mlops-demo -o jsonpath='{.status.url}')
if [ -z "$SERVICE_URL" ]; then
  echo "Error: URL not provisioned."
  exit 1
fi

echo "Endpoint is live at: $SERVICE_URL"
curl -s -w "\nHTTP Status: %{http_code}\n" -H "Content-Type: application/json" \
  "${SERVICE_URL}/v1/models/sklearn-iris:predict" \
  -d '{"instances": [[6.8, 2.8, 4.8, 1.4], [6.0, 3.4, 4.5, 1.6]]}'

echo -e "\n✅ BOOM! Your MLOps platform is officially routing inference traffic."