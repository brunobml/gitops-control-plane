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
set -uo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
REPOS=$(cd "$ROOT/.." && pwd)
OFFLINE=false
[[ "${1:-}" == "--offline" ]] && OFFLINE=true
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

echo "[4] stale application baselines"
if stale=$(grep -rn -E "32 Applications|32/32 Applications|all 32 [Aa]pplications" "$ROOT/README.md" "$ROOT/docs"/*.md "$ROOT/docs/runbooks"/*.md); then
  bad "stale baseline: $stale"
else
  ok "no '32 Applications' baselines in learner documents"
fi

if (( failed )); then echo "✘ $failed doc example check(s) failed"; exit 1; fi
echo "✔ all doc example checks passed"
