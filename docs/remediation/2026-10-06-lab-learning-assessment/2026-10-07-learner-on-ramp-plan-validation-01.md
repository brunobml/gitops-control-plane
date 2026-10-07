# Learner On-Ramp Plan — Independent Validation 01 (Phase 1, Track C)

> **Status: Accepted (2026-10-07).** Validator: Codex. Implementer: Claude. Scope: [plan](2026-10-07-learner-on-ramp-plan.md) Phase 1 and [implementation report 01](2026-10-07-learner-on-ramp-plan-implemented-01.md), change `6a615c6`.

## Verdict

Track C meets its Phase 1 exit gate for the six existing learner documents: **36 bash blocks, 0 unmarked**, with a reason on each of the 15 skipped blocks. The four `covered` references resolve to existing checks or Bats gates. Lab 0 and Lab 1 do not exist yet; their blocks must be added to the inventory when those documents are written.

## Independent checks

| Check | Result |
|---|---|
| `python3 tests/doc_tests.py --markers-only` | Exit 0: run 14, mutating 3, covered 4, skip 15, invalid or unmarked 0. |
| `make test-docs` | Exit 0: all 14 live `run` blocks passed, along with claim, tutorial values, SQS, and stale-baseline checks. |
| `make test-docs MODE=live-mutating` | Exit 0: 14 `run` and 3 `mutating` blocks passed; the lab settled after 240 seconds with 0 unhealthy Applications, the dev DLQ restored in account `111111111111`, and 0 temporary `doctest-learner` users. The full Bats suite passed in the settle phase. |
| Negative tests in an isolated temporary document | An unmarked bash block, a `run` block containing `false`, and a `skip` block without `reason` each failed as intended. No repository document was altered for these tests. |
| CI wiring | `ci/check-control-plane.sh` calls `doc_tests.py --markers-only` in its `doc-markers` stage, so an unmarked block fails that stage. |

The live mutating check temporarily deleted the dev DLQ; ACK restored it within the test's wait window. I did not repeat the implementation's GitHub Actions check.

## Phase 2 decisions

I endorse the plan's recommendations for O-1 through O-5: use `tenant-a-user` for the Lab 0 Argo CD tour; keep the required Lab 0 path Git-free, with a clearly optional Git exercise and revert; make Lab 1 kro-only by default with moto and ACK as a stretch; pilot with the owner and one or two people new to the lab, excluding agents from the learner count; and run `make test-lab1` locally for now. These are implementation choices for Phase 2 onward, not evidence of completed learner outcomes.
