#!/usr/bin/env bats
# tests/smoke/02_gitops_applications.bats

setup() {
  load "common.bash"
}

@test "Gate 3a: All expected 42 Argo CD applications exist" {
  run kubectl --context k3d-hub-cluster -n argocd get applications -o jsonpath='{.items[*].metadata.name}'
  [ "$status" -eq 0 ]
  for expected in "${EXPECTED_APPS[@]}"; do
    [[ " $output " == *" $expected "* ]]
  done
}

@test "Gate 3b: All 42 Argo CD applications are Synced and Healthy" {
  run kubectl --context k3d-hub-cluster -n argocd get applications -o jsonpath='{range .items[*]}{.metadata.name}:{.status.sync.status}:{.status.health.status}{"\n"}{end}'
  [ "$status" -eq 0 ]
  local unready=""
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    local app sync health
    IFS=: read -r app sync health <<< "$line"
    if [[ "$sync" != "Synced" || "$health" != "Healthy" ]]; then
      unready+="$app (Sync: $sync, Health: $health); "
    fi
  done <<< "$output"
  [ -z "$unready" ]
}

@test "Gate 5: QueueBackedService instances are ACTIVE across dev, test, and prod" {
  for spoke_ns in "k3d-spoke-nonprod:orders-dev" "k3d-spoke-nonprod:orders-test" "k3d-spoke-prod:orders-prod"; do
    local ctx="${spoke_ns%%:*}"
    local ns="${spoke_ns##*:}"
    run kubectl --context "$ctx" -n "$ns" get queuebackedservice orders -o jsonpath='{.status.state}'
    [ "$status" -eq 0 ]
    [ "$output" = "ACTIVE" ]
  done
}

@test "Gate 7: Workload pods are Running across non-prod and prod spokes" {
  local dev_pods test_pods prod_pods
  dev_pods=$(kubectl --context k3d-spoke-nonprod -n orders-dev get pods --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' ')
  test_pods=$(kubectl --context k3d-spoke-nonprod -n orders-test get pods --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' ')
  prod_pods=$(kubectl --context k3d-spoke-prod -n orders-prod get pods --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' ')

  [ "$dev_pods" -ge 1 ]
  [ "$test_pods" -ge 1 ]
  [ "$prod_pods" -ge 2 ]
}
