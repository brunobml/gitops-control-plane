#!/usr/bin/env bash
# Temporary SSO user in Keycloak realm "lab" (Argo CD, Headlamp, Grafana, Keycloak account console).
# For a short task (a demo, screenshots, a pairing session): create it, use it, delete it.
#
#   scripts/temp-sso-user.sh create <username> [lab-tenant-a|lab-platform-admins] [hours]
#   scripts/temp-sso-user.sh delete <username>
#   scripts/temp-sso-user.sh list
#
# - Default group lab-tenant-a (least privilege: Argo CD role tenant-a, Grafana Viewer).
#   lab-platform-admins gives Argo CD admin and Grafana Admin; use it only when the task needs it.
# - The password is generated into ~/.config/gitops-lab/keycloak-<username>.password (mode 600)
#   and never printed or passed on a command line; delete removes the file.
# - The user is marked with first name "Temporary" and last name "until <UTC time>" (custom
#   attributes would be dropped: the realm's user profile does not allow unmanaged attributes),
#   so `list` shows leftovers. Nothing deletes them automatically, except a Keycloak restart:
#   Keycloak runs start-dev without a persistent database and re-imports only permanent users.
# - Keycloak admin access uses kc-admin from ~/.config/gitops-lab (break-glass admin of the IdP).
# - Deleting the user ends its Keycloak sessions at once; sessions the apps already hold end when
#   their own tokens or cookies expire (see docs/runbooks/argocd-cli.md, "Temporary SSO user").
set -euo pipefail
SECRET_DIR="${GITOPS_LAB_SECRET_DIR:-$HOME/.config/gitops-lab}"
KC=http://keycloak.localhost
REALM=lab
PERMANENT=(platform-user tenant-a-user)
umask 077
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

usage() { sed -n '4,7p' "$0" | sed 's/^# \{0,3\}//' >&2; exit 2; }
admin_token() {
  curl -sf "${KC}/realms/master/protocol/openid-connect/token" \
    -d grant_type=password -d client_id=admin-cli \
    --data-urlencode "username@${SECRET_DIR}/keycloak-admin.username" \
    --data-urlencode "password@${SECRET_DIR}/keycloak-admin.password" | jq -r .access_token
}
api() {  # api METHOD PATH [json-file]
  local args=(-sf -X "$1" -H "Authorization: Bearer ${TOKEN}" "${KC}/admin/realms/${REALM}$2")
  [[ -n "${3:-}" ]] && args+=(-H 'Content-Type: application/json' --data-binary "@$3")
  curl "${args[@]}"
}
user_id() { api GET "/users?username=$1&exact=true" | jq -r '.[0].id // empty'; }
check_name() {
  [[ "$1" =~ ^[a-z0-9][a-z0-9.-]{2,30}$ ]] || { echo "✘ username must be 3-31 chars of a-z 0-9 . -" >&2; exit 1; }
  for p in "${PERMANENT[@]}"; do [[ "$1" != "$p" ]] || { echo "✘ $1 is a permanent realm user; refusing" >&2; exit 1; }; done
}

cmd=${1:-}; [[ -n "$cmd" ]] || usage
TOKEN=$(admin_token); [[ -n "$TOKEN" && "$TOKEN" != null ]] || { echo "✘ cannot get a Keycloak admin token (is the lab up?)" >&2; exit 1; }

case "$cmd" in
  create)
    name=${2:-}; group=${3:-lab-tenant-a}; hours=${4:-8}
    [[ -n "$name" ]] || usage; check_name "$name"
    [[ "$group" == lab-tenant-a || "$group" == lab-platform-admins ]] || { echo "✘ group must be lab-tenant-a or lab-platform-admins" >&2; exit 1; }
    [[ -z "$(user_id "$name")" ]] || { echo "✘ user $name already exists" >&2; exit 1; }
    pwfile="${SECRET_DIR}/keycloak-${name}.password"
    python3 -c 'import secrets; print(secrets.token_urlsafe(18), end="")' > "$pwfile"; chmod 600 "$pwfile"
    expires=$(( $(date +%s) + hours * 3600 ))
    # JSON body built from the password file inside python: the value never reaches argv or stdout
    NAME=$name GROUP=$group EXPIRES=$expires PWFILE=$pwfile python3 - > "$TMP/user.json" <<'EOF'
import json, os
print(json.dumps({
    "username": os.environ["NAME"], "enabled": True, "emailVerified": True,
    "email": f'{os.environ["NAME"]}@lab.local', "firstName": "Temporary",
    "lastName": "until " + __import__("time").strftime("%Y-%m-%dT%H:%MZ", __import__("time").gmtime(int(os.environ["EXPIRES"]))),
    "groups": ["/" + os.environ["GROUP"]],
    "credentials": [{"type": "password", "value": open(os.environ["PWFILE"]).read(), "temporary": False}],
}))
EOF
    api POST /users "$TMP/user.json" >/dev/null
    echo "✔ created ${name} in realm ${REALM}, group ${group}, marked temporary until $(date -u -d @"$expires" '+%F %H:%M') UTC"
    echo "  password file: ${pwfile} (mode 600). Delete when done: scripts/temp-sso-user.sh delete ${name}"
    ;;
  delete)
    name=${2:-}; [[ -n "$name" ]] || usage; check_name "$name"
    id=$(user_id "$name")
    if [[ -n "$id" ]]; then
      api POST "/users/${id}/logout" >/dev/null || true
      api DELETE "/users/${id}" >/dev/null
      echo "✔ deleted ${name} (Keycloak sessions ended)"
    else
      echo "  ${name} does not exist in realm ${REALM}"
    fi
    rm -f "${SECRET_DIR}/keycloak-${name}.password"
    [[ -z "$(user_id "$name")" ]] && echo "✔ verified: ${name} no longer exists; password file removed"
    ;;
  list)
    api GET "/users?firstName=Temporary&exact=true&max=100" \
      | jq -r --arg now "$(date -u +%Y-%m-%dT%H:%MZ)" '.[] | (.lastName | sub("^until "; "")) as $u | "  \(.username)\t\(if $u < $now then "EXPIRED since" else "temporary until" end) \($u)"'
    echo "  (permanent realm users are not listed)"
    ;;
  *) usage ;;
esac
