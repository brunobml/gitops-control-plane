# Lab Remediation Plan: Low-Severity Findings & Hardening
## Hub-and-Spoke GitOps Control Plane (2026-09-30)

* **Plan Version:** 3.0 (Fully Authorized Version Incorporating [Plan Review v2.1](2026-09-30-lab-remediation-plan-review.md))
* **Assessment Reference:** [`../assessments/2026-09-30-lab-assessment.md`](../assessments/2026-09-30-lab-assessment.md)
* **Target Repositories:** `gitops-control-plane`, `platform-catalog`, `platform-charts`, `orders-processor`, `tenant-workloads`

---

## 1. Executive Summary & Scope

This plan provides actionable, verified remediation for the **7 Low-Severity findings** (`L1-2`, `L1-3`, `L1-6`, `L2-7`, `L3-8`, `L4-10`, `L4-11`) identified during the architectural assessment, while addressing critical credential scrubbing and authorization preconditions highlighted in peer review.

### Scope Framing & Sequencing Relative to High/Critical Findings
Resolving these low-severity items eliminates technical debt, stale state, and credential leakage risks, establishing the clean baseline required before executing the remaining High/Critical roadmap:
1. **Step 0 / Step 5b**: Replaces leaked long-lived static tokens with time-bound TokenRequest credentials and scrubs plaintext annotations, partially completing **L4-1 (Critical)** token decoupling.
2. **L3-1 (High)**: Lowering ACK resync period from 10 hours to 300 seconds (scheduled immediately following this plan).
3. **L3-5 (High)**: CI pipeline immutable SemVer tagging in `orders-processor` (scheduled prior to any new container image releases).
4. **L2-2 (High)**: Production promotion gates and sync windows.

---

## 2. Itemized Analysis: Actions, Agreements & Nuances

| Finding | Topic | Action Summary | Agreement | Key Nuance & Review Refinements |
| :--- | :--- | :--- | :--- | :--- |
| **L1-2** | Hygiene | Back up and delete orphaned `messageprocessors.kro.run` CRD on both spokes. | **Agree** | **Loud failure is safer (R5)**: Stale CRDs without an RGD silently accept manifests without reconciling. Deleting the CRD forces loud, immediate admission rejection. Back up to `/tmp` before delete. |
| **L1-3** | Runtime | Remove 3 stray Headlamp Docker containers (`docker rm -f`). | **Agree** | **Zero residual risk (R14)**: Containers run on the default Docker bridge; temporary host kubeconfig `/tmp/headlamp-test/kubeconfig` was already deleted. |
| **L1-6** | Portability | Parameterize `Makefile` (`ROOT_DIR`/`REPOS_DIR`) and replace all `/home/bleite` paths across 7 active files. | **Agree** | Covers Makefile, README, and 5 documentation files (N8). Verified via scriptable `git grep` with pathspecs (N2). |
| **L2-7** | GitOps | Delete duplicate manual secret `repo-ghcr-charts` in `argocd`. | **Agree** | **Verified identical & public (R7)**: Both secrets lack credentials and point to public OCI GHCR. Use logged-in `argocd app get --hard-refresh` to verify (M1). |
| **L3-8** | Extensibility | Defer imperative script refactor; couple with GitOps Addons (L2-1 / Rec 9). | **Agree** | Skip throwaway script parameterization (R9); resolve controller lifecycle natively via ApplicationSets with sync-wave ordering. |
| **L4-10** | Security | Adopt TokenRequest (30-day) now; scrub plaintext annotations; document EKS end state. | **Agree** | Strip `last-applied-configuration` before server-side apply (B1). Delete legacy token secrets (B2). Record expiry and add `make rotate-spoke-tokens` (S2). Document EKS Access Entries / IRSA end-state. |
| **L4-11** | Security | Harden workload pods: dedicated SA referenced in pod spec, seccomp RuntimeDefault, read-only root FS, conditional PDB. | **Agree** | Set `serviceAccountName: ${serviceaccount.metadata.name}` in Deployment spec (N1). Use `includeWhen: [ ${schema.spec.replicas > 1} ]` on PDB (R1). Skip Dockerfile edits to avoid mutable tag rebuilds (N7). Add staged blueprint rollout (N3, N4, N5, S1). |

---

## 3. Detailed Technical Remediation

### Step 0: Kill Leaked Legacy Tokens & Eliminate Plaintext Secret Annotations (B1, B2, M2)
* **Urgency & Context (B2)**:
  `kubernetes.io/service-account-token` Secrets remain valid until deleted. Furthermore, `kubectl apply -f` with `stringData` records the entire bearer token in plaintext inside `metadata.annotations["kubectl.kubernetes.io/last-applied-configuration"]`.
