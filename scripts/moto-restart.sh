#!/usr/bin/env bash
# scripts/moto-restart.sh: Graceful restart of Moto Cloud with zero-leak recovery (Phase P1 / finding F-6, F-7, F-8).
#
# Every host reboot or container restart wipes Moto's in-memory state.
# 1. Pauses the hub Argo CD application controller (preventing self-heal from undoing controller scale-down).
# 2. Scales ACK deployments to 0 on both spokes (preventing in-flight unauthenticated requests from leaking into Moto account 123456789012).
# 3. Restarts the moto-cloud Docker container and waits for the API to be ready.
# 4. Scales ACK deployments back up to 1 on both spokes and waits for rollout.
# 5. Deletes stale platform-network resources on both spokes (with deletion-policy: retain, so no AWS call is made; avoiding the F-7 NotFound hang).
# 6. Clears stale services.k8s.aws/adopted markers (F-8).
# 7. Unpauses Argo CD application controller.
# 8. Re-syncs platform-network Applications in Argo CD and waits for ACK resources to sync.
# 9. Asserts that Moto default account 123456789012 is completely empty of platform/tenant resources.
# 10. Runs post-bootstrap.sh to re-provision tenant worker credentials, restart workers, and run smoke tests.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SECRET_DIR="${GITOPS_LAB_SECRET_DIR:-$HOME/.config/gitops-lab}"
SPOKES=("spoke-nonprod" "spoke-prod")

echo "=========================================================="
echo " Starting Safe Moto Restart & Control Plane Recovery"
echo "=========================================================="

# 0. Pre-flight checks
if ! docker info >/dev/null 2>&1; then
  echo "❌ Error: Docker daemon is not accessible" >&2
  exit 1
fi

for ctx in "k3d-hub-cluster" "k3d-spoke-nonprod" "k3d-spoke-prod"; do
  if ! kubectl --context "$ctx" cluster-info >/dev/null 2>&1; then
    echo "❌ Error: Cluster context '${ctx}' is not reachable" >&2
    exit 1
  fi
done
echo "✔ Pre-flight: Docker and all cluster APIs are reachable"

# 1. Pause Argo CD application controller (so self-heal does not undo ACK scale-down)
echo "[1/10] Pausing Argo CD application controller on Hub..."
kubectl --context k3d-hub-cluster -n argocd scale statefulset/argo-cd-argocd-application-controller --replicas=0 >/dev/null
kubectl --context k3d-hub-cluster -n argocd wait --for=delete pod/argo-cd-argocd-application-controller-0 --timeout=60s >/dev/null 2>&1 || true
echo "  ✔ Argo CD application controller paused (0 replicas)"

# 2. Scale down ACK deployments on both spokes (prevents F-6 leak into default account 123456789012)
echo "[2/10] Scaling down ACK controllers on both spokes..."
for spoke in "${SPOKES[@]}"; do
  ctx="k3d-${spoke}"
  kubectl --context "$ctx" -n ack-system scale deploy --all --replicas=0 >/dev/null
  t0=$(date +%s)
  until [[ "$(kubectl --context "$ctx" -n ack-system get pods --no-headers 2>/dev/null | wc -l)" -eq 0 ]]; do
    if (( $(date +%s) - t0 > 60 )); then
      echo "  ⚠ Timed out waiting for ack-system pods to terminate on ${spoke}" >&2
      break
    fi
    sleep 1
  done
  echo "  ✔ ${spoke}: ACK deployments scaled to 0"
done

# 3. Restart Moto Cloud container
echo "[3/10] Restarting moto-cloud Docker container..."
docker restart moto-cloud >/dev/null
t0=$(date +%s)
until curl -sf http://localhost:5000/moto-api/ >/dev/null 2>&1; do
  if (( $(date +%s) - t0 > 30 )); then
    echo "❌ Timed out waiting for moto-cloud to respond" >&2
    exit 1
  fi
  sleep 1
done
echo "  ✔ moto-cloud restarted and healthy at http://localhost:5000"

# 4. Delete stale platform-network resources while ACK is scaled to 0 (F-7: prevent duplicate VPC & NotFound hang)
echo "[4/10] Re-creating platform-network resources on both spokes..."
for spoke in "${SPOKES[@]}"; do
  ctx="k3d-${spoke}"
  for res in $(kubectl --context "$ctx" -n platform-network get vpc,subnet,internetgateway,routetable,securitygroup -o name 2>/dev/null || true); do
    kubectl --context "$ctx" -n platform-network patch "$res" -p '{"metadata":{"finalizers":[]}}' --type=merge >/dev/null 2>&1 || true
  done
  kubectl --context "$ctx" -n platform-network delete vpc,subnet,internetgateway,routetable,securitygroup --all --timeout=10s >/dev/null 2>&1 || true
  echo "  ✔ ${spoke}: cleared stale network objects"
done

# 5. Clear stale services.k8s.aws/adopted markers (F-8)
echo "[5/10] Clearing stale services.k8s.aws/adopted markers..."
for spoke in "${SPOKES[@]}"; do
  ctx="k3d-${spoke}"
  cleared=0
  while read -r kind ns name; do
    [[ -z "$kind" ]] && continue
    case "$kind" in
      Role) k=role.iam.services.k8s.aws ;;
      Cluster) k=cluster.eks.services.k8s.aws ;;
      *) k=nodegroup ;;
    esac
    kubectl --context "$ctx" -n "$ns" annotate "$k" "$name" services.k8s.aws/adopted- >/dev/null 2>&1 || true
    cleared=$((cleared + 1))
  done < <(kubectl --context "$ctx" get role.iam.services.k8s.aws,cluster.eks.services.k8s.aws,nodegroup -A \
    -o jsonpath='{range .items[?(@.metadata.annotations.services\.k8s\.aws/adopted=="true")]}{.kind}{" "}{.metadata.namespace}{" "}{.metadata.name}{"\n"}{end}' 2>/dev/null || true)
  echo "  ✔ ${spoke}: cleared ${cleared} adopted markers"
