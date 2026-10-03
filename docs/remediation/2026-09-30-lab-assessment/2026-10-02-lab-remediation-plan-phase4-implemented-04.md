# Phase 4 Implementation Report — Run #04: Track C, ApplicationSet Modernization (2026-10-02)

| | |
|---|---|
| **Plan** | [`2026-10-02-lab-remediation-plan-phase4.md`](2026-10-02-lab-remediation-plan-phase4.md) v1.0 (GREEN LIGHT; remark **R-3** governs C.2) |
| **Preceded by** | [Implemented-03](2026-10-02-lab-remediation-plan-phase4-implemented-03.md), validated 🟢 in [Validation-03](2026-10-02-lab-remediation-plan-phase4-validation-03.md) |
| **Scope executed** | **C.0** (enabling step), **C.1** (L2-4), **C.2** (L2-3) |
| **Commits** | `gitops-control-plane`: `d9d0c7a` (C.0); `9954153`, `9790077`, `7e59779`, `2734629`, `7a3f330` (C.1); `8e1e75f`, `2ee3b08`, `f1cb933`, `6ffa9ba` (C.2). `tenant-workloads`: `88b870d` (registrations), `7343219` / `3ad8fdb` (acceptance add/remove). `orders-processor`: `3ec7833` / `5a731a7` (acceptance values, added/removed) |

## 1. Outcome

| Step | Result |
|---|:-:|
| **C.0** `applicationsetcontroller.enable.policy.override: true` (commit + manual `argo-cd` sync). Without it a per-ApplicationSet `applicationsSync` policy is silently ignored, so the plan's migration guards (C.1 `create-update`, R-3 `create-only`) would have had no effect | ✅ |
| **C.1** 5 platform ApplicationSets → `goTemplate: true` + `missingkey=error`, one commit each, zero-diff gated | ✅ |
| **C.2** Tenant self-registration: one `tenant-workloads` ApplicationSet (Git-files generator over `tenant-workloads/tenants/*/apps/*.yaml`) replaced `tenant-workloads-nonprod` + `-prod`; Applications adopted in place | ✅ |
| Acceptance | a second app registered and deregistered through `tenant-workloads` only — no control-plane commit (§3) | ✅ |
| Regression | **22/22** Synced/Healthy; R-1 audit PASS; smoke 11/11; `post-bootstrap` exit 0; all 6 ApplicationSets `goTemplate` + `missingkey=error`, no migration override left | ✅ |

## 2. Evidence

### Zero-diff gate (W14)
`argocd appset generate` renders through the live Argo CD (real cluster/Git generators); Applications are compared as normalised JSON (name, labels, annotations, finalizers, spec), old file vs new file, and new render vs live Applications.

| ApplicationSet | Apps | Old vs new | New vs live |
|---|:-:|:-:|:-:|
| addons-spoke-platform-config | 2 | identical | identical |
| kro-blueprints | 2 | identical | identical |
| addons-spoke-ack-credentials | 2 | identical | identical |
| addons-spoke-kyverno | 2 | identical | identical |
| addons-spoke | 4 | identical | identical |
| tenant-workloads-nonprod + -prod → tenant-workloads | 3 | identical | identical |

Negative checks: a misspelled key (`.nmae`) now **fails rendering**; the same typo under the old fasttemplate rendered Applications literally named `addon-platform-config-{{nmae}}` (L2-4 demonstrated). A deliberate label change is detected by the harness.

After C.1: **all 22 Applications kept their UID** (updated in place, none recreated or deleted).

### C.2 design (and deviations from the plan text)
| Plan | Implemented | Why |
|---|---|---|
| matrix of Git files × cluster generator (selected by `environment`) | Git-files generator only; the **template derives** the spoke (`prod` → `spoke-prod`, else `spoke-nonprod`) and the CARM account (222222222222 / 111111111111) from `env` | A cluster selector driven by a tenant-written value would let a tenant aim at prod; the platform should own the env → cluster/account mapping |
| `tenants/*/*/app.yaml` | `tenants/<tenant>/apps/<app>-<env>.yaml` | several apps per tenant per env; legacy `<env>/orders-service.yaml` files (unused pre-platform examples) left in place and labelled as such in `tenants/README.md` |
| C.1 includes the 2 tenant ApplicationSets | converted as part of C.2 | they are replaced by C.2; converting them first would be throwaway work |
| — | **Prod gate kept in the template**: `env ∉ {dev,test,prod}` or a prod `valuesRevision` that is not a 40-hex SHA → `fail` (rendering refused, nothing changes) | moving `valuesRevision` into the tenant repo must not weaken the Phase 2 promotion gate |
| — | optional `valuesFile` (default `deploy/values-<env>.yaml`); links built from `<app>-<env>` | otherwise every registered app was forced onto the orders values (same queue name → collision with the real `orders-dev`) |

