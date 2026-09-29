#!/usr/bin/env bash
set -euo pipefail

HUB_CONTEXT="k3d-hub-cluster"
SPOKES=("spoke-nonprod" "spoke-prod")

for spoke in "${SPOKES[@]}"; do
  context="k3d-${spoke}"
  echo "Registering ${spoke} (${context}) to ${HUB_CONTEXT}..."

  # Create ServiceAccount and ClusterRoleBinding on the spoke
  kubectl --context "$context" apply -f - <<'EOF'
apiVersion: v1
kind: ServiceAccount
metadata:
  name: argocd-manager
  namespace: kube-system
---
apiVersion: v1
kind: Secret
metadata:
  name: argocd-manager-token
  namespace: kube-system
  annotations:
    kubernetes.io/service-account.name: argocd-manager
type: kubernetes.io/service-account-token
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

  # Wait for token
  token=""
  ca_data=""
  for i in $(seq 1 30); do
    token=$(kubectl --context "$context" -n kube-system get secret argocd-manager-token -o jsonpath='{.data.token}' 2>/dev/null || true)
    ca_data=$(kubectl --context "$context" -n kube-system get secret argocd-manager-token -o jsonpath='{.data.ca\.crt}' 2>/dev/null || true)
    if [[ -n "$token" && -n "$ca_data" ]]; then
      break
    fi
    sleep 1
  done

  token_decoded=$(printf '%s' "$token" | base64 -d)
  server_url="https://k3d-${spoke}-server-0:6443"

  cluster_config=$(cat <<EOF
{"bearerToken":"${token_decoded}","tlsClientConfig":{"insecure":false,"caData":"${ca_data}"}}
EOF
)

  env_tag="nonprod"
  if [[ "$spoke" == *"prod"* && "$spoke" != *"nonprod"* ]]; then
    env_tag="prod"
  fi

  # Create cluster secret in hub-cluster
  kubectl --context "$HUB_CONTEXT" -n argocd apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: cluster-${spoke}
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: cluster
    environment: ${env_tag}
type: Opaque
stringData:
  name: ${spoke}
  server: ${server_url}
  config: |
    ${cluster_config}
EOF

  echo "✔ Successfully registered ${spoke} at ${server_url} with environment=${env_tag}"
done
