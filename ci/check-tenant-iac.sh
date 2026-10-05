#!/usr/bin/env bash
# CI for tenant-iac (2026-10-05 Tenant IaC P3).
# Required status check on tenant-iac (O-1). Locally: `make ci-iac`.
#
#   claims      JSON Schema (tenant-iac/schema/cluster.schema.json), file naming,
#               uniqueness, directory matching, relational sizing bounds
#   fixtures    Self-test fixture suite (asserts 14 negative rejected, 2 positive admitted)
#   render      offline render of claims through team-cluster chart
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
mkdir -p "$OUT/manifests"

if stage claims "Cluster claim files"; then
  python3 "${CI_DIR}/check-clusters.py" "$TI" || fail "claims"
fi

if stage fixtures "Fixture suite verification (positive and negative fixtures)"; then
  python3 "${CI_DIR}/check-clusters.py" "$TI" --test-fixtures || fail "fixtures"
fi

if stage render "Render cluster claims through chart"; then
  mapfile -t claim_files < <(cd "$TI" && ls teams/*/clusters/*.yaml tests/fixtures/positive/*.yaml 2>/dev/null || true)
  if (( ${#claim_files[@]} )); then
    PCH="${PLATFORM_CHARTS_DIR:-${REPO}/../platform-charts}"
    HELM_HOME=$(mktemp -d)
    chmod 777 "$HELM_HOME"

    if [[ -d "${PCH}/charts/team-cluster" ]]; then
      CHART_PATH="/src/charts/team-cluster"
      CHART_MOUNT=(-v "${PCH}/charts:/src/charts:ro")
    else
      CHART_PATH="oci://ghcr.io/brunobml/charts/team-cluster"
      CHART_MOUNT=()
    fi

    for cf in "${claim_files[@]}"; do
      rel_base=$(basename "$cf" .yaml)
      team_name=$(python3 -c 'import yaml, sys; print(yaml.safe_load(open(sys.argv[1]))["team"])' "$TI/$cf")
      env_name=$(python3 -c 'import yaml, sys; print(yaml.safe_load(open(sys.argv[1]))["env"])' "$TI/$cf")
      ns="iac-${team_name}-${env_name}"
      out_manifest="$OUT/manifests/${team_name}-${rel_base}.yaml"

      if docker run --rm -u "$(id -u):$(id -g)" "${CHART_MOUNT[@]}" -v "$TI:/src/tenant:ro" \
           -v "$HELM_HOME:/helm" -e HELM_CACHE_HOME=/helm/cache \
           -e HELM_CONFIG_HOME=/helm/config -e HELM_DATA_HOME=/helm/data \
           "${HELM_IMAGE}" template "$rel_base" "$CHART_PATH" --version 1.0.0 \
           -f "/src/tenant/$cf" --namespace "$ns" > "$out_manifest"; then
        ok "rendered: $cf -> ${team_name}-${rel_base}.yaml"
      else
        fail "render failed for $cf"
      fi
    done
    rm -rf "$HELM_HOME"
  else
    ok "no claims to render"
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
    ok "no manifests to validate"
  fi
fi

if stage secrets "Secret patterns in tracked files"; then
  python3 "${CI_DIR}/secret-scan.py" "$TI" || fail "secret scan"
fi

finish
