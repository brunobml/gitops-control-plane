#!/usr/bin/env bash
# make test-lab1: Lab 1 end to end in a fresh sandbox (learner on-ramp plan, Track B).
# Creates the sandbox (with moto), plays every step of docs/lab-1-write-a-blueprint.md with the
# reference solution in docs/lab-1-solution/, asserts each expected result and each expected
# failure message, then removes the sandbox. Never touches the lab clusters (G-2). Local only:
# CI has no k3d (owner decision O-5).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SOL="${ROOT_DIR}/docs/lab-1-solution"
SANDBOX="${ROOT_DIR}/scripts/learning-sandbox.sh"
CTX=k3d-learn-sandbox
K="kubectl --context ${CTX}"
NS=lab1
work=$(mktemp -d)
passed=0
# shellcheck source=tests/lab1-lib.bash
source "${ROOT_DIR}/tests/lab1-lib.bash"
exec 3>&2   # fail() reports on fd 3: wait_for silences its predicates' stderr

ok()   { passed=$((passed + 1)); echo "  ✔ $*"; }
fail() { echo "  ✘ $*" >&3; exit 1; }
# wait_for <seconds> <description> <command...>: poll until the command succeeds
wait_for() {
  local limit=$1 what=$2; shift 2
  local t0; t0=$(date +%s)
  until "$@" >/dev/null 2>&1; do
    (( $(date +%s) - t0 > limit )) && fail "${what} (not within ${limit} s)"
    sleep 2
  done
  ok "${what} ($(( $(date +%s) - t0 )) s)"
}
cond()  { $K get rgd web-greeting -o jsonpath="{.status.conditions[?(@.type==\"$1\")].$2}"; }
istate() { $K -n "$NS" get webgreeting "$1" -o jsonpath='{.status.state}/{.status.conditions[?(@.type=="Ready")].status}'; }
is_active() { [[ "$(istate "$1")" == "ACTIVE/True" ]]; }
rgd_active() { [[ "$($K get rgd web-greeting -o jsonpath='{.status.state}')" == "Active" ]]; }
cond_has() { [[ "$(cond "$1" status)" == "$2" && "$(cond "$1" message)" == *"$3"* ]]; }
# Fail closed (validation-04 V3-2): an "absent" check must come from a successful read that also
# shows a control object; a failed read aborts the test instead of counting as "absent".
services() { local out; out=$($K -n "$NS" get service -o name) || fail "cannot list services in ${NS}"; printf '%s\n' "$out"; }
service_hello_gone() {
  local svcs; svcs=$(services)
  grep -qx service/hello-public <<<"$svcs" || fail "control Service hello-public missing"
  ! grep -qx service/hello <<<"$svcs"
}
policy_denies_9() {
  local out
  if out=$($K -n "$NS" patch webgreeting hello --type merge -p '{"spec":{"replicas":9}}' --dry-run=server 2>&1); then return 1; fi
  [[ "$out" == *"spec.replicas must be between 1 and 5"* ]]
}
control_queue_listed() { [[ "$(queue_state lab1-hello-public-jobs lab1-hello-public-jobs)" == present ]]; }
queue_gone() {
  case "$(queue_state lab1-hello-jobs lab1-hello-public-jobs)" in
    absent) return 0 ;;
    present) return 1 ;;
    *) fail "cannot read the queues in moto-sandbox (a read error is not proof of deletion)" ;;
  esac
}

contexts_before=$(kubectl config get-contexts -o name | sort | tr '\n' ' ')
current_before=$(kubectl config current-context 2>/dev/null || true)
cleanup() {
  local rc=$?
  bash "$SANDBOX" down >/dev/null 2>&1 || rc=1
  rm -rf "$work"
  exit "$rc"
}

echo "[0] sandbox"
k3d cluster list learn-sandbox >/dev/null 2>&1 && fail "a sandbox already exists; run make sandbox-down first (test-lab1 starts from a clean state)"
trap cleanup EXIT
bash "$SANDBOX" up >/dev/null
containers=$(docker ps -a --format '{{.Names}}') || fail "docker ps failed"
grep -qx moto-sandbox <<<"$containers" && fail "kro-only sandbox started moto-sandbox"
ok "sandbox up, kro only (the default; moto is added for step 6)"
$K create namespace "$NS" >/dev/null
$K label namespace "$NS" pod-security.kubernetes.io/enforce=restricted >/dev/null

echo "[1] the doc's step-1 blueprint without permissions, then the ClusterRole"
# the YAML a learner copies from the doc is what is applied here (blocks marked <!-- lab1-file: ... -->)
python3 - "${ROOT_DIR}/docs/lab-1-write-a-blueprint.md" "$work" <<'PY'
import re, sys
doc, out = sys.argv[1], sys.argv[2]
blocks = dict(re.findall(r"<!-- lab1-file: (\S+) -->\n```yaml\n(.*?)```", open(doc).read(), re.S))
for name in ("step1-rgd", "step1-instance", "step1-rbac-instance", "step1-rbac-children"):
    open(f"{out}/{name}.yaml", "w").write(blocks[name])
