# Tenant IaC plan v0.3: P4 control plane implementation

> **Status: Implemented on 2026-10-05; ready for independent validation.** Executor: Codex. Plan: [approved v0.3](2026-10-04-tenant-iac-team-clusters-plan.md). P3 closed in [validated-06](2026-10-04-tenant-iac-team-clusters-plan-validated-06.md). This report records executor checks, not independent validation.

## Delivered

| Area | Change |
|---|---|
| Control plane | `gitops-control-plane` commit `768b665`: AppProject `tenant-iac`, generated `tenant-iac-team-data` ApplicationSet, dedicated `argocd-iac-deployer` ServiceAccount/RBAC on both spokes, team ApplicationSet drift and directory coverage checks, offline CI render mapping for `tenant-iac`, and post-bootstrap claim readiness/account checks. Orphan cleanup explicitly excludes `iac-*` and `platform-network` namespaces. |
| Health | Argo CD self-management sync applied exact Lua health checks for `TeamEKSCluster` and `eks.services.k8s.aws/Cluster`, with an ACK wildcard matching the real service groups. The existing `QueueBackedService` and RGD checks use exact keys. |
| Dev claim | `tenant-iac` [PR #3](https://github.com/brunobml/tenant-iac/pull/3), merge `960e2fe`: `team-data/analytics-dev` (1.33, t3.medium, 1/2/3). |
| Prod claim | `tenant-iac` [PR #4](https://github.com/brunobml/tenant-iac/pull/4), merge `935ac4c`: `team-data/analytics-prod` (1.32, m5.large, 1/3/5). |

## Evidence

- Control plane local `make ci`: 42 Applications rendered; 581 resources checked by kubeconform, 0 invalid/errors; 20 alert rules and all other stages passed. Remote [control plane run 37371699370](https://github.com/brunobml/gitops-control-plane/actions/runs/37371699370) passed on rerun. Its first attempt had no executed steps and was cancelled at the 15 minute limit.
- Local tenant IaC validation on each claim branch passed claims, 2/2 positive and 14/14 negative fixtures, ApplicationSet/chart render, kubeconform, and secret scan. Required `cluster-checks` passed on both PRs and on prod `main` ([run 37386971066](https://github.com/brunobml/tenant-iac/actions/runs/37386971066)).
- Hub: **42/42 Applications Synced and Healthy**. Both claims appear as Healthy in `argocd app resources --output tree=detailed`.
- `analytics-dev`: `TeamEKSCluster.status.ready=true`, EKS cluster/node group `ACTIVE`, ARN in account `111111111111`, VPC `vpc-315a36c15213f840b`, namespace annotation for that account and PSS restricted.
- `analytics-prod`: same statuses in account `222222222222`, VPC `vpc-ab499c849aae55e9b`, namespace annotation for that account and PSS restricted. Both roles, EKS Cluster, and Nodegroup carry `services.k8s.aws/deletion-policy: retain`.
- Argo CD's `resource-overrides health` evaluator returned `Healthy / EKS cluster active` for the live dev EKS Cluster with the deployed `argocd-cm`.
- `make post-bootstrap` checked both team claims and accounts, found no orphans, and passed all 12 smoke gates.

## Review notes

1. **Production review wording:** `CODEOWNERS` names `@brunobml`, the same account that authored PR #4. GitHub showed no review request or approval. The actual ruleset, verified in P3, enforces PR plus `cluster-checks` but zero approvals. PR #4 met the enforced gate; the plan's literal “with CODEOWNERS review” exit condition was not achieved. A separate reviewer and stronger branch rule would be needed to enforce it.
2. **Child visibility:** The Argo CD tree shows the Healthy `TeamEKSCluster` but not its kro generated ACK children. Unlike `QueueBackedService`, the `TeamEKSCluster` RGD does not set owner references on the children. The EKS Cluster health Lua works when evaluated directly, but its child is not linked in this Application's tree. Adding owner references would change teardown behavior and needs a separate drill before adoption.
3. The current P4 evidence does not include an independent validator run. P5 operations and the P1 moto restart robustness items R-a/R-b/R-c remain separate work.
