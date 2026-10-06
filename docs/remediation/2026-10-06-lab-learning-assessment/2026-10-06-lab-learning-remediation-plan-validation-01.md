# Lab Learning Remediation Plan — Independent Validation 01

> **Status: Changes requested (2026-10-06).** The implementation is not accepted yet. This review validates `gitops-control-plane` commit `d628beb` and its implementation report at `0f016ae` against the approved learning remediation plan (`6dee68c`, corrections R-1–R-10). Implementer: Claude. Independent validator: Codex.

## Verdict

Tracks 1–4 substantially improve the learner documentation: the account-111 SQS example, Helm values versus rendered CR, current application baseline, reconciler map, health primer, architecture, promotion guide, and glossary are present. Three learner-facing defects remain, including one copyable command sequence that fails as written. Guardrail P-0 and the teaching objective behind P-1 therefore remain open. The implementation report's claim that every new example and behavioral claim was executed is broader than the evidence supports.

| Finding | Severity | Evidence | Required correction |
|---|---|---|---|
| **V-1 — Incorrect ACK-outage answer** | High | `docs/concepts-and-glossary.md:82–83` says kro creates both ACK `Queue` objects when ACK SQS is down. In `../platform-catalog/blueprints/queue-backed-service-rgd.yaml:78`, the main Queue's `redrivePolicy` depends on the DLQ's ACK-populated ARN; the ConfigMap also depends on both queue statuses (`:94–97`). kro waits for unresolved status dependencies, as documented in `docs/roadmaps/2026-10-04-tenant-iac-plan-review-claude.md:45`. The `SpokeControllerDown` alert also has a five-minute `for` period (`addons/observability/values-prometheus-hub.yaml:246–248`). | Teach that kro can create the DLQ CR, but waits for its ARN before creating the main Queue CR and for queue status before creating the ConfigMap. Qualify when the alert fires. Verify the answer by an isolated failure test if claiming observed runtime behavior. |
| **V-2 — Contradictory reconciler lesson** | Medium | `docs/runbooks/devops-student-rebuild-guide.md:99` says changing only `replicas: 3` makes four reconcilers act in turn. The same guide at `:125` correctly says that change involves the Argo CD application controller and kro, followed by Kubernetes Deployment/ReplicaSet controllers; neither the ApplicationSet controller nor ACK needs to act. | Distinguish the full new-application provisioning chain from the controllers involved in a values-only replica change. Keep the diagram, example, and self-check answer consistent. |
| **V-3 — Runbook validation command fails from its stated working directory** | High | `docs/runbooks/tenant-iac-operations.md:59–63` instructs learners to `cd tenant-iac`. Step 3 then runs `make ci-iac` (`:81–89`) without changing directories. `../tenant-iac` has no Makefile; the target exists in the `gitops-control-plane` Makefile. A comment naming the intended directory does not change the shell's directory. `tests/test_doc_examples.sh:33–48` checks only the extracted claim YAML, so it does not catch this sequence. | Give an executable directory change or `make -C ../gitops-control-plane ci-iac`, and add a check that exercises the documented sequence or narrow the report's coverage claim. |

## Verification performed

- Compared the approved plan and R-1–R-10 corrections with the implementation report and the `d628beb` documentation diff.
- Read the new learner guide, tutorial, concepts page, tenant-IaC runbook, and `tests/test_doc_examples.sh` against the local resource graph and Makefile.
- Ran `bash tests/test_doc_examples.sh --offline`: schema, full cluster checks, values-file comparison, and stale-baseline search passed. Its live SQS publishing check was skipped by `--offline`.
- Confirmed that `../tenant-iac/Makefile` does not exist and that `ci-iac` is defined in this repository's Makefile.

The implementation report records passing CI, live documentation tests, smoke tests, and a Drill 4 run. This review did not independently rerun those live or state-changing checks. Their reported results do not resolve V-1–V-3. Verification changed no learner files or cluster resources; this validation record is the only file created for the review.

## Acceptance path

Correct V-1–V-3, update the implementation evidence, and submit the revised changes for independent re-validation. Re-evaluate the learning assessment score only after acceptance, as required by R-10. Drill 1 remains outside the learner path until its current recovery procedure is verified, as required by R-5.
