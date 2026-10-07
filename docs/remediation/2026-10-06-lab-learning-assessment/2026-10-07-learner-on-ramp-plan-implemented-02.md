# Learner On-Ramp Plan: Implementation Report 02 (Phase 2, Track A: Lab 0 guided tour)

> **Status: For independent validation (2026-10-07).** Implementer: Claude (Opus 5.5). Validator: Codex or Antigravity, not me. Plan: [`2026-10-07-learner-on-ramp-plan.md`](2026-10-07-learner-on-ramp-plan.md) §3 (Track A), guardrails G-1 to G-4; owner decisions O-1 (Lab 0 as `tenant-a-user`, required tour Git-free, optional Git step at the end) and O-5 (order C → A → B → D). Change: `gitops-control-plane`, this commit.

## Verdict
Lab 0 exists, is linked as **Start here** from the README and the student guide, and every copyable block is marked and tested. The run and covered blocks pass, and the mutating blocks pass in `MODE=live-mutating`. In the run that recorded the before/after snapshot, the lab was **identical** before and after. **One acceptance item is open for the validator:** the plan asks for each station to be run live by the implementer *and* the validator. I ran every station through the CLI. The two interactive **SSO logins as `tenant-a-user`** (browser and `argocd login --sso`) and the four tenant-session CLI lines in station 1 were **not** run by me, because doing so would require me to handle the tenant's password. Their expected outputs come from the live RBAC policy, which is evaluated by a tested block. The validator, or the owner, should run station 0's login and station 1's skipped block as `tenant-a-user`, and record the output.

## 1. What was built
| Item | Where |
|---|---|
| `docs/lab-0-guided-tour.md`: stations 0–8 as planned, plus the optional Git step. Each station has a question, a prediction prompt, exact commands, a **dated measured** observation, a folded *Explain*, and "how it goes back"; there is also a flow diagram | new |
| **Start here** links: README intro, README "Learning the concepts" paragraph and repository tree; student guide header | `README.md`, `docs/runbooks/devops-student-rebuild-guide.md` |
| Runner: Lab 0 added to `DOCS`; new prelude `with="argocd-session"` (break-glass `platform-admin` login into a **temporary** `--config` via `ARGOCD_OPTS`, deleted on exit; the owner's `~/.config/argocd/config` is not touched, verified by its mtime); unknown `with=` values are rejected; **a copy of `aws_as()` in any learner doc must match the developer tutorial's** (drift guard); in `--mutating` mode **every mutating block starts from a repaired lab** (settle before each block); the settle check also requires `orders-dev-worker` replicas = 1 and `configmap/orders-dev-config` to be present (Lab 0 station 5) | `tests/doc_tests.py` |
| Registry: on-ramp report 01 marked accepted, validation-04 linked, this report added | remediation `README.md` |

## 2. Design decisions the validator should judge
| Decision | Why | Alternative rejected |
|---|---|---|
| Station 1 tests RBAC with `argocd admin settings rbac can role:tenant-a … --policy-file <live argocd-rbac-cm>` | It checks the **live** policy non-interactively and is useful for a learner too ("ask the policy itself") | Enabling Keycloak direct-access grants (password grant) for a scripted tenant login: this weakens the realm (`directAccessGrantsEnabled: false` on all clients), so I did not do it |
| Station 7's `argocd app get --output tree` is tested with a break-glass session | The command and its output shape do not depend on the identity; tenant-a may `get` `orders-dev` | Skipping it: G-3 wants copyable blocks executed where possible |
| The learner's tenant CLI session goes to `$HOME/.config/argocd/lab0.config` (`ARGOCD_OPTS`) | It does not overwrite an admin session (the lab's D-16 rule) | The default config |
| Lab 0 repeats Drill 4 (station 6) instead of linking to it | The tour must contrast watch with resync in one sitting. The delete is guarded (`get-queue-url && delete-queue`, plan §9 risk 1) | Linking only |
| Settle before **each** mutating block | Lab 0 station 6 and Drill 4 delete the same queue. The first live run failed because Drill 4's delete found the queue already gone (`NonExistentQueue`), a test-design collision, not a doc bug. A learner would start from a healthy lab (station 0) | Ordering tricks; deduplicating the Drill 4 block |

