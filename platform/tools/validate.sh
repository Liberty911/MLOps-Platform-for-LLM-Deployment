#!/usr/bin/env bash
set -e
command -v terraform >/dev/null && terraform validate || true
