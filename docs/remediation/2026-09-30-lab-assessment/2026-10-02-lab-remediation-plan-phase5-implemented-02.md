# Phase 5 Implementation Report — Run #02: Track B (alerts for known failure modes) (2026-10-02)

> **Status: Historical.** Record of the 2026-09-30 assessment and its remediation (Phases 1–5, closed 2026-10-03). Kept as evidence and not updated. For the lab as it is today, see the [README](../../../README.md) and the [2026-10-03 assessment](../../assessments/2026-10-03-lab-assessment.md).

| | |
|---|---|
| **Plan** | Phase 5 v1.0 (GREEN LIGHT; remark **R-3** governs B.2) |
| **Executed by** | Claude (Opus 5.5). **To be validated by** Antigravity |
| **Commits** | `gitops-control-plane`: `d5e0e9f` (B.1 exporter, rules), `6c0471b` (B.2 probe, probe alerts), `e84f1b7` (smoke stage 12 fix, promtool tests, register-spokes fix), `554aa2c` (test clean-up). `platform-catalog`: `1d64393` |

## 1. Outcome

| Step | Result |
|---|:-:|
| **B.1** credential-expiry exporter — **no Secret access** (see D-8) | ✅ |
| **B.2** synthetic order probe on each spoke (R-3 isolation) | ✅ |
| **Rules** 12 alerts as code, `promtool check rules` OK, **8 promtool unit tests** (`make test-alert-rules`) | ✅ |
| **Every live-testable alert fired** by causing its failure, and resolved after the fix | ✅ (§2) |

## 2. Alert fire tests (X5–X10)

| # | Alert | Failure caused | Fired | Resolved by |
|---|---|---|---|---|
| X10 | `ProbeFailed[moto]` | `docker stop moto-cloud` 07:12:42 (6 min) | 07:18:26 | moto restart |
| X6 | `ArgoClusterUnreachable[spoke-nonprod]` | invalid bearer token in `cluster-spoke-nonprod` | 07:18:47 | token renewal in `post-bootstrap` |
| X7 | `SpokeTokenExpiringSoon[argocd-spoke-nonprod]` | recorded expiry set to now + 2 days | firing by 07:23 | renewal (expiry back to 29 days) |
| X9 | `OrdersNotProcessed` (dev, test, prod) | moto restart wiped worker keys — **the real F-1 failure** (key resolved to default account 123456789012) | 07:25–07:27 | `make post-bootstrap` (keys re-provisioned, workers restarted) |
| X5 | `ArgoAppOutOfSync[alert-test]` | Application with a non-existent path | 07:43:27 (30 min) | app deleted |
| X5b | `ArgoAppDegraded[alert-test-degraded]` | Application with a failing Pod | 07:55:33 (10 min) | app deleted |
| X8 | `KyvernoDown[spoke-nonprod]` | both Kyverno replicas scaled to 0 (hub Argo CD controller paused) | pending 07:56:50, firing 07:59:01 | replicas restored; cleared |

Unit-tested only (promtool, deterministic): `SpokeControllerDown`, `SpokeAgentDown`, `CredentialExpiryUnknown`, `SyntheticProbeStale`, `KyvernoSlowAdmission`, plus `KyvernoDown`, `SpokeTokenExpiringSoon`, `OrdersNotProcessed`, `ArgoAppOutOfSync` (excludes the manual-sync `argo-cd` app).

**Single-command recovery:** after X6/X7/X9/X10, one `make post-bootstrap` renewed the tokens, re-provisioned all three worker keys, restarted the workers (prod one pod at a time), re-synced, and the smoke test passed 12/12 with no firing alerts.

## 3. Design notes

| ID | Item |
|---|---|
| D-8 | **B.1 without Secret access** (plan: read-only Role on cluster Secrets). The token scripts (`register-spokes.sh`, Headlamp `setup-credentials.sh`) now record each token's JWT `exp` — only the timestamp, token passed on stdin — in ConfigMap `monitoring/credential-expiry` (`scripts/record-credential-expiry.sh`). The exporter mounts that ConfigMap, has **no ServiceAccount token**, read-only root FS, NetworkPolicy: ingress from Prometheus only, no egress |
| D-9 | **B.2 probe**: stdlib Python incl. SigV4 (nothing installed at runtime), digest-pinned base image, PSS `restricted` namespace `platform-probes`, RBAC `list` namespaces + `queuebackedservices` only, egress DNS / spoke Traefik / 172.21.0.0/16 ports 5000 + 6443 (R-3). Discovers tenant namespaces itself (self-registered apps are probed automatically). Uses role name `synthetic-probe`; moto does not enforce IAM (as with smoke stage 9) |
| D-10 | **`MotoRestarted` not implemented as planned**: a moto restart has no observable metric. Covered by `ProbeFailed[moto]` (down) and `OrdersNotProcessed` (its consequence, X9). Added instead: `CredentialExpiryUnknown`, `SpokeAgentDown`, `SyntheticProbeStale` (12 rules total) |
| D-11 | **Promtool lesson**: a target leaving discovery gets **staleness markers** (also through remote write); the first `KyvernoDown` unit test used `_` and did not fire. Modelled with `stale`; the live X8 confirmed real behaviour |
| D-12 | **Test-design gap (author)**: an Application with no resources is *Healthy*, so the first X5 only proved `ArgoAppOutOfSync`; `ArgoAppDegraded` was proven with a failing Pod (X5b) |
| D-13 | **Smoke stage 12 redesigned** after the recovery run: right after recovery, alerts and the 5-minute probe metric are still in their last state. Stage 12 now fails on alerts firing **> 20 min**, reports younger ones and a stale probe result as warnings (stage 9 proves e2e directly) |
| D-14 | **Defect found and fixed — automatic renewal of an already-broken token aborted**: `register-spokes.sh` stopped at the first `Failed` connection state, which is Argo CD's cached state from the old token; it turns `Successful` seconds later. It now keeps polling (up to 60 s) and only aborts if still failing. Re-tested by re-breaking the token: renewal succeeded |
| D-15 | Environmental: one `post-bootstrap` run was killed by a SIGHUP to the host `aws` CLI (native stack trace, `Signal received: 1`); not a lab defect. Re-run in the background succeeded |
