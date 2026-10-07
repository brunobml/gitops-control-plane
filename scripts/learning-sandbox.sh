#!/usr/bin/env bash
# Disposable single-cluster sandbox for Lab 1 (learner on-ramp plan, Track B; guardrail G-2:
# learner RGDs, CRDs and ClusterRoles go here, never on the shared lab clusters).
#
#   learning-sandbox.sh up [--with-moto]   k3d cluster learn-sandbox + kro (the spokes' chart version and
#                                          values, rbac.mode: aggregation). --with-moto adds moto-sandbox
#                                          (127.0.0.1:5002) and the ACK SQS controller (the lab's version);
#                                          on an existing kro-only sandbox it adds only those (Lab 1 step 6)
#   learning-sandbox.sh status
#   learning-sandbox.sh down               delete the cluster, its kube context, network and moto-sandbox,
#                                          then verify that nothing is left
#
# Separate from the lab: own cluster name, API port 127.0.0.1:6560, Docker network k3d-learn-sandbox,
# moto port 5002, no Argo CD. The kube context k3d-learn-sandbox is added to your kubeconfig without
# switching to it: always pass --context k3d-learn-sandbox.
#
# Fail closed (validation-04 V3-1): every inspection of Docker, k3d and kubeconfig must succeed. A
# failed read is "could not verify" (exit 1), never "absent".
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPOS_DIR="${REPOS_DIR:-$(dirname "$ROOT_DIR")}"
CATALOG="${REPOS_DIR}/platform-catalog"
NAME=learn-sandbox
CTX="k3d-${NAME}"
API_PORT=6560
MOTO=moto-sandbox
MOTO_PORT=5002
# same images as the lab (scripts/setup-hub-spoke.sh, scripts/start-hub-spoke.sh)
K3S_IMAGE=rancher/k3s:v1.35.5-k3s1
MOTO_IMAGE=motoserver/moto@sha256:91fd602a21f49cf9eb82fdf474015a3c131d40104c8297ea6a2ca920708ae32c

die() { echo "✘ $*" >&2; exit 1; }

# chart versions as deployed to the spokes (applicationsets/addons-spoke.yaml)
chart_version() {
  awk -v a="$1" '$0 ~ "- addon: "a"$" {f=1} f && /chartVersion:/ {gsub(/"/, "", $2); print $2; exit}' \
    "${ROOT_DIR}/applicationsets/addons-spoke.yaml"
}

k() { kubectl --context "$CTX" "$@"; }

# --- inspections: print the names found; exit 1 if the read itself fails ----------------------
k3d_clusters() {
  local out names
  out=$(k3d cluster list -o json) || die "could not verify: k3d cluster list failed"
  names=$(jq -r '.[].name' <<<"$out") || die "could not verify: k3d cluster list returned no JSON"
  printf '%s\n' "$names"
}
docker_containers() { docker ps -a --format '{{.Names}}' || die "could not verify: docker ps failed"; }
docker_networks()   { docker network ls --format '{{.Name}}' || die "could not verify: docker network ls failed"; }
kube_contexts()     { kubectl config get-contexts -o name || die "could not verify: kubectl config get-contexts failed"; }
# has <list> <name>: exact line match in an already captured list. Capture each list with a plain
# assignment (x=$(k3d_clusters)) so set -e stops on a failed read; inside "$(...)" as an argument
# the failure would be lost.
has() { grep -qx -- "$2" <<<"$1"; }

install_moto() {
  local sqs_version; sqs_version=$(chart_version ack-sqs)
  [[ -n "$sqs_version" ]] || die "ack-sqs chartVersion not found in applicationsets/addons-spoke.yaml"
  echo "==> ${MOTO} (127.0.0.1:${MOTO_PORT}) and ACK SQS ${sqs_version}"
  docker run -d --name "$MOTO" --network "k3d-${NAME}" -p "127.0.0.1:${MOTO_PORT}:5000" \
    "$MOTO_IMAGE" -p5000 -H0.0.0.0 >/dev/null
  k create namespace ack-system >/dev/null
  k label namespace ack-system pod-security.kubernetes.io/enforce=restricted >/dev/null
  k -n ack-system create secret generic ack-aws-creds \
    --from-literal=credentials=$'[default]\naws_access_key_id = mock-key\naws_secret_access_key = mock-secret' >/dev/null
  helm --kube-context "$CTX" install ack-sqs-controller oci://public.ecr.aws/aws-controllers-k8s/sqs-chart \
    --version "$sqs_version" -n ack-system -f "${CATALOG}/controllers/ack/values-sqs.yaml" \
    --set aws.endpoint_url="http://${MOTO}:5000" >/dev/null
  k -n ack-system rollout status deploy --timeout=180s >/dev/null
}

