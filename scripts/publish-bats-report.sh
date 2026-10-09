#!/usr/bin/env bash
# scripts/publish-bats-report.sh
#
# Sanitizes and publishes Bats JUnit reports to Moto S3 and bats-test-results GitHub repo.
# Designed for safe, non-blocking execution from smoke-test-hub-spoke-bats.sh.
#
set -euo pipefail
umask 077

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)

CONFIG_DIR="${HOME}/.config/gitops-lab"
REPORTS_BASE="${CONFIG_DIR}/reports"
RETRY_QUEUE="${REPORTS_BASE}/retry-queue.jsonl"
RESULTS_REPO="${HOME}/repos/bats-test-results"
BUCKET_NAME="${BATS_REPORT_BUCKET:-gitops-lab-reports}"
MOTO_ENDPOINT="${MOTO_ENDPOINT:-http://localhost:5000}"

mkdir -p "${REPORTS_BASE}/staging" "${REPORTS_BASE}/archive"
chmod 700 "${REPORTS_BASE}" "${REPORTS_BASE}/staging" "${REPORTS_BASE}/archive"

# Function to upload to Moto S3
upload_to_s3() {
  local run_id="$1" date_path="$2" report_xml="$3" meta_json="$4"
  local s3_dest="s3://${BUCKET_NAME}/runs/${date_path}/${run_id}"

  # Get temporary credentials for account 111111111111
  local creds
  creds=$(AWS_MAX_ATTEMPTS=1 AWS_ACCESS_KEY_ID=mock-key AWS_SECRET_ACCESS_KEY=mock-secret \
    timeout 30s aws --cli-connect-timeout 5 --cli-read-timeout 20 --endpoint-url="${MOTO_ENDPOINT}" --region us-east-1 sts assume-role \
      --role-arn "arn:aws:iam::111111111111:role/provisioner" \
      --role-session-name "publish-${run_id}" --query Credentials --output json 2>/dev/null) || return 1

  if [[ -z "$creds" || "$creds" == "null" ]]; then
    return 1
  fi
  local access_key secret_key session_token
  access_key=$(jq -er .AccessKeyId <<<"$creds") || return 1
  secret_key=$(jq -er .SecretAccessKey <<<"$creds") || return 1
  session_token=$(jq -er .SessionToken <<<"$creds") || return 1
  AWS_MAX_ATTEMPTS=1 AWS_ACCESS_KEY_ID="$access_key" AWS_SECRET_ACCESS_KEY="$secret_key" AWS_SESSION_TOKEN="$session_token" \
    timeout 30s aws --cli-connect-timeout 5 --cli-read-timeout 20 --endpoint-url="${MOTO_ENDPOINT}" --region us-east-1 \
      s3 cp "${report_xml}" "${s3_dest}/report.xml" >/dev/null 2>&1 || return 1
  AWS_MAX_ATTEMPTS=1 AWS_ACCESS_KEY_ID="$access_key" AWS_SECRET_ACCESS_KEY="$secret_key" AWS_SESSION_TOKEN="$session_token" \
    timeout 30s aws --cli-connect-timeout 5 --cli-read-timeout 20 --endpoint-url="${MOTO_ENDPOINT}" --region us-east-1 \
      s3 cp "${meta_json}" "${s3_dest}/metadata.json" >/dev/null 2>&1
}

