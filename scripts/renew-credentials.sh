#!/usr/bin/env bash
# Renew the spoke (Argo CD) and Headlamp tokens when fewer than RENEW_DAYS (default 7) days are left
# (Phase 5 D.2, owner decision O-4: renewal is condition-based, not a calendar). Expiries come from
# monitoring/credential-expiry (written whenever a token is minted); missing data also renews.
# Shared by post-bootstrap.sh (step 1) and maintain.sh (2026-10-03 Track G.3).
# ARGOCD_CFG: an argocd CLI config with a session (post-bootstrap passes its own); otherwise this
# script logs in as platform-admin with a private config. Never prints a token or password.
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SECRET_DIR="${GITOPS_LAB_SECRET_DIR:-$HOME/.config/gitops-lab}"
RENEW_DAYS="${RENEW_DAYS:-7}"

if [[ -z "${ARGOCD_CFG:-}" ]]; then
  ARGOCD_CFG=$(mktemp)
  trap 'rm -f "$ARGOCD_CFG"' EXIT
  argocd login localhost --plaintext --grpc-web --skip-test-tls --config "$ARGOCD_CFG" \
    --username platform-admin --password "$(cat "${SECRET_DIR}/argocd-platform-admin.password")" </dev/null >/dev/null
fi

min_exp=$(kubectl --context k3d-hub-cluster -n monitoring get configmap credential-expiry -o json 2>/dev/null \
  | jq -r '[.data // {} | to_entries[] | select(.key|test("^(argocd|headlamp)-")) | .value | tonumber] | if length >= 5 then min else 0 end' || echo 0)
days_left=$(( (${min_exp:-0} - $(date +%s)) / 86400 ))
if (( ${min_exp:-0} == 0 || days_left < RENEW_DAYS )); then
  echo "↻ renewing spoke and Headlamp tokens (shortest left: ${days_left} days)"
  # register-spokes.sh calls the argocd CLI; ARGOCD_OPTS points it at this session.
  ARGOCD_OPTS="--config ${ARGOCD_CFG}" bash "${SCRIPT_DIR}/register-spokes.sh" </dev/null
  bash "${SCRIPT_DIR}/../addons/headlamp/setup-credentials.sh" </dev/null
else
  echo "✔ shortest credential lifetime left: ${days_left} days"
fi
