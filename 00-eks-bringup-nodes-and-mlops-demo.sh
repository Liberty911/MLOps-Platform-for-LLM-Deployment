#!/usr/bin/env bash
set -euo pipefail

# ====== CONFIG (edit if needed) ======
AWS_REGION="${AWS_REGION:-us-east-1}"
CLUSTER_NAME="${CLUSTER_NAME:-mlops-llm-platform}"

# Pick 2-3 subnets in your EKS VPC (script will auto-discover)
NODEGROUP_NAME="${NODEGROUP_NAME:-ng-cpu}"
INSTANCE_TYPE="${INSTANCE_TYPE:-t3.large}"   # ok for demo; change to m5.large if needed
DESIRED="${DESIRED:-2}"
MIN="${MIN:-1}"
MAX="${MAX:-3}"

# Namespaces
NS_MON="monitoring"
NS_KSERVE="kserve"
NS_APP="mlops-demo"

say(){ printf "\n\033[1;32m==>\033[0m %s\n" "$*"; }
die(){ printf "\n\033[1;31m[ERROR]\033[0m %s\n" "$*"; exit 1; }

need(){ command -v "$1" >/dev/null 2>&1 || die "Missing: $1"; }

need aws
need kubectl
need helm

say "1) AWS identity"
aws sts get-caller-identity >/dev/null

say "2) Verify kube context"
CTX="$(kubectl config current-context)"
echo "Context: $CTX"
kubectl cluster-info >/dev/null

say "3) Check nodes"
if kubectl get nodes >/dev/null 2>&1; then
  NODES_COUNT="$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')"
else
  NODES_COUNT="0"
fi
echo "Nodes count: $NODES_COUNT"

say "4) Check EKS nodegroups"
NGS="$(aws eks list-nodegroups --cluster-name "$CLUSTER_NAME" --region "$AWS_REGION" --query 'nodegroups' --output text || true)"
echo "Nodegroups: ${NGS:-<none>}"

if [[ "${NODES_COUNT}" == "0" ]]; then
  if [[ -z "${NGS}" ]]; then
    say "No nodegroups and no nodes. Creating managed nodegroup: $NODEGROUP_NAME"

    # Discover VPC + subnets from cluster
    VPC_ID="$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" --query 'cluster.resourcesVpcConfig.vpcId' --output text)"
    [[ -n "$VPC_ID" ]] || die "Could not discover VPC ID"

    # Pick private subnets first, otherwise any
    SUBNETS="$(aws ec2 describe-subnets --region "$AWS_REGION" --filters "Name=vpc-id,Values=$VPC_ID" \
      --query 'Subnets[?MapPublicIpOnLaunch==`false`].SubnetId' --output text || true)"

    if [[ -z "$SUBNETS" ]]; then
      SUBNETS="$(aws ec2 describe-subnets --region "$AWS_REGION" --filters "Name=vpc-id,Values=$VPC_ID" \
        --query 'Subnets[].SubnetId' --output text)"
    fi

    # take first 3
    read -r -a SUB_ARR <<<"$SUBNETS"
    [[ "${#SUB_ARR[@]}" -ge 2 ]] || die "Need at least 2 subnets to create a nodegroup. Found: $SUBNETS"

    SUBNET_CSV="${SUB_ARR[0]},${SUB_ARR[1]}"
    [[ "${#SUB_ARR[@]}" -ge 3 ]] && SUBNET_CSV="${SUBNET_CSV},${SUB_ARR[2]}"

    say "Using subnets: $SUBNET_CSV"

    # Create an IAM role for nodegroup if you don't have one named eksNodeRole
    ROLE_NAME="eksNodeRole"
    ROLE_ARN="$(aws iam get-role --role-name "$ROLE_NAME" --query 'Role.Arn' --output text 2>/dev/null || true)"

    if [[ -z "$ROLE_ARN" ]]; then
      say "Creating IAM role $ROLE_NAME for nodes"
      cat > /tmp/eks-node-trust.json <<'JSON'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Service": "ec2.amazonaws.com" },
      "Action": "sts:AssumeRole"
    }
  ]
}
JSON
      aws iam create-role --role-name "$ROLE_NAME" --assume-role-policy-document file:///tmp/eks-node-trust.json >/dev/null

      # Attach required managed policies for EKS worker nodes
      aws iam attach-role-policy --role-name "$ROLE_NAME" --policy-arn arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy >/dev/null
      aws iam attach-role-policy --role-name "$ROLE_NAME" --policy-arn arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy >/dev/null
      aws iam attach-role-policy --role-name "$ROLE_NAME" --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly >/dev/null

      ROLE_ARN="$(aws iam get-role --role-name "$ROLE_NAME" --query 'Role.Arn' --output text)"
      say "Role ARN: $ROLE_ARN"
      say "Waiting 20s for IAM propagation..."
      sleep 20
    else
      say "Using existing IAM role: $ROLE_ARN"
    fi

    say "Creating nodegroup (this can take several minutes)"
    aws eks create-nodegroup \
      --cluster-name "$CLUSTER_NAME" \
      --nodegroup-name "$NODEGROUP_NAME" \
      --scaling-config "minSize=$MIN,maxSize=$MAX,desiredSize=$DESIRED" \
      --subnets $(echo "$SUBNET_CSV" | tr ',' ' ') \
      --instance-types "$INSTANCE_TYPE" \
      --node-role "$ROLE_ARN" \
      --ami-type AL2_x86_64 \
      --region "$AWS_REGION" >/dev/null

    say "Waiting for nodegroup to become ACTIVE"
    aws eks wait nodegroup-active --cluster-name "$CLUSTER_NAME" --nodegroup-name "$NODEGROUP_NAME" --region "$AWS_REGION"
  else
    say "Nodegroup(s) exist but nodes are 0. Check nodegroup health in AWS console or describe nodegroup."
    aws eks describe-nodegroup --cluster-name "$CLUSTER_NAME" --nodegroup-name "$(echo "$NGS" | awk '{print $1}')" --region "$AWS_REGION" \
      --query 'nodegroup.status' --output text || true
  fi
