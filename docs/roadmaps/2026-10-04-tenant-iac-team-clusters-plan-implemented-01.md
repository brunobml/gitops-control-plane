# Tenant IaC plan v0.2: P0 spike report (implemented-01)

> **Status: For independent validation (2026-10-04).** Executor: Claude (Opus 5.5). Plan: [`2026-10-04-tenant-iac-team-clusters-plan.md`](2026-10-04-tenant-iac-team-clusters-plan.md) (Approved v0.2, `d8fe768`). Only P0 was executed: a throwaway cluster and moto, **the lab was not touched** (hub, spokes, `moto-cloud`, Git state of the platform repos unchanged). The executor does not validate its own work.

**Verdict: GO for P1, with design changes.** All seven gates pass or have a verified workaround. The workarounds change the blueprint, the controller values and the operations runbook. They are listed in §4 as proposed v0.3 amendments, for review before P1.

**Reproduce:** [`tenant-iac-p0-spike/spike.sh`](tenant-iac-p0-spike/spike.sh) `up | claims | status | recover | down`. All manifests the spike ran are in that folder, in their final form. A clean `up` takes ~50 s; the network syncs in ~5 s; three claims are ready in ~3 s.

## 1. Setup

| Item | Value |
|---|---|
| Cluster | k3d `iac-spike`, k3s v1.35.5 (same as the spokes), API on 127.0.0.1:6559, no Traefik/metrics-server |
| moto | `moto-spike`, same image digest as the lab, `MOTO_IAM_LOAD_MANAGED_POLICIES=true` (O-7), port 127.0.0.1:5001 |
| kro | 0.9.4, lab values (`rbac.mode: aggregation`) + `kro-rbac.yaml` |
| ACK | `ec2-chart` 1.21.2, `iam-chart` 1.9.1, `eks-chart` 1.23.1. Images pinned by **index digest from the registry** (`c0a979b3…`, `becbd2a3…`, `fd04f0d8…`). `reconcile.resources` limited as in plan §5. CARM map as the lab (`role/ack-sqs-controller`, R-1) |
| Namespaces | all PSS `restricted` (controllers run under it) |
| Tier 1 | `network.yaml`: namespace `platform-network` (account 111…), VPC 10.10.0.0/16, 2 subnets (1a/1b), IGW, route table, SG; all `retain` |
| Tier 2 | `rgd.yaml` (`TeamEKSCluster`), claims `team-data/analytics` dev (111…) and prod (222…), `team-web/analytics` dev (111…) |

## 2. Gates (plan §6, P0)

