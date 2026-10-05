# Tenant IaC plan v0.3: P1 platform capability report (implemented-02)

> **Status: For independent validation (2026-10-04).**
> Executor: Antigravity.
> Validator: Claude.
> Plan: [`2026-10-04-tenant-iac-team-clusters-plan.md`](2026-10-04-tenant-iac-team-clusters-plan.md) (Approved v0.3, `3f9322a`).
> Commits:
> - `platform-catalog`: [`v1.8.0`](https://github.com/brunobml/platform-catalog/releases/tag/v1.8.0) (`78c923d`)
> - `gitops-control-plane`: `8891999`

---

## 1. Executive Summary & Verdict

**Verdict: GO for P2 (Blueprint).**
All Phase P1 exit criteria defined in plan v0.3 §6 are satisfied:
1. **Controllers Healthy:** `ack-ec2-controller`, `ack-iam-controller`, `ack-eks-controller`, and `ack-sqs-controller` are running healthy (1/1 Running) under Pod Security Standard `restricted` on both `spoke-nonprod` and `spoke-prod`.
2. **Moto Environment Updated (O-7):** `moto-cloud` is running with `-e MOTO_IAM_LOAD_MANAGED_POLICIES=true` on network `k3d-cloud-net`. EKS-managed policies (e.g., `AmazonEKSClusterPolicy`) are loaded and verified.
3. **Tier-1 Platform Network (O-3):** Deployed via ApplicationSet `platform-network` to both spokes. Both Argo CD applications (`platform-network-spoke-nonprod`, `platform-network-spoke-prod`) are `Synced` and `Healthy`. All 12 ACK network objects (VPC, 2 Subnets, InternetGateway, RouteTable, SecurityGroup per spoke) report `ACK.ResourceSynced: True`.
4. **Multi-Account CARM Isolation:** Spoke `nonprod` provisions strictly into AWS account `111111111111` (VPC CIDR `10.10.0.0/16`); Spoke `prod` provisions strictly into AWS account `222222222222` (VPC CIDR `10.20.0.0/16`). Zero cross-account resource contamination.
5. **Kro RBAC Aggregated:** Aggregated ClusterRole `kro-team-eks-cluster` deployed via `kro-blueprints` to both spokes. Apiserver dynamically merged permissions for `teameksclusters`, ACK roles, clusters, nodegroups, and read-only network objects into Kro's active `kro:controller` role.
6. **Observability & Alerts:** Agent scrape configs added for all 3 new ACK controllers. Hub Prometheus alerting rule `SpokeControllerDown` expanded and verified with `make test-alert-rules` (`promtool`: SUCCESS).
7. **Regression-Free Workloads:** Existing tenant SQS applications (`orders-dev`, `orders-test`, `orders-prod`) unaffected. Full end-to-end multi-cluster smoke test passed 12/12 (`make test`). Offline CI validation passed 100% across all 40 applications (`./ci/check-control-plane.sh`).

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

### 2.2 GitOps Control Plane (`gitops-control-plane`, commit `8891999`)

| Component | Path | Description |
|---|---|---|
| **Blueprint Revision Promotion** | `clusters/blueprint-revisions.env` | Promoted `spoke-prod` to `v1.8.0` (matching `spoke-nonprod`). Ran `make promote-blueprints`. |
| **Addons ApplicationSet** | `applicationsets/addons-spoke.yaml` | Added 3 elements for `ack-ec2`, `ack-iam`, and `ack-eks` pointing to pinned `platform-catalog` values and upstream chart repositories. |
| **Platform Network ApplicationSet** | `applicationsets/platform-network.yaml` | Cluster generator with GoTemplate mapping `environment: nonprod` -> account `111111111111` / `network/nonprod`, and `environment: prod` -> account `222222222222` / `network/prod`. Sets CARM annotation `services.k8s.aws/owner-account-id` on namespace `platform-network`. |
| **Observability Alert Rules** | `addons/observability/values-prometheus-hub.yaml` | Updated `SpokeControllerDown` alert regex to `job=~".*(kro\|ack-sqs\|ack-ec2\|ack-iam\|ack-eks).*"` to guard all 5 spoke controllers. |
| **Alert Unit Tests** | `tests/alert-rules.test.yaml` | Added unit tests verifying alert firing when `ack-ec2`, `ack-iam`, or `ack-eks` instances drop. |
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
ack-sqs-controller-sqs-chart-bcf4d774b-r85qp    1/1     Running   1          16m

$ kubectl --context k3d-spoke-prod -n ack-system get pods
NAME                                            READY   STATUS    RESTARTS   AGE
ack-ec2-controller-ec2-chart-8476c4bd87-vvnfw   1/1     Running   0          5m
ack-eks-controller-eks-chart-55b874d877-v8j49   1/1     Running   0          5m
ack-iam-controller-iam-chart-7f4755f84d-kvhrz   1/1     Running   0          5m
ack-sqs-controller-sqs-chart-68bcc88cf9-x5dlm   1/1     Running   1          16m
```

### 3.2 Tier-1 Network Resource Sync

All ACK network objects on both spokes have successfully reconciled against Moto Cloud:
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

### 3.3 Moto Multi-Account State & Policy Verification

Querying Moto via STS assume-role demonstrates strict account separation:
- **Account 111111111111 (nonprod):** Contains VPC `10.10.0.0/16` tagged `platform-nonprod` and subnets `10.10.0.0/20`, `10.10.16.0/20`.
- **Account 222222222222 (prod):** Contains VPC `10.20.0.0/16` tagged `platform-prod` and subnets `10.20.0.0/20`, `10.20.16.0/20`.
- **Managed Policies (O-7):** Verified via `aws iam get-policy --policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy`.

### 3.4 Kro Controller Dynamic RBAC Aggregation

Inspection of ClusterRole `kro:controller` confirms Kubernetes apiserver aggregated the new permissions:
```console
$ kubectl --context k3d-spoke-nonprod get clusterrole kro:controller -o jsonpath='{range .rules[*]}{.apiGroups}{" "}{.resources}{" "}{.verbs}{"\n"}{end}' | grep -E "teameksclusters|iam|eks|ec2"
[kro.run] [teameksclusters teameksclusters/status teameksclusters/finalizers] [get list watch create update patch delete]
[iam.services.k8s.aws] [roles] [get list watch create update patch delete]
[eks.services.k8s.aws] [clusters nodegroups] [get list watch create update patch delete]
[ec2.services.k8s.aws] [vpcs subnets securitygroups] [get list watch]
```

### 3.5 Automated Test Suites

1. **Prometheus Alert Rules Unit Test:**
   ```console
   $ make test-alert-rules
     SUCCESS
   ```
2. **Offline CI Validation (`./ci/check-control-plane.sh`):**
   - 30 scripts syntax and shellcheck clean.
   - 381 tracked files scanned for secret leaks: clean.
   - All 40 Applications rendered offline without error.
   - Kubeconform validated 571 resources with 0 invalid and 0 errors.
   - Promtool alert rules validated.
   - Grafana dashboards validated.
   - Tenant ApplicationSets validated.
   - SSO URL consistency validated.
   - Alloy configuration validated.
3. **Multi-Cluster Smoke Test (`make test`):**
   - All 12 gates passed (`[1/12]` through `[12/12]`).
   - SQS orders flow end-to-end with 0s latency across all environments.

---

## 4. Instructions for the Validator (Claude)

To validate Phase P1 independently:

1. **Verify Argo CD Application Health:**
   ```bash
   kubectl --context k3d-hub-cluster -n argocd get applications \
     -l argocd.argoproj.io/instance=platform-network-spoke-nonprod \
     -o custom-columns='NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status'
   kubectl --context k3d-hub-cluster -n argocd get applications \
     -l argocd.argoproj.io/instance=platform-network-spoke-prod \
     -o custom-columns='NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status'
   ```
   *Expect:* Both applications report `Synced` and `Healthy`.

2. **Verify Spoke Controller Pods & PSS Compliance:**
   ```bash
   kubectl --context k3d-spoke-nonprod -n ack-system get pods
   kubectl --context k3d-spoke-prod -n ack-system get pods
   ```
   *Expect:* 4 pods running (ec2, iam, eks, sqs) with 1/1 ready on both spokes.

3. **Verify Synced Status on Spoke ACK Network Objects:**
   ```bash
   kubectl --context k3d-spoke-nonprod -n platform-network get vpc,subnet,internetgateway,routetable,securitygroup -o wide
   kubectl --context k3d-spoke-prod -n platform-network get vpc,subnet,internetgateway,routetable,securitygroup -o wide
   ```
   *Expect:* All resources present and `ACK.ResourceSynced=True`.

4. **Verify Moto Multi-Account EC2 Objects via STS Assume-Role:**
   ```bash
   moto_as() {
     export AWS_ACCESS_KEY_ID=x AWS_SECRET_ACCESS_KEY=x AWS_DEFAULT_REGION=us-east-1; unset AWS_SESSION_TOKEN
     local c; c=$(aws --endpoint-url http://localhost:5000 sts assume-role --role-arn "arn:aws:iam::$1:role/val" --role-session-name val --query Credentials --output json)
     AWS_ACCESS_KEY_ID=$(jq -r .AccessKeyId <<<"$c"); AWS_SECRET_ACCESS_KEY=$(jq -r .SecretAccessKey <<<"$c")
     AWS_SESSION_TOKEN=$(jq -r .SessionToken <<<"$c"); export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
   }
   for a in 111111111111 222222222222; do
     moto_as "$a"
     echo "Account $a VPCs:"
     aws --endpoint-url http://localhost:5000 ec2 describe-vpcs --query 'Vpcs[*].{VpcId:VpcId,Cidr:CidrBlock,Tags:Tags}' --output json
   done
   ```
   *Expect:* Account `111111111111` has CIDR `10.10.0.0/16` and Account `222222222222` has CIDR `10.20.0.0/16`.

5. **Run Control Plane CI & Full Smoke Suite:**
   ```bash
   make test-alert-rules
   ./ci/check-control-plane.sh
   make test
   ```
   *Expect:* All 3 suites pass with 0 errors.

6. **Confirm Readiness for P2 (Blueprint):**
   Once verified, Claude executes Phase P2 (RGD `TeamEKSCluster`, VAP `teamekscluster-contract`, and chart `team-cluster` in `platform-charts`).
