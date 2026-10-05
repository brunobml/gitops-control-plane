# Tenant IaC plan v0.3: P2 blueprint report (implemented-03)

> **Status: For independent validation (2026-10-05 UTC).** Executor: Claude (Opus 5.5). Validator: Antigravity. Plan: [`2026-10-04-tenant-iac-team-clusters-plan.md`](2026-10-04-tenant-iac-team-clusters-plan.md) v0.3, phase P2. P1 closed in [validated-03](2026-10-04-tenant-iac-team-clusters-plan-validated-03.md).
>
> | Repo | Change |
> |---|---|
> | `platform-catalog` | `a30da38` = tag **`v1.9.0`** (RGD + VAP) |
> | `gitops-control-plane` | `3cf231b` (chart CI + schema), `c425a22` (prod promoted to v1.9.0) |
> | `platform-charts` | PR #1 (chart) and PR #2 (Helm 3.14 fix), merged by the owner; **`team-cluster:1.0.0` released** (`sha256:b0cbb6a6…`), public |

## Verdict: P2 exit gate met on both spokes; chart released and public

| Exit gate (plan §6, P2) | Result |
|---|---|
| A scratch instance reaches `ready` | ✅ hand-written claim ready in **2 s**; the chart's own output ready in **5 s** (spoke-nonprod, account 111…, platform VPC) |
| The VAP denies each out-of-range case | ✅ **16/16** violations denied on create, plus prod size bound and update; the control is admitted |

## 1. What was delivered

