# Phase 3 Remediation Validation — Run #02: Track B (2026-10-01)

> **Status: Historical.** Record of the 2026-09-30 assessment and its remediation (Phases 1–5, closed 2026-10-03). Kept as evidence and not updated. For the lab as it is today, see the [README](../../../README.md) and the [2026-10-03 assessment](../../assessments/2026-10-03-lab-assessment.md).

| | |
|---|---|
| **Validates** | [`2026-10-01-lab-remediation-plan-phase3-implemented-02.md`](2026-10-01-lab-remediation-plan-phase3-implemented-02.md) (commit `7c8d203`) |
| **Commits under test** | `gitops-control-plane@7fd2adf`, `5aeb71b`, `c938212`, `aeed40a`, `98300d7`, `aeddef3`, `7c8d203` |
| **Against** | [Phase 3 plan v1.0](2026-10-01-lab-remediation-plan-phase3.md): authorized scope **Track B (Steps B.1, B.2, B.3, B.5, B.6)**, remarks **R-0 to R-4** |
| **Method** | Independent live verification across all 3 k3d clusters, Argo CD Application and ApplicationSet specs, Helm release records, live drift injection and self-heal timing on AppProjects, controller deployments and Hub Traefik, version pinning checks in scripts, and 8-stage smoke testing. |
| **Changes made by this validation** | Deliberate live drift tests: (1) injected rogue repository into `tenant-workloads.spec.sourceRepos` (reverted by self-heal); (2) deleted `deploy/kro` on nonprod (recreated by self-heal); (3) scaled `deploy/traefik` on Hub to 2 replicas (reverted to 1 by self-heal). All objects restored to Git source of truth. No code commits. |
| **Validated By / Date** | Antigravity (Advanced Agentic AI Peer Reviewer) · 2026-10-01 |

---

## Verdict

> ### 🟢 VALIDATED — Track B Scope is Complete and Robust
>
> All authorized steps in Track B (B.1, B.2, B.3, B.5, B.6) are implemented, active, and verified on the live system.
> 
> The platform layer is now fully declared in GitOps: AppProjects are reconciled with self-healing, Kro and ACK SQS controllers on both spokes have been adopted into Argo CD ApplicationSets with zero downtime, Hub Traefik is managed declaratively by Argo CD, controller configurations are promotion-gated to match blueprint release tags, and all 15 Applications feature sync retry resilience.

| Step | Finding | Result |
|---|---|:-:|
| **B.1** | PV-4 `projects/` not reconciled | ✅ **Closed**: `platform-projects` Application manages all 5 AppProjects; injected drift reverted in **6 s**. |
| **B.2** | L2-1 / L3-8 Imperative spoke controllers | ✅ **Closed**: Kro, ACK SQS, and credentials on both spokes adopted by Argo CD with zero disruption; Helm records deleted; deleted `deploy/kro` recreated in **10 s**; prod controller values gated by `v1.2.0` blueprint tag. |
| **B.3** | Hub Traefik under GitOps | ✅ **Closed**: Adopted into `addon-traefik` with zero disruption; scaled deployment reverted to 1 replica in **6 s**; ingress routing intact. |
| **B.5** | L3-6 Floating versions | ✅ **Closed**: Pinned `rancher/k3s:v1.35.5-k3s1` across all clusters; pinned `motoserver/moto@sha256:91fd602a…` by registry digest (D-9); zero unversioned Helm installs. |
| **B.6** | L3-7 Sync resilience | ✅ **Closed**: `retry.limit: 5` with exponential backoff active across all **15** Applications. |

---

## 1. Step-by-Step Validation Evidence

### Step B.1: Reconcile `projects/` (PV-4) ✅

| Check | Evidence | Result |
|---|---|:-:|
| `platform-projects` Application | Live spec: repo `gitops-control-plane.git`, path `projects`, targetRevision `main`, `prune: false`, `selfHeal: true`, `retry.limit: 5`. Status: `Synced` / `Healthy`. | ✅ |
| AppProjects managed | 5 AppProjects tracked: `control-plane`, `default`, `platform-addons`, `platform-catalog`, `tenant-workloads`. All carry `sync-options: Prune=false`. | ✅ |
| **Live Self-Healing Test** | Injected `spec.sourceRepos: ["https://github.com/evil-corp/rogue.git"]` into `tenant-workloads`. Observed live: **reverted back to Git state within 6 seconds**. | ✅ |

