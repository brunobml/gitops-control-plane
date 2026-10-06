#!/usr/bin/env bash
# tests/smoke/common.bash
#
# Shared configuration and helpers for the Bats smoke test suite.

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
