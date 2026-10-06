# Phase 6 Implementation Plan — Close Validation Report 01 Findings

> **Status: Approved by Agy.** Plan is approved for implementation by Codex.

| | |
|---|---|
| **Parent plan** | [2026-10-06 remediation plan v1.1](2026-10-06-lab-remediation-plan.md) |
| **Source of findings** | [Validation Report 01](2026-10-06-lab-remediation-plan-validation-01.md), findings V-1–V-3 |
| **Implementation baseline** | `gitops-control-plane` commit `39e5fbe` |
| **Scope** | Correct three acceptance gaps and update the implementation evidence; preserve the existing remediation behavior |
| **Reviewer / approver** | Agy — Approved |
| **Implementer** | Codex, after approval |
| **Independent validator** | Agy or another reviewer who did not implement this phase |

## Goal and acceptance rule

Close V-1, V-2, and V-3 without changing the tenant contract, admission policy, or alert expression. Phase 6 is complete only when each targeted failure case is demonstrated, the required quality gates pass, and an independent validation report accepts the result. Passing the current lab's normal two-claim smoke run alone is insufficient to close V-2.

## Step 1 — V-1: Make repository validation a real preflight

**File:** `scripts/push-all.sh`

1. Keep the six-repository inventory and `--dry-run` behavior.
2. Validate every repository path before the first push. Reject missing directories and paths that are not initialized Git repositories. Report all invalid repositories and exit nonzero without attempting a push.
3. Run the existing push loop only after the entire preflight succeeds. Continue tracking push failures across repositories and exit nonzero if any push fails.
4. Keep production `git push` behavior unchanged after a successful preflight.

**Verification:** Use an isolated temporary directory with a copy of the script, fixture repository paths, and a stub `git` command that records push attempts. Make the final repository invalid; assert a nonzero exit and **zero** recorded push attempts. With all six paths valid, assert six dry-run push calls. Stub one push failure and assert the final exit is nonzero. No verification step may push to a real remote.

## Step 2 — V-2: Enforce claim/Application count equality in both smoke suites

**Files:** `scripts/smoke-test-hub-spoke.sh`, `tests/smoke/06_observability.bats`; a shared read-only helper may be added if it reduces duplicate query logic.

1. Discover `TeamEKSCluster` claims on both spokes as `(cluster, namespace, metadata.name)` tuples, preserving the current metric lookup and 60-second readiness poll.
2. Query Argo CD for Applications whose `spec.project` is `tenant-iac`. In both suites, require a positive claim count and exact equality between claim count and registered tenant IaC Application count.
3. Fail closed if either spoke discovery or the Argo CD query fails, returns malformed JSON, or produces a nonnumeric count. Avoid process substitution paths that discard producer exit status.
4. Include observed and expected counts in mismatch output so an operator can diagnose a missing claim.

**Verification:** Exercise at least these fixture states without changing live claims: equal nonzero counts pass; two claims versus three Applications fail; zero claims fail; a spoke API error fails; an Argo CD query or JSON parse error fails. Run the normal legacy and Bats smoke suites against the lab after the change.

## Step 3 — V-3: Cover the probe-down alert state

**File:** `addons/observability/alert-rules.test.yaml`

Add a promtool unit case with `up{job="agent",cluster="spoke-nonprod"}=1` and `up{job="synthetic-order-probe",cluster="spoke-nonprod"}=0` for longer than the rule's five-minute `for` period. Keep a second spoke healthy. Assert exactly one `SyntheticProbeDown` alert, with `cluster=spoke-nonprod` and `severity=critical`; assert no alert for the healthy spoke. Retain the existing absent/stale and all-healthy cases. Run `make test-alert-rules`.

## Step 4 — Evidence and release checks

1. Run shell syntax and shellcheck checks for changed shell files, `make test-alert-rules`, `make ci`, `make ci-iac`, and `make orphans`.
2. Run both required smoke suites: `bash scripts/smoke-test-hub-spoke.sh` and `bash scripts/smoke-test-hub-spoke-bats.sh`. Record the commands, exit codes, and counts; do not substitute one suite for the other.
3. Compare the changed behavior with [Validation Report 01](2026-10-06-lab-remediation-plan-validation-01.md). Record the targeted negative-case results, including zero push attempts for V-1 and nonzero claim mismatch failure for V-2.
4. Write `2026-10-06-lab-remediation-plan-phase6-implemented-02.md` with the commit under test and exact evidence. Correct or qualify any claims in `implemented-01` that were disproved by Validation Report 01.
5. Submit the result for independent review in `2026-10-06-lab-remediation-plan-phase6-validation-02.md`. That report determines acceptance; the implementation report does not self-certify closure.

## Review decision

| Decision | Reviewer | Date | Notes |
|---|---|---|---|
| **Approved** | Agy | 2026-10-06 | Approved without reservations. The plan precisely targets findings V-1 through V-3, establishes strict negative-case verification standards, and properly structures delivery and independent validation. Ready for Codex implementation. |
