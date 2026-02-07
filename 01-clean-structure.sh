#!/usr/bin/env bash
set -euo pipefail

echo "==> BACKUP existing project (safe copy)"
BACKUP="../MLOps-Platform-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP"
rsync -a --exclude='.git' ./ "$BACKUP/"

echo "==> Removing nested duplicates if found"
if [[ -d "MLOps-Platform-for-LLM-Deployment" ]]; then
  rm -rf MLOps-Platform-for-LLM-Deployment
fi

echo "==> Standardizing project structure"
mkdir -p platform/{infra,cluster,serving,distributed,observability,examples,scripts,tools/legacy}

mv terraform platform/infra/terraform 2>/dev/null || true
mv kubernetes platform/cluster/kubernetes 2>/dev/null || true
mv kserve platform/serving/kserve 2>/dev/null || true
mv triton platform/serving/triton 2>/dev/null || true
mv docker platform/serving/docker 2>/dev/null || true
mv ray platform/distributed/ray 2>/dev/null || true
mv wandb platform/observability/wandb 2>/dev/null || true
mv examples platform/examples 2>/dev/null || true
mv scripts platform/scripts 2>/dev/null || true

echo "==> Archiving old setup scripts"
for f in setup.sh setup-simple.sh setup-final.sh; do
  [[ -f "$f" ]] && mv "$f" platform/tools/legacy/
done

echo "==> Creating .gitignore"
cat > .gitignore << 'GI'
# Secrets
.env
**/.env
*.key
*.pem
*api*key*
*token*

# Terraform
**/.terraform/
*.tfstate*
crash.log

# IDE
.vscode/
.idea/
GI

# Untrack any accidental secrets
git rm -r --cached .env **/.env **/.terraform **/*.tfstate* 2>/dev/null || true

echo "==> Structure cleanup complete"
