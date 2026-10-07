# Lab Learning Remediation Plan — Independent Validation 04

> **Status: Changes requested (2026-10-07).** Validator: Codex. Implementer: Claude. Scope: [implementation report 04](2026-10-06-lab-learning-remediation-plan-implemented-04.md), change `517e084`: Bats smoke wording and Drill 1 learner milestone.

## Verdict

The Drill 1 milestone and recovery instructions are supported by the recorded live drill and the current `make moto-restart` script. The smoke wording cleanup is incomplete: current runbooks still describe stages from scripts that `make test` no longer runs. The new stale-wording check passes while missing these cases. Correct the references and extend the guard, then rerun `make test-docs` for a focused re-validation.

## Findings

| ID | Finding | Evidence and correction |
|---|---|
| V4-1 | Current smoke-test instructions retain obsolete stage names and counts. | `docs/runbooks/operational-drills-and-failure-injection.md` says `Stage [8/12]` for token validation; use **Bats Gate 8**. `docs/runbooks/host-reboot-and-cluster-lifecycle.md` says `8-stage comprehensive test suite` and later `smoke stage 10 fails`; describe the Bats suite and identify the relevant Gate 10 checks. `docs/runbooks/tenant-iac-operations.md` says `stage 6, and Bats Gate 6b`; current `make test` runs **Gate 6b** only. Preserve explicitly dated historical observations where useful, but identify them as historical. |
| V4-2 | The regression check does not catch the surviving wording. | `tests/test_doc_examples.sh` searches for `12 stages`, `12/12 smoke stages`, `12-stage smoke`, and `All Core Smoke Tests Passed`. It misses `[8/12]`, `8-stage`, and `smoke stage 10`. Add focused patterns or assertions so these current instructions fail the check if reintroduced. |

## Checks and scope

- `make test-docs` passed, including its existing stale-wording check. An independent repository search found V4-1, demonstrating V4-2.
- The rebuild diagram now attributes Argo CD installation and spoke registration to setup, the root Application to bootstrap, and token renewal, worker keys, and smoke tests to post-bootstrap; these match the current scripts.
- Drill 1's `make moto-restart` recovery, default-account assertion, and controller restart order match `scripts/moto-restart.sh`. The implementation report records a live moto restart and successful recovery; [tenant-IaC validated-12](../../roadmaps/2026-10-04-tenant-iac-team-clusters-plan-validated-12.md) accepted that recovery. I did not repeat the disruptive restart for this wording review.
- The independent learning score remains **8.0 / 10**. Promoting Drill 1 improves the exercises, but the approved higher-score gate still requires the safer Lab 0 entry path and measured results from real learners.
