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
# Fixed subnet: the queue-backed-service blueprint's worker NetworkPolicy allows egress to
# moto in 172.21.0.0/16, so the network must not get a different subnet on re-creation.
if ! docker network inspect "${NETWORK_NAME}" >/dev/null 2>&1; then
  docker network create --subnet 172.21.0.0/16 "${NETWORK_NAME}"
elif [[ "$(docker network inspect "${NETWORK_NAME}" --format '{{range .IPAM.Config}}{{.Subnet}}{{end}}')" != "172.21.0.0/16" ]]; then
  echo -e "${RED}✘ ${NETWORK_NAME} exists with a subnet other than 172.21.0.0/16; run 'make teardown' first.${NC}" >&2
  exit 1
fi

# 2. Launch Central Moto Cloud
# moto pinned by registry digest (5.2.3.dev0, the image the lab was validated on; Phase 3 B.5).
echo -e "\n${YELLOW}[2/6] Starting Central Mock AWS Cloud (moto-cloud)...${NC}"
docker rm -f moto-cloud 2>/dev/null || true
docker run -d --name moto-cloud \
  --network "${NETWORK_NAME}" \
  -p 127.0.0.1:5000:5000 \
  -e PYTHONUNBUFFERED=1 \
  -e MOTO_ALLOW_NONEXISTENT_SERVICES=true \
  --restart unless-stopped \
  motoserver/moto@sha256:91fd602a21f49cf9eb82fdf474015a3c131d40104c8297ea6a2ca920708ae32c \
  -p5000 -H0.0.0.0

# 3. Create k3d Clusters
echo -e "\n${YELLOW}[3/6] Creating k3d clusters (Hub, Spoke Non-Prod, Spoke Prod)...${NC}"
if ! k3d cluster list | grep -q "${HUB_CLUSTER}"; then
  k3d cluster create "${HUB_CLUSTER}" \
    --network "${NETWORK_NAME}" \
    --servers 1 --agents 0 \
    --image rancher/k3s:v1.35.5-k3s1 \
    --api-port 127.0.0.1:6550 \
    --port "127.0.0.1:8080:80@loadbalancer" \
    --port "127.0.0.1:8443:443@loadbalancer" \
    --k3s-arg "--disable=traefik@server:*"
fi

if ! k3d cluster list | grep -q "${SPOKE_NONPROD}"; then
  k3d cluster create "${SPOKE_NONPROD}" \
    --network "${NETWORK_NAME}" \
    --servers 1 --agents 1 \
    --image rancher/k3s:v1.35.5-k3s1 \
    --api-port 127.0.0.1:6551 \
    --port "127.0.0.1:8081:80@loadbalancer"
fi

if ! k3d cluster list | grep -q "${SPOKE_PROD}"; then
  k3d cluster create "${SPOKE_PROD}" \
    --network "${NETWORK_NAME}" \
    --servers 1 --agents 1 \
    --image rancher/k3s:v1.35.5-k3s1 \
    --api-port 127.0.0.1:6552 \
    --port "127.0.0.1:8082:80@loadbalancer"
fi

# 4. Install Traefik Ingress Controller on Hub
echo -e "\n${YELLOW}[4/7] Deploying Traefik Ingress Controller on ${HUB_CLUSTER}...${NC}"
helm repo add traefik https://traefik.github.io/charts 2>/dev/null || true
helm repo update traefik
# Phase 3 B.3: bootstrap-only install, pinned to the version the addon-traefik Application
# manages. The Argo CD UI/CLI ingress needs Traefik before the root app exists; after
# `make bootstrap` Argo CD adopts these objects, so Helm's release record is removed and an
# existing Traefik is never reinstalled.
if ! kubectl --context "k3d-${HUB_CLUSTER}" -n traefik get deployment traefik >/dev/null 2>&1; then
  helm --kube-context "k3d-${HUB_CLUSTER}" upgrade --install traefik traefik/traefik \
    --version 41.6.1 \
    --namespace traefik \
    --create-namespace
  kubectl --context "k3d-${HUB_CLUSTER}" -n traefik delete secret -l owner=helm,name=traefik
fi
kubectl --context "k3d-${HUB_CLUSTER}" wait --for=condition=ready --timeout=120s pod -l app.kubernetes.io/name=traefik -n traefik

# 4b. Install Argo CD on Hub
echo -e "\n${YELLOW}[4b/7] Deploying Argo CD on ${HUB_CLUSTER}...${NC}"
helm repo add argo https://argoproj.github.io/argo-helm 2>/dev/null || true
helm repo update argo
# argocd-secret is not managed by Helm (configs.secret.createSecret=false), so it must exist
# before argocd-server starts. setup-argocd-accounts.sh creates it if missing and sets the
# local-account passwords (Phase 3 A.2).
kubectl --context "k3d-${HUB_CLUSTER}" create namespace argocd --dry-run=client -o yaml \
  | kubectl --context "k3d-${HUB_CLUSTER}" apply -f -
