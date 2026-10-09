#!/usr/bin/env bash
# Provision a Moto IAM identity for the read-only report viewer. Moto does not
# enforce IAM policy, but the same Secret contract works with real AWS.
set -euo pipefail
umask 077

CONTEXT=k3d-spoke-nonprod
NAMESPACE=platform-reports
ACCOUNT=111111111111
USER_NAME=bats-test-reporter-reader
BUCKET=gitops-lab-reports
ENDPOINT="${MOTO_ENDPOINT:-http://localhost:5000}"

if ! kubectl --context "$CONTEXT" get namespace "$NAMESPACE" >/dev/null 2>&1; then
  echo "  ℹ ${NAMESPACE} is not installed; skipping reporter credentials"
  exit 0
fi

creds=$(AWS_MAX_ATTEMPTS=1 AWS_ACCESS_KEY_ID=mock-key AWS_SECRET_ACCESS_KEY=mock-secret \
  timeout 30s aws --cli-connect-timeout 5 --cli-read-timeout 20 --endpoint-url="$ENDPOINT" --region us-east-1 \
    sts assume-role --role-arn "arn:aws:iam::${ACCOUNT}:role/provisioner" \
    --role-session-name setup-bats-reporter --query Credentials --output json)
export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_MAX_ATTEMPTS=1
AWS_ACCESS_KEY_ID=$(jq -er .AccessKeyId <<<"$creds")
AWS_SECRET_ACCESS_KEY=$(jq -er .SecretAccessKey <<<"$creds")
AWS_SESSION_TOKEN=$(jq -er .SessionToken <<<"$creds")
unset creds
AWS_CMD=(timeout 30s aws --cli-connect-timeout 5 --cli-read-timeout 20 --endpoint-url="$ENDPOINT" --region us-east-1)

caller=$("${AWS_CMD[@]}" sts get-caller-identity --query Account --output text)
[[ "$caller" == "$ACCOUNT" ]] || { echo "✘ Moto account mismatch for reporter credentials" >&2; exit 1; }
"${AWS_CMD[@]}" iam get-user --user-name "$USER_NAME" >/dev/null 2>&1 ||
  "${AWS_CMD[@]}" iam create-user --user-name "$USER_NAME" >/dev/null

# This policy is documented intent; Moto currently does not enforce it.
policy=$(jq -nc --arg bucket "$BUCKET" '{Version:"2012-10-17",Statement:[{Effect:"Allow",Action:["s3:ListBucket"],Resource:[("arn:aws:s3:::"+$bucket)]},{Effect:"Allow",Action:["s3:GetObject"],Resource:[("arn:aws:s3:::"+$bucket+"/*")]}]}')
"${AWS_CMD[@]}" iam put-user-policy --user-name "$USER_NAME" --policy-name bats-report-read --policy-document "$policy" >/dev/null

for key_id in $("${AWS_CMD[@]}" iam list-access-keys --user-name "$USER_NAME" --query 'AccessKeyMetadata[].AccessKeyId' --output text); do
  "${AWS_CMD[@]}" iam delete-access-key --user-name "$USER_NAME" --access-key-id "$key_id" >/dev/null
done
key=$("${AWS_CMD[@]}" iam create-access-key --user-name "$USER_NAME" --query AccessKey --output json)
kubectl --context "$CONTEXT" -n "$NAMESPACE" create secret generic bats-reporter-s3 \
  --from-literal=AWS_ACCESS_KEY_ID="$(jq -er .AccessKeyId <<<"$key")" \
  --from-literal=AWS_SECRET_ACCESS_KEY="$(jq -er .SecretAccessKey <<<"$key")" \
  --dry-run=client -o yaml | kubectl --context "$CONTEXT" apply --server-side --force-conflicts -f - >/dev/null
unset key

if kubectl --context "$CONTEXT" -n "$NAMESPACE" get deployment bats-reports >/dev/null 2>&1; then
  kubectl --context "$CONTEXT" -n "$NAMESPACE" rollout restart deployment/bats-reports >/dev/null
fi
echo "  ✔ ${NAMESPACE}: viewer S3 credentials refreshed in Moto account ${ACCOUNT}"
