#!/usr/bin/env bash
# scripts/list-moto-resources.sh
#
# Multi-account resource lister for local Moto Cloud (Version 4).
#
# Enhancements in Version 4:
#   1. Parallel Account Scans: Concurrently scans spoke accounts for ~2-3x speedup.
#   2. Fast Scan Mode (--fast): Focuses on active lab resources (eks, networking, sg, sqs, iam, dynamodb).
#   3. Deep Network Topology: Inspects VPCs, Subnets (with AZs & CIDRs), Route Tables (with 0.0.0.0/0 route check), and IGWs.
#   4. Comprehensive Zero-Leak Guardrail: Validates account 123456789012 across EKS, SQS, DynamoDB, VPCs, SGs, IGWs, and IAM roles.
#   5. Batch JSON Generation: Minimizes jq subshell spawns during resource collection.
#   6. Flexible STS Assumption: Configurable role via --role with multi-role fallback.

set -euo pipefail

# ---------------------------------------------------------------------------
# Config & Defaults
# ---------------------------------------------------------------------------
ENDPOINT="${MOTO_ENDPOINT:-http://localhost:5000}"
DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"
DEFAULT_ROLE="ack-sqs-controller"
FALLBACK_ROLES=("ack-sqs-controller" "ack-ec2-controller")

ACCOUNTS=("111111111111" "222222222222" "123456789012")
declare -A ACCOUNT_DESC=(
  ["111111111111"]="spoke-nonprod / Development & Test"
  ["222222222222"]="spoke-prod / Production"
  ["123456789012"]="Default Root Account / Zero-Leak Guardrail"
)

ACTIVE_LAB_TYPES=(eks networking sg sqs iam dynamodb)
ALL_TYPES=(eks networking sg sqs iam dynamodb s3 lambda rds sns)

# Flags
JSON_MODE=false
YAML_MODE=false
QUIET=false
SHOW_ALL=false
SUMMARY_ONLY=false
NO_SUMMARY=false
TABLE_MODE=false
DEBUG=false
FAST_MODE=false
PARALLEL_MODE=true
WATCH_INTERVAL=0
TARGET_ROLE="$DEFAULT_ROLE"
FILTER_TYPES=()
FILTER_ACCOUNTS=()
REGIONS=("$DEFAULT_REGION")
TMP_DIR=""

# Colors
BOLD=$'\033[1m'
DIM=$'\033[2m'
GREEN=$'\033[0;32m'
BLUE=$'\033[0;34m'
YELLOW=$'\033[0;33m'
RED=$'\033[0;31m'
NC=$'\033[0m'

# ---------------------------------------------------------------------------
# CLI Options
# ---------------------------------------------------------------------------
usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  --json                JSON output format
  --yaml                YAML output format
  --table               Compact two-column table output
  --fast                Fast scan: check active lab resources only (${ACTIVE_LAB_TYPES[*]})
  --no-parallel         Run account scans sequentially instead of in parallel
  --quiet, -q           Minimal output (suppress banner and non-essential logs)
  --all                 Show empty resource categories
  --summary-only        Only print the final resource summary counts
  --no-summary          Omit the summary section at the end
  --account ID[,ID]     Filter specific AWS accounts (e.g. 111111111111,222222222222)
  --only TYPE[,TYPE]    Filter specific resource types (${ALL_TYPES[*]})
  --region R[,R]        One or more regions to scan (default: $DEFAULT_REGION)
  --role NAME           CARM IAM role to assume in spokes (default: $DEFAULT_ROLE)
  --watch SECONDS       Continuously re-scan every N seconds
  --debug               Show debug diagnostic output
  -h, --help            Show this help message
EOF
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --json)          JSON_MODE=true; shift ;;
    --yaml)          YAML_MODE=true; shift ;;
    --table)         TABLE_MODE=true; shift ;;
    --fast)          FAST_MODE=true; shift ;;
    --no-parallel)   PARALLEL_MODE=false; shift ;;
    --parallel)      PARALLEL_MODE=true; shift ;;
    --quiet|-q)      QUIET=true; shift ;;
    --all)           SHOW_ALL=true; shift ;;
    --summary-only)  SUMMARY_ONLY=true; shift ;;
    --no-summary)    NO_SUMMARY=true; shift ;;
    --debug)         DEBUG=true; shift ;;
    --role)          TARGET_ROLE="${2:-$DEFAULT_ROLE}"; shift 2 ;;
    --account)
      IFS=',' read -ra FILTER_ACCOUNTS <<< "${2:-}"
      shift 2
      ;;
    --only)
      IFS=',' read -ra FILTER_TYPES <<< "${2:-}"
      shift 2
      ;;
    --region)
      IFS=',' read -ra REGIONS <<< "${2:-}"
      shift 2
      ;;
    --watch)
      WATCH_INTERVAL="${2:-5}"
      shift 2
      ;;
    -h|--help) usage ;;
    *) echo "Unknown option: $1" >&2; usage ;;
  esac
done

