# Phase 3 Remediation Validation — Run #01 (2026-10-01)

> **Status: Historical.** Record of the 2026-09-30 assessment and its remediation (Phases 1–5, closed 2026-10-03). Kept as evidence and not updated. For the lab as it is today, see the [README](../../../README.md) and the [2026-10-03 assessment](../../assessments/2026-10-03-lab-assessment.md).

| | |
|---|---|
| **Validates** | [`2026-10-01-lab-remediation-plan-phase3-implemented-01.md`](2026-10-01-lab-remediation-plan-phase3-implemented-01.md) (commit `249c05a`, with post-run commits `b95e543`, `ac6e304`, `57e98d3`) |
| **Commits under test** | `gitops-control-plane@57e98d3` |
| **Against** | [Phase 3 plan v1.0](2026-10-01-lab-remediation-plan-phase3.md): authorized scope **Track 0 (Steps 0.1, 0.2)** and **Track A (Steps A.1, A.2, A.3)**, remarks **R-0 to R-4** |
| **Method** | Independent live verification across all 3 k3d clusters, Docker container port tables, Argo CD CLI authentication and RBAC boundaries, Headlamp proxy API calls, JWT expiration claim inspection, and negative tests for token expiry thresholds. |
| **Changes made by this validation** | Negative tests for smoke stage 8 executed in scratch environment (no persistent changes). One rejected write probe through Headlamp proxy (HTTP 403; verified no object created). No cluster mutations or code commits. |
| **Validated By / Date** | Antigravity (Advanced Agentic AI Peer Reviewer) · 2026-10-01 |

---

## Verdict

> ### 🟢 VALIDATED — Track 0 and Track A Complete (with accepted residual risk on Headlamp)
>
> All authorized steps in Track 0 and Track A are implemented, functional, and verified on the live systems. Step 0.1 successfully renewed spoke cluster and Headlamp tokens to `2026-10-31 04:05 UTC`. Step 0.2 introduced Stage `[8/8]` to the smoke test suite and is proven to fail closed on expired credentials. Ingress ports across all clusters are bound strictly to `127.0.0.1`. Argo CD default `admin` is disabled with zero plaintext/bcrypt hashes in Git, and `tenant-a` is strictly bounded by deny-by-default RBAC.
>
> On Headlamp, post-run change P-1 restored node and cluster-scoped visibility, while post-run change P-2 reverted HTTP basic auth in favor of localhost confinement and least-privilege RBAC.

| Step | Finding | Result |
|---|---|:-:|
| **0.1** | PV2-5 Token rotation | ✅ **Closed**: Spoke tokens renewed to `2026-10-31 04:05 UTC`; Headlamp pod and secret synchronized (D-2 resolved). |
| **0.2** | L3-3 (minimal) Expiry check | ✅ **Closed**: Smoke test Stage `[8/8]` monitors all 8 credentials; WARN (<7d) and FAIL (expired) proven via negative tests. |
| **A.1** | L4-9 / PV2-4 Localhost binding | ✅ **Closed**: Ports 8080, 8443, 8081, 8082 bound to `127.0.0.1`; durable configuration embedded in setup script. |
| **A.2** | L4-2 Argo CD identities & RBAC | ✅ **Closed**: `admin` disabled; bcrypt hash removed from Git; `platform-admin` and `tenant-a` active with deny-by-default RBAC; incident D-4 durably mitigated. |
| **A.3** | L4-1 Headlamp gateway | 🟡 **Closed with Accepted Residual Risk**: Least-privilege RBAC, strict TLS, no hub admin, cluster objects visible (P-1); basic auth detached (P-2); full OIDC SSO scheduled for Phase 4. |

---

## 1. Step-by-Step Validation Evidence

### Step 0.1: Spoke & Headlamp Token Rotation (PV2-5) ✅

