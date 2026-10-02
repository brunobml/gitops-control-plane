#!/usr/bin/env bash
# Phase 5 A.1/A.3/A.4: observability secrets, never stored in Git (review remark R-1).
#
# - Generates each value once into ~/.config/gitops-lab (mode 600); re-runs keep them.
# - Hub  monitoring/remote-write-htpasswd     Traefik basic auth for the remote-write endpoint
#                                              (one user per spoke; bcrypt, rewritten only if stale)
# - Spoke monitoring/remote-write-credentials  username/password the spoke agent sends
# - Hub  monitoring/grafana-admin              local Grafana admin (break-glass)
# - Hub  monitoring/grafana-oidc               Keycloak client secret for Grafana (same value as
#                                              LAB_GRAFANA_CLIENT_SECRET, see setup-keycloak-secrets.sh)
# - Never prints a value. Values reach kubectl through files, not process arguments.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SECRET_DIR="${GITOPS_LAB_SECRET_DIR:-$HOME/.config/gitops-lab}"
SPOKES=("spoke-nonprod" "spoke-prod")
H=(kubectl --context k3d-hub-cluster)

umask 077
mkdir -p "$SECRET_DIR"
chmod 700 "$SECRET_DIR"
gen() {
  local f="${SECRET_DIR}/$1"
  if [[ ! -s "$f" ]]; then
    python3 -c 'import secrets; print(secrets.token_urlsafe(24), end="")' > "$f"
    echo "Generated ${f}"
  fi
}
for s in "${SPOKES[@]}"; do gen "remote-write-${s}.password"; done
gen grafana-admin.password
gen grafana-client.secret   # also used by setup-keycloak-secrets.sh
printf %s "admin" > "${SECRET_DIR}/grafana-admin.username"

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
ns() {
  "$@" create namespace monitoring --dry-run=client -o yaml | "$@" apply -f - >/dev/null
  # Phase 5 F.0: Pod Security restricted (also declared in Git; see addons/*/namespace-monitoring.yaml)
  "$@" label namespace monitoring --overwrite pod-security.kubernetes.io/enforce=restricted pod-security.kubernetes.io/enforce-version=latest >/dev/null
}

# Hub: htpasswd for Traefik. Keep the existing bcrypt line when it still matches the password,
# so re-runs do not rewrite the Secret.
ns "${H[@]}"
"${H[@]}" -n monitoring get secret remote-write-htpasswd -o jsonpath='{.data.users}' 2>/dev/null | base64 -d > "$TMP/old" || true
SECRET_DIR="$SECRET_DIR" python3 - "$TMP/old" "$TMP/users" "${SPOKES[@]}" <<'EOF'
import bcrypt, os, sys
old_path, out_path, spokes = sys.argv[1], sys.argv[2], sys.argv[3:]
old = {}
for line in open(old_path).read().splitlines():
    if ':' in line:
        u, h = line.split(':', 1); old[u] = h
lines = []
for s in spokes:
    pw = open(os.path.join(os.environ['SECRET_DIR'], f'remote-write-{s}.password'), 'rb').read()
    h = old.get(s)
    if not (h and bcrypt.checkpw(pw, h.encode())):
        h = bcrypt.hashpw(pw, bcrypt.gensalt(rounds=10)).decode()
    lines.append(f'{s}:{h}')
open(out_path, 'w').write('\n'.join(lines) + '\n')
EOF
"${H[@]}" -n monitoring create secret generic remote-write-htpasswd --from-file=users="$TMP/users" \
  --dry-run=client -o yaml | "${H[@]}" apply -f - >/dev/null

"${H[@]}" -n monitoring create secret generic grafana-admin \
  --from-file=admin-user="${SECRET_DIR}/grafana-admin.username" \
  --from-file=admin-password="${SECRET_DIR}/grafana-admin.password" \
  --dry-run=client -o yaml | "${H[@]}" apply -f - >/dev/null
"${H[@]}" -n monitoring create secret generic grafana-oidc \
  --from-file=client-secret="${SECRET_DIR}/grafana-client.secret" \
  --dry-run=client -o yaml | "${H[@]}" apply -f - >/dev/null

# Spokes: the credential each agent presents.
for s in "${SPOKES[@]}"; do
  K=(kubectl --context "k3d-${s}")
  ns "${K[@]}"
  printf %s "$s" > "$TMP/user"
  "${K[@]}" -n monitoring create secret generic remote-write-credentials \
    --from-file=username="$TMP/user" --from-file=password="${SECRET_DIR}/remote-write-${s}.password" \
    --dry-run=client -o yaml | "${K[@]}" apply -f - >/dev/null
done

echo "✔ Observability secrets applied (values in ${SECRET_DIR}, mode 600, never committed)"