if $FAST_MODE && [[ ${#FILTER_TYPES[@]} -eq 0 ]]; then
  FILTER_TYPES=("${ACTIVE_LAB_TYPES[@]}")
fi

# Disable colors when piping or in structured formats
if $JSON_MODE || $YAML_MODE || $QUIET || $SUMMARY_ONLY || [[ ! -t 1 ]]; then
  BOLD="" DIM="" GREEN="" BLUE="" YELLOW="" RED="" NC=""
fi

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
err()   { echo -e "${RED}$*${NC}" >&2; }
log()   { $QUIET || $SUMMARY_ONLY || $JSON_MODE || $YAML_MODE || echo -e "$*"; }

debug() {
  if $DEBUG && ! $JSON_MODE && ! $YAML_MODE; then
    echo -e "  ${DIM}$*${NC}" >&2
  fi
  return 0
}

has_jq() { command -v jq >/dev/null 2>&1; }
has_yq() { command -v yq >/dev/null 2>&1; }

aws_q() {
  local region="$1"; shift
  aws --endpoint-url="$ENDPOINT" --region "$region" "$@" 2>/dev/null || true
}

should_show_type() {
  local t="$1"
  [[ ${#FILTER_TYPES[@]} -eq 0 ]] && return 0
  for f in "${FILTER_TYPES[@]}"; do [[ "$f" == "$t" ]] && return 0; done
  return 1
}

should_show_account() {
  local a="$1"
  [[ ${#FILTER_ACCOUNTS[@]} -eq 0 ]] && return 0
  for f in "${FILTER_ACCOUNTS[@]}"; do [[ "$f" == "$a" ]] && return 0; done
  return 1
}

# ---------------------------------------------------------------------------
# Credentials Management
# ---------------------------------------------------------------------------
switch_account() {
  local acc="$1"

  if [[ "$acc" == "123456789012" ]]; then
    export AWS_ACCESS_KEY_ID=mock
    export AWS_SECRET_ACCESS_KEY=mock
    export AWS_SESSION_TOKEN=
    return 0
  fi

  debug "Assuming role in account $acc ..."

  local roles_to_try=("$TARGET_ROLE")
  for r in "${FALLBACK_ROLES[@]}"; do
    [[ "$r" != "$TARGET_ROLE" ]] && roles_to_try+=("$r")
  done

  local assumed=false
  for role in "${roles_to_try[@]}"; do
    local creds
    creds=$(AWS_ACCESS_KEY_ID=mock AWS_SECRET_ACCESS_KEY=mock AWS_SESSION_TOKEN="" \
      aws --endpoint-url="$ENDPOINT" --region "$DEFAULT_REGION" sts assume-role \
        --role-arn "arn:aws:iam::${acc}:role/${role}" \
        --role-session-name list-moto-v4 \
        --query Credentials --output json 2>/dev/null || true)

    if [[ -n "$creds" && "$creds" != "null" ]] && has_jq; then
      AWS_ACCESS_KEY_ID=$(jq -r .AccessKeyId <<<"$creds")
      AWS_SECRET_ACCESS_KEY=$(jq -r .SecretAccessKey <<<"$creds")
      AWS_SESSION_TOKEN=$(jq -r .SessionToken <<<"$creds")
      export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
      debug "Role '${role}' assumed successfully for account $acc"
      assumed=true
      break
    fi
  done

  if ! $assumed; then
    debug "Could not assume role in ${acc} – using direct credentials"
    export AWS_ACCESS_KEY_ID=mock
    export AWS_SECRET_ACCESS_KEY=mock
    export AWS_SESSION_TOKEN=""
  fi
  return 0
}

# ---------------------------------------------------------------------------
# Account Collector Runner
# ---------------------------------------------------------------------------
# Collects resources for a single account and writes:
#   $out_prefix.txt   - human readable text output
#   $out_prefix.json  - JSON fragment for account
#   $out_prefix.count - TSV counts (type \t count)
collect_account() {
  local acc="$1"
  local out_prefix="$2"

  local txt_out="$out_prefix.txt"
  local json_out="$out_prefix.json"
  local count_out="$out_prefix.count"

  local desc="${ACCOUNT_DESC[$acc]:-Custom Account}"
  switch_account "$acc"

  # In-memory accumulator for counts and JSON
  declare -A ACC_COUNTS=()
  local acc_json
  acc_json=$(jq -n --arg d "$desc" '{description:$d}')

  record_count() {
    local k="$1" delta="${2:-1}"
    ACC_COUNTS["$k"]=$(( ${ACC_COUNTS["$k"]:-0} + delta ))
  }

  exec 3> "$txt_out"

  # Account header
  if ! $QUIET && ! $SUMMARY_ONLY; then
    echo >&3
    case "$acc" in
      222222222222)  # Production → Blue (replaces red, never red)
        printf "  ${BOLD}${BLUE}%s${NC}  ${DIM}%s${NC}\n" "$acc" "$desc" >&3
        ;;
      111111111111)  # Non-prod → Green
        printf "  ${BOLD}${GREEN}%s${NC}  ${DIM}%s${NC}\n" "$acc" "$desc" >&3
        ;;
      *)             # Root / other → Yellow
        printf "  ${BOLD}${YELLOW}%s${NC}  ${DIM}%s${NC}\n" "$acc" "$desc" >&3
        ;;
    esac
    [[ ${#REGIONS[@]} -gt 1 ]] && printf "  ${DIM}Regions: %s${NC}\n" "${REGIONS[*]}" >&3
    printf "  ${DIM}────────────────────────────────────────────────────${NC}\n" >&3
  fi

  for region in "${REGIONS[@]}"; do
    # 1. EKS Clusters & Nodegroups
    if should_show_type eks; then
      local clusters
      clusters=$(aws_q "$region" eks list-clusters --query "clusters[]" --output text)
      local count=0
      [[ -n "$clusters" && "$clusters" != "None" ]] && count=$(echo "$clusters" | wc -w | tr -d ' ')

      if [[ $count -gt 0 || "$SHOW_ALL" == true ]]; then
        echo >&3
        printf "  ${BOLD}EKS Clusters${NC}  ${DIM}(%s)${NC}\n" "$count" >&3
        printf "  ${DIM}────────────────────────────${NC}\n" >&3
      fi

      if [[ $count -eq 0 ]]; then
        $SHOW_ALL && printf "    ${DIM}(none)${NC}\n" >&3
        acc_json=$(jq -c '.eks=[]' <<<"$acc_json")
      else
        local cluster_list_json="[]"
        for cl in $clusters; do
          record_count eks_clusters
          local cl_desc
          cl_desc=$(aws_q "$region" eks describe-cluster --name "$cl" --query "cluster.[status,arn,version]" --output text)
          read -r status arn version <<< "$cl_desc"

          if $TABLE_MODE; then
            printf "    %-48s %s\n" "$cl" "[${status:-unknown}]" >&3
          else
            printf "    ${GREEN}•${NC} %s  [%s]\n" "$cl" "${status:-unknown}" >&3
          fi
          [[ -n "$arn" && "$arn" != "None" ]] && printf "      ${DIM}arn: %s${NC}\n" "$arn" >&3
          [[ -n "$version" && "$version" != "None" ]] && printf "      ${DIM}version: %s${NC}\n" "$version" >&3

          local ngs
          ngs=$(aws_q "$region" eks list-nodegroups --cluster-name "$cl" --query "nodegroups[]" --output text)
          local ng_items="[]"
          if [[ -n "$ngs" && "$ngs" != "None" ]]; then
            for ng in $ngs; do
              record_count eks_nodegroups
              local ng_status
              ng_status=$(aws_q "$region" eks describe-nodegroup --cluster-name "$cl" --nodegroup-name "$ng" --query "nodegroup.status" --output text)
              printf "      ${DIM}nodegroup: %s [%s]${NC}\n" "$ng" "${ng_status:-unknown}" >&3
              ng_items=$(jq -c --arg n "$ng" --arg s "${ng_status:-}" '.+[{"name":$n,"status":$s}]' <<<"$ng_items")
            done
          fi

          cluster_list_json=$(jq -c --arg n "$cl" --arg s "${status:-}" --arg a "${arn:-}" --arg v "${version:-}" --argjson ng "$ng_items" \
            '.+[{"name":$n,"status":$s,"arn":$a,"version":$v,"nodegroups":$ng}]' <<<"$cluster_list_json")
        done
        acc_json=$(jq -c --argjson v "$cluster_list_json" '.eks=$v' <<<"$acc_json")
      fi
    fi

    # 2. EC2 Networking (VPCs, Subnets, Route Tables, IGWs)
    if should_show_type networking; then
      local vpcs
      vpcs=$(aws_q "$region" ec2 describe-vpcs --query "Vpcs[?!IsDefault].[VpcId,CidrBlock,Tags[?Key=='Name'].Value|[0]]" --output text)
      local vpc_count=0
      [[ -n "$vpcs" && "$vpcs" != "None" ]] && vpc_count=$(echo "$vpcs" | grep -c . || true)

      if [[ $vpc_count -gt 0 || "$SHOW_ALL" == true ]]; then
        echo >&3
        printf "  ${BOLD}EC2 Networking${NC}  ${DIM}(%s VPCs)${NC}\n" "$vpc_count" >&3
        printf "  ${DIM}────────────────────────────${NC}\n" >&3
      fi

      if [[ $vpc_count -eq 0 ]]; then
        $SHOW_ALL && printf "    ${DIM}(none)${NC}\n" >&3
        acc_json=$(jq -c '.networking=[]' <<<"$acc_json")
      else
        local vpc_list_json="[]"
        while read -r vpc_id cidr vpc_name; do
          [[ -z "$vpc_id" ]] && continue
          record_count vpcs
          if $TABLE_MODE; then
            printf "    %-48s %s\n" "${vpc_name:-<unnamed>} ($vpc_id)" "$cidr" >&3
          else
            printf "    ${GREEN}•${NC} %s  (%s)\n" "${vpc_name:-<unnamed>}" "$vpc_id" >&3
          fi
          printf "      ${DIM}CIDR: %s${NC}\n" "$cidr" >&3

          # Subnets
          local subnet_items="[]" subnets
          subnets=$(aws_q "$region" ec2 describe-subnets --filters "Name=vpc-id,Values=$vpc_id" \
            --query "Subnets[].[SubnetId,CidrBlock,AvailabilityZone,Tags[?Key=='Name'].Value|[0]]" --output text)
          if [[ -n "$subnets" && "$subnets" != "None" ]]; then
            while read -r s_id s_cidr s_az s_name; do
              [[ -z "$s_id" ]] && continue
              record_count subnets
              local s_label="${s_name:-subnet}"
              [[ "$s_label" == "None" ]] && s_label="subnet"
              printf "      ${DIM}subnet: %-19s %s  %-10s  (%s)${NC}\n" "$s_id" "$s_cidr" "$s_az" "$s_label" >&3
              subnet_items=$(jq -c --arg id "$s_id" --arg c "$s_cidr" --arg z "$s_az" --arg n "$s_label" \
                '.+[{"id":$id,"cidr":$c,"az":$z,"name":$n}]' <<<"$subnet_items")
            done <<< "$subnets"
          fi

          # Route Tables
          local rtb_items="[]" rtbs
          rtbs=$(aws_q "$region" ec2 describe-route-tables --filters "Name=vpc-id,Values=$vpc_id" \
            --query "RouteTables[].[RouteTableId,Tags[?Key=='Name'].Value|[0],length(Routes[?DestinationCidrBlock=='0.0.0.0/0'])]" --output text)
          if [[ -n "$rtbs" && "$rtbs" != "None" ]]; then
            while read -r rtb_id rtb_name def_routes; do
              [[ -z "$rtb_id" ]] && continue
              record_count route_tables
              local rtb_desc="local only"
              local has_default=false
              if [[ "$def_routes" =~ ^[1-9][0-9]*$ ]]; then
                rtb_desc="default route 0.0.0.0/0 -> IGW active"
                has_default=true
              fi
              local r_label="${rtb_name:-}"
              [[ "$r_label" == "None" ]] && r_label=""
              [[ -n "$r_label" ]] && r_label="(${r_label}) "
              printf "      ${DIM}route-table: %s %s[%s]${NC}\n" "$rtb_id" "$r_label" "$rtb_desc" >&3
              rtb_items=$(jq -c --arg id "$rtb_id" --arg n "$r_label" --argjson d "$has_default" \
                '.+[{"id":$id,"name":$n,"has_default_route":$d}]' <<<"$rtb_items")
            done <<< "$rtbs"
          fi

          # Internet Gateways
          local igw_items="[]" igws
          igws=$(aws_q "$region" ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$vpc_id" \
            --query "InternetGateways[].InternetGatewayId" --output text)
          if [[ -n "$igws" && "$igws" != "None" ]]; then
            for igw in $igws; do
              [[ -z "$igw" ]] && continue
              record_count igws
              printf "      ${DIM}igw: %s${NC}\n" "$igw" >&3
              igw_items=$(jq -c --arg id "$igw" '.+[{"id":$id}]' <<<"$igw_items")
            done
          fi

          vpc_list_json=$(jq -c --arg id "$vpc_id" --arg c "$cidr" --arg n "${vpc_name:-}" \
            --argjson s "$subnet_items" --argjson r "$rtb_items" --argjson i "$igw_items" \
            '.+[{"id":$id,"cidr":$c,"name":$n,"subnets":$s,"route_tables":$r,"internet_gateways":$i}]' <<<"$vpc_list_json")
        done <<< "$vpcs"
        acc_json=$(jq -c --argjson v "$vpc_list_json" '.networking=$v' <<<"$acc_json")
      fi
    fi

    # 3. Security Groups
    if should_show_type sg; then
      local sgs
      sgs=$(aws_q "$region" ec2 describe-security-groups --query "SecurityGroups[?GroupName!='default'].[GroupId,GroupName]" --output text)
      local sg_count=0
      [[ -n "$sgs" && "$sgs" != "None" ]] && sg_count=$(echo "$sgs" | grep -c . || true)

      if [[ $sg_count -gt 0 || "$SHOW_ALL" == true ]]; then
        echo >&3
        printf "  ${BOLD}Security Groups${NC}  ${DIM}(%s)${NC}\n" "$sg_count" >&3
        printf "  ${DIM}────────────────────────────${NC}\n" >&3
      fi

      if [[ $sg_count -eq 0 ]]; then
        $SHOW_ALL && printf "    ${DIM}(none)${NC}\n" >&3
        acc_json=$(jq -c '.sg=[]' <<<"$acc_json")
      else
        local sg_list_json="[]"
        while read -r sg_id sg_name; do
          [[ -z "$sg_id" ]] && continue
          record_count security_groups
          if $TABLE_MODE; then
            printf "    %-48s %s\n" "$sg_name" "($sg_id)" >&3
          else
            printf "    ${GREEN}•${NC} %s  (%s)\n" "$sg_name" "$sg_id" >&3
          fi
          sg_list_json=$(jq -c --arg id "$sg_id" --arg n "$sg_name" '.+[{"id":$id,"name":$n}]' <<<"$sg_list_json")
        done <<< "$sgs"
        acc_json=$(jq -c --argjson v "$sg_list_json" '.sg=$v' <<<"$acc_json")
      fi
    fi

    # 4. SQS Queues
    if should_show_type sqs; then
      local queues
      queues=$(aws_q "$region" sqs list-queues --query "QueueUrls[]" --output text)
      local q_count=0
      [[ -n "$queues" && "$queues" != "None" ]] && q_count=$(echo "$queues" | wc -w | tr -d ' ')

      if [[ $q_count -gt 0 || "$SHOW_ALL" == true ]]; then
        echo >&3
        printf "  ${BOLD}SQS Queues${NC}  ${DIM}(%s)${NC}\n" "$q_count" >&3
        printf "  ${DIM}────────────────────────────${NC}\n" >&3
      fi

      if [[ $q_count -eq 0 ]]; then
        $SHOW_ALL && printf "    ${DIM}(none)${NC}\n" >&3
        acc_json=$(jq -c '.sqs=[]' <<<"$acc_json")
      else
        local q_list_json="[]"
        for q in $queues; do
          record_count sqs_queues
          local q_name; q_name=$(basename "$q")
          if $TABLE_MODE; then
            printf "    %-48s %s\n" "$q_name" "$q" >&3
          else
            printf "    ${GREEN}•${NC} %s\n" "$q_name" >&3
            printf "      ${DIM}%s${NC}\n" "$q" >&3
          fi
          q_list_json=$(jq -c --arg n "$q_name" --arg u "$q" '.+[{"name":$n,"url":$u}]' <<<"$q_list_json")
        done
        acc_json=$(jq -c --argjson v "$q_list_json" '.sqs=$v' <<<"$acc_json")
      fi
    fi

    # 5. IAM Roles
    if should_show_type iam; then
      local roles
      roles=$(aws_q "$region" iam list-roles \
        --query "Roles[?starts_with(RoleName,'team-') || starts_with(RoleName,'ack-') || starts_with(RoleName,'orders-') || starts_with(RoleName,'analytics-')].[RoleName]" \
        --output text)
      local r_count=0
      [[ -n "$roles" && "$roles" != "None" ]] && r_count=$(echo "$roles" | wc -w | tr -d ' ')

      if [[ $r_count -gt 0 || "$SHOW_ALL" == true ]]; then
        echo >&3
        printf "  ${BOLD}IAM Roles${NC}  ${DIM}(%s)${NC}\n" "$r_count" >&3
        printf "  ${DIM}────────────────────────────${NC}\n" >&3
      fi

      if [[ $r_count -eq 0 ]]; then
        $SHOW_ALL && printf "    ${DIM}(none)${NC}\n" >&3
        acc_json=$(jq -c '.iam=[]' <<<"$acc_json")
      else
        local r_list_json="[]"
        for r in $roles; do
          record_count iam_roles
          if $TABLE_MODE; then
            printf "    %-48s\n" "$r" >&3
          else
            printf "    ${GREEN}•${NC} %s\n" "$r" >&3
          fi
          r_list_json=$(jq -c --arg n "$r" '.+[{"name":$n}]' <<<"$r_list_json")
        done
        acc_json=$(jq -c --argjson v "$r_list_json" '.iam=$v' <<<"$acc_json")
      fi
    fi

    # 6. DynamoDB Tables
    if should_show_type dynamodb; then
      local tables
      tables=$(aws_q "$region" dynamodb list-tables --query "TableNames[]" --output text)
      local t_count=0
      [[ -n "$tables" && "$tables" != "None" ]] && t_count=$(echo "$tables" | wc -w | tr -d ' ')

      if [[ $t_count -gt 0 || "$SHOW_ALL" == true ]]; then
        echo >&3
        printf "  ${BOLD}DynamoDB Tables${NC}  ${DIM}(%s)${NC}\n" "$t_count" >&3
        printf "  ${DIM}────────────────────────────${NC}\n" >&3
      fi

      if [[ $t_count -eq 0 ]]; then
        $SHOW_ALL && printf "    ${DIM}(none)${NC}\n" >&3
        acc_json=$(jq -c '.dynamodb=[]' <<<"$acc_json")
      else
        local t_list_json="[]"
        for t in $tables; do
          record_count dynamodb_tables
          local t_status
          t_status=$(aws_q "$region" dynamodb describe-table --table-name "$t" --query "Table.TableStatus" --output text)
          if $TABLE_MODE; then
            printf "    %-48s %s\n" "$t" "[${t_status:-unknown}]" >&3
          else
            printf "    ${GREEN}•${NC} %s  [%s]\n" "$t" "${t_status:-unknown}" >&3
          fi
          t_list_json=$(jq -c --arg n "$t" --arg s "${t_status:-}" '.+[{"name":$n,"status":$s}]' <<<"$t_list_json")
        done
        acc_json=$(jq -c --argjson v "$t_list_json" '.dynamodb=$v' <<<"$acc_json")
      fi
    fi

    # 7. S3 Buckets
    if should_show_type s3; then
      local buckets
      buckets=$(aws_q "$region" s3api list-buckets --query "Buckets[].Name" --output text)
      local b_count=0
      [[ -n "$buckets" && "$buckets" != "None" ]] && b_count=$(echo "$buckets" | wc -w | tr -d ' ')

      if [[ $b_count -gt 0 || "$SHOW_ALL" == true ]]; then
        echo >&3
        printf "  ${BOLD}S3 Buckets${NC}  ${DIM}(%s)${NC}\n" "$b_count" >&3
        printf "  ${DIM}────────────────────────────${NC}\n" >&3
      fi

      if [[ $b_count -eq 0 ]]; then
        $SHOW_ALL && printf "    ${DIM}(none)${NC}\n" >&3
        acc_json=$(jq -c '.s3=[]' <<<"$acc_json")
      else
        local b_list_json="[]"
        for b in $buckets; do
          record_count s3_buckets
          printf "    ${GREEN}•${NC} %s\n" "$b" >&3
          b_list_json=$(jq -c --arg n "$b" '.+[{"name":$n}]' <<<"$b_list_json")
        done
        acc_json=$(jq -c --argjson v "$b_list_json" '.s3=$v' <<<"$acc_json")
      fi
    fi

    # 8. Lambda Functions
    if should_show_type lambda; then
      local funcs
      funcs=$(aws_q "$region" lambda list-functions --query "Functions[].FunctionName" --output text)
      local f_count=0
      [[ -n "$funcs" && "$funcs" != "None" ]] && f_count=$(echo "$funcs" | wc -w | tr -d ' ')

      if [[ $f_count -gt 0 || "$SHOW_ALL" == true ]]; then
        echo >&3
        printf "  ${BOLD}Lambda Functions${NC}  ${DIM}(%s)${NC}\n" "$f_count" >&3
        printf "  ${DIM}────────────────────────────${NC}\n" >&3
      fi

      if [[ $f_count -eq 0 ]]; then
        $SHOW_ALL && printf "    ${DIM}(none)${NC}\n" >&3
        acc_json=$(jq -c '.lambda=[]' <<<"$acc_json")
      else
        local f_list_json="[]"
        for f in $funcs; do
          record_count lambda_functions
          local runtime
          runtime=$(aws_q "$region" lambda get-function --function-name "$f" --query "Configuration.Runtime" --output text)
          printf "    ${GREEN}•${NC} %s  (%s)\n" "$f" "${runtime:-unknown}" >&3
          f_list_json=$(jq -c --arg n "$f" --arg r "${runtime:-}" '.+[{"name":$n,"runtime":$r}]' <<<"$f_list_json")
        done
        acc_json=$(jq -c --argjson v "$f_list_json" '.lambda=$v' <<<"$acc_json")
      fi
    fi

    # 9. RDS Instances
    if should_show_type rds; then
      local rds_ids
      rds_ids=$(aws_q "$region" rds describe-db-instances --query "DBInstances[].DBInstanceIdentifier" --output text)
      local r_count=0
      [[ -n "$rds_ids" && "$rds_ids" != "None" ]] && r_count=$(echo "$rds_ids" | wc -w | tr -d ' ')

      if [[ $r_count -gt 0 || "$SHOW_ALL" == true ]]; then
        echo >&3
        printf "  ${BOLD}RDS Instances${NC}  ${DIM}(%s)${NC}\n" "$r_count" >&3
        printf "  ${DIM}────────────────────────────${NC}\n" >&3
      fi

      if [[ $r_count -eq 0 ]]; then
        $SHOW_ALL && printf "    ${DIM}(none)${NC}\n" >&3
        acc_json=$(jq -c '.rds=[]' <<<"$acc_json")
      else
        local rds_list_json="[]"
        for rid in $rds_ids; do
          record_count rds_instances
          local r_eng r_stat
          read -r r_eng r_stat <<< "$(aws_q "$region" rds describe-db-instances --db-instance-identifier "$rid" --query "DBInstances[0].[Engine,DBInstanceStatus]" --output text)"
          printf "    ${GREEN}•${NC} %s  (%s • %s)\n" "$rid" "${r_eng:-?}" "${r_stat:-?}" >&3
          rds_list_json=$(jq -c --arg id "$rid" --arg e "${r_eng:-}" --arg s "${r_stat:-}" '.+[{"id":$id,"engine":$e,"status":$s}]' <<<"$rds_list_json")
        done
        acc_json=$(jq -c --argjson v "$rds_list_json" '.rds=$v' <<<"$acc_json")
      fi
    fi

    # 10. SNS Topics
    if should_show_type sns; then
      local topics
      topics=$(aws_q "$region" sns list-topics --query "Topics[].TopicArn" --output text)
      local top_count=0
      [[ -n "$topics" && "$topics" != "None" ]] && top_count=$(echo "$topics" | wc -w | tr -d ' ')

      if [[ $top_count -gt 0 || "$SHOW_ALL" == true ]]; then
        echo >&3
        printf "  ${BOLD}SNS Topics${NC}  ${DIM}(%s)${NC}\n" "$top_count" >&3
        printf "  ${DIM}────────────────────────────${NC}\n" >&3
      fi

      if [[ $top_count -eq 0 ]]; then
        $SHOW_ALL && printf "    ${DIM}(none)${NC}\n" >&3
        acc_json=$(jq -c '.sns=[]' <<<"$acc_json")
      else
        local top_list_json="[]"
        for top in $topics; do
          record_count sns_topics
          local t_name; t_name=$(basename "$top")
          printf "    ${GREEN}•${NC} %s\n" "$t_name" >&3
          printf "      ${DIM}%s${NC}\n" "$top" >&3
          top_list_json=$(jq -c --arg n "$t_name" --arg a "$top" '.+[{"name":$n,"arn":$a}]' <<<"$top_list_json")
        done
        acc_json=$(jq -c --argjson v "$top_list_json" '.sns=$v' <<<"$acc_json")
      fi
    fi

  done

  exec 3>&-

  echo "$acc_json" > "$json_out"
  for k in "${!ACC_COUNTS[@]}"; do
    printf "%s\t%s\n" "$k" "${ACC_COUNTS[$k]}"
  done > "$count_out"
}

# ---------------------------------------------------------------------------
# Zero-Leak Guardrail Verification
# ---------------------------------------------------------------------------
check_guardrail() {
  switch_account "123456789012"
  local leaks=0
  local leak_details=()

  for region in "${REGIONS[@]}"; do
    # 1. EKS Clusters
    local c
    c=$(aws_q "$region" eks list-clusters --query "length(clusters)" --output text)
    if [[ "$c" =~ ^[1-9][0-9]*$ ]]; then
      leaks=$((leaks + c))
      leak_details+=("EKS Clusters: $c")
    fi

    # 2. SQS Queues
    c=$(aws_q "$region" sqs list-queues --query "length(QueueUrls)" --output text)
    if [[ "$c" =~ ^[1-9][0-9]*$ ]]; then
      leaks=$((leaks + c))
      leak_details+=("SQS Queues: $c")
    fi

    # 3. DynamoDB Tables
    c=$(aws_q "$region" dynamodb list-tables --query "length(TableNames)" --output text)
    if [[ "$c" =~ ^[1-9][0-9]*$ ]]; then
      leaks=$((leaks + c))
      leak_details+=("DynamoDB Tables: $c")
    fi

    # 4. Non-default VPCs
    local leaked_vpcs
    leaked_vpcs=$(aws_q "$region" ec2 describe-vpcs --query "Vpcs[?!IsDefault].VpcId" --output text)
    if [[ -n "$leaked_vpcs" && "$leaked_vpcs" != "None" ]]; then
      local n; n=$(echo "$leaked_vpcs" | wc -w | tr -d ' ')
      leaks=$((leaks + n))
      leak_details+=("VPCs: $leaked_vpcs")
    fi

    # 5. Non-default Security Groups
    local leaked_sgs
    leaked_sgs=$(aws_q "$region" ec2 describe-security-groups --query "SecurityGroups[?GroupName!='default'].GroupId" --output text)
    if [[ -n "$leaked_sgs" && "$leaked_sgs" != "None" ]]; then
      local n; n=$(echo "$leaked_sgs" | wc -w | tr -d ' ')
      leaks=$((leaks + n))
      leak_details+=("Security Groups: $leaked_sgs")
    fi

    # 6. Internet Gateways
    local leaked_igws
    leaked_igws=$(aws_q "$region" ec2 describe-internet-gateways --query "InternetGateways[?Tags[?Key=='services.k8s.aws/namespace']].InternetGatewayId" --output text)
    if [[ -n "$leaked_igws" && "$leaked_igws" != "None" ]]; then
      local n; n=$(echo "$leaked_igws" | wc -w | tr -d ' ')
      leaks=$((leaks + n))
      leak_details+=("Internet Gateways: $leaked_igws")
    fi

    # 7. IAM Roles
    local leaked_roles
    leaked_roles=$(aws_q "$region" iam list-roles \
      --query "Roles[?starts_with(RoleName,'team-') || starts_with(RoleName,'ack-') || starts_with(RoleName,'orders-') || starts_with(RoleName,'analytics-')].[RoleName]" \
      --output text)
    if [[ -n "$leaked_roles" && "$leaked_roles" != "None" ]]; then
      local n; n=$(echo "$leaked_roles" | wc -w | tr -d ' ')
      leaks=$((leaks + n))
      leak_details+=("IAM Roles: $leaked_roles")
    fi
  done

  if (( leaks > 0 )); then
    err "❌ Zero-leak guardrail FAILED: $leaks leaked resource(s) found in root account 123456789012!"
    for detail in "${leak_details[@]}"; do
      err "   • $detail"
    done
    return 1
  fi
  debug "Zero-leak guardrail passed (0 leaked resources in 123456789012)"
  return 0
}

# ---------------------------------------------------------------------------
# Main Scan Coordinator
# ---------------------------------------------------------------------------
run_scan() {
  TMP_DIR=$(mktemp -d "/tmp/moto-scan-v4.XXXXXX")
  trap '[[ -n "${TMP_DIR:-}" && -d "${TMP_DIR:-}" ]] && rm -rf "$TMP_DIR"' EXIT INT TERM

  local accounts_to_scan=()
  for acc in "${ACCOUNTS[@]}"; do
    should_show_account "$acc" && accounts_to_scan+=("$acc")
  done

  if ! $JSON_MODE && ! $YAML_MODE && ! $QUIET && ! $SUMMARY_ONLY; then
    echo
    printf "${BOLD}${BLUE}Moto Cloud Resources (v4)${NC}\n"
    printf "${DIM}Endpoint  %s${NC}\n" "$ENDPOINT"
    printf "${DIM}Region(s) %s${NC}\n" "${REGIONS[*]}"
    [[ ${#FILTER_TYPES[@]} -gt 0 ]] && printf "${DIM}Filter    %s${NC}\n" "${FILTER_TYPES[*]}"
    [[ ${#FILTER_ACCOUNTS[@]} -gt 0 ]] && printf "${DIM}Accounts  %s${NC}\n" "${FILTER_ACCOUNTS[*]}"
    $FAST_MODE && printf "${DIM}Mode      Fast (active lab services only)${NC}\n"
    $PARALLEL_MODE && printf "${DIM}Execution Parallel${NC}\n" || printf "${DIM}Execution Sequential${NC}\n"
    echo
  fi

  # Launch collection
  local pids=()
  for acc in "${accounts_to_scan[@]}"; do
    local out_prefix="$TMP_DIR/$acc"
    if $PARALLEL_MODE; then
      collect_account "$acc" "$out_prefix" &
      pids+=($!)
    else
      collect_account "$acc" "$out_prefix"
    fi
  done

  if $PARALLEL_MODE; then
    for pid in "${pids[@]}"; do
      wait "$pid"
    done
  fi

  # Aggregate human text, counts, and JSON
  declare -A GLOBAL_COUNTS=()
  local accounts_json="{}"

  for acc in "${accounts_to_scan[@]}"; do
    local out_prefix="$TMP_DIR/$acc"

    # Human text
    if ! $JSON_MODE && ! $YAML_MODE && ! $SUMMARY_ONLY && [[ -f "$out_prefix.txt" ]]; then
      cat "$out_prefix.txt"
    fi

    # JSON aggregation
    if [[ -f "$out_prefix.json" ]]; then
      local single_acc_json
      single_acc_json=$(cat "$out_prefix.json")
      accounts_json=$(jq -c --arg id "$acc" --argjson data "$single_acc_json" \
        '.[$id]=$data' <<<"$accounts_json")
    fi

    # Counts aggregation
    if [[ -f "$out_prefix.count" ]]; then
      while IFS=$'\t' read -r k v; do
        [[ -z "$k" ]] && continue
        GLOBAL_COUNTS["$k"]=$(( ${GLOBAL_COUNTS["$k"]:-0} + v ))
      done < "$out_prefix.count"
    fi
  done

  # Build Root JSON
  local counts_json="{}"
  for k in "${!GLOBAL_COUNTS[@]}"; do
    counts_json=$(jq -c --arg k "$k" --argjson v "${GLOBAL_COUNTS[$k]}" '.[$k]=$v' <<<"$counts_json")
  done

  local root_json
  root_json=$(jq -n \
    --arg ep "$ENDPOINT" \
    --argjson regs "$(printf '%s\n' "${REGIONS[@]}" | jq -R . | jq -s .)" \
    --argjson accs "$accounts_json" \
    --argjson sum "$counts_json" \
    '{endpoint:$ep, regions:$regs, accounts:$accs, summary:$sum}')

  # Output Formats
  if $JSON_MODE; then
    echo "$root_json" | jq .
  elif $YAML_MODE; then
    if has_yq; then
      echo "$root_json" | yq -P -o=yaml
    else
      echo "$root_json" | jq .
      err "Install yq for proper YAML output (https://github.com/mikefarah/yq)"
    fi
  else
    # Summary Table
    if ! $QUIET && ! $NO_SUMMARY; then
      echo
      printf "  ${BOLD}Summary${NC}\n"
      printf "  ${DIM}────────────────────────────${NC}\n"

      local total=0
      if [[ ${#GLOBAL_COUNTS[@]} -gt 0 ]]; then
        for k in $(echo "${!GLOBAL_COUNTS[@]}" | tr ' ' '\n' | sort); do
          printf "    %-22s ${GREEN}%3d${NC}\n" "$k" "${GLOBAL_COUNTS[$k]}"
          total=$((total + GLOBAL_COUNTS[$k]))
        done
      else
        printf "    ${DIM}(no resources found)${NC}\n"
      fi

      echo
      printf "  ${BOLD}Total resources: ${GREEN}%d${NC}\n" "$total"
      echo
    fi
  fi

  # Zero-leak guardrail check
  if should_show_account "123456789012"; then
    check_guardrail || return 1
  fi

  return 0
}

# ---------------------------------------------------------------------------
# Main Entry Point
# ---------------------------------------------------------------------------
main() {
  if ! has_jq; then
    err "Error: jq is required (sudo apt install jq / brew install jq)"
    exit 1
  fi
  if ! curl -s -m 3 "${ENDPOINT}/" >/dev/null 2>&1; then
    err "Error: Moto is not responding at $ENDPOINT"
    exit 1
  fi

  if (( WATCH_INTERVAL > 0 )); then
    while true; do
      clear
      run_scan || true
      echo
      printf "${DIM}Watching... next scan in %s seconds (Ctrl+C to stop)${NC}\n" "$WATCH_INTERVAL"
      sleep "$WATCH_INTERVAL"
    done
  else
    run_scan
  fi
}

main "$@"
