#!/usr/bin/env bash
set -euo pipefail

REPO="MLOps-Platform-for-LLM-Deployment"
TS="$(date +%Y%m%d-%H%M%S)"
BACKUP="../${REPO}-backup-${TS}"

echo "==> Backup to $BACKUP"
mkdir -p "$BACKUP"
rsync -a --exclude='.git' ./ "$BACKUP/"

echo "==> Remove nested cloned repo if present"
[ -d "$REPO" ] && rm -rf "$REPO"

echo "==> Create canonical structure"
mkdir -p platform/{infra,cluster,serving,distributed,observability,examples,scripts,tools/legacy}

move () {
  [ -e "$1" ] || return 0
  git mv "$1" "$2" 2>/dev/null || mv "$1" "$2"
}

move terraform   platform/infra/terraform
move kubernetes  platform/cluster/kubernetes
move kserve      platform/serving/kserve
move triton      platform/serving/triton
move docker      platform/serving/docker
move ray         platform/distributed/ray
move wandb       platform/observability/wandb
move examples    platform/examples
move scripts     platform/scripts

for f in setup.sh setup-simple.sh setup-final.sh; do
  [ -f "$f" ] && move "$f" "platform/tools/legacy/$f"
done

cat > .gitignore <<'GI'
.env
**/.env
*.key
*.pem
*api*key*
*token*

**/.terraform/
*.tfstate
*.tfstate.*

.vscode/
.idea/
GI

git rm -r --cached --ignore-unmatch **/.terraform **/*.tfstate* .env **/.env >/dev/null 2>&1 || true

echo "==> Cleanup done"
