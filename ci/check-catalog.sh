#!/usr/bin/env bash
# CI for platform-catalog (2026-10-03 Track A.3). Locally: `make ci-catalog`.
#
#   cel         CEL of the ValidatingAdmissionPolicies compiled with the Kubernetes CEL environment;
#               Kyverno CEL policies and kro ${...} expressions parsed (labci cel; no cluster)
#   rgd-schema  RGD schemas compatible with the revision prod runs (kro breaking-change lesson D-14)
#   render      every Application of gitops-control-plane that uses platform-catalog (blueprints,
#               controller values, ACK credentials) rendered for both spokes from THIS catalog tree
#   schemas     kubeconform on everything rendered
#   alloy       spoke Alloy config parses
#   secrets     credential patterns in tracked files
#
# usage: ci/check-catalog.sh [stage...]   with PLATFORM_CATALOG_DIR (default ../platform-catalog)
CI_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
# shellcheck source=ci/lib.sh
source "$CI_LIB" "$@"
REPO=$(cd "${CI_DIR}/.." && pwd)
PC=$(cd "${PLATFORM_CATALOG_DIR:-${REPO}/../platform-catalog}" && pwd)
OUT="${LAB_CI_OUT:-$(mktemp -d)}"
mkdir -p "$OUT"

if stage cel "CEL expressions"; then
  labci cel "$PC"/blueprints/*.yaml || fail "CEL"
fi

if stage rgd-schema "RGD schema compatibility with prod"; then
  prod_rev=$(grep -E '^spoke-prod=' "$REPO/clusters/blueprint-revisions.env" | cut -d= -f2)
  promoted=$(clone platform-catalog "$prod_rev")
  python3 "${CI_DIR}/check-rgd-schema.py" "$PC/blueprints" "$promoted/blueprints" "$prod_rev" || fail "RGD schema"
fi

if stage render "Render the Applications that use platform-catalog"; then
  if labci appsets -clusters "${CI_DIR}/clusters.yaml" -revisions "$REPO/clusters/blueprint-revisions.env" \
       "$REPO"/applicationsets/kro-blueprints.yaml "$REPO"/applicationsets/addons-spoke*.yaml "$REPO"/applicationsets/platform-network.yaml > "$OUT/apps.yaml" \
     && python3 "${CI_DIR}/render.py" "$OUT/apps.yaml" --out "$OUT/manifests" --only-repo "${GH}/platform-catalog.git" \
       --repo "${GH}/platform-catalog.git=${PC}" --repo "${GH}/gitops-control-plane.git=${REPO}"; then
    ok "rendered $(ls "$OUT/manifests" | wc -l) Applications from this catalog tree (both spokes)"
  else
    fail "render"
  fi
fi

if stage schemas "Schema validation (kubeconform)"; then
  if [[ -d "$OUT/manifests" ]] && kubeconform "$OUT/manifests"; then ok "manifests valid"; else fail "kubeconform (run the render stage first)"; fi
fi

if stage alloy "Alloy configuration"; then
  alloy_syntax "$PC/controllers/observability/values-alloy.yaml"
fi

if stage secrets "Secret patterns in tracked files"; then
  python3 "${CI_DIR}/secret-scan.py" "$PC" || fail "secret scan"
fi

finish
