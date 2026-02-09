#!/usr/bin/env bash
set -euo pipefail

echo "==> Current resolv.conf"
sudo cat /etc/resolv.conf || true

echo
echo "==> Check if localhost DNS is being used"
grep -E 'nameserver (127\.0\.0\.1|::1)' /etc/resolv.conf && echo "LOCALHOST DNS DETECTED" || echo "OK (not localhost)"

echo
echo "==> Restart NetworkManager (most common fix on RHEL desktop)"
sudo systemctl restart NetworkManager

echo
echo "==> After restart, resolv.conf"
sudo cat /etc/resolv.conf || true

echo
echo "==> DNS test (generic)"
getent hosts google.com || true

echo
echo "==> DNS test (EKS endpoint from kubeconfig)"
EKS_HOST="$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}' | sed 's|https\?://||' | cut -d/ -f1)"
echo "EKS host: $EKS_HOST"
getent hosts "$EKS_HOST" || true

echo
echo "==> If EKS host did NOT resolve, set public DNS temporarily (Google DNS) and retest"
if ! getent hosts "$EKS_HOST" >/dev/null 2>&1; then
  echo "Setting resolv.conf to Google DNS temporarily..."
  sudo cp -a /etc/resolv.conf "/etc/resolv.conf.bak.$(date +%s)" || true
  sudo bash -c 'cat > /etc/resolv.conf <<RES
nameserver 8.8.8.8
nameserver 1.1.1.1
options timeout:1 attempts:3
RES'
  echo "==> New resolv.conf"
  sudo cat /etc/resolv.conf
  echo "==> Retest EKS host"
  getent hosts "$EKS_HOST" || true
fi

echo
echo "==> Done"
