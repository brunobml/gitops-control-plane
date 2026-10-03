#!/usr/bin/env bash
# 2026-10-03 Track B.2: print the ApplicationSet of one tenant (from scripts/templates/tenant-appset.yaml).
# usage: scripts/tenant-appset.sh <tenant> > applicationsets/tenant-workloads-<tenant>.yaml
# CI (ci/check-tenant-appsets.py) fails if a committed tenant ApplicationSet differs from this output.
set -euo pipefail
tenant=${1:?usage: tenant-appset.sh <tenant>}
[[ "$tenant" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]] || { echo "invalid tenant name: $tenant" >&2; exit 1; }
sed "s/__TENANT__/${tenant}/g" "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/templates/tenant-appset.yaml"
