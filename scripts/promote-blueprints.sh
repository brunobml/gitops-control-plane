#!/usr/bin/env bash
set -euo pipefail

HUB_CONTEXT="k3d-hub-cluster"
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REVISIONS_FILE="${SCRIPT_DIR}/../clusters/blueprint-revisions.env"

if [[ ! -f "$REVISIONS_FILE" ]]; then
  echo "Error: Revisions file $REVISIONS_FILE not found" >&2
  exit 1
fi

if [ "$#" -eq 0 ]; then
  SPOKES=("spoke-nonprod" "spoke-prod")
else
  SPOKES=("$@")
fi

echo "Promoting spoke blueprint revisions from ${REVISIONS_FILE}..."

for spoke in "${SPOKES[@]}"; do
  bp_rev=$(grep -E "^${spoke}=" "$REVISIONS_FILE" | cut -d'=' -f2)
  : "${bp_rev:?no blueprints-revision for ${spoke} in clusters/blueprint-revisions.env}"

  kubectl --context "$HUB_CONTEXT" -n argocd annotate --overwrite secret "cluster-${spoke}" \
    blueprints-revision="${bp_rev}"

  echo "✔ Updated cluster-${spoke} blueprints-revision annotation to '${bp_rev}'"
done
