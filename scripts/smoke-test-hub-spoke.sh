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
echo -e "\n${YELLOW}[1/9] Checking Central Mock AWS Cloud (moto-cloud)...${NC}"
if curl -s -f http://localhost:5000/moto-api/ > /dev/null; then
  echo -e "${GREEN}✔ moto-cloud is responding at http://localhost:5000${NC}"
else
  echo -e "${RED}✘ moto-cloud is unreachable at http://localhost:5000${NC}"
  exit 1
fi

# 2. Hub Cluster & Argo CD Core Pods
echo -e "\n${YELLOW}[2/9] Checking Hub Cluster & Argo CD...${NC}"
kubectl --context k3d-hub-cluster get nodes > /dev/null
echo -e "${GREEN}✔ Hub cluster API is reachable${NC}"

ARGOCD_PODS=$(kubectl --context k3d-hub-cluster -n argocd get pods --no-headers | awk '{print $3}')
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
echo -e "\n${YELLOW}[3/9] Asserting Argo CD Application Sync and Health...${NC}"
EXPECTED_APPS=("argo-cd" "addon-headlamp" "addon-platform-config-spoke-nonprod" "addon-platform-config-spoke-prod" "addon-traefik" "platform-projects" "addon-kro-spoke-nonprod" "addon-kro-spoke-prod" "addon-ack-sqs-spoke-nonprod" "addon-ack-sqs-spoke-prod" "addon-ack-credentials-spoke-nonprod" "addon-ack-credentials-spoke-prod" "kro-blueprints-spoke-nonprod" "kro-blueprints-spoke-prod" "orders-dev" "orders-test" "orders-prod" "root-control-plane")
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
echo -e "\n${YELLOW}[4/9] Checking Spoke Controllers (Kro + ACK)...${NC}"
for ctx in "k3d-spoke-nonprod" "k3d-spoke-prod"; do
  kubectl --context "$ctx" get nodes > /dev/null
  echo -e "${GREEN}✔ ${ctx} API is reachable${NC}"

  kubectl --context "$ctx" -n ack-system wait --for=condition=ready --timeout=30s pod -l app.kubernetes.io/name=sqs-chart >/dev/null
  echo -e "${GREEN}✔ ACK SQS controller is ready on ${ctx}${NC}"

  kubectl --context "$ctx" -n kro wait --for=condition=ready --timeout=30s pod -l app.kubernetes.io/name=kro >/dev/null
  echo -e "${GREEN}✔ Kro controller is ready on ${ctx}${NC}"
done

# 5. Kro Custom Resources State
echo -e "\n${YELLOW}[5/9] Asserting QueueBackedService Resource Status...${NC}"
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
echo -e "\n${YELLOW}[6/9] Asserting AWS Cloud SQS Queues & DLQs...${NC}"
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
echo -e "\n${YELLOW}[7/9] Asserting Workload Pods...${NC}"
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
echo -e "\n${YELLOW}[8/9] Asserting Credential Expiry...${NC}"
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
echo -e "\n${YELLOW}[9/9] Asserting End-to-End Order Flow...${NC}"
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

echo -e "\n${GREEN}============================================================${NC}"
echo -e "${GREEN}  All Core Smoke Tests Passed!                             ${NC}"
echo -e "${GREEN}============================================================${NC}"
