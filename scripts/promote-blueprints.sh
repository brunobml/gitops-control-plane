#!/usr/bin/env bash
set -euo pipefail

HUB_CONTEXT="k3d-hub-cluster"
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REVISIONS_FILE="${SCRIPT_DIR}/../clusters/blueprint-revisions.env"

if [[ ! -f "$REVISIONS_FILE" ]]; then
  echo "Error: Revisions file $REVISIONS_FILE not found" >&2
  exit 1
fi

REPO_DIR="${SCRIPT_DIR}/.."

# Preflight: ensure blueprint-revisions.env has no uncommitted changes (W-4)
if ! git -C "$REPO_DIR" diff --quiet HEAD -- "${REVISIONS_FILE}"; then
  echo "❌ Error: Uncommitted changes in ${REVISIONS_FILE}. Commit and push first." >&2
  exit 1
fi

# Preflight: ensure local commits are pushed to upstream (W-4)
if ! git -C "$REPO_DIR" merge-base --is-ancestor HEAD @{u} 2>/dev/null; then
  echo "❌ Error: Local commits not pushed to upstream branch. Push to Git first." >&2
  exit 1
fi

if [ "$#" -eq 0 ]; then
  SPOKES=("spoke-nonprod" "spoke-prod")
else
  SPOKES=("$@")
fi

echo "Promoting spoke blueprint revisions from ${REVISIONS_FILE}..."

for spoke in "${SPOKES[@]}"; do
  bp_rev=$(grep -E "^${spoke}=" "$REVISIONS_FILE" | cut -d'=' -f2 || true)
  : "${bp_rev:?no blueprints-revision for ${spoke} in clusters/blueprint-revisions.env}"

  kubectl --context "$HUB_CONTEXT" -n argocd annotate --overwrite secret "cluster-${spoke}" \
    blueprints-revision="${bp_rev}"

  echo "✔ Updated cluster-${spoke} blueprints-revision annotation to '${bp_rev}'"
done
