#!/usr/bin/env bash
# scripts/smoke-test-hub-spoke-bats.sh
#
# Runner for the Bats-based Multi-Cluster Hub-and-Spoke Smoke Test Suite.
#
# Usage:
#   ./scripts/smoke-test-hub-spoke-bats.sh [OPTIONS]
#
# Examples:
#   ./scripts/smoke-test-hub-spoke-bats.sh                   # Standard pretty run with timing
#   ./scripts/smoke-test-hub-spoke-bats.sh -f "Gate 10"      # Run only SSO tests
#   ./scripts/smoke-test-hub-spoke-bats.sh -f "Kyverno"      # Run only Kyverno / supply-chain tests
#   ./scripts/smoke-test-hub-spoke-bats.sh --tap             # Output in TAP format for CI
#   ./scripts/smoke-test-hub-spoke-bats.sh -F junit -o ./ci  # Generate JUnit XML report

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)

# Check for bats binary
if ! command -v bats >/dev/null 2>&1; then
  echo "❌ Error: bats binary not found in PATH." >&2
  echo "   Install Bats via package manager (sudo apt install bats) or npm (npm install -g bats)" >&2
  echo "   or from source: https://github.com/bats-core/bats-core" >&2
  exit 1
fi

# Locate the Bats test suite target (directory or file)
TEST_TARGET=""
if [[ -d "${REPO_ROOT}/tests/smoke" ]]; then
  TEST_TARGET="${REPO_ROOT}/tests/smoke"
elif [[ -f "${REPO_ROOT}/tests/smoke-test-hub-spoke.bats" ]]; then
  TEST_TARGET="${REPO_ROOT}/tests/smoke-test-hub-spoke.bats"
elif [[ -f "${SCRIPT_DIR}/smoke-test-hub-spoke.bats" ]]; then
  TEST_TARGET="${SCRIPT_DIR}/smoke-test-hub-spoke.bats"
else
  echo "❌ Error: Could not locate smoke tests in tests/smoke/ or tests/!" >&2
  exit 1
fi

# Handle help flag
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  cat <<EOF
Usage: $(basename "$0") [OPTIONS] [BATS_OPTIONS]

Runner for the Bats-based Multi-Cluster Hub-and-Spoke Smoke Test Suite.

Options:
  -f, --filter REGEX       Only run tests matching the regex (e.g. -f "Gate 10", -f "Kyverno")
  -t, --tap                Output results in Test Anything Protocol (TAP) format
  -F, --formatter TYPE     Formatter type: pretty (default), tap, tap13, junit
  -o, --output DIR         Directory to write report files (e.g. JUnit XML for CI)
  -c, --count              Count matching test cases without running
  -j, --jobs N             Run tests in parallel
  -x, --trace              Print test commands as they are executed (set -x)
  -h, --help               Display this help message

Examples:
  ./scripts/smoke-test-hub-spoke-bats.sh                   # Full smoke test run
  ./scripts/smoke-test-hub-spoke-bats.sh -f "Gate 10"      # Run only SSO tests
  ./scripts/smoke-test-hub-spoke-bats.sh -f "Kyverno"      # Run only supply-chain admission tests
  ./scripts/smoke-test-hub-spoke-bats.sh --tap             # CI TAP output
EOF
  exit 0
fi

# Default flags if no custom flags provided
DEFAULT_FLAGS=(--timing --print-output-on-failure)

echo "============================================================"
echo " Running Bats Smoke Test Suite: $(bats -v)"
echo " Target: ${TEST_TARGET}"
echo "============================================================"

if [[ $# -eq 0 ]]; then
  bats "${DEFAULT_FLAGS[@]}" "${TEST_TARGET}"
else
  bats "${DEFAULT_FLAGS[@]}" "$@" "${TEST_TARGET}"
fi
