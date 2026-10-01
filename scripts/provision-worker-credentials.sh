#!/usr/bin/env bash
# Phase 3 D.3b: per-environment cloud credentials for a QueueBackedService worker.
#
# Creates (or reuses) IAM user <name>-<env>-worker in the target moto account, issues a fresh
# access key (older keys are deleted, so re-running rotates), and writes Secret
# <name>-<env>-aws (AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY) into the workload namespace.
# The blueprint mounts it via an optional envFrom. Secrets never go to Git; nothing is printed.
#
# Production equivalent: no static keys at all - IRSA / EKS Pod Identity per namespace.
#
# Usage: provision-worker-credentials.sh <spoke> <namespace> <name> <env> <account-id>
#   e.g. provision-worker-credentials.sh spoke-nonprod orders-dev orders dev 111111111111
set -euo pipefail

spoke="$1"; namespace="$2"; name="$3"; env="$4"; account="$5"
context="k3d-${spoke}"
user="${name}-${env}-worker"
E=(--endpoint-url=http://localhost:5000 --region us-east-1)

creds=$(AWS_ACCESS_KEY_ID=mock-key AWS_SECRET_ACCESS_KEY=mock-secret \
  aws "${E[@]}" sts assume-role --role-arn "arn:aws:iam::${account}:role/provisioner" \
  --role-session-name "provision-${user}" --query Credentials --output json)
export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
AWS_ACCESS_KEY_ID=$(jq -r .AccessKeyId <<<"$creds")
AWS_SECRET_ACCESS_KEY=$(jq -r .SecretAccessKey <<<"$creds")
AWS_SESSION_TOKEN=$(jq -r .SessionToken <<<"$creds")
unset creds

caller=$(aws "${E[@]}" sts get-caller-identity --query Account --output text)
[[ "$caller" == "$account" ]] || { echo "✘ assumed account ${caller}, expected ${account}" >&2; exit 1; }

aws "${E[@]}" iam get-user --user-name "$user" >/dev/null 2>&1 || aws "${E[@]}" iam create-user --user-name "$user" >/dev/null
for old in $(aws "${E[@]}" iam list-access-keys --user-name "$user" --query 'AccessKeyMetadata[].AccessKeyId' --output text); do
  aws "${E[@]}" iam delete-access-key --user-name "$user" --access-key-id "$old"
done
key=$(aws "${E[@]}" iam create-access-key --user-name "$user" --query AccessKey --output json)

kubectl --context "$context" -n "$namespace" create secret generic "${name}-${env}-aws" \
  --from-literal=AWS_ACCESS_KEY_ID="$(jq -r .AccessKeyId <<<"$key")" \
  --from-literal=AWS_SECRET_ACCESS_KEY="$(jq -r .SecretAccessKey <<<"$key")" \
  --dry-run=client -o yaml | kubectl --context "$context" apply --server-side --force-conflicts -f - >/dev/null
unset key

echo "✔ ${spoke}/${namespace}: Secret ${name}-${env}-aws holds a fresh key for IAM user ${user} in account ${account}"
