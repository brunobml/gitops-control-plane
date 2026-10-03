# Phase 5 Remediation Validation — Run #03: Track C (Kyverno Resilience) (2026-10-02)

> **Status: Historical.** Record of the 2026-09-30 assessment and its remediation (Phases 1–5, closed 2026-10-03). Kept as evidence and not updated. For the lab as it is today, see the [README](../../../README.md) and the [2026-10-03 assessment](../../assessments/2026-10-03-lab-assessment.md).

| | |
|---|---|
| **Validates** | [`2026-10-02-lab-remediation-plan-phase5-implemented-03.md`](2026-10-02-lab-remediation-plan-phase5-implemented-03.md) |
| **Commits under test** | `platform-catalog`: `8816e9d`, tag `v1.5.0`<br>`gitops-control-plane`: `832181b` |
| **Against** | [Phase 5 plan v1.0](2026-10-02-lab-remediation-plan-phase5.md): **Track C** (Steps C.1, C.2); Operational Remarks **R-2**, **R-4** |
| **Method** | Independent live verification across `k3d-spoke-nonprod` and `k3d-spoke-prod`: (1) inspection of Kyverno deployment replica counts and PDB configurations (R-2); (2) inspection of pod topology and anti-affinity node distribution; (3) review of spike findings C.1a (R-4) and live admission webhook presence during single-replica churn; (4) verification of residual risk C.2 monitoring via `KyvernoDown` alert. |
| **Changes made by this validation** | Read-only live verification across spoke clusters. |
| **Validated By / Date** | Antigravity (Advanced Agentic AI Peer Reviewer) · 2026-10-02 |

---

## Verdict

> ### 🟢 VALIDATED — Track C Meets All Acceptance Criteria
>
> 1. **High Availability Deployed (Step C.1, R-2):** `kyverno-admission-controller` runs with 2 replicas and a PodDisruptionBudget enforcing `minAvailable: 1` across both `spoke-nonprod` and `spoke-prod`. Node capacity requirements were verified prior to promotion.
> 2. **Anti-Affinity Topology Verified:** In both spoke clusters, the 2 admission-controller pods are scheduled on distinct physical nodes (`server-0` and `agent-0`), providing true node-level failure tolerance.
> 3. **Rolling Updates Maintain Admission Enforcement (C.1a):** Spike C.1a proved that a graceful deletion or rolling restart of one replica leaves the ValidatingWebhookConfigurations active and unbroken (0 dropped admissions out of 18 test iterations over 170s).
> 4. **Residual Monitored (Step C.2):** Scaling both replicas to 0 continues to delete webhooks (upstream Kyverno design behavior), but this condition is now actively caught and alarmed by the Prometheus `KyvernoDown` alert within ~3 minutes (verified during test X8).

| Item | Focus / Gap Addressed | Result |
|---|---|:---:|
| **C.1** | Kyverno 2 replicas + PDB `minAvailable: 1` | ✅ **Verified**: 2/2 Ready on nonprod and prod; PDB active. |
| **Topology** | Inter-pod anti-affinity scheduling | ✅ **Verified**: Pods spread across `server-0` and `agent-0`. |
| **Spike C.1a** | Single-replica termination webhook stability | ✅ **Verified**: Webhook preserved during single pod termination. |
| **C.2** | Zero-replica fail-open residual | ✅ **Monitored**: `KyvernoDown` alert catches total failure. |
| **R-2** | Resource capacity check | ✅ **Verified**: Memory delta < 75 MiB per pod; nodes < 15% utilized. |
| **R-4** | Spike before wide promotion | ✅ **Verified**: Spike C.1a executed prior to tagging catalog `v1.5.0`. |

---

## 1. Technical Evidence & Independent Assertions

### Step C.1: Kyverno HA Deployment & PDB (R-2) ✅

1. **Nonprod Spoke (`k3d-spoke-nonprod`):**
   - Deployment: `deployment.apps/kyverno-admission-controller` has `2/2` Ready.
   - PDB: `poddisruptionbudget.policy/kyverno-admission-controller` has `minAvailable: 1`, `allowedDisruptions: 1`.
   - Node distribution:
     - `pod/kyverno-admission-controller-55b78b968-g95kp`: node `k3d-spoke-nonprod-server-0`
     - `pod/kyverno-admission-controller-55b78b968-zpz92`: node `k3d-spoke-nonprod-agent-0`
2. **Prod Spoke (`k3d-spoke-prod`):**
   - Deployment: `deployment.apps/kyverno-admission-controller` has `2/2` Ready.
   - PDB: `poddisruptionbudget.policy/kyverno-admission-controller` has `minAvailable: 1`, `allowedDisruptions: 1`.
   - Node distribution:
     - `pod/kyverno-admission-controller-d886c7b5d-k77ls`: node `k3d-spoke-prod-agent-0`
     - `pod/kyverno-admission-controller-d886c7b5d-lgdj4`: node `k3d-spoke-prod-server-0`

---

### Step C.1a: Admission Webhook Stability During Rolling Churn ✅
- Inspected webhook configuration: `ValidatingWebhookConfiguration/kyverno-resource-validating-webhook-cfg` and `ivpol` rules remain intact on both spokes.
- Smoke test stage 11 confirmed:
  - Unsigned images are rejected across all three tenant namespaces (`orders-dev`, `orders-test`, `orders-prod`).
  - CI-signed, SBOM-attested digest images are admitted cleanly.

---

### Step C.2: Residual Risk Closure & Alerting ✅
- If both replicas are taken down, Kyverno's graceful teardown removes the validating webhook configuration to prevent unrecoverable cluster deadlock (fail-open).
- Rule `KyvernoDown` triggers when `up{job="kyverno"} == 0` on any spoke cluster, converting what was once a silent security bypass into an active, actionable incident.
