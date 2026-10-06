#!/usr/bin/env bats
# tests/smoke/05_supply_chain_admission.bats

setup() {
  load "common.bash"
}

@test "Gate 11a: Kyverno image verification policy tenant-images-signed is enforcing Deny" {
  for target in "k3d-spoke-nonprod:orders-dev" "k3d-spoke-nonprod:orders-test" "k3d-spoke-prod:orders-prod"; do
    local ctx="${target%%:*}"
    local actions
    actions=$(kubectl --context "$ctx" get imagevalidatingpolicy tenant-images-signed -o jsonpath='{.spec.validationActions}' 2>/dev/null || true)
    [ "$actions" = '["Deny"]' ]
  done
}

@test "Gate 11b: Kyverno denies unsigned image and native VAP denies arbitrary unallowlisted image" {
  local UNSIGNED="ghcr.io/brunobml/orders-processor@sha256:c7e8f5d9038ad202da6d37e0be76aa342a482bd4d6b37279b0891792584cf32f"
  local overrides='{"spec":{"securityContext":{"runAsNonRoot":true,"runAsUser":10001,"seccompProfile":{"type":"RuntimeDefault"}},"containers":[{"name":"probe","image":"IMG","securityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]}}}]}}'

  for target in "k3d-spoke-nonprod:orders-dev" "k3d-spoke-nonprod:orders-test" "k3d-spoke-prod:orders-prod"; do
    IFS=: read -r ctx ns <<<"$target"

    # Unsigned probe denied by Kyverno
    run kubectl --context "$ctx" -n "$ns" run smoke-unsigned-probe --image="$UNSIGNED" --restart=Never --dry-run=server \
      --overrides="${overrides/IMG/$UNSIGNED}" -o name
    [ "$status" -ne 0 ]
    [[ "$output" =~ "Policy tenant-images-signed failed" ]]

    # Alpine probe denied by VAP
    run kubectl --context "$ctx" -n "$ns" run smoke-alpine-probe --image="alpine:latest" --restart=Never --dry-run=server \
      --overrides="${overrides/IMG/alpine:latest}" -o name
    [ "$status" -ne 0 ]
    [[ "$output" =~ "ValidatingAdmissionPolicy 'tenant-image-registry-allowlist'" ]]
  done
}

@test "Gate 11c: Running signed workload image is admitted" {
  local overrides='{"spec":{"securityContext":{"runAsNonRoot":true,"runAsUser":10001,"seccompProfile":{"type":"RuntimeDefault"}},"containers":[{"name":"probe","image":"IMG","securityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]}}}]}}'

  for target in "k3d-spoke-nonprod:orders-dev" "k3d-spoke-nonprod:orders-test" "k3d-spoke-prod:orders-prod"; do
    IFS=: read -r ctx ns <<<"$target"
    local running
    running=$(kubectl --context "$ctx" -n "$ns" get pods -o jsonpath='{.items[0].spec.containers[0].image}')
    run kubectl --context "$ctx" -n "$ns" run smoke-signed-probe --image="$running" --restart=Never --dry-run=server \
      --overrides="${overrides/IMG/$running}" -o name
    [ "$status" -eq 0 ]
  done
}
