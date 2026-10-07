# Learner On-Ramp Plan: Implementation Report 04 (Phase 3, Track B: Lab 1 blueprint sandbox)

> **Status: For independent validation (2026-10-07).** Implementer: Claude (Opus 5.5). Validator: Codex or Antigravity with Docker and k3d access, not me. Plan: [`2026-10-07-learner-on-ramp-plan.md`](2026-10-07-learner-on-ramp-plan.md) §4 (Track B), guardrails G-2 to G-4; owner decisions O-3 (kro only, moto + ACK as the `--with-moto` stretch) and O-5 (`make test-lab1` local only). Phase 2 accepted in [validation-03](2026-10-07-learner-on-ramp-plan-validation-03.md). Change: `gitops-control-plane`, this commit.

## Verdict
Track B's acceptance criteria are met on this machine:
- **`make test-lab1` passed twice in a row** from a clean state, with 36 checks each, in 186 s and 177 s. Earlier attempts failed; §4 lists them.
- **Every expected failure message in the exercise is copied from a real run**, and `make test-lab1` asserts the key phrase of each one.
- **`sandbox-down` verifies** that no cluster, container, network or kube context is left.
- **The shared lab is untouched:** the 49-line snapshot is identical, Bats is 28/28, and the kube contexts and current context are unchanged.

