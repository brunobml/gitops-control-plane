#!/usr/bin/env bash
set -euo pipefail

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

HUB_CLUSTER="hub-cluster"
SPOKE_NONPROD="spoke-nonprod"
SPOKE_PROD="spoke-prod"
NETWORK_NAME="k3d-cloud-net"

echo -e "${BLUE}============================================================${NC}"
echo -e "${BLUE}  Tearing Down Multi-Cluster Hub-and-Spoke Lab               ${NC}"
echo -e "${BLUE}============================================================${NC}"

echo -e "${YELLOW}Deleting k3d clusters...${NC}"
k3d cluster delete "${HUB_CLUSTER}" 2>/dev/null || true
k3d cluster delete "${SPOKE_NONPROD}" 2>/dev/null || true
k3d cluster delete "${SPOKE_PROD}" 2>/dev/null || true

echo -e "${YELLOW}Stopping and removing moto-cloud container...${NC}"
docker rm -f moto-cloud 2>/dev/null || true

echo -e "${YELLOW}Removing Docker network '${NETWORK_NAME}'...${NC}"
docker network rm "${NETWORK_NAME}" 2>/dev/null || true

echo -e "\n${GREEN}Teardown complete.${NC}"
