# Lab Remediation Implementation Report — 2026-09-30 (Run #01)

| Metadata | Details |
|---|---|
| **Document** | `docs/remediation/2026-09-30-lab-remediation-plan-implemented-01.md` |
| **Plan Reference** | [`2026-09-30-lab-remediation-plan.md`](2026-09-30-lab-remediation-plan.md) (v3.0, commit `9571f2f`) |
| **Review Reference** | [`2026-09-30-lab-remediation-plan-review.md`](2026-09-30-lab-remediation-plan-review.md) (Green Light Approval) |
| **Assessment Target** | [`../assessments/2026-09-30-lab-assessment.md`](../assessments/2026-09-30-lab-assessment.md) |
| **Execution Date** | 2026-09-30 |
| **Execution Status** | ✅ **SUCCESSFUL — ALL STEPS 0–8 EXECUTED & VERIFIED** |

---

## 1. Executive Summary

This document records the complete, verified execution of remediation plan v3.0, addressing the Low-severity findings and urgent security findings identified in the 2026-09-30 multi-cluster GitOps control plane lab assessment.

All implementation conditions (**C1**, **C2**, **C3**) from the peer review were incorporated during execution:
- **C1 (Staggered Rotation):** Spoke credentials rotated and verified individually before deleting legacy tokens.
- **C2 (Fail-Closed Guard):** Registration script halts if a cluster's revision is absent from the single source of truth.
- **C3 (Annotation Check):** Checked that `kubectl.kubernetes.io/last-applied-configuration` is completely absent across all three cluster secrets.

---

## 2. Findings Remediation Matrix

| Finding ID | Severity | Description | Remediation Implemented | Status |
|---|---|---|---|:---:|
| **B1 / B2** | **Blocker** | Leaked spoke tokens; plaintext tokens preserved in `last-applied-configuration` | Migrated to 30-day `TokenRequest` API; deleted legacy Secrets; stripped annotations before server-side apply | ✅ Resolved (Step 0) |
| **L1-2** | Low | Kro blueprints lack promotion gate (both spokes tracked `main`) | Implemented Git tag promotion (`v1.0.0`, `v1.1.0`) with `clusters/blueprint-revisions.env` | ✅ Resolved (Steps 5, 7) |
| **L1-3** | Low | Duplicate repository Secret (`repo-ghcr-charts`) in Argo CD | Deleted unmanaged Secret; confirmed all 7 Argo CD applications have 0 error conditions | ✅ Resolved (Step 2) |
| **L1-6** | Low | Hardcoded local filesystem paths (`/home/bleite`) across 6 repo files | Anchored `ROOT_DIR` / `REPOS_DIR` in `Makefile`; converted documentation links to relative paths | ✅ Resolved (Step 3) |
| **L2-7** | Low | Spoke workloads lack dedicated ServiceAccount and run default PSS | Hardened RGD with dedicated SA, token automount disabled, `RuntimeDefault` seccomp, `readOnlyRootFilesystem`, `/tmp` `emptyDir` | ✅ Resolved (Steps 6, 7) |
| **L3-8** | Low | Missing PodDisruptionBudget for production workloads | Added conditional PDB via Kro CEL `includeWhen: [ ${schema.spec.replicas > 1} ]` | ✅ Resolved (Steps 6, 7) |
| **L4-10** | Low | Long-lived spoke registration credentials | Bounded tokens to 720h (`TokenRequest`); added `make rotate-spoke-tokens`; documented AWS EKS Access Entries target | ✅ Resolved (Steps 0, 8) |
| **L4-11** | Low | Developer onboarding tutorial references deprecated blueprint | Replaced `MessageProcessor` with `QueueBackedService`, synced namespaces and replicas | ✅ Resolved (Step 4) |

---

## 3. Step-by-Step Execution Log

### Step 0: Token Rotation & Plaintext Secret Scrubbing (Urgent Security)
1. **Script Hardening:**
   - Modified `scripts/register-spokes.sh` to issue 30-day tokens via `kubectl create token argocd-manager --duration=720h`.
   - Extracted Spoke CA directly from the spoke cluster's `kube-root-ca.crt` ConfigMap (`ca.crt | base64 | tr -d '\n'`), eliminating reliance on legacy token secrets.
   - Added fail-closed guard (C2):
     ```bash
     bp_rev=$(grep -E "^${spoke}=" "$REVISIONS_FILE" | cut -d'=' -f2)
     : "${bp_rev:?no blueprints-revision for ${spoke} in clusters/blueprint-revisions.env}"
     ```
   - Added explicit stripping of plaintext `last-applied-configuration` annotations before running `kubectl apply --server-side --force-conflicts`.
