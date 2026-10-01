#!/usr/bin/env bash
# Phase 3 A.2: provision Argo CD local-account passwords without storing them in Git.
#
# - Generates a random password per account once, in ~/.config/gitops-lab (mode 600).
# - Writes the bcrypt hash into argocd-secret with kubectl (no Argo CD login needed,
#   so this also works as break-glass recovery when nobody can log in).
# - Ensures argocd-secret exists and carries helm.sh/resource-policy=keep, because the
#   Helm values set configs.secret.createSecret=false (Helm must not own this Secret).
# - Never prints a password or hash.
set -euo pipefail

HUB_CONTEXT="k3d-hub-cluster"
NAMESPACE="argocd"
ACCOUNTS=("platform-admin" "tenant-a")
SECRET_DIR="${GITOPS_LAB_SECRET_DIR:-$HOME/.config/gitops-lab}"

umask 077
mkdir -p "$SECRET_DIR"
chmod 700 "$SECRET_DIR"

# Ensure the Secret exists (fresh install with createSecret=false) and is protected from Helm.
if ! kubectl --context "$HUB_CONTEXT" -n "$NAMESPACE" get secret argocd-secret >/dev/null 2>&1; then
  kubectl --context "$HUB_CONTEXT" -n "$NAMESPACE" create secret generic argocd-secret
fi
kubectl --context "$HUB_CONTEXT" -n "$NAMESPACE" annotate secret argocd-secret \
  helm.sh/resource-policy=keep --overwrite >/dev/null

now=$(date -u +%FT%TZ)
patch=""
for account in "${ACCOUNTS[@]}"; do
  pw_file="${SECRET_DIR}/argocd-${account}.password"
  if [[ ! -s "$pw_file" ]]; then
    python3 -c 'import secrets; print(secrets.token_urlsafe(24))' > "$pw_file"
    echo "Generated new password for '${account}' in ${pw_file}"
  fi
  hash=$(argocd account bcrypt --password "$(cat "$pw_file")")
  patch+="\"accounts.${account}.password\":\"${hash}\",\"accounts.${account}.passwordMtime\":\"${now}\","
done

kubectl --context "$HUB_CONTEXT" -n "$NAMESPACE" patch secret argocd-secret \
  --type merge -p "{\"stringData\":{${patch%,}}}" >/dev/null
unset patch hash

echo "✔ Argo CD account passwords set for: ${ACCOUNTS[*]}"
echo "  Password files: ${SECRET_DIR}/argocd-<account>.password (mode 600, never committed)"
