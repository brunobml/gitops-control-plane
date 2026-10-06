# Validation Report 02 — Phase 6 Remediation Closure

**Execution Date:** 2026-10-06  
**Status:** Accepted (All findings V-1, V-2, V-3 closed)  
**Validates:** [Phase 6 Implementation Report 02](2026-10-06-lab-remediation-plan-phase6-implemented-02.md)  
**Against:** [Phase 6 Implementation Plan](2026-10-06-lab-remediation-plan-phase6.md) & [Validation Report 01](2026-10-06-lab-remediation-plan-validation-01.md)  
**Validator:** Agy (Independent Validator)

---

## 1. Executive Verdict

**Phase 6 is formally accepted.** All three acceptance gaps identified in Validation Report 01 (`V-1`, `V-2`, `V-3`) have been resolved with strict implementation and comprehensive negative-path verification evidence. The solution preserves the tenant contract, admission policy, and alert expression without regressions.

| Finding | Topic | Verification Result | Final Verdict |
|---|---|---|---|
| **V-1** | Push Preflight | Preflight loop checks all 6 repos before any push attempt; isolated fixture tests confirm zero push attempts on invalid/missing repos. | **CLOSED** |
| **V-2** | Claim vs Application Count Equality | Shared helper enforces `claims_count == iac_apps_count` and `claims_count > 0` fail-closed across both smoke suites; unit tests confirm mismatch rejection. | **CLOSED** |
| **V-3** | Probe `up=0` Alert Test | Promtool unit test verifies `up=0` exceeding 5m `for` window emits single critical alert on `spoke-nonprod` and remains silent on healthy `spoke-prod`. | **CLOSED** |

---

## 2. Detailed Finding Verification

### V-1 — Repository Preflight Validation (`scripts/push-all.sh`)
* **Code Inspection:**
  * Lines 28–39 of `scripts/push-all.sh` perform a dedicated initial pass validating every repository in `REPOS` using `git -C "$target_dir" rev-parse --is-inside-work-tree`.
  * If any repository path is missing or not an initialized Git repository, the script displays the specific invalid directories, prints `Preflight failed for X of 6 repositories; no pushes attempted.`, and exits nonzero (`exit 1`) immediately before entering the push loop.
* **Negative & Positive Test Verification (`tests/test_phase6_guards.py`):**
  * `test_missing_last_repo_prevents_every_push`: Confirmed nonzero exit and **0 push attempts** when `tenant-iac` is missing.
  * `test_invalid_git_repository_prevents_every_push`: Confirmed nonzero exit and **0 push attempts** when preflight check fails.
  * `test_all_valid_repos_make_six_dry_run_attempts`: Confirmed zero exit code and exactly 6 dry-run push attempts when all 6 repositories are valid.
  * `test_one_push_failure_returns_nonzero_after_all_attempts`: Confirmed all 6 repos attempted and nonzero exit returned on failure.
* **Live Execution:**
  * `bash scripts/push-all.sh --dry-run` successfully verified all 6 repositories without modifying remotes.

### V-2 — Shared Fail-Closed Claim Count Assertion (`scripts/lib/discover-iac-claims.sh`)
* **Code Inspection:**
  * Introduced `scripts/lib/discover-iac-claims.sh` shared between `scripts/smoke-test-hub-spoke.sh` (Stage 12) and `tests/smoke/06_observability.bats` (Gate 12d).
  * Validates JSON response structure from both spokes, extracts complete `(cluster, namespace, metadata.name)` tuples, and queries Argo CD for Applications where `spec.project == "tenant-iac"`.
  * Enforces fail-closed assertion:
    ```bash
    if (( ${#IAC_CLAIM_TUPLES[@]} == 0 || ${#IAC_CLAIM_TUPLES[@]} != IAC_APPS_COUNT )); then
      echo "✘ TeamEKSCluster claim count (${#IAC_CLAIM_TUPLES[@]}) must be positive and match registered tenant-iac Applications (${IAC_APPS_COUNT})" >&2
      return 1
    fi
    ```
* **Negative & Positive Test Verification (`tests/test_phase6_guards.py`):**
  * `test_equal_nonzero_counts_pass`: 2 claims vs 2 tenant IaC apps passes.
  * `test_nonzero_count_mismatch_fails`: 2 claims vs 3 tenant IaC apps fails with clear diagnostic displaying observed and expected counts.
  * `test_empty_discovery_and_query_errors_fail`: Zero claims, spoke API error, Argo CD query error, and malformed JSON all fail closed.
* **Live Execution:**
  * Both `scripts/smoke-test-hub-spoke.sh` (Stage 12) and `tests/smoke/06_observability.bats` (Gate 12d) dynamically discovered 2 claims matching 2 registered `tenant-iac` applications and verified `lab_team_cluster_ready == 1` across both spokes.

### V-3 — Explicit Probe `up=0` Alert Test (`addons/observability/alert-rules.test.yaml`)
* **Code Inspection:**
  * Lines 295–311 add test case `SyntheticProbeDown when synthetic-order-probe target is down`.
  * Inputs: `up{job="synthetic-order-probe",cluster="spoke-nonprod"}` set to `0x20` while `agent` is `1x20`, and `spoke-prod` probe and agent are both `1x20`.
  * Assertions:
    * At `eval_time: 4m`: 0 alerts firing (verifying silence before the 5m `for` duration).
    * At `eval_time: 6m`: Exactly 1 alert firing for `{severity: critical, cluster: spoke-nonprod}` with annotations pointing to `platform-probes`. Healthy `spoke-prod` emits 0 alerts.
  * Retains separate test cases for absent target (`1 1 stale`) and healthy targets (`1x20`).
* **Live Execution:**
  * `make test-alert-rules` passed (`SUCCESS: 22 rules found`).

---

## 3. Independent Quality Gate Results

| Gate | Command | Expected | Observed | Status |
|---|---|---|---|---|
| Phase 6 Guard Unit Tests | `python3 -m unittest tests/test_phase6_guards.py` | 7/7 passed | 7/7 passed (0.85s) | **PASSED** |
| Alert Rule Tests | `make test-alert-rules` | 22 rules passed | `SUCCESS: 22 rules found` | **PASSED** |
| Control Plane CI | `make ci` | 42 apps rendered, valid schemas, 0 lint errors | 585 resources checked (0 invalid), 35 scripts clean | **PASSED** |
| Tenant IaC CI | `make ci-iac` | Positive/negative fixtures valid | 2/2 positive, 14/14 negative rejected | **PASSED** |
| Orphan Check | `make orphans` | No orphaned objects | No orphaned credentials or namespaces | **PASSED** |
| Push Simulation | `bash scripts/push-all.sh --dry-run` | 6 repos processed | All 6 repos processed cleanly | **PASSED** |
| Legacy Smoke Suite | `bash scripts/smoke-test-hub-spoke.sh` | 12/12 stages green | 12/12 stages green | **PASSED** |
| Modular Bats Suite | `bash scripts/smoke-test-hub-spoke-bats.sh` | 27/27 gates green | 27/27 gates green (59s) | **PASSED** |
| Git Whitespace Check | `git diff --check` | Clean | Clean | **PASSED** |

---

## 4. Final Sign-Off

With findings V-1, V-2, and V-3 completely resolved and independently verified, the 2026-10-06 Lab Assessment remediation is **accepted and closed**. All changes are ready for commit and push to `origin/main`.