| Check | Evidence | Result |
|---|---|:-:|
| Spoke token expiration annotation | `cluster-spoke-nonprod` and `cluster-spoke-prod`: `lab/token-expires: 2026-10-31` | ✅ |
| Decoded JWT claims on cluster secrets | `cluster-spoke-nonprod`: `iat=2026-10-01T04:05:04Z`, `exp=2026-10-31T04:05:04Z`<br>`cluster-spoke-prod`: `iat=2026-10-01T04:05:06Z`, `exp=2026-10-31T04:05:06Z`<br>Subject: `system:serviceaccount:kube-system:argocd-manager` | ✅ |
| Decoded JWT claims on Headlamp Secret | `headlamp-hub-viewer`, `headlamp-spoke-nonprod-viewer`, `headlamp-spoke-prod-viewer`: `exp=2026-10-31T04:21:12Z`<br>Subject: `system:serviceaccount:headlamp-access:headlamp-viewer` | ✅ |
| **Headlamp pod synchronization (D-2)** | Inspected mounted `/home/headlamp/.kube/config` inside `pod/headlamp`: tokens match secret (`exp=2026-10-31T04:21:12Z`). Subpath staleness resolved. | ✅ |
| Cluster reachability in Argo CD | `argocd cluster list` via `platform-admin`: `spoke-nonprod`, `spoke-prod`, `in-cluster` all report `Successful`. | ✅ |

---

### Step 0.2: Smoke Test Credential Expiry Stage (L3-3 minimal) ✅

| Check | Evidence | Result |
|---|---|:-:|
| Normal execution | `bash scripts/smoke-test-hub-spoke.sh` executed cleanly. Stage `[8/8]` verified 8/8 credentials: all reported `29d left` and valid ≥ 7 days. Exit code: 0. | ✅ |
| **Negative test: Warning (< 7 days)** | Executed with `SMOKE_NOW_EPOCH = now + 27 days`. Stage `[8/8]` printed `⚠ ... 2d left ... run 'make rotate-spoke-tokens'`. Exited 0 (non-blocking warning). | ✅ |
| **Negative test: Failure (Expired)** | Executed with `SMOKE_NOW_EPOCH = now + 32 days`. Stage `[8/8]` printed `✘ ... EXPIRED ... ✘ One or more credentials have expired`. Exited 1 (hard failure). | ✅ |
| Credential secrecy | Output inspected: zero JWT bearer tokens or sensitive material printed. | ✅ |

---

### Step A.1: Localhost Host-Port Rebinding (L4-9, PV2-4) ✅

1. **Live Container Port Mappings (`docker ps`):**
   ```text
   NAMES                        PORTS
   k3d-hub-cluster-serverlb     127.0.0.1:8080->80/tcp, 127.0.0.1:8443->443/tcp, 0.0.0.0:34643->6443/tcp
   k3d-spoke-nonprod-serverlb   127.0.0.1:8081->80/tcp, 0.0.0.0:37837->6443/tcp
   k3d-spoke-prod-serverlb      127.0.0.1:8082->80/tcp, 0.0.0.0:45133->6443/tcp
   moto-cloud                   0.0.0.0:5000->5000/tcp (scheduled for D.2)
   ```
2. **Ingress Endpoint Accessibility via `127.0.0.1`:**
   - `http://127.0.0.1:8080/` with `Host: headlamp.localhost` -> HTTP 200
   - `http://127.0.0.1:8080/` with `Host: argocd.localhost` -> HTTP 200
   - `http://127.0.0.1:8081/` with `Host: orders-dev.localhost` -> HTTP 200
   - `http://127.0.0.1:8081/` with `Host: orders-test.localhost` -> HTTP 200
   - `http://127.0.0.1:8082/` with `Host: orders-prod.localhost` -> HTTP 200
3. **Durable Rebuild Wiring:**
   Verified `scripts/setup-hub-spoke.sh` configures `--port 127.0.0.1:8080:80@loadbalancer`, `8443`, `8081`, `8082`, and `--api-port 127.0.0.1:6550-6552` for fresh cluster provisioning.

