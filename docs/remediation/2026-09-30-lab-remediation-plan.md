# Lab Remediation Plan: Low-Severity Findings & Hardening
## Hub-and-Spoke GitOps Control Plane (2026-09-30)

* **Plan Version:** 2.1 (Incorporating [Plan Review v2.0](2026-09-30-lab-remediation-plan-review.md))
* **Assessment Reference:** [`../assessments/2026-09-30-lab-assessment.md`](../assessments/2026-09-30-lab-assessment.md)
* **Target Repositories:** `gitops-control-plane`, `platform-catalog`, `platform-charts`, `orders-processor`, `tenant-workloads`

---

## 1. Executive Summary & Scope

This plan addresses the **7 Low-Severity findings** (`L1-2`, `L1-3`, `L1-6`, `L2-7`, `L3-8`, `L4-10`, `L4-11`) identified during the architectural assessment, establishing a clean, portable, and secure foundation.

### Scope Framing & Sequencing Relative to High/Critical Findings
Resolving these low-severity items eliminates technical debt and stale state, enabling safe subsequent execution of the **Critical and High findings**:
1. **L4-1 (Critical)**: Headlamp unauthenticated cluster-admin access (decouple tokens, add view-only SA).
2. **L3-1 (High)**: ACK 10-hour cloud drift detection gap (lower resync period to 300s).
3. **L3-5 (High)**: CI pipeline mutable tag overwrite (implement immutable SemVer & commit SHA tags).
4. **L2-2 (High)**: Production promotion gate (separate prod sync windows & branch/tag tracking).

---

## 2. Itemized Analysis: Actions, Agreements & Nuances

| Finding | Topic | Action Summary | Agreement | Key Nuance & Review Refinements |
| :--- | :--- | :--- | :--- | :--- |
| **L1-2** | Hygiene | Back up and delete orphaned `messageprocessors.kro.run` CRD on both spokes. | **Agree** | **Loud failure is safer (R5)**: Deleting the CRD immediately causes stale manifests to fail loudly rather than silently no-op. Back up YAML to `/tmp` before deletion. |
| **L1-3** | Runtime | Remove 3 stray Headlamp Docker containers (`docker rm -f`). | **Agree** | **Zero residual risk (R14)**: Containers run on the default Docker bridge, and the mounted `/tmp/headlamp-test/kubeconfig` was already deleted. |
| **L1-6** | Portability | Parameterize `Makefile` (`ROOT_DIR`/`REPOS_DIR`) and replace all `/home/bleite` paths across 7 files. | **Agree** | Covers all 7 active files (Makefile, README, and 5 docs). Verified via scriptable `git grep` with pathspecs (N2, N8). |
| **L2-7** | GitOps | Delete duplicate manual secret `repo-ghcr-charts` in `argocd`. | **Agree** | **Verified identical & public (R7)**: Both secrets lack credentials and point to public OCI GHCR. Hard-refresh `orders-dev` with blocking CLI to prove cache independence (N11). |
| **L3-8** | Extensibility | Defer imperative script refactor; couple with GitOps Addons (L2-1 / Rec 9). | **Agree** | Skip throwaway script parameterization (R9); resolve controller lifecycle natively via ApplicationSets with sync-wave ordering. |
| **L4-10** | Security | Defer TokenRequest migration for local lab; eliminate plaintext token annotation; document TokenRequest roadmap. | **Agree** | Local k3d lacks IAM. Use `apply --server-side` to eliminate plaintext tokens in `last-applied-configuration` (N6). Record TokenRequest middle path in docs (R8). |
| **L4-11** | Security | Harden workload pods: dedicated SA referenced in pod spec, seccomp RuntimeDefault, read-only root FS, conditional PDB. | **Agree** | Set `serviceAccountName: ${serviceaccount.metadata.name}` in Deployment spec (N1). Use `includeWhen: [ ${schema.spec.replicas > 1} ]` on PDB (R1). Skip Dockerfile edits to avoid mutable tag rebuilds (N7). Add staged blueprint rollout (N3, N4, N5). |

