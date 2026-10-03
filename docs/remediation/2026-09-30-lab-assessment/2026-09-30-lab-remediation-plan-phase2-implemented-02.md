# Phase 2 Implementation Report #02 (2026-09-30)

> **Status: Historical.** Record of the 2026-09-30 assessment and its remediation (Phases 1–5, closed 2026-10-03). Kept as evidence and not updated. For the lab as it is today, see the [README](../../../README.md) and the [2026-10-03 assessment](../../assessments/2026-10-03-lab-assessment.md).

| Metadata | Details |
|---|---|
| **Implementation Cycle** | Phase 2 — Run #02 |
| **Plan Implemented** | [`2026-09-30-lab-remediation-plan-phase2.md`](2026-09-30-lab-remediation-plan-phase2.md) (Plan v1.1, Approved with MC-1–MC-5) |
| **Target Repositories** | `orders-processor`, `gitops-control-plane`, `platform-catalog` |
| **Commits & Tags** | • `orders-processor@ca4797a`<br>• `platform-catalog@7fab51d` (tag `v1.2.0`)<br>• `gitops-control-plane@81e4cb6` |
| **Execution Date** | 2026-09-30 / 2026-10-01 UTC |

---

## 1. Executive Summary

All authorized Phase 2 remediation steps approved under **Plan v1.1** with **Mandatory Corrections MC-1 through MC-5** have been implemented and verified against the live clusters, GitHub Container Registry, and Git repositories.

| Step | Finding | Implementation Summary | Status |
|:---:|:---:|---|:---:|
| **Step 1** | **L3-5 / PV-1 / MC-4** | Workload manifests across dev, test, and prod pinned to the immutable published GHCR release artifact by digest (`1.3.0@sha256:3fc6e216...`). Purged the untracked locally imported image `:v1.3.0` from all 4 k3d nodes. Kubelets pulled directly from GHCR; runtime footer verified as `Git Commit: 8f5e0b6`. Updated `ci.yaml` pattern to `pattern=v{{version}}`. | ✅ **Closed & Verified** |
| **Step 5** | **X-1 / PV-2** | Strengthened `scripts/promote-blueprints.sh` preflight to require strict equality between local `HEAD` and `origin/main` (`rev-parse HEAD == rev-parse origin/main`). | ✅ **Closed & Verified** |
| **Steps 6 & 7** | **L4-1 (Mitigated) / MC-1, MC-5** | Overhauled Headlamp credentials: set `automountServiceAccountToken: false` and `clusterRoleBinding: {create: false}` in chart values; pruned legacy `headlamp-admin` cluster-admin binding; created dedicated `headlamp-viewer` SAs on all 3 clusters bound to built-in `view` ClusterRole with aggregated `headlamp-crd-viewer` ClusterRole (`aggregate-to-view: "true"`); assembled multi-cluster kubeconfig with cluster root CAs and `insecure-skip-tls-verify: false`; removed `-insecure-ssl`; verified full `auth can-i` matrix. | ✅ **Mitigated & Verified** |
| **Step 9** | **L4-3 / MC-2** | Embedded default-deny `NetworkPolicy` directly into `QueueBackedService` ResourceGroupDefinition in `platform-catalog` (without `metadata.namespace`). Allowed CoreDNS (53), Moto Cloud (`172.21.0.0/16:5000`), and Traefik ingress (8080) while blocking unauthorized egress (`1.1.1.1:443`, `8.8.8.8:80`). Verified on non-prod, tagged `v1.2.0`, and promoted to prod via `promote-blueprints.sh`. | ✅ **Closed & Verified** |
| **Step 11** | **L2-2 / MC-3** | Implemented production promotion gate in `applicationsets/tenant-workloads-prod.yaml`: added `valuesRevision: ca4797acbed28ea7a6a5caf23d591ea30d953d08` (full commit SHA of the digest-pin commit) to List generator and pinned `targetRevision: '{{valuesRevision}}'` while keeping `automated: {selfHeal: true}`. Proved divergence under live test commit: `orders-dev`/`orders-test` tracked `main` while `orders-prod` stayed pinned. | ✅ **Closed & Verified** |

---

## 2. Step-by-Step Implementation & Verification Evidence

### Step 1: Immutable CI Tagging & Digest Pinning (L3-5, PV-1, MC-4)

1. **Digest Pinning in Values Files:**
   Updated `deploy/values-dev.yaml`, `deploy/values-test.yaml`, and `deploy/values-prod.yaml` in `orders-processor` to reference:
   ```yaml
   image: ghcr.io/brunobml/orders-processor:1.3.0@sha256:3fc6e216e13c22db612253d9a844d915899e490acd0815a72d92e5c1279bd70e
   ```