| Gate | Result | Evidence |
|---|---|---|
| (1) resources synced, `ready=true` | **PASS with deviation.** Roles, node groups and network: `ACK.ResourceSynced=True`. The EKS **`Cluster` never reaches `ResourceSynced=True`**: ACK late-initializes `deletionProtection`, `controlPlaneScalingConfig.tier` and `resourcesVpcConfig.controlPlaneEgressMode`, and moto never returns them (eks-controller `generator.yaml` v1.23.1, lines 196–203). It requeues every 5 s (~25 `DescribeCluster`/min per cluster in moto's log). Readiness therefore comes from `status.status == "ACTIVE"` (F-4) | `spike.sh status`; `LateInitialized=False` |
| (2) no failing calls | **PASS.** 0 requests to unimplemented EKS paths (access entries, add-ons, versions, capabilities). Every non-2xx in moto's log falls inside delete/recreate windows (expected NotFound reads). Steady state: 0 reconciler errors | moto log grouped by minute; controller logs |
| (3) delete | **PASS.** Nonprod: ordered and clean in 36–39 s (node group + node role → cluster → cluster role → instance); nothing left in moto. Prod: K8s objects gone, **records retained** in 222…. Re-requesting prod **adopts** them (`adopt-or-create`), ready in 4 s. Only after the fixes in F-1…F-5 | §3 |
| (4) moto restart | **PASS with a recovery procedure** (`spike.sh recover`, 3 steps, F-6/F-7/F-8): network, dev and prod back **in the right accounts in 23 s**. Without the procedure, recovery is partial and wrong (IGW/SG never recreated; roles recreated in moto's default account 123456789012; prod objects stuck) | §3 |
| (5) cross-namespace `externalRef` | **PASS.** The team graph reads VPC, subnets and SG from `platform-network`. After the network was recreated with new IDs, kro re-rendered the cluster onto the new subnets | `status.subnetIDs`, moto `describe-cluster` |
| (6) memory | **PASS.** Working set: ec2 14 Mi, iam 12 Mi, eks 21 Mi, kro 34 Mi; CPU ≤ 5 m idle. moto with managed policies 287 MiB vs 276 MiB for the lab's moto. **35 new CRDs** (+2 shared) as predicted | kubelet stats summary; `docker stats` |
| (7) Kubernetes versions | **PASS (informative).** moto accepts **any** string (`1.29`…`1.34`, even `9.99`) and defaults to `1.19` when none is given. The VAP allowlist is the only guard, and `kubernetesVersion` must be required (no default) | `aws eks create-cluster --kubernetes-version …` |

## 3. Findings (all reproduced in the spike)

| # | Finding | Effect | Fix (verified) |
|---|---|---|---|
| **F-1** | **Cross-team takeover.** With AWS names `<name>-<env>` and `adopt-or-create`, a second team's claim `team-web/analytics-dev` **silently adopted team-data's cluster**. Deleting it **deleted team-data's node group, roles and cluster** | data loss across teams | AWS names **`<team>-<name>-<env>`** (CI keeps `team`+`name`+`env` unique) and adoption **only in prod** |
| **F-2** | An **empty** `adoption-policy` annotation is invalid: `ACK.Terminal "unrecognized adoption policy"` | all nonprod resources stuck | build the **whole annotations map** in CEL per environment (`'${env == "prod" ? {…} : {…}}'`); kro 0.9.4 accepts it |
| **F-3** | kro reported `ready=true` while ACK children were `ACK.Terminal` ("Resource already exists") | a broken claim looks healthy | `ready` also requires no `ACK.Terminal` on any child: `[clusterRole, nodeRole, cluster, nodegroup].all(r, !has(r.status.conditions) \|\| !r.status.conditions.exists(c, …))`. Seen `false` on a Terminal claim, `true` on healthy ones |
| **F-4** | Declaring `deletionProtection`/`controlPlaneScalingConfig`/`controlPlaneEgressMode` (to stop the late-init requeue) makes ACK call **`UpdateClusterConfig`**. **moto then drops the cluster's subnets and SGs** (`describe-cluster` → no `subnetIds`), and the update loop never ends. ACK's **pre-delete sync** compares `deletionProtection` and ignores `ignore-field-drift`, so **deletion hangs** | corrupted record, undeletable claim | **do not declare** those three fields (accept the late-init requeue in gate 1). The blueprint must never cause an EKS update in moto |
| **F-5** | Adopted or long-lived objects show drift on values that a fresh create would have filled. Cluster: `clientRequestToken`, `kubernetesNetworkConfig`, `logging`. Node group: `amiType`, `capacityType`, `diskSize`, `remoteAccess` (moto's fake `eksKeypair`). Platform subnets: 6 default attributes, updated at **every** 5-min resync | perpetual updates, F-4 risk | declare deterministic defaults (`kubernetesNetworkConfig`, `logging`, 5 subnet attributes); **`IgnoreFieldDrift` gate** on the EKS and EC2 controllers plus `services.k8s.aws/ignore-field-drift` for `spec.clientRequestToken`, the 4 node group fields and `spec.availabilityZoneID`. Result: 0 updates over a full resync (§6) |
| **F-6** | After a **moto restart**, ACK keeps cached STS credentials that moto no longer knows, and **moto silently answers as its default account `123456789012`**. Roles were recreated there, and the K8s objects showed `Synced=True` with `arn:aws:iam::123456789012:…` | **resources in the wrong account, looking healthy** | restart the ACK controllers after any moto restart (fresh credentials). *Likely affects the lab's ACK SQS too when moto restarts alone; not tested on the lab* |
| **F-7** | After a moto restart, ACK EC2 **recreates the VPC but not the IGW or SG** (`InvalidInternetGatewayID.NotFound`, `InvalidGroup.NotFound` are not treated as "gone"). Subnets, route table and clusters wait forever | platform network down | delete the network objects (`retain`, so no AWS call) and apply them again. In the lab, Argo CD self-heal re-creates them |
| **F-8** | An **adopted** object whose record vanished fails with `adopted resource not found` and is never recreated | prod clusters lost after a moto restart | remove the `services.k8s.aws/adopted` marker; `adopt-or-create` then recreates |
| **F-9** | The `Nodegroup` must reference `${cluster.spec.name}` (plan §2, D-5). With it, kro created the node group after the cluster and deleted it first | ordering | as planned, confirmed |

**Final steady state** (fresh `spike.sh up`, 3 claims, delete/retain/adopt, one moto restart + `recover`, then one full 300 s resync): see §6.

## 4. Proposed v0.3 amendments (need review before P1/P2)

1. **Naming (F-1):** AWS names and K8s objects `<team>-<name>-<env>`; CI uniqueness on the triple; the VAP checks `team` against the namespace.
2. **Adoption (F-1, F-2, F-8):** `adopt-or-create` + `adoption-fields` **in prod only**, through a CEL annotations map; runbook step for `adopted resource not found`.
3. **Blueprint rules (F-3, F-4, F-5):** the final `rgd.yaml` from the spike is the starting point for P2: stricter `ready`, never declare the three late-init fields, declare the deterministic defaults, `ignore-field-drift` lists. Add `readyWhen` on the children so kro's own `Ready` condition (used by Argo CD's `kro.run/*` health) also reflects Terminal. *Not yet verified; P2 gate.*
4. **Controller values:** add `featureGates: {IgnoreFieldDrift: true}` for EC2 and EKS. Memory: lower the plan's start values to **64Mi request / 256Mi limit** (measured ≤ 21 Mi), as for SQS.
5. **Platform network manifests:** declare the 5 subnet defaults plus `ignore-field-drift: spec.availabilityZoneID` (F-5).
6. **Operations (F-6, F-7, F-8):** a `make`/script step **"after moto restarts"**: restart the ACK controllers on both spokes (SQS included), re-create `platform-network` objects, clear `adopted` markers whose records are gone. Add it to `start-hub-spoke.sh` after moto starts, and to the P5 runbook and drill. Check the lab's SQS behaviour for F-6 in P1.
7. **Argo CD health (gate 1):** the lab's `services.k8s.aws/*` health is "Healthy only if `ResourceSynced=True`", so an EKS `Cluster` would show *Progressing* forever. In P4, add a specific health for `eks.services.k8s.aws/Cluster` (`status.status == ACTIVE` and not Terminal). Also check whether the existing key matches the `*.services.k8s.aws` groups at all.
8. **Versions (gate 7):** `kubernetesVersion` required; VAP allowlist (e.g. `1.32`, `1.33`, `1.34`) is the only check.

## 5. What was not done
- No lab change: moto flags (O-7), controllers, ApplicationSets, VAP and repo are P1–P4.
- VAP not written (P2). CI, Argo CD and Git flows not exercised (P3/P4).
- F-6 not tested against the lab's ACK SQS.
- kro's own `Ready` condition with Terminal children not checked (amendment 3).

## 6. Final steady-state check

Fresh `spike.sh up` with the final manifests, then 3 claims, delete team-web, delete and re-request prod (adopted), `docker restart moto-spike` + `spike.sh recover` (everything back in 23 s), then 330 s covering one full resync (18:15–18:21 UTC):

| Controller | Updates | Reconciler errors |
|---|---|---|
| ec2 | 0 | 0 |
| iam | 0 | 0 |
| eks | 0 | 0 |

- moto: 8 `DescribeCluster` per minute for 2 clusters (gate 1 late-init requeue). Earlier, with 3 clusters in mid-test, it was ~25 per minute per cluster.
- Memory: kro 25 Mi, eks 20 Mi, ec2 15 Mi, iam 13 Mi; moto-spike 341 MiB after the whole run.
- 37 `services.k8s.aws` CRDs on the cluster.

## 7. For the validator
1. `cd docs/roadmaps/tenant-iac-p0-spike && ./spike.sh up && ./spike.sh claims && ./spike.sh status`. Expect 3 claims `READY=true`, names `team-<team>-…`, ARNs in 111… (dev) and 222… (prod), EKS `Cluster` `SYNCED=False` with no Terminal (gate 1 deviation).
2. Delete `iac-team-web-dev/analytics-dev`: team-data's records in 111… must remain (F-1).
3. Delete then re-apply `instance-prod.yaml`: records stay in 222…; the claim is ready again with `services.k8s.aws/adopted=true`.
4. `docker restart moto-spike && ./spike.sh recover`, then `status`: everything back in 111…/222…, nothing named `team-*` in 123456789012.
5. Optional F-4 negative test: add `deletionProtection: false` to the cluster template and watch moto's `describe-cluster` lose `subnetIds`.
6. `./spike.sh down` removes everything.