Guard tests (scratch copies with list elements, via `argocd appset generate`): `env: staging` → **refused**; prod with `main` or a short SHA → **refused**; missing `port` → **refused** (`missingkey=error`); valid prod → `spoke-prod`, account 222222222222; valid test → `spoke-nonprod`, 111111111111.

### C.2 ownership transfer (R-3)
| Step | Result |
|---|---|
| 1. old ApplicationSets `applicationsSync: create-only` + `argocd.argoproj.io/sync-options: Prune=false` (`8e1e75f`) | live |
| 2. new `tenant-workloads` added, old files removed (`2ee3b08`) | new ApplicationSet reported "already owned by another ApplicationSet controller" (expected, no change); root app listed the old ones as *requires pruning* but did **not** delete them |
| 3. `kubectl delete applicationset tenant-workloads-nonprod tenant-workloads-prod --cascade=orphan` | new ApplicationSet adopted all 3 Applications |
| Check | **UIDs unchanged** for `orders-dev`, `orders-test`, `orders-prod`; workloads Running throughout; root Synced/Healthy |

Without step 1, removing the files would have let the root app (`prune: true`) delete the old ApplicationSets and, through owner references, the three Applications and their workloads.

## 3. Acceptance — tenant self-registration (W15)

| Action (no control-plane commit) | Result |
|---|---|
| `orders-processor`: `deploy/values-orders-demo-dev.yaml` (app `orders-demo`); `tenant-workloads`: `tenants/tenant-a/apps/orders-demo-dev.yaml` | Application `orders-demo-dev` created by `tenant-workloads` (160 s incl. Git polling), Synced/Healthy; destination `spoke-nonprod/orders-demo-dev`; namespace labels PSS `restricted` + image verification, account annotation 111111111111; QueueBackedService ACTIVE; queues `orders-demo-dev-queue` / `-dlq` in 111111111111; signed image admitted |
| Gap found → fixed | worker had **no cloud credential**: `post-bootstrap.sh` provisioned a fixed list of 3 workloads. Now it **discovers** workloads from the Applications owned by `tenant-workloads` and each namespace's QueueBackedService (`6ffa9ba`). Re-run: 4 workloads found, only the new credential provisioned and only that worker restarted; an order through `orders-demo-dev-queue` processed in 2 s |
| Deregistration: delete the registration file | Application removed (155 s), workload and both queues deleted; `orders-dev/test/prod` unaffected |
| Manual clean-up (not managed by Argo CD/ACK) | empty namespace + `orders-demo-dev-aws` Secret, moto IAM user `orders-demo-dev-worker`, DynamoDB table `orders-demo-dev-history` (created by the worker), demo values file |

## 4. Notes

| ID | Note |
|---|---|
| D-16 | **Deregistration residue.** Removing a registration removes everything Argo CD and ACK own, but not the namespace (Argo CD never deletes namespaces it created), the worker credential (IAM user + Secret) and data the worker created itself (DynamoDB table). Documented; a `post-bootstrap` prune of orphaned credentials is a candidate improvement. |
| D-17 | **Prod promotion moved** from `gitops-control-plane` (`valuesRevision` in `tenant-workloads-prod.yaml`) to a pull request in `tenant-workloads` (`tenants/tenant-a/apps/orders-prod.yaml`). The SHA requirement is enforced by the template; reviewer approval relies on `tenant-workloads` branch protection. `docs/developer-tutorial.md`, `README.md` and a note in `docs/production-promotion-guardrails.md` updated. |
| D-18 | A new registration needs `make post-bootstrap` once for its worker credential (documented in the tutorial). |
| D-19 | `argocd appset generate` prints a fatal error as a JSON log line; my first guard-test classifier counted it as a render. Fixed before the results above. |

## 5. Next
Track D (full rebuild acceptance) — needs the owner's go (O-4).
