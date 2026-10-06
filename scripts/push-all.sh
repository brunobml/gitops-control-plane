#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPOS_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

REPOS=("gitops-control-plane" "platform-catalog" "tenant-workloads" "orders-processor" "platform-charts" "tenant-iac")

DRY_RUN=()
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=(--dry-run)
  echo -e "${YELLOW}[DRY-RUN MODE] Git push operations will simulate without modifying remote repositories.${NC}"
fi

echo -e "${BLUE}============================================================${NC}"
echo -e "${BLUE}  Pushing Hub-and-Spoke Repositories to GitHub             ${NC}"
echo -e "${BLUE}============================================================${NC}"

failed=0

for repo in "${REPOS[@]}"; do
  target_dir="${REPOS_DIR}/${repo}"
  echo -e "\n${YELLOW}Pushing ${repo}...${NC}"

  if [[ ! -d "${target_dir}/.git" ]]; then
    echo -e "${RED}✘ Directory '${target_dir}' is not an initialized Git repository.${NC}" >&2
    failed=$((failed + 1))
    continue
  fi

  if git -C "${target_dir}" push "${DRY_RUN[@]}" -u origin main; then
    echo -e "${GREEN}✔ Successfully pushed ${repo}${NC}"
  else
    echo -e "${RED}✘ Failed to push ${repo}. Please ensure remote origin exists on GitHub.${NC}" >&2
    failed=$((failed + 1))
  fi
done

if (( failed > 0 )); then
  echo -e "\n${RED}✘ Failed pushing ${failed} of ${#REPOS[@]} repositories.${NC}" >&2
  exit 1
fi

echo -e "\n${GREEN}✔ All ${#REPOS[@]} repositories processed successfully.${NC}"