up() {
  local with_moto=false
  [[ "${1:-}" == "--with-moto" ]] && with_moto=true
  for t in k3d kubectl helm docker jq; do command -v "$t" >/dev/null || die "missing: $t"; done
  [[ -f "${CATALOG}/controllers/kro/values-kro.yaml" ]] || die "platform-catalog not found at ${CATALOG} (set REPOS_DIR)"

  local clusters containers
  clusters=$(k3d_clusters)
  containers=$(docker_containers)
  if has "$clusters" "$NAME"; then
    # Lab 1 step 6 on a kro-only sandbox: add moto + ACK, keep the learner's work
    if $with_moto && ! has "$containers" "$MOTO"; then
      install_moto
      echo "✔ moto-sandbox and ACK SQS added to the existing sandbox"
      return 0
    fi
    die "sandbox ${NAME} already exists$($with_moto && echo ' (with moto)') (make sandbox-down first)"
  fi

  local kro_version; kro_version=$(chart_version kro)
  [[ -n "$kro_version" ]] || die "kro chartVersion not found in applicationsets/addons-spoke.yaml"
  echo "==> k3d cluster ${NAME} (API 127.0.0.1:${API_PORT})"
  k3d cluster create "$NAME" --image "$K3S_IMAGE" --servers 1 --agents 0 --no-lb \
    --api-port "127.0.0.1:${API_PORT}" --kubeconfig-switch-context=false \
    --k3s-arg "--disable=traefik@server:0" --k3s-arg "--disable=metrics-server@server:0" --wait >/dev/null

  echo "==> kro ${kro_version} (platform-catalog values: rbac.mode aggregation)"
  k create namespace kro >/dev/null
  k label namespace kro pod-security.kubernetes.io/enforce=restricted >/dev/null
  helm --kube-context "$CTX" install kro oci://registry.k8s.io/kro/charts/kro --version "$kro_version" \
    -n kro -f "${CATALOG}/controllers/kro/values-kro.yaml" >/dev/null
  k -n kro rollout status deploy --timeout=180s >/dev/null
  if $with_moto; then install_moto; fi
  echo "✔ sandbox ready: kubectl --context ${CTX} ...   (remove with: make sandbox-down)"
}

status() {
  local clusters containers
  clusters=$(k3d_clusters)
  containers=$(docker_containers)
  if ! has "$clusters" "$NAME"; then echo "no sandbox"; return 0; fi
  k get pods -A --no-headers | awk '{print "  " $1 "/" $2 " " $4}'
  k get resourcegraphdefinitions 2>/dev/null || true
  if has "$containers" "$MOTO"; then echo "  ${MOTO}: 127.0.0.1:${MOTO_PORT}"; fi
}

down() {
  local clusters containers networks contexts left=""
  containers=$(docker_containers)
  if has "$containers" "$MOTO"; then
    docker rm -f "$MOTO" >/dev/null || die "could not remove container ${MOTO}"
  fi
  clusters=$(k3d_clusters)
  if has "$clusters" "$NAME"; then
    k3d cluster delete "$NAME" >/dev/null || die "k3d cluster delete ${NAME} failed"
  fi
  # verify: every read must succeed, and none may show a sandbox object
  clusters=$(k3d_clusters); containers=$(docker_containers)
  networks=$(docker_networks); contexts=$(kube_contexts)
  has "$clusters" "$NAME" && left+=" cluster"
  grep -Eq "^(k3d-${NAME}-.*|${MOTO})$" <<<"$containers" && left+=" containers"
  has "$networks" "k3d-${NAME}" && left+=" network"
  has "$contexts" "$CTX" && left+=" kube-context"
  [[ -z "$left" ]] || die "sandbox leftovers:${left}"
  echo "✔ sandbox removed (no cluster, container, network or kube context left)"
}

case "${1:-}" in
  up) shift; up "$@" ;;
  status) status ;;
  down) down ;;
  *) echo "usage: $0 up [--with-moto] | status | down" >&2; exit 2 ;;
esac
