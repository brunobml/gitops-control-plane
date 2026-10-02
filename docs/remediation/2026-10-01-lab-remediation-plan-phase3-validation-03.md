# Phase 3 Remediation Validation — Run #03: Track C & Blueprint v1.3.0 (2026-10-01)

| | |
|---|---|
| **Validates** | [`2026-10-01-lab-remediation-plan-phase3-implemented-03.md`](2026-10-01-lab-remediation-plan-phase3-implemented-03.md) (commit `b5436b8`) |
| **Commits under test** | `gitops-control-plane`: `d95c2ae`, `5891b5d`, `f8f75d3`, `e377af0`, `8839395`, `aba2875`, `30a861e`, `30eafc6`, `b5436b8`<br>`platform-catalog`: `ce2a8e2`, `248e206`, `7f09700`, `74395d9` (tag **`v1.3.0`**) |
| **Against** | [Phase 3 plan v1.0](2026-10-01-lab-remediation-plan-phase3.md): **Track C (Steps C.1, C.2, C.3, C.4)** and blueprint **v1.3.0** carrying **D.1** (credential hook), **D.4** (deletion policy), **D.5** (externalRef config) |
| **Method** | Independent live verification across all 3 k3d clusters (`k3d-hub-cluster`, `k3d-spoke-nonprod`, `k3d-spoke-prod`), `kubectl auth can-i` permission matrix testing, live self-healing under impersonation, NetworkPolicy egress isolation probes with PSS-restricted test pod, externalRef resolution check, Helm revision audit, and 8-stage smoke testing. |
| **Changes made by this validation** | Deliberate live tests: (1) patched QBS `orders-dev` to 2 replicas (reverted to 1 by self-heal under tenant impersonation in 2s); (2) deleted child ConfigMap `orders-dev-config` (recreated by Kro in ~264ms); (3) executed PSS-compliant curl/nslookup probe pod in `orders-dev` to verify `ns-default-deny` egress blocking; (4) verified worker pod egress and ingress connectivity. All temporary test pods cleaned up. No code commits. |
| **Validated By / Date** | Antigravity (Advanced Agentic AI Peer Reviewer) · 2026-10-01 |

---

## Verdict

> ### 🟢 VALIDATED — Track C & Blueprint v1.3.0 Scope is Complete, Verified, and Resilient
>
> All authorized steps in Track C (C.1, C.2, C.3, C.4) and Blueprint v1.3.0 (D.1 hook, D.4 retain, D.5 externalRef) are implemented, active, and independently verified on the live system.
> 
> Spoke access control has been transformed to least-privilege: `argocd-manager` no longer holds `cluster-admin` on either spoke and is restricted to read + impersonate; all GitOps writes execute through scoped deployer identities (`argocd-tenant-deployer` and `argocd-platform-deployer`). Kro runs with `rbac.mode: aggregation`, dropping all unrestricted `*/*` permissions and retaining only blueprint-granted access. Workload namespaces enforce default-deny egress NetworkPolicies, while blueprint v1.3.0 decouples per-cluster environment configuration via `externalRef` and safeguards production cloud queues from accidental deletion.

| Step | Finding | Result |
|---|---|:-:|
| **C.1** | L4-6 tenant `*:*` kinds | ↩️ **Accepted residual risk by owner decision (D-17)**; full visibility in Argo CD UI preserved; tenant write boundary enforced at Kubernetes RBAC level via C.2 `argocd-tenant-deployer`. |
| **C.2** | Rec 18 `argocd-manager` = cluster-admin | ✅ **Closed**: Destination sync impersonation active (Helm rev 14); `argocd-manager` reduced to read + impersonate on both spokes; writes executed via deployer SAs; R-1 audit passes for 17/17 apps. |
| **C.3** | L4-5 kro `*/*` | ✅ **Closed**: `rbac.mode: aggregation` active; aggregated ClusterRole `kro-queue-backed-service` shipped; legacy unrestricted role pruned on both spokes; 0 forbidden log lines. |
| **C.4** | PV2-2 namespace default-deny | ✅ **Closed**: `ns-default-deny` NetworkPolicy active across all workload namespaces; unselected pods blocked from egress (DNS only); worker allow-list unaffected. |
| **D.1** | Worker credentials hook | ✅ **Closed (RGD part)**: Worker deployment includes optional `secretRef: orders-<env>-aws`; backward-compatible with mock credentials. |
| **D.4** | L3-9 prod resources on deletion | ✅ **Closed**: `services.k8s.aws/deletion-policy` set to `retain` on prod queues and `delete` on dev/test. |
| **D.5** | L2-6 env facts in RGD | ✅ **Closed**: Per-cluster facts (`MOTO_ENDPOINT`, `INGRESS_PORT`) decoupled via `externalRef` to `kube-system/platform-config`. |
| **D.5** | L2-5 input validation | ⛔ **Deferred (D-14 / D-18)**: Kro 0.9.4 rejects CRD schema updates on existing instances ("breaking changes detected"); ValidatingAdmissionPolicy proposed as non-breaking solution. |

