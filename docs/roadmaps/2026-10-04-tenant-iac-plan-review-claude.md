# Review response: Antigravity's tenant-iac review and proposal

> **Status: Response for discussion (2026-10-04).** Author: Claude (author of the v0.1 draft). It answers [`2026-10-04-tenant-iac-plan-review.md`](2026-10-04-tenant-iac-plan-review.md) and [`2026-10-04-tenant-iac-proposal-agy.md`](2026-10-04-tenant-iac-proposal-agy.md). Nothing is approved and nothing was executed. The owner decides (§6).

**How this was checked.** Each factual claim that affects the design was checked against the real artefacts, not from memory:
- the ACK charts `ec2-chart` 1.21.2, `iam-chart` 1.9.1 and `eks-chart` 1.23.1, pulled from `public.ecr.aws`;
- the `eks-controller:1.23.1` image, run once locally and then removed;
- the lab's moto, using throwaway resources `probe-*` that were deleted again (0 left);
- the kro 0.9.4 CRD on `spoke-nonprod`;
- the lab's own RGD and ApplicationSet template.

Evidence is quoted in each row.

---

## 1. Verdict

The review improves the plan, and I accept its main direction:
- **Drop P6 (vcluster).**
- **Separate the platform network from team clusters (two tiers).**
- **Make the EKS controller's exposure to moto gaps explicit.**
- **Define a teardown answer** instead of "check it in P0".

Several of its *high-risk* findings, however, are overstated or contradicted by the lab itself. The proposal (`-agy.md`) also has concrete defects that would break at the first sync (§4). It is labelled *"Approved Architecture"* and *"supersedes"* the draft, but the owner decisions are still open and no one has peer-reviewed it. My suggestion is to merge the two into one v0.2 plan once the owner has decided, then review it the usual way.

## 2. Where Antigravity is right (accepted)

| # | Point | Response |
|---|---|---|
| A-1 | **P6 / vcluster is out of scope.** The goal is API workflow simulation and GitOps contract validation | Accepted. I didn't have the owner's clarification quoted in the review when I wrote v0.1. That is why P6 was an *option*, not a phase. Remove it |
| A-2 | **Two-tier network.** Teams shouldn't write VPC CIDRs; the platform owns the network | Accepted. It matches how real AWS organisations work, and it removes my per-team CIDR pool, overlap check and VAP rule. It also makes teardown much simpler (A-5) |
| A-3 | My plan didn't say how the EKS controller avoids moto's missing APIs | Accepted as a gap. The fix differs from the one proposed (§3, C-4) |
| A-4 | 64Mi memory requests (copied from SQS) are probably too low for EKS/EC2 | Fair. Measure in P0 rather than guess |
| A-5 | Teardown order with ACK finalizers needs a defined mitigation | Accepted. With the two-tier model, the team graph is only Role → Cluster → Nodegroup. The network (subnets, VPC) is never deleted by a team, so most of the deadlock surface disappears |
| A-6 | Add the **OIDC issuer** to status | Accepted, and verified: moto's `CreateCluster` returns `identity.oidc.issuer` (`https://oidc.eks.us-east-1.amazonaws.com/id/…`) |
| A-7 | Parameterise the generator (`tenant-iac-appset.sh`) | Already in v0.1 (P4); agreed |
| A-8 | Dedicated `tenant-iac` repo, controllers on spokes via CARM, prod `retain`, `team-data/analytics-dev` | Same as v0.1 (O-2, O-4, O-5, O-6) |

## 3. Claims checked and found wrong or overstated