# Function to commit and push to bats-test-results
push_to_github() {
  local run_id="$1" date_path="$2" report_xml="$3" meta_json="$4"
  if [[ ! -d "${RESULTS_REPO}/.git" ]]; then
    return 1
  fi

  # This alias must resolve to the dedicated, repo-scoped deploy key.
  if [[ "$(git -C "${RESULTS_REPO}" remote get-url --push origin 2>/dev/null)" != "git@github-bats-results:brunobml/bats-test-results.git" ]]; then
    return 1
  fi

  (
    flock -x 9
    cd "${RESULTS_REPO}"
    [[ "$(git branch --show-current)" == "main" ]] || git checkout main >/dev/null 2>&1 || return 1
    timeout 15s git fetch origin main >/dev/null 2>&1 || return 1
    git rebase origin/main >/dev/null 2>&1 || { git rebase --abort >/dev/null 2>&1 || true; return 1; }

    local target_dir="runs/${date_path}/${run_id}"
    mkdir -p "$target_dir"
    for name in report.xml metadata.json; do
      local source="$report_xml"
      [[ "$name" == "metadata.json" ]] && source="$meta_json"
      if [[ -f "${target_dir}/${name}" ]] && ! cmp -s "$source" "${target_dir}/${name}"; then
        return 1
      fi
      cp "$source" "${target_dir}/${name}"
    done
    git add "$target_dir" >/dev/null 2>&1 || return 1
    if ! git diff --cached --quiet; then
      git commit -m "chore(report): record test run ${run_id}" >/dev/null 2>&1 || return 1
    fi

    for _ in {1..3}; do
      if timeout 15s git push origin main >/dev/null 2>&1; then
        timeout 15s git fetch origin main >/dev/null 2>&1 || return 1
        [[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]]
        return
      fi
      timeout 15s git fetch origin main >/dev/null 2>&1 || return 1
      git rebase origin/main >/dev/null 2>&1 || { git rebase --abort >/dev/null 2>&1 || true; return 1; }
    done
    return 1
  ) 9>"${REPORTS_BASE}/.results-push.lock"
}

# Mode: Retry failed uploads
if [[ "${1:-}" == "--retry" ]]; then
  if [[ ! -f "$RETRY_QUEUE" ]]; then
    echo "✔ Retry queue is empty."
    exit 0
  fi

  echo "==> Retrying pending publications from ${RETRY_QUEUE}..."
  temp_queue=$(mktemp)
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -n "$line" ]] || continue
    run_id=$(jq -r .run_id <<<"$line")
    date_path=$(jq -r .date_path <<<"$line")
    archive_dir="${REPORTS_BASE}/archive/runs/${date_path}/${run_id}"
    report_xml="${archive_dir}/report.xml"
    meta_json="${archive_dir}/metadata.json"

    if [[ ! -f "$report_xml" || ! -f "$meta_json" ]]; then
      continue
    fi

    need_s3=$(jq -r '.destinations.s3 // false' <<<"$line")
    need_github=$(jq -r '.destinations.github // false' <<<"$line")

    s3_ok=true
    if [[ "$need_s3" == "false" ]]; then
      if upload_to_s3 "$run_id" "$date_path" "$report_xml" "$meta_json"; then
        echo "  ✔ [retry] S3 upload succeeded for ${run_id}"
      else
        s3_ok=false
      fi
    fi

    gh_ok=true
    if [[ "$need_github" == "false" ]]; then
      if push_to_github "$run_id" "$date_path" "$report_xml" "$meta_json"; then
        echo "  ✔ [retry] GitHub push succeeded for ${run_id}"
      else
        gh_ok=false
      fi
    fi

    if [[ "$s3_ok" == "false" || "$gh_ok" == "false" ]]; then
      jq -c --arg s3 "$s3_ok" --arg gh "$gh_ok" \
        '.destinations.s3 = ($s3 == "true") | .destinations.github = ($gh == "true")' <<<"$line" >> "$temp_queue"
    fi
  done < "$RETRY_QUEUE"
  mv "$temp_queue" "$RETRY_QUEUE"
  echo "✔ Retry cycle complete."
  exit 0
fi

# Parse standard invocation
RAW_XML="${1:-}"
RUN_ID="${2:-}"
START_TIME="${3:-}"
END_TIME="${4:-}"
EXIT_CODE="${5:-0}"
SUITE="${6:-smoke}"
FILTER="${7:-}"
CALLER="${8:-direct}"

