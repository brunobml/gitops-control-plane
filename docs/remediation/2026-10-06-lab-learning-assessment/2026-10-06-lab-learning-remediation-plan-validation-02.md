# Lab Learning Remediation Plan — Independent Validation 02

> **Status: Changes requested, small (2026-10-06).** Validates `gitops-control-plane` `cd4f9d4` and [implemented-02](2026-10-06-lab-learning-remediation-plan-implemented-02.md) (implementer: Antigravity), which answers [validation-01](2026-10-06-lab-learning-remediation-plan-validation-01.md) (validator: Codex). Validator: Claude (Opus 5.5).
>
> **Independence note.** The changes under review are Antigravity's. V-1 and V-2 were defects in *my* implementation-01, so I check the corrections, not my own work. For the same reason **I do not re-evaluate the learning score**: R-10 requires a party other than the Tracks 1–4 implementer (me). That belongs to Codex or the owner.
>
> Changes I made during validation: temporary edits to `docs/runbooks/tenant-iac-operations.md` for a negative test (restored from a backup; `git status` clean). No other files or cluster resources changed.

## Verdict: 🟡 Accept after three small corrections (N-1…N-3)

V-1 and V-3 are **closed**. V-2's original contradiction is closed, but the new text introduces a similar false statement (N-1). N-2 is one wrong word in the V-1 answer; N-3 is a safety guard in the new test. All three are one- or two-line fixes.

## 1. Re-validation of V-1…V-3

| # | Result | Evidence |
|---|---|---|
| **V-1** ACK-outage answer | ✅ **Closed** (one word off, N-2) | The answer now follows the RGD's dependency graph, which I read from `platform-catalog/blueprints/queue-backed-service-rgd.yaml`. The `queue` resource references `${dlq.status.ackResourceMetadata.arn}`. `config` references both queues' `status.queueURL` and `ackResourceMetadata.arn`. The Deployment only *names* the ConfigMap (`envFrom … -config`, a string, not a status reference), so it is created and its pods cannot start. `SpokeControllerDown` `for: 5m` is confirmed (values-prometheus-hub.yaml l.248). Antigravity's live experiment left **no residue**: no `test-outage-*` namespace, no `test-svc-*` queue in account 111 or the default account; all ACK controllers and the hub application controller are at 1 replica; 42/42 Applications `Synced Healthy` |
| **V-2** reconciler lesson | ⚠️ **Original closed, new inaccuracy (N-1)** | The `replicas: 3` paragraph now correctly names only ② and ③, and the opening sentence no longer claims four reconcilers act for that change |
| **V-3** runbook command | ✅ **Closed** | From `../tenant-iac`, `make -C ../gitops-control-plane ci-iac` passes ("2 team cluster claims valid", 2 Applications rendered). `make test-docs` now runs the Step 3 block from the `tenant-iac` working directory: passes. **Negative test:** with Step 3 reverted to `make ci-iac`, the check fails: `✘ Step 3 validation block failed from tenant-iac: make: *** No rule to make target 'ci-iac'.` |

## 2. New findings

| # | Severity | Finding | Evidence | Correction |
|---|---|---|---|---|
| **N-1** | Medium (learner-facing, P-1) | Student guide §1, "Full provisioning chain": *"Registering a new application **or modifying queue settings** exercises all four tiers: ① ApplicationSet controller creates the Application → …"*. Changing queue settings (e.g. `retentionPeriod` in `deploy/values-dev.yaml`) does not touch the registration file, so ① has nothing to do, exactly as for `replicas: 3`. The path is ② → ③ → ④ | Same reasoning the paragraph itself applies to `replicas: 3`; the ApplicationSet only generates Applications from registration files | *"Registering a new application exercises all four tiers … Changing a queue setting in the values file exercises ②, ③ and ④ (not ①: the registration did not change)"* |
| **N-2** | Low | ACK-outage answer (concepts page Q4, assessment §7 Q4): health *"`Progressing`/`Degraded`"*. The lab's Lua check for `QueueBackedService` returns only `Healthy` or `Progressing`, so the instance shows **`Progressing`**; `Degraded` cannot occur for it | `clusters/values-argocd-hub.yaml`, `resource.customizations.health.kro.run_QueueBackedService`: returns only `status = "Healthy"` / `status = "Progressing"` | Replace with *"health `Progressing` (the `QueueBackedService` check only knows Ready → Healthy, otherwise Progressing)"* |
| **N-3** | Medium (test tooling safety) | `tests/test_doc_examples.sh` copies the extracted claim **into the learner's real working copy** (`../tenant-iac/teams/team-data/clusters/ml-feature-store-dev.yaml`) and then runs `rm -f` on it. If that file already exists (a learner following Runbook 1 creates exactly this file), the test **overwrites and deletes it**. If the script is interrupted between `cp` and `rm`, a stray claim is left in a real repository, where it could be committed by mistake. The `EXIT` trap only removes `$TMP` | `tests/test_doc_examples.sh` l. 52–58 (`cp "$claim" "$target_claim"` … `rm -f "$target_claim"`) | Refuse (or skip with a message) if `$target_claim` already exists, and add its removal to the `EXIT` trap. Better: run the Step 3 block in a temporary sibling layout (`$TMP/repos/{tenant-iac,gitops-control-plane→symlink}`) so the real working copy is never touched |
| N-4 | Info | implemented-02 says "All 4 doc example checks passed"; the script now runs 6 checks | `make test-docs` output | Cosmetic |

## 3. Gates (re-run by the validator)
| Gate | Result |
|---|---|
| GitHub Actions `cd4f9d4` (and `0f016ae`, `d628beb`) | success |
| `make ci` | all checks passed; 37 scripts shellcheck-clean |
| `make test-docs` | all 6 checks passed (live account-111 publish included); `tenant-iac` working copy clean afterwards |
| documented Step 3 from `tenant-iac` | passes |
| `scripts/smoke-test-hub-spoke-bats.sh` | **27 ok, 0 not ok** |
| Lab state | 42/42 Applications `Synced Healthy`; no residue from the ACK-outage experiment |

## 4. Acceptance path
Fix N-1, N-2 and N-3 (N-4 optional); then a quick re-check of those three lines and the test guard is enough. After acceptance, **Codex or the owner** re-evaluates the learning score (R-10). Drill 1 stays outside the learner path (R-5).
