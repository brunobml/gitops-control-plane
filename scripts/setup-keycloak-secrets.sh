#!/usr/bin/env bash
# Phase 4 A.1: lab identity secrets for Keycloak SSO, never stored in Git.
#
# - Generates each value once into ~/.config/gitops-lab (mode 600); re-runs keep them.
# - Applies them as Kubernetes Secrets on the hub, built from the files (values never appear
#   in process arguments or output):
#     keycloak/keycloak-bootstrap-admin   Keycloak admin console (break-glass for the IdP)
#     keycloak/keycloak-realm-secrets     ${…} placeholders of addons/keycloak/realm-lab.json
#     oauth2-proxy/oauth2-proxy-credentials  Headlamp SSO (client + cookie secret)
# - Never prints a value.
set -euo pipefail

HUB_CONTEXT="k3d-hub-cluster"
SECRET_DIR="${GITOPS_LAB_SECRET_DIR:-$HOME/.config/gitops-lab}"
K=(kubectl --context "$HUB_CONTEXT")

umask 077
mkdir -p "$SECRET_DIR"
chmod 700 "$SECRET_DIR"

# file name -> generated once
gen() {
  local f="${SECRET_DIR}/$1"
  if [[ ! -s "$f" ]]; then
    # 24 random bytes -> 32 URL-safe characters (also a valid oauth2-proxy cookie secret length).
    python3 -c 'import secrets; print(secrets.token_urlsafe(24), end="")' > "$f"
    echo "Generated ${f}"
  fi
}
for f in keycloak-admin.password keycloak-platform-user.password keycloak-tenant-a-user.password \
         oauth2-proxy-client.secret oauth2-proxy-cookie.secret; do
  gen "$f"
done
printf %s "kc-admin" > "${SECRET_DIR}/keycloak-admin.username"

for ns in keycloak oauth2-proxy; do
  "${K[@]}" create namespace "$ns" --dry-run=client -o yaml | "${K[@]}" apply -f - >/dev/null
done

"${K[@]}" -n keycloak create secret generic keycloak-bootstrap-admin \
  --from-file=KC_BOOTSTRAP_ADMIN_USERNAME="${SECRET_DIR}/keycloak-admin.username" \
  --from-file=KC_BOOTSTRAP_ADMIN_PASSWORD="${SECRET_DIR}/keycloak-admin.password" \
  --dry-run=client -o yaml | "${K[@]}" apply -f - >/dev/null

"${K[@]}" -n keycloak create secret generic keycloak-realm-secrets \
  --from-file=LAB_PLATFORM_USER_PASSWORD="${SECRET_DIR}/keycloak-platform-user.password" \
  --from-file=LAB_TENANT_A_USER_PASSWORD="${SECRET_DIR}/keycloak-tenant-a-user.password" \
  --from-file=LAB_HEADLAMP_CLIENT_SECRET="${SECRET_DIR}/oauth2-proxy-client.secret" \
  --dry-run=client -o yaml | "${K[@]}" apply -f - >/dev/null

printf %s "headlamp" > "${SECRET_DIR}/oauth2-proxy-client.id"
"${K[@]}" -n oauth2-proxy create secret generic oauth2-proxy-credentials \
  --from-file=client-id="${SECRET_DIR}/oauth2-proxy-client.id" \
  --from-file=client-secret="${SECRET_DIR}/oauth2-proxy-client.secret" \
  --from-file=cookie-secret="${SECRET_DIR}/oauth2-proxy-cookie.secret" \
  --dry-run=client -o yaml | "${K[@]}" apply -f - >/dev/null

echo "✔ Keycloak / oauth2-proxy secrets applied (values in ${SECRET_DIR}, mode 600, never committed)"
echo "  SSO users: platform-user (lab-platform-admins), tenant-a-user (lab-tenant-a)"
echo "  Passwords: ${SECRET_DIR}/keycloak-<user>.password"
