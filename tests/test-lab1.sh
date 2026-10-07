#!/usr/bin/env bash
# make test-lab1: Lab 1 end to end in a fresh sandbox (learner on-ramp plan, Track B).
# Runs the copy-and-paste blocks of docs/lab-1-write-a-blueprint.md **verbatim**, in order (each
# block is marked <!-- doc-test: covered by="check:test-lab1" id="..." -->), and after each block
# asserts the result the doc promises, including every expected failure message. Only two
# substitutions: ~/repos/gitops-control-plane -> this checkout, ~/lab1-work -> a temp directory.
# Every block of the doc must be run here (checked). Never touches the lab clusters (G-2). Local
# only: CI has no k3d (owner decision O-5).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DOC="${ROOT_DIR}/docs/lab-1-write-a-blueprint.md"
SOL="${ROOT_DIR}/docs/lab-1-solution"
SANDBOX="${ROOT_DIR}/scripts/learning-sandbox.sh"
CTX=k3d-learn-sandbox
K="kubectl --context ${CTX}"
NS=lab1
work=$(mktemp -d)
files="${work}/lab1-work"   # the learner's ~/lab1-work
passed=0
ran=()
# shellcheck source=tests/lab1-lib.bash
source "${ROOT_DIR}/tests/lab1-lib.bash"
exec 3>&2   # fail() reports on fd 3

ok()   { passed=$((passed + 1)); echo "  ✔ $*"; }
fail() { echo "  ✘ $*" >&3; exit 1; }

# --- the doc's blocks -----------------------------------------------------------------------
mkdir -p "${work}/blocks" "${work}/log"
python3 - "$DOC" "$work/blocks" "$ROOT_DIR" "$files" <<'PY'
import re, sys
doc, out, root, files = sys.argv[1:5]
text = open(doc).read()
ids = []
for m in re.finditer(r'<!-- doc-test: covered by="check:test-lab1" id="([^"]+)" -->\n```bash\n(.*?)\n```', text, re.S):
    bid, body = m.group(1), m.group(2)
    if bid in ids:
        sys.exit(f"duplicate block id {bid}")
    ids.append(bid)
    body = body.replace("~/repos/gitops-control-plane", root).replace("~/lab1-work", files)
    open(f"{out}/{bid}.sh", "w").write(body + "\n")
unmarked = len(re.findall(r'covered by="check:test-lab1"(?! id=)', text))
if unmarked:
    sys.exit(f"{unmarked} test-lab1 block(s) without id")
open(f"{out}/ORDER", "w").write("\n".join(ids) + "\n")
PY

# block <id>: run it as the learner would (cwd ~/lab1-work, SOL set), fail on a nonzero exit
block() {
  local id=$1 cwd="$files"
  [[ -f "${work}/blocks/${id}.sh" ]] || fail "no block id=${id} in the doc"
  [[ "$id" == setup ]] && cwd="$work"
  if ! (cd "$cwd" && SOL="$SOL" bash -e -o pipefail "${work}/blocks/${id}.sh") >"${work}/log/${id}.log" 2>&1; then
    fail "doc block ${id} failed: $(tail -3 "${work}/log/${id}.log" | tr '\n' ' ')"
  fi
  ran+=("$id")
  ok "doc block ${id}"
}
# block_fails <id> <text>: the block's last command must fail with <text> (an expected failure)
block_fails() {
  local id=$1 want=$2
  if (cd "$files" && SOL="$SOL" bash -e -o pipefail "${work}/blocks/${id}.sh") >"${work}/log/${id}.log" 2>&1; then
    fail "doc block ${id} succeeded, but must fail with: ${want}"
  fi
  grep -qF -- "$want" "${work}/log/${id}.log" || fail "doc block ${id} failed without '${want}': $(tail -2 "${work}/log/${id}.log" | tr '\n' ' ')"
  ran+=("$id")
  ok "doc block ${id} fails as documented: ${want}"
}
# says <id> <text>: the block's output contains <text>
says() {
  if grep -qF -- "$2" "${work}/log/$1.log"; then ok "  ${1} shows: $2"
  else fail "${1} output lacks '$2': $(tail -3 "${work}/log/$1.log" | tr '\n' ' ')"; fi
}

istate() { $K -n "$NS" get webgreeting "$1" -o jsonpath='{.status.state}/{.status.conditions[?(@.type=="Ready")].status}'; }
is_active() { [[ "$(istate "$1")" == "ACTIVE/True" ]]; }
# Fail closed (validation-04 V3-2): absence needs a successful read that also shows a control object
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
clusters=$(k3d cluster list -o json) || fail "k3d cluster list failed"
jq -e 'type == "array"' <<<"$clusters" >/dev/null || fail "k3d cluster list returned no JSON array"
if jq -e 'any(.[]; .name == "learn-sandbox")' <<<"$clusters" >/dev/null; then
  fail "a sandbox already exists; run make sandbox-down first (test-lab1 starts from a clean state)"
fi
trap cleanup EXIT
block setup
[[ -d "$files" ]] || fail "setup did not create the working directory"
block s0-up
containers=$(docker ps -a --format '{{.Names}}') || fail "docker ps failed"
if grep -qx moto-sandbox <<<"$containers"; then fail "kro-only sandbox started moto-sandbox"; fi
ok "kro only: no moto-sandbox (the default; moto is added in step 6)"
block s0-ns

