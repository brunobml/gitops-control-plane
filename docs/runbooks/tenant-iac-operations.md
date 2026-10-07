# Operations Runbook: Tenant Infrastructure-as-Code (IaC) Self-Service

> **Audience:** Platform Engineers, SREs, and Tenant Service Owners.  
> **Scope:** Self-service EKS clusters provisioned via [`brunobml/tenant-iac`](https://github.com/brunobml/tenant-iac), governed by Hub Argo CD and instantiated via Kro + AWS Controllers for Kubernetes (ACK) on `k3d-spoke-nonprod` and `k3d-spoke-prod`.

---

## 0. Concepts First (for learners)

Read this before the procedures; the glossary terms are in [Concepts, Glossary & Self-Check](../concepts-and-glossary.md).

* **Same chain as tenant apps, different blueprint.** A claim file → ApplicationSet `tenant-iac-<team>` → chart `team-cluster` (Helm render by Argo CD) → `TeamEKSCluster` → kro → ACK IAM `Role`s, EKS `Cluster`, `Nodegroup` → AWS API in the environment's account. Four reconcilers again: see [One change, four reconcilers](devops-student-rebuild-guide.md#one-change-four-reconcilers).
* **Two tiers of infrastructure.** The **network is platform-owned** (tier 1): one VPC, two subnets, an internet gateway, a route table and a security group per account, declared in `platform-catalog/network/` and deployed to namespace `platform-network`, where teams cannot write. A **team cluster** (tier 2) only *reads* it: the kro blueprint uses `externalRef` to look up `platform-subnet-a/-b` and `platform-cluster-sg` and copies their current IDs into the cluster spec. No ID is ever written in Git; if the network is recreated with new IDs, kro re-renders the clusters.
* **Names include the team** (`<team>-<name>-<env>`). Two teams may both have an `analytics-dev`; AWS names, Argo CD Application names and Kubernetes objects never collide. (Without the team prefix, one team's claim could adopt, and later delete, another team's cluster: tenant-IaC P0 finding F-1.)
* **What "ready" proves here.** moto stores an EKS cluster as an `ACTIVE` record: there is no Kubernetes behind it. A ready `TeamEKSCluster` proves that the request was valid, landed in the right account with the right roles and network, and is observable. It does not prove that anyone can run `kubectl` against it (see the note in Runbook 1).
* **Prod is protected differently.** Prod resources use `deletion-policy: retain` and `adopt-or-create`: deleting a prod claim keeps the cloud resources, and restoring the claim picks them up again.

---

## 1. Architecture & Governance Model

The self-service infrastructure workflow is declarative, PR-driven, and governed by strict isolation boundaries:

```
Tenant Repo (tenant-iac)
  └── teams/<team>/clusters/<name>-<env>.yaml
          │
          │  Pull Request + CI validation (JSON Schema + CEL + Rule 24519842)
          ▼
Hub Argo CD (k3d-hub-cluster)
  ├── AppProject: tenant-iac (scoped sources/destinations)
  └── ApplicationSet: tenant-iac-<team> (git files generator)
          │
          │  Spoke ServiceAccount: argocd-iac-deployer (least-privilege RBAC)
          ▼
Spoke Clusters (k3d-spoke-nonprod / k3d-spoke-prod)
  └── Namespace: iac-<team>-<env> (PSS restricted, CARM owner-account-id)
          └── TeamEKSCluster CR (kro.run/v1alpha1)
                  │       reads (externalRef) ◄── Namespace platform-network (tier 1, platform-owned):
                  │                               VPC, platform-subnet-a/-b, platform-cluster-sg
                  ▼ Kro ResourceGraphDefinition (teamekscluster)
                  ├── iam.services.k8s.aws/v1alpha1: Role (Cluster & Node roles)
                  ├── eks.services.k8s.aws/v1alpha1: Cluster (EKS cluster)
                  └── eks.services.k8s.aws/v1alpha1: Nodegroup (Managed Nodegroup)
                          │
                          ▼ CARM AssumeRole via local STS
AWS / Moto Cloud (http://localhost:5000)
  ├── Nonprod Account 111111111111 (deletion-policy: delete)
  ├── Prod Account 222222222222 (deletion-policy: retain)
  └── Default Account 123456789012 (zero leaked resources)
```

---

## 2. Operational Procedures

### Runbook 1: Requesting a New Cluster (`request`)

1. **Clone & Branch:**
   <!-- doc-test: skip reason="clones tenant-iac and creates a branch in your workspace" -->
   ```bash
   git clone git@github.com:brunobml/tenant-iac.git
   cd tenant-iac
   git checkout -b feature/new-<team>-<name>-<env>
   ```

2. **Create Cluster Claim File:**
   Create file `teams/<team>/clusters/<name>-<env>.yaml` following `schema/cluster.schema.json`:
   ```yaml
   team: team-data
   name: ml-feature-store
   env: dev
   kubernetesVersion: "1.33"
   network: platform-default
   nodeGroup:
     instanceType: t3.medium
     minSize: 1
     desiredSize: 2
     maxSize: 3          # dev/test: at most 3 (prod: at most 5)
   ```

3. **Validate Locally:**
   <!-- doc-test: covered by="check:tenant-iac-step3" -->
   ```bash
   # Quick check: the JSON schema only (fields, allowed values, size limits per environment)
   python3 -c "import json, jsonschema, yaml; jsonschema.validate(yaml.safe_load(open('teams/team-data/clusters/ml-feature-store-dev.yaml')), json.load(open('schema/cluster.schema.json')))" && echo "schema OK"

   # Full check = what the required CI check runs: schema, min <= desired <= max, team = folder,
   # file name = <name>-<env>.yaml, clusters per team, render through the real ApplicationSet + chart.
   # Run from your tenant-iac working directory via gitops-control-plane:
   make -C ../gitops-control-plane ci-iac
   ```

4. **Submit PR & Merge:**
   - Push branch and open PR against `main`.
   - CI workflow `cluster-checks` runs automatically: validates schema, ensures naming convention `teams/<team>/clusters/<name>-<env>.yaml`, enforces unique cluster names, checks allowed Kubernetes versions (`1.32`, `1.33`, `1.34`), and scans for secrets.
   - **Review Gates:**
     - **Current Lab Reality (Single-Contributor):** GitHub ruleset `24519842` enforces a pull request and the required `cluster-checks` CI status check. Mandatory approval review count is `0` (`required_approving_review_count: 0`, `require_code_owner_review: false`) to avoid self-approval blocks in a single-maintainer repository.
     - **Enterprise Target (Multi-Contributor):** Production claims (`teams/*/clusters/*-prod.yaml`) require formal code owner approval (`@brunobml`) before merge.
   - Once automated CI checks pass (and reviews are approved in multi-contributor setups), merge the PR to `main`.
   - Hub Argo CD ApplicationSet automatically detects the file and deploys the cluster application within 3 minutes (or sync immediately via Argo CD UI).

> [!NOTE]
> **Two-Tier Acceptance Model (Moto API Simulation vs Production EKS):**  
> In Moto, ACK EKS Cluster CRs report `status.status == ACTIVE` while `ACK.ResourceSynced` remains `False` due to simulated late-initialization fields. The platform blueprint intentionally defines `TeamEKSCluster` readiness as `ACTIVE` without `ACK.Terminal`. This validates declarative composition, CARM account boundaries, and GitOps lifecycle events. In contrast, real AWS EKS acceptance requires full Kubernetes API convergence: `ACK.ResourceSynced=True`, cluster endpoint authentication, worker nodes `Ready`, pod scheduling, and VPC CNI reachability.

---

### Runbook 2: Modifying an Existing Cluster (`change`)

1. **Allowed In-Place Changes:**
   - **Nodegroup Sizing:** `desiredSize`, `minSize`, `maxSize`.
   - **Instance Type:** `instanceType` (e.g. `t3.medium` $\rightarrow$ `m5.large`).
   - **Kubernetes Version:** `kubernetesVersion` (e.g. `"1.32"` $\rightarrow$ `"1.33"` $\rightarrow$ `"1.34"`).

2. **Procedure:**
   - Create a branch in `brunobml/tenant-iac`.
   - Edit `teams/<team>/clusters/<name>-<env>.yaml` with the updated parameters.
   - Open PR and verify CI passes.
   - Merge PR.
   - Argo CD updates the `TeamEKSCluster` CR on the spoke.
   - Kro reconciles the resource graph and updates the underlying ACK `Cluster` and `Nodegroup` CRs.
   - ACK controller updates the live AWS EKS cluster and nodegroup with zero downtime.

---

### Runbook 3: Deleting a Nonprod Cluster (`delete`)

1. **Procedure:**
   - In `brunobml/tenant-iac`, open a PR removing `teams/<team>/clusters/<name>-dev.yaml`.
   - Merge the PR.
2. **Lifecycle & Teardown Behavior:**
   - Argo CD ApplicationSet notices file removal and prunes the Application.
   - Deletion of `TeamEKSCluster` triggers Kro finalizer.
   - Kro deletes children in strict reverse topological order:
     1. Nodegroup (`Nodegroup.eks.services.k8s.aws`)
     2. EKS Cluster (`Cluster.eks.services.k8s.aws`)
     3. IAM Roles (`Role.iam.services.k8s.aws`)
   - Because `env: dev` uses `deletion-policy: delete`, ACK controller actively calls Moto/AWS to terminate and remove the cloud resources in account `111111111111`.
   - Namespace and all resources are completely cleaned up.

---

### Runbook 4: Deleting a Prod Cluster (`prod-retention`)

1. **Procedure:**
   - Open a PR in `brunobml/tenant-iac` removing `teams/<team>/clusters/<name>-prod.yaml`.
   - Requires PR approval and passing CI checks.
   - Merge PR.
2. **Cloud Resource Protection:**
   - Argo CD prunes the Application and Kubernetes CRs are deleted.
   - **CRITICAL:** Because `env: prod` uses `deletion-policy: retain` (enforced by the Helm chart blueprint), ACK controllers **do not** delete the underlying cloud resources in AWS account `222222222222`.
   - The AWS EKS cluster, managed nodegroup, and IAM roles remain intact in AWS to prevent accidental data loss.
   - To decommission retained cloud resources permanently, a platform administrator must assume the account role and execute AWS CLI deletion explicitly.

---

### Runbook 5: Moto Cloud Restart & Disaster Recovery (`moto-restart`)

When the host machine reboots or the `moto-cloud` Docker container restarts, Moto loses its in-memory state.

#### Automated Recovery:
Run the official recovery script from repository root:
<!-- doc-test: skip reason="restarts moto (about 5 min); exercised by the Drill 1 recovery" -->
```bash
make moto-restart
# OR: bash scripts/moto-restart.sh
```

#### What the Script Does:
1. **Pauses Argo CD Application Controller:** Prevents self-healing race conditions.
2. **Scales Down ACK Controllers (0 Replicas):** Prevents in-flight unauthenticated requests from leaking into Moto default account `123456789012` before STS tokens are ready.
3. **Restarts Moto Container:** Issues `docker restart moto-cloud` with managed IAM policies enabled.
4. **Re-creates Platform Network:** Clears stale network objects and re-syncs VPC, Subnets, and Security Groups.
5. **Clears Stale Adopted Markers:** Removes `services.k8s.aws/adopted` markers.
6. **Scales Up ACK Controllers (1 Replica):** Allows controllers to reconcile against freshly provisioned cloud state.
7. **Resumes Argo CD Application Controller:** Unpauses reconciliation.
8. **Re-syncs Applications:** Ensures platform network and tenant workloads reach `Healthy`.
9. **Leak Verification:** Asserts that account `123456789012` has **zero** leaked VPCs, SGs, IGWs, SQS queues, or IAM roles.
10. **Re-provisions Worker Credentials & Runs Smoke Gates:** Verifies end-to-end functionality (`post-bootstrap`).

**After a host reboot** (`make start` + `make post-bootstrap`, not this script), the network is repaired while the ACK controllers are already running. The EC2 controller first recreates the VPC from its stale object, and the repair then creates a fresh one. `post-bootstrap` therefore runs `scripts/prune-orphan-platform-vpcs.sh`, which deletes a VPC that ACK created for `platform-network` only if no VPC object in that namespace references it **and** it is empty (no subnets, gateway, extra security groups or route tables). It fails closed: a non-empty orphan, an unsynced VPC object or a failed AWS read stops `post-bootstrap` with an error, and nothing is reported clean without being read. The Bats smoke suite (*Gate 6b*, run by `make test` and at the end of `post-bootstrap`) checks that each account has exactly one platform VPC, the one Kubernetes references. Run `bash scripts/prune-orphan-platform-vpcs.sh --dry-run` to see what it would do.

---

## 3. Alerts & Troubleshooting

### Alert: `TeamClusterNotReady`

#### Symptoms:
- Prometheus alert `TeamClusterNotReady` is firing (Critical).
- Grafana *Platform Overview* dashboard (*Team clusters* panel) displays `Readiness` as `NotReady` (and/or state `UNKNOWN`/`FAILED`).
- Hub Argo CD displays application `<team>-<name>-<env>` (e.g. `team-data-analytics-dev`) in `Degraded` or `Progressing` status.

#### Investigation:
1. **Check Team Cluster Status on Spoke:**
   <!-- doc-test: run subst="<team>=team-data,<env>=dev,<name>=analytics" expect="analytics-prod" -->
   ```bash
   # Nonprod:
   kubectl --context k3d-spoke-nonprod -n iac-<team>-<env> get teameksclusters
   kubectl --context k3d-spoke-nonprod -n iac-<team>-<env> describe teamekscluster <name>-<env>

   # Prod (the prod spoke only hosts -prod claims):
   kubectl --context k3d-spoke-prod -n iac-<team>-prod get teameksclusters
   kubectl --context k3d-spoke-prod -n iac-<team>-prod describe teamekscluster <name>-prod
   ```

2. **Check Child Resource Status:**
   <!-- doc-test: run subst="<ctx>=k3d-spoke-nonprod,<team>=team-data,<env>=dev" expect="team-data-analytics-dev" -->
   ```bash
   kubectl --context <ctx> -n iac-<team>-<env> get cluster.eks,nodegroup.eks,role.iam
   ```

3. **Check ACK Controller Logs:**
   <!-- doc-test: run subst="<ctx>=k3d-spoke-nonprod" expect="level" -->
   ```bash
   kubectl --context <ctx> -n ack-system logs -l app.kubernetes.io/name=eks-chart --tail=100
   kubectl --context <ctx> -n ack-system logs -l app.kubernetes.io/name=iam-chart --tail=100
   ```

4. **Common Causes & Remediation:**
   - **VPC Subnet Misalignment:** Check that `TeamEKSCluster` references a valid network (e.g. `platform-default`).
   - **Terminal Condition on Cluster:** If ACK reports `ACK.Terminal=True`, check AWS IAM permissions or VPC limits.
   - **Controller Scale Down:** Verify all pods in `ack-system` are `1/1 Running`.
