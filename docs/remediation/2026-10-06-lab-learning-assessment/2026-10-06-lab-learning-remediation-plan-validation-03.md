# Lab Learning Remediation Plan — Independent Validation 03

> **Status: Accepted (2026-10-06).** Independent validator: Codex. Implementer of the changes under review: Claude. Scope: `gitops-control-plane` `e7f8b72` and [implementation report 03](2026-10-06-lab-learning-remediation-plan-implemented-03.md), responding to [validation 02](2026-10-06-lab-learning-remediation-plan-validation-02.md). This report also performs the independent score re-evaluation required by plan correction R-10.

## Verdict

**N-1, N-2, and N-3 are closed.** The learning remediation is accepted across implementation reports 01–03 and validations 01–03, with the approved R-5 deferral of Drill 1. No further implementation fix was needed in this review.

| Finding | Result | Independent evidence |
|---|---|---|
| **N-1 — queue-setting change and ApplicationSet** | Closed | `docs/runbooks/devops-student-rebuild-guide.md:125–128` now separates new registration (①→②→③→④), a queue setting change (②→③→④), and a replica-only change (②→③, then Kubernetes workload controllers). The self-check answer for `replicas: 3` agrees. |
| **N-2 — QueueBackedService health** | Closed | The answers in `docs/concepts-and-glossary.md:82–83` and `docs/assessments/2026-10-06-lab-learning-assessment.md:185` say `Progressing`. The deployed Lua source in `clusters/values-argocd-hub.yaml:225–233` returns `Healthy` for `Ready=True`, otherwise `Progressing`; it does not return `Degraded` for this kind. The alert's `for: 5m` remains correctly stated. |
| **N-3 — documentation test working-copy safety** | Closed | `tests/test_doc_examples.sh:50–69` copies `tenant-iac` into a temporary sibling layout, runs the extracted Step 3 block there with `REPOS_DIR` pointed at the copy, checks that CI saw `ml-feature-store-dev`, and removes the temporary layout on exit. The real `../tenant-iac` status and team-claim file list were unchanged before and after the independent offline run. |

## Checks and limits

- `bash tests/test_doc_examples.sh --offline`: passed the claim schema and full checks, the runbook Step 3 command from a tenant-IaC working directory, tutorial values parity, and the stale-baseline search. The live SQS publish was skipped by `--offline`.
- `bash -n tests/test_doc_examples.sh` and `git diff --check e7f8b72^ e7f8b72`: passed. `shellcheck` is unavailable in this environment; the implementer reports it passed in `make ci`.
- GitHub Actions CI for `e7f8b72` completed successfully (run [37544031109](https://github.com/brunobml/gitops-control-plane/actions/runs/37544031109)). The follow-up report commit `e665e7f` also has successful CI (run [37544062803](https://github.com/brunobml/gitops-control-plane/actions/runs/37544062803)).
- I did not rerun the live SQS publish, destructive cloud-drift drill, or full 27-test smoke suite. Validation 02 independently ran the earlier live gates; implementation report 03 records the final live reruns. This acceptance rests on those records plus the focused independent checks above.

## Independent learning-score re-evaluation (R-10)

**8.0 / 10**, up from the pre-remediation **6.0 / 10**. This rates the teaching materials and exercises, not measured learner outcomes.

| Dimension | Before | Now | Basis |
|---|---:|---:|---|
| Concept coverage and explicitness | 5.5 | 8.0 | Reconciler ownership, Helm render, health, CARM, lifecycle and simulation limits are now explained together. |
| Learning flow and scaffolding | 4.5 | 7.5 | Objectives, prerequisites, predict/observe/explain checkpoints and self-check answers exist; the full three-cluster rebuild remains a steep starting point. |
| Hands-on design | 8.0 | 8.0 | Drill 4 is now a guided learner milestone; Drill 1 remains an operator drill under R-5 until reverified. |
| Documentation effectiveness | 5.0 | 8.0 | Copyable core examples, account selection, application baseline, architecture, promotion and the glossary were corrected and linked. The documentation checker covers selected examples, not every command. |
| Transfer of learning | 6.5 | 8.5 | The guide now distinguishes full provisioning from values-only changes, Git/Kubernetes/cloud deletion, lab shortcuts from production, and promotion from progressive delivery. |

The equal-weight mean of these five ratings is **8.0**. A higher score requires a safer introductory path than the full rebuild and evidence from real learners completing the exercises without trainer intervention.

The v3.0 assessment remains the historical 6.0/10 baseline; its current score is recorded in the v4.0 re-evaluation note at the top of that document. Drill 1 is not accepted as a learner milestone until its current `make moto-restart` recovery path is verified.
