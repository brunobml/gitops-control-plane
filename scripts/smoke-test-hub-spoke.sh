#!/usr/bin/env bash
set -euo pipefail

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}============================================================${NC}"
echo -e "${BLUE}  Multi-Cluster Hub-and-Spoke Smoke Test                   ${NC}"
echo -e "${BLUE}============================================================${NC}"

# 1. Central Moto Cloud
echo -e "\n${YELLOW}[1/12] Checking Central Mock AWS Cloud (moto-cloud)...${NC}"
if curl -s -f http://localhost:5000/moto-api/ > /dev/null; then
  echo -e "${GREEN}✔ moto-cloud is responding at http://localhost:5000${NC}"
else
  echo -e "${RED}✘ moto-cloud is unreachable at http://localhost:5000${NC}"
  exit 1
fi

# 2. Hub Cluster & Argo CD Core Pods
echo -e "\n${YELLOW}[2/12] Checking Hub Cluster & Argo CD...${NC}"
kubectl --context k3d-hub-cluster get nodes > /dev/null
echo -e "${GREEN}✔ Hub cluster API is reachable${NC}"

# Completed hook/Job pods (phase Succeeded, e.g. redis-secret-init after an argo-cd sync) are expected.
ARGOCD_PODS=$(kubectl --context k3d-hub-cluster -n argocd get pods --field-selector=status.phase!=Succeeded --no-headers | awk '{print $3}')
if echo "$ARGOCD_PODS" | grep -qv "Running"; then
  echo -e "${RED}✘ Not all Argo CD pods are Running:${NC}"
  kubectl --context k3d-hub-cluster -n argocd get pods
  exit 1
fi
echo -e "${GREEN}✔ All Argo CD core pods are Running${NC}"

CLUSTERS=$(kubectl --context k3d-hub-cluster -n argocd get secrets -l argocd.argoproj.io/secret-type=cluster -o jsonpath='{.items[*].metadata.name}')
echo -e "  Registered clusters in Hub Argo CD: ${CLUSTERS}"
if [[ "$CLUSTERS" == *"spoke-nonprod"* && "$CLUSTERS" == *"spoke-prod"* ]]; then
  echo -e "${GREEN}✔ Both spoke-nonprod and spoke-prod clusters are registered${NC}"
else
  echo -e "${RED}✘ Missing spoke registrations!${NC}"
  exit 1
fi

# 3. Argo CD Applications Health & Sync State (L3-4, C-2)
EXPECTED_APPS=("argo-cd" "addon-headlamp" "addon-keycloak" "addon-oauth2-proxy" "addon-kyverno-spoke-nonprod" "addon-kyverno-spoke-prod" "addon-prometheus" "addon-grafana" "addon-blackbox" "addon-lab-exporters" "addon-observability-spoke-nonprod" "addon-observability-spoke-prod" "addon-loki" "addon-alloy" "addon-logging-spoke-nonprod" "addon-logging-spoke-prod" "addon-platform-config-spoke-nonprod" "addon-platform-config-spoke-prod" "addon-traefik" "platform-projects" "addon-kro-spoke-nonprod" "addon-kro-spoke-prod" "addon-ack-sqs-spoke-nonprod" "addon-ack-sqs-spoke-prod" "addon-ack-ec2-spoke-nonprod" "addon-ack-ec2-spoke-prod" "addon-ack-iam-spoke-nonprod" "addon-ack-iam-spoke-prod" "addon-ack-eks-spoke-nonprod" "addon-ack-eks-spoke-prod" "addon-ack-credentials-spoke-nonprod" "addon-ack-credentials-spoke-prod" "platform-network-spoke-nonprod" "platform-network-spoke-prod" "kro-blueprints-spoke-nonprod" "kro-blueprints-spoke-prod" "orders-dev" "orders-test" "orders-prod" "team-data-analytics-dev" "team-data-analytics-prod" "root-control-plane")
APP_DATA=$(kubectl --context k3d-hub-cluster -n argocd get applications -o jsonpath='{range .items[*]}{.metadata.name}:{.status.sync.status}:{.status.health.status}{"\n"}{end}')

