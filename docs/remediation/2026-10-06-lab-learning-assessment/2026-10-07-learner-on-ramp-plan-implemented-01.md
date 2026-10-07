# Learner On-Ramp Plan: Implementation Report 01 (Phase 1, Track C: doc-test markers)

> **Status: For independent validation (2026-10-07).** Implementer: Claude (Opus 5.5). Validator: Codex or Antigravity, not me. Plan: [`2026-10-07-learner-on-ramp-plan.md`](2026-10-07-learner-on-ramp-plan.md) (approved by the owner; approval recorded in its header). Change: `gitops-control-plane` **`6a615c6`**; GitHub Actions green, including the new `doc-markers` stage.

## Verdict
Track C's acceptance criteria are met: **0 unmarked blocks**, every `skip` has a reason, a coverage report exists, and the negative tests fail as required. Marking the blocks and running them **found five learner-facing doc bugs**, all fixed.

## 1. What was built
| Item | Where |
|---|---|
| Marker syntax on the line above each ```` ```bash ```` fence: `<!-- doc-test: run \| mutating \| covered by="…" \| skip reason="…" … -->`; attributes `with="aws_as <account>"` (the tutorial's helper, extracted from the doc itself), `subst="<a>=x,…"` (placeholders), `expect="regex"` (catches commands that "succeed" without output), `cwd`, `timeout` | `tests/doc_tests.py` (stdlib only) |
| Static mode: every bash block in the six learner docs (README, student guide, developer tutorial, concepts page, tenant-IaC runbook, Argo CD CLI runbook) must carry a valid marker; `covered by=` must name a real dedicated check or Bats gate; `run`/`mutating` blocks may not contain unsubstituted `<placeholders>` | `doc_tests.py --markers-only` |
| Live mode: runs the `run` blocks in a clean `env -i` bash with `-e -o pipefail`; `--mutating` then runs the self-reverting blocks and a **settle phase** (polls until all Applications are `Synced/Healthy`, `orders-dev-dlq` is back in account 111 and no `doctest-learner` user is left, then the Bats suite). Read-only blocks run before mutating ones, so a deletion cannot break an observation block | `doc_tests.py`, `doc_tests.py --mutating` |
| `make test-docs` gains check [5] (live by default); `make test-docs MODE=live-mutating`; `--offline` = static only | `tests/test_doc_examples.sh`, `Makefile` |
| CI stage **`doc-markers`** (no lab needed): an unmarked or invalid block fails every push | `ci/check-control-plane.sh` |

## 2. Coverage (36 bash blocks, counted by the tool)
| Kind | Count | Blocks |
|---|---|---|
| **run** (executed every `make test-docs`) | 14 | `make test`/`make status`; secrets dir; port bindings; Applications status; Pod Security; impersonation audit; Drill 4 observation; tutorial pods (dev, prod), worker logs, Step 5 pods; tenant-IaC status, ACK objects, ACK logs (with `subst`) |
| **mutating** (executed with `MODE=live-mutating`) | 3 | Drill 4 DLQ delete; `make maintain`; temporary SSO user create/list/delete |
| **covered** | 4 | tutorial Step 4 → `check:tutorial-sqs`; tenant-IaC Step 3 → `check:tenant-iac-step3`; student guide `make test` → `bats:Gate 1`; break-glass login → `bats:Gate 10d` |
| **skip** (with reason) | 15 | rebuild and lifecycle (setup, bootstrap, post-bootstrap, teardown, stop/start, moto-restart), push to GitHub, Windows/mkcert, interactive SSO, browser port-forward, shared-repo Git change, cloning `tenant-iac` |

**Executed or covered: 21 of 36 (58%)**; the remaining 15 are skipped by design (disruptive, interactive or external), each with its reason in the doc.

## 3. Doc bugs found by running the blocks (all fixed)
| # | Where | Bug | Effect on a learner | Fix |
|---|---|---|---|---|
| D-1 | tenant-IaC runbook, alert investigation | `logs -l app.kubernetes.io/name=eks-controller` / `iam-controller`; the pods are labelled `eks-chart` / `iam-chart` | "No resources found", exit 0: troubleshooting shows **nothing** and looks fine | labels corrected; `expect="level"` now proves log lines arrive |
| D-2 | same section | the Argo CD application is called `team-<team>-<name>-<env>`; the real name is `<team>-<name>-<env>` (`team-data-analytics-dev`) | learner searches for an app that does not exist | name corrected, with an example |
| D-3 | same section | one block mixed nonprod and prod commands with the same `<env>` placeholder | filling in `dev` produced a prod command for a namespace that cannot exist (`NotFound`) | prod lines use `-prod` literally (the prod spoke only hosts prod claims) |
| D-4 | student guide, Applications status | `… \| grep -v "Synced *Healthy"  # expect no output` | exits 1 exactly when the lab is healthy | `… \|\| echo "all Applications Synced/Healthy"` |
| D-5 | student guide, Drill 4 observation | the ACK-log `grep` exits 1 until the queue was recreated | a learner repeating the block "every 20 s" sees an error | `\|\| echo "not recreated yet …"` |

## 4. Evidence
| Test | Result |
|---|---|
| `doc_tests.py --markers-only` | 36 blocks: run 14, mutating 3, covered 4, skip 15, **invalid or unmarked 0** |
| `make test-docs` (default) | all checks passed, 14/14 run blocks |
| `make test-docs MODE=live-mutating` | **rc 0 in 216 s**: 14 run + 3 mutating ✔; settle "lab repaired after 44 s (apps-not-green=0, dlq=…/111111111111/orders-dev-dlq, doctest-users=0)"; Bats all ok; no `doctest` password file left in `~/.config/gitops-lab` |
| Negative tests (temporary edits to `README.md`, restored from a backup) | 1. removed a marker → `bash block without a doc-test marker`, unmarked 1. 2. broken `run` block → `exit 2: make: *** No rule to make target 'no-such-target'`. 3. wrong `expect` → `output does not match expect=…`. 4. `skip` without reason → `skip needs reason="..."`. 5. `covered by="bats:Gate 99"` → `not a known check:<id> or bats:<gate>`. 6. unsubstituted `<target>` → `unsubstituted placeholders ['<target>']`. All fail; README restored |
| `make ci` | all checks passed (39 scripts shellcheck-clean, new stage `doc-markers` included) |
| GitHub Actions `6a615c6` | success; log shows `[doc-markers] … invalid or unmarked 0` |

## 5. For the validator
1. `python3 tests/doc_tests.py --markers-only`; then remove one marker or add an unmarked ```` ```bash ```` block to a learner doc and confirm `make ci` (stage `doc-markers`) fails; restore.
2. `make test-docs` (live) and, optionally, `make test-docs MODE=live-mutating` (about 4 min; the lab repairs itself).
3. Review the 15 `skip` reasons and the 4 `covered` references: is anything skipped that could reasonably run?
4. Spot-check D-1…D-5 in the docs.
