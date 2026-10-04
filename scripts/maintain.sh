#!/usr/bin/env bash
# 2026-10-03 Track G.3 (reduced; owner decision O-10: run manually, `make maintain`): the lab's
# routine upkeep without the full post-bootstrap and smoke test:
#   1. renew spoke and Headlamp tokens when fewer than 7 days are left (scripts/renew-credentials.sh)
#   2. remove what deregistered tenant apps left behind (scripts/orphans.sh, owner decision O-3)
# Review remark R-14: non-interactive; when Docker or the hub is not reachable (lab stopped) it logs
# that and exits 0; everything is also appended to ~/.config/gitops-lab/logs/maintain.log.
# Safety net if nobody runs it: alert SpokeTokenExpiringSoon (7 days before expiry).
set -uo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SECRET_DIR="${GITOPS_LAB_SECRET_DIR:-$HOME/.config/gitops-lab}"
LOG_DIR="${SECRET_DIR}/logs"
LOG="${LOG_DIR}/maintain.log"
umask 077
mkdir -p "$LOG_DIR"; chmod 700 "$LOG_DIR"
exec </dev/null > >(while IFS= read -r l; do printf '%s %s\n' "$(date -u +%FT%TZ)" "$l"; done | tee -a "$LOG") 2>&1
LOGGER=$!
# close our side of the pipe and let the logger finish, so no line is lost after exit
trap 'exec >&- 2>&-; wait "$LOGGER" 2>/dev/null' EXIT

echo "== maintain start"
if ! timeout 20 docker info >/dev/null 2>&1; then
  echo "Docker is not reachable: lab not running, nothing to do"; echo "== maintain end (skipped)"; exit 0
fi
if ! timeout 15 kubectl --context k3d-hub-cluster get --raw /readyz >/dev/null 2>&1 \
   || ! timeout 10 curl -sf -o /dev/null http://localhost/healthz; then
  echo "hub cluster or Argo CD is not reachable: lab stopped, nothing to do"; echo "== maintain end (skipped)"; exit 0
fi

rc=0
echo "-- token renewal"
bash "${SCRIPT_DIR}/renew-credentials.sh" || rc=$?
echo "-- orphans of deregistered tenant apps"
bash "${SCRIPT_DIR}/orphans.sh" || rc=$?
echo "== maintain end (rc=${rc})"
# keep the log short
tail -n 2000 "$LOG" > "${LOG}.tmp" 2>/dev/null && mv "${LOG}.tmp" "$LOG"
exit "$rc"