for expected in "${EXPECTED_APPS[@]}"; do
  app_entry=$(echo "$APP_DATA" | grep "^${expected}:" || true)
  if [[ -z "$app_entry" ]]; then
    echo -e "${RED}✘ Expected Application '${expected}' not found in Argo CD!${NC}"
    exit 1
  fi
  sync_stat=$(echo "$app_entry" | cut -d':' -f2)
  health_stat=$(echo "$app_entry" | cut -d':' -f3)

  if [[ "$sync_stat" != "Synced" || "$health_stat" != "Healthy" ]]; then
    echo -e "${RED}✘ Application '${expected}' is not healthy! (Sync: ${sync_stat}, Health: ${health_stat})${NC}"
    exit 1
  fi
  echo -e "  Application ${expected}: ${GREEN}${sync_stat} / ${health_stat}${NC}"
done

# Also ensure no application in Argo CD is degraded or out of sync
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  app_name=$(echo "$line" | cut -d':' -f1)
  sync_stat=$(echo "$line" | cut -d':' -f2)
  health_stat=$(echo "$line" | cut -d':' -f3)
  if [[ "$sync_stat" != "Synced" || "$health_stat" != "Healthy" ]]; then
    echo -e "${RED}✘ Application '${app_name}' is in unexpected state: Sync=${sync_stat}, Health=${health_stat}${NC}"
    exit 1
  fi
done <<< "$APP_DATA"
echo -e "${GREEN}✔ All Argo CD applications are Synced and Healthy${NC}"

# 4. Spoke Controllers (Kro + ACK)
echo -e "\n${YELLOW}[4/12] Checking Spoke Controllers (Kro + ACK)...${NC}"
for ctx in "k3d-spoke-nonprod" "k3d-spoke-prod"; do
  kubectl --context "$ctx" get nodes > /dev/null
  echo -e "${GREEN}✔ ${ctx} API is reachable${NC}"

  kubectl --context "$ctx" -n ack-system wait --for=condition=ready --timeout=30s pod -l app.kubernetes.io/name=sqs-chart >/dev/null
  echo -e "${GREEN}✔ ACK SQS controller is ready on ${ctx}${NC}"

  kubectl --context "$ctx" -n kro wait --for=condition=ready --timeout=30s pod -l app.kubernetes.io/name=kro >/dev/null
  echo -e "${GREEN}✔ Kro controller is ready on ${ctx}${NC}"
done

# 5. Kro Custom Resources State
echo -e "\n${YELLOW}[5/12] Asserting QueueBackedService Resource Status...${NC}"
for spoke_ns in "k3d-spoke-nonprod:orders-dev" "k3d-spoke-nonprod:orders-test" "k3d-spoke-prod:orders-prod"; do
  ctx="${spoke_ns%%:*}"
  ns="${spoke_ns##*:}"
  qbs_state=$(kubectl --context "$ctx" -n "$ns" get queuebackedservice orders -o jsonpath='{.status.state}' 2>/dev/null || echo "MISSING")
  if [[ "$qbs_state" != "ACTIVE" ]]; then
    echo -e "${RED}✘ QueueBackedService in ${ctx}/${ns} is not ACTIVE (state: ${qbs_state})${NC}"
    exit 1
  fi
  echo -e "  ${ctx}/${ns} QueueBackedService: ${GREEN}ACTIVE${NC}"
done
echo -e "${GREEN}✔ All QueueBackedService instances are ACTIVE${NC}"

# 6. SQS Queues in Central Mock AWS Cloud (L3-4, C-2)
echo -e "\n${YELLOW}[6/12] Asserting AWS Cloud SQS Queues & DLQs...${NC}"
# Phase 3 D.3 (CARM): each workload namespace may live in its own cloud account
# (namespace annotation services.k8s.aws/owner-account-id; default 123456789012).
# List queues *in that account* by assuming a role there in moto.
list_queues_in_account() {
  local account="$1" creds
  creds=$(AWS_ACCESS_KEY_ID=mock-key AWS_SECRET_ACCESS_KEY=mock-secret aws --endpoint-url=http://localhost:5000 --region us-east-1 \
    sts assume-role --role-arn "arn:aws:iam::${account}:role/smoke-test" --role-session-name smoke-test \
    --query Credentials --output json 2>/dev/null) || { echo "{}"; return; }
  AWS_ACCESS_KEY_ID=$(jq -r .AccessKeyId <<<"$creds") AWS_SECRET_ACCESS_KEY=$(jq -r .SecretAccessKey <<<"$creds") \
    AWS_SESSION_TOKEN=$(jq -r .SessionToken <<<"$creds") \
    aws --endpoint-url=http://localhost:5000 --region us-east-1 sqs list-queues --output json 2>/dev/null || echo "{}"
}

