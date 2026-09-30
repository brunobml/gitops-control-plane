#!/usr/bin/env bash
set -euo pipefail

HUB_CTX="k3d-hub-cluster"
NONPROD_CTX="k3d-spoke-nonprod"
PROD_CTX="k3d-spoke-prod"

echo "Configuring Headlamp Multi-Cluster Credentials on Hub..."

# 1. Ensure namespace exists
kubectl --context "${HUB_CTX}" create namespace headlamp --dry-run=client -o yaml | kubectl --context "${HUB_CTX}" apply -f -

# 2. Ensure ServiceAccount headlamp, ClusterRoleBinding and permanent token exist on Hub
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
---
apiVersion: v1
kind: Secret
metadata:
  name: headlamp-token
  namespace: headlamp
  annotations:
    kubernetes.io/service-account.name: headlamp
type: kubernetes.io/service-account-token
EOF

# Brief pause to ensure token controller populates secret data
sleep 2

# 3. Retrieve tokens
HUB_TOKEN=$(kubectl --context "${HUB_CTX}" -n headlamp get secret headlamp-token -o jsonpath='{.data.token}' | base64 -d)
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

# 5. Create or update the Kubernetes Secret in namespace headlamp
kubectl --context "${HUB_CTX}" -n headlamp create secret generic headlamp-kubeconfig \
  --from-file=config="${TMP_KUBECONFIG}" \
  --dry-run=client -o yaml | kubectl --context "${HUB_CTX}" apply -f -

rm -f "${TMP_KUBECONFIG}"
echo "✔ Successfully generated and applied 'headlamp-kubeconfig' secret to namespace 'headlamp'."
