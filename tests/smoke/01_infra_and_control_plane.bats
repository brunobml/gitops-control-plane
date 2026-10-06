#!/usr/bin/env bats
# tests/smoke/01_infra_and_control_plane.bats

setup() {
  load "common.bash"
}

@test "Gate 1: Moto Cloud API is responding at http://localhost:5000" {
  run curl -s -f "${MOTO_ENDPOINT}/moto-api/"
  [ "$status" -eq 0 ]
}

@test "Gate 2a: Hub cluster API is reachable" {
  run kubectl --context k3d-hub-cluster get nodes
  [ "$status" -eq 0 ]
}

@test "Gate 2b: All Argo CD core pods are Running" {
  run kubectl --context k3d-hub-cluster -n argocd get pods --field-selector=status.phase!=Succeeded --no-headers
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  local bad_pods
  bad_pods=$(awk '$3 != "Running" {print $1, $3}' <<< "$output")
  [ -z "$bad_pods" ]
}

@test "Gate 2c: Both spoke-nonprod and spoke-prod clusters are registered in Argo CD" {
  run kubectl --context k3d-hub-cluster -n argocd get secrets -l argocd.argoproj.io/secret-type=cluster -o jsonpath='{.items[*].metadata.name}'
  [ "$status" -eq 0 ]
  [[ "$output" == *"spoke-nonprod"* ]]
  [[ "$output" == *"spoke-prod"* ]]
}

@test "Gate 4a: Spoke clusters APIs are reachable" {
  for ctx in "k3d-spoke-nonprod" "k3d-spoke-prod"; do
    run kubectl --context "$ctx" get nodes
    [ "$status" -eq 0 ]
  done
}

@test "Gate 4b: ACK SQS and Kro controllers are ready on both spokes" {
  for ctx in "k3d-spoke-nonprod" "k3d-spoke-prod"; do
    run kubectl --context "$ctx" -n ack-system wait --for=condition=ready --timeout=30s pod -l app.kubernetes.io/name=sqs-chart
    [ "$status" -eq 0 ]
    run kubectl --context "$ctx" -n kro wait --for=condition=ready --timeout=30s pod -l app.kubernetes.io/name=kro
    [ "$status" -eq 0 ]
  done
}