---

## 3. Detailed Technical Remediation

### Finding L1-2: Orphaned CRD `messageprocessors.kro.run`
* **Root Cause**: The ResourceGraphDefinition was deleted in `platform-catalog@4987050`, but kro preserves generated CRDs to prevent accidental data loss.
* **Pre-Check Verification**: Confirmed zero `MessageProcessor` instances and zero `GraphRevision` references on both spokes (`kubectl get messageprocessors.kro.run -A` returns empty).
* **Action**:
  ```bash
  # 1. Back up CRD definition prior to deletion
  kubectl --context k3d-spoke-nonprod get crd messageprocessors.kro.run -o yaml > /tmp/mp-crd-nonprod.yaml
  kubectl --context k3d-spoke-prod get crd messageprocessors.kro.run -o yaml > /tmp/mp-crd-prod.yaml

  # 2. Delete the orphaned CRD on both workload clusters
  kubectl --context k3d-spoke-nonprod delete crd messageprocessors.kro.run
  kubectl --context k3d-spoke-prod delete crd messageprocessors.kro.run
  ```
* **Review Alignment (R5 & R6)**: Deleting the CRD first is the safer order because a stale CRD without an RGD accepts manifests silently without reconciling them. A loud admission rejection (`no matches for kind "MessageProcessor"`) forces immediate visibility.

---

### Finding L1-3: Stray Headlamp Docker Containers
* **Root Cause**: Containers `elastic_kapitsa`, `affectionate_dubinsky`, and `friendly_lalande` were started directly via `docker run` during early UI testing before Traefik ingress was active on Hub.
* **Security & Resource Context (R14)**: The containers run on the default Docker bridge, detached from `k3d-cloud-net`. The temporary host kubeconfig (`/tmp/headlamp-test/kubeconfig`) has already been deleted.
* **Action**:
  ```bash
  docker rm -f elastic_kapitsa affectionate_dubinsky friendly_lalande
  ```

---

### Finding L1-6: Repository & Documentation Path Portability
* **Root Cause**: Hard-coded personal paths (`/home/bleite/...`) and absolute `file:///` URLs were embedded across repository files.
* **Full Scope Coverage (R3, N8)**: 7 active files in total (Makefile, README, and 5 documentation files; note `tenant-workloads/developer-tutorial.md` will be archived under L1-4):
  1. **`Makefile` (R4)**:
     ```makefile
     ROOT_DIR  := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
     REPOS_DIR ?= $(abspath $(ROOT_DIR)/..)
     ORDERS_DIR ?= $(REPOS_DIR)/orders-processor

     build-app:
     	@bash $(ORDERS_DIR)/build-and-push.sh $(TAG)
     ```
     *(Uses `lastword $(MAKEFILE_LIST)` instead of `CURDIR` so `make -f` works reliably).*
  2. **`README.md` (R12)**: Replace `/home/bleite/repos/...` with relative directory navigation; update repo list from 3 to 5 repos (`gitops-control-plane`, `platform-catalog`, `platform-charts`, `orders-processor`, `tenant-workloads`).
  3. **Documentation Links (N9)**: Convert absolute `file:///home/bleite/...` URLs to standard relative markdown links within the repository, and use full GitHub HTTPS URLs for cross-repository links (e.g. `https://github.com/brunobml/platform-catalog/blob/main/blueprints/queue-backed-service-rgd.yaml`):
     - `docs/developer-tutorial.md`
     - `docs/production-promotion-guardrails.md`
     - `docs/lab-progression-and-next-steps.md`
     - `addons/headlamp/README.md`
     - `docs/remediation/2026-09-30-lab-remediation-plan.md`
* **Automated Verification Check (N2)**:
  ```bash
  ! git grep -nE 'file:///|/home/bleit[e]' -- ':!docs/assessments' ':!docs/remediation'
  ```

---

