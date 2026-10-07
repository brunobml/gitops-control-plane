# shellcheck shell=bash
# Helpers shared by tests/test-lab1.sh and tests/test-sandbox-guards.sh (validation-04 V3-2).

# moto-sandbox through the AWS CLI (default account; the sandbox's ACK has no CARM)
moto() {
  AWS_ACCESS_KEY_ID=mock-key AWS_SECRET_ACCESS_KEY=mock-secret AWS_SESSION_TOKEN='' \
    aws --endpoint-url=http://localhost:5002 --region us-east-1 "$@"
}

# queue_state <queue> <control-queue>: prints present, absent or error.
# "absent" needs a successful read that still lists the control queue: an AWS error, an empty
# answer from the wrong endpoint or account, or a missing control queue is "error", never proof
# that <queue> was deleted.
queue_state() {
  local out
  if ! out=$(moto sqs list-queues --output json 2>&1); then echo error; return 0; fi
  if ! grep -q "/${2}\"" <<<"$out"; then echo error; return 0; fi
  if grep -q "/${1}\"" <<<"$out"; then echo present; else echo absent; fi
}
