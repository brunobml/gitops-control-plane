# Phase 3 Implementation Report — Run #07: B.7 Full Rebuild Acceptance (2026-10-02)

> **Status: Historical.** Record of the 2026-09-30 assessment and its remediation (Phases 1–5, closed 2026-10-03). Kept as evidence and not updated. For the lab as it is today, see the [README](../../../README.md) and the [2026-10-03 assessment](../../assessments/2026-10-03-lab-assessment.md).

| | |
|---|---|
| **Plan** | [`2026-10-01-lab-remediation-plan-phase3.md`](2026-10-01-lab-remediation-plan-phase3.md) v1.0 (GREEN LIGHT) |
| **Preceded by** | [Implemented-06](2026-10-01-lab-remediation-plan-phase3-implemented-06.md) (B.7 pre-flight), validated 🟢 in [Validation-06](2026-10-01-lab-remediation-plan-phase3-validation-06.md) |
| **Scope executed** | **B.7** full rebuild acceptance: destroy the lab and rebuild it from Git with the documented commands only |
| **Owner approval** | "go run B.7." (2026-10-02) |
| **Window** | 2026-10-02 00:20:30Z (teardown) → 00:27:43Z (acceptance complete), ≈ 7 min including two in-flight fixes |

## 1. Outcome

> **✅ B.7 PASSED.** The lab was rebuilt from Git with `make teardown` → `make setup` → `make bootstrap` → `make post-bootstrap`. All acceptance criteria are met. The cold start exposed **two script defects** (G8, G9), both fixed in this run. **No manual cluster changes** were made: each fix was a script change followed by re-running the same documented command.

## 2. Execution Log

| Step | Result |
|---|---|
| `make teardown` | 3 clusters, `moto-cloud` and `k3d-cloud-net` removed. Unrelated container `helm-lab-control-plane` untouched. Password files in `~/.config/gitops-lab/` kept (reused by setup) |
| `make setup` (1st) | Network 172.21.0.0/16, pinned moto, 3 clusters, Traefik, Argo CD, accounts, login OK (R2 retry) → **aborted at spoke registration (G8)** |
| `make setup` (2nd, after fix) | Existing resources skipped; both spokes registered and verified; Headlamp credentials generated; exit 0 |
| `make bootstrap` | Deployer identities, AppProjects, root Application applied |
| `make post-bootstrap` (1st) | Namespaces ready; **3 fresh worker keys provisioned** (111111111111 / 111111111111 / 222222222222); 4 worker pods restarted; **`argo-cd` adopted**; all Applications Synced/Healthy without manual intervention → **smoke stage 2 failed (G9, false negative)** |
| `make post-bootstrap` (2nd, after fix) | Idempotent: keys kept, no restarts, argo-cd already Synced; **smoke 9/9 passed**; exit 0 |

## 3. Defects Found and Fixed

| ID | Defect | Fix |
|---|---|---|
| **G8** | `register-spokes.sh` accepted only Argo CD connection state `Successful`. On a fresh hub, Argo CD reports `Unknown` ("Cluster has no applications and is not being monitored") until an app targets the cluster, so setup could **never** pass on a cold start. (On the old lab it passed because apps already existed.) | Read `connectionState.status` from `argocd cluster get -o json`. `Successful` passes, `Failed` aborts. `Unknown` triggers a direct check that the new token and CA authenticate to the spoke API (`auth can-i get namespaces`). The temporary kubeconfig is mode 600, so the token never appears in process arguments. A wrong token is rejected (negative test). The hub→spoke network path is then proven by the Argo CD connection state (below). |
| **G9** | Smoke stage 2 treated every non-`Running` pod in `argocd` as a failure, including the `redis-secret-init` hook pod (`Completed`) that the `argo-cd` adoption sync just ran | Exclude pods in phase `Succeeded`; Pending/Failed/CrashLoop pods are still reported |

## 4. Acceptance Evidence

| Criterion | Result |
|---|:-:|
| Applications Synced/Healthy | **18/18** ✅ |
| R-1 impersonation audit (`audit-impersonation.sh`), impersonation enabled | **PASS** ✅ |
| Argo CD cluster connection state | spoke-nonprod, spoke-prod, in-cluster **Successful** ✅ |
| Smoke test | **9/9**; end-to-end orders: dev 4 s, test 4 s (111111111111), prod 8 s (222222222222) ✅ |
| 6 SQS queues (3 + 3 DLQs) in CARM accounts; QueueBackedServices ACTIVE | ✅ |
| Logins `platform-admin`, `tenant-a` (built-in admin disabled) | ✅ |
| VAP `queuebackedservice-contract` bound on both spokes | ✅ |
| Prod promotion gate `blueprints-revision` = `v1.3.2` | ✅ |
| Helm release records on hub | none (Argo CD and Traefik owned by Argo CD) ✅ |
| `k3d-cloud-net` subnet | 172.21.0.0/16 ✅ |
| All nodes Ready on both spokes | ✅ |
| Credentials | new 30-day tokens; `lab/token-expires` **2026-11-01** (replaces the 2026-10-31 deadline) |

## 5. Notes

| ID | Note |
|---|---|
| D-34 | The new Argo CD pods are on the version pinned in Git (chart 10.9.4 via the `argo-cd` Application); the bootstrap Helm install is removed as designed (B.4). |
| D-35 | Headlamp kubeconfig and spoke tokens are regenerated on every rebuild; browser sessions to Headlamp/Argo CD need a fresh login. |
| D-36 | Of the 7 pre-flight items, G1, G7 and R2 (plus R5's create path) **were exercised on a cold start for the first time** here and worked. R3's re-sync loop was not needed: Argo CD retries converged within the namespace wait. |

## 6. Phase 3 Status

All Phase 3 steps are implemented. Remaining: independent validation of this report (validation-07) and of G8/G9.
