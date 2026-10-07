# Tenant IaC: independent re-validation of orphan VPC pruning (validated-11)

> **Status: Accepted.** Validated by Codex on 2026-10-07 against fix `ec090ac` and [implemented-10](2026-10-04-tenant-iac-team-clusters-plan-implemented-10.md). This closes the two blockers and safety note in [validated-10](2026-10-04-tenant-iac-team-clusters-plan-validated-10.md).

## Independent evidence

| Case | Result |
| --- | --- |
| Clean live state | `prune-orphan-platform-vpcs.sh --dry-run` exited 0 and reported only `vpc-82e07b99ee1b6cb55` in account `111111111111` and `vpc-4085ac30c29edd10d` in account `222222222222`. Focused Bats Gate 6b passed. |
| Failed AWS discovery | An exported `aws` test function returned 77 only for `ec2 describe-vpcs`, passing other AWS calls through. Both accounts reported `describe-vpcs failed; nothing pruned`; the pruner exited **1** and printed no clean-account message. No Moto resource was changed. |
| Unsynced Kubernetes VPC object | An exported `kubectl` test function added one unsynced VPC object to the nonprod JSON response without changing Kubernetes. The pruner refused to judge nonprod and exited **1**. Code review confirmed the reference set is built from every VPC object's `status.vpcID` in `platform-network`. |
| Nonempty orphan | Created a temporary platform-tagged Moto VPC and subnet in account `111111111111`. Pruner dry-run exited **1** and kept it (`subnets=1`). `make post-bootstrap` exited **2** at the platform network check, before `[9/9] Smoke test`. The legacy `smoke-test-hub-spoke.sh` independently exited **1** at stage 6 because it saw two platform VPCs. |
| Empty orphan and cleanup | Deleted only the test subnet, then ran `make post-bootstrap`. It deleted the empty test VPC, exited **0**, and its full legacy smoke test passed. A subsequent dry-run and Bats Gate 6b again found exactly one referenced platform VPC per account. The test resources are gone; 42/42 Applications remained Synced and Healthy. |
| CI | GitHub Actions runs for `ec090ac` and report commit `f0a60b8` both completed successfully. |

## Finding closure

1. **Post-bootstrap enforcement:** Closed. The prune pipeline is checked under `pipefail`, and a nonzero status stops post-bootstrap. Legacy smoke stage 6 now checks the same VPC invariant as Bats Gate 6b.
2. **Failed discovery appearing clean:** Closed. `describe-vpcs` is now a checked command substitution. The injected failure produced a nonzero result and no clean message.
3. **Reference safety note:** Closed for the documented platform-network scope. The pruner checks every VPC CR in that namespace for `ACK.ResourceSynced=True` and an ID before considering candidates, and excludes all those IDs. The injected unsynced object was rejected. The script and runbook now state this scope precisely.

## Disposition and limit

The orphan platform VPC fix is **accepted**. This review exercised the failure and recovery paths using temporary Moto resources and read-only command injection. It did not repeat a host reboot; the owner's observed reboot supplied the original failure condition. [validated-10](2026-10-04-tenant-iac-team-clusters-plan-validated-10.md) remains the historical record of the rejected first implementation.