### Finding L2-7: Duplicate Helm Repo Secret
* **Root Cause**: Both `argocd-repo-ghcr-charts` (Helm managed) and `repo-ghcr-charts` (manual) exist in `argocd` namespace for `ghcr.io/brunobml/charts`.
* **Verification (R7)**: Both secrets are identical, neither contains credentials, and `ghcr.io/brunobml/charts/queue-backed-service:1.0.0` is public (HTTP 200 anonymous).
* **Action (N11)**:
  ```bash
  # 1. Delete unmanaged duplicate secret
  kubectl --context k3d-hub-cluster -n argocd delete secret repo-ghcr-charts

  # 2. Force hard-refresh and verify condition is empty
  argocd app get orders-dev --hard-refresh || kubectl --context k3d-hub-cluster -n argocd patch app orders-dev --type merge -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'
  kubectl --context k3d-hub-cluster -n argocd get app orders-dev -o jsonpath='{.status.conditions}'
  ```
* **Forward-Looking Note**: If the Helm chart registry ever becomes private, credentials must be managed via an external secret store (ESO / Sealed Secrets), never plaintext in Git values.

---

### Finding L3-8: Extensibility & Controller Lifecycle
* **Decision (R9)**: **Skip throwaway script parameterization.**
* **Rationale**: Parameterizing `setup-hub-spoke.sh` with `ACK_SERVICES=("sqs")` adds little value because each ACK service requires independent chart versions, CRDs, and values files.
* **Target Architecture**: Migrate all controllers (kro, ACK SQS, Traefik) into an `addons/` ApplicationSet under Recommendation 9. CRDs are bundled with charts and applied first; the only inter-resource dependency is `ack-aws-creds`, which will be ordered via `argocd.argoproj.io/sync-wave: "-1"`.

---

### Finding L4-10: ServiceAccount Token Lifecycle & Plaintext Secret Scrubbing
* **Decision (R8, N6)**: **Eliminate plaintext token annotations now; document TokenRequest roadmap.**
* **Plaintext Token Remediation (N6)**:
  `kubectl apply -f` with `stringData` records the plaintext bearer token in `metadata.annotations["kubectl.kubernetes.io/last-applied-configuration"]`.
  1. Update `scripts/register-spokes.sh` and `addons/headlamp/setup-credentials.sh` to use `kubectl apply --server-side`, which does **not** generate `last-applied-configuration`.
  2. Rotate spoke tokens using TokenRequest API (30-day lifetime):
     ```bash
     token=$(kubectl --context "$context" -n kube-system create token argocd-manager --duration=720h)
     ```
  3. Re-run `register-spokes.sh` and `setup-credentials.sh`.
* **Documented Next Step**: Record static token trade-offs and the EKS Access Entries / IRSA end-state in [`docs/aws-well-architected-production-guide.md`](../aws-well-architected-production-guide.md).

---