fi

say "5) Wait for nodes to appear"
for i in {1..60}; do
  if kubectl get nodes --no-headers 2>/dev/null | grep -q .; then
    break
  fi
  echo "  ...waiting for nodes ($i/60)"
  sleep 10
done

kubectl get nodes -o wide || die "Still no nodes. Nodegroup creation likely failed."

say "6) Install LIGHT monitoring (Prometheus + Grafana) with longer timeout"
kubectl get ns "$NS_MON" >/dev/null 2>&1 || kubectl create ns "$NS_MON"

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null || true
helm repo update >/dev/null

helm upgrade --install prometheus prometheus-community/prometheus \
  -n "$NS_MON" \
  --set alertmanager.enabled=false \
  --set pushgateway.enabled=false \
  --set server.persistentVolume.enabled=false \
  --wait --timeout 15m

helm upgrade --install grafana prometheus-community/grafana \
  -n "$NS_MON" \
  --set persistence.enabled=false \
  --set adminPassword=admin \
  --wait --timeout 15m

say "7) Deploy KServe test model (only after nodes exist)"
kubectl create ns "$NS_KSERVE" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl create ns "$NS_APP" --dry-run=client -o yaml | kubectl apply -f - >/dev/null

say "Cert-manager (apply if not healthy)"
kubectl get ns cert-manager >/dev/null 2>&1 || kubectl apply -f https://github.com/cert-manager/cert-manager/releases/latest/download/cert-manager.yaml

say "Install/Upgrade KServe"
helm repo add kserve https://kserve.github.io/helm-charts >/dev/null || true
helm repo update >/dev/null

helm upgrade --install kserve kserve/kserve \
  -n "$NS_KSERVE" \
  --set metricsAggregator.enabled=true \
  --wait --timeout 15m

cat <<'YAML' | kubectl apply -f -
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: iris-model
  namespace: mlops-demo
spec:
  predictor:
    sklearn:
      storageUri: "gs://kfserving-examples/models/sklearn/iris"
YAML

say "Wait for model Ready"
kubectl -n "$NS_APP" wait --for=condition=Ready isvc/iris-model --timeout=15m

say "DONE ✅"
echo
echo "Grafana: kubectl -n $NS_MON port-forward svc/grafana 3000:80"
echo "Login:  admin / admin"
echo
echo "Prometheus: kubectl -n $NS_MON port-forward svc/prometheus-server 9090:80"
echo
echo "KServe model:"
kubectl -n "$NS_APP" get isvc iris-model
