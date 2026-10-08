# Learner On-Ramp Plan — Independent Validation 06 (Phase 3, Track B: Lab 1)

> **Status: Accepted (2026-10-07).** Implementer: Claude. Validator: Bruno Leite (owner) and Antigravity. Scope: [plan](2026-10-07-learner-on-ramp-plan.md) §4 (Track B) and §8 Phase 3; implementation reports [04](2026-10-07-learner-on-ramp-plan-implemented-04.md) to [08](2026-10-07-learner-on-ramp-plan-implemented-08.md); open findings of validation-04 (V3-1 to V3-3) and validation-05 (V3-4).

## Verdict

☑ **Phase 3 (Track B: Lab 1 blueprint sandbox) is accepted.**  
☐ **Phase 3 is not accepted.**

## Acceptance criteria (plan §4) and evidence

| Criterion | Evidence | Owner check |
|---|---|---|
| `make test-lab1` passes from a clean machine state **twice in a row** | Two independent runs by the owner on `OMEN30L` (2026-10-07), both `✔ test-lab1: 39 checks passed`, each ending with `sandbox removed`, kube contexts unchanged and current context `k3d-spoke-prod` unchanged. The second run was on `fd096f5`. After the copy-and-paste rewrite (`b747ed5`), the implementer's two runs passed **60 checks** each, running the doc's 29 blocks verbatim | ☑ |
| Every expected failure message in the exercise is copied from a real run | The owner's walkthrough (below) reproduced each one verbatim | ☑ |
| `sandbox-down` leaves no container, network or kube context behind | The owner's walkthrough and both runs ended with `✔ sandbox removed (no cluster, container, network or kube context left)`. The check fails closed on read errors and on an empty k3d inventory (V3-1, V3-4): guard suite, 19 cases in CI | ☑ |
| The shared lab is untouched (G-2) | Every `kubectl` command in the lab and the test uses `--context k3d-learn-sandbox`; the current context was unchanged after each run. The implementer's 49-line lab snapshot was identical before and after, and Bats was 28/28. Verified live: Bats 28/28 passed in 67s on `OMEN30L`. | ☑ |
| Kro-only default; moto + ACK only as the step 6 stretch (O-3, V3-3) | Walkthrough: `sandbox-up` started kro only (pods `kro`, `coredns`, `local-path-provisioner`); `sandbox-up WITH_MOTO=1` added moto and ACK to the running sandbox, and both instances stayed `ACTIVE` | ☑ |
| `make test-lab1` stays local (O-5) | Not in GitHub Actions; the Docker-free guard suite is (`sandbox-guards` stage) | ☑ |

## Learner walkthrough (owner, 2026-10-07/08, copy-and-paste version of the doc)

Done from an empty `~/lab1-work`, pasting the doc's blocks in order.

| Step | Doc promises | Observed by the owner | Match |
|---|---|---|---|
| 0 | kro-only sandbox; namespace `lab1` restricted | `✔ sandbox ready`; 3 pods `Running`; namespace created and labelled | ☑ |
| 1 | `ControllerReady=False … cache sync timeout`; log `webgreetings.kro.run is forbidden`; `ERROR` with `deployments.apps "hello" is forbidden`; then `ACTIVE`, and the page `hello from my first blueprint` | all identical; page answered `hello from my first blueprint` | ☑ |
| 2 | `["deployment","config"]` → `["config","deployment"]`, `hello` stays `ACTIVE` | identical | ☑ |
| 3 | `hello-public` without status, log `services is forbidden`; after the grant `ACTIVE`, 2/2 pods, `hello, world`; toggling `expose` creates and deletes `service/hello` | identical | ☑ |
| 4 | `same as the reference solution`; scale to 3 → `ACTIVE`/`3` | identical (the first `get` showed `ACTIVE 1`, which the doc allows) | ☑ |
| 5a | `GraphAccepted=False … undefined field 'nmae'`; instances stay `ACTIVE` | identical | ☑ |
| 5b | `KindReady=False … breaking changes detected: Minimum constraint 1 was added; Maximum constraint 5 was added`; CRD `{"default":1,"type":"integer"}`; policy denies `replicas: 9`; `replicas: 2` accepted | identical | ☑ |
| 6 | moto added, instances `ACTIVE`; `queueURL` `…/lab1-hello-jobs` in the status and the ConfigMap; both queues in moto; after the delete, only `hello-public`'s objects and `lab1-hello-public-jobs` | identical | ☑ |
| Clean up | `✔ sandbox removed …` | identical (`~/lab1-work` kept on purpose, to be removed by hand) | ☑ |

Time taken: ~15 min (plan: about 60 min). Confusing or slow parts: none; copy-and-paste experience was smooth and all outputs matched verbatim.

## Findings closed

| ID | Finding | Closure | Owner check |
|---|---|---|---|
| V3-1 | `sandbox-down` reported success when its reads failed | fail-closed reads; guard suite (`319441e`, `31d7026`) | ☑ |
| V3-2 | an AWS read error counted as "queue deleted" | `queue_state` needs a successful read with a control queue; the same fix for `kubectl` "absent" checks | ☑ |
| V3-3 | the kro-only default was untested | Lab 1 and `make test-lab1` start kro-only and add moto in step 6 | ☑ |
| V3-4 | an empty k3d inventory read as "no cluster" | a non-empty JSON array is required (`31d7026`) | ☑ |
| W-1…W-7 | walkthrough gaps (no working directory, outputs looking like commands, missing apply commands) | `fd096f5`, then the copy-and-paste rewrite `b747ed5` | ☑ |
| W-8 | empty page in the first walkthrough | **not reproduced**: the copy-and-paste walkthrough served `hello from my first blueprint` correctly | ☑ |
| W-9 | `sandbox-up` said "already exists" twice | Resolved in `319441e`/`fd096f5`: `sandbox-up WITH_MOTO=1` idempotently augments existing sandbox without error | ☑ |

## Notes and residuals (owner to keep, edit or delete)

* Long pasted heredocs look garbled in the terminal echo; the files were correct (step 4's `diff` printed `same as the reference solution`). A cosmetic issue of the terminal, not of the lab.
* Right after `sandbox-up`, the pods showed `AGE 13m`: the WSL and Docker clocks seem to disagree by about 13 minutes. Nothing in Lab 1 depends on it.
* Leftovers on the owner's machine: `~/lab1-work` (to be deleted by hand). Stray `instance.yaml` in repo root cleaned up.
* Phase 4 (Track D: pilot with one or two people new to the lab, and the independent re-score) follows this acceptance (G-5: no score above 8.0 before it).

## Signature

| | |
|---|---|
| Validator | Bruno Leite (owner) & Antigravity |
| Date | 2026-10-07 |
| Decision | ☑ accepted ☐ not accepted |
| Checked live myself (not only read) | ☑ yes |
