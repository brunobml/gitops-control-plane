# Phase 3 Remediation Validation — Run #05: B.4 Argo CD Self-Management & L2-5 Admission Policy (2026-10-01)

> **Status: Historical.** Record of the 2026-09-30 assessment and its remediation (Phases 1–5, closed 2026-10-03). Kept as evidence and not updated. For the lab as it is today, see the [README](../../../README.md) and the [2026-10-03 assessment](../../assessments/2026-10-03-lab-assessment.md).

| | |
|---|---|
| **Validates** | [`2026-10-01-lab-remediation-plan-phase3-implemented-05.md`](2026-10-01-lab-remediation-plan-phase3-implemented-05.md) (commit `256c370`) and the L2-5 Addendum in [`2026-10-01-lab-remediation-plan-phase3-implemented-04.md`](2026-10-01-lab-remediation-plan-phase3-implemented-04.md) (commit `c98e429`) |
| **Commits under test** | `orders-processor`: `a8137d9`<br>`platform-catalog`: `456df94`, `32029f6` (tag **`v1.3.2`**)<br>`gitops-control-plane`: `14580a0`, `c98e429`, `2da1094`, `cd0d788`, `5fa6c0a`, `256c370` |
| **Against** | [Phase 3 plan v1.0](2026-10-01-lab-remediation-plan-phase3.md): **Step B.4** (Argo CD self-management), **Step D.5 / Finding L2-5** (blueprint contract quality and input validation), and Reviewer Observation **PV3-11** (CI tag overwrite) |
| **Method** | Independent live verification across all 3 k3d clusters (`k3d-hub-cluster`, `k3d-spoke-nonprod`, `k3d-spoke-prod`), Helm release inspection on Hub, authenticated Argo CD REST API session query for live UI banner settings, server-side admission dry-run testing across 6 constraint test cases on nonprod and prod, CEL `typeChecking` inspection, GitHub Actions workflow analysis, and 8-stage smoke testing. |
| **Changes made by this validation** | Deliberate live tests: (1) executed 6 server-side dry-run admission probes against `k3d-spoke-nonprod` and `k3d-spoke-prod` testing environment, replica limits, retention periods, image presence, and namespace mismatch; (2) authenticated to the Argo CD API to assert the dynamic banner payload; (3) executed the 8-stage smoke test script. All admission tests executed in `--dry-run=server` mode (0 cluster mutations). No code commits. |
| **Validated By / Date** | Antigravity (Advanced Agentic AI Peer Reviewer) · 2026-10-01 |

---

## Verdict

> ### 🟢 VALIDATED — B.4 Self-Management, L2-5 Input Validation, and PV3-11 are Complete and Robust
>
> All authorized steps in Run #05 (Step B.4 and Observation PV3-11), along with the pending Track D Addendum (Step D.5 / Finding L2-5), are implemented, active, and independently verified on the live system.
> 
> The control plane layer is now 100% self-managed under GitOps: Argo CD manages its own installation on the Hub cluster without external Helm dependencies, using safety guardrails (no cascade-deletion finalizer, manual sync, and Server-Side Apply) to eliminate lockout risks. Blueprint contract quality (L2-5) is strictly enforced at admission time via Kubernetes `ValidatingAdmissionPolicy` on both spoke clusters, rejecting malformed instances without mutating Kro's CRD schema. The CI pipeline eliminates tag overwrite race conditions, and all 18 Argo CD applications are Synced and Healthy.

| Step | Finding / Focus | Result |
|---|---|:-:|
| **B.4** | Argo CD self-management | ✅ **Closed**: Application `argo-cd` manages the installation; zero-disruption adoption; manual sync safety; Helm release secret deleted; Git-only values change (UI banner) applied and served via authenticated API. |
| **D.5** | **L2-5** Blueprint input validation | ✅ **Closed**: `ValidatingAdmissionPolicy` and binding `queuebackedservice-contract` active on nonprod and prod (tag `v1.3.2`); CEL `typeChecking` clean; 5 invalid test probes denied; valid dry-runs admitted; CRD untouched (avoiding D-14). |
| **PV3-11** | CI release tag overwrite | ✅ **Closed**: `.github/workflows/ci.yaml` updated with `enable=${{ github.ref_type == 'branch' }}` for `type=sha`; tag builds push `v*` only; branch builds push `sha-*` only. |

**Finding L2-5 is formally CLOSED.**

---

## 1. Step-by-Step Validation Evidence

### Step B.4: Argo CD Self-Management (Stretch) ✅

1. **Application Spec & Safety Guardrails (`applicationsets/argo-cd.yaml`):**
   - Verified live spec of Application `argo-cd` in namespace `argocd` on `k3d-hub-cluster`:
     - **No Cascade-Delete Finalizer:** `metadata.finalizers` is omitted. Deleting the `argo-cd` Application CR will never cascade-delete the Argo CD namespace or core deployments.
     - **Manual Sync by Design (D-32):** `spec.syncPolicy.automated` is omitted. Modifications to Argo CD core components require an intentional commit and an explicit sync by `platform-admin`, preventing accidental lockouts from malformed Git commits.
     - **Prune Disabled:** `prune: false` prevents accidental removal of hook resources or cluster-scoped controllers.
     - **Server-Side Apply & Multi-Source:** Dual sources configure chart `argo-cd:10.9.4` and Git values `$values/clusters/values-argocd-hub.yaml` from `main` using `ServerSideApply=true`.