| Item | Where | Notes |
|---|---|---|
| RGD `teamekscluster` (kind `TeamEKSCluster`) | `platform-catalog/blueprints/team-eks-cluster-rgd.yaml` | The P0 spike's final graph with every amendment from v0.3: AWS names `<team>-<name>-<env>`, a per-env CEL annotations map (prod: `retain` + `adopt-or-create`; nonprod: `delete`, no adoption annotation), the 3 late-init fields never declared, deterministic defaults + `ignore-field-drift`, `externalRef` to the tier-1 network, `Nodegroup.clusterName` as a reference. **New in P2 (amendment 3):** every child has a `readyWhen` that is false while ACK marks it Terminal, so kro's own `Ready` condition is correct. Schema has no markers; the contract is the VAP |
| VAP `teamekscluster-contract` + binding (Deny, Audit) | `platform-catalog/blueprints/team-eks-cluster-policy.yaml` | team/name: lowercase DNS label 2–20 chars (keeps `<team>-<name>-<env>-cluster` ≤ 54 < IAM's 64); env in dev/test/prod; **namespace must be `iac-<team>-<env>`** (the namespace decides the account); version in **1.32/1.33/1.34** (the only version check: moto accepts anything); `network == platform-default`; instance type in t3.medium/t3.large/m5.large; `1 ≤ min ≤ desired ≤ max`, max ≤ 3 (dev/test) or ≤ 5 (prod) |
| Chart `team-cluster` 1.0.0 | `platform-charts/charts/team-cluster` (PR #1) | Renders one `TeamEKSCluster` named `<name>-<env>` in the release namespace; `values.schema.json` checks shape only (allowed values stay in the VAP, so they can't drift apart); CI fixtures `ci/dev-values.yaml`, `ci/prod-values.yaml` |
| Chart lint with fixtures | `platform-charts` `Makefile`, `release.yaml` (PR #1) | Uses `charts/<chart>/ci/*-values.yaml` when present; `queue-backed-service` unchanged |
| **First-release fix** in the release guard | `platform-charts` `release.yaml` (PR #1) | Found while testing: GHCR answers **`403 denied`**, not `not found`, for a package name that does not exist. The guard only accepted `: not found`, so **the first release of any new chart would have failed closed**. Now the existence check runs anonymously: pull ok → content must be identical; `: not found` → new version; anonymous token 403 → first release; anything else → fail closed. Charts must be public anyway: Argo CD's `ghcr.io/brunobml/charts` repository has no credentials (checked) |
| Chart CI | `gitops-control-plane/ci/check-charts.sh` (`3cf231b`) | Per-chart fixtures, per-chart kubeconform directory, same first-release rule; shellcheck clean |
| CI schema | `ci/schemas/kro.run/teamekscluster_v1alpha1.json` (`3cf231b`) | Regenerated with `ci/update-crd-schemas.py` from the live CRD; every other schema came out byte-identical |
| Prod rollout | catalog tag `v1.9.0`, `clusters/blueprint-revisions.env` (`c425a22`), `make promote-blueprints` | `teamekscluster` Active on **both** spokes; `kro-blueprints-spoke-prod` Synced/Healthy at `a30da38` |

## 2. Evidence (live lab, 2026-10-05)

**Catalog CI** (`make ci-catalog`): CEL compiles for `teamekscluster-contract` and `teamekscluster`; "2 RGD schema(s) compatible with v1.8.0"; render + kubeconform pass. GitHub Actions: catalog `a30da38` success, control plane `3cf231b` and `c425a22` success, platform-charts PR #1 `chart-checks` pass.

**Scratch instance** (spoke-nonprod, namespace `iac-p2check-dev`, CARM 111…, PSS restricted):
```text
state=ACTIVE ready=true network=platform-default clusterName=p2check-probe-dev
arn=arn:aws:eks:us-east-1:111111111111:cluster/p2check-probe-dev
oidc=https://oidc.eks.us-east-1.amazonaws.com/id/Z0s5DQdvQk   vpc=vpc-315a36c15213f840b (platform-nonprod)
conditions: InstanceManaged=True GraphResolved=True ResourcesReady=True Ready=True      (ready after 2 s)
```

**Admission** (server-side dry-run on spoke-nonprod; one change from the valid claim each):

| Case | Result |
|---|---|
| valid (control) | admitted |
| team `P2check` / 21-char team / name `probe-` | denied: DNS label 2–20 |
| env `staging` | denied: one of dev, test, prod |
| env `prod` in `iac-p2check-dev` / team `otherteam` | denied: namespace does not match, expected `iac-p2check-prod` / `iac-otherteam-dev` |
| version `1.31` / `9.99` / missing | denied: one of 1.32, 1.33, 1.34 |
| network `my-vpc` | denied: must be platform-default |
| instance `c5.24xlarge` | denied: allowed types |
| minSize 0 / desired > max / min > desired / dev maxSize 4 | denied: sizes rule |
| nodeGroup missing | denied |
| prod maxSize 5 / 6 (on **both** spokes) | admitted / denied |
| **UPDATE** of the live claim to version 1.19 | denied (a valid update is admitted) |

**Terminal handling (amendment 3):** a role named `p2check-term-dev-cluster` was created in moto 111… beforehand, then a claim `term` was applied. The role went `ACK.Terminal "Resource already exists"`; the claim stayed `state=IN_PROGRESS`, `ready` unset, kro **`Ready=False`**; the EKS cluster was **not created** (its `readyWhen` dependency held). Deleting the claim removed its own node role and **left the pre-existing role untouched** (ACK never owned it). Test role removed afterwards.

**Chart → policy → blueprint:** `helm template … -f ci/dev-values.yaml` applied in a scratch `iac-team-data-dev`: admitted and ready in 5 s (`team-data-analytics-dev`, account 111…). `values.schema.json` rejects `env=staging` and a missing `kubernetesVersion` at template time.

**Teardown:** `probe-dev` deleted in 35 s; scratch namespaces removed; moto 111… has no `p2check-*` or `team-*` clusters or roles left.

## 2a. Release (after the merges)
- The first release run after PR #1 **failed closed** (nothing pushed). The workflow's Helm v3.14.0 reports an unknown package as `failed to fetch anonymous token … 403 Forbidden`; the guard matched only the newer wording `403: denied`. That was my mistake: I had tested with a newer Helm.
- Fixed in **PR #2**: both wordings are accepted, still only when GHCR's anonymous token endpoint answers 403. The decision logic was re-run with `alpine/helm:3.14.0`: existing version → compare, new version → push, unknown package → first release. The same fix went into the chart CI (`3317a3d`).
- Release run `12457b2`: `queue-backed-service` identical, skipped; `team-cluster` "First release of 1.0.0: pushing…", `Pushed: ghcr.io/brunobml/charts/team-cluster:1.0.0`, digest `sha256:b0cbb6a687cfe2092f50bcff1fb48ca7ec1a7a8ac38f05e00f5898073dd92e5c`.
- The owner made the package public. Anonymous token 200; an anonymous `helm pull … --version 1.0.0` gives the same digest. `make ci-charts`: "team-cluster:1.0.0 is released with identical content".

## 3. Open items
| # | Item | Owner |
|---|---|---|
| O-a | ~~Merge platform-charts PR #1~~ done (plus PR #2), `team-cluster:1.0.0` released | done |
| O-b | ~~Make the package public~~ done, anonymous pull verified | done |
| O-c | Argo CD custom health (validated-02 V-4) is still not applied lab-wide; needed for P4 (health of `TeamEKSCluster` and EKS `Cluster`) | P4 |

## 4. For the validator (Antigravity)
1. `kubectl --context k3d-spoke-{nonprod,prod} get rgd teamekscluster` → Active on both; `get validatingadmissionpolicy teamekscluster-contract`.
2. In a scratch namespace `iac-<team>-dev` with `services.k8s.aws/owner-account-id: "111111111111"` and PSS restricted, apply a valid claim: ready within seconds, ARN in 111…, `vpcID` = the platform-nonprod VPC. Delete it: nothing left in moto.
3. Repeat the admission table with server-side dry-run (any subset).
4. After the merge (O-a/O-b): release workflow green, `team-cluster:1.0.0` pullable anonymously, `make ci-charts` reports "released with identical content".
5. `make ci`, `make ci-catalog`, `make ci-charts` green; 40/40 apps Synced/Healthy.
