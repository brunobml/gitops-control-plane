#!/usr/bin/env bash
# Phase 3 C.2 (Rec 18): identities Argo CD uses on a spoke.
#
#   argocd-manager            Argo CD's connection identity. With --reduce-manager it can only
#                             READ everything (for diffing, the resource tree and the UI) and
#                             IMPERSONATE the two deployers below; all writes happen as a deployer.
#   argocd-tenant-deployer    Impersonated for project tenant-workloads: namespaces + QueueBackedService.
#   argocd-iac-deployer       Impersonated for tenant-iac: namespaces + TeamEKSCluster.
#   argocd-platform-deployer  Impersonated for platform-catalog / platform-addons: cluster-admin (explicit).
#
# Usage: apply-argocd-spoke-rbac.sh <spoke-name> [--reduce-manager]
#   Without --reduce-manager, argocd-manager keeps its cluster-admin binding (staging step).
set -euo pipefail

spoke="${1:?usage: $0 <spoke-name> [--reduce-manager]}"
reduce="${2:-}"
context="k3d-${spoke}"

kubectl --context "$context" apply -f - <<'EOF'
apiVersion: v1
kind: ServiceAccount
metadata:
  name: argocd-manager
  namespace: kube-system
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: argocd-tenant-deployer
  namespace: kube-system
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: argocd-iac-deployer
  namespace: kube-system
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: argocd-platform-deployer
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: argocd-tenant-deployer
rules:
  # CreateNamespace=true and managedNamespaceMetadata (PSS labels)
  - apiGroups: [""]
    resources: ["namespaces"]
    verbs: ["get", "list", "watch", "create", "update", "patch"]
  # The only kind the golden chart renders
  - apiGroups: ["kro.run"]
    resources: ["queuebackedservices"]
    verbs: ["*"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: argocd-tenant-deployer
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: argocd-tenant-deployer
subjects:
  - kind: ServiceAccount
    name: argocd-tenant-deployer
    namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: argocd-iac-deployer
rules:
  - apiGroups: [""]
    resources: ["namespaces"]
    verbs: ["get", "list", "watch", "create", "update", "patch"]
  - apiGroups: ["kro.run"]
    resources: ["teameksclusters"]
    verbs: ["*"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: argocd-iac-deployer
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: argocd-iac-deployer
subjects:
  - kind: ServiceAccount
    name: argocd-iac-deployer
    namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: argocd-platform-deployer
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
  - kind: ServiceAccount
    name: argocd-platform-deployer
    namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: argocd-manager-read-impersonate
rules:
  # Read everything: needed for diffing, the live resource tree and the UI (full visibility).
  - apiGroups: ["*"]
    resources: ["*", "*/*"]
    verbs: ["get", "list", "watch"]
  - nonResourceURLs: ["*"]
    verbs: ["get"]
  # Impersonate only the deployer identities.
  - apiGroups: [""]
    resources: ["serviceaccounts"]
    verbs: ["impersonate"]
    resourceNames: ["argocd-tenant-deployer", "argocd-iac-deployer", "argocd-platform-deployer"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: argocd-manager-read-impersonate
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: argocd-manager-read-impersonate
subjects:
  - kind: ServiceAccount
    name: argocd-manager
    namespace: kube-system
EOF

if [[ "$reduce" == "--reduce-manager" ]]; then
  kubectl --context "$context" delete clusterrolebinding argocd-manager-cluster-admin --ignore-not-found
  echo "✔ ${spoke}: argocd-manager reduced to read + impersonate"
else
  kubectl --context "$context" apply -f - <<'EOF'
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
  echo "✔ ${spoke}: deployers in place; argocd-manager still cluster-admin (staging)"
fi