2. **CI Pipeline SemVer Pattern Fix:**
   Updated `.github/workflows/ci.yaml` in `orders-processor` so future releases preserve the leading `v`:
   ```yaml
   tags: |
     type=semver,pattern=v{{version}}
     type=sha,format=short,prefix=sha-
   ```
   Committed and pushed to `orders-processor@main` (`commit ca4797a`).
3. **Kubelet Registry Pull Verification:**
   Triggered rollout across all environments. Verified that every running pod's `imageID` reflects the exact GHCR digest:
   ```bash
   $ kubectl --context k3d-spoke-nonprod get pods -n orders-dev -o jsonpath='{.items[*].status.containerStatuses[*].imageID}'
   ghcr.io/brunobml/orders-processor@sha256:3fc6e216e13c22db612253d9a844d915899e490acd0815a72d92e5c1279bd70e
   $ kubectl --context k3d-spoke-nonprod get pods -n orders-test -o jsonpath='{.items[*].status.containerStatuses[*].imageID}'
   ghcr.io/brunobml/orders-processor@sha256:3fc6e216e13c22db612253d9a844d915899e490acd0815a72d92e5c1279bd70e
   $ kubectl --context k3d-spoke-prod get pods -n orders-prod -o jsonpath='{.items[*].status.containerStatuses[*].imageID}'
   ghcr.io/brunobml/orders-processor@sha256:3fc6e216e13c22db612253d9a844d915899e490acd0815a72d92e5c1279bd70e
   ```
4. **Node Image Cache Purge (MC-4):**
   Purged the untracked locally imported image `:v1.3.0` across all 4 k3d nodes without `|| true`:
   ```bash
   --- Node: k3d-spoke-nonprod-server-0 ---
   Deleted: ghcr.io/brunobml/orders-processor:v1.3.0
   --- Node: k3d-spoke-nonprod-agent-0 ---
   Deleted: ghcr.io/brunobml/orders-processor:v1.3.0
   --- Node: k3d-spoke-prod-server-0 ---
   Deleted: ghcr.io/brunobml/orders-processor:v1.3.0
   --- Node: k3d-spoke-prod-agent-0 ---
   Deleted: ghcr.io/brunobml/orders-processor:v1.3.0
   ```
   Verified via `crictl images` that no `orders-processor:v1.3.0` tags remain on any node.
5. **Runtime Footer Commit Assertion:**
   Verified that the live HTTP response displays the verified release commit:
   ```html
   Git Commit: <code style="color:#cbd5e1;">8f5e0b6</code> • Built: <span style="color:#cbd5e1;">2026-10-01 02:13 UTC</span>
   ```

---

### Step 5: Promotion Preflight Exact Sync (X-1, PV-2)

1. Updated `scripts/promote-blueprints.sh` in `gitops-control-plane` to replace the ancestor check with an exact equality check:
   ```bash
   if ! git -C "$REPO_DIR" fetch -q origin main; then
     echo "❌ Error: Failed to fetch origin/main." >&2
     exit 1
   fi

   if [[ $(git -C "$REPO_DIR" rev-parse HEAD) != $(git -C "$REPO_DIR" rev-parse origin/main) ]]; then
     echo "❌ Error: Local 'main' is not in sync with origin/main. Pull or push first." >&2
     exit 1
   fi
   ```
2. Committed and pushed in `gitops-control-plane` (`commit aac4a0f`). Tested and passed cleanly during production blueprint promotion.

---

### Track 2: Headlamp Gateway Overhaul (L4-1 Mitigated, MC-1, MC-5)

1. **ApplicationSet & Chart Values Hardening (MC-1):**
   Updated `applicationsets/addon-headlamp.yaml` and `addons/headlamp/values.yaml` in `gitops-control-plane`:
   ```yaml
   valuesObject:
     automountServiceAccountToken: false
     clusterRoleBinding:
       create: false
     config:
       inCluster: false
       extraArgs:
         - "-kubeconfig=/home/headlamp/.kube/config"
         - "-dev"
   ```
