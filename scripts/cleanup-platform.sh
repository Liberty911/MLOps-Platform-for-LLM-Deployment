#!/bin/bash
# cleanup-platform.sh - Safely cleanup MLOps Platform

set -e

echo "=========================================="
echo "MLOps Platform Cleanup"
echo "=========================================="

read -p "⚠️  Are you sure you want to cleanup the MLOps platform? (yes/no): " confirmation

if [ "$confirmation" != "yes" ]; then
    echo "Cleanup cancelled."
    exit 0
fi

echo ""
echo "🗑️  Starting cleanup..."

# Delete namespaces (this will delete all resources within them)
NAMESPACES=(
    "mlops-platform"
    "model-serving"
    "ray-cluster"
    "monitoring"
    "kserve"
    "triton"
    "wandb"
    "gpu-operator"
    "ingress-nginx"
    "cert-manager"
)

for ns in "${NAMESPACES[@]}"; do
    echo "Deleting namespace: $ns"
    kubectl delete namespace "$ns" --ignore-not-found=true --wait=false
done

# Delete cluster-scoped resources
echo "Deleting cluster-scoped resources..."
kubectl delete crd --all --ignore-not-found=true
kubectl delete validatingwebhookconfigurations --all --ignore-not-found=true
kubectl delete mutatingwebhookconfigurations --all --ignore-not-found=true

# Delete Helm releases
echo "Deleting Helm releases..."
helm uninstall prometheus --namespace monitoring --ignore-not-found
helm uninstall gpu-operator --namespace gpu-operator --ignore-not-found

# Wait for namespace deletions
echo ""
echo "⏳ Waiting for namespace deletions to complete..."
for ns in "${NAMESPACES[@]}"; do
    while kubectl get namespace "$ns" &> /dev/null; do
        echo "Waiting for namespace $ns to be deleted..."
        sleep 5
    done
done

# Cleanup local Terraform state
echo ""
echo "🧹 Cleaning local Terraform state..."
cd terraform 2>/dev/null && {
    rm -rf .terraform* terraform.tfstate* 2>/dev/null || true
    cd ..
}

echo ""
echo "=========================================="
echo "✅ Cleanup completed!"
echo "=========================================="
echo ""
echo "Note: The EKS cluster itself is not deleted."
echo "To delete the cluster, run:"
echo "  cd terraform && terraform destroy"
echo ""
echo "To redeploy:"
echo "  ./scripts/deploy-platform.sh"