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
echo -e "\n${YELLOW}[1/5] Checking Central Mock AWS Cloud (moto-cloud)...${NC}"
if curl -s -f http://localhost:5000/moto-api/ > /dev/null; then
  echo -e "${GREEN}✔ moto-cloud is responding at http://localhost:5000${NC}"
else
  echo -e "${RED}✘ moto-cloud is unreachable at http://localhost:5000${NC}"
  exit 1
fi

# 2. Hub Cluster & Argo CD
echo -e "\n${YELLOW}[2/5] Checking Hub Cluster & Argo CD...${NC}"
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

# 3. Spoke Non-Prod (Kro + ACK)
echo -e "\n${YELLOW}[3/5] Checking Spoke Non-Prod (k3d-spoke-nonprod)...${NC}"
kubectl --context k3d-spoke-nonprod get nodes > /dev/null
echo -e "${GREEN}✔ spoke-nonprod API is reachable${NC}"

kubectl --context k3d-spoke-nonprod -n ack-system wait --for=condition=ready --timeout=30s pod -l app.kubernetes.io/name=sqs-chart >/dev/null
echo -e "${GREEN}✔ ACK SQS controller is ready on spoke-nonprod${NC}"

kubectl --context k3d-spoke-nonprod -n kro wait --for=condition=ready --timeout=30s pod -l app.kubernetes.io/name=kro >/dev/null
echo -e "${GREEN}✔ Kro controller is ready on spoke-nonprod${NC}"

# 4. Spoke Prod (Kro + ACK)
echo -e "\n${YELLOW}[4/5] Checking Spoke Prod (k3d-spoke-prod)...${NC}"
kubectl --context k3d-spoke-prod get nodes > /dev/null
echo -e "${GREEN}✔ spoke-prod API is reachable${NC}"

kubectl --context k3d-spoke-prod -n ack-system wait --for=condition=ready --timeout=30s pod -l app.kubernetes.io/name=sqs-chart >/dev/null
echo -e "${GREEN}✔ ACK SQS controller is ready on spoke-prod${NC}"

kubectl --context k3d-spoke-prod -n kro wait --for=condition=ready --timeout=30s pod -l app.kubernetes.io/name=kro >/dev/null
echo -e "${GREEN}✔ Kro controller is ready on spoke-prod${NC}"

# 5. GitOps Workloads & AWS Queues
echo -e "\n${YELLOW}[5/5] Checking Workloads & SQS Queues...${NC}"
echo "Current SQS queues in Central Moto Cloud:"
AWS_ACCESS_KEY_ID=mock-key AWS_SECRET_ACCESS_KEY=mock-secret aws --endpoint-url=http://localhost:5000 --region us-east-1 sqs list-queues --output table 2>/dev/null || echo "  (No queues created yet or aws cli not present)"

DEV_PODS=$(kubectl --context k3d-spoke-nonprod -n orders-dev get pods --no-headers 2>/dev/null | grep -c "Running" || echo "0")
TEST_PODS=$(kubectl --context k3d-spoke-nonprod -n orders-test get pods --no-headers 2>/dev/null | grep -c "Running" || echo "0")
PROD_PODS=$(kubectl --context k3d-spoke-prod -n orders-prod get pods --no-headers 2>/dev/null | grep -c "Running" || echo "0")

echo -e "  orders-dev pods on spoke-nonprod:  ${DEV_PODS} (expected: 1)"
echo -e "  orders-test pods on spoke-nonprod: ${TEST_PODS} (expected: 1)"
echo -e "  orders-prod pods on spoke-prod:    ${PROD_PODS} (expected: 2)"

if [[ "$DEV_PODS" -ge 1 && "$TEST_PODS" -ge 1 && "$PROD_PODS" -ge 2 ]]; then
  echo -e "${GREEN}✔ All orders workloads running across non-prod and prod spokes!${NC}"
fi

echo -e "\n${GREEN}============================================================${NC}"
echo -e "${GREEN}  All Core Smoke Tests Passed!                             ${NC}"
echo -e "${GREEN}============================================================${NC}"
