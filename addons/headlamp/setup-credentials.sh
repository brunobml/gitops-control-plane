#!/usr/bin/env bash
set -euo pipefail

HUB_CTX="k3d-hub-cluster"
NONPROD_CTX="k3d-spoke-nonprod"
PROD_CTX="k3d-spoke-prod"

CLUSTERS=("${HUB_CTX}" "${NONPROD_CTX}" "${PROD_CTX}")

echo "Configuring Headlamp Multi-Cluster Least-Privilege Credentials..."

# 1. Ensure target namespaces and RBAC exist on all three clusters
for ctx in "${CLUSTERS[@]}"; do
  echo "Setting up RBAC on cluster: ${ctx}..."
  kubectl --context "${ctx}" create namespace headlamp-access --dry-run=client -o yaml | kubectl --context "${ctx}" apply -f -

  cat <<EOF | kubectl --context "${ctx}" apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: headlamp-viewer
  namespace: headlamp-access
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: headlamp-crd-viewer
  labels:
    rbac.authorization.k8s.io/aggregate-to-view: "true"
rules:
  - apiGroups: ["kro.run", "internal.kro.run"]
    resources: ["*"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["sqs.services.k8s.aws", "services.k8s.aws"]
    resources: ["*"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["apiextensions.k8s.io"]
    resources: ["customresourcedefinitions"]
    verbs: ["get", "list", "watch"]
---
# The built-in view role excludes cluster-scoped objects; Headlamp needs them read-only
# to show nodes, storage and node/pod metrics.
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: headlamp-cluster-viewer
  labels:
    rbac.authorization.k8s.io/aggregate-to-view: "true"
rules:
  - apiGroups: [""]
    resources: ["nodes", "persistentvolumes"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["storage.k8s.io"]
    resources: ["storageclasses", "csidrivers", "csinodes"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["networking.k8s.io"]
    resources: ["ingressclasses"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["node.k8s.io", "scheduling.k8s.io"]
    resources: ["runtimeclasses", "priorityclasses"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["metrics.k8s.io"]
    resources: ["nodes", "pods"]
    verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: headlamp-viewer-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: view
subjects:
  - kind: ServiceAccount
    name: headlamp-viewer
    namespace: headlamp-access
EOF
done

# 1b. Hub only (Phase 3 A.3 / PV2-3): read Argo CD objects so Headlamp can show them.
#     Applications, ApplicationSets and AppProjects hold no credentials (repository and
#     cluster credentials are Secrets, which the view role still excludes).
cat <<EOF | kubectl --context "${HUB_CTX}" apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: headlamp-argocd-viewer
  labels:
    rbac.authorization.k8s.io/aggregate-to-view: "true"
rules:
  - apiGroups: ["argoproj.io"]
    resources: ["applications", "applicationsets", "appprojects"]
    verbs: ["get", "list", "watch"]
EOF

# 2. Issue 720h (30d) TokenRequest tokens for dedicated viewer ServiceAccounts
echo "Issuing TokenRequest tokens..."
HUB_TOKEN=$(kubectl --context "${HUB_CTX}" -n headlamp-access create token headlamp-viewer --duration=720h)
NONPROD_TOKEN=$(kubectl --context "${NONPROD_CTX}" -n headlamp-access create token headlamp-viewer --duration=720h)
PROD_TOKEN=$(kubectl --context "${PROD_CTX}" -n headlamp-access create token headlamp-viewer --duration=720h)
# Phase 5 B.1: expiries (not the tokens) for the credential-expiry exporter
REC="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../scripts" && pwd)/record-credential-expiry.sh"
printf %s "$HUB_TOKEN" | bash "$REC" headlamp-k3d-hub-cluster
printf %s "$NONPROD_TOKEN" | bash "$REC" headlamp-k3d-spoke-nonprod
printf %s "$PROD_TOKEN" | bash "$REC" headlamp-k3d-spoke-prod

# 3. Retrieve root CA certificates directly from kube-root-ca.crt ConfigMaps
echo "Retrieving cluster root CA certificates..."
HUB_CA=$(kubectl --context "${HUB_CTX}" -n default get cm kube-root-ca.crt -o jsonpath='{.data.ca\.crt}' | base64 -w0)
NONPROD_CA=$(kubectl --context "${NONPROD_CTX}" -n default get cm kube-root-ca.crt -o jsonpath='{.data.ca\.crt}' | base64 -w0)
PROD_CA=$(kubectl --context "${PROD_CTX}" -n default get cm kube-root-ca.crt -o jsonpath='{.data.ca\.crt}' | base64 -w0)

# 4. Assemble multi-cluster kubeconfig with strict CA TLS verification (insecure-skip-tls-verify: false)
TMP_KUBECONFIG=$(mktemp)
cat <<EOF > "${TMP_KUBECONFIG}"
apiVersion: v1
kind: Config
clusters:
- cluster:
    server: https://k3d-hub-cluster-server-0:6443
    certificate-authority-data: ${HUB_CA}
    insecure-skip-tls-verify: false
  name: k3d-hub-cluster
- cluster:
    server: https://k3d-spoke-nonprod-server-0:6443
    certificate-authority-data: ${NONPROD_CA}
    insecure-skip-tls-verify: false
  name: k3d-spoke-nonprod
- cluster:
    server: https://k3d-spoke-prod-server-0:6443
    certificate-authority-data: ${PROD_CA}
    insecure-skip-tls-verify: false
  name: k3d-spoke-prod
contexts:
- context:
    cluster: k3d-hub-cluster
    user: headlamp-hub-viewer
  name: k3d-hub-cluster
- context:
    cluster: k3d-spoke-nonprod
    user: headlamp-spoke-nonprod-viewer
  name: k3d-spoke-nonprod
- context:
    cluster: k3d-spoke-prod
    user: headlamp-spoke-prod-viewer
  name: k3d-spoke-prod
current-context: k3d-hub-cluster
users:
- name: headlamp-hub-viewer
  user:
    token: ${HUB_TOKEN}
- name: headlamp-spoke-nonprod-viewer
  user:
    token: ${NONPROD_TOKEN}
- name: headlamp-spoke-prod-viewer
  user:
    token: ${PROD_TOKEN}
EOF

# 5. Ensure headlamp namespace exists on Hub
kubectl --context "${HUB_CTX}" create namespace headlamp --dry-run=client -o yaml | kubectl --context "${HUB_CTX}" apply -f -

# 6. Strip existing plaintext last-applied-configuration annotation before server-side apply (B1)
kubectl --context "${HUB_CTX}" -n headlamp annotate secret headlamp-kubeconfig \
  kubectl.kubernetes.io/last-applied-configuration- 2>/dev/null || true

# 7. Create or update the Kubernetes Secret in namespace headlamp via server-side apply (B1)
kubectl --context "${HUB_CTX}" -n headlamp create secret generic headlamp-kubeconfig \
  --from-file=config="${TMP_KUBECONFIG}" \
  --dry-run=client -o yaml | kubectl --context "${HUB_CTX}" apply --server-side --force-conflicts -f -

rm -f "${TMP_KUBECONFIG}"
echo "✔ Successfully generated and applied 'headlamp-kubeconfig' secret to namespace 'headlamp' via server-side apply."

# 7. Restart Headlamp so it loads the new kubeconfig. The Secret is mounted with
#    subPath, and subPath mounts are never refreshed in a running pod, so without
#    this the pod keeps the previous (expiring) tokens.
if kubectl --context "${HUB_CTX}" -n headlamp get deployment headlamp >/dev/null 2>&1; then
  kubectl --context "${HUB_CTX}" -n headlamp rollout restart deployment headlamp
  kubectl --context "${HUB_CTX}" -n headlamp rollout status deployment headlamp --timeout=120s
  echo "✔ Headlamp restarted with the refreshed kubeconfig."
fi
