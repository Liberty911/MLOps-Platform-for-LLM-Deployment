#!/usr/bin/env bash
set -euo pipefail

echo "==> Showing structure"
tree -L 3 platform || find platform -maxdepth 3 -type d

echo "==> Running CI locally"
make ci

echo "✔ Local validation complete"
