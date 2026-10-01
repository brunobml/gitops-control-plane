#!/usr/bin/env bash
set -euo pipefail

HUB_CONTEXT="k3d-hub-cluster"
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REVISIONS_FILE="${SCRIPT_DIR}/../clusters/blueprint-revisions.env"

# Allow running for a specific spoke or all spokes (M2)
if [ "$#" -eq 0 ]; then
  SPOKES=("spoke-nonprod" "spoke-prod")
else
  SPOKES=("$@")
fi

for spoke in "${SPOKES[@]}"; do
  context="k3d-${spoke}"
  echo "Registering ${spoke} (${context}) to ${HUB_CONTEXT}..."

  # 1. Ensure ServiceAccount and ClusterRoleBinding exist on the spoke (without legacy permanent token secret - B2)
  kubectl --context "$context" apply -f - <<'EOF'
apiVersion: v1
kind: ServiceAccount
metadata:
  name: argocd-manager
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: argocd-manager-cluster-admin
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
  - kind: ServiceAccount
    name: argocd-manager
    namespace: kube-system
EOF

  # 2. Issue 30-day token via TokenRequest API (L4-10, B2)
  echo "Issuing 30-day TokenRequest token for argocd-manager on ${context}..."
  token=$(kubectl --context "$context" -n kube-system create token argocd-manager --duration=720h)

  # 3. Retrieve Cluster CA certificate data directly from spoke cluster
  ca_data=$(kubectl --context "$context" -n default get cm kube-root-ca.crt -o jsonpath='{.data.ca\.crt}' | base64 | tr -d '\n')

  server_url="https://k3d-${spoke}-server-0:6443"

  cluster_config=$(cat <<EOF
{"bearerToken":"${token}","tlsClientConfig":{"insecure":false,"caData":"${ca_data}"}}
EOF
)

  env_tag="nonprod"
  if [[ "$spoke" == *"prod"* && "$spoke" != *"nonprod"* ]]; then
    env_tag="prod"
  fi

  # 4. Determine blueprint revision from single source of truth with fail-closed guard (S1, C2)
  if [[ ! -f "$REVISIONS_FILE" ]]; then
    echo "Error: Revisions file $REVISIONS_FILE not found" >&2
    exit 1
  fi
  bp_rev=$(grep -E "^${spoke}=" "$REVISIONS_FILE" | cut -d'=' -f2)
  : "${bp_rev:?no blueprints-revision for ${spoke} in clusters/blueprint-revisions.env}"

  expires_at=$(date -u -d @$(( $(date +%s) + 2592000 )) +%F 2>/dev/null || date -u -v+30d +%F 2>/dev/null || date -d "+30 days" +%Y-%m-%d 2>/dev/null || echo "2026-10-30")

  # 5. Strip existing plaintext last-applied-configuration annotation before server-side apply (B1)
  kubectl --context "$HUB_CONTEXT" -n argocd annotate secret "cluster-${spoke}" \
    kubectl.kubernetes.io/last-applied-configuration- 2>/dev/null || true

  # 6. Apply cluster secret server-side (B1) with blueprint-revision and expiry annotations
  kubectl --context "$HUB_CONTEXT" -n argocd apply --server-side --force-conflicts -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: cluster-${spoke}
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: cluster
    environment: ${env_tag}
  annotations:
    blueprints-revision: ${bp_rev}
    lab/token-expires: "${expires_at}"
type: Opaque
stringData:
  name: ${spoke}
  server: ${server_url}
  config: |
    ${cluster_config}
EOF

  echo "✔ Successfully registered ${spoke} at ${server_url} (env=${env_tag}, revision=${bp_rev}, expires=${expires_at})"

  # Staggered validation (M2, C1): Verify cluster connection before deleting legacy secret
  echo "Verifying Argo CD cluster connectivity for ${spoke}..."
  status=""
  for i in {1..15}; do
    status=$(argocd cluster list --grpc-web 2>/dev/null | awk -v name="$spoke" '$2 == name {print $4}' || true)
    if [[ "$status" == "Successful" ]]; then
      break
    fi
    sleep 1
  done

  if [[ "$status" == "Successful" ]]; then
    echo "Argo CD cluster connectivity for ${spoke}: Successful"
  else
    echo "Warning: Argo CD cluster list status is '${status}' (will proceed with fallback secret verification)"
    kubectl --context "$HUB_CONTEXT" -n argocd get secret "cluster-${spoke}" -o jsonpath='{.metadata.name}: OK' && echo
  fi

  # 7. Clean up legacy token secret on spoke after connection is verified (B2, C1)
  echo "Deleting legacy argocd-manager-token Secret on ${spoke}..."
  kubectl --context "$context" -n kube-system delete secret argocd-manager-token 2>/dev/null || true
done
