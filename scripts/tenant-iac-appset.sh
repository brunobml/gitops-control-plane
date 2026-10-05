#!/usr/bin/env bash
# Tenant IaC: print the ApplicationSet of one team (from scripts/templates/tenant-iac-appset.yaml).
# usage: scripts/tenant-iac-appset.sh <team> > applicationsets/tenant-iac-<team>.yaml
set -euo pipefail
team=${1:?usage: tenant-iac-appset.sh <team>}
[[ "$team" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]] || { echo "invalid team name: $team" >&2; exit 1; }
sed "s/__TEAM__/${team}/g" "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/templates/tenant-iac-appset.yaml"
