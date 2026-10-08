#!/usr/bin/env bats
# tests/smoke/05_supply_chain_admission.bats

setup() {
  load "common.bash"
}

# The admission probes of Gates 11b/11c run in the namespace admission-probes
# (addons/admission-probes), never in a tenant namespace, so they do not count as tenant denials
# on the Kyverno dashboards. Gate 11a proves that the tenant namespaces opt in to the same chain.
PROBE_NS=admission-probes

@test "Gate 11a: Kyverno image verification policy tenant-images-signed is enforcing Deny, and every tenant namespace and the probe namespace opt in" {
  for target in "k3d-spoke-nonprod:orders-dev" "k3d-spoke-nonprod:orders-test" "k3d-spoke-prod:orders-prod" \
                "k3d-spoke-nonprod:${PROBE_NS}" "k3d-spoke-prod:${PROBE_NS}"; do
    IFS=: read -r ctx ns <<<"$target"
    local actions label
    actions=$(kubectl --context "$ctx" get imagevalidatingpolicy tenant-images-signed -o jsonpath='{.spec.validationActions}')
    [ "$actions" = '["Deny"]' ]
    label=$(kubectl --context "$ctx" get namespace "$ns" -o jsonpath='{.metadata.labels.platform\.lab/image-verification}')
    [ "$label" = "enabled" ]
  done
}

@test "Gate 11b: Kyverno denies unsigned image and native VAP denies arbitrary unallowlisted image" {
  local UNSIGNED="ghcr.io/brunobml/orders-processor@sha256:c7e8f5d9038ad202da6d37e0be76aa342a482bd4d6b37279b0891792584cf32f"
  local overrides='{"spec":{"securityContext":{"runAsNonRoot":true,"runAsUser":10001,"seccompProfile":{"type":"RuntimeDefault"}},"containers":[{"name":"probe","image":"IMG","securityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]}}}]}}'

  for ctx in k3d-spoke-nonprod k3d-spoke-prod; do
    local ns="$PROBE_NS"

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
    IFS=: read -r ctx tenant_ns <<<"$target"
    local running
    running=$(kubectl --context "$ctx" -n "$tenant_ns" get pods -o jsonpath='{.items[0].spec.containers[0].image}')
    [ -n "$running" ]
    run kubectl --context "$ctx" -n "$PROBE_NS" run smoke-signed-probe --image="$running" --restart=Never --dry-run=server \
      --overrides="${overrides/IMG/$running}" -o name
    [ "$status" -eq 0 ]
  done
}

@test "Gate 11d: Policy Reporter: reports controller and APIs on both spokes (routes need credentials), UI on the hub behind Keycloak" {
  for spoke in spoke-nonprod spoke-prod; do
    local ctx="k3d-${spoke}" port code
    run kubectl --context "$ctx" -n kyverno rollout status deployment/kyverno-reports-controller --timeout=30s
    [ "$status" -eq 0 ]
    for deployment in policy-reporter policy-reporter-kyverno-plugin; do
      run kubectl --context "$ctx" -n policy-reporter rollout status "deployment/$deployment" --timeout=30s
      [ "$status" -eq 0 ]
    done
    run kubectl --context "$ctx" get policyreports.wgpolicyk8s.io --all-namespaces -o name
    [ "$status" -eq 0 ]
    # the hub reaches the spoke API through its load balancer; without credentials Traefik refuses
    port=8081; [ "$spoke" = spoke-prod ] && port=8082
    code=$(curl -s -o /dev/null -w '%{http_code}' -H "Host: k3d-${spoke}-serverlb" "http://127.0.0.1:${port}/pr-core/v1/namespaces")
    [ "$code" = "401" ]
  done
  run kubectl --context k3d-hub-cluster -n policy-reporter rollout status deployment/policy-reporter-ui --timeout=30s
  [ "$status" -eq 0 ]
  # the UI sends an anonymous visitor to Keycloak (client policy-reporter)
  local loc
  loc=$(curl -s -o /dev/null -L --max-redirs 3 -w '%{url_effective}' http://policy-reporter.localhost/)
  [[ "$loc" == "${ISSUER}/protocol/openid-connect/auth?"*"client_id=policy-reporter"* ]]
}