## 1. What was built
| Item | Where |
|---|---|
| `make sandbox-up [WITH_MOTO=1]` / `sandbox-down` / `sandbox-status`. One k3d cluster `learn-sandbox` (API `127.0.0.1:6560`, network `k3d-learn-sandbox`); the context is added **without switching** (`--kubeconfig-switch-context=false`). kro's chart version is read from `applicationsets/addons-spoke.yaml` and its values come from `platform-catalog/controllers/kro/values-kro.yaml` (`rbac.mode: aggregation`, the plan's version-drift mitigation). `--with-moto` adds `moto-sandbox` (`127.0.0.1:5002`, the lab's pinned moto image) and ACK SQS at the lab's chart version and values, pointed at `moto-sandbox`. `down` deletes everything, then checks for leftovers and exits 1 if any remain | `scripts/learning-sandbox.sh`, `Makefile` |
| **Lab 1** `docs/lab-1-write-a-blueprint.md`: steps 0–6 as planned, plus clean-up and four self-check questions. Each step has predict / measured / explain. Linked from Lab 0's "Next" and from the README | new |
| Reference solution: `rgd.yaml` (steps 1–4), `rbac.yaml`, `instances.yaml`, `policy.yaml` (VAP, step 5b), `rgd-with-queue.yaml` + `rbac-queue.yaml` (stretch) | `docs/lab-1-solution/` |
| **`make test-lab1`**: creates the sandbox, then plays every step. Step 1 applies the **YAML blocks from the doc itself** (`<!-- lab1-file: … -->`), so the copied YAML is what is tested. It asserts each result and each expected failure, then removes the sandbox and checks that the kube contexts are unchanged | `tests/test-lab1.sh` |
| Doc markers: Lab 1 added to the learner docs; its 11 bash blocks are `covered by="check:test-lab1"` (new check id). Total: **68 blocks in 8 documents**: run 26, mutating 6, covered 16, skip 20, 0 unmarked | `tests/doc_tests.py` |

## 2. Measured, and where it differs from the plan
| Plan | Measured (recorded in the doc) |
|---|---|
| Step 1: "Observe it fail" | **Two layers.** Without any grant: RGD `Inactive`, `ControllerReady=False … cache sync timeout` after about 30 s; the instance has **no status**; the kro log says `webgreetings.kro.run is forbidden … cannot list`. With the instance kind only: instance `ERROR`, `deployments.apps "hello" is forbidden`. With the child kinds: `ACTIVE` 5–10 s later |
| Step 2: "see kro order creation by dependency" | `status.topologicalOrder` `["deployment","config"]` → `["config","deployment"]` after the reference (the Deployment is declared first on purpose) |
| Step 3: conditional Service | Works. The new failure mode is worth teaching: without `services` RBAC, `hello-public` has **no status at all**, and only the kro log shows the cause. Toggling `expose` creates and deletes the Service within about 1 s |
| Step 4: `readyWhen` | `ACTIVE/True` → `IN_PROGRESS/False` → `ACTIVE/True` with `availableReplicas 3` in about 3 s. A comparison without `readyWhen` was **not** clean on kro 0.9.4 (Ready also flickered), so the doc does not claim one |
| Step 5a: "`GraphResolved=False`" | Actually **`GraphAccepted=False`** with the CEL compile error `undefined field 'nmae'`, at RGD apply time. Running instances stay `ACTIVE` on the last good revision |
| Step 5b: D-14 | Reproduced exactly: `KindReady=False … breaking changes detected: Minimum constraint 1 was added; Maximum constraint 5 was added`; the CRD keeps its old schema. A VAP (`policy.yaml`) denies `replicas: 9` with its message |
| Step 6 (stretch) | `status.queueURL` set within 3–5 s and copied into the ConfigMap. Deleting the instance cascades: the queue disappears from moto within 1–7 s. Without CARM, the queue lands in moto's default account `123456789012`; the doc explains how the lab differs |

The plan's schema field `name` is the instance's `metadata.name`, which is idiomatic kro, so the schema has `message`, `replicas` and `expose`. The page container listens on 8000, not 8080, because the CI guard against old hub URLs (`ci/check-sso-urls.py`) matches `localhost:8080`.

## 3. Evidence
| Test | Result |
|---|---|
| `make test-lab1` ×2 in a row | **rc 0, 36 checks, 186 s; rc 0, 36 checks, 177 s** (after the port change; the two passes before it were also green) |
| `sandbox-down` | `✔ sandbox removed (no cluster, container, network or kube context left)`; `k3d cluster list` shows only the lab and the owner's `argolab` |
| Shared lab (G-2) | 49-line snapshot before Phase 2 vs after all Lab 1 runs: **identical**; `make test` **28 ok, 0 not ok**; current context `k3d-spoke-prod` unchanged; the lab clusters were never addressed |
| `doc_tests.py --markers-only` | 68 blocks, 0 invalid or unmarked |
| `make ci` | all checks passed; **41** scripts shellcheck-clean (the two new ones included once tracked) |

## 4. Failures on the way (test or doc, all fixed)
| Run | Failure | Cause | Fix |
|---|---|---|---|
| 1 | `no matches for kind "WebGreeting"` | instances applied before kro created the CRD | the test waits for the CRD (`Established`); the doc tells learners to wait |
| 2 | `exec`: `container not found ("web")` | without `readyWhen` (step 4), the instance is Ready before its pod runs | `rollout status` in the test and in the doc's block; the doc uses it as a pointer to step 4 |
| 3 | `no 'services is forbidden' in the kro log` | **my test bug:** `kubectl logs \| grep -q` under `pipefail` fails on SIGPIPE | capture the log first |
| 4 | `hello not ACTIVE after step 2` | a brief re-reconcile after the new revision | wait for `ACTIVE`, and print the state seen right after the apply |
| 5 | `strict decoding error: unknown field "spec.expose"` | the RGD reports `Active` before kro has updated the CRD | the test waits for the CRD field; the doc names the message and what to do |
| CI | SC1007 (`AWS_SESSION_TOKEN= \`); the old-hub-port guard on `localhost:8080` | — | `AWS_SESSION_TOKEN=''`; container port 8000 |

Failures 1, 2 and 5 are real learner pitfalls, and the doc now names each of them.

## 5. For the validator
1. From a state without a sandbox: `make test-lab1` twice; both rc 0. Then `k3d cluster list`, `docker ps -a`, `docker network ls`, `kubectl config get-contexts`: nothing named `learn-sandbox`/`moto-sandbox`.
2. Do Lab 1 as a learner from the doc (about 60 min), from your own empty directory, comparing every **Measured** line, especially steps 1, 3 and 5.
3. Check that nothing touched the lab: snapshot and `make test` before and after.
4. Judge: is kro-only with a `--with-moto` stretch the right size (O-3)? Do the explanations of aggregated RBAC, `includeWhen`, D-14 and the VAP match `platform-catalog/blueprints/`?
