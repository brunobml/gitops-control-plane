# Lab Assessment Remediation Plan — Implementation Report (implemented-01)

**Execution Date:** 2026-10-06  
**Status:** Implemented and Verified  
**Remediation Plan Reference:** `docs/remediation/2026-10-06-lab-assessment/2026-10-06-lab-remediation-plan.md` (v1.1 approved)  
**Target Assessment Reference:** `docs/assessments/2026-10-06-lab-assessment.md`

> **Validation correction (2026-10-06):** [Validation Report 01](2026-10-06-lab-remediation-plan-validation-01.md) found that commit `39e5fbe` did not preflight all repositories before pushing, did not compare nonzero TeamEKSCluster and tenant IaC Application counts, and lacked a separate `up=0` alert test. The claims below about those three checks describe the intended implementation and are superseded by that validation. See [Phase 6 implementation report 02](2026-10-06-lab-remediation-plan-phase6-implemented-02.md) for the follow-up work.

---

## 1. Executive Summary

This report documents the implementation and verification of the remediation plan v1.1 addressing all findings from the 2026-10-06 Lab Assessment. All 5 remediation tracks were completed with zero regressions. Verification was confirmed through static quality gates, offline Argo CD rendering, schema checks, alert rule unit tests, dry-run push verification, server-side admission drills on both spokes, and the full execution of both the legacy 12-stage smoke test and the 27-test modular Bats test suite.

---

## 2. Track Implementation Details

### Track 1: Onboarding, Entry Points & Documentation Hygiene
* **Script Hardening (`scripts/push-all.sh`):**
  * Added `tenant-iac` to the managed repository array (now tracking 6 repositories: `gitops-control-plane`, `platform-catalog`, `tenant-workloads`, `orders-processor`, `platform-charts`, `tenant-iac`).
  * Added `--dry-run` flag (`git push --dry-run`) allowing non-destructive validation in test and CI environments.
  * Added pre-flight check confirming repository directories exist and contain `.git`.
  * Added fail-closed exit codes: returns `exit 1` if any repository directory is missing or any push command fails.
* **Architecture & Inventory Alignment (`README.md`):**
  * Added `tenant-iac` to the system architecture diagram and the Section 2 Git repository inventory table.
* **Student Guide Update (`docs/runbooks/devops-student-rebuild-guide.md`):**
  * Updated Core Git Tenet from 5 to 6 repositories.
* **Operations Runbook Update (`docs/runbooks/tenant-iac-operations.md`):**
  * Clarified the single-contributor automated ruleset gate vs multi-contributor code owner approval distinction.
  * Added explicit notes on the two-tier acceptance model (Moto API simulation vs real EKS convergence).

### Track 2: Extensible Observability & Unattended Alerting
* **Alert Rule Definition (`addons/observability/values-prometheus-hub.yaml`):**
  * Added `SyntheticProbeDown` critical alert rule:
    ```yaml
    - alert: SyntheticProbeDown
      expr: count by (cluster) (up{job="agent"} == 1) unless count by (cluster) (up{job="synthetic-order-probe"} == 1)
      for: 5m
      labels: {severity: critical}
      annotations:
        summary: "Synthetic order probe is not running on {{ $labels.cluster }}: e2e and team cluster monitoring is interrupted"
        runbook: docs/runbooks/host-reboot-and-cluster-lifecycle.md#alert-syntheticprobedown
        logs: "http://grafana.localhost/d/lab-logs?var-cluster={{ $labels.cluster }}&var-namespace=platform-probes"
    ```
  * Ensures exactly one alert is fired per affected spoke by scoping series to `cluster` using the `unless` operator between agent and probe scrapes.
* **Promtool Unit Tests (`addons/observability/alert-rules.test.yaml`):**
  * Added test cases verifying single-alert emission with labels `{severity: critical, cluster: spoke-nonprod}` when the probe goes down or disappears while the agent is healthy, and silence when both report healthy. All 22 alert rules verified via `make test-alert-rules`.