if [[ -z "$RAW_XML" || ! -f "$RAW_XML" || -z "$RUN_ID" ]]; then
  echo "Usage: $0 <raw_report.xml> <run_id> <start_time_utc> <end_time_utc> <exit_code> [suite] [filter]" >&2
  exit 1
fi

DATE_PATH=$(date -u -d "${START_TIME}" +%Y/%m/%d 2>/dev/null || date -u +%Y/%m/%d)
STAGING_DIR="${REPORTS_BASE}/staging/${RUN_ID}"
ARCHIVE_DIR="${REPORTS_BASE}/archive/runs/${DATE_PATH}/${RUN_ID}"
mkdir -p "${STAGING_DIR}" "${ARCHIVE_DIR}"

GIT_COMMIT=$(git -C "${REPO_ROOT}" rev-parse --short HEAD 2>/dev/null || echo "unknown")
BATS_VER=$(bats -v 2>/dev/null | awk '{print $2}' || echo "1.14.0")

# 1. Sanitize report and generate metadata
if ! python3 "${SCRIPT_DIR}/lib/sanitize_report.py" \
    --input "${RAW_XML}" \
    --output-dir "${STAGING_DIR}" \
    --run-id "${RUN_ID}" \
    --start-time "${START_TIME}" \
    --end-time "${END_TIME}" \
    --exit-code "${EXIT_CODE}" \
    --bats-version "${BATS_VER}" \
    --suite "${SUITE}" \
    --filter "${FILTER}" \
    --caller "${CALLER}" \
    --commit "${GIT_COMMIT}"; then
  echo "✘ Sanitization check failed. Test results quarantined locally; no outbound data sent." >&2
  rm -rf "${STAGING_DIR}"
  exit 2
fi

# Archive locally first
cp -f "${STAGING_DIR}/report.xml" "${ARCHIVE_DIR}/report.xml"
cp -f "${STAGING_DIR}/metadata.json" "${ARCHIVE_DIR}/metadata.json"

REPORT_XML="${ARCHIVE_DIR}/report.xml"
META_JSON="${ARCHIVE_DIR}/metadata.json"

# 2. Upload to Moto S3 (bounded timeout)
S3_SUCCESS=false
if upload_to_s3 "${RUN_ID}" "${DATE_PATH}" "${REPORT_XML}" "${META_JSON}"; then
  S3_SUCCESS=true
fi

# 3. Push to GitHub bats-test-results
GH_SUCCESS=false
if push_to_github "${RUN_ID}" "${DATE_PATH}" "${REPORT_XML}" "${META_JSON}"; then
  GH_SUCCESS=true
fi

# 4. Queue failed destinations
if [[ "$S3_SUCCESS" == "false" || "$GH_SUCCESS" == "false" ]]; then
  mkdir -p "$(dirname "$RETRY_QUEUE")"
  jq -n -c \
    --arg run_id "${RUN_ID}" \
    --arg date_path "${DATE_PATH}" \
    --argjson s3 "${S3_SUCCESS}" \
    --argjson gh "${GH_SUCCESS}" \
    '{run_id: $run_id, date_path: $date_path, destinations: {s3: $s3, github: $gh}, queued_at: (now | todate)}' \
    >> "${RETRY_QUEUE}"
fi

# Output publication status
s3_label="✔ ok"
[[ "$S3_SUCCESS" == "true" ]] || s3_label="✘ failed"
gh_label="✔ ok"
[[ "$GH_SUCCESS" == "true" ]] || gh_label="✘ failed"

if [[ "$S3_SUCCESS" == "true" && "$GH_SUCCESS" == "true" ]]; then
  echo "✔ Published test run ${RUN_ID} (S3: ${s3_label}, GitHub: ${gh_label})"
else
  echo "✘ Publication incomplete for ${RUN_ID} (S3: ${s3_label}, GitHub: ${gh_label}); retry with scripts/publish-bats-report.sh --retry" >&2
fi
rm -rf "${STAGING_DIR}"
