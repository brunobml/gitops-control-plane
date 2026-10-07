#!/usr/bin/env bash
# Disposable single-cluster sandbox for Lab 1 (learner on-ramp plan, Track B; guardrail G-2:
# learner RGDs, CRDs and ClusterRoles go here, never on the shared lab clusters).
#
#   learning-sandbox.sh up [--with-moto]   k3d cluster learn-sandbox + kro (the spokes' chart version and
#                                          values, rbac.mode: aggregation); --with-moto adds moto-sandbox
#                                          (127.0.0.1:5002) and the ACK SQS controller (the lab's version)
#   learning-sandbox.sh status
#   learning-sandbox.sh down               delete the cluster, its kube context, network and moto-sandbox
#
# Separate from the lab: own cluster name, API port 127.0.0.1:6560, Docker network k3d-learn-sandbox,
# moto port 5002, no Argo CD. The kube context k3d-learn-sandbox is added to your kubeconfig without
# switching to it: always pass --context k3d-learn-sandbox.
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

# chart versions as deployed to the spokes (applicationsets/addons-spoke.yaml)
chart_version() {
  awk -v a="$1" '$0 ~ "- addon: "a"$" {f=1} f && /chartVersion:/ {gsub(/"/, "", $2); print $2; exit}' \
    "${ROOT_DIR}/applicationsets/addons-spoke.yaml"
}

k() { kubectl --context "$CTX" "$@"; }

up() {
  local with_moto=false
  [[ "${1:-}" == "--with-moto" ]] && with_moto=true
  for t in k3d kubectl helm docker; do command -v "$t" >/dev/null || { echo "missing: $t" >&2; exit 1; }; done
  [[ -f "${CATALOG}/controllers/kro/values-kro.yaml" ]] || { echo "platform-catalog not found at ${CATALOG} (set REPOS_DIR)" >&2; exit 1; }
  local kro_version; kro_version=$(chart_version kro)
  [[ -n "$kro_version" ]] || { echo "kro chartVersion not found in applicationsets/addons-spoke.yaml" >&2; exit 1; }

  if k3d cluster list "$NAME" >/dev/null 2>&1; then
    echo "sandbox ${NAME} already exists (make sandbox-down first)" >&2; exit 1
  fi
  echo "==> k3d cluster ${NAME} (API 127.0.0.1:${API_PORT})"
  k3d cluster create "$NAME" --image "$K3S_IMAGE" --servers 1 --agents 0 --no-lb \
    --api-port "127.0.0.1:${API_PORT}" --kubeconfig-switch-context=false \
    --k3s-arg "--disable=traefik@server:0" --k3s-arg "--disable=metrics-server@server:0" --wait >/dev/null

  echo "==> kro ${kro_version} (platform-catalog values: rbac.mode aggregation)"
  k create namespace kro >/dev/null
  k label namespace kro pod-security.kubernetes.io/enforce=restricted >/dev/null
  helm --kube-context "$CTX" install kro oci://registry.k8s.io/kro/charts/kro --version "$kro_version" \
    -n kro -f "${CATALOG}/controllers/kro/values-kro.yaml" >/dev/null

  if $with_moto; then
    local sqs_version; sqs_version=$(chart_version ack-sqs)
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
  fi
  k -n kro rollout status deploy --timeout=180s >/dev/null
  echo "✔ sandbox ready: kubectl --context ${CTX} ...   (remove with: make sandbox-down)"
}

status() {
  k3d cluster list "$NAME" 2>/dev/null || { echo "no sandbox"; return 0; }
  k get pods -A --no-headers | awk '{print "  " $1 "/" $2 " " $4}'
  k get resourcegraphdefinitions 2>/dev/null || true
  docker ps --filter "name=^${MOTO}$" --format '  {{.Names}} {{.Status}} {{.Ports}}'
}

down() {
  docker rm -f "$MOTO" >/dev/null 2>&1 || true
  if k3d cluster list "$NAME" >/dev/null 2>&1; then
    k3d cluster delete "$NAME" >/dev/null
  fi
  # verify: nothing of the sandbox is left
  local left=""
  k3d cluster list "$NAME" >/dev/null 2>&1 && left+=" cluster"
  docker ps -a --format '{{.Names}}' | grep -Eq "^(k3d-${NAME}-|${MOTO}$)" && left+=" containers"
  docker network ls --format '{{.Name}}' | grep -qx "k3d-${NAME}" && left+=" network"
  kubectl config get-contexts -o name | grep -qx "$CTX" && left+=" kube-context"
  if [[ -n "$left" ]]; then echo "✘ sandbox leftovers:${left}" >&2; exit 1; fi
  echo "✔ sandbox removed (no cluster, container, network or kube context left)"
}

case "${1:-}" in
  up) shift; up "$@" ;;
  status) status ;;
  down) down ;;
  *) echo "usage: $0 up [--with-moto] | status | down" >&2; exit 2 ;;
esac