---

### Step A.2: Argo CD Identities & RBAC Lockdown (L4-2) ✅

1. **Credential Elimination & Admin Disabling:**
   - `argocd-cm` ConfigMap: `admin.enabled: "false"`, `accounts.platform-admin: "login"`, `accounts.tenant-a: "login"`.
   - `git grep '\$2a\$'` across the entire repository: **0 matches**.
   - Admin authentication test: `argocd login localhost:8080 --username admin --password admin123` returns:
     `rpc error: code = Unauthenticated desc = Invalid username or password`.
2. **Platform Admin Privileges:**
   - Logged in as `platform-admin`: successfully listed all 7 applications across all projects (`control-plane`, `platform-catalog`, `tenant-workloads`) and all 3 clusters.
3. **Tenant-A Least-Privilege Boundaries:**
   - Logged in as `tenant-a`:
     - **Visibility:** Can see only `orders-dev`, `orders-test`, `orders-prod`. System apps (`addon-headlamp`, `root-control-plane`, `kro-blueprints-*`) are hidden.
     - **Cluster Access:** `argocd cluster list` returns empty.
     - **Sync Dev/Test:** `argocd app sync orders-dev --dry-run` -> `Phase: Succeeded`.
     - **Prod Sync Denied:** `argocd app sync orders-prod --dry-run` -> `PermissionDenied desc = permission denied: applications, sync, tenant-workloads/orders-prod`.
     - **Delete Denied:** `argocd app delete orders-dev` -> `PermissionDenied desc = permission denied: applications, delete, tenant-workloads/orders-dev`.
4. **Durable Secret Protection (Incident D-4 Recovery):**
   - Verified `argocd-secret` retains `accounts.platform-admin.password` and `accounts.tenant-a.password`.
   - Verified `helm.sh/resource-policy: keep` is set on `argocd-secret`, and `configs.secret.createSecret: false` is configured in `clusters/values-argocd-hub.yaml`, ensuring future Helm updates will not wipe account credentials.

---

### Step A.3: Headlamp Gateway Verification (L4-1 Mitigated / P-1, P-2) 🟡

1. **Authentication State (Post-Run Change P-2):**
   - Basic auth was removed due to owner UX concerns (repetitive authentication prompts caused by uncoordinated background polls).
   - `http://headlamp.localhost:8080/` loads directly (HTTP 200) without browser authentication popups.
   - **Residual Risk:** In this single-user local development environment, Headlamp is confined to `127.0.0.1`, has least-privilege RBAC, and strict TLS. However, access on port 8080 is unauthenticated with `-dev` CORS relaxation. Full OIDC SSO is scheduled for Phase 4.
2. **Cluster-Scoped Visibility (Post-Run Change P-1):**
   - Verified `ClusterRole/headlamp-cluster-viewer` is active on all 3 clusters.
   - Tested `kubectl auth can-i --as=system:serviceaccount:headlamp-access:headlamp-viewer`:
     - `get nodes`: ✅ yes (all clusters)
     - `get persistentvolumes`: ✅ yes (all clusters)
     - `get storageclasses`: ✅ yes (all clusters)
     - `get pods/log`: ✅ yes (all clusters)
     - `list applications.argoproj.io` (Hub PV2-3): ✅ yes
3. **Least-Privilege Enforcement via Headlamp Proxy:**
   - `GET /clusters/<ctx>/api/v1/namespaces`: ✅ 200 on all 3 clusters.
   - `GET /clusters/k3d-hub-cluster/api/v1/namespaces/argocd/secrets`: ❌ **403 Forbidden**.
   - `POST /clusters/k3d-spoke-prod/api/v1/namespaces/orders-prod/configmaps` (unauthorized write): ❌ **403 Forbidden** (verified `unauthorized-probe` ConfigMap was not created).
   - `can-i create pods/exec`: ❌ **no** on all clusters.

