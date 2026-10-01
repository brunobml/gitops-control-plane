# Remediation Implementation Report — Phase 2, Run #01 (2026-09-30)

| Field | Details |
|---|---|
| **Plan Reference** | [`2026-09-30-lab-remediation-plan-phase2.md`](2026-09-30-lab-remediation-plan-phase2.md) (Plan v1.0, Review commit `5939bc5`) |
| **Scope Executed** | **Authorized Scope**: Track 1 Quick Wins (Steps 1–5), Step 8 (PSS `restricted` labels), Conditions C-1 to C-4, and Observation X-1 |
| **Scope Deferred** | Track 2 (L4-1 Headlamp), Step 9 (NetworkPolicy), Step 10 (CARM), Track 4 (Prod Promotion Gate) pending Plan v1.1 resolution of blockers P2-B1 through P2-B6 |
| **Execution Date** | 2026-09-30 |
| **Target Repositories** | `gitops-control-plane`, `platform-catalog`, `orders-processor` |

---

## 1. Summary of Actions Taken & Findings Addressed

| Step / Finding | Sev | Summary of Implemented Changes | Status |
|:---|:---:|:---|:---:|
| **Step 1 / L3-5** | High | **Immutable CI Tagging & Release v1.3.0 (C-1):** Updated `orders-processor/.github/workflows/ci.yaml` to eliminate mutable raw tags (`latest`, `v1.2.0`, `v1.1.0`), generate SemVer and commit SHA tags (`type=semver`, `type=sha,prefix=sha-`), and derive `APP_VERSION` from `github.ref_name`. Cut release `v1.3.0`, built and loaded image into spoke clusters, updated values files, tagged git release `v1.3.0`, and pushed upstream. | ✅ Implemented & Verified |
| **Step 2 / L3-1** | High | **ACK SQS Resync Window Hardening (C-3):** Set `reconcile: {defaultResyncPeriod: 300}` in `platform-catalog/controllers/ack/values-sqs.yaml`. Upgraded Helm release `ack-sqs-controller` on `k3d-spoke-nonprod` and `k3d-spoke-prod`. Verified container env `RECONCILE_DEFAULT_RESYNC_SECONDS="300"`. | ✅ Implemented & Verified |
| **Step 3 / L3-4** | Medium | **Honest Multi-Cluster Smoke Test Suite (C-2):** Overhauled `scripts/smoke-test-hub-spoke.sh`. Replaced flaky grep logic with structured validation of all 7 Argo CD applications (`Synced`/`Healthy`), verified all 3 `QueueBackedService` CRs are `ACTIVE`, validated all 6 SQS queues and DLQs by exact name in Moto, and fixed the `grep -c` bug. | ✅ Implemented & Verified |
| **Step 4 / L4-7, L1-4** | Medium | **AppProject Hardening & Cleanup:** Created `projects/default.yaml` locking down the `default` AppProject (`sourceRepos: []`, `destinations: []`, `clusterResourceWhitelist: []`). Removed dead repository `tenant-workloads.git` from `projects/tenant-workloads.yaml`. Applied both to Hub cluster. | ✅ Implemented & Verified |
| **Step 5 / X-1** | Info | **Promotion Preflight Branch Pinning:** Updated `scripts/promote-blueprints.sh` to enforce that promotions only execute from the `main` branch and that local HEAD is an ancestor of `origin/main` (`git fetch -q origin main && git merge-base --is-ancestor HEAD origin/main`). | ✅ Implemented & Verified |
| **Step 8 / L4-3** | High | **Declarative PSS Restricted Enforcement (C-4):** Configured `syncPolicy.managedNamespaceMetadata.labels` in `tenant-workloads-nonprod.yaml` and `tenant-workloads-prod.yaml` to enforce `pod-security.kubernetes.io/enforce=restricted`. Applied to Hub and verified across `orders-dev`, `orders-test`, and `orders-prod`. | ✅ Implemented & Verified |

---

## 2. Detailed Technical Execution Log