---

### Step B.2: Spoke Controllers as GitOps ApplicationSets (L2-1, L3-8, L3-6) ✅

1. **Generated Applications (6 total):**
   - `addon-kro-spoke-nonprod`, `addon-ack-sqs-spoke-nonprod`, `addon-ack-credentials-spoke-nonprod`
   - `addon-kro-spoke-prod`, `addon-ack-sqs-spoke-prod`, `addon-ack-credentials-spoke-prod`
   All 6 applications report `Synced` and `Healthy`.
2. **Promotion-Gated Controller Values (D-8):**
   - `addon-kro-spoke-nonprod` & `addon-ack-sqs-spoke-nonprod`: values `targetRevision: main`
   - `addon-kro-spoke-prod` & `addon-ack-sqs-spoke-prod`: values `targetRevision: v1.2.0` (matching cluster `blueprints-revision` annotation).
3. **Helm Records Cleaned Up:**
   `helm list -A` on both `k3d-spoke-nonprod` and `k3d-spoke-prod` shows **zero** Kro or ACK releases. Only k3s built-in traefik remains in `kube-system`.
4. **Controller Pods & Configuration:**
   - Both spokes run `kro` and `ack-sqs-controller-sqs-chart` pods with 0 restarts and status `Running`.
   - `RECONCILE_DEFAULT_RESYNC_SECONDS` verified as `300` on both ACK deployments.
5. **Resource Safety (R-2 / D-7):**
   Verified `spec.syncPolicy.preserveResourcesOnDeletion: true` is configured in both `applicationsets/addons-spoke.yaml` and `applicationsets/addons-spoke-ack-credentials.yaml`.
6. **Live Controller Self-Healing Test:**
   Executed `kubectl delete deploy/kro -n kro` on `k3d-spoke-nonprod`. Observed live: **Argo CD recreated `deploy/kro` within 10 seconds**; pod became Ready and Running.

---

### Step B.3: Hub Traefik under GitOps ✅

1. **`addon-traefik` Application:**
   - Spec: chart `traefik:41.6.1`, repo `https://traefik.github.io/charts`, `ServerSideApply=true`, `prune: false`, `selfHeal: true`.
   - Status: `Synced` / `Healthy`.
2. **Helm Record Cleaned Up:**
   `helm list -n traefik` on `k3d-hub-cluster` is **empty** (Helm release secret removed; Argo CD owns the deployment).
3. **Live Self-Healing Test:**
   Scaled `deploy/traefik` in namespace `traefik` to 2 replicas. Observed live: **Argo CD reverted replicas back to 1 within 6 seconds**.
4. **Traffic Continuity:**
   `curl` to `http://127.0.0.1:8080/` with `Host: headlamp.localhost` and `Host: argocd.localhost` returned HTTP 200 without disruption.

---

### Step B.5: Version Pinning (L3-6) ✅

Inspected `scripts/setup-hub-spoke.sh`:
- k3s cluster nodes: `--image rancher/k3s:v1.35.5-k3s1` across all 3 clusters.
- Moto Cloud container: `motoserver/moto@sha256:91fd602a21f49cf9eb82fdf474015a3c131d40104c8297ea6a2ca920708ae32c` (registry digest, resolving D-9).
- Helm installs: zero unversioned installs (`--version 10.9.4` on Argo CD, `--version 41.6.1` on Traefik).
- Zero `:latest` tags remain.

---

### Step B.6: Sync Resilience (L3-7) ✅

Inspected all **15** Applications in Argo CD:
```text
NAME                                  SYNC     HEALTH    RETRY   SELFHEAL
addon-ack-credentials-spoke-nonprod   Synced   Healthy   5       true
addon-ack-credentials-spoke-prod      Synced   Healthy   5       true
addon-ack-sqs-spoke-nonprod           Synced   Healthy   5       true
addon-ack-sqs-spoke-prod              Synced   Healthy   5       true
addon-headlamp                        Synced   Healthy   5       true
addon-kro-spoke-nonprod               Synced   Healthy   5       true
addon-kro-spoke-prod                  Synced   Healthy   5       true
addon-traefik                         Synced   Healthy   5       true
kro-blueprints-spoke-nonprod          Synced   Healthy   5       true
kro-blueprints-spoke-prod             Synced   Healthy   5       true
orders-dev                            Synced   Healthy   5       true
orders-prod                           Synced   Healthy   5       true
orders-test                           Synced   Healthy   5       true
platform-projects                     Synced   Healthy   5       true
root-control-plane                    Synced   Healthy   5       true
```
- All 15 applications configured with `retry.limit: 5` and backoff.
- All 15 applications configured with `selfHeal: true`.

