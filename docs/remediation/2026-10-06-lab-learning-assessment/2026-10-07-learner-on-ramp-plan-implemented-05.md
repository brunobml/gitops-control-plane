# Learner On-Ramp Plan: Implementation Report 05 (validation-04 V3-1 to V3-3)

> **Status: For independent validation (2026-10-07).** Implementer: Claude (Opus 5.5). Answers [validation-04](2026-10-07-learner-on-ramp-plan-validation-04.md) (Codex: changes requested). Validator: Codex or Antigravity **with Docker and k3d access** for the live part; the guard tests below need neither. Change: `gitops-control-plane`, this commit.

## V3-1: `sandbox-down` fails closed (fixed)
Codex was right: every failed read counted as "absent", and the script printed `sandbox removed` with exit 0. `scripts/learning-sandbox.sh` now works like this:
- Every inspection (`k3d cluster list -o json` parsed with `jq`, `docker ps -a`, `docker network ls`, `kubectl config get-contexts`) is captured with a plain assignment, so `set -e` stops on a failed read. A failed read exits 1 with `could not verify: …`.
- A failed `docker rm` or `k3d cluster delete` exits 1.
- Success is printed only after four successful reads that show no sandbox object.
- I also fixed a trap in my first draft of the fix. `has "$(k3d_clusters)"` would have lost the failure, because `exit` inside a command substitution leaves only the subshell. The script now has no `"$(…)"` arguments.
- `up` and `status` use the same reads.

**Negative test** `tests/test-sandbox-guards.sh`: stub `docker`, `k3d`, `kubectl` and `aws` executables on `PATH`, so it needs no Docker. It runs in `make ci` as the new stage **`sandbox-guards`**. Its 11 `down` cases:

| Case | Expected |
|---|---|
| Clean reads | rc 0, `sandbox removed` |
| Every read fails with 77 (Codex's reproduction) | rc 1, `could not verify` |
| Each read failing alone (4 cases) | rc 1, `could not verify` |
| k3d answers with no JSON | rc 1, `could not verify` |
| Network left behind | rc 1, `leftovers` |
| Kube context left behind | rc 1, `leftovers` |
| `docker rm` fails | rc 1 |
| Cluster delete fails | rc 1 |

**Mutation check:** the same test run against the script from `27a2248` fails 8 cases (`rc 0, output: ✔ sandbox removed`), which reproduces V3-1. Against the fixed script, all cases pass.

## V3-2: deleting the queue must be proven, not assumed (fixed)
`tests/lab1-lib.bash` `queue_state <queue> <control>` returns:
- `error` if `aws sqs list-queues` fails, or if a successful answer does **not** list the control queue (`lab1-hello-public-jobs`, which must still exist). An empty answer from the wrong endpoint or account therefore cannot pass.
- `present` or `absent` otherwise.

`make test-lab1` waits for `absent` and **aborts** on `error`. It first checks that the control queue is listed and that the queue is readable as present before the delete. The guard test covers `aws` failing with 77 → `error`, an empty answer → `error`, both listed → `present`, and only the control listed → `absent`.

**Same pattern elsewhere in `test-lab1.sh`, found by me and fixed** (Codex named only the queue check). Each of these "absent" checks passed when `kubectl` itself failed:
- "no Service `hello`" (`get service hello && fail || ok`);
- "Service deleted after toggling `expose`" (`! kubectl get service hello`);
- "`hello-public` has no status" (an empty jsonpath);
- "kro removed `hello`'s children" (`kubectl … | grep … || true`);
- "policy registered" (any dry-run failure counted).

Each now uses a read that must succeed, with a control object where it applies: `service/hello-public` and `deployment.apps/hello-public` must be listed. The policy check requires the policy's own message. `fail` reports on a saved stderr (fd 3), because `wait_for` silences its predicates' output.

## V3-3: the default path is kro-only and tested (fixed)
- Lab 1 step 0 is now `make sandbox-up` (kro only; **measured 34 s**).
- Step 6 starts with `make sandbox-up WITH_MOTO=1`, which on an existing kro-only sandbox **adds** only `moto-sandbox` and ACK SQS and keeps the learner's work (**measured 19 s**; instances stayed `ACTIVE`). Running it again refuses, because the sandbox already has moto.
- `make test-lab1` follows the same path: kro-only `up` (it checks that no `moto-sandbox` container exists), steps 1–5b, then `up --with-moto` (it checks that both instances stay `ACTIVE`), step 6, delete, and `down`.
- A manual kro-only `up` → add moto → `status` → `down` (2 s) cycle also passed, with the current context unchanged.

## Gates
| Test | Result |
|---|---|
| `make test-lab1` ×2 in a row (kro-only start) | **rc 0, 39 checks, 204 s; rc 0, 39 checks, 215 s** |
| `tests/test-sandbox-guards.sh` | 15/15 (11 `down`, 4 `queue_state`); against the old script, 8 fail as required |
| `make ci` | all checks passed, including the new stage `sandbox-guards`; 42 scripts shellcheck-clean |
| `doc_tests.py --markers-only` | 69 blocks (the step 6 `sandbox-up` block is new), 0 unmarked |
| Shared lab | 49-line snapshot identical; current context `k3d-spoke-prod` unchanged |

## For the validator
1. Without Docker: `bash tests/test-sandbox-guards.sh`, or `ci/check-control-plane.sh sandbox-guards`. Optionally repeat your exit-77 reproduction against `scripts/learning-sandbox.sh down`: it must exit 1.
2. With Docker and k3d: the live checks of implemented-04 §5 (`make test-lab1` twice, Lab 1 as a learner, the before/after lab snapshot), now with a kro-only start.

This commit also adds Codex's validation-04, which could not be committed from its read-only session.