---

## 1. Step-by-Step Validation Evidence

### Step C.1: Tenant AppProject Whitelist & Visibility (L4-6, D-17) ↩️

1. **Context & Verification:**
   - Plan C.1 proposed restricting `projects/tenant-workloads.yaml` `namespaceResourceWhitelist` strictly to `kro.run/QueueBackedService`.
   - Live testing in Run #03 revealed that Argo CD filters the application's live resource tree using the AppProject whitelist. Restricting to `QueueBackedService` concealed all child resources created by Kro (`Deployment`, `ReplicaSet`, `Pod`, `Service`, `Queue`, `NetworkPolicy`, `PDB`) in the Argo CD UI.
   - Owner decision (D-17): Full visibility across the lab is required. The AppProject whitelist was restored to `group: "*", kind: "*"` (commit `5891b5d`).
2. **Independent Risk & Defense-in-Depth Assessment:**
   - In ordinary setups, open AppProject whitelists allow tenants to deploy arbitrary resources. Here, two layers neutralize that risk:
     1. **Argo CD RBAC (Phase 3 A.2):** Tenant `tenant-a` is granted sync-only access to `tenant-workloads/*` and cannot create or edit Application specs.
     2. **Kubernetes RBAC via C.2 Impersonation:** Sync operations for `tenant-workloads` run under `argocd-tenant-deployer`. As independently validated below, `argocd-tenant-deployer` **cannot** create Deployments, Secrets, Services, or any kind other than `Namespace` and `QueueBackedService`.
   - **Verdict:** Reverting C.1 while enforcing C.2 provides the optimal balance of operator visibility and strict cluster-level least privilege.

---

### Step C.2: Destination Impersonation & Non-Admin `argocd-manager` (Rec 18) ✅

1. **Reviewer Remark R-1 Audit:**
   - Ran `scripts/audit-impersonation.sh` independently against `k3d-hub-cluster`:
     - 5/5 AppProjects carry valid `destinationServiceAccounts`.
     - `default` project maps `*/*` to non-existent `kube-system:argocd-default-project-denied` (hard-deny guardrail, D-22).
     - **17/17 Applications** resolve to an existing deployer identity on their target cluster (`argocd-tenant-deployer` for tenant workloads; `argocd-platform-deployer` for platform addons and catalog).
     - Result: `PASS`.
2. **Impersonation Setting & Helm Revision:**
   - `clusters/values-argocd-hub.yaml` sets `application.sync.impersonation.enabled: "true"`.
   - Live `argocd-cm` ConfigMap on `k3d-hub-cluster` verified with `application.sync.impersonation.enabled: "true"`.
   - Helm release `argo-cd` is at revision 14 (`deployed`).
   - `argocd-secret` retains account password hashes for `platform-admin` and `tenant-a` (D-4 fix holds).
3. **Spoke RBAC Reduction & Permission Verification:**
   - `argocd-manager-cluster-admin` ClusterRoleBinding is **absent / deleted** on both `k3d-spoke-nonprod` and `k3d-spoke-prod`.
   - `argocd-manager-read-impersonate` is active on both spokes.
   - Tested live permissions with `kubectl auth can-i` across both spokes:
     | Action | `argocd-manager` | `argocd-tenant-deployer` | `argocd-platform-deployer` |
     |---|:---:|:---:|:---:|
     | `create deployments` | ❌ **no** | ❌ **no** | ✅ yes |
     | `delete namespaces` | ❌ **no** | ❌ **no** | ✅ yes |
     | `create clusterrolebindings` | ❌ **no** | ❌ **no** | ✅ yes |
     | `create secrets` | ❌ **no** | ❌ **no** | ✅ yes |
     | `delete nodes` | ❌ **no** | ❌ **no** | ✅ yes |
     | `get pods` / `get pods/log` | ✅ **yes** | ❌ no | ✅ yes |
     | `impersonate argocd-tenant-deployer` | ✅ **yes** | ❌ no | ❌ no |
     | `impersonate argocd-platform-deployer`| ✅ **yes** | ❌ no | ❌ no |
     | `impersonate default` SA | ❌ **no** | ❌ no | ❌ no |
     | `create / patch namespaces` | ❌ no | ✅ **yes** | ✅ yes |
     | `manage queuebackedservices.kro.run`| ❌ no | ✅ **yes** | ✅ yes |
