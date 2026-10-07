# Learner On-Ramp Plan: Implementation Report 07 (Lab 1 walkthrough by the owner)

> **Status: Doc fixes for independent validation (2026-10-07).** Implementer: Claude (Opus 5.5). Input: the owner's `make test-lab1` run (rc 0, 39 checks, the first independent pass) and the owner's hand walkthrough of Lab 1 (terminal transcript, 2026-10-07). This is the first real-learner evidence for Track D. Phase 3 is **not** accepted by this report.

## What the walkthrough showed
| # | Observed | Cause | Fix |
|---|---|---|---|
| W-1 | Files created in the repository root (`rgd.yaml`, `instance.yaml`, `rbac.yaml`) | the doc said "work in an empty directory" but never created one | a block at the start: `mkdir -p ~/lab1-work && cd ~/lab1-work` and `SOL=…/docs/lab-1-solution`; clean-up removes `~/lab1-work` |
| W-2 | The expected `forbidden` output was pasted into the shell (`command not found`) | output blocks looked like commands | every expected-output block starts with `# output (compare, do not run)`, and the convention is stated at the top |
| W-3 | After the instance-only grant, the status was empty; the learner moved on before the planned `ERROR` appeared | the doc said "after about 30 s" with no way to wait | a `-w` watch ("empty for about 30 s, then ERROR: Ctrl-C"), then the message |
| W-4 | Step 3: `hello-public` was never created and `services` never granted | step 3 had no commands, only prose | an `instance-public.yaml` block (`lab1-file: step3-instance`, which `make test-lab1` now checks against the solution) and an apply block; the measured text says how to add `services` |
| W-5 | `spec.resources[3]: Invalid value: exactly one of template or externalRef must be provided` | an editing slip in the new resource | the message and its meaning (resource N, counting from 0, lost `template:` or its indentation) are added to step 3 |
| W-6 | Step 5b: `error: the path "policy.yaml" does not exist`, then `replicas: 9` was **accepted** | the doc linked to the solution file but applied `policy.yaml` from the working directory | `cp "$SOL/policy.yaml" .` before applying |
| W-7 | Step 6: `QUEUE <none>`, `list-queues` → `None` | step 6 had observe commands but **no apply**; the learner never applied the queue RGD | a copy-and-apply block for `rbac-queue.yaml` and `rgd-with-queue.yaml`, before observing |
| W-8 | `exec … wget -qO- localhost:8000` printed **nothing** | **unexplained.** The same check passes in `make test-lab1` with the doc's own YAML (also in the owner's run). The learner's hand-typed `rgd.yaml` was deleted before review | open: needs the learner's file on a repeat (an empty `index.html` would explain it) |
| W-9 | `sandbox-up` answered "already exists" twice, then succeeded with no `down` in between | **unexplained**; most likely a concurrent `make test-lab1` in another terminal, whose teardown removed the sandbox | open: ask the owner |

Six of the seven fixed defects are doc gaps that `make test-lab1` could not find. The test plays the solution files, so it never needed the missing commands. That is the point of G-5: tests prove the commands work, and only learners prove the doc is followable.

## Gates after the fixes
| Test | Result |
|---|---|
| `make test-lab1` | rc 0, 39 checks, 205 s (it also checks that the doc's step-3 instance matches the solution) |
| Drift check negative test | the doc's `hello-public` message changed → `doc step3-instance differs …`, exit 1; unchanged → exit 0 |
| `doc_tests.py --markers-only` | 72 blocks, 0 unmarked |
| `make ci` | all checks passed |

## Still needed for Phase 3 acceptance
1. A second independent `make test-lab1` pass (the owner's run is the first).
2. A **complete** learner walkthrough with the fixed doc, ideally with the learner's files kept, to settle W-8, and noting time per step.
3. A validation report by someone other than me.

Leftover from the walkthrough: an untracked `instance.yaml` in the `gitops-control-plane` root (the owner's file; delete it with `rm ~/repos/gitops-control-plane/instance.yaml`).
