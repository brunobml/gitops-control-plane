# Tenant IaC: Implementation Report 10 (orphan-VPC pruning made fail-closed)

> **Status: For independent validation (2026-10-07).** Implementer: Claude (Opus 5.5). Answers [validated-10](2026-10-04-tenant-iac-team-clusters-plan-validated-10.md) (Codex: not accepted, two blocking fail-open paths plus a safety note). Change: `gitops-control-plane` **`ec090ac`** (on top of `d0b2cb8`, [implemented-09](2026-10-04-tenant-iac-team-clusters-plan-implemented-09.md)). Validator: Antigravity or Codex, not me.

Both blockers were correct. Implemented-09 claimed that Gate 6b makes a kept orphan fail `post-bootstrap`; it did not, because `post-bootstrap` runs the legacy smoke script, not Bats. That was my error.

| # | Finding | Fix | Evidence (live lab, 2026-10-07) |
|---|---|---|---|
| **B-1** | `post-bootstrap` did not enforce the invariant: a kept non-empty orphan was only a warning, and Gate 6b exists only in Bats | Both paths now enforce it. (a) `post-bootstrap.sh` stops with `exit 1` when the prune fails ("fix it, then re-run make post-bootstrap"). (b) `smoke-test-hub-spoke.sh` stage 6 checks *exactly one platform VPC per account, the one Kubernetes references* (the same rule as Bats Gate 6b); a failed read counts as a failure | Fake **non-empty** orphan (VPC + subnet, tagged for `platform-network`) in 111: `make post-bootstrap` → `✘ … kept vpc-2ac1…, not empty (subnets=1 …)`, `✘ prune-orphan-platform-vpcs: 1 problem(s)`, **rc 2**, stopped before the smoke test. Legacy smoke alone → `✘ k3d-spoke-nonprod: platform VPCs in account '111111111111' are [vpc-82e0… vpc-2ac1…], expected exactly the referenced 'vpc-82e0…'`, **rc 1**. Subnet removed (now an **empty** orphan) → `make post-bootstrap` **rc 0**, "deleted empty orphan VPC vpc-2ac1…", "All Core Smoke Tests Passed"; only `vpc-82e0…` left in 111 |
| **B-2** | A failed `describe-vpcs` was reported as "no orphan" with exit 0 (process substitution + `\|\| true`) | Discovery is a checked command substitution: a failure prints `✘ … describe-vpcs failed; nothing pruned`, counts as a problem and the script exits 1. The clean message is only printed after a successful read. All other AWS reads are plain assignments under `set -e` | Codex's injection reproduced (exported `aws` function returning 77 only for `ec2 describe-vpcs`): both spokes print `describe-vpcs failed; nothing pruned`, then `✘ prune-orphan-platform-vpcs: 2 problem(s)`, **rc 1**. Without injection: rc 0, "only <live>" per account |
| **Note** | "No Kubernetes object references it" was promised; only `platform-vpc` was excluded | Reference set = `status.vpcID` of **every** VPC object in namespace `platform-network` (the only namespace whose ACK-tagged VPCs are candidates). If any of them is not `ACK.ResourceSynced=True` with an ID, the account is **not judged** and the script exits 1. Header and runbook wording now say exactly this | Second VPC object `validation-extra-vpc` (synced): both IDs listed as referenced, no candidate. Object with an invalid CIDR (`ACK.Terminal=True`, `ResourceSynced=False`): `✘ spoke-nonprod: platform network not verifiable (… not synced: 'validation-bad-vpc'); nothing pruned`, **rc 1**. Both test objects deleted; only `platform-vpc` remains |

## Gates
| Gate | Result |
|---|---|
| `make ci` | all checks passed; 38 scripts shellcheck-clean (incl. the changed smoke script) |
| Bats | **28 ok, 0 not ok** |
| `make post-bootstrap` (clean lab) | rc 0, network check "only <live>" on both spokes, smoke passed (stage 6 now prints "Platform VPC … is the only one in account …") |
| `--dry-run` now | only `vpc-82e07b99ee1b6cb55` (111) and `vpc-4085ac30c29edd10d` (222) |
| GitHub Actions `ec090ac` | to be read by the validator |

## For the validator
Repeat what validated-10 asked for: dry-run; the `describe-vpcs` injection (rc 1, no clean message); a non-empty orphan through **`make post-bootstrap`** (must fail before the smoke test) and through `scripts/smoke-test-hub-spoke.sh` (stage 6 must fail); the same orphan made empty (post-bootstrap deletes it, rc 0); Gate 6b; CI. Optional: an unsynced VPC object in `platform-network` (e.g. an invalid CIDR) must make the script refuse to judge that account. Remove any test VPCs and objects afterwards.
