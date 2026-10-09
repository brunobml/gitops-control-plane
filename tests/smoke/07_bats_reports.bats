#!/usr/bin/env bats

@test "Gate 14: Bats report viewer is ready and has prior results" {
  run curl -fsS --max-time 5 http://bats-reports.localhost:8081/readyz
  [ "$status" -eq 0 ]

  run curl -fsS --max-time 5 http://bats-reports.localhost:8081/api/runs
  [ "$status" -eq 0 ]
  run jq -e 'if type == "array" then length > 0 else (.runs | length) > 0 end' <<<"$output"
  [ "$status" -eq 0 ]
}

@test "Gate 14a: ACK S3 report bucket is synced in the nonprod account" {
  run kubectl --context k3d-spoke-nonprod -n platform-reports get bucket gitops-lab-reports -o json
  [ "$status" -eq 0 ]
  run jq -e '.status.ackResourceMetadata.ownerAccountID == "111111111111" and any(.status.conditions[]; .type == "ACK.ResourceSynced" and .status == "True")' <<<"$output"
  [ "$status" -eq 0 ]
}
