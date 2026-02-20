#!/bin/bash
# scripts/fix-kserve-working.sh - ACTUAL WORKING SOLUTION

echo "========================================="
echo "✅ KServe Working Fix - Based on Error Logs"
echo "========================================="
echo ""

NAMESPACE="mlops-demo"

# Step 1: Fix the ConfigMap - REMOVE the invalid modelcar fields
echo "📌 Step 1: Fixing ConfigMap (removing invalid modelcar fields)..."
kubectl -n kserve patch cm inferenceservice-config --type merge -p '{
  "data": {
    "storageInitializer": "{\n  \"image\": \"kserve/storage-initializer:v0.16.0\",\n  \"memoryRequest\": \"100Mi\",\n  \"memoryLimit\": \"1Gi\",\n  \"cpuRequest\": \"100m\",\n  \"cpuLimit\": \"1\"\n}"
  }
}'
echo "   ✅ ConfigMap fixed"

# Step 2: Set RawDeployment mode
echo ""
echo "📌 Step 2: Setting RawDeployment mode..."
kubectl -n kserve patch cm inferenceservice-config --type merge -p '{
  "data": {
    "deploy": "{\"defaultDeploymentMode\":\"RawDeployment\"}"
  }
}'
echo "   ✅ Deployment mode set"

# Step 3: Restart controller
echo ""
echo "📌 Step 3: Restarting KServe controller..."
kubectl -n kserve rollout restart deploy/kserve-controller-manager
kubectl -n kserve rollout status deploy/kserve-controller-manager --timeout=2m
echo "   ✅ Controller restarted"

# Step 4: Wait for controller to be ready
echo ""
echo "📌 Step 4: Waiting 20 seconds for controller to initialize..."
sleep 20

# Step 5: Delete any stuck ISVCs
echo ""
echo "📌 Step 5: Cleaning up old InferenceServices..."
kubectl -n $NAMESPACE delete isvc --all --wait=true --timeout=2m 2>/dev/null || true
sleep 5

# Step 6: Create a NEW test InferenceService
echo ""
echo "📌 Step 6: Creating new InferenceService..."
cat <<'EOF' | kubectl apply -n $NAMESPACE -f -
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: sklearn-test
  annotations:
    serving.kserve.io/deploymentMode: RawDeployment
spec:
  predictor:
    model:
      modelFormat:
        name: sklearn
      storageUri: gs://kfserving-examples/models/sklearn/1.0/model
EOF
echo "   ✅ InferenceService created"

echo ""
echo "========================================="
echo "✅ Fix completed!"
echo "========================================="
echo ""
echo "📋 Now watch it become ready:"
echo "   kubectl -n $NAMESPACE get isvc sklearn-test -w"
echo ""
echo "📋 Once READY=True, test with:"
echo "   kubectl -n $NAMESPACE port-forward svc/sklearn-test-predictor 8080:80 &"
echo "   curl -X POST localhost:8080/v1/models/sklearn-test:predict \\"
echo "        -H 'Content-Type: application/json' \\"
echo "        -d '{\"instances\": [[5.1, 3.5, 1.4, 0.2]]}'"
echo "   pkill -f 'port-forward'"