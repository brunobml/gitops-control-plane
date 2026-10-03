# Phase 5 Implementation Report — Run #04: Track D (self-healing operations) (2026-10-02)

> **Status: Historical.** Record of the 2026-09-30 assessment and its remediation (Phases 1–5, closed 2026-10-03). Kept as evidence and not updated. For the lab as it is today, see the [README](../../../README.md) and the [2026-10-03 assessment](../../assessments/2026-10-03-lab-assessment.md).

| | |
|---|---|
| **Plan** | Phase 5 v1.0 (GREEN LIGHT); owner decisions **O-3**, **O-4** |
| **Executed by** | Claude (Opus 5.5). **To be validated by** Antigravity |
| **Commits** | `gitops-control-plane`: `8399b26` (D.1–D.3, smoke stage 12), `e84f1b7` (renewal fix). Test data in `tenant-workloads` / `orders-processor` added and removed |

## Outcome
| Step | Result |
|---|:-:|
| **D.1** `scripts/orphans.sh` (`make orphans` = dry run; `post-bootstrap` step 6/9 removes) | ✅ |
| **D.2** automatic token renewal, `post-bootstrap` step 1/9 (< 7 days or missing data) | ✅ |
| **D.3** runbook: one section per alert (anchors match the `runbook` annotations) | ✅ |
| `post-bootstrap` now 9 steps; smoke now **12 stages** | ✅ |

## Evidence
| # | Test | Result |
|---|---|---|
| — | dry run on the live lab (all registered) | "no orphaned credentials or namespaces" |
| X12 | register `orders-demo` → credential provisioned → deregister → `make orphans` | lists: empty namespace (+Secret), IAM user `orders-demo-dev-worker`, table `orders-demo-dev-history` (kept) |
| X12 | `make post-bootstrap` | namespace + Secret and IAM user removed; table **reported only** (O-3) |
| X12 | `PRUNE_DATA=1 bash scripts/orphans.sh` | table deleted; registered users/tables untouched (111…: dev/test, 222…: prod) |
| X13 | recorded expiry of `argocd-spoke-prod` set to tomorrow | `post-bootstrap` renewed all spoke + Headlamp tokens, connections verified, all 29 days, next run "29 days left" (idempotent) |
| X13b | renewal of an **already broken** token (from the B alert test) | first attempt aborted (defect D-14, report #02), fixed; renewal then succeeded |

## Notes
| ID | Item |
|---|---|
| D-16 | `register-spokes.sh` uses the caller's Argo CD CLI session; inside `post-bootstrap` it now gets the script's own session through `ARGOCD_OPTS="--config …"` — the operator's session is never used or changed |
| D-17 | Orphan safety: refuses to run with no registrations; registered names come from the Applications of the `tenant-workloads` ApplicationSet and their QueueBackedServices; namespaces with any Deployment/Pod/QueueBackedService are only reported |
| D-18 | Spoke/Headlamp tokens were renewed several times during testing; they now expire 2026-11-01 (~08:00 UTC) and are renewed automatically by `post-bootstrap` |