---

## 2. Regression & Overall System Health

| Check | Live Result | Status |
|---|---|:-:|
| Full Smoke Test (`scripts/smoke-test-hub-spoke.sh`) | All 8 stages exit 0 (checking all 15 applications and all 8 credentials) | ✅ |
| Account Secrets after Helm rev 13 | `argocd-secret` retains `platform-admin` and `tenant-a` passwords (D-4 fix holds) | ✅ |
| Spoke Cluster Registrations | `spoke-nonprod` and `spoke-prod`: `Successful` | ✅ |
| Workload Pods | `orders-dev` (1), `orders-test` (1), `orders-prod` (2) Ready, 0 restarts | ✅ |
| Workload Ingress | `orders-dev` (8081), `orders-test` (8081), `orders-prod` (8082) return HTTP 200 | ✅ |
| SQS Queues & DLQs | All 6 named queues verified in Moto Cloud | ✅ |
| Credential Expiry (Stage 8) | All 8 credentials valid for 29d (until 2026-10-31 04:05/04:21 UTC) | ✅ |

---

## 3. Observations & Carry-Forward

| ID | Sev | Observation | Note / Next Action |
|---|---|---|---|
| **PV3-4** | Info | **Track B Pending Items:** Step B.4 (stretch: Argo CD self-management) and Step B.7 (rebuild acceptance) are not yet executed. B.7 requires explicit owner approval as it recreates the lab. | Defer B.4 and B.7 to the end of Phase 3 as scheduled in the plan's §8 execution sequence. |
| **PV3-5** | Info | **Controller Promotion Decoupling:** Gating spoke controller values on `blueprints-revision` ensures controller configuration drift (e.g. resync intervals) cannot reach production unexpectedly. | Established as a durable architectural pattern for platform addons. |

---

## 4. Phase 3 Cumulative Status

| Track | Scope | Status |
|---|---|:-:|
| **Track 0** | Steps 0.1, 0.2 (Token rotation & expiry check) | ✅ **Closed** (Validation #01) |
| **Track 0** | Steps 0.3, 0.4 (GitHub UI branch protection & orphan cleanup) | ⏳ Pending Owner UI Action |
| **Track A** | Steps A.1, A.2, A.3 (Localhost binding, Argo CD RBAC, Headlamp) | ✅ **Closed / Accepted Residual** (Validation #01) |
| **Track B** | Steps B.1, B.2, B.3, B.5, B.6 (GitOps platform layer) | ✅ **Closed** (Validation #02) |
| **Track B** | Steps B.4, B.7 (Argo CD self-management, Rebuild test) | ⏳ Deferred to end of Phase 3 |
| **Track C** | Steps C.1–C.4 (Tenant kinds, Impersonation, Kro RBAC, NetPol default-deny) | ⏳ Ready for Implementation |
| **Track D** | Steps D.1–D.5 (Worker credentials, Moto resilience, CARM, Deletion policy) | ⏳ Scheduled after Track C |

---

## 5. Next Actions

Track B is validated. The control plane is ready to proceed with **Track C (Least Privilege & Tenant Guardrails)** in the following sequence:
1. **Step C.1:** Narrow the tenant AppProject (`tenant-workloads`) `namespaceResourceWhitelist` strictly to `kro.run/QueueBackedService`.
2. **Release Blueprint `v1.3.0`:** Ship `kro-queue-backed-service` ClusterRole, namespace default-deny NetworkPolicy (`ns-default-deny`), and D.1/D.4/D.5 schema additions to non-prod first.
3. **Step C.3:** Switch Kro to `rbac.mode: aggregation` on non-prod, verify, and promote `v1.3.0` to prod via the blueprint gate.
4. **Step C.4:** Verify namespace default-deny enforcement with control probe.
5. **Step C.2:** Preflight audit of all AppProjects, deploy `argocd-tenant-deployer` / `argocd-platform-deployer`, and enable destination impersonation (Remark R-1).
