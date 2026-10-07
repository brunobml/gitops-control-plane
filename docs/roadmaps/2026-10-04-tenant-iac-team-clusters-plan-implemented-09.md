# Tenant IaC: Implementation Report 09 (orphan platform VPC after a host reboot, residual R-c)

> **Status: For independent validation (2026-10-07).** Implementer: Claude (Opus 5.5). **Validator: Antigravity** (owner's assignment). Change: `gitops-control-plane` **`d0b2cb8`**. Context: residual **R-c** from [validated-03](2026-10-04-tenant-iac-team-clusters-plan-validated-03.md) ("the `make start` path after a host reboot is untested").

## 1. Finding (observed after the owner's reboot, 2026-10-07)
After `make start` + `make post-bootstrap` the lab was healthy (42/42 Applications, network 6/6 synced per spoke, queues 4/2, default account empty, smoke green), but **each account held two platform VPCs**:

| Account | Referenced by Kubernetes | Orphan |
|---|---|---|
| 111111111111 | `vpc-82e07b99ee1b6cb55` (2 subnets, IGW, SG) | `vpc-cb99979241533191e`: same tags (`Name=platform-nonprod`, `services.k8s.aws/namespace=platform-network`), only the default SG and main route table, no subnets, no IGW |
| 222222222222 | `vpc-4085ac30c29edd10d` | `vpc-d9d2e9b280d1d2d02`: same, empty |

**Cause:** moto restarted empty at 23:37:26; the ACK pods restarted with the clusters. The EC2 controller **recreated the VPC** from its stale object (P0 F-7: VPCs are recreated, IGW/SG are not), producing the first VPC. The network repair (`start-hub-spoke.sh` / `post-bootstrap.sh`: delete the objects with `deletion-policy: retain`, then Argo CD re-creates them, here at 23:43:05) then created a second VPC. The first is never deleted (retain). `make moto-restart` does not have this problem, because it deletes the objects while ACK is scaled to 0. Harmless in moto (state is wiped at the next restart, no accumulation); a leak on real AWS.

## 2. Fix
| File | Change |
|---|---|
| `scripts/prune-orphan-platform-vpcs.sh` (new) | Per spoke: account from the `platform-network` namespace's CARM annotation; the live VPC ID from `platform-vpc` (must be `ACK.ResourceSynced=True`, otherwise the account is skipped). Candidates are VPCs tagged `services.k8s.aws/namespace=platform-network` other than the live one. A candidate is deleted **only if empty**: 0 subnets, no attached IGW, no non-default security group, no route table besides the main one. Anything else is **kept and reported**, and the script exits 1. `--dry-run` supported |
| `scripts/post-bootstrap.sh` | After step 8 (all Applications Synced/Healthy, so the network is re-synced), runs the prune; non-fatal there (warns), because Gate 6b makes a kept VPC visible |
| `tests/smoke/common.bash`, `03_carm_and_workload_pipeline.bats` | **Gate 6b**: each CARM account has exactly one platform VPC, and it is the one Kubernetes references (Bats: 27 → 28 tests) |
| `tenant-iac-operations.md` Runbook 5, `host-reboot-and-cluster-lifecycle.md` Step 2 | Why the orphan appears after a reboot, what the prune deletes and keeps, Gate 6b, `--dry-run` |

Considered and rejected: preventing the second VPC by racing the controllers at start (the ACK pods reconcile as soon as the spokes start, before any script can act); pausing everything on every `make start` (that is `make moto-restart`'s job, at a much higher cost).

## 3. Evidence (live lab, 2026-10-07)
| Test | Result |
|---|---|
| Guards on the **live** VPC (`vpc-82e0…`) | subnets=2, igws=1, non-default SGs=1, extra route tables=1 → would be kept |
| Guards on the orphan (`vpc-cb99…`) | all 0 → deletable |
| `--dry-run` | "would delete empty orphan VPC vpc-cb99…" (111) and "vpc-d9d2…" (222); live VPCs not listed |
| Real run | both orphans deleted; moto now holds exactly `vpc-82e0…` (111) and `vpc-4085…` (222); network still **6/6 synced** on both spokes |
| Second run (idempotence) | "only <live>, no orphan platform VPC" on both; rc 0 |
| Negative 1: fake empty orphan (tagged VPC created in 111) | Gate 6b **not ok** → prune deletes only the fake → Gate 6b ok |
| Negative 2: fake orphan **with a subnet** | prune **keeps** it ("not empty (subnets=1 …); investigate"), rc **1**; fake removed by hand afterwards; Gate 6b ok |
| `make post-bootstrap` (full) | rc 0; the new step printed "only <live>, no orphan platform VPC" for both spokes; smoke "All Core Smoke Tests Passed" |
| `make ci` | all checks passed, **38** scripts shellcheck-clean |
| Bats | **28 ok, 0 not ok** |
| `make test-docs` | all checks passed |

## 4. For the validator (Antigravity)
1. Read `scripts/prune-orphan-platform-vpcs.sh`: the deletion conditions in its header, and that the live VPC can never be a candidate.
2. `bash scripts/prune-orphan-platform-vpcs.sh --dry-run` → no orphan (current state).
3. Reproduce: with account-111 credentials (STS AssumeRole via moto), create an empty VPC tagged `services.k8s.aws/namespace=platform-network`; `bats tests/smoke/03_carm_and_workload_pipeline.bats -f "Gate 6b"` → not ok; `make post-bootstrap` (or the script) → deleted; Gate 6b → ok. Repeat with a subnet in the fake VPC → kept, rc 1; remove it yourself.
4. Optional, closest to the real case: `make stop`, `make start`, `make post-bootstrap` (an owner-approved window); then Gate 6b and the prune output.
5. Gates: `make ci`, Bats 28/28, GitHub Actions on `d0b2cb8`.
