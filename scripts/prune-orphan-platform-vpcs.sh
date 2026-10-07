#!/usr/bin/env bash
# scripts/prune-orphan-platform-vpcs.sh: delete empty platform VPCs that no Kubernetes object references.
#
# Why: after moto loses its state (host reboot, `make start`), the ACK EC2 controller recreates
# the platform VPC from the stale VPC object (P0 finding F-7), while the internet gateway and
# security group cannot be recreated. The network repair (start-hub-spoke.sh / post-bootstrap.sh)
# then deletes the network objects with deletion-policy retain and Argo CD creates new ones, so
# a second VPC is created and the first is left behind (observed 2026-10-07: one empty orphan
# VPC per account). Harmless in moto, a leak on real AWS.
#
# Candidates are only VPCs that ACK created for namespace platform-network (tag
# services.k8s.aws/namespace=platform-network) in the account named by that namespace's CARM
# annotation. A candidate is deleted only if ALL hold:
#   - every VPC object in namespace platform-network on the spoke is ACK.ResourceSynced=True with a
#     status.vpcID (otherwise the account is not checked and the script fails), and the candidate
#     is none of those IDs: no VPC object in that namespace references it;
#   - it is empty: no subnets, no attached internet gateway, only the default security group,
#     only the main route table.
# Fail-closed (validated-10): a VPC that is not empty is kept and reported, an unsynced network or
# a failed AWS read is reported, and in all these cases the script exits 1. It never reports an
# account as clean without having read it.
#
# usage: scripts/prune-orphan-platform-vpcs.sh [--dry-run]
set -euo pipefail

DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true
ENDPOINT="${MOTO_ENDPOINT:-http://localhost:5000}"
E=(--endpoint-url="$ENDPOINT" --region "${AWS_DEFAULT_REGION:-us-east-1}")
SPOKES=(spoke-nonprod spoke-prod)
problems=0

as_account() {  # credentials for one moto account (STS AssumeRole, as the ACK controllers do)
  local creds
  creds=$(AWS_ACCESS_KEY_ID=mock-key AWS_SECRET_ACCESS_KEY=mock-secret AWS_SESSION_TOKEN='' aws "${E[@]}" \
    sts assume-role --role-arn "arn:aws:iam::$1:role/prune-orphan-vpcs" --role-session-name prune-orphan-vpcs \
    --query Credentials --output json)
  AWS_ACCESS_KEY_ID=$(jq -r .AccessKeyId <<<"$creds")
  AWS_SECRET_ACCESS_KEY=$(jq -r .SecretAccessKey <<<"$creds")
  AWS_SESSION_TOKEN=$(jq -r .SessionToken <<<"$creds")
  export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
}

for spoke in "${SPOKES[@]}"; do
  ctx="k3d-${spoke}"
  account=$(kubectl --context "$ctx" get ns platform-network \
    -o jsonpath='{.metadata.annotations.services\.k8s\.aws/owner-account-id}' 2>/dev/null || true)
  if ! vpcs_json=$(kubectl --context "$ctx" -n platform-network get vpc.ec2.services.k8s.aws -o json 2>/dev/null); then
    echo "  ✘ ${spoke}: cannot read the VPC objects in namespace platform-network" >&2
    problems=$((problems + 1)); continue
  fi
  # IDs of every VPC object in the namespace; all must be synced with an ID, or nothing is pruned
  unsynced=$(jq -r '[.items[] | select(([.status.conditions[]? | select(.type=="ACK.ResourceSynced")][0].status // "") != "True" or (.status.vpcID // "") == "") | .metadata.name] | join(",")' <<<"$vpcs_json")
  mapfile -t referenced < <(jq -r '.items[].status.vpcID // empty' <<<"$vpcs_json")
  if [[ -z "$account" || ${#referenced[@]} -eq 0 || -n "$unsynced" ]]; then
    echo "  ✘ ${spoke}: platform network not verifiable (account='${account}', VPC objects with an ID: ${#referenced[@]}, not synced: '${unsynced}'); nothing pruned" >&2
    problems=$((problems + 1)); continue
  fi
  as_account "$account"
  # Read the account's platform VPCs; a failed read is an error, never "no orphan"
  if ! all_ids=$(aws "${E[@]}" ec2 describe-vpcs \
        --filters "Name=tag:services.k8s.aws/namespace,Values=platform-network" \
        --query 'Vpcs[].VpcId' --output text); then
    echo "  ✘ ${spoke} (account ${account}): describe-vpcs failed; nothing pruned" >&2
    problems=$((problems + 1)); continue
  fi
  candidates=()
  for vpc in $all_ids; do
    [[ " ${referenced[*]} " == *" ${vpc} "* ]] || candidates+=("$vpc")
  done
  if (( ${#candidates[@]} == 0 )); then
    echo "  ✔ ${spoke} (account ${account}): only ${referenced[*]}, no orphan platform VPC"
    continue
  fi
  for vpc in "${candidates[@]}"; do
    subnets=$(aws "${E[@]}" ec2 describe-subnets --filters "Name=vpc-id,Values=${vpc}" --query 'length(Subnets)' --output text)
    igws=$(aws "${E[@]}" ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=${vpc}" --query 'length(InternetGateways)' --output text)
    sgs=$(aws "${E[@]}" ec2 describe-security-groups --filters "Name=vpc-id,Values=${vpc}" --query 'length(SecurityGroups[?GroupName!=`default`])' --output text)
    rts=$(aws "${E[@]}" ec2 describe-route-tables --filters "Name=vpc-id,Values=${vpc}" --query 'length(RouteTables[?!(Associations[?Main])])' --output text)
    if [[ "$subnets" == 0 && "$igws" == 0 && "$sgs" == 0 && "$rts" == 0 ]]; then
      if $DRY_RUN; then
        echo "  ↻ ${spoke} (account ${account}): would delete empty orphan VPC ${vpc} (referenced: ${referenced[*]})"
      else
        aws "${E[@]}" ec2 delete-vpc --vpc-id "$vpc"
        echo "  ✔ ${spoke} (account ${account}): deleted empty orphan VPC ${vpc} (referenced: ${referenced[*]})"
      fi
    else
      echo "  ✘ ${spoke} (account ${account}): kept ${vpc}, not empty (subnets=${subnets} igws=${igws} non-default SGs=${sgs} extra route tables=${rts}); investigate" >&2
      problems=$((problems + 1))
    fi
  done
done

(( problems == 0 )) || { echo "✘ prune-orphan-platform-vpcs: ${problems} problem(s), see above" >&2; exit 1; }