## 3. Measured observations (2026-10-07, recorded in the doc)
| Station | Observation |
|---|---|
| 1 | Hub: 42 Applications (`platform-addons` 20, `control-plane` 13, `platform-catalog` 4, `tenant-workloads` 3, `tenant-iac` 2); `policy.default` is empty, so the tenant sees 3. Policy: `orders-dev`/`orders-test` sync **Yes**, `orders-prod` **No**, `addon-kro` get **No** |
| 2 | Sources `queue-backed-service @ 1.0.0` + `orders-processor.git @ main` (`ref: values`); revisions `["1.0.0","6924cfd…"]`, matching `git ls-remote … refs/heads/main` |
| 3 | `QueueBackedService/orders` `ACTIVE`/`True`; **9** children by label `kro.run/instance-name=orders`; owner `QueueBackedService/orders controller=true`; both queues account `111111111111` = namespace annotation |
| 4 | Plain mock keys = account `123456789012`, **0** queues; 111…: 4 queues; 222…: 2 queues |
| 5 | 18:51:28 UTC: scale to 3 → `replicas` 1 at the first 0.5 s poll; ConfigMap recreated in the same second; Argo CD `Synced/Healthy`; one extra pod briefly `Progressing` in the tree, gone 20 s later |
| 6 | DLQ recreated by ACK after **113 s** (Lab 0) and **290 s** (Drill 4, right after) in the second mutating run, both within the 300 s resync |
| 7 | Tree: QBS + 9 children with health from the Lua checks; `status.resources`: only `QueueBackedService/orders status=Synced`, health **empty** |

## 4. Coverage
The runner counts **53 bash blocks in 7 learner documents**: run 25, mutating 6, covered 5, skip 17, invalid or unmarked 0. Lab 0 has 17 blocks:

| Kind | Count | Blocks |
|---|---|---|
| run | 11 | stations 1 (policy), 2 (×2), 3 (×2), 4 (×2), 6 (observe), 7 (×2, one with `argocd-session`), optional Git |
| mutating | 3 | station 5 (scale, ConfigMap delete), station 6 (guarded DLQ delete) |
| covered | 1 | station 0 `make test` → `bats:Gate 1` |
| skip | 2 | station 0 SSO login (interactive); station 1 tenant-session CLI lines (need the SSO session; the next block checks the same rules) |

**All copyable blocks of stations 1–7 run**, except the tenant-session block of station 1.

## 5. Evidence
| Test | Result |
|---|---|
| `doc_tests.py --markers-only` | 53 blocks, 0 invalid or unmarked |
| `doc_tests.py` (live, read-only) | 25/25 run blocks ✔ (Lab 0: 11/11) |
| `make test-docs MODE=live-mutating`, run 1 | rc 2: the Drill 4 delete collided with Lab 0 station 6 (above); every Lab 0 block ✔; settle and Bats all ok. This led to the settle-before-each-block fix |
| `make test-docs MODE=live-mutating`, run 2 (19:06 UTC) | **rc 0 in 585 s**; 6/6 mutating ✔; settles 2 s / 113 s / 290 s; final settle and **Bats all ok** |
| Lab snapshot before run 1 vs after run 2 (49 lines: every Application's sync and health, queues and tagged VPCs per account 111/222/123, worker replicas) | **identical** (`diff` empty) |
| `make ci` | all checks passed |
| Negative tests (temporary edits to Lab 0, restored with `cmp`) | 1. altered `aws_as` copy → `copy of aws_as() differs from developer-tutorial.md Step 4`. 2. `with="argocd-admin"` → `unknown with=`. 3. wrong `expect` on the tree block → `output does not match`. All fail as required |
| Station 1 block's first version | failed live (exit 1). `argocd admin settings rbac can` **exits 1 when the answer is No**; fixed with `\|\| true`, and `expect` now asserts all four answers, so a real error still fails the check |

## 6. For the validator
1. Do Lab 0 as a learner, top to bottom, **as `tenant-a-user`** (station 0 login, station 1's skipped block). Record the outputs, and how long each station took.
2. `python3 tests/doc_tests.py --markers-only`; `make test-docs`; optionally `make test-docs MODE=live-mutating` (about 10 min; the lab repairs itself) with a before/after snapshot.
3. Judge the decisions in §2, especially the RBAC test via `--policy-file` and the break-glass session for station 7.
4. Check that the explanations are correct (station 7: Argo CD 3.x does not store per-resource health in `status.resources`; station 1: RBAC vs AppProject).