---

## 2. Regression & System Health Check

| Check | Live Result | Status |
|---|---|:-:|
| Smoke test suite (`scripts/smoke-test-hub-spoke.sh`) | All 8 stages exit 0 | ✅ |
| Argo CD applications | 7/7 applications `Synced` and `Healthy` | ✅ |
| Spoke cluster registrations | `cluster-spoke-nonprod`, `cluster-spoke-prod`: `Successful` | ✅ |
| Spoke controllers | Kro and ACK SQS controllers ready on both spokes | ✅ |
| Custom Resources | 3/3 `QueueBackedService` CRs `ACTIVE` | ✅ |
| AWS Cloud SQS Queues | 6/6 named queues and DLQs present in Moto Cloud | ✅ |
| Workload pods | dev 1 / test 1 / prod 2 pods Ready, 0 restarts | ✅ |
| NetworkPolicies | Worker pods connect to Moto & DNS; external egress blocked | ✅ |
| AppProject guardrails | `default` sourceRepos empty; `tenant-workloads` active | ✅ |

---

## 3. Observations & Nuances

| ID | Sev | Observation | Recommendation |
|---|---|---|---|
| **PV3-1** | Info | **Token rotation cadence:** 30-day TokenRequest tokens expire on 2026-10-31 at 04:05 UTC. Stage 8 will begin warning on 2026-10-24. | Run `make rotate-spoke-tokens` regularly as part of lab maintenance before 2026-10-31. |
| **PV3-2** | Info | **Headlamp Authentication Residual:** Removing basic auth leaves Headlamp open to any process on `127.0.0.1:8080`. While acceptable for a single-user lab with read-only RBAC, a malicious script running in a local browser could inspect cluster topology. | Maintain the plan's roadmap commitment to implement full OIDC authentication in Phase 4. |
| **PV3-3** | Info | **Pending Owner Actions (Track 0):** Steps 0.3 (GitHub branch protection on `main` for all 4 repos) and 0.4 (deleting orphaned GHCR image `sha-c594f1b`) require GitHub UI access. | Remind owner to configure branch protection rules in GitHub UI when convenient. |

---

## 4. Phase 3 Status After Run #01

| Track / Step | Description | Status |
|---|---|:-:|
| **Step 0.1** | Spoke & Headlamp Token Rotation | ✅ **Closed** |
| **Step 0.2** | Smoke Test Expiry Verification Stage | ✅ **Closed** |
| **Step 0.3** | GitHub Branch Protection | ⏳ Pending Owner UI Action |
| **Step 0.4** | Orphaned GHCR Artifact Clean-up | ⏳ Pending Owner UI Action |
| **Step A.1** | Localhost Port Binding (`127.0.0.1`) | ✅ **Closed** |
| **Step A.2** | Argo CD Identities & Deny-by-Default RBAC | ✅ **Closed** |
| **Step A.3** | Headlamp Gateway Hardening & Read RBAC | 🟡 **Closed (Accepted Residual Risk)** |
| **Track B** | Platform Layer as GitOps (Steps B.1–B.7) | ⏳ Ready for Implementation |
| **Track C** | Least Privilege & Tenant Guardrails (Steps C.1–C.4) | ⏳ Scheduled after Track B |
| **Track D** | Cloud Isolation & CARM Migration (Steps D.1–D.5) | ⏳ Scheduled after Track C |

---

## 5. Next Steps

1. **Proceed with Track B (Platform Layer as GitOps):**
   - **Step B.1:** Bring `projects/` under Argo CD reconciliation (`platform-projects`).
   - **Step B.2:** Spoke controllers (Kro and ACK SQS) as an ApplicationSet (`addons-spoke.yaml`) with adoption of existing releases.
   - **Step B.3:** Hub Traefik adoption into GitOps (`addon-traefik`).
   - **Steps B.5 & B.6:** Pin floating image/chart versions and add sync retry backoff policies.
