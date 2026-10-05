#!/usr/bin/env bash
# Phase 5 D.1 (owner decision O-3): remove what a deregistered tenant app leaves behind (Phase 4 D-16).
#   - tenant namespace (label platform.lab/image-verification=enabled) with no registration and no
#     workload objects -> deleted (with its <name>-<env>-aws Secret)
#   - worker IAM user <name>-<env>-worker (moto, accounts 111111111111 / 222222222222) with no
#     registration -> keys, policies and user deleted
#   - DynamoDB table <name>-<env>-history with no registration -> reported; deleted only with PRUNE_DATA=1
# Registrations = Applications owned by the tenant-workloads-<tenant> ApplicationSets (Track B.2). Nothing registered is
# ever touched; with no registrations at all the script refuses to run.
# usage: orphans.sh [--dry-run]     (make orphans = --dry-run)
set -euo pipefail
E=(--endpoint-url=http://localhost:5000 --region us-east-1)
DRY=0; [[ "${1:-}" == --dry-run ]] && DRY=1
PREFIX=""; (( DRY )) && PREFIX="[dry-run] would remove: "
run() { if (( DRY )); then return 0; fi; "$@" >/dev/null; }
# Phase 5 D.1: anything a tenant app leaves behind after its registration is removed (Phase 4 D-16).
# Credentials (IAM user + Secret) and the empty namespace are removed; data (DynamoDB tables) is only
# reported unless PRUNE_DATA=1. Runs only after discovery found registrations; registered names are
# never touched.
targets=$(kubectl --context k3d-hub-cluster -n argocd get applications -o json | jq -r \
  '[.items[] | select(any(.metadata.ownerReferences[]?; .kind=="ApplicationSet" and (.name|startswith("tenant-workloads")))) | "\(.spec.destination.name):\(.spec.destination.namespace)"] | join(" ")')
[[ -n "$targets" ]] || { echo "✘ no tenant-workloads registrations found; refusing to compute orphans" >&2; exit 1; }
declare -A REG_NS=() REG_NAME=()
for t in $targets; do
  IFS=: read -r spoke ns <<<"$t"; REG_NS["${t}"]=1
  while read -r name env; do [[ -n "$name" ]] && REG_NAME["${name}-${env}"]=1; done < <(kubectl --context "k3d-${spoke}" -n "$ns" get queuebackedservice -o json 2>/dev/null | jq -r '.items[] | "\(.spec.name) \(.spec.environment)"')
  # registration also covers the default name of a namespace whose instance is not created yet
  REG_NAME["${ns}"]=1
done
orphans=0
for spoke in spoke-nonprod spoke-prod; do
  K=(kubectl --context "k3d-${spoke}")
  for ns in $("${K[@]}" get ns -l platform.lab/image-verification=enabled -o jsonpath='{.items[*].metadata.name}'); do
    # Team IaC namespaces and the platform network have their own lifecycle.
    [[ "$ns" == iac-* || "$ns" == platform-network ]] && continue
    [[ -n "${REG_NS[${spoke}:${ns}]:-}" ]] && continue
    busy=$("${K[@]}" -n "$ns" get deploy,pods,queuebackedservices --no-headers 2>/dev/null | wc -l)
    if (( busy == 0 )); then
      echo "${PREFIX}− ${spoke}/${ns}: not registered and empty -> namespace deleted (incl. its credential Secret)"
      run "${K[@]}" delete ns "$ns" --wait=false; orphans=$((orphans + 1))
    else
      echo "! ${spoke}/${ns}: not registered but still has ${busy} workload objects -> reported only"
    fi
  done
done
for account in 111111111111 222222222222; do
  creds=$(AWS_ACCESS_KEY_ID=mock-key AWS_SECRET_ACCESS_KEY=mock-secret aws "${E[@]}" sts assume-role \
    --role-arn "arn:aws:iam::${account}:role/post-bootstrap" --role-session-name post-bootstrap --query Credentials --output json)
  AC=(env AWS_ACCESS_KEY_ID="$(jq -r .AccessKeyId <<<"$creds")" AWS_SECRET_ACCESS_KEY="$(jq -r .SecretAccessKey <<<"$creds")" AWS_SESSION_TOKEN="$(jq -r .SessionToken <<<"$creds")")
  unset creds
  for user in $("${AC[@]}" aws "${E[@]}" iam list-users --query 'Users[].UserName' --output text); do
    [[ "$user" == *-worker ]] || continue
    [[ -n "${REG_NAME[${user%-worker}]:-}" ]] && continue
    for k in $("${AC[@]}" aws "${E[@]}" iam list-access-keys --user-name "$user" --query 'AccessKeyMetadata[].AccessKeyId' --output text); do
      run "${AC[@]}" aws "${E[@]}" iam delete-access-key --user-name "$user" --access-key-id "$k"; done
    for pol in $("${AC[@]}" aws "${E[@]}" iam list-user-policies --user-name "$user" --query 'PolicyNames' --output text); do
      run "${AC[@]}" aws "${E[@]}" iam delete-user-policy --user-name "$user" --policy-name "$pol"; done
    for arn in $("${AC[@]}" aws "${E[@]}" iam list-attached-user-policies --user-name "$user" --query 'AttachedPolicies[].PolicyArn' --output text); do
      run "${AC[@]}" aws "${E[@]}" iam detach-user-policy --user-name "$user" --policy-arn "$arn"; done
    run "${AC[@]}" aws "${E[@]}" iam delete-user --user-name "$user"
    echo "${PREFIX}− account ${account}: IAM user ${user} (deregistered app) deleted"; orphans=$((orphans + 1))
  done
  for table in $("${AC[@]}" aws "${E[@]}" dynamodb list-tables --query 'TableNames' --output text); do
    [[ "$table" == *-history ]] || continue
    [[ -n "${REG_NAME[${table%-history}]:-}" ]] && continue
    if [[ "${PRUNE_DATA:-0}" == 1 ]]; then
      run "${AC[@]}" aws "${E[@]}" dynamodb delete-table --table-name "$table"; orphans=$((orphans + 1))
      echo "${PREFIX}− account ${account}: DynamoDB table ${table} deleted (PRUNE_DATA=1)"
    else
      echo "! account ${account}: DynamoDB table ${table} belongs to no registered app (data kept; PRUNE_DATA=1 deletes it)"
    fi
  done
done
(( orphans == 0 )) && echo "✔ no orphaned credentials or namespaces" || true