* **Action Plan**:
  1. **Scrub Plaintext Annotation Before Server-Side Apply (B1)**:
     `apply --server-side` does **not** delete an existing `last-applied-configuration`. We must explicitly strip it first:
     ```bash
     kubectl --context "$HUB_CONTEXT" -n argocd annotate secret "cluster-${spoke}" \
       kubectl.kubernetes.io/last-applied-configuration- 2>/dev/null || true
     kubectl --context "$HUB_CONTEXT" -n argocd apply --server-side --force-conflicts -f -
     ```
  2. **Update `scripts/register-spokes.sh`**:
     - Remove the `Secret argocd-manager-token` document from the spoke-side heredoc. Keep only `ServiceAccount: argocd-manager` and its `ClusterRoleBinding`.
     - Issue time-bound 30-day tokens via TokenRequest:
       ```bash
       token=$(kubectl --context "$context" -n kube-system create token argocd-manager --duration=720h)
       ```
     - Calculate and attach expiry annotation: `lab/token-expires: $(date -d "+30 days" +%Y-%m-%d)` (S2).
     - Read cluster CA data directly from kubeconfig:
       ```bash
       ca_data=$(kubectl config view --raw -o jsonpath='{.clusters[?(@.name=="k3d-'"$spoke"'")].cluster.certificate-authority-data}')
       ```
     - Stagger rotation (M2): rotate `spoke-nonprod` first, verify `argocd cluster list` reports `Successful`, then rotate `spoke-prod`.
  3. **Delete Leaked Legacy Token Secrets**:
     ```bash
     for c in spoke-nonprod spoke-prod; do
       kubectl --context k3d-$c -n kube-system delete secret argocd-manager-token
     done
     # Also scrub Hub Headlamp legacy token secret:
     kubectl --context k3d-hub-cluster -n headlamp delete secret headlamp-token 2>/dev/null || true
     ```
  4. **Update `addons/headlamp/setup-credentials.sh`**:
     - Use TokenRequest for `headlamp` SA on Hub (`kubectl create token headlamp --duration=720h`).
     - Strip `last-applied-configuration` on `headlamp-kubeconfig` and apply server-side.

---

### Finding L1-2: Orphaned CRD `messageprocessors.kro.run`
* **Root Cause**: The RGD was deleted in `platform-catalog@4987050`, but kro preserves generated CRDs.
* **Pre-Check Verification**: Confirmed zero instances and zero GraphRevisions across both clusters (`kubectl get messageprocessors.kro.run -A` is empty).
* **Action**:
  ```bash
  # 1. Back up CRDs prior to deletion
  kubectl --context k3d-spoke-nonprod get crd messageprocessors.kro.run -o yaml > /tmp/mp-crd-nonprod.yaml
  kubectl --context k3d-spoke-prod get crd messageprocessors.kro.run -o yaml > /tmp/mp-crd-prod.yaml

  # 2. Delete the orphaned CRD on both workload clusters
  kubectl --context k3d-spoke-nonprod delete crd messageprocessors.kro.run
  kubectl --context k3d-spoke-prod delete crd messageprocessors.kro.run
  ```

---

### Finding L1-3: Stray Headlamp Docker Containers
* **Action**:
  ```bash
  docker rm -f elastic_kapitsa affectionate_dubinsky friendly_lalande
  ```

---

### Finding L1-6: Repository & Documentation Path Portability
* **Action**:
  1. **`Makefile` (R4)**: Anchor paths to Makefile's location:
     ```makefile
     ROOT_DIR  := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
     REPOS_DIR ?= $(abspath $(ROOT_DIR)/..)
     ORDERS_DIR ?= $(REPOS_DIR)/orders-processor

     build-app:
     	@bash $(ORDERS_DIR)/build-and-push.sh $(TAG)
     ```
  2. **`README.md` (R12)**: Replace `/home/bleite/repos/...` with relative directory navigation; update repo list from 3 to 5 repos (`gitops-control-plane`, `platform-catalog`, `platform-charts`, `orders-processor`, `tenant-workloads`).
  3. **Documentation Links (N9)**: Convert absolute `file:///home/bleite/...` URLs to standard relative markdown links within the repo, and use full GitHub HTTPS URLs for cross-repository links across all 5 docs:
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
* **Verification (R7)**: Both secrets are identical, credential-free, and `ghcr.io/brunobml/charts/queue-backed-service:1.0.0` is public.
* **Action (M1)**:
  ```bash
  # 1. Delete unmanaged duplicate secret
  kubectl --context k3d-hub-cluster -n argocd delete secret repo-ghcr-charts

  # 2. Authenticate CLI and force blocking hard-refresh
  argocd login localhost:8080 --plaintext --grpc-web --username admin --password admin123 || true
  argocd app get orders-dev --hard-refresh
  ```

