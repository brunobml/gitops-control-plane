# Tenant IaC: independent validation of implementation report 09 (validated-10)

> **Status: Not accepted; two blocking fail-open paths remain.** Reviewed by Codex on 2026-10-07 against implementation commit `d0b2cb8` and report [implemented-09](2026-10-04-tenant-iac-team-clusters-plan-implemented-09.md). The original assignment named Antigravity as validator; the owner requested this Codex validation directly.

## Verified behavior

- `bash scripts/prune-orphan-platform-vpcs.sh --dry-run` exited 0 and found only the live platform VPC in each account (`vpc-82e07b99ee1b6cb55` in `111111111111`, `vpc-4085ac30c29edd10d` in `222222222222`). It proposed no deletion.
- Focused Bats Gate 6b passed. The complete modular Bats suite passed **28/28**, including the new VPC count gate and end-to-end orders in dev, test and prod.
- `make test-docs` passed. GitHub CI for both `d0b2cb8` and the report commit `c8defe2` completed successfully. `bash -n` passed on the pruning script. Local `shellcheck` was unavailable; the reported `make ci` and remote CI cover that check.
- The script excludes the `platform-vpc` object's current `status.vpcID` and checks candidate VPCs for subnets, attached internet gateways, non-default security groups and non-main route tables before deletion. The live cluster has one `platform-vpc` CR per spoke.

## Blocking findings

1. **`post-bootstrap` does not enforce Gate 6b.** `scripts/post-bootstrap.sh` intentionally suppresses a nonzero exit from `prune-orphan-platform-vpcs.sh`, then calls `scripts/smoke-test-hub-spoke.sh`. Gate 6b exists only in `tests/smoke/03_carm_and_workload_pipeline.bats`, which post-bootstrap does not run. The legacy smoke script has no equivalent VPC count check. Therefore a kept, nonempty orphan can be reported as a warning while `make post-bootstrap` still exits 0. The implementation report's statement that Gate 6b makes this condition fail during post-bootstrap is incorrect. **Fix:** either propagate pruning failure, or add the VPC invariant to the legacy smoke path; keeping both checks is preferable.
2. **VPC discovery errors are misreported as a clean account.** Candidate discovery runs `aws ec2 describe-vpcs` inside process substitution, then ends the pipeline with `grep ... || true`. The parent `mapfile` sees an empty list if the AWS command fails. In a read-only controlled test, I exported an `aws` shell function that returned 77 only for `ec2 describe-vpcs` and passed other calls through to the real CLI. The script printed `simulated describe-vpcs failure` for each account, then `only <live>, no orphan platform VPC` twice and exited **0**. **Fix:** capture and check `describe-vpcs` status before splitting IDs; a failed AWS read must exit nonzero and must never produce the clean-account message.

## Additional safety note

The script's header and runbook say a candidate is deleted only if **no Kubernetes object references it**, but the implementation excludes only `platform-network/platform-vpc.status.vpcID`. It does not enumerate other VPC CRs or references. That is sufficient for today's one-VPC-per-spoke topology; before reusing this pruner with more platform VPC objects, check all Kubernetes VPC references and tighten candidate tags. Moto's `delete-vpc` dependency checks provide a last backstop, not a substitute for the promised reference check.

## Disposition

The current lab is clean, and the focused and full smoke tests pass. The new cleanup path is **not accepted** because its automatic recovery claim is not fail-closed. After the two blockers are fixed, repeat the dry-run, the `describe-vpcs` error injection, a nonempty-orphan case through **post-bootstrap**, Gate 6b, and CI. A host stop/start drill is not required for this review because the owner already supplied the reboot observation and repeating it would interrupt the running lab.
