#!/usr/bin/env bash
# Phase 3 B.7 pre-flight: the one documented step after `make bootstrap`. Idempotent; on a
# running lab it only acts where something is missing or stale.
#
#  0. Renew spoke/Headlamp tokens with fewer than 7 days left (Phase 5 D.2).
#  1. Discover tenant workloads from the tenant-workloads ApplicationSet (Phase 4 C.2) and wait
#     for their namespaces (CARM account annotation) and QueueBackedServices.
#  2. SSO prerequisites: restart CoreDNS when the keycloak.localhost rewrite changed (its
#     reload plugin ignores imported files), then wait for Keycloak.
#  3. Worker credentials: provision Secret <name>-<env>-aws in the namespace's owner account,
#     unless the existing Secret's key still authenticates to that account.
#  4. Restart a worker only if its running key does not match its Secret (env is read at start).
#  5. Adopt Argo CD itself: sync the manual-sync argo-cd Application if it is OutOfSync.
#  6. Re-sync any Application that is not Synced/Healthy (bootstrap ordering can exhaust retries).
#  7. Run the smoke test (includes an end-to-end order per environment).
#
# Uses its own Argo CD CLI config, so the operator's CLI session is never read or changed.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SECRET_DIR="${GITOPS_LAB_SECRET_DIR:-$HOME/.config/gitops-lab}"
E=(--endpoint-url=http://localhost:5000 --region us-east-1)
TIMEOUT_NS=600
TIMEOUT_APPS=900
RENEW_DAYS=7

ARGOCD_CFG=$(mktemp)
trap 'rm -f "$ARGOCD_CFG"' EXIT
argocd login localhost --plaintext --grpc-web --skip-test-tls --config "$ARGOCD_CFG" \
  --username platform-admin --password "$(cat "${SECRET_DIR}/argocd-platform-admin.password")" </dev/null >/dev/null
A=(argocd --config "$ARGOCD_CFG")

echo "[1/9] Credential expiry (renew when fewer than ${RENEW_DAYS} days are left)..."
# Phase 5 D.2 (owner decision O-4): tokens are renewed here, not on a calendar. Expiries come from
# monitoring/credential-expiry (written whenever a token is minted); missing data also renews.
min_exp=$(kubectl --context k3d-hub-cluster -n monitoring get configmap credential-expiry -o json 2>/dev/null \
  | jq -r '[.data // {} | to_entries[] | select(.key|test("^(argocd|headlamp)-")) | .value | tonumber] | if length >= 5 then min else 0 end' || echo 0)
days_left=$(( (${min_exp:-0} - $(date +%s)) / 86400 ))
if (( ${min_exp:-0} == 0 || days_left < RENEW_DAYS )); then
  echo "  ↻ renewing spoke and Headlamp tokens (shortest left: ${days_left} days)"
  # register-spokes.sh calls the argocd CLI; ARGOCD_OPTS points it at this script's own session.
  ARGOCD_OPTS="--config ${ARGOCD_CFG}" bash "${SCRIPT_DIR}/register-spokes.sh" | sed 's/^/  /'
  bash "${SCRIPT_DIR}/../addons/headlamp/setup-credentials.sh" | sed 's/^/  /'
else
  echo "  ✔ shortest credential lifetime left: ${days_left} days"
fi

echo "[2/9] Discovering tenant workloads (tenant-workloads registrations) and waiting for their namespaces..."
# Phase 4 C.2: workloads are whatever tenants registered, not a fixed list. Each Application of
# the tenant-workloads ApplicationSet names a spoke and namespace; the namespace's
# QueueBackedService gives the app name and environment (Secret <name>-<env>-aws).
t0=$(date +%s); targets=""; stable=0
while :; do
  now=$(kubectl --context k3d-hub-cluster -n argocd get applications -o json | jq -r \
    '[.items[] | select(any(.metadata.ownerReferences[]?; .name=="tenant-workloads")) | "\(.spec.destination.name):\(.spec.destination.namespace)"] | sort | join(" ")')
  if [[ -n "$now" && "$now" == "$targets" ]]; then stable=$((stable + 1)); else stable=0; targets=$now; fi
  (( stable >= 2 )) && break
  (( $(date +%s) - t0 > TIMEOUT_NS )) && { echo "✘ no tenant-workloads Applications after ${TIMEOUT_NS}s" >&2; exit 1; }
  sleep 5
done
WORKLOADS=()   # spoke:namespace:app-name:env
for t in $targets; do
  IFS=: read -r spoke ns <<<"$t"
  until [[ -n "$(kubectl --context "k3d-${spoke}" get ns "$ns" -o jsonpath='{.metadata.annotations.services\.k8s\.aws/owner-account-id}' 2>/dev/null)" ]] \
        && [[ -n "$(kubectl --context "k3d-${spoke}" -n "$ns" get queuebackedservice -o name 2>/dev/null)" ]]; do
    (( $(date +%s) - t0 > TIMEOUT_NS )) && { echo "✘ namespace ${ns} on ${spoke} not ready after ${TIMEOUT_NS}s" >&2; exit 1; }
    sleep 5
  done
  while read -r name env; do
    WORKLOADS+=("${spoke}:${ns}:${name}:${env}")
    echo "  ✔ ${spoke}/${ns} (${name}, ${env})"
  done < <(kubectl --context "k3d-${spoke}" -n "$ns" get queuebackedservice -o json | jq -r '.items[] | "\(.spec.name) \(.spec.environment)"')
done

echo "[3/9] SSO prerequisites (CoreDNS *.localhost, Keycloak, lab TLS certificate)..."
H=(kubectl --context k3d-hub-cluster)
t0=$(date +%s)
until "${H[@]}" -n kube-system get cm coredns-custom >/dev/null 2>&1; do
  (( $(date +%s) - t0 > TIMEOUT_NS )) && { echo "✘ coredns-custom not created by addon-keycloak after ${TIMEOUT_NS}s" >&2; exit 1; }
  sleep 5
done
want=$("${H[@]}" -n kube-system get cm coredns-custom -o json | jq -cS .data | sha256sum | cut -c1-16)
have=$("${H[@]}" -n kube-system get deploy coredns -o jsonpath='{.spec.template.metadata.annotations.lab/coredns-custom-hash}')
if [[ "$want" != "$have" ]]; then
  "${H[@]}" -n kube-system patch deploy coredns --type merge \
    -p "{\"spec\":{\"template\":{\"metadata\":{\"annotations\":{\"lab/coredns-custom-hash\":\"${want}\"}}}}}" >/dev/null
  "${H[@]}" -n kube-system rollout status deploy/coredns --timeout=180s >/dev/null
  echo "  ↻ CoreDNS restarted for coredns-custom ${want}"
else
  echo "  ✔ CoreDNS already serves coredns-custom ${want}"
fi
until "${H[@]}" -n keycloak get deploy keycloak >/dev/null 2>&1; do
  (( $(date +%s) - t0 > TIMEOUT_NS )) && { echo "✘ Keycloak not deployed after ${TIMEOUT_NS}s" >&2; exit 1; }
  sleep 5
done
"${H[@]}" -n keycloak rollout status deploy/keycloak --timeout=600s >/dev/null
echo "  ✔ Keycloak Ready (issuer $(curl -s http://keycloak.localhost/realms/lab/.well-known/openid-configuration | jq -r .issuer))"
# Track I.4: lab certificate for https://*.localhost (mkcert if available, else self-signed;
# renewed when fewer than 30 days are left).
bash "${SCRIPT_DIR}/setup-local-tls.sh" | sed 's/^/  /'

echo "[4/9] Worker credentials..."
declare -A PROVISIONED=()
for w in "${WORKLOADS[@]}"; do
  IFS=: read -r spoke ns name env <<<"$w"
  account=$(kubectl --context "k3d-${spoke}" get ns "$ns" -o jsonpath='{.metadata.annotations.services\.k8s\.aws/owner-account-id}')
  secret="${name}-${env}-aws"
  valid=""
  if kubectl --context "k3d-${spoke}" -n "$ns" get secret "$secret" >/dev/null 2>&1; then
    akid=$(kubectl --context "k3d-${spoke}" -n "$ns" get secret "$secret" -o jsonpath='{.data.AWS_ACCESS_KEY_ID}' | base64 -d)
    sak=$(kubectl --context "k3d-${spoke}" -n "$ns" get secret "$secret" -o jsonpath='{.data.AWS_SECRET_ACCESS_KEY}' | base64 -d)
    got=$(AWS_ACCESS_KEY_ID="$akid" AWS_SECRET_ACCESS_KEY="$sak" aws "${E[@]}" sts get-caller-identity --query Account --output text 2>/dev/null || true)
    unset akid sak
    [[ "$got" == "$account" ]] && valid=yes
  fi
  if [[ -n "$valid" ]]; then
    echo "  ✔ ${ns}: ${secret} valid for account ${account} (kept)"
  else
    bash "${SCRIPT_DIR}/provision-worker-credentials.sh" "$spoke" "$ns" "$name" "$env" "$account" | sed 's/^/  /'
    PROVISIONED["$ns"]=1
  fi
done

echo "[5/9] Workers running with their Secret's key..."
for w in "${WORKLOADS[@]}"; do
  IFS=: read -r spoke ns name env <<<"$w"
  K=(kubectl --context "k3d-${spoke}" -n "$ns")
  want=$("${K[@]}" get secret "${name}-${env}-aws" -o jsonpath='{.data.AWS_ACCESS_KEY_ID}' | base64 -d)
  for pod in $("${K[@]}" get pods -l "app=${name}-${env}-worker" --field-selector=status.phase=Running -o jsonpath='{.items[*].metadata.name}'); do
    have=$("${K[@]}" exec "$pod" -- sh -c 'printf %s "${AWS_ACCESS_KEY_ID:-}"' 2>/dev/null || true)
    if [[ "$have" != "$want" || -n "${PROVISIONED[$ns]:-}" ]]; then
      # One pod at a time so multi-replica workloads (prod, PDB minAvailable 1) keep serving.
      "${K[@]}" delete pod "$pod" --wait=false >/dev/null
      t1=$(date +%s)
      until [[ $("${K[@]}" get pods -l "app=${name}-${env}-worker" -o json \
          | jq '[.items[]|select(.metadata.deletionTimestamp==null and .status.phase=="Running" and ([.status.containerStatuses[]?.ready]|all))]|length') \
          -ge $("${K[@]}" get deploy "${name}-${env}-worker" -o jsonpath='{.spec.replicas}') ]]; do
        (( $(date +%s) - t1 > 180 )) && { echo "✘ ${ns}: worker not Ready after restart" >&2; exit 1; }
        sleep 3
      done
      echo "  ↻ ${ns}: restarted ${pod}"
    fi
  done
  echo "  ✔ ${ns}: workers use ${name}-${env}-aws"
  unset want have
done

echo "[6/9] Orphans of deregistered tenant apps (owner decision O-3)..."
bash "${SCRIPT_DIR}/orphans.sh" | sed 's/^/  /'

echo "[7/9] Argo CD self-management (argo-cd Application, manual sync by design)..."
if [[ "$("${A[@]}" app get argo-cd -o json | jq -r .status.sync.status)" != "Synced" ]]; then
  "${A[@]}" app sync argo-cd --timeout 300 >/dev/null
  "${A[@]}" app wait argo-cd --health --sync --timeout 300 >/dev/null
  echo "  ✔ argo-cd synced (adopted)"
else
  echo "  ✔ argo-cd already Synced"
fi

echo "[8/9] All Applications Synced/Healthy..."
t0=$(date +%s)
while :; do
  bad=$(kubectl --context k3d-hub-cluster -n argocd get applications -o json \
    | jq -r '.items[]|select(.status.sync.status!="Synced" or .status.health.status!="Healthy")|.metadata.name')
  [[ -z "$bad" ]] && { echo "  ✔ all Applications Synced/Healthy"; break; }
  (( $(date +%s) - t0 > TIMEOUT_APPS )) && { echo "✘ still not Synced/Healthy: $(echo $bad)" >&2; exit 1; }
  for app in $bad; do
    phase=$("${A[@]}" app get "$app" -o json | jq -r '.status.operationState.phase // ""')
    [[ "$phase" == "Running" ]] || "${A[@]}" app sync "$app" --timeout 120 >/dev/null 2>&1 || true
  done
  sleep 15
done

echo "[9/9] Smoke test..."
bash "${SCRIPT_DIR}/smoke-test-hub-spoke.sh"
