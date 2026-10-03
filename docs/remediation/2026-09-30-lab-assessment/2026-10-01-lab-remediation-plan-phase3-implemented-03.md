# Phase 3 Implementation Report — Run #03: Track C (+ blueprint v1.3.0) (2026-10-01)

> **Status: Historical.** Record of the 2026-09-30 assessment and its remediation (Phases 1–5, closed 2026-10-03). Kept as evidence and not updated. For the lab as it is today, see the [README](../../../README.md) and the [2026-10-03 assessment](../../assessments/2026-10-03-lab-assessment.md).

| | |
|---|---|
| **Plan** | [`2026-10-01-lab-remediation-plan-phase3.md`](2026-10-01-lab-remediation-plan-phase3.md) v1.0 (GREEN LIGHT, R-0 to R-4) |
| **Preceded by** | [Implemented-02](2026-10-01-lab-remediation-plan-phase3-implemented-02.md), validated 🟢 in [Validation-02](2026-10-01-lab-remediation-plan-phase3-validation-02.md) |
| **Scope executed** | **C.1** (then reverted by owner decision), **C.2**, **C.3**, **C.4**, and blueprint **v1.3.0** carrying **D.1** (hook only), **D.4**, **D.5** (externalRef part) |
| **Implemented by** | Claude (Opus 5.5), the plan's author. Independent validation requested. |
| **Commits** | `gitops-control-plane`: `d95c2ae`, `5891b5d` (C.1 + revert) · `f8f75d3` (runbook Issue E) · `e377af0` (platform-config) · `8839395` (prod → v1.3.0) · `aba2875`, `30a861e`, `30eafc6` (C.2) — `platform-catalog`: `ce2a8e2` → reverted `248e206` · `7f09700`, `74395d9` = tag **`v1.3.0`** |
| **Hub `argo-cd` Helm revision** | 14 (impersonation on); `argocd-secret` keys intact (D-4 fix holds) |

---

## 1. Outcome Summary

| Step | Finding | Result |
|---|---|:-:|
| C.1 | L4-6 tenant `*:*` kinds | ↩️ **Implemented, accepted, then reverted by owner decision** (see D-17). L4-6 → *Accepted residual risk* |
| C.2 | Rec 18 `argocd-manager` = cluster-admin | ✅ Impersonation on; `argocd-manager` is **read + impersonate** on both spokes; all writes go through deployer identities |
| C.3 | L4-5 kro `*/*` | ✅ `rbac.mode: aggregation` + blueprint-shipped ClusterRole; old unrestricted role pruned on both spokes |
| C.4 | PV2-2 namespace default-deny | ✅ Unselected pods are blocked (DNS only); worker allow-list unchanged |
| D.4 | L3-9 prod resources on deletion | ✅ `deletion-policy: retain` on prod queues, `delete` on dev/test |
| D.1 | Worker credentials hook | ✅ RGD part only (`envFrom` optional Secret); app change + credentials come in D.1/D.3 |
| D.5 | L2-6 env facts in RGD | ✅ `externalRef` to per-cluster `kube-system/platform-config` (GitOps-managed) |
| D.5 | L2-5 input validation | ⛔ **Not delivered** (D-14): kro refuses to add constraints to an existing CRD. Proposed: ValidatingAdmissionPolicy (needs owner/reviewer OK) |

---

## 2. Incidents, Deviations & Findings

