# Lab Remediation Plan: Low-Severity Findings & Hardening
## Hub-and-Spoke GitOps Control Plane (2026-09-30)

* **Plan Version:** 2.0 (Updated following [Remediation Plan Review](2026-09-30-lab-remediation-plan-review.md))
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
| **L1-2** | Hygiene | Back up and delete orphaned `messageprocessors.kro.run` CRD on both spokes. | **Agree** | **Loud failure is safer**: Deleting the CRD immediately causes stale manifests to fail loudly rather than silently no-op. Back up YAML to `/tmp` before deletion. |
| **L1-3** | Runtime | Remove 3 stray Headlamp Docker containers (`docker rm -f`). | **Agree** | **Zero residual risk**: Containers run on the default Docker bridge, and the mounted `/tmp/headlamp-test/kubeconfig` was already deleted. |
| **L1-6** | Portability | Parameterize `Makefile` (`ROOT_DIR`/`REPOS_DIR`) and replace all `/home/bleite` paths across 7 files. | **Agree** | Must cover all 7 active files (including docs, Makefile, and this plan). Verify via automated scriptable grep. |
| **L2-7** | GitOps | Delete duplicate manual secret `repo-ghcr-charts` in `argocd`. | **Agree** | **Verified identical & public**: Both secrets lack credentials and point to public OCI GHCR. Hard-refresh `orders-dev` to prove cache independence. |
| **L3-8** | Extensibility | Defer imperative script refactor; couple with GitOps Addons (L2-1 / Rec 9). | **Agree** | Skip throwaway script parameterization; resolve controller lifecycle natively via ApplicationSets with sync-wave ordering. |
| **L4-10** | Security | Defer TokenRequest migration for local lab; document TokenRequest middle path. | **Agree** | Local k3d lacks IAM/EKS Access Entries. Accept static tokens as a documented lab trade-off; record 30-day TokenRequest middle path in docs. |
| **L4-11** | Security | Harden workload pods: dedicated SA, automount false, seccomp RuntimeDefault, read-only root FS, conditional PDB. | **Agree** | Use kro `includeWhen: [ ${schema.spec.replicas > 1} ]` on PDB; place `PYTHONDONTWRITEBYTECODE` in Dockerfile; add staged blueprint promotion gate. |

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
* **Full Scope Coverage (R3)**:
  1. `Makefile`:
     ```makefile
     ROOT_DIR  := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
     REPOS_DIR ?= $(abspath $(ROOT_DIR)/..)
     ORDERS_DIR ?= $(REPOS_DIR)/orders-processor

     build-app:
     	@bash $(ORDERS_DIR)/build-and-push.sh $(TAG)
     ```
     *(R4: Uses `lastword $(MAKEFILE_LIST)` instead of `CURDIR` so `make -f` works reliably).*
  2. `README.md`: Replace `/home/bleite/repos/...` with relative directory navigation; update repo list from 3 to 5 repos (`gitops-control-plane`, `platform-catalog`, `platform-charts`, `orders-processor`, `tenant-workloads`) (R12).
  3. Documentation Links: Convert absolute `file:///home/bleite/...` URLs to standard relative markdown links across:
     - `docs/developer-tutorial.md`
     - `docs/production-promotion-guardrails.md`
     - `docs/lab-progression-and-next-steps.md`
     - `addons/headlamp/README.md`
     - `docs/remediation/2026-09-30-lab-remediation-plan.md`

---

### Finding L2-7: Duplicate Helm Repo Secret
* **Root Cause**: Both `argocd-repo-ghcr-charts` (Helm managed) and `repo-ghcr-charts` (manual) exist in `argocd` namespace for `ghcr.io/brunobml/charts`.
* **Verification (R7)**: Both secrets are identical, neither contains credentials, and `ghcr.io/brunobml/charts/queue-backed-service:1.0.0` is public (HTTP 200 anonymous).
* **Action**:
  ```bash
  # Delete unmanaged duplicate secret
  kubectl --context k3d-hub-cluster -n argocd delete secret repo-ghcr-charts

  # Force hard-refresh to verify un-cached reconciliation
  kubectl --context k3d-hub-cluster -n argocd patch app orders-dev --type merge -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'
  kubectl --context k3d-hub-cluster -n argocd get app orders-dev -o jsonpath='{.status.conditions}'
  ```
* **Forward-Looking Note**: If the Helm chart registry ever becomes private, credentials must be managed via an external secret store (ESO / Sealed Secrets), never plaintext in Git values.

---

### Finding L3-8: Extensibility & Controller Lifecycle
* **Decision (R9)**: **Skip throwaway script parameterization.**
* **Rationale**: Parameterizing `setup-hub-spoke.sh` with `ACK_SERVICES=("sqs")` adds little value because each ACK service requires independent chart versions, CRDs, and values files.
* **Target Architecture**: Migrate all controllers (kro, ACK SQS, Traefik) into an `addons/` ApplicationSet under Recommendation 9. CRDs are bundled with charts and applied first; the only inter-resource dependency is `ack-aws-creds`, which will be ordered via `argocd.argoproj.io/sync-wave: "-1"`.

---

### Finding L4-10: ServiceAccount Token Lifecycle
* **Decision (R8)**: **Defer replacement for local lab; document the TokenRequest middle path.**
* **Lab Reality**: Local k3d clusters lack native AWS IAM / EKS Access Entries. Full rotation via external daemons adds friction without teaching core GitOps concepts.
* **Documented Next Step (TokenRequest Middle Path)**:
  ```bash
  # Time-bound (30-day) token generation for spoke registration:
  token=$(kubectl --context "$context" -n kube-system create token argocd-manager --duration=720h)
  ```
  This pattern allows rotating spoke tokens on demand via `make rotate-spoke-tokens` and naturally decouples Headlamp to its own dedicated `view` ClusterRole. Record this in [`docs/aws-well-architected-production-guide.md`](aws-well-architected-production-guide.md).