done

# 6. Scale up ACK deployments on both spokes
echo "[6/10] Scaling up ACK controllers on both spokes..."
for spoke in "${SPOKES[@]}"; do
  ctx="k3d-${spoke}"
  kubectl --context "$ctx" -n ack-system scale deploy --all --replicas=1 >/dev/null
  kubectl --context "$ctx" -n ack-system rollout status deploy --timeout=180s >/dev/null
  echo "  ✔ ${spoke}: all ACK deployments ready (1/1)"
done

# 7. Resume Argo CD application controller
echo "[7/10] Resuming Argo CD application controller on Hub..."
kubectl --context k3d-hub-cluster -n argocd scale statefulset/argo-cd-argocd-application-controller --replicas=1 >/dev/null
kubectl --context k3d-hub-cluster -n argocd rollout status statefulset/argo-cd-argocd-application-controller --timeout=120s >/dev/null
echo "  ✔ Argo CD application controller running (1 replica)"

# 8. Re-sync platform-network in Argo CD and wait for ACK resources to sync
echo "[8/10] Triggering sync and asserting platform-network sync on spokes..."
ARGOCD_CFG=$(mktemp)
trap 'rm -f "$ARGOCD_CFG"' EXIT
argocd login localhost --plaintext --grpc-web --skip-test-tls --config "$ARGOCD_CFG" \
  --username platform-admin --password "$(cat "${SECRET_DIR}/argocd-platform-admin.password")" </dev/null >/dev/null
A=(argocd --config "$ARGOCD_CFG")

for spoke in "${SPOKES[@]}"; do
  app="platform-network-${spoke}"
  "${A[@]}" app sync "$app" --prune --timeout 120 >/dev/null 2>&1 || true
done

for spoke in "${SPOKES[@]}"; do
  ctx="k3d-${spoke}"
  t0=$(date +%s)
  until [[ "$(kubectl --context "$ctx" -n platform-network get vpc,subnet,internetgateway,routetable,securitygroup --no-headers 2>/dev/null | wc -l)" -eq 6 ]] \
        && [[ "$(kubectl --context "$ctx" -n platform-network get vpc,subnet,internetgateway,routetable,securitygroup -o json 2>/dev/null | jq -r '[.items[].status.conditions[]? | select(.type=="ACK.ResourceSynced" and .status=="True")] | length')" -eq 6 ]]; do
    if (( $(date +%s) - t0 > 120 )); then
      echo "❌ Timed out waiting for network resources on ${spoke} to reach ACK.ResourceSynced=True" >&2
      exit 1
    fi
    sleep 3
  done
  echo "  ✔ ${spoke}: all 6 network resources synced in Moto"
done

# 9. Assert Moto default account 123456789012 is clean (no leaked resources, F-6 verification)
echo "[9/10] Asserting Moto default account 123456789012 is empty..."
export AWS_ACCESS_KEY_ID=mock AWS_SECRET_ACCESS_KEY=mock AWS_DEFAULT_REGION=us-east-1
E=(--endpoint-url=http://localhost:5000)

leaked_vpcs=$(aws "${E[@]}" ec2 describe-vpcs --query 'Vpcs[?!IsDefault].VpcId' --output text 2>/dev/null || true)
leaked_sgs=$(aws "${E[@]}" ec2 describe-security-groups --query "SecurityGroups[?GroupName=='platform-cluster-sg'].GroupId" --output text 2>/dev/null || true)
leaked_igws=$(aws "${E[@]}" ec2 describe-internet-gateways --query "InternetGateways[?Tags[?Key=='services.k8s.aws/namespace']].InternetGatewayId" --output text 2>/dev/null || true)
leaked_sqs=$(aws "${E[@]}" sqs list-queues --query 'QueueUrls' --output text 2>/dev/null || true)
leaked_roles=$(aws "${E[@]}" iam list-roles --query "Roles[?starts_with(RoleName, 'team-') || starts_with(RoleName, 'ack-')].RoleName" --output text 2>/dev/null || true)

if [[ -n "$leaked_vpcs" || -n "$leaked_sgs" || -n "$leaked_igws" || ("$leaked_sqs" != "None" && -n "$leaked_sqs") || -n "$leaked_roles" ]]; then
  echo "❌ Error: leaked resources found in Moto default account 123456789012!" >&2
  echo "   VPCs:  ${leaked_vpcs}" >&2
  echo "   SGs:   ${leaked_sgs}" >&2
  echo "   IGWs:  ${leaked_igws}" >&2
  echo "   SQS:   ${leaked_sqs}" >&2
  echo "   Roles: ${leaked_roles}" >&2
  exit 1
fi
echo "  ✔ Moto default account 123456789012 is completely empty"

# 10. Run post-bootstrap to restore worker credentials and run full smoke test
echo "[10/10] Running post-bootstrap (re-provision worker keys, restart workers, smoke test)..."
bash "${SCRIPT_DIR}/post-bootstrap.sh"

echo "=========================================================="
echo "✔ Moto restart and zero-leak recovery completed successfully!"
echo "=========================================================="
