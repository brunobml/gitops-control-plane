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
echo -e "\n${YELLOW}[1/7] Checking Central Mock AWS Cloud (moto-cloud)...${NC}"
if curl -s -f http://localhost:5000/moto-api/ > /dev/null; then
  echo -e "${GREEN}✔ moto-cloud is responding at http://localhost:5000${NC}"
else
  echo -e "${RED}✘ moto-cloud is unreachable at http://localhost:5000${NC}"
  exit 1
fi

# 2. Hub Cluster & Argo CD Core Pods
echo -e "\n${YELLOW}[2/7] Checking Hub Cluster & Argo CD...${NC}"
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
echo -e "\n${YELLOW}[3/7] Asserting Argo CD Application Sync and Health...${NC}"
EXPECTED_APPS=("addon-headlamp" "kro-blueprints-spoke-nonprod" "kro-blueprints-spoke-prod" "orders-dev" "orders-test" "orders-prod" "root-control-plane")
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
echo -e "\n${YELLOW}[4/7] Checking Spoke Controllers (Kro + ACK)...${NC}"
for ctx in "k3d-spoke-nonprod" "k3d-spoke-prod"; do
  kubectl --context "$ctx" get nodes > /dev/null
  echo -e "${GREEN}✔ ${ctx} API is reachable${NC}"

  kubectl --context "$ctx" -n ack-system wait --for=condition=ready --timeout=30s pod -l app.kubernetes.io/name=sqs-chart >/dev/null
  echo -e "${GREEN}✔ ACK SQS controller is ready on ${ctx}${NC}"

  kubectl --context "$ctx" -n kro wait --for=condition=ready --timeout=30s pod -l app.kubernetes.io/name=kro >/dev/null
  echo -e "${GREEN}✔ Kro controller is ready on ${ctx}${NC}"
done

# 5. Kro Custom Resources State
echo -e "\n${YELLOW}[5/7] Asserting QueueBackedService Resource Status...${NC}"
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
echo -e "\n${YELLOW}[6/7] Asserting AWS Cloud SQS Queues & DLQs...${NC}"
QUEUES_OUTPUT=$(AWS_ACCESS_KEY_ID=mock-key AWS_SECRET_ACCESS_KEY=mock-secret aws --endpoint-url=http://localhost:5000 --region us-east-1 sqs list-queues --output json 2>/dev/null || echo "{}")

EXPECTED_QUEUES=(
  "orders-dev-queue"
  "orders-dev-dlq"
  "orders-test-queue"
  "orders-test-dlq"
  "orders-prod-queue"
  "orders-prod-dlq"
)

for qname in "${EXPECTED_QUEUES[@]}"; do
  if ! echo "$QUEUES_OUTPUT" | grep -q "/${qname}\""; then
    echo -e "${RED}✘ Missing expected SQS queue in Moto Cloud: ${qname}${NC}"
    exit 1
  fi
  echo -e "  Queue: ${GREEN}${qname}${NC} present"
done
echo -e "${GREEN}✔ All 6 expected SQS queues (3 queues + 3 DLQs) verified in Moto Cloud${NC}"

# 7. GitOps Workload Pods (L3-4, C-2)
echo -e "\n${YELLOW}[7/7] Asserting Workload Pods...${NC}"
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

echo -e "\n${GREEN}============================================================${NC}"
echo -e "${GREEN}  All Core Smoke Tests Passed!                             ${NC}"
echo -e "${GREEN}============================================================${NC}"