echo "[1] blueprint, no permissions, then the ClusterRole"
block s1-rgd
block s1-instance
block s1-apply
says s1-apply "cache sync timeout for kro.run/v1alpha1, Resource=webgreetings"
block s1-log
says s1-log 'cannot list resource \"webgreetings\" in API group \"kro.run\"'
block s1-rbac
says s1-rbac 'deployments.apps "hello" is forbidden'
block s1-children
says s1-children "hello from my first blueprint"

echo "[2] dependency order"
block s2-order
says s2-order '["deployment","config"]'
block s2-edit
says s2-edit '["config","deployment"]'
if is_active hello; then ok "hello ACTIVE on the new revision"; else fail "hello not ACTIVE after step 2: $(istate hello)"; fi

echo "[3] includeWhen"
block s3-edit
block s3-apply
block s3-observe
state=$($K -n "$NS" get webgreeting hello-public -o jsonpath='{.status.state}') || fail "cannot read hello-public"
if [[ -z "$state" ]]; then ok "without services RBAC: hello-public has no status"; else fail "hello-public has status '${state}' without services RBAC"; fi
says s3-observe "services is forbidden"
block s3-rbac
says s3-rbac "hello, world"
svcs=$($K -n "$NS" get service -o name) || fail "cannot list services"
grep -qx service/hello-public <<<"$svcs" || fail "no Service hello-public"
ok "expose: true → Service hello-public"
if grep -qx service/hello <<<"$svcs"; then fail "Service hello exists although expose is false"; fi
ok "expose: false → no Service hello"
block s3-toggle
order=$($K get rgd web-greeting -o jsonpath='{.status.topologicalOrder}') || fail "cannot read the RGD"
[[ "$order" == '["config","deployment","service"]' ]] || fail "topologicalOrder ${order}"
ok "topologicalOrder ${order}"

echo "[4] readyWhen and status"
block s4-rgd
says s4-rgd "same as the reference solution"
block s4-scale
[[ "$($K -n "$NS" get webgreeting hello -o jsonpath='{.status.availableReplicas}/{.status.state}')" == 3/ACTIVE ]] \
  || fail "hello not 3/ACTIVE after scaling"
ok "status.availableReplicas 3, ACTIVE"

echo "[5a] a reference to a field that does not exist"
block s5a-break
says s5a-break "undefined field 'nmae'"
if is_active hello && is_active hello-public; then ok "existing instances keep running"; else fail "instances not ACTIVE during the bad revision"; fi
block s5a-fix

echo "[5b] a constraint added to an existing field (incident D-14)"
block s5b-break
says s5b-break "breaking changes detected: Minimum constraint 1 was added; Maximum constraint 5 was added"
says s5b-break '{"default":1,"type":"integer"}'
block s5b-fix
block_fails s5b-policy "spec.replicas must be between 1 and 5"
block s5b-ok

echo "[6] stretch: an ACK Queue child"
block s6-moto
containers=$(docker ps -a --format '{{.Names}}') || fail "docker ps failed"
grep -qx moto-sandbox <<<"$containers" || fail "no moto-sandbox"
ok "moto-sandbox added to the running sandbox"
if is_active hello && is_active hello-public; then ok "instances still ACTIVE after adding moto"; else fail "instances changed by adding moto"; fi
block s6-apply
block s6-observe
says s6-observe "http://moto-sandbox:5000/123456789012/lab1-hello-jobs"
says s6-observe "http://localhost:5002/123456789012/lab1-hello-public-jobs"
[[ "$(queue_state lab1-hello-jobs lab1-hello-public-jobs)" == present ]] || fail "queue lab1-hello-jobs not readable as present before the delete"
block s6-delete
queue_gone || fail "queue lab1-hello-jobs still in moto 5 s after the delete"
ok "queue lab1-hello-jobs deleted from moto (control queue lab1-hello-public-jobs still listed)"
names=$($K -n "$NS" get deploy,configmap,service -o name) || fail "cannot list hello's children"
grep -qx deployment.apps/hello-public <<<"$names" || fail "control Deployment hello-public missing"
if grep -Eq '/hello(-page)?$' <<<"$names"; then fail "hello children left: ${names}"; fi
ok "kro removed hello's children (hello-public kept)"

echo "[7] clean up"
trap - EXIT
block cleanup
says cleanup "sandbox removed (no cluster, container, network or kube context left)"
[[ ! -e "$files" ]] || fail "working directory still there"
ok "working directory removed"
[[ "$(kubectl config get-contexts -o name | sort | tr '\n' ' ')" == "$contexts_before" ]] || fail "kube contexts changed"
ok "kube contexts unchanged"
[[ "$(kubectl config current-context 2>/dev/null || true)" == "$current_before" ]] || fail "current context changed"
ok "current context unchanged (${current_before})"

# every block of the doc was run, in the doc's order
mapfile -t all < "${work}/blocks/ORDER"
[[ "${all[*]}" == "${ran[*]}" ]] || fail "doc blocks and test order differ: doc=(${all[*]}) ran=(${ran[*]})"
ok "all ${#all[@]} doc blocks run, in the doc's order"
rm -rf "$work"
echo "✔ test-lab1: ${passed} checks passed"
