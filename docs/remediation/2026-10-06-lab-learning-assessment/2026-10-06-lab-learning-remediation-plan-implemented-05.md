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

## Addendum: early token warning restored (owner request, 2026-10-07)
Bats Gate 8 honours `TOKEN_WARN_DAYS` again (default 7), as the 12-stage script did: an **expired** credential fails the gate; fewer than `TOKEN_WARN_DAYS` days left prints `# ⚠ <credential>: Nd left (<date>); renew now: make rotate-spoke-tokens (make maintain renews below 7 days)` per credential plus a summary, and the gate **passes**; otherwise one line `# credentials: shortest lifetime left Nd`. Output goes to Bats fd 3, so it shows in `make test`. Verified: default → summary "28d", `ok`; `TOKEN_WARN_DAYS=40` → 8 warnings + summary, `ok` (also through `make test`: `ok 14 Gate 8`); `SMOKE_NOW_EPOCH` = now + 60 days → every credential `EXPIRED`, **`not ok`**, rc 1. Drill 2's text describes this again and its `TOKEN_WARN_DAYS=40 make test` tip works; the `TOKEN_WARN_DAYS=` pattern is removed from the stale-wording guard.

## Gates
`make test-docs` (live) all passed; `make ci` all passed (doc-markers: 36 blocks, 0 unmarked). Owner decisions O-1…O-6 for the learner on-ramp plan are recorded in its header.

Change: `gitops-control-plane` (this commit; it also pushes the owner's local commit `efaa8bb` with validation-01 of the on-ramp plan and validation-04).