### 2.1 Step 1 (L3-5 & C-1): Immutable CI Pipeline & Release `v1.3.0`
1. **Workflow Update:** In [`orders-processor/.github/workflows/ci.yaml`](file:///home/bleite/repos/orders-processor/.github/workflows/ci.yaml), removed lines publishing mutable tags `latest`, `v1.2.0`, `v1.1.0` on every push to `main`. Configured:
   ```yaml
   tags: |
     type=semver,pattern={{version}}
     type=sha,format=short,prefix=sha-
   build-args: |
     APP_VERSION=${{ github.ref_name }}
     BUILD_COMMIT=${{ github.sha }}
     BUILD_TIME=${{ steps.build_time.outputs.time }}
   ```
2. **Values Files Update:** Updated `deploy/values-dev.yaml`, `deploy/values-test.yaml`, and `deploy/values-prod.yaml` to reference `ghcr.io/brunobml/orders-processor:v1.3.0`.
3. **Local Build & Cluster Import:** Built container image `ghcr.io/brunobml/orders-processor:v1.3.0` and imported it into `k3d-spoke-nonprod` and `k3d-spoke-prod` using `k3d image import`.
4. **Git Tagging & Push:** Committed changes with message `fix(ci): enforce immutable semver/sha image tagging and bump workloads to v1.3.0 (L3-5)`, created annotated Git tag `v1.3.0`, and pushed commit and tag to `origin/main` (`commit 8f5e0b6`).
5. **Live Verification:** Workload pods in `orders-dev`, `orders-test`, and `orders-prod` automatically rolled out to `ghcr.io/brunobml/orders-processor:v1.3.0` with 0 restarts.

### 2.2 Step 2 (L3-1 & C-3): Lower ACK SQS Resync Period
1. **Catalog Update:** Added `reconcile: {defaultResyncPeriod: 300}` to [`platform-catalog/controllers/ack/values-sqs.yaml`](file:///home/bleite/repos/platform-catalog/controllers/ack/values-sqs.yaml). Committed and pushed (`commit c0f8779`).
2. **Spoke Helm Upgrades:** Upgraded Helm release `ack-sqs-controller` on `k3d-spoke-nonprod` and `k3d-spoke-prod`:
   ```bash
   helm --kube-context k3d-spoke-nonprod upgrade ack-sqs-controller oci://public.ecr.aws/aws-controllers-k8s/sqs-chart \
     --version 1.7.1 --namespace ack-system -f controllers/ack/values-sqs.yaml
   helm --kube-context k3d-spoke-prod upgrade ack-sqs-controller oci://public.ecr.aws/aws-controllers-k8s/sqs-chart \
     --version 1.7.1 --namespace ack-system -f controllers/ack/values-sqs.yaml
   ```
3. **Rollout Verification:** Verified both deployments rolled out cleanly and container env variable reflects the new setting:
   ```bash
   $ kubectl --context k3d-spoke-nonprod -n ack-system get deploy ack-sqs-controller-sqs-chart -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="RECONCILE_DEFAULT_RESYNC_SECONDS")].value}'
   300
   ```

### 2.3 Step 3 (L3-4 & C-2): Overhauled Smoke Test Suite
1. **Script Enhancement:** Rewrote [`scripts/smoke-test-hub-spoke.sh`](file:///home/bleite/repos/gitops-control-plane/scripts/smoke-test-hub-spoke.sh):
   - Asserts all Argo CD applications in namespace `argocd` are `Synced` and `Healthy`, ensuring expected apps (`addon-headlamp`, `kro-blueprints-spoke-nonprod`, `kro-blueprints-spoke-prod`, `orders-dev`, `orders-test`, `orders-prod`, `root-control-plane`) are present.
   - Asserts all 3 `QueueBackedService` CR instances are in state `ACTIVE`.
   - Asserts all 6 queues by exact name via AWS CLI against Moto: `orders-dev-queue`, `orders-dev-dlq`, `orders-test-queue`, `orders-test-dlq`, `orders-prod-queue`, `orders-prod-dlq`.
   - Replaced fragile `grep -c` checks with `wc -l` counting against `status.phase=Running`.
   - Added fail-closed `exit 1` on any assertion failure.
2. **Verification:** Ran `make test`; all 7 stages passed cleanly with zero warnings or errors.

### 2.4 Step 4 (L4-7, L1-4): AppProject Hardening
1. **Tenant Project Cleanup:** Removed dead repo `https://github.com/brunobml/tenant-workloads.git` from `projects/tenant-workloads.yaml`.
2. **Default Project Lockdown:** Created [`projects/default.yaml`](file:///home/bleite/repos/gitops-control-plane/projects/default.yaml) with empty `sourceRepos: []`, `destinations: []`, `clusterResourceWhitelist: []`, `namespaceResourceWhitelist: []`.
3. **Application to Hub:** Applied both files to `k3d-hub-cluster`. Confirmed `appproject.argoproj.io/default` is locked down and cannot be used to deploy arbitrary resources.

### 2.5 Step 5 (X-1): Promotion Preflight Main Branch Check
1. **Script Update:** Modified [`scripts/promote-blueprints.sh`](file:///home/bleite/repos/gitops-control-plane/scripts/promote-blueprints.sh):
   ```bash
   current_branch=$(git -C "$REPO_DIR" branch --show-current)
   if [[ "$current_branch" != "main" ]]; then
     echo "❌ Error: Promotion must be run from 'main' branch (current: '${current_branch}')." >&2
     exit 1
   fi
   if ! git -C "$REPO_DIR" fetch -q origin main || ! git -C "$REPO_DIR" merge-base --is-ancestor HEAD origin/main; then
     echo "❌ Error: Local commits not pushed to upstream origin/main. Push to Git first." >&2
     exit 1
   fi
   ```
2. **Verification:**
   - Tested running with uncommitted edits to `clusters/blueprint-revisions.env` -> rejected with `Uncommitted changes`.
   - Tested running against live repo -> preflight passed and proceeded to spoke argument guard.

### 2.6 Step 8 (L4-3 & C-4): Declarative PSS Restricted Enforcement
1. **ApplicationSet Update:** Updated [`applicationsets/tenant-workloads-nonprod.yaml`](file:///home/bleite/repos/gitops-control-plane/applicationsets/tenant-workloads-nonprod.yaml) and [`applicationsets/tenant-workloads-prod.yaml`](file:///home/bleite/repos/gitops-control-plane/applicationsets/tenant-workloads-prod.yaml) under `syncPolicy`:
   ```yaml
   managedNamespaceMetadata:
     labels:
       pod-security.kubernetes.io/enforce: restricted
       pod-security.kubernetes.io/enforce-version: latest
       pod-security.kubernetes.io/warn: restricted
       pod-security.kubernetes.io/audit: restricted
   ```
2. **Applied & Verified:** Applied both ApplicationSets to `k3d-hub-cluster`. Verified labels on namespaces `orders-dev`, `orders-test`, `orders-prod`. Workload pods are running with 0 restarts and 0 security admission warnings.

---

## 3. Verification & Live Cluster Evidence

```
============================================================
  Multi-Cluster Hub-and-Spoke Smoke Test                   
============================================================

[1/7] Checking Central Mock AWS Cloud (moto-cloud)...
✔ moto-cloud is responding at http://localhost:5000

[2/7] Checking Hub Cluster & Argo CD...
✔ Hub cluster API is reachable
✔ All Argo CD core pods are Running
  Registered clusters in Hub Argo CD: cluster-spoke-nonprod cluster-spoke-prod
✔ Both spoke-nonprod and spoke-prod clusters are registered

[3/7] Asserting Argo CD Application Sync and Health...
  Application addon-headlamp: Synced / Healthy
  Application kro-blueprints-spoke-nonprod: Synced / Healthy
  Application kro-blueprints-spoke-prod: Synced / Healthy
  Application orders-dev: Synced / Healthy
  Application orders-test: Synced / Healthy
  Application orders-prod: Synced / Healthy
  Application root-control-plane: Synced / Healthy
✔ All Argo CD applications are Synced and Healthy

[4/7] Checking Spoke Controllers (Kro + ACK)...
✔ k3d-spoke-nonprod API is reachable
✔ ACK SQS controller is ready on k3d-spoke-nonprod
✔ Kro controller is ready on k3d-spoke-nonprod
✔ k3d-spoke-prod API is reachable
✔ ACK SQS controller is ready on k3d-spoke-prod
✔ Kro controller is ready on k3d-spoke-prod

[5/7] Asserting QueueBackedService Resource Status...
  k3d-spoke-nonprod/orders-dev QueueBackedService: ACTIVE
  k3d-spoke-nonprod/orders-test QueueBackedService: ACTIVE
  k3d-spoke-prod/orders-prod QueueBackedService: ACTIVE
✔ All QueueBackedService instances are ACTIVE

[6/7] Asserting AWS Cloud SQS Queues & DLQs...
  Queue: orders-dev-queue present
  Queue: orders-dev-dlq present
  Queue: orders-test-queue present
  Queue: orders-test-dlq present
  Queue: orders-prod-queue present
  Queue: orders-prod-dlq present
✔ All 6 expected SQS queues (3 queues + 3 DLQs) verified in Moto Cloud

[7/7] Asserting Workload Pods...
  orders-dev pods on spoke-nonprod:  1 (expected: 1)
  orders-test pods on spoke-nonprod: 1 (expected: 1)
  orders-prod pods on spoke-prod:    2 (expected: 2)
✔ All orders workloads running across non-prod and prod spokes!

============================================================
  All Core Smoke Tests Passed!                             
============================================================
```

---

## 4. Next Steps for Phase 2 Plan v1.1

With Track 1 and Step 8 fully implemented and verified:
1. Address Review Blockers in Plan v1.1:
   - **P2-B1 & P2-B2 (Headlamp Gateway):** Remove ClusterRoleBinding `headlamp-admin`, disable automount on SA `headlamp`, remove `-insecure-ssl` extraArg.
   - **P2-B3 (Headlamp Aggregated Viewer):** Bind built-in `view` and aggregate CRD viewer permissions for `sqs.services.k8s.aws`, `services.k8s.aws`, `kro.run`, and `apiextensions.k8s.io`.
   - **P2-B4 (NetworkPolicy):** Embed NetworkPolicy template into the Kro ResourceGraphDefinition (`orders-${env}-worker` pod selector) with explicit egress to DNS and Moto network (`172.21.0.0/16`).
   - **P2-B5 (ACK CARM Multi-Account):** Formally defer CARM multi-account until per-environment worker IAM credentials and migration procedures are prepared.
   - **P2-B6 (Production Workload Gate):** Add `valuesRevision` to the ApplicationSet List generator and pin `orders-prod` to `v1.3.0`.
