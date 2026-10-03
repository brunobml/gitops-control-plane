# Lab Remediation Implementation Report — 2026-09-30 (Run #02)

| Metadata | Details |
|---|---|
| **Document** | `docs/remediation/2026-09-30-lab-remediation-plan-implemented-02.md` |
| **Plan Reference** | [`2026-09-30-lab-remediation-plan.md`](2026-09-30-lab-remediation-plan.md) (v3.0, commit `9571f2f`) |
| **Review Reference** | [`2026-09-30-lab-remediation-plan.md#review--approval-sign-off`](2026-09-30-lab-remediation-plan.md#review--approval-sign-off) (Green Light Approval with C1–C3) |
| **Validation Reference**| [`2026-09-30-lab-remediation-plan-validation-01.md`](2026-09-30-lab-remediation-plan-validation-01.md) (Validated with Observations V-1 to V-9) |
| **Supercedes** | [`2026-09-30-lab-remediation-plan-implemented-01.md`](2026-09-30-lab-remediation-plan-implemented-01.md) |
| **Assessment Target** | [`../assessments/2026-09-30-lab-assessment.md`](../../assessments/2026-09-30-lab-assessment.md) |
| **Execution Date** | 2026-09-30 |
| **Execution Status** | ✅ **FULLY VALIDATED & REMEDIATED — ALL OBSERVATIONS V-1 TO V-9 RESOLVED** |

---

## 1. Executive Summary

This report serves as the authoritative audit record for the remediation of the findings in the 2026-09-30 Multi-Cluster GitOps Control Plane Lab Assessment. It builds on the verified runtime implementation of Run #01 and incorporates the fixes for all observations (**V-1 through V-9**) identified in `2026-09-30-lab-remediation-plan-validation-01.md`.

### Key Outcomes:
1. **Security & Credential Hardening:**
   - All legacy permanent token Secrets (`kubernetes.io/service-account-token`) have been eradicated across all namespaces in all three clusters (Hub, Non-Prod Spoke, Prod Spoke), including the leftover `headlamp/headlamp-admin-token` (V-5).
   - Plaintext credentials in `kubectl.kubernetes.io/last-applied-configuration` annotations were stripped before server-side apply.
   - Spoke cluster authentication is strictly bounded to 30-day tokens via the Kubernetes `TokenRequest` API (`--duration=720h`).
2. **Promotion Gate Architecture:**
   - Kro blueprint promotion is decoupled from Git `main` via Git tags (`v1.0.0` baseline, `v1.1.0` hardened).
   - Single source of truth is enforced via `clusters/blueprint-revisions.env` with a fail-closed guard (C2).
   - Dedicated promotion script (`scripts/promote-blueprints.sh`) and Makefile target (`make promote-blueprints`) allow advancing spoke blueprints without issuing unnecessary new credentials (V-4).
3. **Workload Hardening & Reliability:**
   - Dedicated ServiceAccounts (`orders-{dev,test,prod}-sa`) with `automountServiceAccountToken: false` and DAG edges.
   - Pod Security Standards Restricted profile satisfied: `seccompProfile.type: RuntimeDefault`, `readOnlyRootFilesystem: true`, capabilities dropped (`ALL`), `/tmp` `emptyDir` mount.
   - Conditional PodDisruptionBudget active only in production (`orders-prod-pdb`, `minAvailable: 1`) via Kro CEL `includeWhen: [ ${schema.spec.replicas > 1} ]`.
4. **Documentation & Traceability Integrity:**
   - Audit matrix corrected to strictly map to original assessment findings (V-1).
   - Architecture diagrams, tutorial manifests, and replica counts synchronized with live deployments (V-2).

---

## 2. Assessment Traceability Matrix (V-1 Corrected)

| Finding ID | Assessment Severity | Assessment Description | Remediation Implemented in Run #01 & #02 | Final Status |
|---|---|---|---|:---:|
| **B1** | **Blocker** *(Review)* | Plaintext bearer tokens retained in `last-applied-configuration` Secret annotations | Stripped annotations prior to server-side apply; verified absent on all cluster Secrets | ✅ Closed |
| **B2** | **Blocker** *(Review)* | Leaked spoke permanent token Secrets stay valid indefinitely | Removed Secret manifest; deleted legacy Secrets; migrated to 30-day TokenRequest | ✅ Closed |
| **L1-2** | Low | Orphaned `messageprocessors.kro.run` CRD remains installed on spokes | Backed up CRD to `/tmp/mp-crd-*.yaml`; confirmed 0 CRs; deleted CRD on both spokes | ✅ Closed |
| **L1-3** | Low | Stray Headlamp Docker containers running on host | Removed `elastic_kapitsa`, `affectionate_dubinsky`, `friendly_lalande`; deleted leftover `headlamp-admin-token` Secret and SA (V-5) | ✅ Closed |
| **L1-5** | Medium | Developer onboarding tutorial and README reference deprecated blueprints and outdated namespaces/replicas | Updated tutorial and README diagrams to `orders-*` namespaces, 2 prod replicas, and `orders-processor` structure (V-2) | ✅ Closed |
| **L1-6** | Low | Personal absolute paths (`/home/bleite`) hardcoded across repository files and Makefile | Anchored `ROOT_DIR` / `REPOS_DIR` in `Makefile` (V-8); converted documentation links to relative paths; 0 grep matches | ✅ Closed |
| **L2-7** | Low | Duplicate Helm repository Secret (`repo-ghcr-charts`) configured in Argo CD | Deleted unmanaged Secret; confirmed all 7 Argo CD applications have 0 error conditions | ✅ Closed |
| **L3-8** | Low | Imperatively applied infrastructure and controller installations | Code codified; formal GitOps controller packaging deferred by design to Recommendation 9 | ⏸ Deferred to Rec 9 |
| **L4-10** | Low | Indefinite-lifetime spoke cluster ServiceAccount token Secrets | Migrated to 30-day TokenRequest API; added `make rotate-spoke-tokens`; documented AWS EKS Access Entries target | ✅ Closed |
| **L4-11** | Low | Spoke tenant workloads lack dedicated ServiceAccount, PSS Restricted profile, and PDB | Hardened Kro RGD with dedicated SA, PSS `RuntimeDefault`/`readOnlyRootFS`, conditional PDB, and Git tag promotion gate | ✅ Closed |
| **L4-1** | **Critical** | Headlamp multi-cluster credential architecture | Hub SA decoupled via TokenRequest; spoke credential isolation remains open for High/Critical track (V-9) | ⚠️ Open (as planned) |

---

## 3. Detailed Implementation & Fix Log

### 3.1. Fixes Applied in Response to Validation Report (V-1 to V-9)

#### **V-1: Traceability Mappings Corrected**
The findings matrix in §2 has been reconstructed from the ground up against `2026-09-30-lab-assessment.md`. The promotion gate is correctly categorized as the delivery mechanism for **L4-11** (and down payment on L2-2/L3-6), rather than mislabeled as L1-2.

#### **V-2: Documentation Synchronization Completed**
- **`docs/developer-tutorial.md`**:
  - Line 32: Updated mermaid node from `Prod Worker Pods (5 replicas)` to `Prod Worker Pods (2 replicas)`.
  - Lines 55–68: Replaced stale `tenants/tenant-a/{dev,test,prod}` folder tree with the live `orders-processor` layout:
    ```text
    deploy/
    ├── values-dev.yaml      # Deployed to spoke-nonprod (namespace: orders-dev)
    ├── values-test.yaml     # Deployed to spoke-nonprod (namespace: orders-test)
    └── values-prod.yaml     # Deployed to spoke-prod (namespace: orders-prod)
    ```
- **`README.md`**:
  - Lines 29–36: Updated architecture diagram node labels from `tenant-a-dev (1)`, `tenant-a-test (2)`, `tenant-a-prod (5)` to `orders-dev (1)`, `orders-test (1)`, `orders-prod (2)`.
  - Confirmed 0 remaining matches for `tenant-a` in any active documentation.

#### **V-3: Strict Abort on Connectivity Verification Failure**
In `scripts/register-spokes.sh`, replaced the warning/fallback path with an explicit failure exit:
```bash
if [[ "$status" == "Successful" ]]; then
  echo "Argo CD cluster connectivity for ${spoke}: Successful"
else
  echo "❌ Error: Argo CD cluster connectivity check failed for ${spoke} (status: '${status}'). Aborting." >&2
  exit 1
fi
```
This guarantees that if Argo CD cannot reach a spoke with the newly minted credentials, the script halts immediately before any further actions are taken.

#### **V-4: Dedicated Promotion Script Without Credential Generation**
- Created `scripts/promote-blueprints.sh` and wired it into `make promote-blueprints`.
- Reads `clusters/blueprint-revisions.env` (with fail-closed guard C2) and updates the `blueprints-revision` annotation on `cluster-${spoke}` Secrets on the Hub.
- Prevents minting redundant 30-day `cluster-admin` bearer tokens during standard blueprint promotions.
- Corrected runbook wording: TokenRequest tokens expire naturally after 720 hours and cannot be revoked one-by-one; early revocation requires cycling the ServiceAccount.

#### **V-5: Residual Token Secret Deletion (`headlamp-admin-token`)**
- Deleted orphaned Secret `headlamp-admin-token` and ServiceAccount `headlamp-admin` in namespace `headlamp` on `k3d-hub-cluster`:
  ```bash
  kubectl --context k3d-hub-cluster -n headlamp delete secret headlamp-admin-token sa headlamp-admin
  ```
- Audited all namespaces across all three clusters: **Zero** `kubernetes.io/service-account-token` Secrets remain in the entire lab.

#### **V-6: RGD Container Runtime Note (W-2)**
The inclusion of `PYTHONDONTWRITEBYTECODE: "1"` in `blueprints/queue-backed-service-rgd.yaml` is recorded as a deliberate hygiene decision: while CPython silently ignores bytecode write failures on read-only filesystems and continues execution without error, setting this environment variable suppresses futile write attempts, eliminates unnecessary filesystem stats, and ensures deterministic container runtime behavior.

#### **V-7: Restored Controls in AWS Well-Architected Guide**
Restored the explicit rows for `Non-Root Container Execution` (`runAsNonRoot: true`, UID/GID 10001) and `Linux Capability Dropping` (`capabilities.drop: ["ALL"]`, `allowPrivilegeEscalation: false`) in the Security pillar of `docs/aws-well-architected-production-guide.md`.

#### **V-8: Makefile Path Anchoring**
All script targets in `Makefile` (`rotate-spoke-tokens`, `promote-blueprints`, `push`, `setup`, `test`, `teardown`, `bootstrap`) now strictly use `$(ROOT_DIR)/scripts/...` and `$(ROOT_DIR)/addons/...`, enabling execution from any directory.

#### **V-9: Accurate Headlamp Framing**
The Headlamp changes in Step 0 are framed as **Headlamp credential refresh**. Assessment **L4-1 (Critical)** remains open because Headlamp continues to share Argo CD's `argocd-manager` spoke credentials and runs as `cluster-admin` across all clusters. This will be addressed in the High/Critical remediation track.

### 3.3. Follow-up Hardening from Validation Run #02 (W-1 to W-4)

1. **W-1 (Fail-Closed Guard Diagnostics):**
   Appended `|| true` to the pipeline `bp_rev=$(grep -E "^${spoke}=" "$REVISIONS_FILE" | cut -d= -f2 || true)` in both `scripts/promote-blueprints.sh` and `scripts/register-spokes.sh`. This ensures that under `set -eo pipefail`, missing keys allow the execution to reach `: "${bp_rev:?no blueprints-revision for ...}"`, outputting the operator diagnostic message rather than terminating silently.
2. **W-2 (CPython Bytecode Rationale):**
   Corrected the technical rationale in §3.1 (V-6) to accurately reflect CPython's graceful handling of read-only directories.
3. **W-3 (ApplicationSet Routing Clarification):**
   Updated `docs/developer-tutorial.md` to explicitly state that routing decisions originate from the ApplicationSet manifests (`applicationsets/tenant-workloads-*.yaml`), which reference each values file.
4. **W-4 (Git Preflight Check in Promotion Script):**
   Added preflight validation to `scripts/promote-blueprints.sh` requiring `clusters/blueprint-revisions.env` to have no uncommitted changes (`git diff --quiet HEAD -- clusters/blueprint-revisions.env`) and all commits to be pushed upstream (`git merge-base --is-ancestor HEAD @{u}`) before applying annotations.

---

### 3.2. Summary of Original Step 0–8 Execution

- **Step 0 (Token Rotation & Secret Scrub):** Generated 30-day tokens via `kubectl create token argocd-manager --duration=720h`; extracted spoke CA from `kube-root-ca.crt` ConfigMap; stripped `last-applied-configuration` annotations; applied server-side; deleted legacy `argocd-manager-token` Secrets on spokes and `headlamp-token` on Hub.
- **Step 1 (Low-Risk Cleanup):** Backed up `messageprocessors.kro.run` CRD; confirmed 0 CRs; deleted CRD on both spokes; killed stray Docker containers.
- **Step 2 (Duplicate Secret Cleanup):** Deleted unmanaged `repo-ghcr-charts` Secret from `argocd` namespace; refreshed apps; confirmed 0 conditions.
- **Step 3 (Portability):** Anchored `ROOT_DIR` / `REPOS_DIR`; replaced absolute host paths with relative links; verified 0 grep matches.
- **Step 4 (Tutorial Sync):** Replaced `MessageProcessor` with `QueueBackedService`; updated namespace routing and replica counts.
- **Step 5 (Promotion Gate Wiring):** Tagged `platform-catalog@a8825b2` as `v1.0.0`; created `clusters/blueprint-revisions.env`; wired `applicationsets/kro-blueprints.yaml` with dynamic `targetRevision`.
- **Step 6 (Blueprint Hardening):** Added dedicated SA, PSS `RuntimeDefault`, `readOnlyRootFilesystem`, `/tmp` `emptyDir`, and conditional PDB to RGD; pushed commit `5dc0dfa` to `platform-catalog@main`; verified clean on non-prod.
- **Step 7 (Prod Promotion):** Tagged `5dc0dfa` as `v1.1.0` in `platform-catalog`; updated `blueprint-revisions.env`; rolled out `orders-prod-worker` cleanly; verified active PDB and restricted PSS.
- **Step 8 (Well-Architected Guide):** Documented TokenRequest lifecycle, rotation procedures, EKS Access Entries target architecture, and PDB reliability.

---

## 4. Verification Evidence & Test Outputs

### 4.1. Comprehensive Audit Verifications (Run #02)

```text
=== Check 1: Zero legacy service-account-token Secrets on ALL clusters ===
k3d-hub-cluster: No resources found
k3d-spoke-nonprod: No resources found
k3d-spoke-prod: No resources found
✔ PASS: All clusters 100% clean of static legacy tokens.

=== Check 2: Plaintext secret annotations absent (C3 loop) ===
OK  argocd/cluster-spoke-nonprod
OK  argocd/cluster-spoke-prod
OK  headlamp/headlamp-kubeconfig
✔ PASS: No plaintext tokens stored in last-applied annotations.

=== Check 3: Orphaned MessageProcessor CRD absent ===
k3d-spoke-nonprod: NotFound
k3d-spoke-prod: NotFound
✔ PASS: Obsolete CRD eradicated.

=== Check 4: Duplicate Secret absent & Zero application conditions ===
Secret repo-ghcr-charts: NotFound
addon-headlamp: conditions=
kro-blueprints-spoke-nonprod: conditions=
kro-blueprints-spoke-prod: conditions=
orders-dev: conditions=
orders-prod: conditions=
orders-test: conditions=
root-control-plane: conditions=
✔ PASS: All applications healthy with zero conditions.

=== Check 5: Zero personal host paths ===
git grep -nE 'file:///|/home/bleit[e]' -- ':!docs/assessments' ':!docs/remediation' -> 0 matches
✔ PASS: Repository is 100% portable.

=== Check 6: Blueprint tags and single source of truth ===
Tags in platform-catalog: v1.0.0 v1.1.0
clusters/blueprint-revisions.env:
  spoke-nonprod=main
  spoke-prod=v1.1.0
kro-blueprints-spoke-nonprod targetRevision: main
kro-blueprints-spoke-prod targetRevision: v1.1.0
✔ PASS: Promotion gate correctly wired and pinned.

=== Check 7: Workload hardening, PSS Restricted, and PDB ===
orders-dev:
  ServiceAccount: orders-dev-sa
  Volumes: tmp (no kube-api-access)
  PSS Restricted Dry-Run: labeled (server dry run) [0 warnings]
  PDB: None (replicas = 1)
orders-prod:
  ServiceAccount: orders-prod-sa
  Volumes: tmp (no kube-api-access)
  PSS Restricted Dry-Run: labeled (server dry run) [0 warnings]
  PDB: orders-prod-pdb (minAvailable = 1, disruptionsAllowed = 1)
✔ PASS: PSS Restricted satisfied; PDB conditionally active in prod only.

=== Check 8: Argo CD connectivity & applications health ===
SERVER                                   NAME           VERSION  STATUS      MESSAGE  PROJECT
https://k3d-spoke-nonprod-server-0:6443  spoke-nonprod  v1.35.5  Successful           
https://k3d-spoke-prod-server-0:6443     spoke-prod     v1.35.5  Successful           
https://kubernetes.default.svc           in-cluster     v1.35.5  Successful           

NAME                           SYNC STATUS   HEALTH STATUS
addon-headlamp                 Synced        Healthy
kro-blueprints-spoke-nonprod   Synced        Healthy
kro-blueprints-spoke-prod      Synced        Healthy
orders-dev                     Synced        Healthy
orders-prod                    Synced        Healthy
orders-test                    Synced        Healthy
root-control-plane             Synced        Healthy
✔ PASS: All clusters Successful and all applications Synced/Healthy.
```

### 4.2. End-to-End Smoke Test Suite (`make test`)

```text
============================================================
  Multi-Cluster Hub-and-Spoke Smoke Test                   
============================================================

[1/5] Checking Central Mock AWS Cloud (moto-cloud)...
✔ moto-cloud is responding at http://localhost:5000

[2/5] Checking Hub Cluster & Argo CD...
✔ Hub cluster API is reachable
✔ All Argo CD core pods are Running
  Registered clusters in Hub Argo CD: cluster-spoke-nonprod cluster-spoke-prod
✔ Both spoke-nonprod and spoke-prod clusters are registered

[3/5] Checking Spoke Non-Prod (k3d-spoke-nonprod)...
✔ spoke-nonprod API is reachable
✔ ACK SQS controller is ready on spoke-nonprod
✔ Kro controller is ready on spoke-nonprod

[4/5] Checking Spoke Prod (k3d-spoke-prod)...
✔ spoke-prod API is reachable
✔ ACK SQS controller is ready on spoke-prod
✔ Kro controller is ready on spoke-prod

[5/5] Checking Workloads & SQS Queues...
Current SQS queues in Central Moto Cloud:
------------------------------------------------------------
|                        ListQueues                        |
+----------------------------------------------------------+
||                        QueueUrls                       ||
|+--------------------------------------------------------+|
||  http://localhost:5000/123456789012/orders-prod-queue  ||
||  http://localhost:5000/123456789012/orders-dev-queue   ||
||  http://localhost:5000/123456789012/orders-test-queue  ||
||  http://localhost:5000/123456789012/orders-prod-dlq    ||
||  http://localhost:5000/123456789012/orders-test-dlq    ||
||  http://localhost:5000/123456789012/orders-dev-dlq     ||
|+--------------------------------------------------------+|
  orders-dev pods on spoke-nonprod:  1 (expected: 1)
  orders-test pods on spoke-nonprod: 1 (expected: 1)
  orders-prod pods on spoke-prod:    2 (expected: 2)
✔ All orders workloads running across non-prod and prod spokes!

============================================================
  All Core Smoke Tests Passed!                             
============================================================
```

---

## 5. Git Commit Log

### `gitops-control-plane`
- `eb4a0d9`: `fix(security): step 0 token rotation, secret scrubbing, and single revision source`
- `6a1519b`: `docs: step 3 & 4 portability fixes and developer tutorial synchronization`
- `966fc23`: `feat(blueprints): promote blueprints per spoke using blueprints-revision annotation`
- `e301e1f`: `chore(blueprints): promote spoke-prod to v1.1.0 (commit 5dc0dfa)`
- `ea67e93`: `docs: step 8 update AWS Well-Architected guide with security, token lifecycle, and PDB reliability details`
- `5ac95f2`: `docs: add 2026-09-30-lab-remediation-plan-implemented-01.md implementation report`
- *(Current)*: `fix(audit): resolve validation observations V-1 to V-9 and publish implementation report #02`

### `platform-catalog`
- `a8825b2` (Tagged `v1.0.0`): Baseline blueprint running on prod
- `5dc0dfa` (Tagged `v1.1.0`): Hardened blueprint with dedicated SA, PSS `RuntimeDefault`/`readOnlyRootFilesystem`, and conditional PDB

---

## 6. Operational Runbooks

### 6.1. Routine 30-Day Token Rotation
Tokens issued via `TokenRequest` API expire after 720 hours (30 days). To issue fresh tokens without downtime:
```bash
make rotate-spoke-tokens
```
*Note: Tokens expire naturally at their TTL. Because TokenRequest tokens cannot be revoked individually without deleting their parent ServiceAccount, older tokens remain valid until their expiration timestamp (`lab/token-expires`).*

### 6.2. Emergency Token Revocation Runbook
If a spoke token is compromised and must be invalidated immediately before its 30-day expiration:
```bash
kubectl --context k3d-spoke-prod -n kube-system delete sa argocd-manager
make rotate-spoke-tokens
```
Deleting and recreating the `argocd-manager` ServiceAccount instantly invalidates all previously issued TokenRequest tokens for that ServiceAccount.

### 6.3. Future Blueprint Promotion Process
To promote a new blueprint release to production without minting new credentials:
1. Make and test blueprint changes on `platform-catalog@main`.
2. Verify behavior in non-prod (`orders-dev` / `orders-test`).
3. Identify the verified Git SHA (e.g., `abc1234`).
4. Tag release in `platform-catalog`:
   ```bash
   git -C ../platform-catalog tag -a v1.2.0 abc1234 -m "Release description"
   git -C ../platform-catalog push origin v1.2.0
   ```
5. Promote in control plane:
   - Edit `clusters/blueprint-revisions.env` -> `spoke-prod=v1.2.0`.
   - Commit & push:
     ```bash
     git commit -am "chore: promote spoke-prod to v1.2.0" && git push
     ```
   - Annotate cluster Secret without minting new credentials:
     ```bash
     make promote-blueprints
     ```
