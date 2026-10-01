#!/usr/bin/env bash
# Phase 3 A.3: basic-auth credential for the Headlamp ingress (Traefik Middleware headlamp-auth).
#
# - Generates a random password once, in ~/.config/gitops-lab (mode 600). Username: platform.
# - Stores only the bcrypt hash, in Secret headlamp/headlamp-basic-auth (htpasswd format,
#   key "users"), via server-side apply so no last-applied-configuration annotation is written.
# - Never prints the password or hash. The Secret is intentionally not in Git; the Middleware
#   that references it is (addons/headlamp/manifests/middleware.yaml).
set -euo pipefail

HUB_CONTEXT="k3d-hub-cluster"
NAMESPACE="headlamp"
USERNAME="platform"
SECRET_DIR="${GITOPS_LAB_SECRET_DIR:-$HOME/.config/gitops-lab}"
PW_FILE="${SECRET_DIR}/headlamp-basic-auth.password"

umask 077
mkdir -p "$SECRET_DIR"
chmod 700 "$SECRET_DIR"

if [[ ! -s "$PW_FILE" ]]; then
  python3 -c 'import secrets; print(secrets.token_urlsafe(24))' > "$PW_FILE"
  echo "Generated new Headlamp password in ${PW_FILE}"
fi

hash=$(argocd account bcrypt --password "$(cat "$PW_FILE")")

kubectl --context "$HUB_CONTEXT" create namespace "$NAMESPACE" --dry-run=client -o yaml \
  | kubectl --context "$HUB_CONTEXT" apply -f - >/dev/null
kubectl --context "$HUB_CONTEXT" -n "$NAMESPACE" create secret generic headlamp-basic-auth \
  --from-literal=users="${USERNAME}:${hash}" --dry-run=client -o yaml \
  | kubectl --context "$HUB_CONTEXT" apply --server-side --force-conflicts -f - >/dev/null
unset hash

echo "✔ Secret ${NAMESPACE}/headlamp-basic-auth applied (user: ${USERNAME})"
echo "  Password file: ${PW_FILE} (mode 600, never committed)"
