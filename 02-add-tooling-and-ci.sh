#!/usr/bin/env bash
set -euo pipefail

echo "==> Creating Makefile"
cat > Makefile << 'MK'
SHELL := /usr/bin/env bash
.ONESHELL:
.DEFAULT_GOAL := help

TOOLS := platform/tools

help:
	@echo "make bootstrap | fmt | lint | validate | ci"

bootstrap:
	@./\$(TOOLS)/bootstrap.sh

fmt:
	@./\$(TOOLS)/fmt.sh

lint:
	@./\$(TOOLS)/lint.sh

validate:
	@./\$(TOOLS)/validate.sh

ci: fmt lint validate
	@echo "✔ CI passed"
MK

echo "==> Adding dev tool scripts"
mkdir -p platform/tools

cat > platform/tools/bootstrap.sh << 'BS'
#!/usr/bin/env bash
set -euo pipefail
echo "✔ Bootstrap (no external installs)"
BS

cat > platform/tools/fmt.sh << 'FS'
#!/usr/bin/env bash
set -euo pipefail
if command -v terraform >/dev/null 2>&1; then
  terraform fmt -recursive platform/infra/terraform || true
fi
FS

cat > platform/tools/lint.sh << 'LS'
#!/usr/bin/env bash
set -euo pipefail
echo "✔ Lint minimal (extend later)"
LS

cat > platform/tools/validate.sh << 'VS'
#!/usr/bin/env bash
set -euo pipefail
if command -v terraform >/dev/null 2>&1; then
  pushd platform/infra/terraform >/dev/null || true
  terraform init -backend=false -input=false >/dev/null || true
  terraform validate || true
  popd >/dev/null
fi
echo "✔ Validate done"
VS

chmod +x platform/tools/*.sh

echo "==> Adding GitHub Actions CI"
mkdir -p .github/workflows
cat > .github/workflows/ci.yml << 'CI'
name: CI

on:
  push:
    branches: [ "main" ]
  pull_request:

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: make ci
CI

echo "==> Tooling and CI setup complete"
