# Validation Report 01 — 2026-10-06 Lab Remediation

> **Status: Not accepted.** Three implementation gaps remain against the approved v1.1 plan.

| | |
|---|---|
| **Validates** | [Implementation report 01](2026-10-06-lab-remediation-plan-implemented-01.md) |
| **Against** | [Remediation plan v1.1](2026-10-06-lab-remediation-plan.md), especially guardrails R-0, R-1, and R-2 |
| **Commit reviewed** | `gitops-control-plane` `39e5fbe` |
| **Validator** | Codex, independent of the implementation report author |
| **Method** | Read-only review of the implementation report, commit diff, plan requirements, scripts, smoke tests, alert tests, and admission policy manifests |
| **Date** | 2026-10-06 |

## Verdict

**Implementation is partially validated; formal acceptance is withheld.** The reviewed changes deliver the documented application baseline checks, dynamic metric lookup by `(cluster, namespace, name)`, and matching admission policy manifests for both spokes. Three required checks are incomplete. The implementation report's statements about a repository preflight, claim-count equality, and `up=0` alert coverage are stronger than the committed code supports.

The implementation report records passing CI, dry-run, live admission drills, and both smoke suites. This validation did **not** rerun those commands or independently verify the live cluster state. Passing smoke tests on the current two-claim estate would not exercise the missing-claim case described below.

| Track | Result | Basis |
|---|---|---|
| 1 — Onboarding and push script | **Finding V-1** | R-0 requires a complete preflight before pushing |
| 2 — Synthetic probe alert | **Finding V-3** | R-1 requires a separate `up=0` test |
| 3 — Dynamic tenant smoke gates | **Finding V-2** | R-2 requires claim count to match registered tenant IaC Applications |
| 4 — Admission boundary | **Static review passed** | Both spoke manifests match; policy and bootstrap copy use the planned operations, identity, validation, and failure policy |
| 5 — Verification and sign-off | **Pending** | Reported test results are not independently rerun; findings V-1–V-3 remain open |

## Findings

### V-1 — Push preflight occurs after pushes can begin (Medium)

**Evidence:** [`scripts/push-all.sh`](../../../scripts/push-all.sh) checks each repository's `.git` directory inside the same loop that executes `git push` (lines 27–43). The sixth repository, `tenant-iac`, is checked only after the preceding repositories have been processed. The implementation report calls this a pre-flight check, but [plan guardrail R-0](2026-10-06-lab-remediation-plan.md) requires validating all six repositories **before attempting operations**.

**Impact:** If a later repository is missing or uninitialized, the command exits nonzero only after earlier repositories may already have been pushed. A successful `--dry-run` with all six present does not test this failure path.

**Required for acceptance:** Validate all six repository paths in a separate first pass and abort before any `git push` if any is invalid. Exercise a missing later repository with `git push` stubbed or another non-pushing test, and verify zero push attempts.

### V-2 — Claim count is not compared with registered Applications (Medium)

**Evidence:** [`scripts/smoke-test-hub-spoke.sh`](../../../scripts/smoke-test-hub-spoke.sh) obtains `iac_apps_count` at lines 399–401 but only rejects the case `iac_apps_count > 0` with **zero** discovered claims at lines 403–410. It never compares nonzero counts. [`tests/smoke/06_observability.bats`](../../../tests/smoke/06_observability.bats) lines 35–47 require at least two claims but never query the Application count. The [implementation report](2026-10-06-lab-remediation-plan-implemented-01.md) says the discovered count matches registered `tenant-iac` Applications; the code does not enforce that assertion.

**Impact:** With three registered tenant IaC Applications and two live claims, both gates can pass if the two discovered claims have ready metrics. This misses an unexpectedly absent claim as the lab grows.

**Required for acceptance:** In both smoke suites, fail unless the discovered claim count is greater than zero **and equals** the count of registered `tenant-iac` Applications. Keep API and JSON parsing failures fail-closed. Verify a mismatched nonzero count fails and equal counts pass.

### V-3 — Alert rule tests omit the `up=0` scenario (Low)

**Evidence:** [`addons/observability/alert-rules.test.yaml`](../../../addons/observability/alert-rules.test.yaml) adds an absent/stale probe case and a healthy `up=1` case (lines 295–322). It contains no input series in which `up{job="synthetic-order-probe"}` becomes `0`. [Plan guardrail R-1](2026-10-06-lab-remediation-plan.md) requires separate evidence for `up=0`, absence, and `up=1`.

**Impact:** The expression appears designed to alert when the target is down, but the reported unit coverage does not prove that case or its one-alert-per-spoke cardinality.

**Required for acceptance:** Add a promtool case with a healthy spoke agent and probe `up=0` for at least five minutes. Assert exactly one `SyntheticProbeDown` alert for that spoke and no alert for a healthy spoke; rerun `make test-alert-rules`.

## Checks that passed static review

- The fixed 37 platform Applications remain named explicitly; the three existing orders Applications and two team cluster Applications are required by name. Discovered tenant Applications are included in health checks.
- Team cluster metric queries use the full `(cluster, namespace, name)` label tuple and `.metadata.name` for claim identity.
- The two spoke admission policy manifests are byte-identical. They match namespace `CREATE` and `UPDATE`, filter the `argocd-iac-deployer` username, enforce the `iac-` prefix, and set `failurePolicy: Fail`. The bootstrap script contains the same policy and binding definitions.
- The new alert expression aggregates by `cluster`, and its annotations point to `platform-probes`.

## Revalidation gate

Resolve V-1–V-3, update the implementation report to match the evidence, and submit the follow-up commit for independent validation. Run the targeted failure-path checks plus `make test-alert-rules` and both smoke suites. Formal plan close-out remains pending until those results pass.