open(f"{out}/step1-rbac.yaml", "w").write(blocks["step1-rbac-instance"] + blocks["step1-rbac-children"])
PY
$K apply -f "$work/step1-rgd.yaml" >/dev/null
wait_for 60 "kro created the CRD webgreetings.kro.run" $K get crd webgreetings.kro.run
$K wait --for=condition=Established crd/webgreetings.kro.run --timeout=60s >/dev/null
$K apply -f "$work/step1-instance.yaml" >/dev/null
wait_for 180 "without RBAC: ControllerReady=False (cache sync timeout: kro may not watch webgreetings)" \
  cond_has ControllerReady False "cache sync timeout"
$K apply -f "$work/step1-rbac-instance.yaml" >/dev/null
wait_for 120 "instance kind only: hello ERROR, deployments forbidden" bash -c \
  "[[ \"\$($K -n $NS get webgreeting hello -o jsonpath='{.status.state} {.status.conditions[?(@.type==\"Ready\")].message}')\" == ERROR*'deployments.apps \"hello\" is forbidden'* ]]"
$K apply -f "$work/step1-rbac.yaml" >/dev/null
wait_for 120 "with the child kinds: hello ACTIVE/Ready" is_active hello
$K -n "$NS" rollout status deployment/hello --timeout=120s >/dev/null   # no readyWhen yet: Ready precedes the pod
page=$($K -n "$NS" exec deploy/hello -- wget -qO- localhost:8000)
[[ "$page" == "hello from my first blueprint" ]] && ok "the page serves spec.message" || fail "page: '${page}'"

echo "[2] dependency order"
order=$($K get rgd web-greeting -o jsonpath='{.status.topologicalOrder}')
[[ "$order" == '["deployment","config"]' ]] && ok "no reference: topologicalOrder ${order} (declaration order)" || fail "topologicalOrder ${order}"
sed 's|configMap: {name: "${schema.metadata.name}-page"}|configMap: {name: "${config.metadata.name}"}|' "$work/step1-rgd.yaml" > "$work/step2-rgd.yaml"
grep -q 'config.metadata.name' "$work/step2-rgd.yaml" || fail "step 2 edit did not apply to the doc's RGD"
$K apply -f "$work/step2-rgd.yaml" >/dev/null
wait_for 60 "with the reference: topologicalOrder [\"config\",\"deployment\"]" bash -c \
  "[[ \"\$($K get rgd web-greeting -o jsonpath='{.status.topologicalOrder}')\" == '[\"config\",\"deployment\"]' ]]"
echo "  · hello right after the new revision: $(istate hello)"
wait_for 60 "hello ACTIVE/Ready on the new revision" is_active hello

echo "[3] includeWhen (the reference solution from here on)"
$K apply -f "${SOL}/rgd.yaml" >/dev/null
wait_for 60 "solution RGD Active" rgd_active
wait_for 60 "CRD has the new field spec.expose" bash -c \
  "$K get crd webgreetings.kro.run -o jsonpath='{.spec.versions[0].schema.openAPIV3Schema.properties.spec.properties.expose.type}' | grep -qx boolean"
$K apply -f "${SOL}/instances.yaml" >/dev/null
sleep 20
state=$($K -n "$NS" get webgreeting hello-public -o jsonpath='{.status.state}') || fail "cannot read hello-public"
[[ -z "$state" ]] && ok "without services RBAC: hello-public has no status" || fail "hello-public has status '${state}' without services RBAC"
kro_log=$($K -n kro logs deploy/kro --since=2m)   # not piped into grep -q: SIGPIPE + pipefail
[[ "$kro_log" == *"services is forbidden"* ]] && ok "kro log: services is forbidden" || fail "no 'services is forbidden' in the kro log"
$K apply -f "${SOL}/rbac.yaml" >/dev/null
wait_for 120 "with services: hello-public ACTIVE/Ready" is_active hello-public
order=$($K get rgd web-greeting -o jsonpath='{.status.topologicalOrder}')
[[ "$order" == '["config","deployment","service"]' ]] && ok "solution topologicalOrder ${order}" || fail "topologicalOrder ${order}"
svcs=$(services)
grep -qx service/hello-public <<<"$svcs" && ok "expose: true → Service hello-public" || fail "no Service hello-public"
grep -qx service/hello <<<"$svcs" && fail "Service hello exists although expose is false" || ok "expose: false → no Service hello"
$K -n "$NS" patch webgreeting hello --type merge -p '{"spec":{"expose":true}}' >/dev/null
wait_for 30 "expose toggled on → Service hello created" $K -n "$NS" get service hello
$K -n "$NS" patch webgreeting hello --type merge -p '{"spec":{"expose":false}}' >/dev/null
wait_for 30 "expose toggled off → Service hello deleted" service_hello_gone

