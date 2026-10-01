#!/usr/bin/env bash
set -euo pipefail

HUB_CTX="k3d-hub-cluster"
NONPROD_CTX="k3d-spoke-nonprod"
PROD_CTX="k3d-spoke-prod"

echo "Configuring Headlamp Multi-Cluster Credentials on Hub..."

# 1. Ensure namespace exists
kubectl --context "${HUB_CTX}" create namespace headlamp --dry-run=client -o yaml | kubectl --context "${HUB_CTX}" apply -f -

# 2. Ensure ServiceAccount headlamp and ClusterRoleBinding exist on Hub (without permanent legacy token secret - B2)
cat <<EOF | kubectl --context "${HUB_CTX}" apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: headlamp
  namespace: headlamp
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: headlamp-admin
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: headlamp
  namespace: headlamp
EOF

# Delete legacy permanent token secret if present (B2)
kubectl --context "${HUB_CTX}" -n headlamp delete secret headlamp-token 2>/dev/null || true

# 3. Retrieve TokenRequest token for Hub and spoke tokens from Argo CD cluster secrets
HUB_TOKEN=$(kubectl --context "${HUB_CTX}" -n headlamp create token headlamp --duration=720h)
NONPROD_TOKEN=$(kubectl --context "${HUB_CTX}" -n argocd get secret cluster-spoke-nonprod -o jsonpath='{.data.config}' | base64 -d | jq -r .bearerToken)
PROD_TOKEN=$(kubectl --context "${HUB_CTX}" -n argocd get secret cluster-spoke-prod -o jsonpath='{.data.config}' | base64 -d | jq -r .bearerToken)

# 4. Assemble multi-cluster kubeconfig
TMP_KUBECONFIG=$(mktemp)
cat <<EOF > "${TMP_KUBECONFIG}"
apiVersion: v1
kind: Config
clusters:
- cluster:
    server: https://k3d-hub-cluster-server-0:6443
    insecure-skip-tls-verify: true
  name: k3d-hub-cluster
- cluster:
    server: https://k3d-spoke-nonprod-server-0:6443
    insecure-skip-tls-verify: true
  name: k3d-spoke-nonprod
- cluster:
    server: https://k3d-spoke-prod-server-0:6443
    insecure-skip-tls-verify: true
  name: k3d-spoke-prod
contexts:
- context:
    cluster: k3d-hub-cluster
    user: hub-admin
  name: k3d-hub-cluster
- context:
    cluster: k3d-spoke-nonprod
    user: spoke-nonprod-admin
  name: k3d-spoke-nonprod
- context:
    cluster: k3d-spoke-prod
    user: spoke-prod-admin
  name: k3d-spoke-prod
current-context: k3d-hub-cluster
users:
- name: hub-admin
  user:
    token: ${HUB_TOKEN}
- name: spoke-nonprod-admin
  user:
    token: ${NONPROD_TOKEN}
- name: spoke-prod-admin
  user:
    token: ${PROD_TOKEN}
EOF

# 5. Strip existing plaintext last-applied-configuration annotation before server-side apply (B1)
kubectl --context "${HUB_CTX}" -n headlamp annotate secret headlamp-kubeconfig \
  kubectl.kubernetes.io/last-applied-configuration- 2>/dev/null || true

# 6. Create or update the Kubernetes Secret in namespace headlamp via server-side apply (B1)
kubectl --context "${HUB_CTX}" -n headlamp create secret generic headlamp-kubeconfig \
  --from-file=config="${TMP_KUBECONFIG}" \
  --dry-run=client -o yaml | kubectl --context "${HUB_CTX}" apply --server-side --force-conflicts -f -

rm -f "${TMP_KUBECONFIG}"
echo "✔ Successfully generated and applied 'headlamp-kubeconfig' secret to namespace 'headlamp' via server-side apply."
