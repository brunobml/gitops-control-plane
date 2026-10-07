# Lab Learning Remediation: Implementation Report 04 (follow-ups: smoke drift, Drill 1 milestone)

> **Status: For independent validation (2026-10-07).** Implementer: Claude (Opus 5.5), at the owner's request. Change: `gitops-control-plane` **`517e084`**. Validator: Codex or Antigravity, not me. Scope: two items left after [validation-03](2026-10-06-lab-learning-remediation-plan-validation-03.md): (1) new learner-doc drift caused by the Bats consolidation (`9134041`), and (2) the **R-5 deferral**: Drill 1 into the learner path once its `make moto-restart` recovery was verified (accepted in tenant-IaC [validated-12](../../roadmaps/2026-10-04-tenant-iac-team-clusters-plan-validated-12.md)).

## 1. Smoke-suite drift (guardrail P-0)
`9134041` turned `scripts/smoke-test-hub-spoke.sh` into a wrapper around the Bats suite (`tests/smoke/`, 28 tests). The learner docs still described "12 stages" and an `All Core Smoke Tests Passed!` banner that no longer exists, so a learner could not confirm acceptance.

| File | Change |
|---|---|
| `README.md` (repository tree, Quick Start) | "End-to-end checks: runs the Bats suite in tests/smoke/" |
| `full-rebuild-and-acceptance.md` acceptance row 6 | expected result: exit 0 and every line `ok N Gate …`, none `not ok`; quick check `make test \| grep -c '^not ok'` → 0 |
| `operational-drills-and-failure-injection.md` pre-drill check | "every Bats smoke gate passes"; the 2026-10-03 observation keeps "12/12" marked as "the 12-stage script of that time" |
| `host-reboot-and-cluster-lifecycle.md` Issue F / G | stage numbers mapped to the Bats gates that kept them (stage 9 → *Gate 9*, stage 10 → *Gate 10a*) |
| `devops-student-rebuild-guide.md` Step 4 + rebuild diagram | Bats suite, success criterion. **The diagram notes were also wrong** and are corrected: *setup* installs Argo CD and registers the spokes (`setup-hub-spoke.sh`: `helm upgrade --install argo-cd`, `register-spokes.sh`); *bootstrap* only applies `root-control-plane`; *post-bootstrap* renews tokens only when < 7 days are left, does **not** "seed Moto queues" (ACK creates them, the L-1 lesson) and does not import the Keycloak realm or register clusters. Diagram rendered with mermaid-cli |
| `tests/test_doc_examples.sh` | New check: no `12 stages`, `12/12 smoke stages`, `12-stage smoke` or `All Core Smoke Tests Passed` in learner docs. **It caught a sixth instance on its first run** (the diagram note) |

## 2. Drill 1 re-verified and promoted (R-5)
**Live run 2026-10-07** (`docker restart moto-cloud` at 07:00:37 UTC, sampled every ~35 s):

| Time | Observation |
|---|---|
| +41 s | `platform-network` on spoke-nonprod: **1/6** objects synced (VPC only, F-7); 2 Applications not `Synced/Healthy` |
| +110 s | `min(lab_order_e2e_success)` = **0** |
| +284 s | **6 SQS queues in the default account `123456789012`**, none in 111/222. **F-6 confirmed for SQS on the real lab** (until now only verified for IAM in the P0 spike): the ACK SQS controller recreated the queues with stale STS credentials |
| recovery | `make moto-restart`: **rc 0 in 270 s**, "default account … completely empty", one platform VPC per account, Bats **28 ok**; queues 4 in 111, 2 in 222, none in 123; 0 Applications not green |

**Consequence:** the old Drill 1 recovery (`make post-bootstrap` alone) would have left the queues in the wrong account. Changes:
* `operational-drills-and-failure-injection.md` **Drill 1 rewritten**: F-1 + F-6 + F-7, the measured timeline, commands to watch each account, recovery = `make moto-restart` (and why not `post-bootstrap` alone), validation as observed.
* `devops-student-rebuild-guide.md` **§4.7 Milestone: Lose the Cloud (Drill 1)**: predict (will Argo CD turn red, where will the queues appear, does `post-bootstrap` suffice) → act → recover → folded *Explain* with the measured answers. The lesson: self-healing with a **stale identity** makes things worse; recovery must reset the controllers. Objective 4 now names both milestones; the old "Drill 1 predates…" note is removed.

## 3. Gates
| Gate | Result |
|---|---|
| `make test-docs` | all checks passed (including the new smoke-reference check) |
| `make ci` | all checks passed, 39 scripts shellcheck-clean |
| `make moto-restart` (recovery of the drill) | rc 0, Bats 28 ok |
| Lab now | 42/42 Applications `Synced/Healthy`, queues in 111/222 only, default account empty |
| GitHub Actions `517e084` | to be read by the validator |

## 4. For the validator
1. `make test-docs`; then put "12 stages" back in any learner doc and confirm it fails; restore.
2. Read the rebuild diagram notes against `scripts/setup-hub-spoke.sh` and `scripts/post-bootstrap.sh`.
3. Optional, ~15 min, disruptive but self-recovering: run the §4.7 milestone as a learner (Drill 1), then `make moto-restart`. Expect the queues in `123456789012` after ≈ 5 min, and the clean state after recovery.
4. If accepted: does the score change? R-5 was one of validation-03's named limits.