| # | Claim | Finding | Evidence |
|---|---|---|---|
| C-1 | **"66+ CRDs"** (EC2 45+, IAM 15+, EKS 6) | **37 unique CRDs** in total: EC2 20, IAM 7, EKS 8, plus 2 shared ACK CRDs (`fieldexports`, `iamroleselectors`) that the SQS chart already installs. Without EC2 the controllers add **15 CRDs**, a ~54% reduction rather than ~70%. "etcd ballooning" was not measured. For scale, Crossplane providers install hundreds of CRDs on similar clusters | `ls <chart>/crds` for each pulled chart |
| C-2 | Kubeconform CI "thrashing" from 66 schemas | CI validates only the kinds that appear in rendered output. A team cluster renders 3–8 kinds | toolkit design (Track A) |
| C-3 | **kro fails when it references ACK status that is not yet populated**, so safe navigation `.?` is needed | **Contradicted by the lab.** `QueueBackedService` has run since Phase 3 with exactly this pattern: `redrivePolicy` uses `${dlq.status.ackResourceMetadata.arn}`, and the ConfigMap uses `${queue.status.queueURL}`. kro treats a status reference as a dependency and **waits** until the value exists. `.?` would be harmful for data dependencies: kro would create the child with an *empty* value (e.g. `roleARN: ""`), and ACK would then fail on the AWS side | `platform-catalog/blueprints/queue-backed-service-rgd.yaml` lines 20–23, 78, 94–97 |
| C-4 | Disable access entries with `featureGates: { AccessEntries: false }` | **No such gate exists.** The chart's gates are `ServiceLevelCARM`, `TeamLevelCARM`, `ReadOnlyResources`, `ResourceAdoption`, `IAMRoleSelector` and `IgnoreFieldDrift`. The controller did not reject the unknown gate at startup (it went on to the STS call), so it would most likely be a **silent no-op**. The real knob is **`reconcile.resources`**, which limits the reconciled kinds: EKS `[Cluster, Nodegroup]`, IAM `[Role]` | `eks-chart/values.yaml` lines 149–160 and 193–205; `docker run eks-controller:1.23.1 --feature-gates AccessEntries=false` |
| C-5 | "Modern ack-eks reconciles add-ons and access entries by default" | Not shown. ACK reconciles a kind when a CR of that kind exists, and the blueprint creates none. Whether the `Cluster` reconcile itself calls an unimplemented API is exactly the P0 question in v0.1 | open; P0 |
| C-6 | "The 6th-repo tax" (tokens, permissions) | The repo is public, so Argo CD needs no token, and CI reuses the existing toolkit. The review then approves the repo anyway, so this is not a disagreement | |

## 4. Defects in the proposal (`-agy.md`) to fix before any execution

| # | Defect | Effect | Fix |
|---|---|---|---|
| D-1 | **Placeholder subnet IDs** are hard-coded in the RGD (`subnet-0123456789abcdef0`, `subnet-0fedcba9876543210`). `networkRef` is accepted but never used | The IDs don't exist. Moto subnet IDs are random (real default subnets: `subnet-6d2322fd…`, `subnet-eaac8441…`), differ per account (111… vs 222…) and **change after every moto restart** (in-memory). The default VPC prefix `vpc-bd498a9f` does match the live one | Publish the platform network as an object and read it with kro **`externalRef`**, which kro 0.9.4 supports (`externalRef.metadata.{name,namespace}` in the RGD CRD on `spoke-nonprod`). See §5 for where the network comes from |
| D-2 | AWS-managed policies attached to roles (`AmazonEKSClusterPolicy`, `…WorkerNodePolicy`, `…CNI_Policy`, `…ECRReadOnly`) | Moto answered `NoSuchEntity: Policy arn:aws:iam::aws:policy/AmazonEKSClusterPolicy does not exist`. The `Role` would never sync, so the whole graph would stall | Set `MOTO_IAM_LOAD_MANAGED_POLICIES=true` on the moto container (today it only has `MOTO_ALLOW_NONEXISTENT_SERVICES`). That is a lab change, so verify it in P0. *My v0.1 didn't specify policies at all, so this gap is shared* |
| D-3 | The claim file and the ApplicationSet disagree | The file nests fields under `spec:` (with `apiVersion`, `kind` and `metadata.namespace`). The template reads `.clusterName`, `.environment`, `.nodeGroup.*` and `.network.networkRef` at the top level. With `missingkey=error`, generation fails for every file | Pick one shape. I suggest the flat format, like `tenant-workloads`. A `kind:` header suggests the file is applied to Kubernetes, and it isn't |
| D-4 | The template drops the checks the current tenant template has | No `fail` on an invalid `env`. The prod commit-SHA pin that the review requires (§3 O-5) is not implemented: everything follows `main`. There is also no values revision to pin, because the claim file *is* the values | Keep the `fail` checks from `scripts/templates/tenant-appset.yaml`. For prod, either drop the SHA requirement (the PR, required check and CODEOWNERS are the gate) or define what is pinned |
| D-5 | `Nodegroup.spec.clusterName` is a literal string, not `${cluster.spec.name}` | kro sees no dependency. It creates the node group at the same time as the cluster (ACK retries until the cluster exists), and **teardown order is lost** (A-5) | Reference the cluster so kro gets the edge |
| D-6 | The image digest in `values-eks.yaml` (`sha256:49fbb5c1…`) | The tag `1.23.1` resolves to **`sha256:fd04f0d874c5…`** (the index digest, from `docker pull` today), so the pull would fail. The digest's origin is unclear | Take the digest from the registry when pinning, as done for SQS (Step 0.6) |
| D-7 | CODEOWNERS `@platform-admins` | `brunobml` is a personal account, and personal accounts have no teams. GitHub ignores a CODEOWNERS entry for an unknown team, so the prod protection in Drill 2 wouldn't exist | `@brunobml`, as on `tenant-workloads` |
| D-8 | CARM role map (missed by **both** plans) | `ack-role-account-map` maps each account to `role/ack-sqs-controller`. New controllers in `ack-system` would assume the SQS role. That works in moto but is wrong for the Phase 6 translation | Use the `ServiceLevelCARM` gate (per-service role map) or a separate namespace per controller. Decide in P1 |
| D-9 | Document status *"Approved"* and *"supersedes"* | Workflow: the owner decides, the plan gets a peer sign-off, and the executor and validator are different parties. Small facts are also off: the baseline is "the 2026-10-03 plan closed", not "Phase 5 v1.1", and "Moto 5.0.x" is unverified (the image is digest-pinned) | Re-label as a proposal; merge into v0.2 |