| ID | Type | Detail |
|---|---|---|
| **D-14** | **Incident** | The first `v1.3.0` candidate (`ce2a8e2`) added schema markers (required, enum, min/max). kro 0.9.4 refused the CRD update ("breaking changes detected") and the **nonprod RGD went Inactive (~06:49–06:53, ~4 min)**. kro **still applied the new graph** to existing instances (workers rolled with the new `envFrom`), so a failed blueprint update is **not atomic**. Workloads kept serving; prod was unaffected (pinned to `v1.2.0`). **Root cause in my verification:** the feature probe tested a *fresh* RGD, not an *upgrade* of an existing one. Recovered by reverting (`248e206`, tree verified identical to `7fab51d`), then re-shipping a schema-unchanged candidate (`7f09700`). |
| **D-15** | **Process error (self-caught)** | During the revert, `git revert` did not create a commit and my follow-up `git commit --amend` **rewrote `ce2a8e2` locally**. The push was rejected as non-fast-forward; nothing was forced. Fixed by resetting to `origin/main` and creating a proper revert on top. (This is exactly the force-push risk that branch protection, step 0.3, guards against.) |
| **D-16** | Reboot incident (before Track C) | Docker Desktop's engine API and DNS relay hung (Argo CD couldn't resolve github.com → ComparisonError everywhere; workloads kept running). After the owner rebooted, **`k3d-spoke-nonprod-agent-0` stayed NotReady ("not authorized")**: its k3s agent load-balancer cache held `172.21.0.3`, which after the IP reshuffle belonged to **spoke-prod's** server. That took nonprod ACK down, so the dev/test queues weren't recreated while ACK still showed them as synced. Fixed by removing the cache file and restarting the agent; documented as runbook **Issue E** (`f8f75d3`). |
| **D-17** | Owner decision | C.1 (tenant whitelist = `QueueBackedService` only) made Argo CD **hide every kro child** (Deployment, ReplicaSets, Pods, Queues...) from the app's resource tree, because Argo CD filters the tree by the AppProject's permissions. Owner: "this is a lab I need to be able to see everything" → reverted to `*:*` (`5891b5d`). Residual risk is low: `tenant-a` cannot create or edit Applications (A.2 RBAC), so tenants can't make Argo CD render arbitrary manifests. My C.1 acceptance test missed the visibility impact; "can the owner still see everything?" is now part of every acceptance check. |
| **D-18** | Design deviation | Kept the RGD schema unchanged; input validation (L2-5) is open. Proposal: a ValidatingAdmissionPolicy on `queuebackedservices.kro.run` (no CRD change). |
| **D-19** | Finding | **kube-router programs NetworkPolicy rules a few seconds after a pod starts**, so a fresh pod has a brief window of unfiltered egress (the first C.4 probe, which connected immediately, was allowed; the same probe after a 20 s settle was blocked). Residual risk, inherent to the policy engine. |
| **D-20** | Design gap closed | The kro chart's mode switch leaves the old unrestricted `kro-cluster-role` + binding **orphaned** (addon apps have `prune: false`, D-11), so kro would have kept `*/*`. Removed per cluster with an explicit, resource-scoped `argocd app sync --prune --resource …` after reviewing the prune list. |
| **D-21** | Self-correction | An early C.2 pre-check suggested the hub controller couldn't impersonate; the cause was the wrong ServiceAccount name in my query (the controller runs as `argocd-application-controller`). With the correct name it can. |
| **D-22** | Design choice | `destinationServiceAccounts` entries for spoke projects use `server: "*"` (tenant apps address clusters by **name**; the projects' destinations still restrict clusters). The `default` project points at a **non-existent** identity on purpose. |
| **D-23** | Durability fix | `register-spokes.sh` re-created `argocd-manager-cluster-admin` on every run; it now calls `apply-argocd-spoke-rbac.sh --reduce-manager`. Proven by running `make rotate-spoke-tokens` (bindings stayed reduced). |

---

## 3. Evidence

### Post-reboot recovery (D-16)
* moto restarted 06:32:10 (state lost). **spoke-prod: ACK recreated both prod queues in ~97 s** with redrive intact (early D.2 data). Nonprod queues came back as soon as agent-0 was fixed (all 6 at 06:37:52).
* Hub CoreDNS upstream timeouts after reboot: 0. Smoke test green.

### C.1 (before revert)
* The forced sync of a temporary tenant app rendering a ConfigMap **failed**: `resource :ConfigMap is not permitted in project tenant-workloads`; nothing was created. Probe branch and app deleted.

### Blueprint v1.3.0 (`74395d9`)
* **Feature probe** (throwaway RGD `phase3probe`, deleted with its CRD and namespace): `externalRef` ✓, CEL conditional annotation ✓, defaults ✓, enum/min/max/required rejected `prood`/`50`/`0`/missing ✓ (but see D-14: not usable as an *upgrade*).
* **platform-config** (`e377af0`): `kube-system/platform-config` per spoke (`INGRESS_PORT` 8081 / 8082) via ApplicationSet `addons-spoke-platform-config`; created before the RGD referenced it.
* **Nonprod after `7f09700`:** RGD Active (schema block byte-identical, no CRD change); both instances ACTIVE; `ns-default-deny` + worker netpol; `envFrom` `orders-<env>-aws` optional; deletion-policy `delete`; ingress link and `MOTO_ENDPOINT` from `platform-config`; ClusterRole present.
* **Prod after promotion** (`v1.3.0`, `8839395` + `make promote-blueprints`): RGD Active, `orders-prod` ACTIVE, rollout clean under PDB, **deletion-policy `retain`** on both prod queues, ingress link `…:8082`, ConfigMap drift recreated in 5 s, worker → moto OPEN / `1.1.1.1` BLOCKED, ingress 200.

### C.4
| Probe | Phase 2 (before) | Now |
|---|---|---|
| Unselected pod → `1.1.1.1:443` | OPEN | **BLOCKED** (after 20 s settle; D-19) |
| Unselected pod → API server `10.43.0.1:443` | OPEN | **BLOCKED** |
| Unselected pod → `moto-cloud:5000` | OPEN | **BLOCKED** |
| Unselected pod → DNS | OK | OK |
| Worker → moto / internet / API server | OPEN / BLOCKED / BLOCKED | unchanged |

### C.3
| kro ServiceAccount can... | Before | After (both spokes) |
|---|---|---|
| create secrets / clusterrolebindings / delete nodes | yes / yes / yes | **no / no / no** |
| create queues, update deployments, create networkpolicies, update qbs/finalizers, get configmaps in kube-system, update CRDs | yes | yes |
* kro "forbidden" log lines after the switch: **0**. Drift (nonprod): worker scale, deleted ConfigMap and deleted `ns-default-deny` each restored in **5 s**.

### C.2
* **R-1 audit** (`scripts/audit-impersonation.sh`): 5/5 projects have entries; **17/17** Applications resolve to an **existing** deployer identity → `PASS` (before and after enabling).
* Impersonation enabled (Helm rev 14). **17/17 forced syncs succeeded**; the controller log shows `impersonationEnabled=true serviceAccount=…deployer` (223 lines).
* `argocd-manager` reduced (nonprod, then prod): create deployments / delete namespaces / create CRBs → **no**; list pods / get pods/log → yes; impersonate the deployers → yes; impersonate other SAs → **no**.
* After the reduction: nonprod **7/7** and prod **6/6** forced syncs **succeeded**, so writes provably go through the deployers. Self-heal of a manual `QueueBackedService` edit reverted in **5 s** on both spokes, as `argocd-tenant-deployer`.
* **Visibility (D-17 rule):** the full resource tree is still shown in Argo CD (Pods, Deployment, ReplicaSets, Queues, NetworkPolicies, PDB…).
* Durability: `make rotate-spoke-tokens` → both spokes `Successful`, Headlamp refreshed, and **no** cluster-admin binding afterwards.
* Rollback ready: `scripts/rollback-argocd-impersonation.sh` (kubectl-only).

### Regression
* Smoke test (8 stages, 17 apps): **exit 0**. Credentials valid until **2026-10-31 07:19 UTC**. Headlamp shows nodes on all 3 clusters.

---

## 4. Open Items

| Item | Status |
|---|---|
| L2-5 input validation | Needs a decision: ValidatingAdmissionPolicy proposed (D-18) |
| Track D (D.1 app v1.4.0 + per-env credentials, D.2 moto test, D.3 CARM) | Next |
| B.4 / B.7 | End of phase; B.7 needs explicit owner approval |
| 0.3 / 0.4 | Owner GitHub UI actions (branch protection would have hard-blocked D-15's mistake) |
| Runbook | Owner to review Issue C (annotation resync doesn't trigger ACK) and Issue D (moto binding until D.2) |