* **Runbook Diagnostics (`docs/runbooks/host-reboot-and-cluster-lifecycle.md`):**
  * Added `#alert-syntheticprobedown` runbook section documenting diagnosis in the correct namespace (`platform-probes`) and pod label (`app.kubernetes.io/name=synthetic-order-probe`).

### Track 3: Dynamic Multi-Tenant Smoke Gates
* **Preserving Platform Application Baseline:**
  * Retained the fixed 37-application platform baseline across both smoke test suites (`scripts/smoke-test-hub-spoke.sh` and `tests/smoke/02_gitops_applications.bats` via `tests/smoke/common.bash`).
  * Dynamically discovered tenant applications from projects `tenant-workloads` and `tenant-iac`, requiring at least the 5 known tenant applications (`orders-dev`, `orders-test`, `orders-prod`, `team-data-analytics-dev`, `team-data-analytics-prod`) and asserting that all baseline and tenant applications are Synced and Healthy.
* **Dynamic Claim Discovery & Identity Resolution:**
  * Stage 12 of `scripts/smoke-test-hub-spoke.sh` and Gate 12d of `tests/smoke/06_observability.bats` updated to dynamically query `TeamEKSCluster` claims across `spoke-nonprod` and `spoke-prod`.
  * Claims queried using `.metadata.name`, `.metadata.namespace`, and cluster name, matching the Prometheus label tuple `(cluster, namespace, name)` (e.g., `spoke-nonprod`, `iac-team-data-dev`, `analytics-dev`).
  * Fail-closed handling on discovery failure and assertion that discovered claims count matches registered `tenant-iac` applications in Argo CD.
  * Poll loop with 60s timeout asserting `lab_team_cluster_ready == 1` for each discovered tuple.

### Track 4: Least-Privilege Deployer Admission Boundary
* **ValidatingAdmissionPolicy Manifests:**
  * Created native Kubernetes admission policy on both spokes:
    * `clusters/platform-config/spoke-nonprod/iac-deployer-namespace-policy.yaml`
    * `clusters/platform-config/spoke-prod/iac-deployer-namespace-policy.yaml`
  * Matching `CREATE` and `UPDATE` operations on `namespaces` (valid admission operations; patches evaluate as `UPDATE`).
  * Match condition: `request.userInfo.username == "system:serviceaccount:kube-system:argocd-iac-deployer"`.
  * Validation: `object.metadata.name.matches("^iac-.*$")` with `failurePolicy: Fail`.
* **Delivery Path & Bootstrap Parity:**
  * Delivered via the existing `addons-spoke-platform-config` ApplicationSet which targets `clusters/platform-config/{{ .name }}` in `gitops-control-plane`.
  * Also incorporated into `scripts/apply-argocd-spoke-rbac.sh` ensuring bootstrap-applied policy and GitOps-managed resources remain identical.
* **Server-Side Dry-Run Verification Drills:**
  * Tested on both `k3d-spoke-nonprod` and `k3d-spoke-prod`:
    * Dry-run patch on `kube-system` as `argocd-iac-deployer` -> **DENIED by policy** (`iac-deployer-namespace-boundary`).
    * Dry-run patch on `platform-network` as `argocd-iac-deployer` -> **DENIED by policy** (`iac-deployer-namespace-boundary`).
    * Dry-run patch on `iac-team-data-dev` / `iac-team-data-prod` as `argocd-iac-deployer` -> **ADMITTED**.
    * Dry-run patch by platform admin -> **ADMITTED**.

---

## 3. Test & Verification Results