2. **Staggered Execution (C1):**
   - Registered `spoke-nonprod`: verified `argocd cluster list` reported `Successful`, then deleted `kube-system/argocd-manager-token` on `spoke-nonprod`.
   - Registered `spoke-prod`: verified `argocd cluster list` reported `Successful`, then deleted `kube-system/argocd-manager-token` on `spoke-prod`.
3. **Headlamp Decoupling:**
   - Executed `addons/headlamp/setup-credentials.sh` using 720h `TokenRequest` for Hub `headlamp` SA and spoke bearer tokens from cluster Secrets.
   - Deleted legacy `headlamp/headlamp-token` Secret.
   - Stripped `last-applied-configuration` on `headlamp-kubeconfig` and applied server-side.
   - Rolled out `deployment/headlamp` and verified running pods.
4. **Validation (C3):**
   - Verified that `kubectl.kubernetes.io/last-applied-configuration` is completely absent on `argocd/cluster-spoke-nonprod`, `argocd/cluster-spoke-prod`, and `headlamp/headlamp-kubeconfig`.
   - Confirmed `kube-system/argocd-manager-token` and `headlamp/headlamp-token` return `NotFound`.

### Step 1: Low-Risk Cleanup
1. Backed up `messageprocessors.kro.run` CRD on both spokes to `/tmp/mp-crd-nonprod.yaml` and `/tmp/mp-crd-prod.yaml`.
2. Confirmed 0 Custom Resources existed for `messageprocessors.kro.run` on both spokes.
3. Deleted `messageprocessors.kro.run` CRD on both `k3d-spoke-nonprod` and `k3d-spoke-prod`. Confirmed `NotFound`.
4. Removed stray stopped Docker containers (`elastic_kapitsa`, `affectionate_dubinsky`, `friendly_lalande`).

### Step 2: Duplicate Repository Secret Cleanup (L1-3)
1. Deleted unmanaged Secret `repo-ghcr-charts` from namespace `argocd` on Hub.
2. Authenticated `argocd` CLI to `localhost:8080`.
3. Triggered hard-refresh on `orders-dev`, `orders-test`, and `orders-prod`.
4. Verified all 7 Argo CD applications have empty `.status.conditions`.

### Step 3: Repository Portability Fixes (L1-6)
1. In `Makefile`:
   - Anchored paths with `ROOT_DIR := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))` and `REPOS_DIR ?= $(abspath $(ROOT_DIR)/..)`.
   - Added `rotate-spoke-tokens` phony target.
2. Updated documentation across 5 files:
   - `README.md`: Updated repo count to 5; removed hardcoded `/home/bleite` paths; updated app names to `orders-*`.
   - `addons/headlamp/README.md`: Converted `file:///` links to relative paths.
   - `docs/developer-tutorial.md`: Removed `file:///` links.
   - `docs/lab-progression-and-next-steps.md`: Converted `file:///` links to relative and GitHub links.
   - `docs/production-promotion-guardrails.md`: Converted `file:///` links to relative paths.
3. Verification check:
   ```bash
   git grep -nE 'file:///|/home/bleit[e]' -- ':!docs/assessments' ':!docs/remediation'
   ```
   Returned **0 matches**.

### Step 4: Developer Documentation Sync (L4-11)
1. Synchronized `docs/developer-tutorial.md`:
   - Updated manifest samples from `MessageProcessor` to `QueueBackedService`.
   - Updated namespace routing from `tenant-a-*` to `orders-dev`, `orders-test`, `orders-prod`.
   - Updated production replica count to 2 (matching live `values-prod.yaml`).

### Step 5: Promotion Gate Wiring (L1-2, S1)
1. **Platform Catalog Baseline Tag (5a):**
   - Tagged `platform-catalog@a8825b2` as `v1.0.0` with message *"Blueprint baseline currently running on spoke-prod"*.
   - Pushed tag `v1.0.0` to `origin`.
