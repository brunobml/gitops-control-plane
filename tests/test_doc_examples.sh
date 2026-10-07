#!/usr/bin/env bash
# Learner-facing examples must work as written (learning remediation 2026-10-06, guardrail P-0).
# The code blocks are extracted from the documents themselves, so a doc edit that breaks an
# example fails here. Run: `make test-docs` (needs ../tenant-iac, ../orders-processor and, for
# the live checks, the running lab). `--offline` skips the checks that need the lab.
#
#   1. tenant-iac-operations.md, Runbook 1: the claim passes the schema and the full cluster checks
#   2. developer-tutorial.md, Step 2: the "what you write" block equals orders-processor/deploy/values-dev.yaml
#   3. developer-tutorial.md, Step 4: the AWS CLI block resolves the dev queue in account 111111111111
#      and publishes a message (live)
#   4. no stale "32 Applications" baselines in learner documents
#   5. doc-test markers (learner on-ramp plan, Track C): every bash block in the learner path is
#      marked run / mutating / covered / skip; the run blocks are executed (tests/doc_tests.py).
#      --offline: markers only. --mutating (make test-docs MODE=live-mutating): also the
#      self-reverting blocks, then wait until the lab has repaired itself and run the Bats suite.
set -uo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
REPOS=$(cd "$ROOT/.." && pwd)
OFFLINE=false
MUTATING=false
[[ "${1:-}" == "--offline" ]] && OFFLINE=true
[[ "${1:-}" == "--mutating" ]] && MUTATING=true
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
failed=0
ok()   { echo "  ✔ $*"; }
bad()  { echo "  ✘ $*"; failed=$((failed + 1)); }

