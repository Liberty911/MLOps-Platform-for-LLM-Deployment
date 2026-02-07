#!/usr/bin/env bash
set -e
command -v terraform >/dev/null && terraform fmt -recursive platform/infra/terraform || true