### Finding L4-11: Workload Pod Hardening & Staged Rollout
* **Blueprint Enhancements in [`platform-catalog/blueprints/queue-backed-service-rgd.yaml`](https://github.com/brunobml/platform-catalog/blob/main/blueprints/queue-backed-service-rgd.yaml)**:
  1. **Dedicated ServiceAccount & Pod Assignment (N1)**:
     ```yaml
     - id: serviceaccount
       template:
         apiVersion: v1
         kind: ServiceAccount
         metadata:
           name: ${schema.spec.name}-${schema.spec.environment}
         automountServiceAccountToken: false

     - id: deployment
       template:
         apiVersion: apps/v1
         kind: Deployment
         spec:
           template:
             spec:
               serviceAccountName: ${serviceaccount.metadata.name}
               automountServiceAccountToken: false
     ```
     *(Referencing `${serviceaccount.metadata.name}` creates the DAG edge in kro so the SA is provisioned before the Deployment).*

  2. **Pod Security & Read-Only Root Filesystem**:
     ```yaml
     spec:
       template:
         spec:
           securityContext:
             runAsNonRoot: true
             runAsUser: 10001
             runAsGroup: 10001
             fsGroup: 10001
             seccompProfile:
               type: RuntimeDefault
           containers:
             - name: app
               securityContext:
                 readOnlyRootFilesystem: true
                 allowPrivilegeEscalation: false
                 capabilities:
                   drop: [ALL]
               volumeMounts:
                 - name: tmp
                   mountPath: /tmp
           volumes:
             - name: tmp
               emptyDir: {}
     ```

  3. **Conditional PodDisruptionBudget (R1)**:
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

  4. **Application Runtime (N7)**:
     *Do NOT touch `orders-processor` Dockerfile or push to `main`.* The Python application uses only standard library modules and does not write to disk; skipping this avoids triggering CI and overwriting mutable tags (`v1.1.0`/`v1.2.0`).

* **Staged Rollout & Promotion Strategy (N3, N4, N5, N13)**:
  1. **Step 5a (Tag Baseline)**: Create tag `v1.0.0` at current commit `a8825b2` in `platform-catalog` and push to GitHub (N3):
     ```bash
     git -C ../platform-catalog tag -a v1.0.0 a8825b2 -m "Blueprint baseline currently running on spoke-prod"
     git -C ../platform-catalog push origin v1.0.0
     ```
  2. **Step 5b (Annotate Cluster Secrets)**:
     Update `register-spokes.sh` to write `blueprints-revision` annotations on the cluster Secrets (`cluster-spoke-nonprod: main`, `cluster-spoke-prod: v1.0.0`).
  3. **Step 5c (AppSet Wiring)**:
     Update `applicationsets/kro-blueprints.yaml`:
     ```yaml
     targetRevision: '{{metadata.annotations.blueprints-revision}}'
     ```
     Because tag `v1.0.0` was pushed in Step 5a, Argo CD syncs without any `ComparisonError` window (N13).
  4. **Step 6 (Non-Prod Verification)**:
     Commit RGD hardening to `platform-catalog@main`. Non-prod syncs. Verify pods running and test PSS restricted compliance:
     ```bash
     kubectl --context k3d-spoke-nonprod label --dry-run=server --overwrite ns orders-dev \
       pod-security.kubernetes.io/enforce=restricted
     ```
  5. **Step 7 (Prod Promotion & Rollback)**:
     - **Promotion**: Create a **new** tag `v1.1.0` (never move existing tags per N4):
       ```bash
       git -C ../platform-catalog tag -a v1.1.0 -m "Hardened blueprint with dedicated SA, seccomp, and conditional PDB"
       git -C ../platform-catalog push origin v1.1.0
       ```
       Update `cluster-spoke-prod` annotation to `v1.1.0`.
     - **Rollback Path (N5)**:
       - **Prod**: Repoint `cluster-spoke-prod` annotation back to `v1.0.0` (rolls back within seconds upon refresh).
       - **Non-prod**: `git revert` on `platform-catalog@main`; kro creates a new `GraphRevision` (`queuebackedservice-r00006`) within one poll cycle.

---

## 4. Revised Step-by-Step Execution Schedule

| Step | Action | Execution Details | Done When |
| :---: | :--- | :--- | :--- |
| **1** | **Low-risk cleanup** (L1-2, L1-3) | Back up CRD to `/tmp`; delete `messageprocessors.kro.run` on both spokes; `docker rm -f elastic_kapitsa affectionate_dubinsky friendly_lalande` | `kubectl get crd messageprocessors.kro.run` returns NotFound; `docker ps -a` clean |
| **2** | **Secret cleanup** (L2-7) | Delete manual secret `repo-ghcr-charts`; hard-refresh `orders-dev` via CLI | `argocd-repo-ghcr-charts` is sole secret; app condition has no errors; Synced/Healthy |
| **3** | **Portability fixes** (L1-6, N2, N8) | Update `Makefile` (`ROOT_DIR`/`REPOS_DIR`); update `README.md` (relative paths, 5 repos); remove `/home/bleite` across all 7 files | Automated check passes: `! git grep -nE 'file:///\|/home/bleit[e]' -- ':!docs/assessments' ':!docs/remediation'` |
| **4** | **Documentation sync** (L1-5) | Update `docs/developer-tutorial.md` with `QueueBackedService`, `orders-*` names, and 2 prod replicas | Tutorial instructions match live cluster state |
| **5a**| **Tag baseline blueprint** (N3) | Tag `platform-catalog@a8825b2` as `v1.0.0` and push to GitHub | `git tag -l` shows `v1.0.0` on GitHub |
| **5b**| **Cluster Secret annotations & token scrub** (N4, N6) | Add `blueprints-revision` annotations to `register-spokes.sh`; apply with `--server-side`; rotate `argocd-manager` tokens; re-run `setup-credentials.sh` | Cluster secrets have annotations (`nonprod: main`, `prod: v1.0.0`); `last-applied-configuration` absent |
| **5c**| **AppSet promotion wiring** (N13) | Update `applicationsets/kro-blueprints.yaml` `targetRevision` to `{{metadata.annotations.blueprints-revision}}` | Non-prod tracks `main`; prod tracks `v1.0.0`; zero `ComparisonError` |
| **6** | **Harden platform blueprint** (L4-11, N1) | Update `queue-backed-service-rgd.yaml` (SA automount false, `serviceAccountName` assigned, seccomp RuntimeDefault, readOnlyRootFilesystem, conditional PDB) | Non-prod pods `Running` with 0 restarts; SA assigned; no `kube-api-access` volume; PSS dry-run returns no warnings; dev PDB absent |
| **7** | **Promote blueprint to prod** (N4, N5) | Create new tag `v1.1.0` in `platform-catalog`; update `cluster-spoke-prod` annotation to `v1.1.0` | `orders-prod` rolls out cleanly; PDB present on prod (2 replicas); Synced/Healthy |
| **8** | **Document trade-offs** (L4-10) | Document static tokens as local lab trade-off with TokenRequest / EKS Access Entries roadmap in Well-Architected guide | Security section of `aws-well-architected-production-guide.md` updated |

---

## 5. Verification Checklist

Execute after completing Steps 1–8:

```bash
# 1. Clean containers
docker ps --filter "name=elastic_kapitsa|affectionate_dubinsky|friendly_lalande"

# 2. Clean CRDs
kubectl --context k3d-spoke-nonprod get crd messageprocessors.kro.run 2>&1 | grep -q "NotFound" && echo "Nonprod Clean"
kubectl --context k3d-spoke-prod get crd messageprocessors.kro.run 2>&1 | grep -q "NotFound" && echo "Prod Clean"

# 3. Single repo secret
kubectl --context k3d-hub-cluster -n argocd get secrets -l argocd.argoproj.io/secret-type=repository

# 4. Zero hardcoded paths (N2)
! git grep -nE 'file:///|/home/bleit[e]' -- ':!docs/assessments' ':!docs/remediation'

# 5. Pod Security Standard restricted compliance dry-run
kubectl --context k3d-spoke-nonprod label --dry-run=server --overwrite ns orders-dev pod-security.kubernetes.io/enforce=restricted

# 6. ServiceAccount assigned and token unmounted on workload pod (N1, N12)
kubectl --context k3d-spoke-nonprod -n orders-dev get pod -l app=orders-dev-worker -o jsonpath='{.items[0].spec.serviceAccountName}'
# Verify no kube-api-access volume is mounted:
! kubectl --context k3d-spoke-nonprod -n orders-dev get pod -l app=orders-dev-worker -o jsonpath='{.items[0].spec.volumes[*].name}' | grep -q kube-api-access

# 7. Conditional PDB check
kubectl --context k3d-spoke-nonprod -n orders-dev get pdb # (should be empty - 1 replica)
kubectl --context k3d-spoke-prod -n orders-prod get pdb    # (should exist - 2 replicas)

# 8. Token annotation scrub check (N6)
kubectl --context k3d-hub-cluster -n argocd get secret cluster-spoke-prod -o jsonpath='{.metadata.annotations.kubectl\.kubernetes\.io/last-applied-configuration}' # (should be empty)

# 9. All Argo CD applications Synced and Healthy
kubectl --context k3d-hub-cluster -n argocd get applications
```