for pair in "k3d-spoke-nonprod:orders-dev" "k3d-spoke-nonprod:orders-test" "k3d-spoke-prod:orders-prod"; do
  ctx="${pair%%:*}"; ns="${pair##*:}"
  account=$(kubectl --context "$ctx" get namespace "$ns" -o jsonpath='{.metadata.annotations.services\.k8s\.aws/owner-account-id}' 2>/dev/null)
  account="${account:-123456789012}"
  QUEUES_OUTPUT=$(list_queues_in_account "$account")
  for qname in "${ns}-queue" "${ns}-dlq"; do
    if ! echo "$QUEUES_OUTPUT" | grep -q "/${account}/${qname}\""; then
      echo -e "${RED}✘ Missing expected SQS queue ${qname} in account ${account} (namespace ${ns})${NC}"
      exit 1
    fi
    echo -e "  Queue: ${GREEN}${qname}${NC} present in account ${account}"
  done
done
echo -e "${GREEN}✔ All 6 expected SQS queues (3 queues + 3 DLQs) verified in Moto Cloud${NC}"

# 7. GitOps Workload Pods (L3-4, C-2)
echo -e "\n${YELLOW}[7/12] Asserting Workload Pods...${NC}"
DEV_PODS=$(kubectl --context k3d-spoke-nonprod -n orders-dev get pods --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' ')
TEST_PODS=$(kubectl --context k3d-spoke-nonprod -n orders-test get pods --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' ')
PROD_PODS=$(kubectl --context k3d-spoke-prod -n orders-prod get pods --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' ')

echo -e "  orders-dev pods on spoke-nonprod:  ${DEV_PODS} (expected: 1)"
echo -e "  orders-test pods on spoke-nonprod: ${TEST_PODS} (expected: 1)"
echo -e "  orders-prod pods on spoke-prod:    ${PROD_PODS} (expected: 2)"

if [[ "$DEV_PODS" -lt 1 || "$TEST_PODS" -lt 1 || "$PROD_PODS" -lt 2 ]]; then
  echo -e "${RED}✘ Insufficient running pods across spokes!${NC}"
  exit 1
fi
echo -e "${GREEN}✔ All orders workloads running across non-prod and prod spokes!${NC}"

# 8. Credential expiry (Phase 3 Step 0.2). Reads the JWT exp claim only; tokens are never printed.
#    Checks the Argo CD cluster Secrets, the Headlamp kubeconfig Secret, and the kubeconfig actually
#    mounted in the running Headlamp pod (a subPath mount does not refresh, so this catches a missed restart).
#    WARN when fewer than TOKEN_WARN_DAYS remain; FAIL when expired.
#    SMOKE_NOW_EPOCH overrides "now" (for negative testing only).
echo -e "\n${YELLOW}[8/12] Asserting Credential Expiry...${NC}"
TOKEN_WARN_DAYS="${TOKEN_WARN_DAYS:-7}"
NOW_EPOCH="${SMOKE_NOW_EPOCH:-$(date +%s)}"

jwt_exp_from_cluster_secret() {
  kubectl --context k3d-hub-cluster -n argocd get secret "$1" -o jsonpath='{.data.config}' \
    | base64 -d | jq -r '.bearerToken' \
    | python3 -c 'import sys,json,base64; p=sys.stdin.read().strip().split(".")[1]; p+="="*(-len(p)%4); print(json.loads(base64.urlsafe_b64decode(p))["exp"])'
}

kubeconfig_exps() {
  # stdin: kubeconfig YAML; stdout: "<user> <exp>" per user
  python3 -c 'import sys,yaml,json,base64
k=yaml.safe_load(sys.stdin)
for u in k["users"]:
    p=u["user"]["token"].split(".")[1]; p+="="*(-len(p)%4)
    print(u["name"], json.loads(base64.urlsafe_b64decode(p))["exp"])'
}

EXPIRY_ROWS=""
for s in cluster-spoke-nonprod cluster-spoke-prod; do
  EXPIRY_ROWS+="argocd/${s} $(jwt_exp_from_cluster_secret "$s")"$'\n'
done
while read -r user exp; do
  EXPIRY_ROWS+="headlamp-secret/${user} ${exp}"$'\n'