4. **Live Self-Healing Under Impersonation:**
   - Injected live drift into `orders-dev` on `k3d-spoke-nonprod`: patched `queuebackedservices.kro.run/orders` from `replicas: 1` to `replicas: 2`.
   - Observed live: **Argo CD detected the drift and reconciled `replicas` back to `1` in ~2.0 seconds**.
   - Because `argocd-manager` has zero write permissions on the spoke, this reconciliation provably executed via impersonation of `argocd-tenant-deployer`.
5. **Break-Glass Rollback & Script Durability:**
   - Verified `scripts/rollback-argocd-impersonation.sh` is present and functional using kubectl-only commands.
   - Verified `scripts/register-spokes.sh` invokes `apply-argocd-spoke-rbac.sh --reduce-manager`, guaranteeing that token rotation (`make rotate-spoke-tokens`) does not re-grant `cluster-admin`.

---

### Step C.3: Kro Least Privilege & Aggregated RBAC (L4-5) ✅

1. **Configuration & Mode Verification:**
   - `platform-catalog/controllers/kro/values-kro.yaml` declares `rbac.mode: aggregation`.
   - Blueprint ClusterRole `kro-queue-backed-service` (`platform-catalog/blueprints/kro-rbac-queue-backed-service.yaml`) carries label `rbac.kro.run/aggregate-to-controller: "true"`.
   - Verified `kro:controller` ClusterRole on both spokes aggregates `kro:controller:static` and `kro-queue-backed-service`.
2. **Legacy Role Pruning (D-20):**
   - Verified legacy unrestricted `kro-cluster-role` and `kro-cluster-role` binding are **absent / deleted** on both `k3d-spoke-nonprod` and `k3d-spoke-prod`.
3. **Kro ServiceAccount Permission Matrix:**
   - Tested live permissions for `system:serviceaccount:kro:kro` across both spokes:
     | Resource / Action | Result | Security Assessment |
     |---|:---:|---|
     | `create secrets` | ❌ **no** | Kro cannot access or leak cluster secrets |
     | `create clusterrolebindings` | ❌ **no** | Kro cannot escalate cluster privileges |
     | `delete nodes` | ❌ **no** | Kro cannot disrupt node infrastructure |
     | `create queues.sqs.services.k8s.aws` | ✅ **yes** | Required for ACK SQS child resources |
     | `update deployments` | ✅ **yes** | Required for workload container management |
     | `create networkpolicies` | ✅ **yes** | Required for C.4 netpol resources |
     | `update queuebackedservices/finalizers` | ✅ **yes** | Required for blockOwnerDeletion child cleanup |
     | `get configmaps in kube-system` | ✅ **yes** | Required for D.5 platform-config externalRef |
4. **Log Inspection & Child Resource Self-Healing:**
   - Inspected Kro controller logs on both spokes: **0 "forbidden" log lines**.
   - Deleted child ConfigMap `orders-dev-config` in `orders-dev` on `k3d-spoke-nonprod`.
   - Observed live: **Kro recreated `orders-dev-config` in ~264 ms** using aggregated permissions.

---

### Step C.4: Namespace Default-Deny NetworkPolicy (PV2-2) ✅

1. **Policy Specification & Deployment:**
   - NetworkPolicy `ns-default-deny` is active across all workload namespaces:
     - `orders-dev-ns-default-deny` in `orders-dev` (nonprod)
     - `orders-test-ns-default-deny` in `orders-test` (nonprod)
     - `orders-prod-ns-default-deny` in `orders-prod` (prod)
   - Configuration: `podSelector: {}`, `policyTypes: [Ingress, Egress]`, egress allowed strictly to `kube-dns` on port 53 (UDP/TCP).
