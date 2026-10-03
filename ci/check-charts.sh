#!/usr/bin/env bash
# CI for platform-charts (2026-10-03 Track A.4 required check; assessment L2-6 "no chart tests").
# Locally: `make ci-charts`.
#
#   lint     helm lint with each real orders-processor values file (not a placeholder image)
#   render   helm template with each values file -> kubeconform against the QueueBackedService CRD
#            schema kro generates from the RGD (the contract the chart must meet)
#   release  the release workflow's immutability rule, without pushing: a chart version already in
#            GHCR must have identical content, otherwise the PR must bump `version`
#   secrets  credential patterns in tracked files
#
# usage: ci/check-charts.sh [stage...]   with PLATFORM_CHARTS_DIR (default ../platform-charts)
CI_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
# shellcheck source=ci/lib.sh
source "$CI_LIB" "$@"
REPO=$(cd "${CI_DIR}/.." && pwd)
PCH=$(cd "${PLATFORM_CHARTS_DIR:-${REPO}/../platform-charts}" && pwd)
OUT="${LAB_CI_OUT:-$(mktemp -d)}"
mkdir -p "$OUT/manifests"
chmod 777 "$OUT" "$OUT/manifests"
app=$(clone orders-processor main)
mapfile -t values < <(cd "$app" && ls deploy/values-*.yaml)
helm() {
  docker run --rm -u "$(id -u):$(id -g)" -v "$PCH:/src/charts:ro" -v "$app:/src/app:ro" -v "$OUT:/out" \
    -v "${LAB_CI_CACHE}/helm:/cache" -e HELM_CACHE_HOME=/cache/cache -e HELM_CONFIG_HOME=/cache/config \
    -e HELM_DATA_HOME=/cache/data "${HELM_IMAGE}" "$@"
}

for chart in "$PCH"/charts/*/; do
  c=$(basename "$chart")
  if stage lint "helm lint ${c}"; then
    for v in "${values[@]}"; do
      helm lint "/src/charts/charts/$c" -f "/src/app/$v" >/dev/null || fail "helm lint $c with $v"
    done
    ok "$c lints with ${#values[@]} values files (${values[*]})"
  fi
  if stage render "Render ${c} with each values file"; then
    for v in "${values[@]}"; do
      n=$(basename "$v" .yaml)
      helm template "$n" "/src/charts/charts/$c" -f "/src/app/$v" > "$OUT/manifests/$c-$n.yaml" || fail "helm template $c with $v"
    done
    if kubeconform "$OUT/manifests"; then ok "$c renders a valid QueueBackedService for every values file"; else fail "kubeconform $c"; fi
  fi
  if stage release "Release immutability (no push)"; then
    name=$(awk '/^name:/ {print $2; exit}' "$chart/Chart.yaml")
    version=$(awk '/^version:/ {print $2; exit}' "$chart/Chart.yaml")
    mkdir -p "$OUT/pkg/local" "$OUT/pkg/remote" && chmod -R 777 "$OUT/pkg"
    helm package "/src/charts/charts/$c" -d /out/pkg >/dev/null
    set +e
    err=$(helm pull "oci://ghcr.io/brunobml/charts/${name}" --version "$version" -d /out/pkg/remote 2>&1 >/dev/null)
    rc=$?
    set -e
    if (( rc == 0 )); then
      tar -xzf "$OUT/pkg/${name}-${version}.tgz" -C "$OUT/pkg/local"
      tar -xzf "$OUT/pkg/remote/${name}-${version}.tgz" -C "$OUT/pkg/remote"
      if diff -r -q "$OUT/pkg/local/$name" "$OUT/pkg/remote/$name" >/dev/null; then
        ok "${name}:${version} is released with identical content (release would skip)"
      else
        diff -r -u "$OUT/pkg/remote/$name" "$OUT/pkg/local/$name" | head -40 || true
        fail "${name}:${version} is already released with different content: bump version in charts/$c/Chart.yaml"
      fi
    elif [[ "$err" == *": not found"* ]]; then
      ok "${name}:${version} is a new version (release would push it)"
    else
      fail "cannot tell whether ${name}:${version} exists in GHCR: ${err}"
    fi
  fi
done

if stage secrets "Secret patterns in tracked files"; then
  python3 "${CI_DIR}/secret-scan.py" "$PCH" || fail "secret scan"
fi

finish