done < <(kubectl --context k3d-hub-cluster -n headlamp get secret headlamp-kubeconfig -o jsonpath='{.data.config}' | base64 -d | kubeconfig_exps)
HEADLAMP_POD=$(kubectl --context k3d-hub-cluster -n headlamp get pods -l app.kubernetes.io/name=headlamp \
  --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [[ -n "$HEADLAMP_POD" ]]; then
  while read -r user exp; do
    EXPIRY_ROWS+="headlamp-pod/${user} ${exp}"$'\n'
  done < <(kubectl --context k3d-hub-cluster -n headlamp exec "$HEADLAMP_POD" -- cat /home/headlamp/.kube/config | kubeconfig_exps)
else
  echo -e "${RED}✘ No running Headlamp pod found to inspect its mounted kubeconfig${NC}"
  exit 1
fi

EXPIRY_FAILED=0
EXPIRY_WARNED=0
while read -r name exp; do
  [[ -z "$name" ]] && continue
  remaining=$(( exp - NOW_EPOCH ))
  days=$(( remaining / 86400 ))
  expires_at=$(date -u -d "@${exp}" +%FT%TZ)
  if (( remaining <= 0 )); then
    echo -e "  ${RED}✘ ${name}: EXPIRED (${expires_at})${NC}"
    EXPIRY_FAILED=1
  elif (( days < TOKEN_WARN_DAYS )); then
    echo -e "  ${YELLOW}⚠ ${name}: ${days}d left (${expires_at}); run 'make rotate-spoke-tokens'${NC}"
    EXPIRY_WARNED=1
  else
    echo -e "  ${name}: ${days}d left (${expires_at})"
  fi
done <<< "$EXPIRY_ROWS"

if (( EXPIRY_FAILED )); then
  echo -e "${RED}✘ One or more credentials have expired. Run 'make rotate-spoke-tokens'.${NC}"
  exit 1
fi
if (( EXPIRY_WARNED )); then
  echo -e "${YELLOW}⚠ Credentials expire within ${TOKEN_WARN_DAYS} days. Rotate soon.${NC}"
else
  echo -e "${GREEN}✔ All cluster and Headlamp credentials valid for at least ${TOKEN_WARN_DAYS} days${NC}"
fi

# 9. End-to-end message flow per environment (Phase 3 B.7 pre-flight). Sends an order from the
#    namespace's own cloud account and requires it on the dashboard: catches workers that run
#    but cannot consume (missing/stale credentials, NetworkPolicy/moto subnet mismatch, ...).
echo -e "\n${YELLOW}[9/12] Asserting End-to-End Order Flow...${NC}"
for triple in "k3d-spoke-nonprod:orders-dev:8081" "k3d-spoke-nonprod:orders-test:8081" "k3d-spoke-prod:orders-prod:8082"; do
  IFS=: read -r ctx ns port <<<"$triple"
  account=$(kubectl --context "$ctx" get namespace "$ns" -o jsonpath='{.metadata.annotations.services\.k8s\.aws/owner-account-id}' 2>/dev/null)
  account="${account:-123456789012}"
  creds=$(AWS_ACCESS_KEY_ID=mock-key AWS_SECRET_ACCESS_KEY=mock-secret aws --endpoint-url=http://localhost:5000 --region us-east-1 \
    sts assume-role --role-arn "arn:aws:iam::${account}:role/smoke-test" --role-session-name smoke-e2e --query Credentials --output json)
  marker="smoke-e2e-${ns}-$(date +%s)"
  AWS_ACCESS_KEY_ID=$(jq -r .AccessKeyId <<<"$creds") AWS_SECRET_ACCESS_KEY=$(jq -r .SecretAccessKey <<<"$creds") \
    AWS_SESSION_TOKEN=$(jq -r .SessionToken <<<"$creds") \
    aws --endpoint-url=http://localhost:5000 --region us-east-1 sqs send-message \
    --queue-url "http://localhost:5000/${account}/${ns}-queue" --message-body "$marker" >/dev/null
  unset creds
  t0=$(date +%s)
  until curl -s "http://${ns}.localhost:${port}/" | grep -q "$marker"; do
    if (( $(date +%s) - t0 > 60 )); then
      echo -e "${RED}✘ ${ns}: order ${marker} sent in account ${account} was not processed within 60s${NC}"
      exit 1
    fi
    sleep 2
  done
  echo -e "  ${ns}: order from account ${account} processed in $(( $(date +%s) - t0 ))s"
done
echo -e "${GREEN}✔ Orders flow end-to-end in every environment${NC}"

echo -e "\n${YELLOW}[10/12] Asserting Single Sign-On (Keycloak, Argo CD, Headlamp)...${NC}"
ISSUER="http://keycloak.localhost/realms/lab"
host_iss=$(curl -s "${ISSUER}/.well-known/openid-configuration" | jq -r .issuer 2>/dev/null || true)
# In-cluster path (CoreDNS *.localhost -> Traefik, Track I.1), from the argocd-server pod itself.
pod_iss=$(kubectl --context k3d-hub-cluster -n argocd exec deploy/argo-cd-argocd-server -- bash -c \
  'exec 3<>/dev/tcp/keycloak.localhost/80; printf "GET /realms/lab/.well-known/openid-configuration HTTP/1.0\r\nHost: keycloak.localhost\r\n\r\n" >&3; cat <&3' 2>/dev/null \
  | grep -o '"issuer":"[^"]*"' | cut -d'"' -f4 || true)
if [[ "$host_iss" != "$ISSUER" || "$pod_iss" != "$ISSUER" ]]; then
  echo -e "${RED}✘ OIDC issuer mismatch: host='${host_iss}' argocd-server='${pod_iss}' expected='${ISSUER}'${NC}"
  exit 1
fi
echo -e "${GREEN}✔ Issuer identical from host and from argocd-server: ${ISSUER}${NC}"
settings=$(curl -s http://localhost/api/v1/settings)
if [[ "$(jq -r '.oidcConfig.issuer // ""' <<<"$settings")" != "$ISSUER" || "$(jq -r '.oidcConfig.enablePKCEAuthentication // false' <<<"$settings")" != "true" ]]; then
  echo -e "${RED}✘ Argo CD does not advertise the Keycloak OIDC (PKCE) configuration${NC}"
  exit 1
fi
echo -e "${GREEN}✔ Argo CD advertises Keycloak SSO (PKCE)${NC}"
# Every SSO entry point must reach Keycloak's login form, not an error page: this catches
# unregistered redirect URIs and hosts Argo CD does not accept (no password is used).
for start in "http://localhost/auth/login?return_url=http%3A%2F%2Flocalhost%2Fapplications" \
             "http://argocd.localhost/auth/login?return_url=http%3A%2F%2Fargocd.localhost%2Fapplications" \
             "http://headlamp.localhost/"; do
  kc_url=$(curl -s -o /dev/null -w '%{redirect_url}' "$start")
  if [[ "$kc_url" != "${ISSUER}/protocol/openid-connect/auth?"* ]] || ! curl -s "$kc_url" | grep -q 'id="kc-form-login"'; then
    echo -e "${RED}✘ SSO entry point does not reach the Keycloak login form: ${start%%\?*}${NC}"
    exit 1
  fi
done
echo -e "${GREEN}✔ Argo CD (localhost, argocd.localhost) and Headlamp reach the Keycloak login form${NC}"
# Break-glass: the local platform-admin account must keep working (Phase 4 R-4).
pw_file="${GITOPS_LAB_SECRET_DIR:-$HOME/.config/gitops-lab}/argocd-platform-admin.password"
token=$(jq -n --rawfile p "$pw_file" '{username: "platform-admin", password: ($p | rtrimstr("\n"))}' \
  | curl -s -H 'Content-Type: application/json' -d @- http://localhost/api/v1/session | jq -r '.token // ""')
if [[ -z "$token" ]]; then
  echo -e "${RED}✘ Local break-glass login (platform-admin) failed${NC}"
  exit 1
fi
unset token
echo -e "${GREEN}✔ Local break-glass account platform-admin can log in${NC}"
hl=$(curl -s -o /dev/null -w '%{http_code} %{redirect_url}' -H 'Origin: https://evil.example' http://headlamp.localhost/clusters/k3d-spoke-prod/api/v1/namespaces)
if [[ "$hl" != "302 ${ISSUER}/protocol/openid-connect/auth?"*"client_id=headlamp"* ]]; then
  echo -e "${RED}✘ Unauthenticated Headlamp request is not redirected to Keycloak: ${hl:0:120}${NC}"
  exit 1
fi
if curl -s -D - -o /dev/null -H 'Origin: https://evil.example' http://headlamp.localhost/ | grep -qi '^access-control-allow-origin'; then
  echo -e "${RED}✘ Headlamp answers cross-origin requests (P4-1 regression)${NC}"
  exit 1
fi
echo -e "${GREEN}✔ Headlamp requires SSO (302 to Keycloak) and refuses cross-origin access${NC}"

echo -e "\n${YELLOW}[11/12] Asserting Supply-Chain Admission (Kyverno image verification)...${NC}"
# Phase 4 B.4: tenant namespaces only admit orders-processor images signed by its CI workflow.
UNSIGNED="ghcr.io/brunobml/orders-processor@sha256:c7e8f5d9038ad202da6d37e0be76aa342a482bd4d6b37279b0891792584cf32f"  # v1.4.0, built before signing existed
for target in "k3d-spoke-nonprod:orders-dev" "k3d-spoke-nonprod:orders-test" "k3d-spoke-prod:orders-prod"; do
  IFS=: read -r ctx ns <<<"$target"
  actions=$(kubectl --context "$ctx" get imagevalidatingpolicy tenant-images-signed -o jsonpath='{.spec.validationActions}' 2>/dev/null || true)
  if [[ "$actions" != '["Deny"]' ]]; then
    echo -e "${RED}✘ ${ctx}: image verification policy not enforcing (validationActions=${actions:-missing})${NC}"
    exit 1
  fi
  running=$(kubectl --context "$ctx" -n "$ns" get pods -o jsonpath='{.items[0].spec.containers[0].image}')
  overrides='{"spec":{"securityContext":{"runAsNonRoot":true,"runAsUser":10001,"seccompProfile":{"type":"RuntimeDefault"}},"containers":[{"name":"probe","image":"IMG","securityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]}}}]}}'
  # Each probe must be denied by the control it targets, not by any other one (2026-10-03 validation-01 V-6).
  if out=$(kubectl --context "$ctx" -n "$ns" run smoke-unsigned-probe --image="$UNSIGNED" --restart=Never --dry-run=server \
       --overrides="${overrides/IMG/$UNSIGNED}" -o name 2>&1); then
    echo -e "${RED}✘ ${ns}: an unsigned orders-processor image was admitted${NC}"
    exit 1
  elif [[ "$out" != *"Policy tenant-images-signed failed"* ]]; then
    echo -e "${RED}✘ ${ns}: the unsigned image was denied, but not by Kyverno policy tenant-images-signed: ${out:0:200}${NC}"
    exit 1
  fi
  # Step 0.3 (L4-2, O-2): arbitrary public image (alpine:latest) must be denied by native VAP
  if out=$(kubectl --context "$ctx" -n "$ns" run smoke-alpine-probe --image="alpine:latest" --restart=Never --dry-run=server \
       --overrides="${overrides/IMG/alpine:latest}" -o name 2>&1); then
    echo -e "${RED}✘ ${ns}: an unallowlisted image (alpine:latest) was admitted (VAP allowlist bypass)${NC}"
    exit 1
  elif [[ "$out" != *"ValidatingAdmissionPolicy 'tenant-image-registry-allowlist'"* ]]; then
    echo -e "${RED}✘ ${ns}: alpine:latest was denied, but not by the VAP tenant-image-registry-allowlist: ${out:0:200}${NC}"
    exit 1
  fi
  if ! kubectl --context "$ctx" -n "$ns" run smoke-signed-probe --image="$running" --restart=Never --dry-run=server \
       --overrides="${overrides/IMG/$running}" -o name >/dev/null 2>&1; then
    echo -e "${RED}✘ ${ns}: the running (signed) image ${running} is not admitted${NC}"
    exit 1
  fi
  echo -e "  ${ns}: unsigned image denied by Kyverno, alpine denied by the allowlist VAP, running image admitted (${running##*:})"
done
echo -e "${GREEN}✔ Image registry allowlist (VAP) and CI signature/SBOM policies (Kyverno) enforced in tenant namespaces${NC}"

echo -e "\n${YELLOW}[12/12] Asserting Observability (metrics, logs, probes, alerts, Grafana SSO)...${NC}"
promq() { kubectl --context k3d-hub-cluster -n monitoring exec deploy/prometheus-server -c prometheus-server -- \
  wget -qO- "http://localhost:9090/api/v1/query?query=$(jq -rn --arg q "$1" '$q|@uri')" 2>/dev/null; }
for spoke in spoke-nonprod spoke-prod; do
  n=$(promq "count(up{cluster=\"${spoke}\"} == 1)" | jq -r '.data.result[0].value[1] // 0')
  if (( n < 5 )); then echo -e "${RED}✘ hub has only ${n} healthy scrape targets from ${spoke}${NC}"; exit 1; fi
done
echo -e "${GREEN}✔ Hub receives metrics from both spokes${NC}"
failed=$(promq 'probe_success{job="blackbox"} == 0' | jq -r '[.data.result[].metric.probe] | join(",")')
if [[ -n "$failed" ]]; then echo -e "${RED}✘ Synthetic probes failing: ${failed}${NC}"; exit 1; fi
echo -e "${GREEN}✔ HTTP probes green${NC}"
# Phase 5 F: logs are shipped from every cluster and Loki is up.
for cl in hub spoke-nonprod spoke-prod; do
  r=$(promq "sum(rate(loki_write_sent_entries_total{cluster=\"${cl}\"}[10m]))" | jq -r '.data.result[0].value[1] // 0')
  if ! awk -v r="$r" 'BEGIN{exit !(r > 0)}'; then echo -e "${RED}✘ no log lines shipped from ${cl} in the last 10 min${NC}"; exit 1; fi
done
if [[ "$(promq 'up{job="loki"}' | jq -r '.data.result[0].value[1] // 0')" != 1 ]]; then echo -e "${RED}✘ Loki is not up${NC}"; exit 1; fi
echo -e "${GREEN}✔ Logs shipped from hub, spoke-nonprod and spoke-prod; Loki up${NC}"
# The synthetic order probe runs every 5 min, so right after a recovery (e.g. post-bootstrap after a
# moto restart) its last result can still be a failure; stage 9 already proved e2e processing directly.
e2e=$(promq 'lab_order_e2e_success == 0' | jq -r '[.data.result[] | .metric.namespace] | join(",")')
[[ -n "$e2e" ]] && echo -e "${YELLOW}! synthetic order probe's last run failed for: ${e2e} (re-checked every 5 min)${NC}"
# Phase P5: assert team EKS clusters are ready in Prometheus metrics
team_unready=$(promq 'lab_team_cluster_ready == 0' | jq -r '[.data.result[] | .metric.name] | join(",")' 2>/dev/null || true)
if [[ -n "$team_unready" ]]; then
  echo -e "${RED}✘ Team clusters not ready in Prometheus metrics: ${team_unready}${NC}"
  exit 1
fi
# Alerts firing for more than 20 min are persistent problems; younger ones are reported (they
# clear on their own after a recovery, within one probe cycle / alert 'for' window).
alerts=$(kubectl --context k3d-hub-cluster -n monitoring exec deploy/prometheus-server -c prometheus-server -- wget -qO- http://localhost:9090/api/v1/alerts 2>/dev/null)
old=$(jq -r --argjson now "$(date +%s)" '[.data.alerts[] | select(.state=="firing" and ((.activeAt | sub("\\.[0-9]+";"") | fromdateiso8601) < ($now - 1200))) | .labels.alertname] | unique | join(",")' <<<"$alerts")
new=$(jq -r '[.data.alerts[] | select(.state=="firing") | .labels.alertname] | unique | join(",")' <<<"$alerts")
if [[ -n "$old" ]]; then echo -e "${RED}✘ Alerts firing for more than 20 min: ${old}${NC}"; exit 1; fi
if [[ -n "$new" ]]; then echo -e "${YELLOW}! recently firing alerts: ${new}${NC}"; else echo -e "${GREEN}✔ No firing alerts${NC}"; fi
kc=$(curl -s -o /dev/null -w '%{redirect_url}' http://grafana.localhost/login/generic_oauth)
if [[ "$kc" != "${ISSUER}/protocol/openid-connect/auth?"* ]] || ! curl -s "$kc" | grep -q 'id="kc-form-login"'; then
  echo -e "${RED}✘ Grafana SSO entry point does not reach the Keycloak login form${NC}"; exit 1
fi
echo -e "${GREEN}✔ Grafana SSO entry point reaches the Keycloak login form${NC}"

echo -e "\n${GREEN}============================================================${NC}"
echo -e "${GREEN}  All Core Smoke Tests Passed!                             ${NC}"
echo -e "${GREEN}============================================================${NC}"