2. **Dedicated Viewer RBAC & Strict TLS Script (MC-1, MC-5):**
   Rewrote `addons/headlamp/setup-credentials.sh`:
   - Configured dedicated `headlamp-access:headlamp-viewer` ServiceAccounts on Hub, Spoke-Nonprod, and Spoke-Prod.
   - Deployed aggregated `ClusterRole/headlamp-crd-viewer` on all 3 clusters with label `rbac.authorization.k8s.io/aggregate-to-view: "true"` covering `kro.run`, `internal.kro.run`, `sqs.services.k8s.aws`, `services.k8s.aws`, and `apiextensions.k8s.io/customresourcedefinitions`.
   - Bound `headlamp-viewer` to built-in `view` ClusterRole via `ClusterRoleBinding/headlamp-viewer-binding`.
   - Issued 720h TokenRequest tokens.
   - Extracted cluster root CAs from `kube-root-ca.crt` ConfigMaps and generated multi-cluster kubeconfig with `certificate-authority-data: <caData>` and `insecure-skip-tls-verify: false`.
   - Applied `headlamp-kubeconfig` via server-side apply with stripped plaintext annotations.
3. **Execution & Argo CD Sync:**
   Executed `addons/headlamp/setup-credentials.sh` and synced `addon-headlamp` in Argo CD.
4. **Verification Matrix (MC-1 & MC-5):**
   - **Legacy Binding Pruned:**
     ```bash
     $ kubectl --context k3d-hub-cluster get clusterrolebinding headlamp-admin
     Error from server (NotFound): clusterrolebindings.rbac.authorization.k8s.io "headlamp-admin" not found
     ```
   - **Pod Automount Disabled:**
     ```bash
     $ kubectl --context k3d-hub-cluster -n headlamp get pod -l app.kubernetes.io/name=headlamp -o jsonpath='{"automountServiceAccountToken: "}{.items[0].spec.automountServiceAccountToken}{"\nvolumes: "}{.items[0].spec.volumes[*].name}'
     automountServiceAccountToken: false
     volumes: kubeconfig
     ```
     (Zero `kube-api-access-*` token volumes mounted).
   - **Container Args:** `-insecure-ssl` completely removed; container runs strictly with `-dev` and mounted kubeconfig.
   - **Least-Privilege `auth can-i` Matrix (MC-5):**
     Tested across all 3 clusters for `system:serviceaccount:headlamp-access:headlamp-viewer`:
     | Cluster | `get pods/log` | `list queues.sqs...` | `list rgd.kro.run` | `get secrets` | `create deployments` | `delete namespaces` |
     |---|:---:|:---:|:---:|:---:|:---:|:---:|
     | `k3d-hub-cluster` | ✅ yes | *(CRD not on hub)* | *(CRD not on hub)* | ❌ no | ❌ no | ❌ no |
     | `k3d-spoke-nonprod` | ✅ yes | ✅ yes | ✅ yes | ❌ no | ❌ no | ❌ no |
     | `k3d-spoke-prod` | ✅ yes | ✅ yes | ✅ yes | ❌ no | ❌ no | ❌ no |
   - **Headlamp Ingress:** Responding HTTP 200 at `http://headlamp.localhost:8080/`. Backend logs confirm successful multi-cluster proxy setup for all 3 clusters with zero TLS errors.

---

### Step 9: Workload NetworkPolicy via Kro RGD (L4-3, MC-2)

1. **RGD Definition (MC-2):**
   Edited `blueprints/queue-backed-service-rgd.yaml` in `platform-catalog`. Appended `networkpolicy` resource (omitting `metadata.namespace`, allowing Kro to place it in the instance namespace):
   ```yaml
   - id: networkpolicy
     template:
       apiVersion: networking.k8s.io/v1
       kind: NetworkPolicy
       metadata:
         name: ${schema.spec.name}-${schema.spec.environment}-netpol
         labels:
           app: ${schema.spec.name}-${schema.spec.environment}-worker
           environment: ${schema.spec.environment}
         ownerReferences:
           - apiVersion: kro.run/v1alpha1
             kind: ${schema.kind}
             name: ${schema.metadata.name}
             uid: ${schema.metadata.uid}
             controller: true
             blockOwnerDeletion: true
       spec:
         podSelector:
           matchLabels:
             app: ${schema.spec.name}-${schema.spec.environment}-worker
         policyTypes:
           - Ingress
           - Egress
         ingress:
           - from:
               - namespaceSelector:
                   matchLabels:
                     kubernetes.io/metadata.name: kube-system
                 podSelector:
                   matchLabels:
                     app.kubernetes.io/name: traefik
               - podSelector: {}
             ports:
               - protocol: TCP
                 port: 8080
         egress:
           - to:
               - namespaceSelector: {}
                 podSelector:
                   matchLabels:
                     k8s-app: kube-dns
             ports:
               - protocol: UDP
                 port: 53
               - protocol: TCP
                 port: 53
           - to:
               - ipBlock:
                   cidr: 172.21.0.0/16
             ports:
               - protocol: TCP
                 port: 5000
   ```
