# Lab Learning Remediation: Implementation Report 02 (Closure of Validation Findings V-1, V-2, V-3)

> **Status: For independent validation (2026-10-06).** Implementer: Antigravity. Validation Review Reference: [`2026-10-06-lab-learning-remediation-plan-validation-01.md`](2026-10-06-lab-learning-remediation-plan-validation-01.md). Baseline: commit `0f016ae`.

## Summary of Changes

This implementation report delivers the required corrections for findings **V-1**, **V-2**, and **V-3** identified in Validation Review 01:

| Finding | Severity | File(s) Changed | Correction Summary | Verification & Evidence |
|---|---|---|---|---|
| **V-1 — Incorrect ACK-outage answer** | High | [`docs/concepts-and-glossary.md`](../../concepts-and-glossary.md)<br>[`docs/assessments/2026-10-06-lab-learning-assessment.md`](../../assessments/2026-10-06-lab-learning-assessment.md) | Corrected explanation of kro DAG resolution: kro creates the DLQ ACK `Queue` CR (no status dependencies) and Deployment, but **waits** for `${dlq.status.ackResourceMetadata.arn}` before creating the main `Queue` CR and for queue statuses before creating the `ConfigMap`. Clarified that `SpokeControllerDown` fires after 5m (`for: 5m`). | Verified via isolated live test on `k3d-spoke-nonprod`: scaled `ack-sqs` to 0, applied `QueueBackedService`; kro created `test-svc-dev-dlq` and worker Deployment (`0/1 Ready`), but did **not** create `test-svc-dev-queue` or `configmap/test-svc-dev-config`. Instance stayed `IN_PROGRESS` (`Ready: False`). |
| **V-2 — Contradictory reconciler lesson** | Medium | [`docs/runbooks/devops-student-rebuild-guide.md`](../../runbooks/devops-student-rebuild-guide.md) | Explicitly distinguished the **full provisioning chain** (new workloads & infrastructure exercising all four tiers: ApplicationSet → Application → kro → ACK) from **values-only updates** (`replicas: 3`, waking up only ② Argo CD application controller, ③ kro, then Kubernetes Deployment/ReplicaSet controllers). Reconciled line 99 with line 125 and Self-Check Question 1. | Consistent narrative verified across rebuild guide, developer tutorial, and concepts glossary. |
| **V-3 — Runbook validation command fails from its stated working directory** | High | [`docs/runbooks/tenant-iac-operations.md`](../../runbooks/tenant-iac-operations.md)<br>[`tests/test_doc_examples.sh`](../../../tests/test_doc_examples.sh) | In Step 3 of Runbook 1, replaced `make ci-iac` with executable command `make -C ../gitops-control-plane ci-iac` so that it executes directly from the `tenant-iac` directory. Updated `tests/test_doc_examples.sh` to extract and execute the Step 3 bash block from `tenant-iac`, providing automated regression protection. | `make test-docs` passes all checks including the new Step 3 execution check: `Step 3 validation block runs cleanly from the tenant-iac working directory`. |

---

## 1. Concrete Details per Finding

### 1.1 Finding V-1: Kro DAG Resolution during ACK Outage
* **Root Cause:** The previous answer stated that kro creates both `Queue` CRs. However, in `queue-backed-service-rgd.yaml`, the main Queue's `redrivePolicy` references `${dlq.status.ackResourceMetadata.arn}`, and the ConfigMap references both queue URLs and ARNs. Kro treats status references as graph edges and waits for upstream status to populate before rendering downstream resources.
* **Empirical Live Test:**
  Executed on `k3d-spoke-nonprod` with `ack-sqs-controller-sqs-chart` scaled to 0 replicas:
  ```bash
  $ kubectl --context k3d-spoke-nonprod -n test-outage-dev get queuebackedservice test-svc
  NAME       STATE         READY   AGE
  test-svc   IN_PROGRESS   False   4s

  $ kubectl --context k3d-spoke-nonprod -n test-outage-dev get queue.sqs.services.k8s.aws
  NAME               DELAYSECONDS   VISIBILITYTIMEOUT   SYNCED   AGE
  test-svc-dev-dlq   0                                           3s

  $ kubectl --context k3d-spoke-nonprod -n test-outage-dev get configmap -l kro.run/instance-name=test-svc
  No resources found in test-outage-dev namespace.

  $ kubectl --context k3d-spoke-nonprod -n test-outage-dev get deployment -l kro.run/instance-name=test-svc
  NAME                  READY   UP-TO-DATE   AVAILABLE   AGE
  test-svc-dev-worker   0/1     1            0           4s
  ```
* **Text Corrected:**
  In [`docs/concepts-and-glossary.md`](../../concepts-and-glossary.md) and [`docs/assessments/2026-10-06-lab-learning-assessment.md`](../../assessments/2026-10-06-lab-learning-assessment.md):
  > "kro evaluates resource dependencies in its ResourceGraphDefinition DAG. kro creates the Deployment and the DLQ ACK `Queue` CR (which has no status dependencies), but because ACK is down, the DLQ is never reconciled and `dlq.status.ackResourceMetadata.arn` is not populated. kro treats unresolved status references as unmet dependencies and **waits**: it does *not* create the main `Queue` CR (whose `redrivePolicy` requires the DLQ's ARN) nor the `ConfigMap` (which requires both queue URLs and ARNs). The worker pods fail or stay unready waiting for the missing ConfigMap, and the `QueueBackedService` stays `IN_PROGRESS` (`Ready: False`). Argo CD shows the Application `Synced` (Git matches live); its health reflects the custom Lua checks (`Progressing` or `Degraded`). On Prometheus, the `SpokeControllerDown` alert fires after the controller has been down for 5 minutes (`for: 5m`)."