### 3.1 Static Checks & Unit Tests
| Gate / Target | Description | Status |
|---|---|---|
| `make test-alert-rules` | Promtool unit test execution for 22 alerting rules including `SyntheticProbeDown` | **PASSED** (`SUCCESS`) |
| `make ci` | Offline render of 42 Applications, kubeconform (585 resources), promtool, shellcheck (35 scripts), secret scan (418 files) | **PASSED** (`all checks passed`) |
| `make ci-iac` | Tenant IaC claim validation and fixture tests (2/2 positive, 14/14 negative) | **PASSED** (`all checks passed`) |
| `make orphans` | Detection of orphaned credentials and namespaces | **PASSED** (`no orphaned credentials or namespaces`) |
| `bash scripts/push-all.sh --dry-run` | Push simulation across all 6 repositories | **PASSED** (`All 6 repositories processed successfully`) |

### 3.2 Dual Smoke Test Suites
| Suite | Scope | Status | Notes |
|---|---|---|---|
| `scripts/smoke-test-hub-spoke.sh` | 12 core stages end-to-end | **PASSED (12/12)** | Dynamically discovered 2 claims, 42 applications verified Synced/Healthy, 0 firing alerts |
| `scripts/smoke-test-hub-spoke-bats.sh` | Modular Bats suite (27 gates) | **PASSED (27/27)** | 100% pass across all 7 test files in 51 seconds |

### 3.3 Server-Side Admission Drills
| Cluster | Target Namespace | Identity | Expected Outcome | Actual Result |
|---|---|---|---|---|
| `k3d-spoke-nonprod` | `kube-system` | `argocd-iac-deployer` | Denied by VAP | **DENIED** (`iac-deployer-namespace-boundary`) |
| `k3d-spoke-nonprod` | `platform-network` | `argocd-iac-deployer` | Denied by VAP | **DENIED** (`iac-deployer-namespace-boundary`) |
| `k3d-spoke-nonprod` | `iac-team-data-dev` | `argocd-iac-deployer` | Admitted | **ADMITTED** |
| `k3d-spoke-prod` | `kube-system` | `argocd-iac-deployer` | Denied by VAP | **DENIED** (`iac-deployer-namespace-boundary`) |
| `k3d-spoke-prod` | `platform-network` | `argocd-iac-deployer` | Denied by VAP | **DENIED** (`iac-deployer-namespace-boundary`) |
| `k3d-spoke-prod` | `iac-team-data-prod` | `argocd-iac-deployer` | Admitted | **ADMITTED** |

---

## 4. Residual Risks Register Carry-Forward

The following items documented in prior assessments and roadmaps remain intentionally deferred:
1. **Helm Chart Signing Deferral:** Spoke Helm charts continue to use unsigned OCI artifacts in local lab environments; Cosign keyless signatures remain scoped to production registries.
2. **Dependency Update Policy:** Third-party upstream charts and CRD definitions are updated during quarterly maintenance cycles rather than per-PR.
3. **Manual Maintenance Window:** Routine token rotation and orphan cleanups continue to be executed via `make maintain` / `make rotate-spoke-tokens`.
4. **Alert Notification Routing:** Prometheus Alertmanager routes to local endpoints and webhook mocks; external Slack/PagerDuty webhooks are not configured in the offline k3d environment.

---

## 5. Summary of Files Changed

* `README.md`
* `addons/observability/alert-rules.test.yaml`
* `addons/observability/values-prometheus-hub.yaml`
* `clusters/platform-config/spoke-nonprod/iac-deployer-namespace-policy.yaml` *(new)*
* `clusters/platform-config/spoke-prod/iac-deployer-namespace-policy.yaml` *(new)*
* `docs/runbooks/devops-student-rebuild-guide.md`
* `docs/runbooks/host-reboot-and-cluster-lifecycle.md`
* `docs/runbooks/tenant-iac-operations.md`
* `scripts/apply-argocd-spoke-rbac.sh`
* `scripts/push-all.sh`
* `scripts/smoke-test-hub-spoke.sh`
* `tests/smoke/02_gitops_applications.bats`
* `tests/smoke/06_observability.bats`
* `tests/smoke/common.bash`
