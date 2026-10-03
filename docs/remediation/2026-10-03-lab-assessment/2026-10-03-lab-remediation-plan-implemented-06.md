# Implementation Report 06 — Track B: Tenant Blast Radius and ApplicationSet Health (2026-10-03)

> **Status: Current.** Active remediation record for the 2026-10-03 assessment.

| | |
|---|---|
| **Implements** | [Remediation plan v1.1](2026-10-03-lab-remediation-plan.md) Track B (L2-3): **B.1** `ApplicationSetNotUpToDate`, **B.2** one ApplicationSet per tenant; review remark **R-4** |
| **Executed by** | Claude (Opus 5.5), owner's assignment. **To be validated by** Antigravity, independent of the execution |
| **Commits** | `gitops-control-plane` `29f1174` (B.1), `a8ef7f4` (B.2 migration step 1), `8b0f748` (B.2 step 2), plus this report's commit; `tenant-workloads` branch `docs/b2-per-tenant-appsets` (docs only; **PR to be opened and merged by the owner**, since `main` requires a PR since V-7) |
| **Live change outside Git** | `kubectl delete applicationset tenant-workloads --cascade=orphan` (B.2 step 3, as in Phase 4 C.2) |
| **Date** | 2026-10-03 |

---

## Summary

| Step | Result |
|---|---|
| **B.1** | Alert **`ApplicationSetNotUpToDate`** (critical, 5 min) with a unit test and a runbook section. **Live fire test** (throwaway branch and ApplicationSet): pending 20:45:57, **firing 20:51:05**, cleared after cleanup. The real `tenant-workloads` ApplicationSet stayed UpToDate throughout, which shows the isolation B.2 builds on |
| **B.2** | `tenant-workloads` → **`tenant-workloads-tenant-a`**, generated from one template. **Zero-diff gate** passed (old vs new identical; new vs live identical apart from the controller-managed finalizer). Migration 20:57:22–20:57:44 (**22 s**): **UIDs unchanged**, owner moved, pods untouched |
| CI | New stage `tenant-appsets` on both sides. The control plane checks that every tenant ApplicationSet equals the generator output; `tenant-workloads` checks that every `tenants/<tenant>/` has an ApplicationSet. The render covers all tenants together, so cross-tenant duplicates fail. A template guard rejects a file that claims another tenant |
| Regression | smoke 12/12; `post-bootstrap` rc 0 (discovery through the new owner); `make orphans` clean; 32/32 Synced/Healthy; 20 rules SUCCESS; CI green on `29f1174`, `a8ef7f4`, `8b0f748` |

---

## 1. B.1 — `ApplicationSetNotUpToDate`

**Metric check first:** `argocd_appset_info` is already scraped (job `kubernetes-service-endpoints`) for all 8 ApplicationSets, with the label `resource_update_status`.

**Rule** (group `lab.argocd`):
* `max by (name, resource_update_status) (argocd_appset_info{resource_update_status!="ApplicationSetUpToDate"})`, for 5 min, `severity: critical`.
* Summary: *"ApplicationSet X is not up to date (status): its Applications are no longer updated"*.
* Runbook section `#alert-applicationsetnotuptodate`: how to read the condition, CI pointers, the "already owned" case.

**Unit test:** a failing ApplicationSet fires only after 5 min (none at 7 min, fires at 9 min in the test series), and an UpToDate one never fires. 20 rules; promtool SUCCESS.

