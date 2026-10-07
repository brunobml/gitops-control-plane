# Learner On-Ramp Plan — Independent Validation 05 (Phase 3 guard fixes)

> **Status: Changes requested; live acceptance pending (2026-10-07).** Validator: Codex. Implementer: Claude. Scope: [implementation report 05](2026-10-07-learner-on-ramp-plan-implemented-05.md), change `319441e`, responding to [validation-04](2026-10-07-learner-on-ramp-plan-validation-04.md).

## Verdict

V3-1 and V3-2 are substantially fixed, and V3-3's kro-only learning path is now implemented. The new k3d verification still accepts an empty successful response as “no cluster,” so teardown can again report clean state without a usable cluster inventory. Phase 3 also requires two independent live `make test-lab1` runs and a learner walkthrough; this session cannot reach Docker or k3d and cannot complete those gates.

## Finding

| ID | Finding | Independent evidence and correction |
|---|---|
| V3-4 | **Empty k3d inventory is treated as successful verification.** `k3d_clusters()` captures `k3d cluster list -o json`, then runs `jq -r '.[].name'`. `jq` exits 0 on empty stdin and prints nothing. `down()` therefore sees no cluster and prints `sandbox removed` if its other reads are empty. The guard suite's “no JSON” case supplies malformed text (`FATA no nodes`), which `jq` rejects; it does not cover an empty response. | With exported test `k3d`, `docker`, and `kubectl` functions returning exit 0 and empty inventories, `bash scripts/learning-sandbox.sh down` printed `✔ sandbox removed …` and exited **0**, with no real resources touched. Require a nonempty response and a JSON array before extracting names; add an empty-success response to `test-sandbox-guards.sh`. |

## Independent checks

| Check | Result |
|---|---|
| `bash tests/test-sandbox-guards.sh` | Passed all 15 cases: 11 teardown cases and 4 queue-state cases. The previously reported exit-77 injection now fails closed. |
| Source review | `queue_state` checks a successful AWS list and a control queue; the deletion wait aborts on `error`. Service and policy checks now distinguish failed reads from absence. Lab 1 starts kro-only and adds moto/ACK at step 6 without recreating the sandbox. |
| `bash -n` for sandbox, Lab 1 test, and library | Passed. |
| `python3 tests/doc_tests.py --markers-only` | Passed: 69 blocks in 8 learner documents, 0 invalid or unmarked. |
| Live gate | `docker info` and `k3d cluster list` were denied access to `/var/run/docker.sock`. No `make test-lab1` run, learner walkthrough, or shared-lab snapshot was performed in this review. |

After V3-4 is closed, a validator with Docker and k3d access should complete implemented-04 §5 and implemented-05 §For the validator: `make test-lab1` twice from a clean state, Lab 1 from an empty directory as a learner, no sandbox residue, and before/after shared-lab snapshot plus Bats. Phase 4's human pilot follows Phase 3 acceptance.