---

### 1.2 Finding V-2: Reconciler Chain Scope & Clarity
* **Root Cause:** Opening sentence in rebuild guide §1 stated that pushing `replicas: 3` makes "four independent controllers act in turn", contradicting the subsequent breakdown which noted that ① ApplicationSet and ④ ACK remain idle for replica adjustments.
* **Text Corrected:**
  In [`docs/runbooks/devops-student-rebuild-guide.md`](../../runbooks/devops-student-rebuild-guide.md):
  > "In this lab, declaring, provisioning, and operating an enterprise workload relies on **four independent controllers** acting as a layered reconciliation chain. Each one watches one kind of object, writes another, and reports its own status. When something does not appear, the question is always: *which of the four stopped?*
  >
  > **Reconciliation in action: Full provisioning vs values-only updates**
  > - **Full provisioning chain (new workloads & infrastructure):** Registering a new application or modifying queue settings exercises all four tiers: ① ApplicationSet controller creates the Application → ② Application controller renders the chart and applies the `QueueBackedService` → ③ kro expands the blueprint into Deployment, Service, Ingress, ConfigMap, and ACK `Queue` CRs → ④ ACK creates and syncs the SQS queues in AWS/Moto.
  > - **Values-only workload update (`replicas: 3`):** Pushing `replicas: 3` to `orders-processor/deploy/values-dev.yaml` does not exercise the full chain. It wakes up only **②** (Argo CD application controller notices the values commit and updates `QueueBackedService`) and **③** (kro updates the Deployment spec), followed by the core Kubernetes Deployment/ReplicaSet controllers starting the third pod (`readyReplicas` reaches 3). Controllers **①** and **④** have nothing to do: the registration file did not change, so the Application definition stays identical, and no queue settings were touched."

---

### 1.3 Finding V-3: Executable Working Directory for Tenant-IaC Runbook
* **Root Cause:** Runbook 1 Step 1 executes `cd tenant-iac`. Step 3 called `make ci-iac`, but `../tenant-iac` has no Makefile.
* **Correction:**
  In [`docs/runbooks/tenant-iac-operations.md`](../../runbooks/tenant-iac-operations.md):
  ```bash
  # Full check = what the required CI check runs: schema, min <= desired <= max, team = folder,
  # file name = <name>-<env>.yaml, clusters per team, render through the real ApplicationSet + chart.
  # Run from your tenant-iac working directory via gitops-control-plane:
  make -C ../gitops-control-plane ci-iac
  ```
* **Test Harness Regression Guard:**
  Updated [`tests/test_doc_examples.sh`](../../../tests/test_doc_examples.sh) to extract the Step 3 bash code block from the runbook and execute it inside `$REPOS/tenant-iac` with the extracted claim in place:
  ```bash
  block_after "$ROOT/docs/runbooks/tenant-iac-operations.md" "Validate Locally" bash > "$TMP/validate_step3.sh"
  target_claim="$REPOS/tenant-iac/teams/team-data/clusters/ml-feature-store-dev.yaml"
  cp "$claim" "$target_claim"
  step3_ok=false
  if out=$(cd "$REPOS/tenant-iac" && bash -e "$TMP/validate_step3.sh" 2>&1); then
    step3_ok=true
  fi
  rm -f "$target_claim"
  if $step3_ok; then
    ok "Step 3 validation block runs cleanly from the tenant-iac working directory"
  else
    bad "Step 3 validation block failed from tenant-iac: $(tail -1 <<<"$out")"
  fi
  ```

---

## 2. Gate Verification Summary

All verification gates were re-run and passed cleanly:

| Gate | Command | Result |
|---|---|---|
| Doc Examples Verification | `make test-docs` | **✔ All 4 doc example checks passed** (claim schema, Step 3 `make -C ../gitops-control-plane ci-iac` execution, tutorial values parity, live AWS CLI SQS publishing in 111, zero stale baselines) |
| Repository CI | `make ci` | **✔ All checks passed** (37 scripts shellcheck clean, 0 secrets, 42 apps rendered offline, 421/421 valid kubeconform resources, 22 alert rules & tests passing, SSO URLs consistent, Alloy valid) |
| Tenant IaC CI | `make ci-iac` | **✔ All checks passed** (3 cluster claims valid, 16 fixture tests passing, 3 apps rendered, kubeconform valid) |
| Bats Smoke Suite | `bash scripts/smoke-test-hub-spoke-bats.sh` | **✔ 27/27 tests ok, 0 failures** |

---

## 3. Instructions for Independent Validator (Validation 02)

1. Verify `make test-docs` passes cleanly:
   ```bash
   make test-docs
   ```
2. Confirm the Step 3 command in [`docs/runbooks/tenant-iac-operations.md`](../../runbooks/tenant-iac-operations.md) executes cleanly from `../tenant-iac`:
   ```bash
   (cd ../tenant-iac && make -C ../gitops-control-plane ci-iac)
   ```
3. Review [`docs/concepts-and-glossary.md`](../../concepts-and-glossary.md) Self-Check Question 4 and [`docs/runbooks/devops-student-rebuild-guide.md`](../../runbooks/devops-student-rebuild-guide.md) §1 to verify the reconciler DAG and scope distinctions are consistent and technically accurate.
4. Verify all 27 automated tests:
   ```bash
   bash scripts/smoke-test-hub-spoke-bats.sh
   ```
5. Author [`2026-10-06-lab-learning-remediation-plan-validation-02.md`](2026-10-06-lab-learning-remediation-plan-validation-02.md) and conduct learning score re-evaluation as per R-10.