2. **Live Isolation Probe (PSS Restricted):**
   - Launched an unselected test pod (`netpol-probe`) in `orders-dev` matching Pod Security Standards `restricted:latest` (non-root, drop ALL, read-only root FS, seccomp RuntimeDefault).
   - Allowed 20-second settlement window for kube-router rule programming (accounting for finding D-19).
   - Tested egress connectivity from the unselected pod:
     | Destination | Expected | Live Result | Status |
     |---|---|---|:---:|
     | DNS Resolver `10.43.0.10:53` | Allowed | Reached resolver on port 53 | ✅ |
     | Internet `1.1.1.1:443` | Blocked | `curl` exit code 7 (Failed to connect) | ✅ |
     | API Server `10.43.0.1:443` | Blocked | `curl` exit code 7 (Failed to connect) | ✅ |
     | Moto Cloud `moto-cloud:5000` | Blocked | `curl` exit code 7 (Failed to connect) | ✅ |
   - Deleted `netpol-probe` cleanly after test.
3. **Worker Allow-List Continuity:**
   - Tested egress from running worker pod `orders-dev-worker`:
     - Moto Cloud `http://moto-cloud:5000/moto-api/data.json`: HTTP 200 (OPEN).
     - Internet `1.1.1.1:443`: Connection Refused (BLOCKED).
     - API Server `10.43.0.1:443`: Connection Refused (BLOCKED).
   - Ingress endpoints through Traefik ports return HTTP 200 across all workloads:
     - `orders-dev.localhost:8081` -> HTTP 200
     - `orders-test.localhost:8081` -> HTTP 200
     - `orders-prod.localhost:8082` -> HTTP 200

---

### Blueprint v1.3.0 Promotion & Partial Track D Deliveries ✅

1. **Step D.1 (Worker Credentials Hook):**
   - Inspected worker deployment specs across all 3 environments:
     - `orders-dev-worker`: `envFrom: [{"secretRef":{"name":"orders-dev-aws","optional":true}}]`
     - `orders-test-worker`: `envFrom: [{"secretRef":{"name":"orders-test-aws","optional":true}}]`
     - `orders-prod-worker`: `envFrom: [{"secretRef":{"name":"orders-prod-aws","optional":true}}]`
   - Verified workloads continue operating cleanly with mock credentials when the Secret is absent.
2. **Step D.4 (Cloud Resource Deletion Policy):**
   - Inspected SQS queue CR annotations across spokes:
     - `orders-dev-queue` & `orders-dev-dlq`: `services.k8s.aws/deletion-policy: delete`
     - `orders-test-queue` & `orders-test-dlq`: `services.k8s.aws/deletion-policy: delete`
     - `orders-prod-queue` & `orders-prod-dlq`: `services.k8s.aws/deletion-policy: retain`
   - Accidental deletion of prod workloads will retain cloud queues and DLQs in production.
3. **Step D.5 (Per-Cluster Config Decoupling via `externalRef`):**
   - ConfigMap `kube-system/platform-config` managed by `addons-spoke-platform-config` ApplicationSet:
     - `spoke-nonprod`: `INGRESS_PORT: "8081"`, `MOTO_ENDPOINT: http://moto-cloud:5000`
     - `spoke-prod`: `INGRESS_PORT: "8082"`, `MOTO_ENDPOINT: http://moto-cloud:5000`
   - RGD `platformconfig` resource references `kube-system/platform-config` via `externalRef`.
   - Verified live Ingress annotations resolve dynamically:
     - `orders-dev`: `http://orders-dev.localhost:8081`
     - `orders-prod`: `http://orders-prod.localhost:8082`
4. **Step D.5 (Input Validation Status - D-14 / D-18):**
   - Kro 0.9.4 rejects CRD schema constraint additions (required, enum, min/max) on existing instances with `breaking changes detected`, making the RGD Inactive.
   - Claude Opus correctly identified this, reverted commit `ce2a8e2` with `248e206`, and released `7f09700` with graph-only updates.
   - Proposed resolution: Kubernetes 1.30+ `ValidatingAdmissionPolicy` on `queuebackedservices.kro.run` without mutating the Kro-managed CRD.
5. **Production Promotion to `v1.3.0`:**
   - `clusters/blueprint-revisions.env` pins `spoke-prod=v1.3.0`.
   - `kro-blueprints-spoke-prod` Application is `Synced` to commit `74395d9` (tag `v1.3.0`).
   - `orders-prod` runs 2 worker pods under `orders-prod-pdb` (minAvailable: 1), 0 restarts.

---

## 2. Regression & Overall System Health

