#!/bin/bash
# scripts/create-structure.sh - Create project structure after cluster is up

echo " Creating MLOps Platform project structure..."

# Create all necessary directories
mkdir -p \
  kubernetes/{namespaces,storage/{pvc},ingress,monitoring,certificates} \
  kserve/{inference-service,transformers} \
  triton/{deployment,models/{llama-2-7b,falcon-7b,mistral-7b},client} \
  ray/{examples} \
  wandb/{experiment-tracking} \
  examples/{llm-inference,fine-tuning} \
  docker/{triton,custom-transformer,ray-worker} \
  helm/templates \
  docs

# Create basic namespace configuration
cat > kubernetes/namespaces/mlops-namespaces.yaml << 'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: mlops-platform
  labels:
    name: mlops-platform
---
apiVersion: v1
kind: Namespace
metadata:
  name: model-serving
  labels:
    name: model-serving
---
apiVersion: v1
kind: Namespace
metadata:
  name: monitoring
  labels:
    name: monitoring
EOF

# Create a simple deployment script
cat > scripts/deploy-basic.sh << 'EOF'
#!/bin/bash
# Deploy basic components to the cluster

echo " Deploying basic MLOps components..."

# Create namespaces
kubectl apply -f kubernetes/namespaces/mlops-namespaces.yaml

# Deploy metrics server
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Deploy NVIDIA GPU operator (optional)
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
helm repo update
helm install gpu-operator nvidia/gpu-operator \
  --namespace gpu-operator \
  --create-namespace \
  --set driver.enabled=false

echo " Basic components deployed!"
echo ""
echo "Next: Install KServe, Triton, etc. as needed."
EOF

chmod +x scripts/deploy-basic.sh

echo " Project structure created!"
echo ""
echo "To deploy basic components:"
echo "  ./scripts/deploy-basic.sh"