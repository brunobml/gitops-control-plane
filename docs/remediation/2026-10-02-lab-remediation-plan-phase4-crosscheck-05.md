# Phase 4 — Independent Cross-Check of Run #05 (Track D full rebuild) (2026-10-02)

| | |
|---|---|
| **Cross-checks** | [Implemented-05](2026-10-02-lab-remediation-plan-phase4-implemented-05.md) and [Validation-05](2026-10-02-lab-remediation-plan-phase4-validation-05.md) (published together in `09bfff4`) |
| **Why this document** | Run #05 was executed and validated on the reviewer/owner side. Under the remediation workflow the implementer does not validate their own run, so this is an independent check by an agent that did **not** perform the rebuild |
| **By / date** | Claude (Opus 5.5), author of the Phase 4 plan · 2026-10-02, ~15 min after the rebuild |
| **Changes made** | None to Git or cluster configuration. Live probes only: scripted logins/logouts (SSO users and local accounts), smoke test, impersonation audit |

## Verdict
**Concur: Track D passed.** The rebuilt lab matches Git and every Phase 4 behaviour — including the three SSO defects fixed during Track A (addenda 1–3 of implemented-02) and the O-1 account removal — survived a cold rebuild without manual changes.

## Evidence (independent)
| Area | Check | Result |
|---|---|---|
| Rebuild | container ages (hub/spokes 16–17 min, moto 13 min) | fresh estate |
| Argo CD | Applications | **22/22** Synced/Healthy |
| W14 | 6 ApplicationSets | all `goTemplate: true`; `orders-dev/test/prod` owned by `tenant-workloads` |
| W6 (B.4) | hub Helm releases | 0 |
| Tokens | `lab/token-expires` | 2026-11-01 (both spokes) |
| B.3 | `kyverno=enabled` cluster label | both spokes (from `register-spokes.sh`) |
| O-1 / P4-2 | local accounts / Dex | `platform-admin` only; no Dex Deployment. (`dexserver.log.*` params are chart defaults, owned by Argo CD — not Helm leftovers) |
| R-1 | `audit-impersonation.sh` | PASS |
| Smoke | 11 stages | pass; e2e orders dev 10 s, test 8 s, prod 0 s; unsigned image denied / running image admitted in all 3 tenant namespaces |
| W3 | Argo CD UI login through `argocd-server` (`/auth/login` → Keycloak → `/auth/callback`), both users × both hosts | 4/4 → `/applications`, correct groups |
| Addendum 2 | Argo CD logout → next login | Keycloak logout followed, **login form shown** (user switch works) |
| Addendum 3 | Headlamp after Keycloak logout (75 s) | **302** (must sign in again) |
| W4 / O-1 | local `platform-admin` / local `tenant-a` | token issued / "Invalid username or password" |
| W1 | Headlamp `Origin: https://evil.example` | 0 `Access-Control-*` headers |

## Process note
For future runs: the party that executes a step writes `implemented-NN`, and the other party writes `validation-NN`, so that no run is validated by the party that performed it.

## Residual risks carried out of Phase 4
| Ref | Risk | Status |
|---|---|---|
| D-10 | Kyverno deletes its webhooks on a graceful stop → tenant admission fails open until it returns (crash/unreachable fails closed) | accepted (lab); mitigation: >1 replica |
| D-16 | Deregistering a tenant app leaves namespace, worker credential and worker-created data | documented; candidate automation |
| §1.3 | Plain HTTP on loopback for UIs and the IdP | accepted residual (secure context on `*.localhost`) |
| 0.1 | Spoke tokens expire 2026-11-01 | rotate (`make rotate-spoke-tokens`) or rebuild by 2026-10-29 |
| L3-3 | No metrics/alerting stack | deferred |
