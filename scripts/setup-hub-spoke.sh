#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPOS_DIR="$(cd "${REPO_ROOT}/.." && pwd)"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

NETWORK_NAME="k3d-cloud-net"
HUB_CLUSTER="hub-cluster"
SPOKE_NONPROD="spoke-nonprod"
SPOKE_PROD="spoke-prod"

echo -e "${BLUE}============================================================${NC}"
echo -e "${BLUE}  Starting Multi-Cluster Hub-and-Spoke Lab Setup            ${NC}"
echo -e "${BLUE}============================================================${NC}"

# 1. Create Docker Network
echo -e "\n${YELLOW}[1/6] Creating shared Docker network '${NETWORK_NAME}'...${NC}"
docker network create "${NETWORK_NAME}" 2>/dev/null || true

# 2. Launch Central Moto Cloud
echo -e "\n${YELLOW}[2/6] Starting Central Mock AWS Cloud (moto-cloud)...${NC}"
docker rm -f moto-cloud 2>/dev/null || true
docker run -d --name moto-cloud \
  --network "${NETWORK_NAME}" \
  -p 5000:5000 \
  -e PYTHONUNBUFFERED=1 \
  -e MOTO_ALLOW_NONEXISTENT_SERVICES=true \
  --restart unless-stopped \
  motoserver/moto:latest \
  -p5000 -H0.0.0.0

# 3. Create k3d Clusters
echo -e "\n${YELLOW}[3/6] Creating k3d clusters (Hub, Spoke Non-Prod, Spoke Prod)...${NC}"
if ! k3d cluster list | grep -q "${HUB_CLUSTER}"; then
  k3d cluster create "${HUB_CLUSTER}" \
    --network "${NETWORK_NAME}" \
    --servers 1 --agents 0 \
    --port "8080:80@loadbalancer" \
    --port "8443:443@loadbalancer" \
    --k3s-arg "--disable=traefik@server:*"
fi

if ! k3d cluster list | grep -q "${SPOKE_NONPROD}"; then
  k3d cluster create "${SPOKE_NONPROD}" \
    --network "${NETWORK_NAME}" \
    --servers 1 --agents 1 \
    --port "8081:80@loadbalancer"
fi

if ! k3d cluster list | grep -q "${SPOKE_PROD}"; then
  k3d cluster create "${SPOKE_PROD}" \
    --network "${NETWORK_NAME}" \
    --servers 1 --agents 1 \
    --port "8082:80@loadbalancer"
fi

# 4. Install Argo CD on Hub
echo -e "\n${YELLOW}[4/6] Deploying Argo CD on ${HUB_CLUSTER}...${NC}"
helm repo add argo https://argoproj.github.io/argo-helm 2>/dev/null || true
helm repo update argo
helm --kube-context "k3d-${HUB_CLUSTER}" upgrade --install argo-cd argo/argo-cd \
  --namespace argocd \
  --create-namespace \
  -f "${REPO_ROOT}/clusters/values-argocd-hub.yaml"
kubectl --context "k3d-${HUB_CLUSTER}" wait --for=condition=ready --timeout=120s pod -l app.kubernetes.io/name=argocd-server -n argocd

# 4b. Apply Enterprise AppProjects
echo -e "\n${YELLOW}[4b/6] Creating Enterprise AppProjects on ${HUB_CLUSTER}...${NC}"
kubectl --context "k3d-${HUB_CLUSTER}" apply -f "${REPO_ROOT}/projects/" --validate=false

# 5. Register Spokes into Hub Argo CD
echo -e "\n${YELLOW}[5/6] Registering spokes into Hub Argo CD...${NC}"
bash "${SCRIPT_DIR}/register-spokes.sh"

# 6. Install Platform Controllers (Kro + ACK) on Spokes
echo -e "\n${YELLOW}[6/6] Installing Kro & ACK on both spoke clusters...${NC}"
for ctx in "k3d-${SPOKE_NONPROD}" "k3d-${SPOKE_PROD}"; do
  kubectl --context "$ctx" apply -f "${REPOS_DIR}/platform-catalog/controllers/ack/credentials-secret.yaml"
  helm --kube-context "$ctx" upgrade --install ack-sqs-controller oci://public.ecr.aws/aws-controllers-k8s/sqs-chart \
    --version 1.7.1 \
    --namespace ack-system \
    --create-namespace \
    -f "${REPOS_DIR}/platform-catalog/controllers/ack/values-sqs.yaml"
  helm --kube-context "$ctx" upgrade --install kro oci://registry.k8s.io/kro/charts/kro \
    --version 0.9.4 \
    --namespace kro \
    --create-namespace
done

# Clean up temporary initial-admin-secret if present, using predefined lab credentials
kubectl --context "k3d-${HUB_CLUSTER}" -n argocd delete secret argocd-initial-admin-secret 2>/dev/null || true
ADMIN_PASS="admin123"

echo -e "\n${GREEN}============================================================${NC}"
echo -e "${GREEN}  Hub-and-Spoke Environment Ready!                         ${NC}"
echo -e "${GREEN}============================================================${NC}"
echo -e "  Hub Argo CD UI:     http://localhost:8080 (admin / ${ADMIN_PASS})"
echo -e "  Central Moto Cloud: http://localhost:5000/moto-api/"
echo -e "  Spoke Non-Prod:     k3d-spoke-nonprod (Traefik Ingress on port 8081)"
echo -e "    - Dev Orders:     http://orders-dev.localhost:8081"
echo -e "    - Test Orders:    http://orders-test.localhost:8081"
echo -e "  Spoke Prod:         k3d-spoke-prod    (Traefik Ingress on port 8082)"
echo -e "    - Prod Orders:    http://orders-prod.localhost:8082"