bash "${SCRIPT_DIR}/setup-argocd-accounts.sh"
# Phase 4 A.1: Keycloak / oauth2-proxy secrets (outside Git) for the SSO addons.
bash "${SCRIPT_DIR}/setup-keycloak-secrets.sh"
# Phase 3 B.4: bootstrap-only install. After `make bootstrap`, the argo-cd Application
# (applicationsets/argo-cd.yaml) manages Argo CD from Git, so Helm's release record is removed
# and an existing Argo CD is never reinstalled here. Break-glass: run this helm command by hand.
if ! kubectl --context "k3d-${HUB_CLUSTER}" -n argocd get deployment argo-cd-argocd-server >/dev/null 2>&1; then
  helm --kube-context "k3d-${HUB_CLUSTER}" upgrade --install argo-cd argo/argo-cd \
    --version 10.9.4 \
    --namespace argocd \
    --create-namespace \
    -f "${REPO_ROOT}/clusters/values-argocd-hub.yaml"
  kubectl --context "k3d-${HUB_CLUSTER}" -n argocd delete secret -l owner=helm,name=argo-cd
fi
kubectl --context "k3d-${HUB_CLUSTER}" wait --for=condition=ready --timeout=120s pod -l app.kubernetes.io/name=argocd-server -n argocd

# Log the CLI in as platform-admin: register-spokes.sh verifies connectivity with `argocd cluster list`.
# Retry: the server can be Ready slightly before the Traefik route serves it.
for attempt in $(seq 1 30); do
  if argocd login localhost:8080 --plaintext --grpc-web --skip-test-tls \
      --username platform-admin \
      --password "$(cat "${GITOPS_LAB_SECRET_DIR:-$HOME/.config/gitops-lab}/argocd-platform-admin.password")" </dev/null >/dev/null 2>&1; then
    echo "✔ argocd CLI logged in as platform-admin"
    break
  fi
  [[ "$attempt" == 30 ]] && { echo -e "${RED}✘ argocd login failed after 30 attempts${NC}" >&2; exit 1; }
  sleep 5
done

# 4c. Apply Enterprise AppProjects
echo -e "\n${YELLOW}[4c/7] Creating Enterprise AppProjects on ${HUB_CLUSTER}...${NC}"
kubectl --context "k3d-${HUB_CLUSTER}" apply -f "${REPO_ROOT}/projects/" --validate=false

# 5. Register Spokes into Hub Argo CD
echo -e "\n${YELLOW}[5/7] Registering spokes into Hub Argo CD...${NC}"
bash "${SCRIPT_DIR}/register-spokes.sh"

# 5b. Configure Headlamp Multi-Cluster Credentials
echo -e "\n${YELLOW}[5b/7] Configuring Headlamp Multi-Cluster Credentials on ${HUB_CLUSTER}...${NC}"
bash "${REPO_ROOT}/addons/headlamp/setup-credentials.sh"

# 6. Platform controllers (kro + ACK) are no longer installed here (Phase 3 B.2).
#    register-spokes.sh labels each spoke addons-managed=true, and after `make bootstrap`
#    the addons-spoke / addons-spoke-ack-credentials ApplicationSets deploy them from Git.
echo -e "\n${YELLOW}[6/7] Spoke controllers (kro, ACK) will be deployed by Argo CD after 'make bootstrap'.${NC}"

# The built-in admin account is disabled (Phase 3 A.2); remove any generated initial password.
kubectl --context "k3d-${HUB_CLUSTER}" -n argocd delete secret argocd-initial-admin-secret 2>/dev/null || true

echo -e "\n${GREEN}============================================================${NC}"
echo -e "${GREEN}  Hub-and-Spoke Environment Ready!                         ${NC}"
echo -e "${GREEN}============================================================${NC}"
echo -e "  Hub Argo CD UI:     http://localhost:8080 (or http://argocd.localhost:8080; accounts: run 'make password')"
echo -e "  Hub Headlamp UI:    http://headlamp.localhost:8080 (Single Pane of Glass Dashboard)"
echo -e "  Central Moto Cloud: http://localhost:5000/moto-api/"
echo -e "  Spoke Non-Prod:     k3d-spoke-nonprod (Traefik Ingress on port 8081)"
echo -e "    - Dev Orders:     http://orders-dev.localhost:8081"
echo -e "    - Test Orders:    http://orders-test.localhost:8081"
echo -e "  Spoke Prod:         k3d-spoke-prod    (Traefik Ingress on port 8082)"
echo -e "    - Prod Orders:    http://orders-prod.localhost:8082"
