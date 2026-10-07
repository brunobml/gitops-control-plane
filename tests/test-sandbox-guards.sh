#!/usr/bin/env bash
# Negative tests for the Lab 1 sandbox guards (validation-04 V3-1, V3-2). No Docker or cluster:
# docker, k3d, kubectl and aws are replaced by stubs on PATH whose answers and failures are set
# per case. Run by `make ci` (stage sandbox-guards).
#
#   sandbox-down must exit 1 when any inspection fails (never "removed" because a read failed),
#   when a leftover is seen, or when the removal fails; exit 0 only on successful clean reads.
#   queue_state must answer "error", not "absent", when the AWS read fails or cannot be trusted.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
stubs=$(mktemp -d)
trap 'rm -rf "$stubs"' EXIT
failed=0

cat > "$stubs/stub" <<'EOF'
#!/usr/bin/env bash
# behaviour from STUB_* variables; STUB_FAIL lists the operations that exit 77
op="$(basename "$0") $*"
fails() { [[ " ${STUB_FAIL:-} " == *" $1 "* ]]; }
case "$op" in
  "k3d cluster list -o json")          fails k3d-list && exit 77; printf '%s' "${STUB_K3D-[]}" ;;
  "k3d cluster delete "*)              fails k3d-delete && exit 77; exit 0 ;;
  "docker ps -a "*)                    fails docker-ps && exit 77; printf '%s' "${STUB_CONTAINERS:-}" ;;
  "docker network ls "*)               fails docker-net && exit 77; printf '%s' "${STUB_NETWORKS:-}" ;;
  "docker rm "*)                       fails docker-rm && exit 77; exit 0 ;;
  "kubectl config get-contexts -o name") fails kubectl && exit 77; printf '%s' "${STUB_CONTEXTS:-}" ;;
  "aws "*)                             fails aws && exit 77; printf '%s' "${STUB_AWS:-}" ;;
  *) echo "stub: unexpected call: $op" >&2; exit 99 ;;
esac
EOF
chmod +x "$stubs/stub"
for t in docker k3d kubectl aws; do ln -s stub "$stubs/$t"; done

# case <name> <expected rc: 0|nonzero> <expected output regex> [VAR=value ...]
case_down() {
  local name=$1 want=$2 re=$3; shift 3
  local out rc=0
  out=$(env "$@" PATH="$stubs:$PATH" bash "$ROOT_DIR/scripts/learning-sandbox.sh" down 2>&1) || rc=$?
  if { [[ "$want" == 0 && $rc -eq 0 ]] || [[ "$want" != 0 && $rc -ne 0 ]]; } && [[ "$out" =~ $re ]] \
     && { [[ "$want" == 0 ]] || [[ "$out" != *"sandbox removed"* ]]; }; then
    echo "  ✔ down, ${name}: rc ${rc}"
  else
    echo "  ✘ down, ${name}: rc ${rc}, output: ${out}"; failed=1
  fi
}

clean=(STUB_K3D='[{"name":"hub-cluster"}]' STUB_CONTAINERS=$'k3d-hub-cluster-server-0\nmoto-cloud' \
       STUB_NETWORKS=$'bridge\nk3d-hub-cluster' STUB_CONTEXTS=$'k3d-hub-cluster')
case_down "clean reads, nothing left"      0       "sandbox removed"           "${clean[@]}"
case_down "every read fails (exit 77)"     nonzero "could not verify"          "${clean[@]}" STUB_FAIL="k3d-list docker-ps docker-net kubectl"
case_down "docker ps fails"                nonzero "could not verify: docker ps" "${clean[@]}" STUB_FAIL="docker-ps"
case_down "k3d cluster list fails"         nonzero "could not verify: k3d"     "${clean[@]}" STUB_FAIL="k3d-list"
case_down "docker network ls fails"        nonzero "could not verify: docker network" "${clean[@]}" STUB_FAIL="docker-net"
case_down "kube contexts unreadable"       nonzero "could not verify: kubectl" "${clean[@]}" STUB_FAIL="kubectl"
case_down "k3d answers no JSON"            nonzero "could not verify: k3d cluster list returned no JSON array" "${clean[@]}" STUB_K3D="FATA no nodes"
case_down "k3d answers nothing, exit 0"    nonzero "could not verify: k3d cluster list returned nothing" "${clean[@]}" STUB_K3D=""
case_down "k3d answers a JSON object"      nonzero "could not verify: k3d cluster list returned no JSON array" "${clean[@]}" STUB_K3D="{}"
case_down "all reads empty, exit 0 (V3-4)" nonzero "could not verify" STUB_K3D="" STUB_CONTAINERS="" STUB_NETWORKS="" STUB_CONTEXTS=""
case_down "k3d answers [] (no clusters)"   0       "sandbox removed"           "${clean[@]}" STUB_K3D="[]"
case_down "network left behind"            nonzero "leftovers: network"        "${clean[@]}" STUB_NETWORKS=$'bridge\nk3d-learn-sandbox'
case_down "kube context left behind"       nonzero "leftovers: kube-context"   "${clean[@]}" STUB_CONTEXTS=$'k3d-hub-cluster\nk3d-learn-sandbox'
case_down "moto-sandbox cannot be removed" nonzero "could not remove container moto-sandbox" \
  "${clean[@]}" STUB_CONTAINERS=$'moto-cloud\nmoto-sandbox' STUB_FAIL="docker-rm"
case_down "cluster delete fails"           nonzero "k3d cluster delete learn-sandbox failed" \
  STUB_K3D='[{"name":"learn-sandbox"}]' STUB_CONTAINERS="" STUB_NETWORKS="" STUB_CONTEXTS="" STUB_FAIL="k3d-delete"

# queue_state <queue> <control>: the V3-2 predicate of make test-lab1
case_queue() {
  local name=$1 want=$2; shift 2
  local got
  got=$(env "$@" PATH="$stubs:$PATH" bash -c "source '$ROOT_DIR/tests/lab1-lib.bash'; queue_state lab1-hello-jobs lab1-hello-public-jobs")
  if [[ "$got" == "$want" ]]; then echo "  ✔ queue_state, ${name}: ${got}"; else echo "  ✘ queue_state, ${name}: ${got}, want ${want}"; failed=1; fi
}
both='{"QueueUrls": ["http://localhost:5002/123456789012/lab1-hello-jobs", "http://localhost:5002/123456789012/lab1-hello-public-jobs"]}'
control='{"QueueUrls": ["http://localhost:5002/123456789012/lab1-hello-public-jobs"]}'
case_queue "AWS read fails (exit 77)"       error   STUB_FAIL="aws"
case_queue "empty answer (no control queue)" error  STUB_AWS=""
case_queue "queue and control listed"       present STUB_AWS="$both"
case_queue "only the control listed"        absent  STUB_AWS="$control"

if (( failed )); then echo "✘ sandbox guard tests failed"; exit 1; fi
echo "✔ sandbox guard tests passed"
