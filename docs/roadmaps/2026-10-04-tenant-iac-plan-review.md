# Critical Architectural Review: Tenant IaC Self-Service Team Clusters Plan (v0.1)
## Evaluation of Claude's Draft Plan for "API Workflow Simulation & GitOps Contract Validation"

> **Document Status:** Official Review  
> **Reviewer:** Antigravity (Principal Platform & GitOps Architect)  
> **Target Document:** [`docs/roadmaps/2026-10-04-tenant-iac-team-clusters-plan.md`](file:///home/bleite/repos/gitops-control-plane/docs/roadmaps/2026-10-04-tenant-iac-team-clusters-plan.md)  
> **Date:** 2026-10-04  
> **Platform Baseline:** Phase 5 v1.1 Complete (Argo CD v3.5.3, Kro v0.9.4, ACK SQS 1.7.1, CARM, Moto 5.0.x)  
> **Core Objective:** Establish a declarative, self-service IaC pattern for team EKS clusters focused on **API workflow simulation & GitOps contract validation** to mature patterns locally prior to enterprise AWS EKS adoption (Phase 6).

---

## 1. Executive Summary & Verdict

The draft roadmap authored by Claude ([`docs/roadmaps/2026-10-04-tenant-iac-team-clusters-plan.md`](file:///home/bleite/repos/gitops-control-plane/docs/roadmaps/2026-10-04-tenant-iac-team-clusters-plan.md)) demonstrates sound initial reconnaissance regarding AWS Moto's live EKS behaviors and correctly identifies the platform's existing GitOps building blocks (per-tenant ApplicationSets, CARM multi-account annotations, Kro admission contracts, and required PR checks).

However, from an enterprise systems architecture, local stability, and operational reality standpoint, **the plan contains several critical architectural liabilities, scope distractions, and fragility traps** that must be resolved before any code is committed.

### Assessment Scorecard

| Dimension | Rating | Finding |
|---|---|---|
| **1. Goal & Scope Alignment** | ⚠️ **Marginal** | Distracted by Option P6 (vcluster). The user's explicit objective is *API workflow simulation and GitOps contract validation*. Introducing nested vclusters creates architectural dissonance and diverts engineering energy from contract maturity. |
| **2. Controller & CRD Footprint** | 🔴 **High Risk** | Deploying full EC2, IAM, and EKS ACK controllers across both spokes injects **65+ custom CRDs** into lightweight k3s clusters, risking etcd memory ballooning, API server OpenAPI latency, and CI schema thrashing. |
| **3. Kro Composability & Failure Modes** | 🔴 **High Risk** | Monolithic 6-level Kro DAG (`VPC` $\rightarrow$ `Subnets` $\rightarrow$ `IGW/RouteTable` $\rightarrow$ `SG` $\rightarrow$ `IAM Roles` $\rightarrow$ `EKS Cluster` $\rightarrow$ `Nodegroup`) will suffer asynchronous CEL resolution failures and ACK finalizer deadlocks during teardown. |
| **4. Tenancy & Repository Topology** | 🟡 **Needs Refinement** | Immediately creating a 6th standalone repository (`tenant-iac`) introduces outsized maintenance overhead (CI workflows, CODEOWNERS, token distribution) without first standardizing the generator and contract boundary. |
| **5. AWS / Moto Compatibility** | 🟢 **Good Probing / Needs Tuning** | Probed Moto capabilities accurately, but fails to specify the exact ACK Helm chart flags required to disable unsupported Moto EKS features (Access Entries, Addons) to prevent reconciliation CrashLoopBackOffs. |

**Final Recommendation:** **Revise with Architectural Pivot**. Reject P6 (vcluster). Decouple raw network infrastructure from team cluster compute by adopting a **Two-Tier Enterprise Model** (Platform Network Pool vs Team EKS Cluster), reduce CRD footprint by up to 70%, and harden Kro CEL status evaluation against asynchronous ACK updates.

---

## 2. In-Depth Architectural Critique

### 2.1 Scope Creep & The "P6 (vcluster) Illusion"
Claude's plan spends significant narrative space framing Option **P6** (deploying vcluster alongside Moto records) and designates it as owner decision **O-1**.

#### The Flaw
The owner explicitly clarified the boundary:
> *"the goal is 'API workflow simulation & GitOps contract validation' you've got it, this is a lab for learning the pattern for eventually bring the learning for a real AWS environment, but first I need to mature the flow."*

Introducing vcluster creates a split reality:
1. GitOps reconciles AWS Moto records (`Cluster`, `Nodegroup`, `Role`, `VPC`).
2. A sidecar vcluster orchestrator spawns a nested k8s control plane inside k3d.
3. Developers interact with vcluster endpoints that have **zero structural or identity parity** with AWS IAM authenticator, AWS VPC CNI, or EKS security groups.
4. When migrating to real AWS in Phase 6, vcluster is entirely discarded, meaning none of the operational or security patterns developed around vcluster carry forward.

#### The Verdict
**Excise P6 entirely from the roadmap.** The value of this lab is validating the end-to-end GitOps contract:
$$\text{Git PR} \longrightarrow \text{CI Policy/VAP} \longrightarrow \text{Argo CD} \longrightarrow \text{Kro Instance} \longrightarrow \text{ACK Controllers} \longrightarrow \text{Cloud State \& Status}$$
Developers and automated smoke tests validate that the cloud resources exist, have valid ARNs, endpoints, OIDC issuers, tags, and cross-account isolation.

---

### 2.2 The ACK Controller CRD Avalanche (65+ CRDs on k3s)
Claude proposes deploying three new ACK controllers to `addons-spoke.yaml` across both `spoke-nonprod` and `spoke-prod`:
- `ack-ec2-controller` (v1.21.2)
- `ack-iam-controller` (v1.9.1)
- `ack-eks-controller` (v1.23.1)

#### The Hidden Footprint
| Controller | Upstream CRD Count | Key Resources |
|---|---|---|
| `ack-ec2-controller` | **45+ CRDs** | `VPC`, `Subnet`, `RouteTable`, `InternetGateway`, `NatGateway`, `SecurityGroup`, `Instance`, `LaunchTemplate`, `TransitGateway`, `VPCPeeringConnection`, `NetworkInterface`, etc. |
| `ack-iam-controller` | **15+ CRDs** | `Role`, `Policy`, `InstanceProfile`, `OpenIDConnectProvider`, `Group`, `User`, etc. |
| `ack-eks-controller` | **6 CRDs** | `Cluster`, `Nodegroup`, `FargateProfile`, `Addon`, `AccessEntry`, `PodIdentityAssociation` |
| **Total Injected** | **66+ CRDs** | Multiplied across both spoke clusters + local schema tooling |

#### Consequences for the Local Platform
1. **K3s etcd & API Server Memory:** Injecting 66 sprawling AWS CRDs into k3d k3s nodes swells the API server OpenAPI schema memory footprint and increases discovery latency for `kubectl`, Headlamp, and Argo CD.
2. **Kubeconform CI Thrashing:** The CI toolkit relies on pre-cached CRD schemas. Downloading and caching OpenAPI v3 schemas for 66 AWS resources in GitHub Actions or local pre-commit hooks adds noticeable latency.
3. **Controller Pod Sprawl:** Running 3 controllers $\times$ 2 spokes adds 6 Go controller pods. Under CRD reconciliation loops, memory spikes frequently exceed the proposed 64Mi limits, risking OOMKills.

#### Architectural Alternative: Two-Tier Separation
In mature AWS enterprise environments, **application teams do not provision their own VPCs, Internet Gateways, and Route Tables**. Platform Network teams provision shared, segmented VPCs and subnets once; development teams provision their EKS clusters into pre-allocated platform subnets.

By providing a **Platform Network Baseline** (either binding to Moto's pre-existing default VPC `172.31.0.0/16` or deploying a platform VPC once), the team blueprint only requires:
- `iam.services.k8s.aws/Role` (Cluster & Node roles)
- `eks.services.k8s.aws/Cluster`
- `eks.services.k8s.aws/Nodegroup`

This eliminates `ack-ec2-controller` from the required spoke footprint, **slashing the CRD load by ~70%** (from 66 CRDs down to ~21 CRDs).

---

### 2.3 Kro Composability & Asynchronous Status Traps
Claude's proposed Kro RGD `TeamCluster` attempts to orchestrate a single massive DAG:
$$\text{VPC} \longrightarrow \text{Subnets} \longrightarrow \text{RouteTable/IGW} \longrightarrow \text{SG} \longrightarrow \text{IAM Roles} \longrightarrow \text{EKS Cluster} \longrightarrow \text{Nodegroup}$$

#### Critical Failure Mode 1: Asynchronous Status Resolution
In Kubernetes and ACK, status fields (e.g., `${vpc.status.vpcID}`, `${subnet.status.subnetID}`) are **not populated immediately**. The CR is admitted with empty status; the ACK controller asynchronously calls AWS/Moto, obtains the resource ID, and updates the status subresource seconds later.

In Kro (v0.8.x / v0.9.x), referencing a status field that does not yet exist in an intermediate template (e.g. `${vpc.status.vpcID}` in `Subnet.spec.vpcID`) causes CEL evaluation failure during the initial reconciliation passes:
```text
evaluation error: no such key: vpcID
```
Unless fields use safe CEL navigation or Kro readiness gates, intermediate resources fail to compile, triggering reconciliation retries and potential sync lockups in Argo CD.

#### Critical Failure Mode 2: Cascade Teardown Deadlocks
ACK controllers install Kubernetes finalizers (e.g., `finalizers.ack.aws.amazon.com`).
When a tenant cluster is deleted:
1. An AWS EKS Cluster cannot be deleted if it has active Nodegroups.
2. An AWS Security Group cannot be deleted if it is attached to an active EKS Cluster.
3. An AWS Subnet cannot be deleted if network interfaces (ENIs) or clusters reside in it.
4. An AWS VPC cannot be deleted if subnets exist.

If Kro triggers simultaneous deletions or does not strictly reverse the dependency order during garbage collection, ACK finalizers will hang indefinitely, leaving the namespace permanently stuck in `Terminating`. Claude's plan defers this to "check deletion order in P0" without defining the architectural mitigation.

---

### 2.4 Tenancy Model: The 6th Repo Tax vs Governance
Claude proposes a completely new repository: `tenant-iac`.

#### Operational Friction
Adding a 6th repository (`gitops-control-plane`, `platform-catalog`, `platform-charts`, `tenant-workloads`, `orders-processor`, and now `tenant-iac`) incurs substantial recurring platform maintenance:
- Dedicated GitHub repository creation, permissions, and GitHub Actions tokens.
- Separate CODEOWNERS, branch protection rulesets, and pull request policies.
- New CI validation script (`ci/check-tenant-iac.sh`).
- Updates to `scripts/tenant-appset.sh`, which currently hardcodes `tenant-workloads.git`.

#### Strategic Alignment
While creating `tenant-iac` has operational costs, **it accurately reflects enterprise reality**: infrastructure definitions should be isolated from application code to enforce stricter RBAC and audit policies.
However, the rollout must be structured cleanly:
- Provide a parameterized ApplicationSet generator (`scripts/tenant-iac-appset.sh`).
- Ensure the CI validation script strictly mirrors the established Track A/B conventions.
- Provide an integrated alternative fallback for single-repo testing.

---

### 2.5 AWS Moto API Emulation Reality
Claude noted that EKS Access Entries and Addons return HTTP 404 in Moto.
However, the plan fails to address how `ack-eks-controller` behaves out of the box:
- By default, modern `ack-eks-controller` versions attempt to reconcile EKS Managed Addons (e.g., VPC CNI, CoreDNS, Kube-Proxy) and Access Entries.
- When the controller calls Moto's unsupported endpoints, Moto returns 404/500, causing the controller to mark the CR as `ACK.ResourceSynced=False` and log continuous error backoffs.

#### Required Mitigation
The Helm values for `ack-eks-controller` in `platform-catalog/controllers/ack/values-eks.yaml` must explicitly disable unsupported features via controller flags or ensure the Kro blueprint templates omit all optional addon and access entry fields.

---

## 3. Review of Claude's Decisions (§7)

| ID | Decision Question | Claude's Recommendation | Antigravity Critical Evaluation |
|---|---|---|---|
| **O-1** | Moto-only cloud records vs real usable clusters (P6, vcluster)? | *"Start moto-only, decide P6 after seeing it work"* | **Definitive Rejection of P6**. Do not leave P6 lingering as an open question. The platform's stated goal is GitOps API contract simulation. vcluster adds unnecessary cognitive and operational baggage with zero parity to real AWS EKS. |
| **O-2** | Dedicated `tenant-iac` repo for all teams vs subfolder in `tenant-workloads`? | *"Yes: one repo, one ApplicationSet per team"* | **Approved with Rigor**. Adopt `tenant-iac` because enterprise IaC demands distinct RBAC and approval workflows from application manifests. Parameterize the generator script (`scripts/tenant-iac-appset.sh`). |
| **O-3** | Network: teams pick `vpcCidr` from pool or platform assigns? | *"Team picks from pool, CI + VAP check"* | **Modify to Two-Tier Platform Pool**. Asking teams to declare raw CIDRs and subnets forces them to think like network engineers. Better enterprise abstraction: Teams reference a named network pool (e.g. `platform-default` or `analytics-vpc`), and the blueprint binds to pre-existing or platform-managed subnets. |
| **O-4** | Where do ACK controllers run? | *"On the spokes, per environment"* | **Approved with Resource Guards**. Run on spokes via CARM account mapping (`111111111111` for nonprod, `222222222222` for prod). Start with Lean EKS (EKS + IAM only); introduce EC2 controller only if dynamic VPC provisioning is explicitly required. |
| **O-5** | Prod clusters and gates? | *"Yes, with PR + required check + CODEOWNERS + retain"* | **Approved**. Prod must enforce: full 40-char commit SHA pinning, `services.k8s.aws/deletion-policy: retain`, and restricted team quotas. |
| **O-6** | Initial team and cluster names? | *`team-data` with `analytics-dev`* | **Approved**. Excellent initial tenant candidate, matching existing platform convention (`orders-processor` for e-commerce, `analytics` for data squad). |

---

## 4. Architectural Directives for the Antigravity Proposal (`-agy.md`)

To transform this concept into an enterprise-grade, resilient platform capability, the revised proposal must execute on the following architectural directives:

1. **Focus 100% on API Simulation & Contract Validation:** Discard all references to nested vclusters. Measure success by GitOps sync health, admission policy enforcement, AWS API fidelity in Moto, and clean tear-down.
2. **Implement the Two-Tier Network Model (Lean Architecture):**
   - Provide **Profile A (Lean EKS - Recommended)**: Deploys `ack-eks-controller` + `ack-iam-controller`, binding clusters to the platform's baseline network. Footprint: 21 CRDs, 2 pods per spoke.
   - Provide **Profile B (Full Infrastructure Stack)**: Includes `ack-ec2-controller` with dynamic VPC/Subnet generation for teams requiring complete network isolation drills.
3. **Harden Kro Schema & Status Projections:**
   - Define a minimal, immutable Kro schema (`TeamEKSCluster`).
   - Use safe CEL navigation (`.?`) and explicit status readiness conditions to prevent reconciliation lockups.
   - Delegate all value constraints (versions, sizes, types) to a Kubernetes Validating Admission Policy (`teamekscluster-contract`).
4. **Harden ACK Controller Helm Values:**
   - Digest-pin container images.
   - Configure Moto endpoint (`http://moto-cloud:5000`) and bypass TLS/signature validation where appropriate.
   - Set realistic resource requests/limits (100m/128Mi request, 300m/384Mi limit) to avoid OOMKills during CRD ingestion.
5. **Standardize the Tenancy Lifecycle in `tenant-iac`:**
   - Dedicated AppProject `tenant-iac` with destination namespace pattern `iac-*`.
   - Generator script `scripts/tenant-iac-appset.sh` matching the established B.2 pattern.
   - CI validation script enforcing CIDR/name uniqueness, commit SHA pinning for prod, and kubeconform schema checks.

---

## 5. Conclusion

Claude's draft plan provides a useful starting baseline and verified Moto's API response profile. However, pursuing it without addressing CRD bloat, Kro asynchronous status hazards, and scope sprawl risks destabilizing the local platform.

The refined architecture document—[`docs/roadmaps/2026-10-04-tenant-iac-proposal-agy.md`](file:///home/bleite/repos/gitops-control-plane/docs/roadmaps/2026-10-04-tenant-iac-proposal-agy.md)—implements these recommendations into an actionable, phased engineering blueprint ready for immediate execution.
