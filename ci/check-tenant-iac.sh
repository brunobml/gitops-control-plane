#!/usr/bin/env bash
# CI for tenant-iac (2026-10-05 Tenant IaC P3).
# Required status check on tenant-iac (O-1). Locally: `make ci-iac`.
#
#   claims      JSON Schema (tenant-iac/schema/cluster.schema.json), file naming,
#               uniqueness, directory matching, relational sizing bounds
#   fixtures    Self-test fixture suite (asserts 14 negative rejected, 2 positive admitted)
#   team-appsets Every team directory has a committed control-plane ApplicationSet
#   render      offline render through ApplicationSet template + golden chart (plan v0.3 §4)
#   schemas     kubeconform of rendered TeamEKSClusters (kro CRD schema)
#   secrets     credential patterns in tracked files
#
# usage: ci/check-tenant-iac.sh [stage...]   with TENANT_IAC_DIR (default ../tenant-iac)
CI_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
# shellcheck source=ci/lib.sh
source "$CI_LIB" "$@"
REPO=$(cd "${CI_DIR}/.." && pwd)
TI=$(cd "${TENANT_IAC_DIR:-${REPO}/../tenant-iac}" && pwd)
OUT="${LAB_CI_OUT:-$(mktemp -d)}"
mkdir -p "$OUT/appsets" "$OUT/manifests"

if stage claims "Cluster claim files"; then
  python3 "${CI_DIR}/check-clusters.py" "$TI" || fail "claims"
fi

if stage fixtures "Fixture suite verification (positive and negative fixtures)"; then
  python3 "${CI_DIR}/check-clusters.py" "$TI" --test-fixtures || fail "fixtures"
fi

if stage team-appsets "Every team directory has an ApplicationSet"; then
  python3 "${CI_DIR}/check-tenant-iac-appsets.py" "$REPO" "$TI" || fail "team ApplicationSets"
fi

if stage render "Render through ApplicationSet template + chart (plan v0.3 §4)"; then
  mapfile -t teams < <(cd "$TI" && find teams -mindepth 1 -maxdepth 1 -type d -exec basename {} \; 2>/dev/null || true)

  TARGET_TI="$TI"
  CLEANUP_TEMP=false

  if (( ${#teams[@]} == 0 )); then
    # Before P4 onboards teams, test the ApplicationSet template with the positive fixtures
    TEMP_TI=$(mktemp -d)
    mkdir -p "$TEMP_TI/teams/team-data/clusters"
    cp "$TI/tests/fixtures/positive/dev.yaml" "$TEMP_TI/teams/team-data/clusters/analytics-dev.yaml"
    cp "$TI/tests/fixtures/positive/prod.yaml" "$TEMP_TI/teams/team-data/clusters/analytics-prod.yaml"
    TARGET_TI="$TEMP_TI"
    CLEANUP_TEMP=true
    teams=("team-data")
  fi

  for team in "${teams[@]}"; do
    bash "$REPO/scripts/tenant-iac-appset.sh" "$team" > "$OUT/appsets/tenant-iac-${team}.yaml"
  done

  if labci appsets -repo "${GH}/tenant-iac.git=${TARGET_TI}" "$OUT/appsets"/*.yaml > "$OUT/apps.yaml" \
     && python3 "${CI_DIR}/render.py" "$OUT/apps.yaml" --out "$OUT/manifests" --repo "${GH}/tenant-iac.git=${TARGET_TI}"; then
    ok "ApplicationSets and charts rendered successfully"
  else
    fail "render through ApplicationSet template failed"
  fi

  if [[ "$CLEANUP_TEMP" == true ]]; then
    rm -rf "$TARGET_TI"
  fi
fi

if stage schemas "Schema validation (kubeconform)"; then
  if [[ -d "$OUT/manifests" && $(ls -A "$OUT/manifests" 2>/dev/null) ]]; then
    if kubeconform "$OUT/manifests"; then
      ok "manifests valid against TeamEKSCluster CRD schema"
    else
      fail "kubeconform validation failed"
    fi
  else
    fail "no manifests to validate (run the render stage first)"
  fi
fi

if stage secrets "Secret patterns in tracked files"; then
  python3 "${CI_DIR}/secret-scan.py" "$TI" || fail "secret scan"
fi

finish
