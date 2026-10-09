#!/usr/bin/env bash
# Moto compatibility for ACK S3 1.13.0: GetBucketEncryption returns
# ServerSideEncryptionConfigurationNotFoundError for a new bucket, and ACK's
# bucket hook dereferences the nil response. Seed AES256 encryption before ACK
# reconciles, then let ACK adopt and manage the bucket. No-op without a claim.
set -euo pipefail

CONTEXT=k3d-spoke-nonprod
NAMESPACE=platform-reports
ENDPOINT="${MOTO_ENDPOINT:-http://localhost:5000}"
ACCOUNT=111111111111

if ! kubectl --context "$CONTEXT" -n "$NAMESPACE" get testreportviewer bats-reports >/dev/null 2>&1; then
  echo "  ℹ Bats report claim is not installed; no Moto bucket to seed"
  exit 0
fi

bucket=$(kubectl --context "$CONTEXT" -n "$NAMESPACE" get testreportviewer bats-reports -o jsonpath='{.spec.bucketName}')
[[ -n "$bucket" ]] || { echo "✘ Bats report claim has no bucketName" >&2; exit 1; }

creds=$(AWS_MAX_ATTEMPTS=1 AWS_ACCESS_KEY_ID=mock-key AWS_SECRET_ACCESS_KEY=mock-secret \
  timeout 30s aws --cli-connect-timeout 5 --cli-read-timeout 20 --endpoint-url="$ENDPOINT" --region us-east-1 \
    sts assume-role --role-arn "arn:aws:iam::${ACCOUNT}:role/provisioner" \
    --role-session-name seed-bats-report-bucket --query Credentials --output json)
export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_MAX_ATTEMPTS=1
AWS_ACCESS_KEY_ID=$(jq -er .AccessKeyId <<<"$creds")
AWS_SECRET_ACCESS_KEY=$(jq -er .SecretAccessKey <<<"$creds")
AWS_SESSION_TOKEN=$(jq -er .SessionToken <<<"$creds")
unset creds
AWS_CMD=(timeout 30s aws --cli-connect-timeout 5 --cli-read-timeout 20 --endpoint-url="$ENDPOINT" --region us-east-1)

caller=$("${AWS_CMD[@]}" sts get-caller-identity --query Account --output text)
[[ "$caller" == "$ACCOUNT" ]] || { echo "✘ Moto account ${caller} is not ${ACCOUNT}" >&2; exit 1; }

exists=$("${AWS_CMD[@]}" s3api list-buckets --query "Buckets[?Name=='${bucket}'].Name" --output text)
if [[ -z "$exists" ]]; then
  "${AWS_CMD[@]}" s3api create-bucket --bucket "$bucket" >/dev/null
fi
"${AWS_CMD[@]}" s3api put-bucket-encryption --bucket "$bucket" \
  --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
"${AWS_CMD[@]}" s3api get-bucket-encryption --bucket "$bucket" >/dev/null
echo "  ✔ ${bucket}: AES256 encryption seeded in Moto account ${ACCOUNT} for ACK S3"

if [[ "${1:-}" == "--repair-controller" ]] && \
   kubectl --context "$CONTEXT" -n "$NAMESPACE" get bucket "$bucket" >/dev/null 2>&1; then
  terminal=$(kubectl --context "$CONTEXT" -n "$NAMESPACE" get bucket "$bucket" -o json |
    jq -r '[.status.conditions[]? | select(.type=="ACK.Terminal" and .status=="True")] | length')
  if [[ "$terminal" != "0" ]]; then
    # A previous nil-response panic can leave a stale Terminal condition.
    kubectl --context "$CONTEXT" -n "$NAMESPACE" patch bucket "$bucket" --subresource=status \
      --type=merge -p '{"status":{"conditions":[]}}' >/dev/null
  fi
  synced=$(kubectl --context "$CONTEXT" -n "$NAMESPACE" get bucket "$bucket" -o json |
    jq -r '[.status.conditions[]? | select(.type=="ACK.ResourceSynced" and .status=="True")] | length')
  if [[ "$synced" == "0" ]]; then
    kubectl --context "$CONTEXT" -n ack-system rollout restart deployment/ack-s3-controller-s3-chart >/dev/null
    kubectl --context "$CONTEXT" -n ack-system rollout status deployment/ack-s3-controller-s3-chart --timeout=90s >/dev/null
  fi
  for _ in {1..30}; do
    synced=$(kubectl --context "$CONTEXT" -n "$NAMESPACE" get bucket "$bucket" -o json |
      jq -r '[.status.conditions[]? | select(.type=="ACK.ResourceSynced" and .status=="True")] | length')
    [[ "$synced" != "0" ]] && exit 0
    sleep 3
  done
  echo "✘ ACK S3 Bucket ${bucket} did not reach ResourceSynced=True" >&2
  exit 1
fi