echo "[4] readyWhen and status"
$K -n "$NS" patch webgreeting hello --type merge -p '{"spec":{"replicas":3}}' >/dev/null
wait_for 120 "replicas 3 → status.availableReplicas 3 and Ready" \
  bash -c "[[ \"\$($K -n $NS get webgreeting hello -o jsonpath='{.status.availableReplicas}/{.status.state}/{.status.conditions[?(@.type==\"Ready\")].status}')\" == 3/ACTIVE/True ]]"

echo "[5a] a reference to a field that does not exist"
sed 's/${config.metadata.name}/${config.metadata.nmae}/' "${SOL}/rgd.yaml" > "$work/rgd-typo.yaml"
$K apply -f "$work/rgd-typo.yaml" >/dev/null
wait_for 60 "GraphAccepted=False: undefined field 'nmae'" cond_has GraphAccepted False "undefined field 'nmae'"
is_active hello && ok "existing instances keep running" || fail "hello not ACTIVE during the bad revision"
$K apply -f "${SOL}/rgd.yaml" >/dev/null
wait_for 60 "fixed RGD Active again" rgd_active

echo "[5b] a constraint added to an existing field (incident D-14)"
sed 's/replicas: integer | default=1/replicas: integer | default=1 minimum=1 maximum=5/' "${SOL}/rgd.yaml" > "$work/rgd-breaking.yaml"
$K apply -f "$work/rgd-breaking.yaml" >/dev/null
wait_for 60 "KindReady=False: breaking changes detected" cond_has KindReady False "breaking changes detected"
$K apply -f "${SOL}/rgd.yaml" >/dev/null
wait_for 60 "original RGD Active again" rgd_active
$K apply -f "${SOL}/policy.yaml" >/dev/null
wait_for 30 "policy registered (server dry-run denies replicas 9 with the policy message)" policy_denies_9
if out=$($K -n "$NS" patch webgreeting hello --type merge -p '{"spec":{"replicas":9}}' 2>&1); then
  fail "replicas 9 was accepted"
fi
[[ "$out" == *"spec.replicas must be between 1 and 5"* ]] && ok "ValidatingAdmissionPolicy denies replicas 9" || fail "unexpected: ${out}"
$K -n "$NS" patch webgreeting hello --type merge -p '{"spec":{"replicas":2}}' >/dev/null && ok "replicas 2 accepted"

echo "[6] stretch: an ACK Queue child (moto added to the running sandbox, as in the doc)"
bash "$SANDBOX" up --with-moto >/dev/null
ok "make sandbox-up WITH_MOTO=1 added moto-sandbox and ACK SQS; the learner's work is kept"
is_active hello && is_active hello-public && ok "instances still ACTIVE after adding moto" || fail "instances changed by adding moto"
$K apply -f "${SOL}/rbac-queue.yaml" -f "${SOL}/rgd-with-queue.yaml" >/dev/null
wait_for 120 "status.queueURL set" bash -c "[[ -n \"\$($K -n $NS get webgreeting hello -o jsonpath='{.status.queueURL}')\" ]]"
[[ "$($K -n "$NS" get configmap hello-page -o jsonpath='{.data.queue-url}')" == http://moto-sandbox:5000/*/lab1-hello-jobs ]] \
  && ok "ConfigMap carries the queue URL" || fail "ConfigMap queue-url missing"
moto sqs get-queue-url --queue-name lab1-hello-jobs >/dev/null && ok "queue lab1-hello-jobs exists in moto-sandbox"

echo "[7] delete cascades to the cloud"
wait_for 120 "control queue lab1-hello-public-jobs listed" control_queue_listed
[[ "$(queue_state lab1-hello-jobs lab1-hello-public-jobs)" == present ]] || fail "queue lab1-hello-jobs not readable as present before the delete"
$K -n "$NS" delete webgreeting hello --timeout=120s >/dev/null
wait_for 120 "queue lab1-hello-jobs deleted from moto-sandbox (control queue lab1-hello-public-jobs still listed)" queue_gone
names=$($K -n "$NS" get deploy,configmap,service -o name) || fail "cannot list hello's children"
grep -qx deployment.apps/hello-public <<<"$names" || fail "control Deployment hello-public missing"
grep -Eq '/hello(-page)?$' <<<"$names" && fail "hello children left: ${names}" || ok "kro removed hello's children (hello-public kept)"

echo "[8] teardown"
trap - EXIT
bash "$SANDBOX" down >/dev/null && ok "sandbox removed (no cluster, container, network or kube context)"
rm -rf "$work"
[[ "$(kubectl config get-contexts -o name | sort | tr '\n' ' ')" == "$contexts_before" ]] && ok "kube contexts unchanged" || fail "kube contexts changed"
[[ "$(kubectl config current-context 2>/dev/null || true)" == "$current_before" ]] && ok "current context unchanged (${current_before})" || fail "current context changed"
echo "✔ test-lab1: ${passed} checks passed"