2. **Non-Prod Validation:**
   Committed and pushed to `platform-catalog@main` (`commit 7fab51d`). Synced `kro-blueprints-spoke-nonprod`.
   - RGD `queuebackedservice` remained `Active` (True).
   - Kro stamped out `orders-dev-netpol` and `orders-test-netpol`.
   - **Connectivity Tests from Worker Pod:**
     - DNS resolution (`moto-cloud` -> `172.21.0.9`): ✅ Success.
     - Moto Cloud egress (`http://moto-cloud:5000/`): ✅ HTTP 200.
     - External egress (`1.1.1.1:443`, `8.8.8.8:80`): ❌ Blocked (Connection refused / timeout).
     - Traefik ingress (`http://orders-dev.localhost:8081/`): ✅ HTTP 200.
     - Unselected pod in same namespace: ✅ Unaffected.
     - Pod health: 0 restarts over multiple liveness periods.
3. **Production Promotion Lifecycle:**
   - Tagged release `v1.2.0` in `platform-catalog` and pushed tag.
   - Updated `clusters/blueprint-revisions.env` in `gitops-control-plane` (`spoke-prod=v1.2.0`) and committed.
   - Promoted via `bash scripts/promote-blueprints.sh spoke-prod`.
   - Synced `kro-blueprints-spoke-prod` in Argo CD.
   - Kro stamped out `orders-prod-netpol` on `k3d-spoke-prod`.
   - Traefik ingress to prod (`http://orders-prod.localhost:8082/`): ✅ HTTP 200.

---

### Step 11: Production Workload Promotion Gate (L2-2, MC-3)

1. **Parameterize `valuesRevision` in List Generator:**
   Updated `applicationsets/tenant-workloads-prod.yaml` in `gitops-control-plane` (`commit 81e4cb6`):
   ```yaml
   spec:
     generators:
       - list:
           elements:
             - app: orders
               tenant: tenant-a
               env: prod
               port: "8082"
               valuesRevision: ca4797acbed28ea7a6a5caf23d591ea30d953d08
   ```
2. **Pin Template TargetRevision:**
   ```yaml
   sources:
     - chart: queue-backed-service
       repoURL: ghcr.io/brunobml/charts
       targetRevision: 1.0.0
       helm:
         valueFiles:
           - $values/deploy/values-{{env}}.yaml
     - repoURL: https://github.com/brunobml/orders-processor.git
       targetRevision: '{{valuesRevision}}'
       ref: values
   ```
   Preserved `syncPolicy.automated: {prune: true, selfHeal: true}`.
3. **Live Divergence Verification (MC-3):**
   - Synced `root-control-plane` and `orders-prod`. Verified application spec and status:
     ```json
     spec.sources.targetRevisions: ["1.0.0", "ca4797acbed28ea7a6a5caf23d591ea30d953d08"]
     status.sync.status: Synced / Healthy
     ```
   - Pushed test commit `c594f1b` to `orders-processor@main`. Refreshed all applications:
     - `orders-dev`: sync revision moved to `c594f1b` ✅
     - `orders-test`: sync revision moved to `c594f1b` ✅
     - `orders-prod`: sync revision **remained strictly pinned to `ca4797a`** ✅
   - Reset test commit on `orders-processor@main` back to `ca4797a` cleanly.

---

## 3. Multi-Cluster Smoke Test Results

Executed `bash scripts/smoke-test-hub-spoke.sh`:

```text
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

## 4. Conclusion & Next Steps

Phase 2 implementation is complete across all four tracks:
1. **Supply Chain & Provenance (L3-5 / PV-1 / MC-4):** Workloads run verified GHCR digest `3fc6e216...` with commit `8f5e0b6`; node image cache purged; CI metadata retains `v` prefix.
2. **Promotion Preflight (X-1 / PV-2):** Enforces exact sync between local `HEAD` and `origin/main`.
3. **Headlamp Gateway Overhaul (L4-1 Mitigated / MC-1 / MC-5):** Full least-privilege RBAC, automount token disabled, strict CA TLS verification, `headlamp-admin` deleted.
4. **Workload Security Baseline (L4-3 / MC-2):** Pod Security Standards `restricted` enforced; Kro RGD default-deny NetworkPolicy active on both spokes.
5. **Production Promotion Gate (L2-2 / MC-3):** `orders-prod` pinned to immutable commit SHA with self-heal active; non-prod follows `main`.

Phase 2 is ready for independent validation (Validation Run #02).
