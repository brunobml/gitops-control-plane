#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPOS_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

REPOS=("gitops-control-plane" "platform-catalog" "tenant-workloads" "orders-processor" "platform-charts")

echo -e "${BLUE}============================================================${NC}"
echo -e "${BLUE}  Pushing Hub-and-Spoke Repositories to GitHub             ${NC}"
echo -e "${BLUE}============================================================${NC}"

for repo in "${REPOS[@]}"; do
  echo -e "\n${YELLOW}Pushing ${repo}...${NC}"
  if git -C "${REPOS_DIR}/${repo}" push -u origin main; then
    echo -e "${GREEN}✔ Successfully pushed ${repo}${NC}"
  else
    echo -e "${RED}✘ Failed to push ${repo}. Please ensure the repo exists on GitHub: https://github.com/new${NC}"
  fi
done
