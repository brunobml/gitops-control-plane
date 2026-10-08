#!/usr/bin/env bats
# tests/smoke/03_carm_and_workload_pipeline.bats

setup() {
  load "common.bash"
}

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

@test "Gate 6b: Each CARM account has exactly one platform VPC, the one Kubernetes references" {
  for ctx in k3d-spoke-nonprod k3d-spoke-prod; do
    local account live vpcs
    account=$(kubectl --context "$ctx" get namespace platform-network -o jsonpath='{.metadata.annotations.services\.k8s\.aws/owner-account-id}')
    live=$(kubectl --context "$ctx" -n platform-network get vpc platform-vpc -o jsonpath='{.status.vpcID}')
    [[ -n "$account" && -n "$live" ]]
    vpcs=$(platform_vpcs_in_account "$account")
    # an orphan left by a moto restart shows up as a second ID (scripts/prune-orphan-platform-vpcs.sh)
    [[ "$vpcs" == "$live" ]]
  done
}

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
    while (( $(date +%s) - t0 <= 60 )); do
      if curl -s "http://${ns}.localhost:${port}/" | grep -q "$marker"; then
        found=true
        break
      fi
      sleep 1
    done
    [ "$found" = "true" ]
  done
}

@test "Gate 9b: Each spoke load balancer routes every request (no stale upstream after a restart)" {
  # Gate 9 retries for 60 s and would pass a route that fails every second request; here 6
  # requests in a row must all reach the tenant app (fix: docker exec k3d-<spoke>-serverlb nginx -s reload,
  # done by make start).
  for pair in "orders-dev:8081" "orders-test:8081" "orders-prod:8082"; do
    IFS=: read -r ns port <<<"$pair"
    local codes="" i
    for i in 1 2 3 4 5 6; do
      codes+="$(curl -s -o /dev/null -w '%{http_code}' "http://${ns}.localhost:${port}/") "
    done
    echo "# ${ns}: ${codes}" >&3
    [ "$codes" = "200 200 200 200 200 200 " ]
  done
}

