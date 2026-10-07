# Lab Learning Remediation Plan — Independent Validation 05

> **Status: Accepted (2026-10-07).** Validator: Antigravity. Implementer: Claude. Scope: [implementation report 05](2026-10-06-lab-learning-remediation-plan-implemented-05.md), commits `57bf9c8` and `e56a270`. Closes findings **V4-1** and **V4-2** from [validation-04](2026-10-06-lab-learning-remediation-plan-validation-04.md).

## Verdict

Findings **V4-1** and **V4-2** are **closed**. All surviving obsolete smoke stage references across learner runbooks and `README.md` have been updated to reference the Bats smoke gates. The regression guard in `tests/test_doc_examples.sh` has been widened and proven via negative testing. In addition, the early token warning in Bats Gate 8 (`TOKEN_WARN_DAYS`) has been verified live.

---

## Independent Evidence

| Check | Target / Command | Result |
|---|---|---|
| **V4-1: Obsolete wording removal** | Repository regex search across `README.md`, `docs/*.md`, `docs/runbooks/*.md` | **0 occurrences found.** All instances updated to Bats Gates (`Gate 8`, `Gate 9`, `Gate 10a–10e`, `Gate 6b`, `Gate 12`). Historical incident descriptions are explicitly dated and contextualized. |
| **V4-2: Stale wording guard** | `tests/test_doc_examples.sh` check [4] | **Passed.** Regular expression enforces absence of `[N/12]`, `N-stage`, `smoke stage(s) N`, `(stage N`, and `stage N fails`. |
| **V4-2: Negative test** | Temporary injection of `smoke stage 10 fails` into `devops-student-rebuild-guide.md` | **Failed as expected.** Check [4] flagged `stale smoke reference: ...:smoke stage 10 fails` and exited with rc 1. Test injection cleanly discarded. |
| **Addendum: Default Gate 8** | `make test ARGS='-f "Gate 8"'` | **Passed.** Output displays `# credentials: shortest lifetime left 28d (warning below 7d)` on fd 3. Gate 8 passes. |
| **Addendum: Early token warning** | `TOKEN_WARN_DAYS=40 make test ARGS='-f "Gate 8"'` | **Passed with warnings.** Emits 8 `⚠ <credential>: 28d left ...; renew now: make rotate-spoke-tokens` warnings and summary on fd 3 while the test passes (`✓ Gate 8`). Matches Drill 2 runbook guidance. |
| **Addendum: Expired token failure** | `SMOKE_NOW_EPOCH=$(date -d "+60 days" +%s) make test ARGS='-f "Gate 8"'` | **Failed closed.** All credentials reported as `✘ <credential>: EXPIRED`; gate failed (`✗ Gate 8`, rc 1). |
| **Automated Gates** | `make test-docs` (live) | **Passed.** 36 doc blocks verified (14 run, 3 mutating, 4 covered, 15 skip, 0 unmarked). |
| **Control Plane CI** | `make ci` | **Passed.** 39 shell scripts ShellCheck-clean, 42 applications rendered offline, kubeconform valid, 22 alert rules valid, secret scan clean. |

---

## Finding Closure

1. **V4-1 (Obsolete smoke stage wording):** Closed. All runbooks and documentation now consistently reference Bats Gates.
2. **V4-2 (Regression guard coverage):** Closed. `tests/test_doc_examples.sh` now guards against all obsolete stage phrasing formats.
3. **Owner Addendum (Early token warning):** Verified. `TOKEN_WARN_DAYS` functions correctly in Bats Gate 8 without masking failures when tokens expire.

The learning remediation score remains **8.0 / 10** pending completion of the approved Learner On-Ramp tracks (Lab 0, Lab 1, and human pilot results).
