#!/usr/bin/env bash
# Source this file, then call discover_iac_claims. On success it sets
# IAC_CLAIM_TUPLES and IAC_APPS_COUNT for the caller.

discover_iac_claims() {
  local spoke claim_json tuple_json apps_json app_count tuple
  IAC_CLAIM_TUPLES=()
  IAC_APPS_COUNT=0

  for spoke in spoke-nonprod spoke-prod; do
    if ! claim_json=$(kubectl --context "k3d-${spoke}" get teamekscluster -A -o json); then
      echo "✘ Failed to discover TeamEKSCluster claims on ${spoke}" >&2
      return 1
    fi
    if ! tuple_json=$(jq -e --arg cluster "$spoke" '
      if (.items | type) != "array" then error("claim items is not an array")
      else [.items[] |
        if (.metadata.name | type) == "string" and (.metadata.name | length) > 0
           and (.metadata.namespace | type) == "string" and (.metadata.namespace | length) > 0
        then "\($cluster)|\(.metadata.namespace)|\(.metadata.name)"
        else error("claim metadata is incomplete") end]
      end' <<< "$claim_json"); then
      echo "✘ Invalid TeamEKSCluster response on ${spoke}" >&2
      return 1
    fi
    while IFS= read -r tuple; do
      [[ -n "$tuple" ]] && IAC_CLAIM_TUPLES+=("$tuple")
    done < <(jq -r '.[]' <<< "$tuple_json")
  done

  if ! apps_json=$(kubectl --context k3d-hub-cluster -n argocd get applications -o json); then
    echo "✘ Failed to discover Argo CD Applications" >&2
    return 1
  fi
  if ! app_count=$(jq -r '
    if (.items | type) != "array" then error("application items is not an array")
    else [.items[] | select(.spec.project == "tenant-iac")] | length end' <<< "$apps_json"); then
    echo "✘ Invalid Argo CD Applications response" >&2
    return 1
  fi
  if [[ ! "$app_count" =~ ^[0-9]+$ ]]; then
    echo "✘ Invalid tenant-iac Application count: ${app_count}" >&2
    return 1
  fi
  IAC_APPS_COUNT="$app_count"

  if (( ${#IAC_CLAIM_TUPLES[@]} == 0 || ${#IAC_CLAIM_TUPLES[@]} != IAC_APPS_COUNT )); then
    echo "✘ TeamEKSCluster claim count (${#IAC_CLAIM_TUPLES[@]}) must be positive and match registered tenant-iac Applications (${IAC_APPS_COUNT})" >&2
    return 1
  fi
}