---

### Finding L4-11: Workload Pod Hardening & Staged Rollout
* **Blueprint Enhancements in [`platform-catalog/blueprints/queue-backed-service-rgd.yaml`](../../platform-catalog/blueprints/queue-backed-service-rgd.yaml)**:
  1. **Dedicated ServiceAccount**:
     ```yaml
     apiVersion: v1
     kind: ServiceAccount
     metadata:
       name: ${schema.spec.name}-${schema.spec.environment}-sa
     automountServiceAccountToken: false
     ```
  2. **Pod Security & Filesystem**:
     ```yaml
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
  4. **Application Runtime (R10)**: Put `ENV PYTHONDONTWRITEBYTECODE=1` in `orders-processor/Dockerfile`, keeping the platform contract runtime-agnostic.

* **Staged Rollout & Rollback Gate (R2)**:
  Currently `kro-blueprints` tracks `main` across both clusters, causing immediate rollout to prod.
  1. Add annotation to cluster Secrets on Hub:
     - `k3d-spoke-nonprod`: `blueprints-revision: main`
     - `k3d-spoke-prod`: `blueprints-revision: v1.0.0` (pinned tag)
  2. Update `applicationsets/kro-blueprints.yaml`:
     ```yaml
     targetRevision: '{{metadata.annotations.blueprints-revision}}'
     ```
  3. Apply changes to `platform-catalog@main` ➔ deploys and verifies on `nonprod` (`orders-dev`, `orders-test`).
  4. Validate PSS compliance via dry run (R10):
     ```bash
     kubectl --context k3d-spoke-nonprod label --dry-run=server --overwrite ns orders-dev \
       pod-security.kubernetes.io/enforce=restricted
     ```
  5. Promote to production by moving the git tag `v1.1.0` and updating `k3d-spoke-prod` cluster secret.
  6. **Rollback Plan**: `git revert` on `platform-catalog` reverts the RGD; kro automatically restores the previous `GraphRevision` in under 5 seconds.

---

## 4. Revised Step-by-Step Execution Schedule

| Step | Action | Execution Details | Done When |
| :---: | :--- | :--- | :--- |
| **1** | **Low-risk cleanup** (L1-2, L1-3) | Back up CRD to `/tmp`; delete `messageprocessors.kro.run` on both spokes; `docker rm -f elastic_kapitsa affectionate_dubinsky friendly_lalande` | `kubectl get crd messageprocessors.kro.run` returns NotFound; `docker ps -a` clean |
| **2** | **Secret cleanup** (L2-7) | Delete manual secret `repo-ghcr-charts`; hard-refresh `orders-dev` | `argocd-repo-ghcr-charts` is sole secret; app condition has no errors; Synced/Healthy |
| **3** | **Portability fixes** (L1-6) | Update `Makefile` (`ROOT_DIR`/`REPOS_DIR`); update `README.md` (relative paths, 5 repos); remove `/home/bleite` across all 7 markdown files | Automated check passes: `! grep -rn 'file:///\|/home/bleite' --include=*.md --include=Makefile --include=*.sh . ':!docs/assessments'` |
| **4** | **Documentation sync** (L1-5) | Update `docs/developer-tutorial.md` with `QueueBackedService`, `orders-*` names, and 2 prod replicas | Tutorial instructions match live cluster state |
| **5** | **Blueprint promotion gate** (R2) | Add `blueprints-revision` annotation to cluster Secrets; update `kro-blueprints` AppSet `targetRevision` | Non-prod tracks `main`; prod tracks pinned tag `v1.0.0` |
| **6** | **Harden platform blueprint** (L4-11) | Update `queue-backed-service-rgd.yaml` (SA automount false, seccomp RuntimeDefault, readOnlyRootFilesystem, conditional PDB) | Non-prod pods `Running` with 0 restarts; PSS restricted dry-run returns no warnings |
| **7** | **Promote blueprint to prod** (R2) | Tag release `v1.1.0` in `platform-catalog`; update prod cluster secret annotation | `orders-prod` rolls out cleanly; PDB present on prod (2 replicas); zero dev PDB |
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

# 4. Zero hardcoded paths
! grep -rn 'file:///\|/home/bleite' --include=*.md --include=Makefile --include=*.sh . ':!docs/assessments'

# 5. Pod Security Standard restricted compliance (dry-run)
kubectl --context k3d-spoke-nonprod label --dry-run=server --overwrite ns orders-dev pod-security.kubernetes.io/enforce=restricted

# 6. ServiceAccount token unmounted on workload pod
kubectl --context k3d-spoke-nonprod -n orders-dev get pod -l app=orders-dev-worker -o jsonpath='{.items[0].spec.serviceAccountName}'
# Verify no kube-api-access volume is mounted:
kubectl --context k3d-spoke-nonprod -n orders-dev get pod -l app=orders-dev-worker -o jsonpath='{.items[0].spec.volumes[*].name}' | grep -v "kube-api-access"

# 7. Conditional PDB check
kubectl --context k3d-spoke-nonprod -n orders-dev get pdb # (should be empty - 1 replica)
kubectl --context k3d-spoke-prod -n orders-prod get pdb    # (should exist - 2 replicas)

# 8. All Argo CD applications Synced and Healthy
kubectl --context k3d-hub-cluster -n argocd get applications
```