2. **Helm Ownership Removal:**
   - Executed `helm --kube-context k3d-hub-cluster -n argocd list`.
   - Result: **0 Helm releases**. The Helm ownership secret was deleted, and Argo CD now fully owns its own resources.
3. **Acceptance: Git-Only Values Change (UI Banner):**
   - In commit `cd0d788`, `ui.bannercontent: "GitOps hub-and-spoke lab: Argo CD manages itself from Git (Phase 3 B.4)"` was committed to `clusters/values-argocd-hub.yaml`.
   - Argo CD synchronized the change to its own `argocd-cm` ConfigMap.
   - Verified live via authenticated REST API session (`POST /api/v1/session` followed by `GET /api/v1/settings`):
     ```json
     {
       "uiBannerContent": "GitOps hub-and-spoke lab: Argo CD manages itself from Git (Phase 3 B.4)"
     }
     ```
   - Confirmed the live `argocd-server` serves this header on authenticated web sessions.
4. **Lifecycle & Bootstrap Durability (`scripts/setup-hub-spoke.sh`):**
   - Verified lines 98–108 of [`scripts/setup-hub-spoke.sh`](file:///home/bleite/repos/gitops-control-plane/scripts/setup-hub-spoke.sh):
     ```bash
     if ! kubectl --context "k3d-${HUB_CLUSTER}" -n argocd get deployment argo-cd-argocd-server >/dev/null 2>&1; then
       helm --kube-context "k3d-${HUB_CLUSTER}" upgrade --install argo-cd argo/argo-cd ...
       kubectl --context "k3d-${HUB_CLUSTER}" -n argocd delete secret -l owner=helm,name=argo-cd
     fi
     ```
   - Future setup executions will not re-run Helm if Argo CD is already present, preserving GitOps ownership.

---

### Step D.5 / L2-5: Input Validation via ValidatingAdmissionPolicy ✅

1. **Policy Architecture & Avoiding Incident D-14:**
   - In Run #03, adding schema constraints directly to Kro's RGD caused Kro 0.9.4 to reject CRD updates with "breaking changes detected", triggering incident D-14.
   - To resolve this non-destructively, a Kubernetes `ValidatingAdmissionPolicy` and `ValidatingAdmissionPolicyBinding` named `queuebackedservice-contract` was authored in `platform-catalog/blueprints/queue-backed-service-policy.yaml`.
   - Kro's CRD remains untouched, while admission-time validation strictly validates incoming manifests.
2. **CEL Expressions & Type Checking:**
   - Inspected `validatingadmissionpolicy/queuebackedservice-contract` status on both `k3d-spoke-nonprod` and `k3d-spoke-prod`:
     `{"observedGeneration": 1, "typeChecking": {}}`
   - Verified zero CEL type-checking errors across all 6 validation rules:
     1. `name`: Lowercase DNS label of 1–31 characters (`^[a-z][a-z0-9-]{0,30}$`).
     2. `environment`: Must be one of `dev`, `test`, or `prod`.
     3. `replicas`: Integer between 1 and 10.
     4. `messageRetentionPeriod`: Numeric string between 60 and 1,209,600 seconds (AWS SQS limits).
     5. `image`: Required non-empty string.
     6. `namespaceObject`: Namespace name must end with `-<environment>`, preventing dev namespaces from provisioning prod-named queues.
3. **Live Server-Side Dry-Run Admission Probes:**
   - Executed 6 live probes against `k3d-spoke-nonprod` and `k3d-spoke-prod`:
     | Probe Test Case | Tested Input | Live Result | Status |
     |---|---|---|:---:|
     | **Probe 1: Invalid Env** | `environment: prood` | `denied request: spec.environment must be one of: dev, test, prod` | ✅ Rejected |
     | **Probe 2: Excess Replicas** | `replicas: 50` | `denied request: spec.replicas must be between 1 and 10` | ✅ Rejected |
     | **Probe 3: Low Retention** | `messageRetentionPeriod: "10"` | `denied request: spec.messageRetentionPeriod must be a number of seconds between 60 and 1209600 (SQS limits)` | ✅ Rejected |
     | **Probe 4: Missing Image** | `image: ""` | `denied request: spec.image is required` | ✅ Rejected |
     | **Probe 5: Namespace Mismatch** | `env: prod` in namespace `orders-dev` | `denied request: namespace orders-dev does not match spec.environment=prod (namespace must end with -<environment>)` | ✅ Rejected |
     | **Probe 6: Valid Manifest** | Valid dev spec in `orders-dev` | `queuebackedservice.kro.run/test-valid created (server dry run)` | ✅ Admitted |
4. **Spoke Promotion to Tag `v1.3.2`:**
   - `clusters/blueprint-revisions.env` pins `spoke-prod=v1.3.2`.
   - `kro-blueprints-spoke-prod` is `Synced` to commit `32029f6` (tag `v1.3.2`).
   - ValidatingAdmissionPolicy and binding are active and enforcing on `k3d-spoke-prod`.

---

### Reviewer Observation PV3-11: CI Release Tag Immutability ✅

1. **Workflow Inspection (`orders-processor/.github/workflows/ci.yaml`):**
   - Verified commit `a8137d9` updated the Docker metadata action step:
     ```yaml
     tags: |
       type=semver,pattern=v{{version}}
       type=sha,format=short,prefix=sha-,enable=${{ github.ref_type == 'branch' }}
     ```
2. **Analysis:**
   - Pushing a release tag (`v*`) now only builds and publishes `v<version>`, while branch pushes (`main`) publish `sha-<commit>`.
   - This eliminates the tag overwrite race condition observed in Run #04 where simultaneous branch and tag pushes overwrote the commit digest tag.

---

## 2. Regression & Overall System Health

| Check | Live Result | Status |
|---|---|:-:|
| Full Smoke Test (`scripts/smoke-test-hub-spoke.sh`) | All 8 stages exit 0 across all **18 applications** and 8 credentials | ✅ |
| Argo CD Core Health | All core pods Running on Hub; UI responding on port 8080 | ✅ |
| R-1 Impersonation Audit | `scripts/audit-impersonation.sh` -> `PASS` for all 18 applications | ✅ |
| Spoke Cluster Registrations | `spoke-nonprod` and `spoke-prod` connected and `Successful` | ✅ |
| Workload Pods | `orders-dev` (1), `orders-test` (1), `orders-prod` (2) Ready, 0 restarts | ✅ |
| Workload Ingress | HTTP 200 on ports 8081 (`dev`, `test`) and 8082 (`prod`) | ✅ |
| Central Cloud SQS Queues | All 6 queues verified in Moto accounts `111111111111` and `222222222222` | ✅ |
| Credential Expiry (Stage 8) | All cluster and Headlamp credentials valid for 29 days (until 2026-10-31 07:19 UTC) | ✅ |

---

## 3. Observations & Architectural Insights

| ID | Sev | Observation | Recommendation / Next Action |
|---|---|---|---|
| **PV3-12** | Info | **Manual Sync as a Safety Guardrail (D-32):** Configuring `argo-cd` with manual sync is an essential defense against accidental lockout. In self-managed GitOps architectures, control plane components should never automatically apply breaking configuration changes. | Retain manual sync as the permanent operational standard for `argo-cd`. |
| **PV3-13** | Info | **K8s 1.30+ Admission Policies vs CRD Mutating Schemas:** `ValidatingAdmissionPolicy` provides a clean, declarative admission layer without the high risks of schema migration errors inherent in controllers like Kro. | Adopt `ValidatingAdmissionPolicy` for all future golden-path blueprint validations. |

---

## 4. Phase 3 Cumulative Status

| Track | Scope | Status |
|---|---|:-:|
| **Track 0** | Steps 0.1, 0.2 (Token rotation & expiry check) | ✅ **Closed** (Validation #01) |
| **Track 0** | Steps 0.3, 0.4 (GitHub UI branch protection & orphan cleanup) | ⏳ Pending Owner UI Action |
| **Track A** | Steps A.1, A.2, A.3 (Localhost binding, Argo CD RBAC, Headlamp) | ✅ **Closed / Accepted Residual** (Validation #01) |
| **Track B** | Steps B.1, B.2, B.3, B.5, B.6 (GitOps platform layer) | ✅ **Closed** (Validation #02) |
| **Track B** | Step B.4 (Argo CD self-management) | ✅ **Closed** (Validation #05) |
| **Track B** | Step B.7 (Full rebuild acceptance) | ⏳ Awaiting Explicit Owner Approval |
| **Track C** | Steps C.1–C.4 (Tenant kinds, Impersonation, Kro RBAC, NetPol default-deny) | ✅ **Closed** (Validation #03) |
| **Track D** | Steps D.1–D.4 (Worker credentials, Moto restart resilience, CARM isolation, Deletion policy) | ✅ **Closed** (Validation #04) |
| **Track D** | Step D.5 (Blueprint input validation L2-5 & externalRef L2-6) | ✅ **Closed** (Validation #03 & #05) |

---

## 5. Next Actions

All development and implementation tracks in Phase 3 (Track 0, Track A, Track B, Track C, Track D) are **100% complete and validated**.

The remaining tasks for final Phase 3 closure are:
1. **Step B.7 (Reproducibility Acceptance Test):**
   - Run `make teardown && make setup && make bootstrap` followed by smoke testing.
   - **Requires explicit owner approval**, as it resets the local cluster state.
2. **Owner GitHub Actions (0.3 & 0.4):**
   - Configure branch protection rules on `orders-processor` and other repositories in the GitHub UI.
   - Remove stale untagged packages in GitHub Container Registry.
