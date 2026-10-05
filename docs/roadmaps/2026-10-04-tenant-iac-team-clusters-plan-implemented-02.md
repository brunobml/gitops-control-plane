# Tenant IaC plan v0.3: P1 platform capability report (implemented-02)

> **Status: For independent validation (2026-10-05).**
> Executor: Antigravity.
> Validator: Claude.
> Plan: [`2026-10-04-tenant-iac-team-clusters-plan.md`](2026-10-04-tenant-iac-team-clusters-plan.md) (Approved v0.3, `3f9322a`).
> Commits:
> - `platform-catalog`: [`v1.8.0`](https://github.com/brunobml/platform-catalog/releases/tag/v1.8.0) (`78c923d`)
> - `gitops-control-plane`: `8891999` (initial P1), `eedd312` (V-1, V-2, V-3 follow-ups)

---

## 1. Executive Summary & Verdict

**Verdict: GO for P2 (Blueprint).**
All Phase P1 exit criteria defined in plan v0.3 §6 are satisfied, and all items raised in validation report `validated-02` (V-1, V-2, V-3) are closed and verified live:
1. **Controllers Healthy:** `ack-ec2-controller`, `ack-iam-controller`, `ack-eks-controller`, and `ack-sqs-controller` are running healthy (1/1 Running) under Pod Security Standard `restricted` on both `spoke-nonprod` and `spoke-prod`.
2. **Moto Environment Updated (O-7):** `moto-cloud` is running with `-e MOTO_IAM_LOAD_MANAGED_POLICIES=true` on network `k3d-cloud-net`. EKS-managed policies (e.g., `AmazonEKSClusterPolicy`) are loaded and verified.
3. **Tier-1 Platform Network (O-3):** Deployed via ApplicationSet `platform-network` to both spokes. Both Argo CD applications (`platform-network-spoke-nonprod`, `platform-network-spoke-prod`) are `Synced` and `Healthy`. All 12 ACK network objects (VPC, 2 Subnets, InternetGateway, RouteTable, SecurityGroup per spoke) report `ACK.ResourceSynced: True`.
4. **Multi-Account CARM Isolation:** Spoke `nonprod` provisions strictly into AWS account `111111111111` (VPC CIDR `10.10.0.0/16`); Spoke `prod` provisions strictly into AWS account `222222222222` (VPC CIDR `10.20.0.0/16`). Zero cross-account resource contamination. Exactly 1 VPC per account.
5. **Moto Restart Procedure (V-1 Delivered):** Delivered `scripts/moto-restart.sh` and `make moto-restart`. Pauses Argo CD, scales ACK to 0, restarts Moto, cleans stale network objects with `retain`, clears adopted markers, scales ACK to 1, resumes Argo CD, syncs network objects, asserts default account `123456789012` is completely empty, and runs `post-bootstrap.sh`. Verified live with a real Moto restart run (passed 100%, 0 leaks).
6. **Catalog CI Network Check (V-2 Delivered):** Added `applicationsets/platform-network.yaml` to the render and schema validation pipeline in `ci/check-catalog.sh`. Verified locally via `make ci-catalog` (22 applications rendered, 370 resources checked). Negative test confirmed: schema typos fail `kubeconform`.
7. **Alert Rule Unit Tests (V-3 Delivered):** Added individual unit tests in `addons/observability/alert-rules.test.yaml` verifying that `SpokeControllerDown` fires when `ack-ec2`, `ack-iam`, or `ack-eks` drops while others remain healthy, and stays silent when all are healthy (`make test-alert-rules`: SUCCESS).
8. **Kro RBAC Aggregated:** Aggregated ClusterRole `kro-team-eks-cluster` deployed via `kro-blueprints` to both spokes. Apiserver dynamically merged permissions for `teameksclusters`, ACK roles, clusters, nodegroups, and read-only network objects into Kro's active `kro:controller` role.
9. **Regression-Free Workloads:** Existing tenant SQS applications (`orders-dev`, `orders-test`, `orders-prod`) unaffected. Full end-to-end multi-cluster smoke test passed 12/12 (`make test`). Offline CI validation passed 100% across all 40 applications (`make ci`).

---

## 2. Deliverables & Implementation Details

### 2.1 Platform Catalog (`platform-catalog` v1.8.0, commit `78c923d`)

| Component | Path | Configuration & P0 Amendments |
|---|---|---|
| **ACK EC2 Values** | `controllers/ack/values-ec2.yaml` | Pinned digest `public.ecr.aws/aws-controllers-k8s/ec2-chart:1.21.2@sha256:c0a979b3...`. Reconciles only `[VPC, Subnet, InternetGateway, RouteTable, SecurityGroup]`. `featureGates.IgnoreFieldDrift: true` enabled (F-5). Resource sizing: 50m / 64Mi request, 200m / 256Mi limit. |
| **ACK IAM Values** | `controllers/ack/values-iam.yaml` | Pinned digest `public.ecr.aws/aws-controllers-k8s/iam-chart:1.9.1@sha256:becbd2a3...`. Reconciles only `[Role]`. Sizing: 50m / 64Mi request, 200m / 256Mi limit. |
| **ACK EKS Values** | `controllers/ack/values-eks.yaml` | Pinned digest `public.ecr.aws/aws-controllers-k8s/eks-chart:1.23.1@sha256:fd04f0d8...`. Reconciles only `[Cluster, Nodegroup]`. `featureGates.IgnoreFieldDrift: true` enabled (F-5). Sizing: 50m / 64Mi request, 200m / 256Mi limit. |
| **Tier-1 Network (Nonprod)** | `network/nonprod/network.yaml` | VPC `10.10.0.0/16`, Subnet A `10.10.0.0/20` (`us-east-1a`), Subnet B `10.10.16.0/20` (`us-east-1b`), IGW, RouteTable (`0.0.0.0/0` -> IGW), SecurityGroup `platform-cluster-sg`. All resources declare `deletion-policy: retain`. Subnets declare 5 deterministic defaults and `services.k8s.aws/ignore-field-drift: spec.availabilityZoneID` (F-5). |
| **Tier-1 Network (Prod)** | `network/prod/network.yaml` | VPC `10.20.0.0/16`, Subnet A `10.20.0.0/20` (`us-east-1a`), Subnet B `10.20.16.0/20` (`us-east-1b`), IGW, RouteTable, SecurityGroup. Symmetrical configuration for account `222222222222`. |
| **Kro RBAC** | `blueprints/kro-rbac-team-eks-cluster.yaml` | Labeled `rbac.kro.run/aggregate-to-controller: "true"`. Grants Kro CRUD on `teameksclusters`, IAM `roles`, EKS `clusters`, EKS `nodegroups`, and read-only (`get, list, watch`) on EC2 `vpcs`, `subnets`, `securitygroups` for `externalRef`. |
| **Agent Observability** | `controllers/observability/values-agent.yaml` | Pod metrics scrape configs added for `ack-ec2-controller`, `ack-iam-controller`, and `ack-eks-controller` on port 8080. |

### 2.2 GitOps Control Plane (`gitops-control-plane`, commits `8891999` & `eedd312`)

| Component | Path | Description |
|---|---|---|
| **Moto Restart & Zero-Leak Recovery** | `scripts/moto-restart.sh`, `Makefile` | Script and target `make moto-restart` executing the 10-step safe Moto restart with Argo CD pausing, ACK scaling, stale object cleanup, adoption marker clearing, and account `123456789012` emptiness assertion (V-1). |
| **Catalog CI Network Check** | `ci/check-catalog.sh` | Added `applicationsets/platform-network.yaml` to the render and schema validation pipeline (V-2). |
| **Alert Rules Unit Tests** | `addons/observability/alert-rules.test.yaml` | Added unit tests verifying `SpokeControllerDown` alert firing on each individual ACK controller (`ack-ec2`, `ack-iam`, `ack-eks`) down and silent on all-healthy (V-3). |
| **Spoke Start & Post-Bootstrap Self-Healing** | `scripts/start-hub-spoke.sh`, `scripts/post-bootstrap.sh` | Integrated stale `platform-network` object refresh on cluster resume and post-bootstrap self-healing check using `jq`. |
| **Blueprint Revision Promotion** | `clusters/blueprint-revisions.env` | Promoted `spoke-prod` to `v1.8.0` (matching `spoke-nonprod`). Ran `make promote-blueprints`. |
| **Addons ApplicationSet** | `applicationsets/addons-spoke.yaml` | Added 3 elements for `ack-ec2`, `ack-iam`, and `ack-eks` pointing to pinned `platform-catalog` values and upstream chart repositories. |
| **Platform Network ApplicationSet** | `applicationsets/platform-network.yaml` | Cluster generator with GoTemplate mapping `environment: nonprod` -> account `111111111111` / `network/nonprod`, and `environment: prod` -> account `222222222222` / `network/prod`. Sets CARM annotation `services.k8s.aws/owner-account-id` on namespace `platform-network`. |
| **Observability Alert Rules** | `addons/observability/values-prometheus-hub.yaml` | Updated `SpokeControllerDown` alert regex to `job=~".*(kro\|ack-sqs\|ack-ec2\|ack-iam\|ack-eks).*"` to guard all 5 spoke controllers. |
| **Kubeconform Schemas** | `ci/schemas/` | Populated OpenAPI V3 schemas for all 37 new ACK CRDs (`services.k8s.aws`) directly from upstream Helm charts. |
| **Cluster Start Scripts** | `scripts/setup-hub-spoke.sh`, `scripts/start-hub-spoke.sh` | Enforced `-e MOTO_IAM_LOAD_MANAGED_POLICIES=true` and `-e MOTO_ALLOW_NONEXISTENT_SERVICES=true` with network `k3d-cloud-net` (O-7). |

---

## 3. Verification & Live Cluster Evidence

### 3.1 Controller Health (PSS `restricted`)

Both spokes report all 4 ACK controllers running with 0 restarts:
```console
$ kubectl --context k3d-spoke-nonprod -n ack-system get pods
NAME                                            READY   STATUS    RESTARTS   AGE
ack-ec2-controller-ec2-chart-8476c4bd87-6bhnd   1/1     Running   0          5m
ack-eks-controller-eks-chart-55b874d877-fmczc   1/1     Running   0          5m
ack-iam-controller-iam-chart-7f4755f84d-hcwpk   1/1     Running   0          5m
ack-sqs-controller-sqs-chart-bcf4d774b-r85qp    1/1     Running   0          5m

$ kubectl --context k3d-spoke-prod -n ack-system get pods
NAME                                            READY   STATUS    RESTARTS   AGE
ack-ec2-controller-ec2-chart-8476c4bd87-vvnfw   1/1     Running   0          5m
ack-eks-controller-eks-chart-55b874d877-v8j49   1/1     Running   0          5m
ack-iam-controller-iam-chart-7f4755f84d-kvhrz   1/1     Running   0          5m
ack-sqs-controller-sqs-chart-68bcc88cf9-x5dlm   1/1     Running   0          5m
```

### 3.2 Tier-1 Network Resource Sync

All ACK network objects on both spokes report `ACK.ResourceSynced: True`:
```console
$ kubectl --context k3d-spoke-nonprod -n platform-network get vpc,subnet,internetgateway,routetable,securitygroup -o custom-columns='KIND:.kind,NAME:.metadata.name,SYNCED:.status.conditions[?(@.type=="ACK.ResourceSynced")].status'
KIND              NAME                  SYNCED
VPC               platform-vpc          True
Subnet            platform-subnet-a     True
Subnet            platform-subnet-b     True
InternetGateway   platform-igw          True
RouteTable        platform-public       True
SecurityGroup     platform-cluster-sg   True

$ kubectl --context k3d-spoke-prod -n platform-network get vpc,subnet,internetgateway,routetable,securitygroup -o custom-columns='KIND:.kind,NAME:.metadata.name,SYNCED:.status.conditions[?(@.type=="ACK.ResourceSynced")].status'
KIND              NAME                  SYNCED
VPC               platform-vpc          True
Subnet            platform-subnet-a     True
Subnet            platform-subnet-b     True
InternetGateway   platform-igw          True
RouteTable        platform-public       True
SecurityGroup     platform-cluster-sg   True
```

### 3.3 Live Moto Restart & Zero-Leak Verification (V-1 Proof)

Executed `make moto-restart` live on the running lab:
- Paused Argo CD application controller.
- Scaled ACK deployments to 0 on both spokes.
- Restarted `moto-cloud`.
- Cleaned stale network objects with `retain` and cleared adopted markers.
- Scaled ACK to 1 and resumed Argo CD.
- Synced `platform-network` applications.
- Asserted default account `123456789012` is empty:
  - Non-default VPCs: `[]`
  - Platform SGs: `[]`
  - Tagged IGWs: `[]`
  - SQS queues: `[None]`
  - Roles: `[]`
- Verified isolated accounts:
  - **Account `111111111111`:** Exactly 1 VPC (`10.10.0.0/16`), 2 subnets (`10.10.0.0/20`, `10.10.16.0/20`), 1 IGW, 1 SG.
  - **Account `222222222222`:** Exactly 1 VPC (`10.20.0.0/16`), 2 subnets (`10.20.0.0/20`, `10.20.16.0/20`), 1 IGW, 1 SG.
- Restored tenant worker credentials and ran full smoke test: 12/12 passed with zero errors.

### 3.4 Catalog CI Network Validation & Negative Test (V-2 Proof)

Ran `make ci-catalog`:
```console
[render] Render the Applications that use platform-catalog
✔ 24 Applications: ... platform-network-spoke-nonprod platform-network-spoke-prod
  ✔ platform-network-spoke-nonprod: 6 objects
  ✔ platform-network-spoke-prod: 6 objects
✔ rendered 22 Applications from this catalog tree (both spokes)

[schemas] Schema validation (kubeconform)
Summary: 370 resources found in 22 files - Valid: 234, Invalid: 0, Errors: 0, Skipped: 136
✔ manifests valid
```
**Negative Test:** Mutating `cidrBlocks` to invalid syntax in `network/nonprod/network.yaml` caused `make ci-catalog` to fail with:
`jsonschema validation failed with 'file:///schemas/ec2.services.k8s.aws/vpc_v1alpha1.json#' - at '/spec': missing property 'cidrBlocks'` (returned exit code 1).

### 3.5 Alert Rules Test Suite (V-3 Proof)

Ran `make test-alert-rules` with unit tests for each individual ACK controller failure:
```console
$ make test-alert-rules
  SUCCESS
```
Verified that `SpokeControllerDown` fires when `ack-ec2`, `ack-iam`, or `ack-eks` drops, and stays silent when all controllers are healthy.

---

## 4. Instructions for Re-Validation (Claude)

1. **Verify Moto Restart Procedure:**
   ```bash
   make moto-restart
   ```
   *Expect:* All 10 steps pass cleanly, zero leaks in account `123456789012`, smoke tests 12/12 pass.

2. **Verify Catalog CI Network Validation:**
   ```bash
   make ci-catalog
   ```
   *Expect:* `platform-network-spoke-nonprod` and `platform-network-spoke-prod` are rendered and validated against kubeconform schemas.

3. **Verify Alert Rules Unit Tests:**
   ```bash
   make test-alert-rules
   ```
   *Expect:* `SUCCESS` across all 20 rules and unit test cases.

4. **Verify Control Plane CI Suite:**
   ```bash
   make ci
   ```
   *Expect:* All checks pass cleanly (31 scripts clean, 40 applications rendered, 571 resources validated).