**Live fire test (the plan's method: a throwaway branch and an ApplicationSet copy, never `main`):**

| Time (UTC) | Event |
|---|---|
| 20:45 | branch `b1-firetest` in `tenant-workloads` with one file in `tenants/b1test/apps/`, in the v1.0 drill-5 format. The ruleset protects only `main` |
| 20:45:42 | ApplicationSet `b1-firetest` applied with kubectl (not in Git; the root app does not manage it). Safety: `applicationsSync: create-only`, a non-existent destination cluster, no sync policy |
| 20:46:19 | condition `RenderTemplateParamsError … map has no entry for key "app"`, the L2-3 failure mode. **`tenant-workloads`: ErrorOccurred=False, ResourcesUpToDate=True** |
| 20:45:57 / **20:51:05** | alert pending / **firing**, `name=b1-firetest`, `resource_update_status=ErrorOccurred` |
| 20:51:35 | ApplicationSet and branch deleted; alert gone; no `b1-firetest` Application ever created |

* **Finding:** in practice the metric label carries the condition (`ErrorOccurred`), not the specific reason. The unit test was aligned to the real value (`a8ef7f4`).
* **Note:** right after the push, the repo-server first reported `unable to resolve 'b1-firetest'` (cached refs). A refresh resolved it after about 30 s. That error class also trips the alert.

## 2. B.2 — One ApplicationSet per tenant

### Design
* **One template, one generator:**
  * `scripts/templates/tenant-appset.yaml` holds the former `tenant-workloads` ApplicationSet, parameterised by `__TENANT__`;
  * `scripts/tenant-appset.sh <tenant>` prints it;
  * `applicationsets/tenant-workloads-tenant-a.yaml` is its output, with a "GENERATED, do not edit" header.

  Per tenant, only three things differ: the name `tenant-workloads-<tenant>`, the label `platform.lab/tenant`, and the Git-files path `tenants/<tenant>/apps/*.yaml`.
* **New template guard:** `{{ if ne .tenant "<tenant>" }}{{ fail … }}`. A file under `tenants/b/` cannot claim tenant `a`. The rendered Applications are unchanged.
* **Onboarding:** an app or environment stays a tenant PR in `tenant-workloads`; a *tenant* is a platform change: run `scripts/tenant-appset.sh <t> > applicationsets/tenant-workloads-<t>.yaml`. That matches the plan.
* **Scripts:** `post-bootstrap.sh` and `orphans.sh` find tenant Applications by owner `kind == ApplicationSet` and a name starting with `tenant-workloads`, so they work for every tenant.

### Deviations from the plan text (recorded)
| Plan | Implemented | Why |
|---|---|---|
| `applicationsets/tenants/<tenant>.yaml` | `applicationsets/tenant-workloads-<tenant>.yaml` | The root app's directory source (`path: applicationsets`) does not recurse. Enabling `directory.recurse` means a `kubectl apply` of `bootstrap/root-app.yaml` outside GitOps; flat names need no root change |
| R-4 lists `preserveResourcesOnDeletion: true` | **not** set on the new ApplicationSets; the migration is protected by `create-only` + `Prune=false` on the old ApplicationSet and the orphan delete (the Phase 4 C.2 protocol) | `preserveResourcesOnDeletion` stops the controller from adding `resources-finalizer.argocd.argoproj.io`. A deregistered app's workload would then stay behind (breaks Drill 5 and the O-3 clean-up). After migration the three Applications **keep** the finalizer |

### Zero-diff gate (R-4)
Rendered offline with `labci appsets` (verified against the hub in Track A) from the current registrations:

| Comparison | Result |
|---|---|
| old `tenant-workloads` vs new `tenant-workloads-tenant-a` (name, labels, annotations, finalizers, spec) | **identical** for `orders-dev`, `orders-test`, `orders-prod` |
| new render vs live Applications | **identical** labels, annotations and spec. Only difference: the live `resources-finalizer.argocd.argoproj.io`, which the ApplicationSet controller adds (neither template sets it) |

### Migration (Phase 4 C.2 protocol)
| Step | Time (UTC) | Result |
|---|---|---|
| 0 | — | UIDs recorded: `orders-dev` `044494f3…`, `orders-test` `b967f9f5…`, `orders-prod` `c24da692…` |
| 1. `a8ef7f4`: old ApplicationSet `applicationsSync: create-only` + annotation `argocd.argoproj.io/sync-options: Prune=false` | ~20:55 | live: `create-only Prune=false`; still UpToDate |
| 2. `8b0f748`: new `tenant-workloads-tenant-a.yaml`, old file removed, CI and scripts updated | 20:57:22 | new ApplicationSet: *"orders-dev is already owned by another ApplicationSet controller"* (expected). Root: old one *OutOfSync (requires pruning)* but **not pruned** |
| 3. `kubectl delete applicationset tenant-workloads --cascade=orphan` | 20:57:38 | new ApplicationSet `ResourcesUpToDate=True` at 20:57:44 |
| Check | 20:57:44 | **UIDs unchanged**; owner `tenant-workloads-tenant-a`; all Synced/Healthy; finalizers kept; worker pods untouched (age 162 min); root Synced/Healthy; `argocd_appset_info{name="tenant-workloads-tenant-a"}` UpToDate; **no alert** (22 s window) |

### CI
* **Control plane, stage `tenant-appsets`** (`ci/check-tenant-appsets.py`): every `tenant-workloads-*.yaml` must equal `scripts/tenant-appset.sh <tenant>`.
* **`tenant-workloads`:**
  * new stage `tenant-appsets`: each `tenants/<t>/apps/` needs `tenant-workloads-<t>.yaml`;
  * the render now uses **all** tenant ApplicationSets together, so a cross-tenant `<app>-<env>` duplicate is a duplicate-name error, just as Argo CD would raise "already owned".

Negative tests (scratch copies):

| Case | Result |
|---|---|
| new `tenants/tenant-b/` without an ApplicationSet | ✘ `tenants/tenant-b/ has no ApplicationSet: its registrations would be ignored. Platform onboarding: scripts/tenant-appset.sh tenant-b > …` |
| file in `tenants/tenant-b/` with `tenant: tenant-a` | ✘ `ApplicationSet tenant-workloads-tenant-b: … fail "tenant registration: tenant must be tenant-b …"` |
| tenant-b registers `orders-dev` | ✘ `duplicate Application name "orders-dev" (tenant-workloads-tenant-a.yaml and tenant-workloads-tenant-b.yaml)` |
| hand-edited tenant ApplicationSet | ✘ `differs from scripts/tenant-appset.sh tenant-a (regenerate it; do not edit by hand)` |
| properly onboarded tenant-b with `orders-b-dev` | ✔ 4 Applications |

The first run of the last two cases reported false duplicates. That was my test harness (a worktree of the M1 commit still contained the old file), corrected before recording.

### Docs
* **Control plane:** README tree, naming standards §4, tutorial, promotion guardrails, runbook.
* **`tenant-workloads`:** README, `tenants/README.md`, schema description, registration comments. These are on branch `docs/b2-per-tenant-appsets` (CI green locally) because `main` now requires a PR: https://github.com/brunobml/tenant-workloads/compare/main...docs/b2-per-tenant-appsets?expand=1.

## 3. Regression
| Check | Result |
|---|---|
| `scripts/smoke-test-hub-spoke.sh` | 12/12, no firing alerts |
| `make post-bootstrap` | rc 0; step 2 discovers `orders-dev`, `orders-test`, `orders-prod` through the new owner; step 6 *no orphaned credentials or namespaces* |
| Applications | 32/32 Synced/Healthy |
| `make ci` / `make ci-tenants` | all stages green (414 resources; 20 rules) |
| GitHub CI | `29f1174`, `a8ef7f4`, `8b0f748`: success |

## 4. Notes for the validator
* **Isolation evidence:**
  * the B.1 fire test (a failing ApplicationSet next to a healthy one);
  * the per-tenant split, so a real tenant's bad file now affects only `tenant-workloads-<that tenant>`;
  * a cross-tenant name clash is caught by CI before merge. If it ever reached `main`, only the second tenant's ApplicationSet would error, and `ApplicationSetNotUpToDate` would name it.
* **Residual (unchanged by B):** all tenants share the `tenant-workloads` AppProject, so tenant B *could* register an app name in tenant A's namespace pattern (`orders-*`). CI blocks duplicates of *existing* names. Per-tenant AppProjects would be the structural fix (candidate for a later plan).
* **Suggested checks:**
  * `argocd_appset_info` series;
  * the UIDs above;
  * `make ci-tenants` with a `tenants/<new>/` directory;
  * a throwaway fire test as in §1;
  * after the owner merges the `tenant-workloads` docs PR, the `registration-checks` run on that PR.

## 5. Track B status
| Step | Status |
|---|---|
| B.1 | 🔧 Done; fired live. **Awaiting validation-06** |
| B.2 | 🔧 Done; migrated with UIDs unchanged. **Awaiting validation-06**. Owner: merge the `tenant-workloads` docs PR |
