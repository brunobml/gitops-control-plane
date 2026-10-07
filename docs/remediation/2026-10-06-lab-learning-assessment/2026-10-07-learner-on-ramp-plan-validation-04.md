# Learner On-Ramp Plan — Independent Validation 04 (Phase 3, Lab 1)

> **Status: Changes requested; live acceptance pending (2026-10-07).** Validator: Codex. Implementer: Claude. Scope: [plan](2026-10-07-learner-on-ramp-plan.md) Phase 3 / Track B and [implementation report 04](2026-10-07-learner-on-ramp-plan-implemented-04.md), change `27a2248`.

## Verdict

I could not run the required two clean `make test-lab1` passes or take the learner tour: this session is denied access to the Docker socket, which also prevents k3d access. Static review found two fail-open assertions that must be fixed before the cleanup and cloud-deletion claims can be accepted. The implementer's two passing runs remain useful evidence, but are not independent acceptance.

## Findings

| ID | Finding | Independent evidence and required correction |
|---|---|
| V3-1 | **`sandbox-down` reports success when its inspection calls fail.** `scripts/learning-sandbox.sh` suppresses a failed `docker rm`, treats a failed `k3d cluster list` as absence, and uses failed Docker, network, and kube-context reads in conditional pipelines. If all reads fail, `left` stays empty and line 95 prints `sandbox removed` with exit 0. | I exported test `docker`, `k3d`, and `kubectl` functions that each returned 77, then ran `learning-sandbox.sh down`. It printed the success message and exited **0**, with no real resource changes. Check each read separately and distinguish “absent” from “could not verify”; deletion or verification failure must exit nonzero. Add a negative test for a failed inspection call. |
| V3-2 | **The cloud queue deletion assertion accepts an AWS read error as deletion.** `tests/test-lab1.sh` line 148 waits on `! aws … sqs get-queue-url`. Any nonzero result, including endpoint or credential failure, satisfies the predicate. | With an exported `aws` test function returning 77, the exact negated command exited **0**. Check that Moto is readable, then identify the specific `NonExistentQueue` result (or verify with a successful `list-queues` response lacking the queue). An AWS read error must fail the test. |
| V3-3 | **The documented default path is not the path exercised.** O-3 chooses kro only by default with moto and ACK as a stretch, but Lab 1's first command always uses `WITH_MOTO=1`, and `make test-lab1` always starts with `--with-moto`. The comment says the flag is “only for step 6.” | Make the start command conditional for learners who will attempt step 6, and independently check a kro-only `sandbox-up`/`sandbox-down` cycle. This is a documentation and coverage issue; the Makefile's default itself is kro-only. |

## Checks and limits

- `python3 tests/doc_tests.py --markers-only` passed: **68 bash blocks in 8 documents**, 0 invalid or unmarked.
- `bash -n scripts/learning-sandbox.sh tests/test-lab1.sh` passed. The complete copied YAML blocks and reference solution YAML parsed successfully with PyYAML. `shellcheck` is not installed in this session.
- Static comparison found the same aggregated kro RBAC label, `includeWhen` pattern, `readyWhen` use, and ValidatingAdmissionPolicy approach in `platform-catalog/blueprints/`. The exercise correctly labels its expected errors as observed; I could not reproduce them live.
- `docker info` failed with permission denied on `/var/run/docker.sock`; `k3d cluster list` failed for the same reason. No sandbox or shared-lab resource was created, modified, or deleted during this review.

After V3-1 and V3-2 are corrected, a validator with Docker and k3d access should follow §5 of implemented-04: run `make test-lab1` twice from a clean state, do Lab 1 from an empty directory as a learner, check a kro-only start as well as the stretch, and compare the shared lab snapshot and Bats results before and after.
