#!/usr/bin/env bash
# Secrets of the Policy Reporter UI (hub) and of the spokes' Policy Reporter APIs, never in Git.
#
# - Generates each value once into ~/.config/gitops-lab (mode 600); re-runs keep them:
#     policy-reporter-client.secret   Keycloak client policy-reporter (also used by setup-keycloak-secrets.sh)
#     policy-reporter-api.password    basic auth of the spokes' /pr-core and /pr-kyverno routes
# - Spokes: policy-reporter/policy-reporter-api-htpasswd (Traefik basic auth, bcrypt; an existing
#   line is kept while it still matches, so re-runs do not rewrite the Secret).
# - Hub: policy-reporter/policy-reporter-oidc (discoveryUrl, clientId, clientSecret) and one
#   policy-reporter/policy-reporter-cluster-<spoke> per spoke (API URLs + credentials, the format
#   of the chart's default-cluster Secret).
# - Values are read from files, never passed as arguments, never printed.
set -euo pipefail

SECRET_DIR="${GITOPS_LAB_SECRET_DIR:-$HOME/.config/gitops-lab}"
SPOKES=(spoke-nonprod spoke-prod)
NS=policy-reporter
USER_NAME=policy-reporter
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
gen policy-reporter-client.secret
gen policy-reporter-api.password

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
ns() {
  "$@" create namespace "$NS" --dry-run=client -o yaml | "$@" apply -f - >/dev/null
  "$@" label namespace "$NS" --overwrite pod-security.kubernetes.io/enforce=restricted \
    pod-security.kubernetes.io/enforce-version=latest >/dev/null
}

# Spokes: htpasswd for the Traefik basic-auth middleware
for s in "${SPOKES[@]}"; do
  K=(kubectl --context "k3d-${s}")
  ns "${K[@]}"
  "${K[@]}" -n "$NS" get secret policy-reporter-api-htpasswd -o jsonpath='{.data.users}' 2>/dev/null | base64 -d > "$TMP/old" || true
  SECRET_DIR="$SECRET_DIR" python3 - "$TMP/old" "$TMP/users" "$USER_NAME" <<'PY'
import bcrypt, os, sys
old_path, out_path, user = sys.argv[1:4]
pw = open(os.path.join(os.environ["SECRET_DIR"], "policy-reporter-api.password"), "rb").read()
old = dict(l.split(":", 1) for l in open(old_path).read().splitlines() if ":" in l)
h = old.get(user)
if not (h and bcrypt.checkpw(pw, h.encode())):
    h = bcrypt.hashpw(pw, bcrypt.gensalt(rounds=10)).decode()
open(out_path, "w").write(f"{user}:{h}\n")
PY
  "${K[@]}" -n "$NS" create secret generic policy-reporter-api-htpasswd --from-file=users="$TMP/users" \
    --dry-run=client -o yaml | "${K[@]}" apply -f - >/dev/null
done

# Hub: OIDC and one cluster Secret per spoke
ns "${H[@]}"
printf %s "http://keycloak.localhost/realms/lab/.well-known/openid-configuration" > "$TMP/discovery"
printf %s "policy-reporter" > "$TMP/client-id"
"${H[@]}" -n "$NS" create secret generic policy-reporter-oidc \
  --from-file=discoveryUrl="$TMP/discovery" --from-file=clientId="$TMP/client-id" \
  --from-file=clientSecret="${SECRET_DIR}/policy-reporter-client.secret" \
  --dry-run=client -o yaml | "${H[@]}" apply -f - >/dev/null
for s in "${SPOKES[@]}"; do
  rm -f "$TMP"/c.*
  SECRET_DIR="$SECRET_DIR" python3 - "$TMP" "$s" "$USER_NAME" <<'PY'
import json, os, sys
tmp, spoke, user = sys.argv[1:4]
pw = open(os.path.join(os.environ["SECRET_DIR"], "policy-reporter-api.password")).read()
base = f"http://k3d-{spoke}-serverlb"
files = {"host": f"{base}/pr-core", "username": user, "password": pw}
for key, name, suffix in (("plugin.kyverno", "kyverno", ""), ("plugin.kyverno.vpol", "KyvernoValidatingPolicy", "/vpol"),
                          ("plugin.kyverno.ivpol", "KyvernoImageValidatingPolicy", "/ivpol")):
    files[key] = json.dumps({"host": f"{base}/pr-kyverno{suffix}", "name": name, "username": user, "password": pw})
for k, v in files.items():
    with open(os.path.join(tmp, "c." + k), "w") as f:
        f.write(v)
PY
  args=()
  for f in "$TMP"/c.*; do args+=(--from-file="${f##*/c.}=$f"); done
  "${H[@]}" -n "$NS" create secret generic "policy-reporter-cluster-${s}" "${args[@]}" \
    --dry-run=client -o yaml | "${H[@]}" apply -f - >/dev/null
done
echo "✔ Policy Reporter secrets applied (values in ${SECRET_DIR}, mode 600, never committed)"