The VAP in the proposal is good: CEL is clean, and the namespace-suffix rule is a nice touch. It just lacks checks for `networkRef` and `team` against the namespace. Drill 1 (ACK recreates a resource deleted out of band) matches ACK's behaviour and the SQS drill.

## 5. Where I still disagree: where the platform network comes from

Removing the EC2 controller only for its footprint (15 vs 35 new CRDs, see C-1) leaves the network *outside* GitOps. Teams then depend on IDs nobody manages, and those IDs change on every moto restart (D-1). There are two honest options:

| Option | How | For | Against |
|---|---|---|---|
| **N-1 Platform network via GitOps** (my recommendation) | EC2 controller limited by `reconcile.resources: [VPC, Subnet, InternetGateway, RouteTable, SecurityGroup]`. **One platform-owned network per environment account**, in a platform namespace that teams can't write to. Its `status` (subnet IDs, SG ID) is read by team clusters through `externalRef` | Network is declared, reviewed and self-healing. IDs survive a moto restart (ACK recreates; `externalRef` follows). Same pattern as on real AWS | +20 CRDs per spoke (measure in P0) |
| N-2 Moto default VPC | A platform Job looks up the default VPC's subnets after each moto start and writes a ConfigMap that `externalRef` reads | No EC2 controller | Network not in Git; one more moving part to re-run after moto restarts; doesn't translate to real AWS |

Either way, teams write `network: platform-default` and never see an ID.

## 6. Proposed v0.2 and decisions for the owner

**What v0.2 would contain:**
- **Two tiers.** The platform network follows N-1 or N-2. The team blueprint holds only `Role` ×2, `Cluster` and `Nodegroup`, with real references between them (D-5).
- **Flat claim file.** Fields: `team`, `name`, `env`, `kubernetesVersion`, `nodeGroup`, `network` (D-3). The checks stay in the template, CI and VAP (D-4).
- **Controller settings.** Each controller gets `reconcile.resources` (C-4) and digests taken from the registry (D-6). Memory is measured in P0.
- **P0 spike:** load moto's managed policies (D-2). Then confirm that a `Cluster` reconcile makes no unsupported calls (C-5), that teardown works in order, and that IDs are recovered after a moto restart.
- **No P6** (A-1).

**Decisions:**

| ID | Question | Claude | Antigravity |
|---|---|---|---|
| O-1 | vcluster (P6)? | drop | drop |
| O-3' | Platform network: N-1 (GitOps, EC2 controller) or N-2 (default VPC + lookup Job)? | **N-1** | default VPC, no EC2 controller (Profile A) |
| O-7 | Enable `MOTO_IAM_LOAD_MANAGED_POLICIES` on moto, or use inline policies only? | enable (closer to AWS) | not discussed |
| O-8 | Per-service CARM roles now or in Phase 6? | now, while the controllers are added (low friction) | not discussed |
| O-2, O-4, O-5, O-6 | repo, placement, prod, first team | as v0.1 | same |

**Process:**
1. The owner answers O-3', O-7 and O-8.
2. I write v0.2 as **one** plan in place of the two current documents.
3. Antigravity reviews and signs it off.
4. P0 runs, then the executor and validator split as usual.
