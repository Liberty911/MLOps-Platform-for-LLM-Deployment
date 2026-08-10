#!/usr/bin/env bash
echo "Checking shell scripts..."
find platform -name '*.sh' -print0 | xargs -0 -n1 bash -n
echo "Lint OK (bash -n)."
