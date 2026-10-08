#!/usr/bin/env bash
# Read-only snapshot of the lab state that learner sessions must leave unchanged (learner on-ramp
# plan G-1; pilot protocol docs/learning/pilot-protocol.md). Compare two runs with diff:
#
#   make lab-snapshot > before.txt   ...session...   make lab-snapshot > after.txt; diff before.txt after.txt
#
# Lines: every Argo CD Application with sync and health status; the SQS queues and tagged VPCs per
# moto account (111111111111 nonprod, 222222222222 prod, 123456789012 the default account, which
# must stay empty); orders-dev-worker's replica count.
# Fail closed: if any read fails, the script exits 1 (a partial snapshot would compare as "changed"
# or, worse, as "equal").
set -euo pipefail

MOTO=http://localhost:5000
die() { echo "lab-snapshot: could not read $*" >&2; exit 1; }

apps=$(kubectl --context k3d-hub-cluster -n argocd get applications --no-headers \
  -o custom-columns='NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status') || die "Argo CD Applications"
[[ -n "$apps" ]] || die "Argo CD Applications (empty list)"
sort <<<"$apps" | awk '{print "app " $1 " " $2 " " $3}'

for acct in 111111111111 222222222222 123456789012; do
  if [[ "$acct" == 123456789012 ]]; then
    creds=(AWS_ACCESS_KEY_ID=mock-key AWS_SECRET_ACCESS_KEY=mock-secret AWS_SESSION_TOKEN='')
  else
    json=$(AWS_ACCESS_KEY_ID=mock-key AWS_SECRET_ACCESS_KEY=mock-secret AWS_SESSION_TOKEN='' \
      aws --endpoint-url="$MOTO" --region us-east-1 sts assume-role \
      --role-arn "arn:aws:iam::${acct}:role/snapshot" --role-session-name snapshot \
      --query Credentials --output json) || die "STS credentials for ${acct}"
    creds=("AWS_ACCESS_KEY_ID=$(jq -r .AccessKeyId <<<"$json")" \
           "AWS_SECRET_ACCESS_KEY=$(jq -r .SecretAccessKey <<<"$json")" \
           "AWS_SESSION_TOKEN=$(jq -r .SessionToken <<<"$json")")
  fi
  q=$(env "${creds[@]}" aws --endpoint-url="$MOTO" --region us-east-1 sqs list-queues --output json) || die "queues of ${acct}"
  queues=$(jq -r '(.QueueUrls // [])[] | split("/") | last' <<<"${q:-{\}}" | sort | tr '\n' ' ')
  v=$(env "${creds[@]}" aws --endpoint-url="$MOTO" --region us-east-1 ec2 describe-vpcs --output json) || die "VPCs of ${acct}"
  vpcs=$(jq '[.Vpcs[] | select((.Tags // []) | length > 0)] | length' <<<"$v") || die "VPCs of ${acct} (no JSON)"
  echo "account ${acct} queues: ${queues:-none}"
  echo "account ${acct} tagged-vpcs: ${vpcs}"
done

replicas=$(kubectl --context k3d-spoke-nonprod -n orders-dev get deployment orders-dev-worker -o jsonpath='{.spec.replicas}') \
  || die "orders-dev-worker"
echo "orders-dev-worker replicas: ${replicas}"