| Check | Live Result | Status |
|---|---|:-:|
| Full Smoke Test (`scripts/smoke-test-hub-spoke.sh`) | All 8 stages exit 0 across all 17 applications and 8 credentials | ✅ |
| Account Secrets after Helm rev 14 | `argocd-secret` retains `platform-admin` and `tenant-a` passwords | ✅ |
| Spoke Cluster Registrations | `spoke-nonprod` and `spoke-prod` connected and `Successful` | ✅ |
| Workload Pods | `orders-dev` (1), `orders-test` (1), `orders-prod` (2) Ready, 0 restarts | ✅ |
| Workload Ingress | HTTP 200 on ports 8081 (`dev`, `test`) and 8082 (`prod`) | ✅ |
| SQS Queues & DLQs | All 6 named queues verified in Moto Cloud with RedrivePolicies | ✅ |
| Headlamp Multi-Cluster UI | HTTP 200 on `headlamp.localhost:8080`; tokens valid for 29 days | ✅ |
| Credential Expiry (Stage 8) | All credentials valid until 2026-10-31 07:19 UTC | ✅ |

---

## 3. Observations & Carry-Forward

| ID | Sev | Observation | Recommendation / Next Action |
|---|---|---|---|
| **PV3-6** | Info | **Defense-in-Depth for Tenant Isolation:** Restoring `*:*` in `tenant-workloads.spec.namespaceResourceWhitelist` preserves full tree visibility in Argo CD, while `argocd-tenant-deployer` strictly enforces kind restrictions at the Kubernetes API level. | Document this architectural separation of concerns in the platform architecture docs. |
| **PV3-7** | Low | **Kube-Router NetworkPolicy Programming Window (D-19):** Kube-router programs iptables/ipset rules a few seconds after pod initialization, creating a momentary window of open egress for short-lived pods. | Inherent to CNI / kube-router engine. For highly sensitive pods, init containers or link-down bootstrapping can close this if required. |
| **PV3-8** | Medium | **Input Validation Strategy (D-18):** Kro 0.9.4 cannot update existing CRDs with additional schema validations without breaking live instances. | Implement a Kubernetes `ValidatingAdmissionPolicy` and `ValidatingAdmissionPolicyBinding` targeting `queuebackedservices.kro.run` in Phase 3 Track D or as a platform addon. |

---

## 4. Phase 3 Cumulative Status

| Track | Scope | Status |
|---|---|:-:|
| **Track 0** | Steps 0.1, 0.2 (Token rotation & expiry check) | ✅ **Closed** (Validation #01) |
| **Track 0** | Steps 0.3, 0.4 (GitHub UI branch protection & orphan cleanup) | ⏳ Pending Owner UI Action |
| **Track A** | Steps A.1, A.2, A.3 (Localhost binding, Argo CD RBAC, Headlamp) | ✅ **Closed / Accepted Residual** (Validation #01) |
| **Track B** | Steps B.1, B.2, B.3, B.5, B.6 (GitOps platform layer) | ✅ **Closed** (Validation #02) |
| **Track B** | Steps B.4, B.7 (Argo CD self-management, Rebuild test) | ⏳ Deferred to end of Phase 3 |
| **Track C** | Steps C.1–C.4 (Tenant kinds, Impersonation, Kro RBAC, NetPol default-deny) | ✅ **Closed** (Validation #03) |
| **Track D** | Steps D.1 (hook), D.4, D.5 (externalRef) | ✅ **Delivered in Blueprint v1.3.0** |
| **Track D** | Steps D.1 (app v1.4.0), D.2 (moto restart test), D.3 (CARM), D.5 (input validation) | ⏳ Scheduled for Next Run |

---

## 5. Next Actions

Track C and the blueprint v1.3.0 foundation are validated. The control plane is ready to proceed with **Track D (Cloud Isolation & Resilience)**:
1. **Step D.1 (Application v1.4.0):** Update `orders-processor` to take AWS credentials from environment, implement lazy DynamoDB table creation, release container image, and pin by digest.
2. **Step D.2 (Moto Restart Test):** Planned maintenance window testing ACK queue reconciliation and worker recovery after container recreation.
3. **Step D.3 (CARM Multi-Account Migration):**
   - Canary test `carm-canary` on nonprod.
   - Provision per-account worker secrets.
   - Migrate dev (`111111111111`), test (`111111111111`), and prod (`222222222222`).
4. **Step D.5 Follow-up:** Implement `ValidatingAdmissionPolicy` for `QueueBackedService` schema enforcement.
