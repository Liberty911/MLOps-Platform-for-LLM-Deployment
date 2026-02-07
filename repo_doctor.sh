#!/usr/bin/env bash
set -euo pipefail

# =========================
# Repo Doctor for:
# https://github.com/Liberty911/MLOps-Platform-for-LLM-Deployment
# =========================

REPO_NAME="MLOps-Platform-for-LLM-Deployment"
NOW="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="../${REPO_NAME}-backup-${NOW}"

say(){ printf "\n\033[1;32m==>\033[0m %s\n" "$*"; }
warn(){ printf "\n\033[1;33m[WARN]\033[0m %s\n" "$*"; }
die(){ printf "\n\033[1;31m[ERROR]\033[0m %s\n" "$*"; exit 1; }

# Must be run in repo root (best-effort check)
[[ -d .git || -f README.md || -f Makefile ]] || die "Run this from your repo root folder (open VSCode in the project root)."

say "1) Create a safety backup copy (outside git) -> ${BACKUP_DIR}"
mkdir -p "${BACKUP_DIR}"
rsync -a --exclude='.git' ./ "${BACKUP_DIR}/"

# Helper: use git mv if git repo, else mv
mv_smart(){
  local src="$1" dst="$2"
  [[ -e "$src" ]] || return 0
  mkdir -p "$(dirname "$dst")"
  if [[ -d .git ]] && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git mv "$src" "$dst" 2>/dev/null || mv "$src" "$dst"
  else
    mv "$src" "$dst"
  fi
}

say "2) Remove nested cloned repo folder if it exists (common duplicate cause)"
# If you accidentally cloned inside itself, you often end up with ./MLOps-Platform-for-LLM-Deployment/...
if [[ -d "./${REPO_NAME}" ]]; then
  warn "Found nested folder ./${REPO_NAME}. Removing it to stop duplicates."
  rm -rf "./${REPO_NAME}"
fi

say "3) Standardize layout under platform/"
mkdir -p platform/{infra,cluster,serving,distributed,observability,examples,docs,scripts,tools}

# Move existing top-level dirs into a clean hierarchy (no content loss)
mv_smart terraform     platform/infra/terraform
mv_smart kubernetes    platform/cluster/kubernetes
mv_smart kserve        platform/serving/kserve
mv_smart triton        platform/serving/triton
mv_smart docker        platform/serving/docker
mv_smart ray           platform/distributed/ray
mv_smart wandb         platform/observability/wandb
mv_smart examples      platform/examples
mv_smart scripts       platform/scripts

say "4) Replace scattered setup scripts with a single entrypoint (keep originals archived)"
mkdir -p platform/tools/legacy-setup
for f in setup.sh setup-simple.sh setup-final.sh; do
  if [[ -f "$f" ]]; then
    mv_smart "$f" "platform/tools/legacy-setup/${f}"
  fi
done

say "5) Create a strict .gitignore (prevents secrets/state from ever being pushed again)"
cat > .gitignore <<'EOF'
# --- Secrets ---
.env
**/.env
*.pem
*.key
*.p12
*.pfx
*api*key*
*token*
*secret*
wandb*
**/wandb/**/run-*
**/wandb/**/logs/**
**/wandb/**/media/**

# --- Terraform ---
**/.terraform/
*.tfstate
*.tfstate.*
crash.log
crash.*.log
.terraform.lock.hcl

# --- Python / Node ---
__pycache__/
*.pyc
.venv/
node_modules/

# --- OS / IDE ---
.DS_Store
.vscode/
.idea/
EOF

say "6) Add docs and a professional README (keeps your existing one as docs/legacy)"
mkdir -p docs
if [[ -f README.md ]]; then
  mv_smart README.md docs/LEGACY_README.md
fi

cat > README.md <<'EOF'
# MLOps Platform for LLM Deployment (Kubernetes + Triton + KServe + Ray)

A practical, portfolio-grade platform repo showing how to provision infrastructure, deploy serving stacks, and run reproducible checks in CI.

## What’s in this repo
- **Infra (Terraform):** `platform/infra/terraform`
- **Cluster manifests:** `platform/cluster/kubernetes`
- **Serving:** Triton + KServe in `platform/serving/`
- **Distributed workloads:** Ray in `platform/distributed/ray`
- **Observability:** W&B integration assets in `platform/observability/wandb`
- **Examples:** `platform/examples`

## Quick start (local validation)
```bash
make bootstrap
make ci
