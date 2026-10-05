# Tenant IaC plan v0.3: P2 blueprint validation report (validated-04)

> **Status: Independent validation (2026-10-05 UTC).**
> Validator: Antigravity.
> Executor: Claude (Opus 5.5).
> Plan: [`2026-10-04-tenant-iac-team-clusters-plan.md`](2026-10-04-tenant-iac-team-clusters-plan.md) v0.3, Phase P2.
> Report under review: [`implemented-03.md`](2026-10-04-tenant-iac-team-clusters-plan-implemented-03.md) (`01c4966`).
> Verified Commits & Releases:
> - `platform-catalog`: tag **`v1.9.0`** (`a30da38`)
> - `gitops-control-plane`: `3cf231b` (chart CI + schema), `c425a22` (prod promoted to v1.9.0)
> - `platform-charts`: `12457b2` (PR #1 + PR #2 merged), OCI package **`team-cluster:1.0.0`** (`sha256:b0cbb6a6…`)

---

## Verdict: 🟢 GREEN: P2 exit gates met; chart released and public

All Phase P2 exit criteria and requirements defined in plan v0.3 §6 have been independently verified on the live multi-cluster lab:
1. **Live Blueprints & Admission:** RGD `teamekscluster` is `Active` and `Ready=True` on both spokes (`k3d-spoke-nonprod` and `k3d-spoke-prod`). ValidatingAdmissionPolicy `teamekscluster-contract` and its binding are active with `[Deny, Audit]` enforcement.
2. **Scratch Instance Reconciles & Cleans Up:** A scratch claim in namespace `iac-p2val-dev` reached `ready: true`, `state: ACTIVE` in **3 seconds**. Moto Cloud in account `111111111111` provisioned the cluster, node group, cluster role, and node role onto the tier-1 platform network. Deletion was clean, ordered, and left 0 lingering resources in Moto.
3. **VAP Contract Enforced:** Tested 14 admission scenarios via server-side dry-run. Every invalid input (DNS labels, staging env, namespace mismatch, version 1.31/9.99, custom network, disallowed instance type, invalid sizing bounds, prod size > 5) was rejected with descriptive messages; valid dev and prod claims were admitted.
4. **Terminal Dependency Guarding (Amendment 3):** Pre-existing conflicting IAM role induced an `ACK.Terminal` condition on the role child. Kro correctly held the claim in `state=IN_PROGRESS` with `Ready=False`, and the downstream EKS cluster was **never created**. Teardown left the pre-existing role intact.
5. **Chart `team-cluster:1.0.0` Public & Immutable:** Chart package `oci://ghcr.io/brunobml/charts/team-cluster:1.0.0` was pulled anonymously without authentication. Digest matches repository source (`sha256:b0cbb6a6…`). `make ci-charts` verified immutability and linting with dev and prod fixtures.
6. **Zero Lab Regressions:** Control plane CI (`make ci`), catalog CI (`make ci-catalog`), chart CI (`make ci-charts`), and alert rules (`make test-alert-rules`) all passed 100%. All 40 Argo CD applications are `Synced` and `Healthy`. Full smoke test passed 12/12 (`make test`).

---

## 1. Verification Evidence

### 1.1 Live Blueprint & Admission Policies (Both Spokes)

```console
$ kubectl --context k3d-spoke-nonprod get rgd teamekscluster
NAME             APIVERSION   KIND             STATE    READY   AGE
teamekscluster   v1alpha1     TeamEKSCluster   Active   True    7h35m

$ kubectl --context k3d-spoke-prod get rgd teamekscluster
NAME             APIVERSION   KIND             STATE    READY   AGE
teamekscluster   v1alpha1     TeamEKSCluster   Active   True    7h24m

$ kubectl --context k3d-spoke-nonprod get validatingadmissionpolicy,validatingadmissionpolicybinding teamekscluster-contract
NAME                                                          VALIDATIONS   PARAMKIND   AGE
validatingadmissionpolicy.admissionregistration.k8s.io/teamekscluster-contract   8             <unset>     7h35m

NAME                                                                 POLICYNAME                PARAMREF   AGE
validatingadmissionpolicybinding.admissionregistration.k8s.io/teamekscluster-contract   teamekscluster-contract   <unset>    7h35m
```

### 1.2 Scratch Instance Provisioning & Ordered Teardown

Created scratch namespace `iac-p2val-dev` (PSS `restricted`, account `111111111111`) and applied claim `probe-dev`:

```console
$ kubectl --context k3d-spoke-nonprod -n iac-p2val-dev get teamekscluster probe-dev
NAME        READY   STATE    CLUSTERNAME       CLUSTERARN                                                VPCID
probe-dev   true    ACTIVE   p2val-probe-dev   arn:aws:eks:us-east-1:111111111111:cluster/p2val-probe-dev   vpc-315a36c15213f840b

$ kubectl --context k3d-spoke-nonprod -n iac-p2val-dev get role,cluster,nodegroup
NAME                                                READY   STATUS
role.iam.services.k8s.aws/p2val-probe-dev-cluster   True    Synced
role.iam.services.k8s.aws/p2val-probe-dev-node      True    Synced

NAME                                           VERSION   STATUS   SYNCED
cluster.eks.services.k8s.aws/p2val-probe-dev   1.32      ACTIVE   False

NAME                                                CLUSTER           VERSION   STATUS   DESIREDSIZE   MINSIZE   MAXSIZE   SYNCED
nodegroup.eks.services.k8s.aws/p2val-probe-dev-ng   p2val-probe-dev   1.19      ACTIVE   1             1         2         True
```

Verified live in Moto Cloud via STS assume-role (`111111111111`):
- Cluster: `p2val-probe-dev`
- Nodegroup: `p2val-probe-dev-ng`
- Roles: `p2val-probe-dev-cluster`, `p2val-probe-dev-node`

**Teardown:** Deleted `probe-dev`. Ordered deletion executed in 35 seconds (nodegroup deleted first, then cluster, then roles). Querying Moto Cloud confirmed 0 lingering clusters or roles.

### 1.3 Admission Control Matrix (VAP `teamekscluster-contract`)

Tested 14 distinct test cases via server-side dry-run (`kubectl apply --server-side --dry-run=server -f -`):

| Test Case | Manifest Modification | Expected | Result | Validation Message |
|---|---|---|---|---|
| **Control** | Standard valid dev claim | Admitted | **PASS** | Admitted |
| **Team case** | `team: TestAdmission` | Denied | **PASS** | `spec.team must be a lowercase DNS label of 2-20 characters` |
| **Name suffix** | `name: analytics-` | Denied | **PASS** | `spec.name must be a lowercase DNS label of 2-20 characters` |
| **Env** | `env: staging` | Denied | **PASS** | `spec.env must be one of: dev, test, prod` |
| **Namespace binding** | `env: dev` in namespace `iac-testadmission-prod` | Denied | **PASS** | `namespace iac-testadmission-prod does not match team/env: expected iac-testadmission-dev` |
| **Version (low)** | `kubernetesVersion: "1.31"` | Denied | **PASS** | `spec.kubernetesVersion must be one of: 1.32, 1.33, 1.34` |
| **Version (arbitrary)** | `kubernetesVersion: "9.99"` | Denied | **PASS** | `spec.kubernetesVersion must be one of: 1.32, 1.33, 1.34` |
| **Network** | `network: custom-vpc` | Denied | **PASS** | `spec.network must be platform-default (the platform owns the network)` |
| **Instance type** | `instanceType: c5.24xlarge` | Denied | **PASS** | `spec.nodeGroup.instanceType must be one of: t3.medium, t3.large, m5.large` |
| **Min size** | `minSize: 0` | Denied | **PASS** | `spec.nodeGroup sizes must satisfy 1 <= minSize <= desiredSize <= maxSize` |
| **Desired > Max** | `desiredSize: 3, maxSize: 2` | Denied | **PASS** | `spec.nodeGroup sizes must satisfy 1 <= minSize <= desiredSize <= maxSize` |
| **Dev max bound** | `maxSize: 4` (dev) | Denied | **PASS** | `with maxSize <= 3 (dev/test) or <= 5 (prod)` |
| **Prod max bound (valid)** | `maxSize: 5` (prod) | Admitted | **PASS** | Admitted |
| **Prod max bound (invalid)** | `maxSize: 6` (prod) | Denied | **PASS** | `with maxSize <= 3 (dev/test) or <= 5 (prod)` |

### 1.4 Negative Terminal Dependency Handling (Amendment 3)

1. Pre-created IAM role `p2val-term-dev-cluster` in Moto account `111111111111`.
2. Applied claim `term-dev`.
3. Observed child role reconciliation: encountered conflict; condition marked `ACK.Terminal: Resource already exists`.
4. Inspected `TeamEKSCluster`:
   - `state: IN_PROGRESS`
   - `ready`: unset
   - Kro condition `Ready: False`
5. Inspected child EKS Cluster `p2val-term-dev`:
   - Apiserver reported `NotFound` (EKS cluster creation was blocked by the `readyWhen` dependency on `clusterRole`).
6. Deleted `term-dev`:
   - Deletion completed cleanly.
   - Pre-existing Moto IAM role remained intact and was manually verified before cleanup.

### 1.5 Helm Chart `team-cluster:1.0.0` & Anonymous OCI Pull

```console
$ helm pull oci://ghcr.io/brunobml/charts/team-cluster --version 1.0.0 -d /tmp/chart-pull
Pulled: ghcr.io/brunobml/charts/team-cluster:1.0.0
Digest: sha256:b0cbb6a687cfe2092f50bcff1fb48ca7ec1a7a8ac38f05e00f5898073dd92e5c
```
- Package is public and pullable without credentials.
- Tarball contains `Chart.yaml`, `values.yaml`, `values.schema.json`, `templates/team-eks-cluster.yaml`, and `ci/` fixtures (`dev-values.yaml`, `prod-values.yaml`).
- Templating with `dev-values.yaml` and `prod-values.yaml` generates valid `TeamEKSCluster` manifests matching the contract.

### 1.6 CI & Test Suites

- **Alert Rules (`make test-alert-rules`):** `SUCCESS` (20 rules).
- **Chart CI (`make ci-charts`):**
  - `queue-backed-service:1.0.0` (lint with 4 values files, kubeconform valid, released).
  - `team-cluster:1.0.0` (lint with 2 values files, kubeconform valid, released).
- **Catalog CI (`make ci-catalog`):**
  - CEL compile on 6 objects (including `teamekscluster-contract` and `teamekscluster`).
  - 2 RGD schemas compatible with `v1.9.0`.
  - Rendered 22 Applications (376 resources validated by kubeconform with 0 errors).
- **Control Plane CI (`make ci`):**
  - 31 shell scripts clean.
  - 387 files scanned for credentials: clean.
  - 40 applications rendered offline; 577 resources validated by kubeconform with 0 errors.
- **Argo CD Applications:** 40/40 applications `Synced` and `Healthy` on Hub.
- **Smoke Suite (`make test`):** 12/12 gates passed with zero regressions.

---

## 2. Verdict & Next Step

Phase P2 is **fully validated and closed**.

**Next Step:** Proceed to **Phase P3 (Tenant Repository)**:
- Create repository `brunobml/tenant-iac` (public).
- Layout: `teams/`, JSON Schema for claim files, CODEOWNERS (`@brunobml` on `teams/*/clusters/*-prod.yaml`), README.
- GitHub Actions CI workflow `cluster-checks` (validating file naming, JSON Schema, team uniqueness, and rendering through `team-cluster` chart + kubeconform).
- Ruleset on `main` requiring PR and `cluster-checks`.