2. **Single Source of Truth (5b):**
   - Created `clusters/blueprint-revisions.env` containing:
     ```env
     spoke-nonprod=main
     spoke-prod=v1.0.0
     ```
   - Synced `blueprints-revision` annotations on `cluster-spoke-nonprod` (`main`) and `cluster-spoke-prod` (`v1.0.0`).
3. **ApplicationSet Wiring (5c):**
   - Updated `applicationsets/kro-blueprints.yaml`:
     ```yaml
     targetRevision: '{{metadata.annotations.blueprints-revision}}'
     ```
   - Applied to Hub cluster and committed to `gitops-control-plane`.
   - Verified `kro-blueprints-spoke-nonprod` points to `main` and `kro-blueprints-spoke-prod` points to `v1.0.0`.

### Step 6: Blueprint Hardening in `platform-catalog` (L2-7, N1, R1, N7)
1. Modified `blueprints/queue-backed-service-rgd.yaml`:
   - Added `ServiceAccount` resource: `${schema.spec.name}-${schema.spec.environment}-sa` with `automountServiceAccountToken: false`.
   - Wired DAG edge into Deployment: `serviceAccountName: ${serviceaccount.metadata.name}` and `automountServiceAccountToken: false`.
   - Enforced Pod Security Standards:
     ```yaml
     securityContext:
       runAsNonRoot: true
       runAsUser: 10001
       runAsGroup: 10001
       fsGroup: 10001
       seccompProfile:
         type: RuntimeDefault
     ```
   - Enforced container hardening:
     ```yaml
     securityContext:
       allowPrivilegeEscalation: false
       readOnlyRootFilesystem: true
       capabilities:
         drop: ["ALL"]
     volumeMounts:
       - name: tmp
         mountPath: /tmp
     ```
   - Added `PYTHONDONTWRITEBYTECODE: "1"` env var and `/tmp` `emptyDir` volume.
   - Added conditional `PodDisruptionBudget`:
     ```yaml
     - id: pdb
       includeWhen:
         - ${schema.spec.replicas > 1}
       template:
         apiVersion: policy/v1
         kind: PodDisruptionBudget
         metadata:
           name: ${schema.spec.name}-${schema.spec.environment}-pdb
         spec:
           minAvailable: 1
           selector:
             matchLabels:
               app: ${schema.spec.name}-${schema.spec.environment}-worker
     ```
2. Committed to `platform-catalog@main` (`commit 5dc0dfa`) and pushed to `origin`.
3. Verified on `spoke-nonprod`:
   - Argo CD `kro-blueprints-spoke-nonprod` synced commit `5dc0dfa`.
   - `orders-dev` rolled to new pod with `orders-dev-sa`.
   - Volumes contained only `tmp` (`kube-api-access` absent).
   - Server dry-run `pod-security.kubernetes.io/enforce=restricted` passed with **zero warnings**.
   - Dev PDB was **absent** (single replica).
   - Pods healthy with 0 restarts.

### Step 7: Blueprint Production Promotion
1. Tagged verified commit `5dc0dfa` as `v1.1.0` in `platform-catalog`:
   ```bash
   git tag -a v1.1.0 5dc0dfa -m "Hardened blueprint with dedicated SA, seccomp, and conditional PDB"
   git push origin v1.1.0
   ```
2. Updated `clusters/blueprint-revisions.env` to `spoke-prod=v1.1.0`.
3. Committed and pushed to `gitops-control-plane` (`commit e301e1f`).
4. Re-registered `spoke-prod` to apply the updated `blueprints-revision: v1.1.0` annotation.
5. Refreshed Argo CD `kro-blueprints-spoke-prod`: Synced to `v1.1.0 (5dc0dfa)`.
6. Verified on `spoke-prod`:
   - `orders-prod-worker` rolled cleanly to new pods using `orders-prod-sa`.
   - Volumes contained only `tmp`.
   - `orders-prod-pdb` was **created** (`minAvailable: 1`, `allowedDisruptions: 1`).
   - Server dry-run `pod-security.kubernetes.io/enforce=restricted` passed with **zero warnings**.

