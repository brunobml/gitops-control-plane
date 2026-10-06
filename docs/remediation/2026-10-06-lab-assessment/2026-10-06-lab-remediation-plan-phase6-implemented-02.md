# Phase 6 Implementation Report 02 — Validation Report 01 Findings

> **Status: Implemented locally; awaiting independent validation.** This report records implementation evidence, not acceptance or plan close-out.

| | |
|---|---|
| **Implements** | [Approved Phase 6 plan](2026-10-06-lab-remediation-plan-phase6.md), findings V-1–V-3 from [Validation Report 01](2026-10-06-lab-remediation-plan-validation-01.md) |
| **Base commit** | `gitops-control-plane` `8bc3589` (the prior implementation under review was `39e5fbe`) |
| **Commit under test** | Pending: these changes are in the local working tree and have not been committed or pushed |
| **Implemented by** | Codex |
| **Date** | 2026-10-06 |
| **Independent validation** | Pending; to be recorded by Agy or another reviewer in `2026-10-06-lab-remediation-plan-phase6-validation-02.md` |

## Changes

### V-1 — Repository preflight before any push

[`scripts/push-all.sh`](../../../scripts/push-all.sh) now checks all six repository paths with `git rev-parse --is-inside-work-tree` before entering the push loop. Any missing or invalid repository produces a nonzero exit with an explicit “no pushes attempted” message. After a successful preflight, the existing six-repository push behavior and aggregate failure status remain in place.

### V-2 — Shared, fail-closed claim count check

New [`scripts/lib/discover-iac-claims.sh`](../../../scripts/lib/discover-iac-claims.sh) queries both spokes for `TeamEKSCluster` objects and Argo CD for `tenant-iac` Applications. It validates JSON structure and claim metadata, retains `(cluster, namespace, metadata.name)` tuples, and requires a positive claim count exactly equal to the Application count. API errors, malformed JSON, zero claims, and nonzero mismatches return failure with a diagnostic.

Both [`scripts/smoke-test-hub-spoke.sh`](../../../scripts/smoke-test-hub-spoke.sh) and [`tests/smoke/06_observability.bats`](../../../tests/smoke/06_observability.bats) call that helper before their existing full-tuple Prometheus readiness checks. The legacy suite and Gate 12d therefore use the same count rule.

### V-3 — Explicit probe `up=0` alert test

[`addons/observability/alert-rules.test.yaml`](../../../addons/observability/alert-rules.test.yaml) now has separate `SyntheticProbeDown` cases for a down target (`up=0`), an absent target, and healthy targets. The down case keeps `spoke-prod` healthy, checks silence before the five-minute `for` period, and expects exactly one critical `spoke-nonprod` alert after it.

## Verification evidence

| Check | Result |
|---|---|
| [`tests/test_phase6_guards.py`](../../../tests/test_phase6_guards.py) | **7/7 passed.** Isolated temporary fixtures use a stub `git` or `kubectl`; no real push or claim mutation occurs. |
| V-1 missing final repository | Nonzero exit; **zero** recorded push attempts. |
| V-1 invalid final Git repository | Nonzero exit; **zero** recorded push attempts. |
| V-1 all six valid | Zero exit; six stubbed `git push --dry-run` attempts. |
| V-1 one push failure | Nonzero exit after all six attempts. |
| V-2 equal counts | Two claims, two tenant IaC Applications: passed; full tuple retained. |
| V-2 nonzero mismatch | Two claims, three Applications: failed with both counts in diagnostic. |
| V-2 zero/error cases | Zero claims, spoke API error, Argo CD API error, and malformed claim JSON: all failed. |
| `bash -n` and containerized ShellCheck on changed shell files, including the new helper | Passed. Local `shellcheck` binary was unavailable; the repository's pinned ShellCheck container was used. |
| `make test-alert-rules` | Passed (`SUCCESS`), including the new `up=0` case. |
| `make ci` | Passed: 42 Applications rendered, 585 resources checked (0 invalid), 22 alert rules valid, 2 dashboards valid, and all other CI stages green. The new helper was also shellchecked directly because the local CI shell stage enumerates tracked files. |
| `make ci-iac` | Passed: two valid claims, 2/2 positive fixtures, 14/14 negative fixtures, schema and render checks green. |
| `make orphans` | Passed: no orphaned credentials or namespaces. |
| `bash scripts/smoke-test-hub-spoke.sh` | Passed all 12 stages, including two discovered claims matching two registered Applications and both readiness metrics. |
| `bash scripts/smoke-test-hub-spoke-bats.sh` | Passed all 27 gates, including updated Gate 12d. |
| `git diff --check` | Passed with no whitespace errors. |

The isolated fixture suite provides the negative-path evidence that a green run against the current two-claim lab cannot provide. The full smoke runs confirm the revised checks also work against the live lab. Neither suite establishes independent acceptance; that decision belongs to the validator.

## Evidence correction and handoff

The original [implementation report 01](2026-10-06-lab-remediation-plan-implemented-01.md) now carries a correction pointing to Validation Report 01 and this follow-up. Its claims about complete repository preflight, claim/Application count equality, and `up=0` test coverage did not hold for `39e5fbe`.

The code and report are ready for a reviewed commit and independent validation. The unrelated pre-existing `scripts/grok/` directory was not changed.
