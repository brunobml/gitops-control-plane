#!/usr/bin/env bats
# tests/smoke-test-hub-spoke.bats
#
# Bats test suite for Multi-Cluster Hub-and-Spoke Smoke Gates (1-12).
# Maps 1-to-1 to scripts/smoke-test-hub-spoke.sh with granular assertion isolation.

setup_file() {
  export MOTO_ENDPOINT="${MOTO_ENDPOINT:-http://localhost:5000}"
  export DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"
  export ISSUER="http://keycloak.localhost/realms/lab"
  export SECRET_DIR="${GITOPS_LAB_SECRET_DIR:-$HOME/.config/gitops-lab}"
  export TOKEN_WARN_DAYS="${TOKEN_WARN_DAYS:-7}"
  export NOW_EPOCH="${SMOKE_NOW_EPOCH:-$(date +%s)}"

  export EXPECTED_APPS=(
    "argo-cd" "addon-headlamp" "addon-keycloak" "addon-oauth2-proxy"
    "addon-kyverno-spoke-nonprod" "addon-kyverno-spoke-prod"
    "addon-prometheus" "addon-grafana" "addon-blackbox" "addon-lab-exporters"
    "addon-observability-spoke-nonprod" "addon-observability-spoke-prod"
    "addon-loki" "addon-alloy"
    "addon-logging-spoke-nonprod" "addon-logging-spoke-prod"
    "addon-platform-config-spoke-nonprod" "addon-platform-config-spoke-prod"
    "addon-traefik" "platform-projects"
    "addon-kro-spoke-nonprod" "addon-kro-spoke-prod"
    "addon-ack-sqs-spoke-nonprod" "addon-ack-sqs-spoke-prod"
    "addon-ack-ec2-spoke-nonprod" "addon-ack-ec2-spoke-prod"
    "addon-ack-iam-spoke-nonprod" "addon-ack-iam-spoke-prod"
    "addon-ack-eks-spoke-nonprod" "addon-ack-eks-spoke-prod"
    "addon-ack-credentials-spoke-nonprod" "addon-ack-credentials-spoke-prod"
    "platform-network-spoke-nonprod" "platform-network-spoke-prod"
    "kro-blueprints-spoke-nonprod" "kro-blueprints-spoke-prod"
    "orders-dev" "orders-test" "orders-prod"
    "team-data-analytics-dev" "team-data-analytics-prod"
    "root-control-plane"
  )
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
list_queues_in_account() {
  local account="$1" creds
  creds=$(AWS_ACCESS_KEY_ID=mock-key AWS_SECRET_ACCESS_KEY=mock-secret aws --endpoint-url="$MOTO_ENDPOINT" --region "$DEFAULT_REGION" \
    sts assume-role --role-arn "arn:aws:iam::${account}:role/smoke-test" --role-session-name smoke-test \
    --query Credentials --output json 2>/dev/null) || { echo "{}"; return; }
  AWS_ACCESS_KEY_ID=$(jq -r .AccessKeyId <<<"$creds") AWS_SECRET_ACCESS_KEY=$(jq -r .SecretAccessKey <<<"$creds") \
    AWS_SESSION_TOKEN=$(jq -r .SessionToken <<<"$creds") \
    aws --endpoint-url="$MOTO_ENDPOINT" --region "$DEFAULT_REGION" sqs list-queues --output json 2>/dev/null || echo "{}"
}

promq() {
  kubectl --context k3d-hub-cluster -n monitoring exec deploy/prometheus-server -c prometheus-server -- \
    wget -qO- "http://localhost:9090/api/v1/query?query=$(jq -rn --arg q "$1" '$q|@uri')" 2>/dev/null
}

jwt_exp_from_cluster_secret() {
  kubectl --context k3d-hub-cluster -n argocd get secret "$1" -o jsonpath='{.data.config}' \
    | base64 -d | jq -r '.bearerToken' \
    | python3 -c 'import sys,json,base64; p=sys.stdin.read().strip().split(".")[1]; p+="="*(-len(p)%4); print(json.loads(base64.urlsafe_b64decode(p))["exp"])'
}

kubeconfig_exps() {
  python3 -c 'import sys,yaml,json,base64
k=yaml.safe_load(sys.stdin)
for u in k["users"]:
    p=u["user"]["token"].split(".")[1]; p+="="*(-len(p)%4)
    print(u["name"], json.loads(base64.urlsafe_b64decode(p))["exp"])'
}

# ---------------------------------------------------------------------------
# [1/12] Mock AWS Cloud (Moto)
# ---------------------------------------------------------------------------
@test "Gate 1: Moto Cloud API is responding at http://localhost:5000" {
  run curl -s -f "${MOTO_ENDPOINT}/moto-api/"
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# [2/12] Hub Cluster & Argo CD Core
# ---------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------
# [3/12] Argo CD Applications Health & Sync State
# ---------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------
# [4/12] Spoke Controllers (Kro + ACK)
# ---------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------
# [5/12] Kro QueueBackedService Custom Resources State
# ---------------------------------------------------------------------------
@test "Gate 5: QueueBackedService instances are ACTIVE across dev, test, and prod" {
  for spoke_ns in "k3d-spoke-nonprod:orders-dev" "k3d-spoke-nonprod:orders-test" "k3d-spoke-prod:orders-prod"; do
    local ctx="${spoke_ns%%:*}"
    local ns="${spoke_ns##*:}"
    run kubectl --context "$ctx" -n "$ns" get queuebackedservice orders -o jsonpath='{.status.state}'
    [ "$status" -eq 0 ]
    [ "$output" = "ACTIVE" ]
  done
}

# ---------------------------------------------------------------------------
# [6/12] SQS Queues & DLQs in Moto Cloud (CARM Multi-Account)
# ---------------------------------------------------------------------------
@test "Gate 6: All 6 SQS queues and DLQs exist in their designated CARM cloud accounts" {
  for pair in "k3d-spoke-nonprod:orders-dev" "k3d-spoke-nonprod:orders-test" "k3d-spoke-prod:orders-prod"; do
    local ctx="${pair%%:*}"
    local ns="${pair##*:}"
    local account
    account=$(kubectl --context "$ctx" get namespace "$ns" -o jsonpath='{.metadata.annotations.services\.k8s\.aws/owner-account-id}' 2>/dev/null || true)
    account="${account:-123456789012}"
    local queues
    queues=$(list_queues_in_account "$account")
    for qname in "${ns}-queue" "${ns}-dlq"; do
      [[ "$queues" == *"/$account/$qname\""* ]]
    done
  done
}

# ---------------------------------------------------------------------------
# [7/12] GitOps Workload Pods
# ---------------------------------------------------------------------------
@test "Gate 7: Workload pods are Running across non-prod and prod spokes" {
  local dev_pods test_pods prod_pods
  dev_pods=$(kubectl --context k3d-spoke-nonprod -n orders-dev get pods --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' ')
  test_pods=$(kubectl --context k3d-spoke-nonprod -n orders-test get pods --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' ')
  prod_pods=$(kubectl --context k3d-spoke-prod -n orders-prod get pods --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' ')

  [ "$dev_pods" -ge 1 ]
  [ "$test_pods" -ge 1 ]
  [ "$prod_pods" -ge 2 ]
}

# ---------------------------------------------------------------------------
# [8/12] Credential Expiry
# ---------------------------------------------------------------------------
@test "Gate 8: Cluster and Headlamp credentials are valid and unexpired" {
  local rows=""
  for s in cluster-spoke-nonprod cluster-spoke-prod; do
    rows+="argocd/${s} $(jwt_exp_from_cluster_secret "$s")"$'\n'
  done
  while read -r user exp; do
    rows+="headlamp-secret/${user} ${exp}"$'\n'
  done < <(kubectl --context k3d-hub-cluster -n headlamp get secret headlamp-kubeconfig -o jsonpath='{.data.config}' | base64 -d | kubeconfig_exps)

  local headlamp_pod
  headlamp_pod=$(kubectl --context k3d-hub-cluster -n headlamp get pods -l app.kubernetes.io/name=headlamp \
    --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
  [ -n "$headlamp_pod" ]

  while read -r user exp; do
    rows+="headlamp-pod/${user} ${exp}"$'\n'
  done < <(kubectl --context k3d-hub-cluster -n headlamp exec "$headlamp_pod" -- cat /home/headlamp/.kube/config | kubeconfig_exps)

  local failed=0
  while read -r name exp; do
    [[ -z "$name" ]] && continue
    local remaining=$(( exp - NOW_EPOCH ))
    if (( remaining <= 0 )); then
      failed=1
    fi
  done <<< "$rows"

  [ "$failed" -eq 0 ]
}

# ---------------------------------------------------------------------------
# [9/12] End-to-End Order Flow
# ---------------------------------------------------------------------------
@test "Gate 9: Orders flow end-to-end and are processed across dev, test, and prod" {
  for triple in "k3d-spoke-nonprod:orders-dev:8081" "k3d-spoke-nonprod:orders-test:8081" "k3d-spoke-prod:orders-prod:8082"; do
    IFS=: read -r ctx ns port <<<"$triple"
    local account
    account=$(kubectl --context "$ctx" get namespace "$ns" -o jsonpath='{.metadata.annotations.services\.k8s\.aws/owner-account-id}' 2>/dev/null || true)
    account="${account:-123456789012}"

    local creds
    creds=$(AWS_ACCESS_KEY_ID=mock-key AWS_SECRET_ACCESS_KEY=mock-secret aws --endpoint-url="$MOTO_ENDPOINT" --region "$DEFAULT_REGION" \
      sts assume-role --role-arn "arn:aws:iam::${account}:role/smoke-test" --role-session-name smoke-e2e --query Credentials --output json)
    local marker="smoke-e2e-${ns}-$(date +%s)"
    AWS_ACCESS_KEY_ID=$(jq -r .AccessKeyId <<<"$creds") AWS_SECRET_ACCESS_KEY=$(jq -r .SecretAccessKey <<<"$creds") \
      AWS_SESSION_TOKEN=$(jq -r .SessionToken <<<"$creds") \
      aws --endpoint-url="$MOTO_ENDPOINT" --region "$DEFAULT_REGION" sqs send-message \
      --queue-url "${MOTO_ENDPOINT}/${account}/${ns}-queue" --message-body "$marker" >/dev/null

    local t0=$(date +%s)
    local found=false
    until curl -s "http://${ns}.localhost:${port}/" | grep -q "$marker"; do
      if (( $(date +%s) - t0 > 60 )); then
        break
      fi
      sleep 2
    done
    if curl -s "http://${ns}.localhost:${port}/" | grep -q "$marker"; then
      found=true
    fi
    [ "$found" = "true" ]
  done
}

# ---------------------------------------------------------------------------
# [10/12] Single Sign-On (Keycloak, Argo CD, Headlamp)
# ---------------------------------------------------------------------------
@test "Gate 10a: OIDC issuer is identical from host and from argocd-server" {
  local host_iss pod_iss
  host_iss=$(curl -s "${ISSUER}/.well-known/openid-configuration" | jq -r .issuer 2>/dev/null || true)
  pod_iss=$(kubectl --context k3d-hub-cluster -n argocd exec deploy/argo-cd-argocd-server -- bash -c \
    'exec 3<>/dev/tcp/keycloak.localhost/80; printf "GET /realms/lab/.well-known/openid-configuration HTTP/1.0\r\nHost: keycloak.localhost\r\n\r\n" >&3; cat <&3' 2>/dev/null \
    | grep -o '"issuer":"[^"]*"' | cut -d'"' -f4 || true)

  [ "$host_iss" = "$ISSUER" ]
  [ "$pod_iss" = "$ISSUER" ]
}

@test "Gate 10b: Argo CD advertises Keycloak SSO (PKCE)" {
  local settings
  settings=$(curl -s http://localhost/api/v1/settings)
  [ "$(jq -r '.oidcConfig.issuer // ""' <<<"$settings")" = "$ISSUER" ]
  [ "$(jq -r '.oidcConfig.enablePKCEAuthentication // false' <<<"$settings")" = "true" ]
}

@test "Gate 10c: SSO entry points reach Keycloak login form" {
  for start in "http://localhost/auth/login?return_url=http%3A%2F%2Flocalhost%2Fapplications" \
               "http://argocd.localhost/auth/login?return_url=http%3A%2F%2Fargocd.localhost%2Fapplications" \
               "http://headlamp.localhost/"; do
    local kc_url
    kc_url=$(curl -s -o /dev/null -w '%{redirect_url}' "$start")
    [[ "$kc_url" == "${ISSUER}/protocol/openid-connect/auth?"* ]]
    run curl -s "$kc_url"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "id=\"kc-form-login\"" ]]
  done
}

@test "Gate 10d: Local platform-admin break-glass login succeeds" {
  local pw_file="${SECRET_DIR}/argocd-platform-admin.password"
  local token
  token=$(jq -n --rawfile p "$pw_file" '{username: "platform-admin", password: ($p | rtrimstr("\n"))}' \
    | curl -s -H 'Content-Type: application/json' -d @- http://localhost/api/v1/session | jq -r '.token // ""')
  [ -n "$token" ]
}

@test "Gate 10e: Headlamp requires SSO and refuses cross-origin access" {
  local hl
  hl=$(curl -s -o /dev/null -w '%{http_code} %{redirect_url}' -H 'Origin: https://evil.example' http://headlamp.localhost/clusters/k3d-spoke-prod/api/v1/namespaces)
  [[ "$hl" == "302 ${ISSUER}/protocol/openid-connect/auth?"*"client_id=headlamp"* ]]

  local cors
  cors=$(curl -s -D - -o /dev/null -H 'Origin: https://evil.example' http://headlamp.localhost/ | grep -i '^access-control-allow-origin' || true)
  [ -z "$cors" ]
}

# ---------------------------------------------------------------------------
# [11/12] Supply-Chain Admission (Kyverno & VAP)
# ---------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------
# [12/12] Observability (Prometheus, Blackbox, Loki, Team Clusters, Grafana)
# ---------------------------------------------------------------------------
@test "Gate 12a: Hub Prometheus receives scrape metrics from both spokes" {
  for spoke in spoke-nonprod spoke-prod; do
    local n
    n=$(promq "count(up{cluster=\"${spoke}\"} == 1)" | jq -r '.data.result[0].value[1] // 0')
    [ "$n" -ge 5 ]
  done
}

@test "Gate 12b: Synthetic HTTP blackbox probes are healthy" {
  local failed
  failed=$(promq 'probe_success{job="blackbox"} == 0' | jq -r '[.data.result[].metric.probe] | join(",")')
  [ -z "$failed" ]
}

@test "Gate 12c: Logs shipped from hub, spoke-nonprod and spoke-prod, and Loki is up" {
  for cl in hub spoke-nonprod spoke-prod; do
    local r
    r=$(promq "sum(rate(loki_write_sent_entries_total{cluster=\"${cl}\"}[10m]))" | jq -r '.data.result[0].value[1] // 0')
    local ok
    ok=$(awk -v r="$r" 'BEGIN{print (r > 0) ? 1 : 0}')
    [ "$ok" -eq 1 ]
  done
  local loki_up
  loki_up=$(promq 'up{job="loki"}' | jq -r '.data.result[0].value[1] // 0')
  [ "$loki_up" -eq 1 ]
}

@test "Gate 12d: Team clusters analytics-dev and analytics-prod report ready in Prometheus" {
  for exp in "analytics-dev" "analytics-prod"; do
    local r
    r=$(promq "lab_team_cluster_ready{name=\"${exp}\"}" | jq -r '.data.result[0].value[1] // empty')
    [ "$r" = "1" ]
  done
}

@test "Gate 12e: No alerts persistently firing over 20 minutes" {
  local alerts
  alerts=$(kubectl --context k3d-hub-cluster -n monitoring exec deploy/prometheus-server -c prometheus-server -- wget -qO- http://localhost:9090/api/v1/alerts 2>/dev/null)
  local old
  old=$(jq -r --argjson now "$(date +%s)" '[.data.alerts[] | select(.state=="firing" and ((.activeAt | sub("\\.[0-9]+";"") | fromdateiso8601) < ($now - 1200))) | .labels.alertname] | unique | join(",")' <<<"$alerts")
  if [[ -n "$old" ]]; then
    echo "Persistently firing alerts (>20m): ${old}" >&2
  fi
  [ -z "$old" ]
}

@test "Gate 12f: Grafana SSO entry point reaches Keycloak login form" {
  local kc
  kc=$(curl -s -o /dev/null -w '%{redirect_url}' http://grafana.localhost/login/generic_oauth)
  [[ "$kc" == "${ISSUER}/protocol/openid-connect/auth?"* ]]
  run curl -s "$kc"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "id=\"kc-form-login\"" ]]
}
