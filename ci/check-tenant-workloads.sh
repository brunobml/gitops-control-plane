#!/usr/bin/env bash
# CI for tenant-workloads (2026-10-03 Track A.2): a merge can no longer break the tenant render.
# Required status check on tenant-workloads (O-1). Locally: `make ci-tenants`.
#
#   registrations  JSON Schema (tenant-workloads/schema/registration.schema.json), file naming,
#                  uniqueness, values file present at valuesRevision (ci/check-registrations.py)
#   render         the tenant-workloads ApplicationSet of gitops-control-plane rendered with these
#                  registrations (same template guards, missingkey=error), then the golden chart
#                  rendered with each app's values
#   schemas        kubeconform of the rendered QueueBackedServices (kro-generated CRD schema)
#   secrets        credential patterns in tracked files
#
# usage: ci/check-tenant-workloads.sh [stage...]   with TENANT_WORKLOADS_DIR (default ../tenant-workloads)
CI_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
# shellcheck source=ci/lib.sh
source "$CI_LIB" "$@"
REPO=$(cd "${CI_DIR}/.." && pwd)
TW=$(cd "${TENANT_WORKLOADS_DIR:-${REPO}/../tenant-workloads}" && pwd)
OUT="${LAB_CI_OUT:-$(mktemp -d)}"
mkdir -p "$OUT"

if stage registrations "Registration files"; then
  python3 "${CI_DIR}/check-registrations.py" "$TW" || fail "registrations"
fi

if stage render "Render the tenant-workloads ApplicationSet with these registrations"; then
  if labci appsets -repo "${GH}/tenant-workloads.git=${TW}" "$REPO/applicationsets/tenant-workloads.yaml" > "$OUT/apps.yaml" \
     && python3 "${CI_DIR}/render.py" "$OUT/apps.yaml" --out "$OUT/manifests"; then
    ok "tenant Applications render"
  else
    fail "render"
  fi
fi

if stage schemas "Schema validation (kubeconform)"; then
  if [[ -d "$OUT/manifests" ]] && kubeconform "$OUT/manifests"; then ok "manifests valid"; else fail "kubeconform (run the render stage first)"; fi
fi

if stage secrets "Secret patterns in tracked files"; then
  python3 "${CI_DIR}/secret-scan.py" "$TW" || fail "secret scan"
fi

finish
