# Lab Learning Remediation: Implementation Report 05 (validation-04 V4-1, V4-2)

> **Status: For focused re-validation (2026-10-07).** Implementer: Claude (Opus 5.5). Answers [validation-04](2026-10-06-lab-learning-remediation-plan-validation-04.md) (Codex: changes requested). Validator: Codex or Antigravity, not me.

## V4-1: obsolete smoke stage wording (all instances, not only the three listed)
A repository-wide search (`\[[0-9]+/12\]`, `[0-9]+-stage`, `stage [0-9]+`, `smoke stage`, `TOKEN_WARN_DAYS=`) over README, `docs/*.md` and `docs/runbooks/*.md` found **six** instances. Codex listed four of them (three runbooks); `README.md` had a fifth. The sixth was a wording problem *and* a broken instruction:

| File | Before | After |
|---|---|---|
| `operational-drills-and-failure-injection.md` (Drill 2) | "Stage `[8/12]` reads the `exp` claim … To see that warning, run `TOKEN_WARN_DAYS=40 make test`." | **Bats Gate 8** reads the `exp` claim and fails only once a token **has expired**. Since the Bats consolidation there is no early warning: `TOKEN_WARN_DAYS` is still exported by `tests/smoke/common.bash`, but **no gate reads it**, so the documented tip did nothing. The early warning is the `SpokeTokenExpiringSoon` alert |
| `host-reboot-and-cluster-lifecycle.md` command table | "Executes the 8-stage comprehensive test suite" | runs the Bats smoke suite; success = every line `ok`, none `not ok` |
| `host-reboot-and-cluster-lifecycle.md` Issue F (dated 2026-10-01) | "caught by smoke stage 9, now Bats Gate 9" | kept as a historical observation, worded without the old stage number: "caught by the smoke test's end-to-end order check, today *Bats Gate 9*" |
| `host-reboot-and-cluster-lifecycle.md` Issue G | "smoke stage 10 fails" | "the SSO gates fail (*Gate 10a*–*10e*: issuer, Argo CD SSO, login forms, break-glass, Headlamp)" |
| `tenant-iac-operations.md` Runbook 5 (my own text) | "The smoke test (stage 6, and Bats Gate 6b)" | "The Bats smoke suite (*Gate 6b*, run by `make test` and at the end of `post-bootstrap`)" |
| `README.md` (missing Keycloak symptoms) | "smoke stages 9 and 12 fail" | "the Bats smoke suite fails, at least *Gate 9* and the *Gate 12* observability checks" |

## V4-2: the guard missed these forms
`tests/test_doc_examples.sh` check [4] now also rejects `[N/12]`, `N-stage comprehensive/smoke/test`, `smoke stage(s) N`, `(stage N`, `stage N fails` and `TOKEN_WARN_DAYS=`. **Negative test:** each of the five phrases (`[8/12]`, `8-stage comprehensive test suite`, `smoke stage 10 fails`, `(stage 6, and Bats Gate 6b)`, `TOKEN_WARN_DAYS=40 make test`) appended to a runbook makes the check fail (`caught=1` each); runbook restored.

## Observation (not changed here)
Bats Gate 8 no longer gives the early token warning the old script had (`TOKEN_WARN_DAYS`, default 7 days). `SpokeTokenExpiringSoon` covers it in monitoring, so nothing is unobserved; but if a pre-expiry failure or warning in `make test` is wanted, Gate 8 needs to use `TOKEN_WARN_DAYS` again. Owner's call; it is a test change, not a doc change.

## Gates
`make test-docs` (live) all passed; `make ci` all passed (doc-markers: 36 blocks, 0 unmarked). Owner decisions O-1…O-6 for the learner on-ramp plan are recorded in its header.

Change: `gitops-control-plane` (this commit; it also pushes the owner's local commit `efaa8bb` with validation-01 of the on-ramp plan and validation-04).