---

### Finding L3-8: Extensibility & Controller Lifecycle
* **Decision (R9)**: Skip throwaway script parameterization; resolve controller lifecycle natively via ApplicationSets under Recommendation 9 / L2-1.

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
  4. **Application Runtime (N7)**: Do NOT touch `orders-processor` Dockerfile or push to `main` (avoids triggering CI mutable tag overwrite).

* **Staged Rollout & Promotion Strategy (N3, N4, N5, N13, S1)**:
  1. **Single Source of Truth for Blueprint Revisions (S1)**:
     Create `clusters/blueprint-revisions.env` in `gitops-control-plane`:
     ```env
     spoke-nonprod=main
     spoke-prod=v1.0.0
     ```
     `register-spokes.sh` reads this file to set `metadata.annotations["blueprints-revision"]` on `cluster-spoke-*` Secrets.
  2. **Step 5a (Tag Baseline)**: Tag `platform-catalog@a8825b2` as `v1.0.0` and push to GitHub (N3):
     ```bash
     git -C ../platform-catalog tag -a v1.0.0 a8825b2 -m "Blueprint baseline currently running on spoke-prod"
     git -C ../platform-catalog push origin v1.0.0
     ```
  3. **Step 5b (Annotate Cluster Secrets & Server-Side Apply)**:
     Run `register-spokes.sh` with `--server-side` and stripped annotations.
  4. **Step 5c (AppSet Wiring)**:
     Update `applicationsets/kro-blueprints.yaml`:
     ```yaml
     targetRevision: '{{metadata.annotations.blueprints-revision}}'
     ```
  5. **Step 6 (Non-Prod Verification)**:
     Commit RGD hardening to `platform-catalog@main`. Non-prod syncs. Verify pods running and test PSS restricted compliance dry-run:
     ```bash
     kubectl --context k3d-spoke-nonprod label --dry-run=server --overwrite ns orders-dev \
       pod-security.kubernetes.io/enforce=restricted
     ```
  6. **Step 7 (Prod Promotion & Rollback)**:
     - **Promotion**: Tag the exact commit verified in Step 6 as a **new** tag `v1.1.0` (never move existing tags):
       ```bash
       git -C ../platform-catalog tag -a v1.1.0 <verified-sha> -m "Hardened blueprint with dedicated SA, seccomp, and conditional PDB"
       git -C ../platform-catalog push origin v1.1.0
       ```
       Update `clusters/blueprint-revisions.env` to `spoke-prod=v1.1.0`, commit, and re-run registration (or annotate `cluster-spoke-prod`).
     - **Rollback Path (N5)**:
       - **Prod**: Repoint `clusters/blueprint-revisions.env` back to `v1.0.0` and annotate cluster secret.
       - **Non-prod**: `git revert` on `platform-catalog@main`; kro creates a new `GraphRevision` (`queuebackedservice-r00006`) within one poll cycle.

---

## 4. Fully Authorized Execution Schedule

