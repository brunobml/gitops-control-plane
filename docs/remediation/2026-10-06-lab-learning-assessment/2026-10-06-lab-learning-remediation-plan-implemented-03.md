# Lab Learning Remediation: Implementation Report 03 (Closure of N-1, N-2, N-3)

> **Status: For independent validation (2026-10-06).** Implementer: Claude (Opus 5.5), at the owner's request. It answers [validation-02](2026-10-06-lab-learning-remediation-plan-validation-02.md). Change: `gitops-control-plane` **`e7f8b72`**. Because I wrote these fixes *and* validation-02, the next validation and the score re-evaluation (R-10) must come from **Codex, Antigravity or the owner**, not from me.

| # | Finding | Change | Evidence |
|---|---|---|---|
| **N-1** | "modifying queue settings exercises all four tiers" | Student guide §1: the four-tier path is now *registering a new application (a new file in `tenant-workloads`)*. A separate bullet: **queue setting change in the values file** (e.g. `retentionPeriod`) → ② → ③ → ④, not ①, because the registration did not change | Text consistent with the `replicas: 3` bullet, self-check Q1 and the assessment's Q1 |
| **N-2** | ACK-outage answer said `Progressing`/`Degraded` | `concepts-and-glossary.md` Q4 and the assessment §7 Q4: health is **`Progressing`**, because the `QueueBackedService` Lua check only knows Ready → `Healthy`, otherwise `Progressing` | `clusters/values-argocd-hub.yaml` `resource.customizations.health.kro.run_QueueBackedService` returns only those two |
| **N-3** | `make test-docs` wrote into, then `rm -f`'d, a file in the learner's real `../tenant-iac` | Step 3 now runs in a **temporary sibling layout**: `$TMP/repos/tenant-iac` (copy, with the claim) + `$TMP/repos/gitops-control-plane` (link to this repo), with `REPOS_DIR=$TMP/repos`. GNU make resolves `../gitops-control-plane` to the physical path, so the link alone would have checked the real repo; the Makefile's `REPOS_DIR ?=` takes the environment value. The check only passes if the CI output names `ml-feature-store-dev`, which proves the copy was checked. Everything lives under `$TMP` (removed by the existing `EXIT` trap) | `make test-docs`: 6/6 pass. A fingerprint of the real `tenant-iac` (`git status --porcelain` + file list) is **identical before and after**. **Negative test:** with Step 3 reverted to `make ci-iac` → `✘ Step 3 validation block failed from tenant-iac: make: *** No rule to make target 'ci-iac'`; runbook restored. ShellCheck clean |

## Gates
| Gate | Result |
|---|---|
| `make test-docs` | 6/6 checks passed (live account-111 publish included) |
| `make ci` | all checks passed, 37 scripts shellcheck-clean |
| `make ci-iac` | all checks passed |
| `scripts/smoke-test-hub-spoke-bats.sh` | 27 ok, 0 not ok |
| GitHub Actions `e7f8b72` | to be read by the validator |

## For the validator
1. Read the student guide §1 bullets ("Full provisioning chain", "Queue setting change", "Values-only update") and the Q4 answers in the concepts page and the assessment.
2. `make test-docs`; check that `git -C ../tenant-iac status --porcelain` and the files under `../tenant-iac/teams` are unchanged afterwards.
3. Optional: put a file `../tenant-iac/teams/team-data/clusters/ml-feature-store-dev.yaml` in place first; it must survive `make test-docs` unchanged. Then remove it yourself.
4. If accepted: re-evaluate the learning score (R-10).
