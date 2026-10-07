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
# A VPC is deleted only if ALL hold:
#   - the spoke's VPC object (platform-network/platform-vpc) is ACK.ResourceSynced=True and has a
#     status.vpcID, in the account named by the namespace's CARM annotation;
#   - the VPC is tagged services.k8s.aws/namespace=platform-network and is not that vpcID;
#   - it is empty: no subnets, no attached internet gateway, only the default security group,
#     only the main route table.
# Anything else is reported and kept.
#
# usage: scripts/prune-orphan-platform-vpcs.sh [--dry-run]
set -euo pipefail

DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true
ENDPOINT="${MOTO_ENDPOINT:-http://localhost:5000}"
E=(--endpoint-url="$ENDPOINT" --region "${AWS_DEFAULT_REGION:-us-east-1}")
SPOKES=(spoke-nonprod spoke-prod)
kept=0

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
  vpc_json=$(kubectl --context "$ctx" -n platform-network get vpc platform-vpc -o json 2>/dev/null || true)
  live=$(jq -r '.status.vpcID // empty' <<<"${vpc_json:-{\}}")
  synced=$(jq -r '[.status.conditions[]? | select(.type=="ACK.ResourceSynced")][0].status // empty' <<<"${vpc_json:-{\}}")
  if [[ -z "$account" || -z "$live" || "$synced" != "True" ]]; then
    echo "  - ${spoke}: platform VPC not synced yet (account='${account}', vpcID='${live}', synced='${synced}'); nothing pruned"
    continue
  fi
  as_account "$account"
  mapfile -t candidates < <(aws "${E[@]}" ec2 describe-vpcs \
    --filters "Name=tag:services.k8s.aws/namespace,Values=platform-network" \
    --query 'Vpcs[].VpcId' --output text | tr '\t' '\n' | grep -v -x -e "$live" -e '' || true)
  if (( ${#candidates[@]} == 0 )); then
    echo "  ✔ ${spoke} (account ${account}): only ${live}, no orphan platform VPC"
    continue
  fi
  for vpc in "${candidates[@]}"; do
    subnets=$(aws "${E[@]}" ec2 describe-subnets --filters "Name=vpc-id,Values=${vpc}" --query 'length(Subnets)' --output text)
    igws=$(aws "${E[@]}" ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=${vpc}" --query 'length(InternetGateways)' --output text)
    sgs=$(aws "${E[@]}" ec2 describe-security-groups --filters "Name=vpc-id,Values=${vpc}" --query 'length(SecurityGroups[?GroupName!=`default`])' --output text)
    rts=$(aws "${E[@]}" ec2 describe-route-tables --filters "Name=vpc-id,Values=${vpc}" --query 'length(RouteTables[?!(Associations[?Main])])' --output text)
    if [[ "$subnets" == 0 && "$igws" == 0 && "$sgs" == 0 && "$rts" == 0 ]]; then
      if $DRY_RUN; then
        echo "  ↻ ${spoke} (account ${account}): would delete empty orphan VPC ${vpc} (live: ${live})"
      else
        aws "${E[@]}" ec2 delete-vpc --vpc-id "$vpc"
        echo "  ✔ ${spoke} (account ${account}): deleted empty orphan VPC ${vpc} (live: ${live})"
      fi
    else
      echo "  ⚠ ${spoke} (account ${account}): kept ${vpc}, not empty (subnets=${subnets} igws=${igws} non-default SGs=${sgs} extra route tables=${rts}); investigate" >&2
      kept=$((kept + 1))
    fi
  done
done

(( kept == 0 )) || exit 1