### Step 8: Documentation & AWS Well-Architected Framework Updates
1. Updated `docs/aws-well-architected-production-guide.md`:
   - codifying TokenRequest 30-day lifecycle and rotation command `make rotate-spoke-tokens`.
   - Documented immediate revocation runbook (deleting and recreating the `argocd-manager` ServiceAccount).
   - Documented AWS production target (EKS Access Entries + IAM Roles for Service Accounts / Pod Identity).
   - Added Pod Disruption Budget reliability architecture.
2. Committed and pushed to `gitops-control-plane` (`commit ea67e93`).

---

## 4. Verification Evidence & Test Outputs

### 4.1. Security & Hygiene Verifications

```text
=== Verification 1: Legacy token secrets absent ===
✔ OK: k3d-spoke-nonprod kube-system/argocd-manager-token is NotFound
✔ OK: k3d-spoke-prod kube-system/argocd-manager-token is NotFound
✔ OK: k3d-hub-cluster headlamp/headlamp-token is NotFound

=== Verification 2: Plaintext secret annotations absent (C3) ===
✔ OK  argocd/cluster-spoke-nonprod
✔ OK  argocd/cluster-spoke-prod
✔ OK  headlamp/headlamp-kubeconfig

=== Verification 3: MessageProcessor CRD absent ===
✔ OK: k3d-spoke-nonprod messageprocessors.kro.run is NotFound
✔ OK: k3d-spoke-prod messageprocessors.kro.run is NotFound

=== Verification 4: Duplicate secret absent & zero app conditions ===
✔ OK: repo-ghcr-charts is NotFound
addon-headlamp: conditions=
kro-blueprints-spoke-nonprod: conditions=
kro-blueprints-spoke-prod: conditions=
orders-dev: conditions=
orders-prod: conditions=
orders-test: conditions=
root-control-plane: conditions=

=== Verification 5: Zero hardcoded host paths ===
✔ OK: Zero hardcoded paths found

=== Verification 6: Blueprint tags, env, and targetRevisions ===
Tags in platform-catalog: v1.0.0 v1.1.0 
# Blueprint Git Revisions per Spoke Cluster
# S1 Single source of truth for blueprint promotion
spoke-nonprod=main
spoke-prod=v1.1.0
nonprod targetRevision: main
prod targetRevision: v1.1.0

=== Verification 7: Spoke workload hardening & PDB ===
nonprod SA: orders-dev-sa
nonprod volumes: tmp
nonprod PDB count: 
prod SA: orders-prod-sa
prod volumes: tmp
prod PDB: orders-prod-pdb

=== Verification 8: Argo CD cluster connectivity & application health ===
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
```

### 4.2. End-to-End Smoke Test Suite Output

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

### `platform-catalog`
- `a8825b2` (Tagged `v1.0.0`): Baseline blueprint running on prod
- `5dc0dfa` (Tagged `v1.1.0`): Hardened blueprint with dedicated SA, PSS `RuntimeDefault`/`readOnlyRootFilesystem`, and conditional PDB

---

## 6. Operational Runbook

### 6.1. Routine 30-Day Token Rotation
To rotate spoke authentication tokens before the 30-day bounded expiry:
```bash
make rotate-spoke-tokens
```
This issues fresh 720h tokens, applies them via server-side apply, deletes old tokens, and refreshes Headlamp credentials.

### 6.2. Emergency Token Revocation Runbook
Because tokens issued via the `TokenRequest` API cannot be revoked individually, execute early revocation by deleting and recreating the `argocd-manager` ServiceAccount:
```bash
kubectl --context k3d-spoke-prod -n kube-system delete sa argocd-manager
make rotate-spoke-tokens
```

### 6.3. Future Blueprint Promotion Process
1. Make and test blueprint changes on `platform-catalog@main`.
2. Verify behavior in non-prod (`orders-dev` / `orders-test`).
3. Identify the verified Git SHA (e.g., `abc1234`).
4. Tag release:
   ```bash
   git -C ../platform-catalog tag -a v1.2.0 abc1234 -m "Release description"
   git -C ../platform-catalog push origin v1.2.0
   ```
5. Promote in control plane:
   - Edit `clusters/blueprint-revisions.env` -> `spoke-prod=v1.2.0`.
   - Commit & push: `git commit -am "chore: promote spoke-prod to v1.2.0" && git push`.
   - Run: `bash scripts/register-spokes.sh spoke-prod`.
