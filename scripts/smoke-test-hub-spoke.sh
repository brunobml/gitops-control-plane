#!/usr/bin/env bash
# scripts/smoke-test-hub-spoke.sh
#
# Multi-Cluster Hub-and-Spoke Smoke Test Runner.
# Delegates directly to the modular Bats smoke test suite in tests/smoke/.
#
# Retained for backwards compatibility with operational lifecycle scripts and CI checks.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# Single source of truth for Keycloak SSO issuer (checked by ci/check-sso-urls.py)
ISSUER="http://keycloak.localhost/realms/lab"
export ISSUER

exec "${SCRIPT_DIR}/smoke-test-hub-spoke-bats.sh" "$@"
