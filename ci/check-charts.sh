#!/usr/bin/env bash
# CI for platform-charts (2026-10-03 Track A.4 required check; assessment L2-6 "no chart tests").
# Locally: `make ci-charts`.
#
#   lint     helm lint with each values file: the chart's own fixtures in charts/<chart>/ci/*-values.yaml
#            (Helm chart-testing convention; e.g. team-cluster), otherwise each real orders-processor
#            values file (queue-backed-service; not a placeholder image)
#   render   helm template with each values file -> kubeconform against the CRD schema kro generates
#            from the RGD (QueueBackedService, TeamEKSCluster: the contract the chart must meet)
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
  # values files as paths inside the helm container
  mapfile -t fixtures < <(cd "$chart" && ls ci/*-values.yaml 2>/dev/null)
  if (( ${#fixtures[@]} )); then
    cvalues=("${fixtures[@]/#//src/charts/charts/$c/}")
  else
    cvalues=("${values[@]/#//src/app/}")
  fi
  if stage lint "helm lint ${c}"; then
    for v in "${cvalues[@]}"; do
      helm lint "/src/charts/charts/$c" -f "$v" >/dev/null || fail "helm lint $c with $v"
    done
    ok "$c lints with ${#cvalues[@]} values files (${cvalues[*]##*/})"
  fi
  if stage render "Render ${c} with each values file"; then
    rm -rf "$OUT/manifests/$c" && mkdir -p "$OUT/manifests/$c" && chmod 777 "$OUT/manifests/$c"
    for v in "${cvalues[@]}"; do
      n=$(basename "$v" .yaml)
      helm template "$n" "/src/charts/charts/$c" -f "$v" > "$OUT/manifests/$c/$n.yaml" || fail "helm template $c with $v"
    done
    if kubeconform "$OUT/manifests/$c"; then ok "$c renders a valid custom resource for every values file"; else fail "kubeconform $c"; fi
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
    elif [[ "$err" == *"403: denied"* ]] && [[ "$(curl -s -o /dev/null -w '%{http_code}' "https://ghcr.io/token?scope=repository:brunobml/charts/${name}:pull&service=ghcr.io")" == 403 ]]; then
      # GHCR answers "denied" (not "not found") for a package name that does not exist; lab charts are public
      ok "${name} is not in GHCR yet: first release of ${version} (release would push it; make the package public)"
    else
      fail "cannot tell whether ${name}:${version} exists in GHCR: ${err}"
    fi
  fi
done

if stage secrets "Secret patterns in tracked files"; then
  python3 "${CI_DIR}/secret-scan.py" "$PCH" || fail "secret scan"
fi

finish
