#!/usr/bin/env bash
# scripts/list-moto-resources.sh: Inspect and list all AWS cloud resources in Moto Cloud across accounts.
#
# Inspects CARM accounts:
#   - 111111111111 (spoke-nonprod / Development & Test)
#   - 222222222222 (spoke-prod / Production)
#   - 123456789012 (Default root account / Leaked resource check)

set -euo pipefail

ENDPOINT="${MOTO_ENDPOINT:-http://localhost:5000}"
REGION="${AWS_DEFAULT_REGION:-us-east-1}"
E=(--endpoint-url="$ENDPOINT" --region "$REGION")

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

if ! curl -s -m 3 "${ENDPOINT}/" >/dev/null 2>&1; then
  echo "❌ Error: Moto is not responding at ${ENDPOINT}" >&2
  exit 1
fi

echo -e "${BLUE}================================================================================${NC}"
echo -e "${BLUE}                   MOTO CLOUD RESOURCES OVERVIEW (${ENDPOINT})${NC}"
echo -e "${BLUE}================================================================================${NC}"

for acc in "111111111111" "222222222222" "123456789012"; do
  desc=""
  case "$acc" in
    111111111111) desc="(spoke-nonprod / Development & Test)" ;;
    222222222222) desc="(spoke-prod / Production)" ;;
    123456789012) desc="(Default Root Account / Zero-Leak Guardrail)" ;;
  esac

  echo ""
  echo -e "${YELLOW}--------------------------------------------------------------------------------${NC}"
  echo -e "${YELLOW} AWS Account: ${acc} ${desc}${NC}"
  echo -e "${YELLOW}--------------------------------------------------------------------------------${NC}"

  if [[ "$acc" == "123456789012" ]]; then
    export AWS_ACCESS_KEY_ID=mock AWS_SECRET_ACCESS_KEY=mock AWS_SESSION_TOKEN=""
  else
    c=$(AWS_ACCESS_KEY_ID=mock AWS_SECRET_ACCESS_KEY=mock aws "${E[@]}" sts assume-role \
        --role-arn "arn:aws:iam::${acc}:role/ack-sqs-controller" \
        --role-session-name list-script \
        --query Credentials --output json 2>/dev/null || true)
    if [[ -n "$c" && "$c" != "null" ]]; then
      export AWS_ACCESS_KEY_ID=$(jq -r .AccessKeyId <<<"$c")
      export AWS_SECRET_ACCESS_KEY=$(jq -r .SecretAccessKey <<<"$c")
      export AWS_SESSION_TOKEN=$(jq -r .SessionToken <<<"$c")
    else
      echo "  (Could not assume role in ${acc}; querying with direct credentials)"
      export AWS_ACCESS_KEY_ID=mock AWS_SECRET_ACCESS_KEY=mock AWS_SESSION_TOKEN=""
    fi
  fi

  # 1. EKS Clusters & Managed Nodegroups
  echo -e " ${CYAN}[EKS Clusters]${NC}"
  clusters=$(aws "${E[@]}" eks list-clusters --query "clusters[]" --output text 2>/dev/null || true)
  if [[ -n "$clusters" && "$clusters" != "None" ]]; then
    for cl in $clusters; do
      status=$(aws "${E[@]}" eks describe-cluster --name "$cl" --query "cluster.status" --output text 2>/dev/null || true)
      arn=$(aws "${E[@]}" eks describe-cluster --name "$cl" --query "cluster.arn" --output text 2>/dev/null || true)
      echo -e "   • Cluster: ${GREEN}${cl}${NC} (status: ${status}, arn: ${arn})"
      ngs=$(aws "${E[@]}" eks list-nodegroups --cluster-name "$cl" --query "nodegroups[]" --output text 2>/dev/null || true)
      if [[ -n "$ngs" && "$ngs" != "None" ]]; then
        for ng in $ngs; do
          ng_status=$(aws "${E[@]}" eks describe-nodegroup --cluster-name "$cl" --nodegroup-name "$ng" --query "nodegroup.status" --output text 2>/dev/null || true)
          echo -e "     - Nodegroup: ${ng} (status: ${ng_status})"
        done
      fi
    done
  else
    echo "   (none)"
  fi

  # 2. EC2 VPCs, Subnets, and IGWs
  echo -e " ${CYAN}[EC2 Networking]${NC}"
  vpcs=$(aws "${E[@]}" ec2 describe-vpcs --query "Vpcs[?!IsDefault].[VpcId,CidrBlock,Tags[?Key=='Name'].Value|[0]]" --output text 2>/dev/null || true)
  if [[ -n "$vpcs" && "$vpcs" != "None" ]]; then
    while read -r vpc_id cidr name; do
      echo -e "   • VPC: ${GREEN}${name}${NC} (${vpc_id}, CIDR: ${cidr})"
      subnets=$(aws "${E[@]}" ec2 describe-subnets --filters "Name=vpc-id,Values=$vpc_id" --query "Subnets[].[SubnetId,CidrBlock]" --output text 2>/dev/null || true)
      while read -r s_id s_cidr; do
        if [[ -n "$s_id" ]]; then
          echo -e "     - Subnet: ${s_id} (CIDR: ${s_cidr})"
        fi
      done <<< "$subnets"
      igws=$(aws "${E[@]}" ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$vpc_id" --query "InternetGateways[].[InternetGatewayId]" --output text 2>/dev/null || true)
      for igw in $igws; do
        if [[ -n "$igw" ]]; then
          echo -e "     - IGW: ${igw}"
        fi
      done
    done <<< "$vpcs"
  else
    echo "   (none)"
  fi

  # 3. EC2 Security Groups
  echo -e " ${CYAN}[EC2 Security Groups]${NC}"
  sgs=$(aws "${E[@]}" ec2 describe-security-groups --query "SecurityGroups[?GroupName!='default'].[GroupId,GroupName]" --output text 2>/dev/null || true)
  if [[ -n "$sgs" && "$sgs" != "None" ]]; then
    while read -r sg_id sg_name; do
      echo -e "   • SG: ${sg_name} (${sg_id})"
    done <<< "$sgs"
  else
    echo "   (none)"
  fi

  # 4. SQS Queues
  echo -e " ${CYAN}[SQS Queues]${NC}"
  queues=$(aws "${E[@]}" sqs list-queues --query "QueueUrls[]" --output text 2>/dev/null || true)
  if [[ -n "$queues" && "$queues" != "None" ]]; then
    for q in $queues; do
      q_name=$(basename "$q")
      echo -e "   • Queue: ${q_name} (${q})"
    done
  else
    echo "   (none)"
  fi

  # 5. IAM Roles
  echo -e " ${CYAN}[IAM Roles]${NC}"
  roles=$(aws "${E[@]}" iam list-roles --query "Roles[?starts_with(RoleName, 'team-') || starts_with(RoleName, 'ack-') || starts_with(RoleName, 'orders-')].[RoleName]" --output text 2>/dev/null || true)
  if [[ -n "$roles" && "$roles" != "None" ]]; then
    for r in $roles; do
      echo -e "   • Role: ${r}"
    done
  else
    echo "   (none)"
  fi

done

echo ""
echo -e "${BLUE}================================================================================${NC}"
echo -e "${GREEN}✔ Inspection complete.${NC}"
echo -e "${BLUE}================================================================================${NC}"
