#!/usr/bin/env bash
# Phase 3 C.2 rollback: disable sync impersonation and restore cluster-admin for argocd-manager
# on the spokes. Break-glass: uses kubectl only (works even if Argo CD syncs are failing).
# Follow up by setting application.sync.impersonation.enabled back to "false" in
# clusters/values-argocd-hub.yaml, or the next Helm upgrade re-enables it.
set -euo pipefail

kubectl --context k3d-hub-cluster -n argocd patch configmap argocd-cm --type merge \
  -p '{"data":{"application.sync.impersonation.enabled":"false"}}'
echo "✔ impersonation disabled in argocd-cm"

for spoke in spoke-nonprod spoke-prod; do
  bash "$(dirname "${BASH_SOURCE[0]}")/apply-argocd-spoke-rbac.sh" "$spoke"
done
echo "✔ argocd-manager has cluster-admin again on both spokes"