# Print the first fenced block of type $3 that follows the line matching $2 in file $1 (indent removed).
block_after() {
  awk -v start="$2" -v type="$3" '
    index($0, start) { found = 1 }
    found && !inside && $0 ~ "^[[:space:]]*```" type "$" { inside = 1; match($0, /^[[:space:]]*/); ind = RLENGTH; next }
    inside && /^[[:space:]]*```[[:space:]]*$/ { exit }
    inside { print substr($0, ind + 1) }
  ' "$1"
}

echo "[1] tenant-iac claim example"
claim="$TMP/tenant-iac/teams/team-data/clusters/ml-feature-store-dev.yaml"
mkdir -p "$TMP/tenant-iac"
cp -r "$REPOS/tenant-iac/schema" "$TMP/tenant-iac/"
mkdir -p "$(dirname "$claim")"
block_after "$ROOT/docs/runbooks/tenant-iac-operations.md" "Create Cluster Claim File" yaml > "$claim"
if [[ -s "$claim" ]] && (cd "$TMP/tenant-iac" && python3 -c "import json, jsonschema, yaml; jsonschema.validate(yaml.safe_load(open('teams/team-data/clusters/ml-feature-store-dev.yaml')), json.load(open('schema/cluster.schema.json')))" 2>"$TMP/schema.err"); then
  ok "claim passes the JSON schema"
else
  bad "claim fails the JSON schema (or was not found): $(grep -m1 ValidationError "$TMP/schema.err")"
fi
if python3 "$ROOT/ci/check-clusters.py" "$TMP/tenant-iac" >/dev/null 2>&1; then
  ok "claim passes the full cluster checks (naming, sizes, team = folder)"
else
  bad "claim fails ci/check-clusters.py"
fi

# Step 3 executable validation: the documented bash block runs from a tenant-iac working directory.
# It runs in a temporary sibling layout (a copy of tenant-iac next to a link to this repository),
# never in the learner's real ../tenant-iac, so no existing claim can be overwritten or deleted
# (validation-02 N-3). REPOS_DIR points the Makefile's ci-iac target at that layout (GNU make
# resolves ../gitops-control-plane to the real path, so the link alone is not enough).
block_after "$ROOT/docs/runbooks/tenant-iac-operations.md" "Validate Locally" bash > "$TMP/validate_step3.sh"
layout="$TMP/repos"
mkdir -p "$layout"
cp -r "$REPOS/tenant-iac" "$layout/tenant-iac"
ln -s "$ROOT" "$layout/gitops-control-plane"
cp "$claim" "$layout/tenant-iac/teams/team-data/clusters/ml-feature-store-dev.yaml"
step3_ok=false
if out=$(cd "$layout/tenant-iac" && REPOS_DIR="$layout" bash -e "$TMP/validate_step3.sh" 2>&1); then
  grep -q "ml-feature-store-dev" <<<"$out" && step3_ok=true   # proves the copy (with the claim) was checked
fi
if $step3_ok; then
  ok "Step 3 validation block runs cleanly from the tenant-iac working directory"
else
  bad "Step 3 validation block failed from tenant-iac: $(tail -1 <<<"$out")"
fi

echo "[2] developer tutorial: values file shown = real values file"
block_after "$ROOT/docs/developer-tutorial.md" "**What you write**" yaml > "$TMP/values.yaml"
if diff -q "$TMP/values.yaml" "$REPOS/orders-processor/deploy/values-dev.yaml" >/dev/null; then
  ok "Step 2 values block equals orders-processor/deploy/values-dev.yaml"
else
  bad "Step 2 values block differs from orders-processor/deploy/values-dev.yaml"
fi

echo "[3] developer tutorial: AWS CLI example (live)"
if $OFFLINE; then
  echo "  - skipped (--offline)"
else
  block_after "$ROOT/docs/developer-tutorial.md" "### Step 4: Interacting with Simulated AWS" bash > "$TMP/step4.sh"
  if out=$(env -i HOME="$HOME" PATH="$PATH" bash -e "$TMP/step4.sh" 2>&1); then
    if grep -q "http://localhost:5000/111111111111/orders-dev-queue" <<<"$out" && grep -q '"MessageId"' <<<"$out"; then
      ok "dev queue resolved in account 111111111111 and a message was published"
    else
      bad "Step 4 ran but did not resolve the dev queue in account 111111111111 or publish"
    fi
  else
    bad "Step 4 block failed: $(tail -1 <<<"$out")"
  fi
fi

echo "[4] stale baselines"
if stale=$(grep -rn -E "32 Applications|32/32 Applications|all 32 [Aa]pplications" "$ROOT/README.md" "$ROOT/docs"/*.md "$ROOT/docs/runbooks"/*.md); then
  bad "stale baseline: $stale"
else
  ok "no '32 Applications' baselines in learner documents"
fi
# The 12-stage smoke script was replaced by the Bats suite (9134041); its banner no longer exists
# Also stage numbers of the old scripts ("[8/12]", "8-stage …", "smoke stage 10", "stage 6, and Gate 6b")
# and the TOKEN_WARN_DAYS tip, which Bats Gate 8 ignores (validation-04 V4-1/V4-2)
if stale=$(grep -rn -E "12 stages|12/12 smoke stages|12-stage smoke|All Core Smoke Tests Passed|\[[0-9]+/12\]|[0-9]+-stage (comprehensive |smoke |test)|smoke stages? [0-9]|\(stage [0-9]+|stage [0-9]+ fails|TOKEN_WARN_DAYS=" "$ROOT/README.md" "$ROOT/docs"/*.md "$ROOT/docs/runbooks"/*.md); then
  bad "stale smoke reference: $stale"
else
  ok "no stale smoke-stage references (old stage numbers, 12-stage banner, TOKEN_WARN_DAYS tip)"
fi

echo "[5] doc-test markers and runnable blocks"
if $OFFLINE; then
  python3 "$ROOT/tests/doc_tests.py" --markers-only || failed=$((failed + 1))
elif $MUTATING; then
  python3 "$ROOT/tests/doc_tests.py" --mutating || failed=$((failed + 1))
else
  python3 "$ROOT/tests/doc_tests.py" || failed=$((failed + 1))
fi

if (( failed )); then echo "✘ $failed doc example check(s) failed"; exit 1; fi
echo "✔ all doc example checks passed"
