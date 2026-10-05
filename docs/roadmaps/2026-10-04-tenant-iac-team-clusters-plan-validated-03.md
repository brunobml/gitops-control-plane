# Tenant IaC plan v0.3: P1 re-validation of V-1, V-2, V-3 (validated-03)

> **Status: Independent re-validation (2026-10-05 UTC).** Validator: Claude (Opus 5.5). Executor: Antigravity. Under review: `eedd312` (fixes) and the updated [implemented-02](2026-10-04-tenant-iac-team-clusters-plan-implemented-02.md) (`8260184`). Previous verdict: [validated-02](2026-10-04-tenant-iac-team-clusters-plan-validated-02.md) 🟡. As the owner asked, I ran `make moto-restart` on the live lab. The only other change was a temporary local edit for the negative CI test (restored).

## Verdict: 🟢 GREEN: P1 closed

V-1, V-2 and V-3 are closed. Two robustness gaps in `moto-restart.sh` remain (R-a, R-b). They don't block P1, but should be fixed before the procedure is relied on unattended.

| # | Item | Result | Evidence |
|---|---|---|---|
| **V-1** | moto restart procedure | ✅ **Closed** | `make moto-restart` on the live lab at 09:24:53 UTC: **exit 0 in 265 s**, all 10 steps, `post-bootstrap` + smoke test ("All Core Smoke Tests Passed", 0 failures). Then checked by me, not by the script: the network was **recreated with new IDs** (nonprod `vpc-61c7…`→`vpc-315a…`, prod `vpc-ef6b…`→`vpc-ab49…`), **exactly one** non-default VPC, IGW and `platform-cluster-sg` per account, and the IDs in each spoke's status equal moto's. Queues: 4 in 111…, 2 in 222…. Default account 123456789012: 0 VPCs, 0 IGWs, 0 queues, 0 users, 0 roles. Hub app controller back to 1 replica; **40/40** apps Synced/Healthy. One resync later (330 s, both spokes): ec2/iam/eks/sqs **0 updates, 0 errors** |
| **V-2** | catalog CI covers `network/` | ✅ **Closed** | Negative test (`cidrBlocks: 42` in `network/nonprod/network.yaml`, local only): `make ci-catalog` → `VPC platform-vpc is invalid … /spec/cidrBlocks`, "✘ 1 check(s) failed". File restored → 24 Applications, 22 rendered incl. `platform-network-spoke-{nonprod,prod}` (6 objects each), "all checks passed" |
| **V-3** | alert tests for the new controllers | ✅ **Closed** | 4 new cases (ack-ec2 / ack-iam / ack-eks down fire; all up silent); `make test-alert-rules` → SUCCESS |

## Remaining gaps (not blocking)

| # | Gap | Effect | Suggested fix |
|---|---|---|---|
| R-a | `moto-restart.sh` has `set -e` but **no trap**. If anything fails between step 1 and step 7 (e.g. moto not answering within 30 s, an ACK rollout timeout), the script exits with the **hub application controller and all ACK controllers at 0 replicas**. GitOps then stops silently until someone scales them back | lab frozen after a failed run | `trap` on EXIT that restores ACK to 1 on both spokes and the application controller to 1 unless the run finished |
| R-b | The default-account assertion (step 9) ends every `aws` call with `\|\| true`. If moto doesn't answer, the empty output reads as "completely empty" | false PASS | Fail on a non-zero `aws` exit instead of suppressing it |
| R-c | Not tested: the **`make start` path** (host reboot). `start-hub-spoke.sh` deletes the network objects right after the clusters start, possibly before the ACK controllers run, and `post-bootstrap` has a repair fallback. Plausible, but unproven | first reboot is the test | Next host reboot: run `make start` + `make post-bootstrap` and check the network as above |

## Next
P1 is closed. **P2 (executor Claude, validator Antigravity) starts now.**
