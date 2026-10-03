# shellcheck shell=bash
# Shared helpers for the lab CI checks (2026-10-03 Track A). Sourced by ci/check-*.sh.
# Runs the same way locally (`make ci`, ...) and in GitHub Actions: tools are the digest-pinned
# images in ci/tools.env; only bash, git, docker, python3 (+PyYAML, jsonschema) and Go are needed.
set -euo pipefail

CI_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=ci/tools.env
source "${CI_DIR}/tools.env"
export LAB_CI_CACHE="${LAB_CI_CACHE:-$HOME/.cache/lab-ci}"
mkdir -p "${LAB_CI_CACHE}/kubeconform" "${LAB_CI_CACHE}/helm"
GH=https://github.com/brunobml

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
STAGES=("$@")
FAILED=0
stage() {  # stage <id> <title>: true if this stage should run (all when no stage was named)
  if (( ${#STAGES[@]} )) && [[ ! " ${STAGES[*]} " == *" $1 "* ]]; then return 1; fi
  echo -e "\n${YELLOW}[$1] $2${NC}"
}
ok()   { echo -e "${GREEN}✔ $*${NC}"; }
fail() { echo -e "${RED}✘ $*${NC}" >&2; FAILED=$((FAILED + 1)); }
finish() {
  if (( FAILED )); then echo -e "\n${RED}✘ ${FAILED} check(s) failed${NC}" >&2; exit 1; fi
  echo -e "\n${GREEN}✔ all checks passed${NC}"
}

# labci: build once per source hash.
labci() {
  local h bin
  h=$(cat "${CI_DIR}"/labci/*.go "${CI_DIR}/labci/go.sum" | sha256sum | cut -c1-16)
  bin="${LAB_CI_CACHE}/labci-${h}"
  if [[ ! -x "$bin" ]]; then
    (cd "${CI_DIR}/labci" && CGO_ENABLED=0 go build -trimpath -o "$bin" .) >&2
  fi
  "$bin" "$@"
}

# clone <repo name> <revision>: prints a checkout of github.com/brunobml/<repo> at <revision>.
clone() {
  local d="${LAB_CI_CACHE}/git/$1@$2"
  if [[ ! -d "$d/.git" ]]; then
    git init -q "$d"
  fi
  git -C "$d" fetch -q --depth 1 "${GH}/$1.git" "$2" >&2
  git -C "$d" checkout -q -f FETCH_HEAD >&2
  echo "$d"
}

# kubeconform <dir>: validates every manifest under <dir> (built-in kinds from the pinned
# kubernetes-json-schema commit, custom resources from ci/schemas/). Missing schemas are errors,
# except CustomResourceDefinition objects themselves (vendor CRDs shipped by charts).
kubeconform() {
  docker run --rm -u "$(id -u):$(id -g)" -v "${CI_DIR}/schemas:/schemas:ro" -v "$1:/m:ro" \
    -v "${LAB_CI_CACHE}/kubeconform:/cache" "${KUBECONFORM_IMAGE}" \
    -summary -output text -skip CustomResourceDefinition -kubernetes-version "${KUBERNETES_VERSION}" \
    -cache /cache -schema-location "${K8S_SCHEMA_LOCATION}" \
    -schema-location '/schemas/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' /m
}

# alloy_syntax <values file>...: `alloy fmt` parses the embedded config (alloy.configMap.content).
alloy_syntax() {
  local f
  for f in "$@"; do
    if python3 -c 'import sys,yaml; print(yaml.safe_load(open(sys.argv[1]))["alloy"]["configMap"]["content"], end="")' "$f" \
        | docker run --rm -i "${ALLOY_IMAGE}" fmt >/dev/null; then
      ok "Alloy config parses: ${f}"
    else
      fail "Alloy config does not parse: ${f}"
    fi
  done
}
