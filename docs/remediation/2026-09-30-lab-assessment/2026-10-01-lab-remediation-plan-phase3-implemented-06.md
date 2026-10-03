# Phase 3 Implementation Report — Run #06: B.7 pre-flight fixes (2026-10-01)

| | |
|---|---|
| **Plan** | [`2026-10-01-lab-remediation-plan-phase3.md`](2026-10-01-lab-remediation-plan-phase3.md) v1.0 (GREEN LIGHT) |
| **Preceded by** | [Implemented-05](2026-10-01-lab-remediation-plan-phase3-implemented-05.md), validated in [Validation-05](2026-10-01-lab-remediation-plan-phase3-validation-05.md) |
| **Scope executed** | Pre-flight hardening so that **B.7** (full rebuild acceptance) can succeed from Git alone. **B.7 itself has not been run** — it still needs explicit owner approval. |
| **Owner approval** | "I agree implement the pre-flight fixes" (2026-10-01) |

## 1. Gaps Found in the Rebuild Path, and Fixes

| ID | Gap (would have broken or silently degraded B.7) | Fix |
|---|---|---|
| G1 | Worker credentials (`orders-<env>-aws`) are created by hand-run `provision-worker-credentials.sh`; a rebuild leaves workers without valid keys | New `scripts/post-bootstrap.sh` (`make post-bootstrap`) provisions them per namespace owner account, keeping keys that still authenticate |
| G2 | Smoke test did not prove that orders are actually processed; a silent processing outage passed | New smoke stage **[9/9] End-to-End Order Flow**: per environment, sends a marker message into the namespace's account queue (as the `smoke-test` role) and waits up to 60 s for it on the dashboard |
| G7 | The `argo-cd` Application is manual-sync by design (D-32); after bootstrap it stays OutOfSync | `post-bootstrap.sh` step 4 syncs it once if not Synced |
| R2 | `argocd login` in setup can race the Traefik route | 30-attempt retry loop (5 s) |
| R3 | Bootstrap ordering (CRDs, CARM, namespaces) can exhaust an Application's sync retries | `post-bootstrap.sh` step 5 re-syncs non-Synced/Healthy Applications (skips running operations, 900 s timeout; no `--force`, per D-31) |
| R5 | Re-created `k3d-cloud-net` could get another subnet, breaking the worker NetworkPolicy egress to moto (172.21.0.0/16) | Network created with `--subnet 172.21.0.0/16`; setup aborts if an existing network has another subnet |

Also: `make start` now tells the operator to run `make post-bootstrap`; runbook Issue F added.

## 2. Finding Discovered While Testing (F-1)

The first run of the new stage 9 against the live lab **failed in all three environments**. Root cause: the host reboot earlier today restarted moto (in-memory state), which wiped the IAM users behind the worker keys. The keys then resolved to the empty default account, so workers polled nothing: every environment had **silently stopped processing orders** while every Application stayed Synced/Healthy and the previous 8-stage smoke test passed.

| | |
|---|---|
| Fix applied | `bash scripts/post-bootstrap.sh`: re-provisioned 3 keys, restarted workers (prod one pod at a time, PDB respected), exit 0 |
| Re-test | Smoke 9/9 passed (order seen after 3 s / 2 s / 2 s in dev / test / prod) |
| Idempotency | Second `post-bootstrap.sh` run: all keys "valid (kept)", no restarts, argo-cd already Synced, all Applications Synced/Healthy, exit 0 |
| Durable handling | Runbook Issue F; `make start` reminder. Not automated into `make start` (keeps start fast and non-interactive; owner can choose otherwise) |

## 3. Security Notes
* `post-bootstrap.sh` uses its own temporary Argo CD CLI config; the operator's session is not read or changed.
* Key material is read only into shell variables for the `sts get-caller-identity` check and unset immediately; nothing is printed.
* No new long-lived credentials; worker keys stay scoped to the namespace's CARM account.

## 4. B.7 Readiness

| Item | Status |
|---|---|
| Rebuild sequence | `make teardown` → `make setup` → `make bootstrap` → `make post-bootstrap` |
| Expected acceptance | 18/18 Applications Synced/Healthy, R-1 audit PASS, smoke 9/9 |
| Known residual risk | Argo CD sync-wave/ordering timing on a cold start (mitigated by step 5); GitHub/GHCR availability |
| Approval | **Pending owner** |