| Step | Action | Execution Details | Done When |
| :---: | :--- | :--- | :--- |
| **0** | **Kill leaked tokens & scrub annotations** (B1, B2, M2) | Delete legacy `argocd-manager-token` Secrets on spokes; update `register-spokes.sh` to TokenRequest + server-side apply (non-prod first); update `headlamp-kubeconfig` | Legacy Secrets NotFound; `last-applied-configuration` absent on cluster Secrets; `argocd cluster list` both Successful; Headlamp connects to all 3 clusters |
| **1** | **Low-risk cleanup** (L1-2, L1-3) | Back up CRD to `/tmp`; delete `messageprocessors.kro.run` on both spokes; `docker rm -f elastic_kapitsa affectionate_dubinsky friendly_lalande` | `kubectl get crd messageprocessors.kro.run` returns NotFound; `docker ps -a` clean |
| **2** | **Secret cleanup** (L2-7, M1) | Delete manual secret `repo-ghcr-charts`; authenticate CLI; `argocd app get orders-dev --hard-refresh` | `argocd-repo-ghcr-charts` is sole secret; app condition has no errors; Synced/Healthy |
| **3** | **Portability fixes** (L1-6, N2, N8) | Update `Makefile` (`ROOT_DIR`/`REPOS_DIR`); update `README.md` (relative paths, 5 repos); remove `/home/bleite` across all 7 files | Automated check passes: `! git grep -nE 'file:///\|/home/bleit[e]' -- ':!docs/assessments' ':!docs/remediation'` |
| **4** | **Documentation sync** (L1-5) | Update `docs/developer-tutorial.md` with `QueueBackedService`, `orders-*` names, and 2 prod replicas | Tutorial instructions match live cluster state |
| **5a**| **Tag baseline blueprint** (N3) | Tag `platform-catalog@a8825b2` as `v1.0.0` and push to GitHub | `git tag -l` shows `v1.0.0` on GitHub |
| **5b**| **Write blueprint revision source** (S1, S2) | Create `clusters/blueprint-revisions.env`; wire into `register-spokes.sh`; record expiry annotation `lab/token-expires` | Cluster Secrets have annotations (`nonprod: main`, `prod: v1.0.0`, `lab/token-expires`); prod revision unchanged |
| **5c**| **AppSet promotion wiring** (N13) | Update `applicationsets/kro-blueprints.yaml` `targetRevision` to `{{metadata.annotations.blueprints-revision}}` | Non-prod tracks `main`; prod tracks `v1.0.0`; zero `ComparisonError` |
| **6** | **Harden platform blueprint** (L4-11, N1) | Update `queue-backed-service-rgd.yaml` (SA automount false, `serviceAccountName` assigned, seccomp RuntimeDefault, readOnlyRootFilesystem, conditional PDB) | Non-prod pods `Running` with 0 restarts; SA assigned; no `kube-api-access` volume; PSS dry-run returns no warnings; dev PDB absent |
| **7** | **Promote blueprint to prod** (N4, N5, S1) | Tag verified SHA as `v1.1.0` in `platform-catalog`; update `clusters/blueprint-revisions.env` to `v1.1.0`; annotate prod secret | `orders-prod` rolls out cleanly; PDB present on prod (2 replicas); Synced/Healthy |
| **8** | **Document trade-offs & rotation** (L4-10, S2) | Add `make rotate-spoke-tokens` to Makefile; record TokenRequest rotation and EKS Access Entries / IRSA roadmap in Well-Architected guide | Security section of `aws-well-architected-production-guide.md` updated |

---

## 5. Verification Checklist

Execute after completing Steps 0–8:

```bash
# 1. Verify legacy token secrets deleted
kubectl --context k3d-spoke-nonprod -n kube-system get secret argocd-manager-token 2>&1 | grep -q "NotFound" && echo "Nonprod Token Scrubbed"
kubectl --context k3d-spoke-prod -n kube-system get secret argocd-manager-token 2>&1 | grep -q "NotFound" && echo "Prod Token Scrubbed"

# 2. Verify plaintext token annotation absent on cluster secrets (B1, N6)
! kubectl --context k3d-hub-cluster -n argocd get secret cluster-spoke-prod -o jsonpath='{.metadata.annotations.kubectl\.kubernetes\.io/last-applied-configuration}' | grep -q "bearerToken"

# 3. Clean containers
docker ps --filter "name=elastic_kapitsa|affectionate_dubinsky|friendly_lalande"

# 4. Clean CRDs
kubectl --context k3d-spoke-nonprod get crd messageprocessors.kro.run 2>&1 | grep -q "NotFound" && echo "Nonprod CRD Clean"
kubectl --context k3d-spoke-prod get crd messageprocessors.kro.run 2>&1 | grep -q "NotFound" && echo "Prod Clean"

# 5. Single repo secret
kubectl --context k3d-hub-cluster -n argocd get secrets -l argocd.argoproj.io/secret-type=repository

# 6. Zero hardcoded paths (N2)
! git grep -nE 'file:///|/home/bleit[e]' -- ':!docs/assessments' ':!docs/remediation'

# 7. Pod Security Standard restricted compliance dry-run
kubectl --context k3d-spoke-nonprod label --dry-run=server --overwrite ns orders-dev pod-security.kubernetes.io/enforce=restricted

# 8. ServiceAccount assigned and token unmounted on workload pod (N1, N12)
kubectl --context k3d-spoke-nonprod -n orders-dev get pod -l app=orders-dev-worker -o jsonpath='{.items[0].spec.serviceAccountName}' | grep -q "orders-dev"
! kubectl --context k3d-spoke-nonprod -n orders-dev get pod -l app=orders-dev-worker -o jsonpath='{.items[0].spec.volumes[*].name}' | grep -q kube-api-access

# 9. Conditional PDB check (R1)
kubectl --context k3d-spoke-nonprod -n orders-dev get pdb # (should be empty - 1 replica)
kubectl --context k3d-spoke-prod -n orders-prod get pdb    # (should exist - 2 replicas)

# 10. All Argo CD applications Synced and Healthy
kubectl --context k3d-hub-cluster -n argocd get applications
```
