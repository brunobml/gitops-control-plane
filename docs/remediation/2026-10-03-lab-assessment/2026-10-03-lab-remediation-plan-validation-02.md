# Validation Report 02 — Track 0: Steps 0.1–0.3 Closure (2026-10-03)

> **Status: Current.** Active remediation record for the 2026-10-03 assessment.

| | |
|---|---|
| **Validates** | [`2026-10-03-lab-remediation-plan-implemented-02.md`](2026-10-03-lab-remediation-plan-implemented-02.md) |
| **Against** | [`2026-10-03-lab-remediation-plan.md`](2026-10-03-lab-remediation-plan.md) (v1.0), [`validation-01.md`](2026-10-03-lab-remediation-plan-validation-01.md) (Findings V-1, V-2, V-3, Y3) |
| **Commits under test** | `platform-charts` `d36a84e` (fix), `c275245` (negative test), `30881bf` (revert); `platform-catalog` `618467b`, tag `v1.7.1`; `gitops-control-plane` `4f1e01f` (prod promotion to v1.7.1) |
| **Executed by** | Claude (Opus 5.5). **Validated by** Antigravity (Advanced Agentic AI Peer Reviewer), independent of the execution |
| **Method** | Public GitHub API verification of workflow runs and check-run annotations; local syntax validation (`bash -n`); reproduction of fail-closed behavior on simulated registry error; OCI manifest verification on GHCR; independent server-side dry runs of ephemeral containers via raw Kubernetes API on both `spoke-nonprod` and `spoke-prod`; full regression suite (smoke test 12/12, impersonation audit, Prometheus alert rules, Application sync/health) |
| **Changes made by this validation** | None (read-only verification & dry runs; no live cluster objects or configs modified) |
| **Date** | 2026-10-03 / 2026-10-02 |

---

## Verdict

> ### 🟢 FULLY VALIDATED (PASS) — Track 0 Early-Authorized Steps (0.1–0.3) Closed
>
> All three findings from Validation 01 (**V-1**, **V-2**, **V-3**) and the required real-run proof (**Y3**) have been independently verified and proven:
>
> 1. **0.1 Change control:** ✅ Validated in Validation 01 (`main` protected on all 5 repos; `.github/CODEOWNERS` active and error-free).
> 2. **0.2 Chart immutability (V-1, V-2, Y3):** ✅ **PASS.** The release workflow parses cleanly (`bash -n` passes). The extraction logic uses Helm's normalized `helm show chart` output without brittle quote stripping. The guard fails closed on registry errors (only `: not found` triggers a push). Real GitHub Actions runs confirm both branches: run `37097248060` failed with exit code 1 and exact diff annotations when a template was modified without a version bump; runs `37097203382` and `37097279544` succeeded on the skip path. GHCR `1.0.0` digest was preserved throughout.
> 3. **0.3 Registry allowlist (V-3):** ✅ **PASS.** The `ValidatingAdmissionPolicy` and binding now match `resources: ["pods", "pods/ephemeralcontainers"]` for operations `CREATE` and `UPDATE`. Server-side dry runs on both `spoke-nonprod` and `spoke-prod` confirm that ephemeral containers with unallowlisted images (e.g. `alpine:latest`) are **denied by the VAP**, while allowlisted images are admitted.
> 4. **Regression:** ✅ 32/32 Applications Synced/Healthy, smoke test 12/12 PASS (including Stage 11 VAP assertions), impersonation audit 100% PASS, alert rule tests SUCCESS, 0 firing alerts.
>
> **Track 0 Steps 0.1, 0.2, and 0.3 are officially CLOSED and validated.** Execution may proceed to Steps 0.4–0.7.

| Step | Focus | Result | Status |
|---|---|:---:|:---:|
| **0.1** | Branch protection & CODEOWNERS (L2-2, L4-1) | ✅ PASS | Closed |
| **0.2** | Immutable golden chart versions & SHA-pinned Actions (L2-1, V-1, V-2, Y3) | ✅ PASS | Closed |
| **0.3** | Tenant image allowlist including ephemeral containers (L4-2, O-2, V-3) | ✅ PASS | Closed |

---

## 1. Independent Verification Evidence

### 1.1 Step 0.2: Release Workflow Syntax & Fail-Closed Guard (V-1, V-2)

1. **Syntax Check:**
   Extracted all `run:` blocks from `platform-charts/.github/workflows/release.yaml` and verified with `bash -n`. All steps passed with 0 errors.

2. **Extraction Normalization:**
   The logic uses:
   ```bash
   chart_name=$(helm show chart "$chart" | awk '/^name:/ {print $2; exit}')
   chart_version=$(helm show chart "$chart" | awk '/^version:/ {print $2; exit}')
   ```
   Anchoring at column 0 prevents matching nested keys (e.g., `maintainers[].name`), and reading from Helm's normalized output avoids quote stripping issues.

3. **Fail-Closed Behavior Reproduction:**
   Simulated an authentication failure / unreachable OCI registry via bash. `helm pull` returned exit code 1 with denied access. The guard correctly caught the error, verified that it did NOT contain `: not found`, and aborted execution:
   ```text
   PASS: pull error caught and failed closed (rc=1): Error: failed to perform "FetchReference" on source: ... response status code 403: denied
   ```

### 1.2 Step 0.2: Real GitHub Actions Runs & In-Flight Immutability (Y3)

Queried GitHub API for the three workflow runs on `platform-charts`:

| Run ID | Head SHA | Description | Status | Conclusion |
|---|---|---|:---:|:---:|
| `37097203382` | `d36a84e` | Fix release guard parsing & fail-closed logic | completed | **success** (skip path) |
| `37097248060` | `c275245` | Negative test: template comment without version bump | completed | **failure** (diff guard) |
| `37097279544` | `30881bf` | Revert negative test commit | completed | **success** (skip path) |

Inspected the check-run annotations for the negative test run (`37097248060`):
```json
[
  {
    "annotation_level": "failure",
    "message": "Chart queue-backed-service:1.0.0 exists in GHCR but packaged contents DIFFER!"
  },
  {
    "annotation_level": "failure",
    "message": "Re-releasing existing chart versions with modified templates is prohibited (L2-1)."
  },
  {
    "annotation_level": "failure",
    "message": "Bump 'version' in charts/queue-backed-service/Chart.yaml to release changes."
  },
  {
    "annotation_level": "failure",
    "message": "Process completed with exit code 1."
  }
]
```
Verified that the GHCR manifest digest for `queue-backed-service:1.0.0` remained identical:
`sha256:4668c360b2fdee088e7db4ea572cec19217a2d0b0b6b3af9f69831d0a22825bd`.

### 1.3 Step 0.3: Ephemeral Containers Allowlist Admission (V-3)

1. **Policy Rules:**
   Verified live `ValidatingAdmissionPolicy` definition on both `spoke-nonprod` and `spoke-prod`:
   ```bash
   kubectl --context <ctx> get validatingadmissionpolicy tenant-image-registry-allowlist -o jsonpath='{.spec.matchConstraints.resourceRules[*].resources}'
   ```
   **Output:** `["pods","pods/ephemeralcontainers"]` on both clusters.

2. **Raw Subresource Dry-Run (`PUT /api/v1/namespaces/<ns>/pods/<pod>/ephemeralcontainers?dryRun=All`):**

   - **Non-prod (`orders-dev`) with `alpine:latest`:**
     ```text
     The pods "orders-dev-worker-864d57fd69-wbtww" is invalid: : ValidatingAdmissionPolicy 'tenant-image-registry-allowlist' with binding 'tenant-image-registry-allowlist' denied request: All ephemeralContainer images in tenant namespaces must originate from 'ghcr.io/brunobml/' (O-2 allowlist)
     ```
     Result: ❌ **DENIED** (bypass closed).

   - **Non-prod (`orders-dev`) with `ghcr.io/brunobml/orders-processor:v1.5.0`:**
     ```json
     {
       "name": "orders-dev-worker-864d57fd69-wbtww",
       "ephemeralContainers": [
         "ghcr.io/brunobml/orders-processor:v1.5.0"
       ]
     }
     ```
     Result: ✅ **ADMITTED**.

   - **Prod (`orders-prod`) with `alpine:latest`:**
     ```text
     The pods "orders-prod-worker-c48446485-29wp9" is invalid: : ValidatingAdmissionPolicy 'tenant-image-registry-allowlist' with binding 'tenant-image-registry-allowlist' denied request: All ephemeralContainer images in tenant namespaces must originate from 'ghcr.io/brunobml/' (O-2 allowlist)
     ```
     Result: ❌ **DENIED**.

   - **Prod (`orders-prod`) with `ghcr.io/brunobml/orders-processor:v1.5.0`:**
     Result: ✅ **ADMITTED**.

   - **Live Cluster Integrity:**
     Verified that zero ephemeral containers were added to running pods on either spoke.

---

## 2. Full Regression Suite Results

| Test Suite | Command | Expected | Actual |
|---|---|---|---|
| **Argo CD Application Health** | `kubectl get apps -n argocd` | 32/32 Synced & Healthy | 32/32 Synced & Healthy ✅ |
| **Impersonation Audit** | `./scripts/audit-impersonation.sh` | PASS | PASS ✅ |
| **Prometheus Alert Rules** | `make test-alert-rules` | SUCCESS | SUCCESS ✅ |
| **Active Prometheus Alerts** | Query `http://localhost:9090/api/v1/alerts` | 0 firing alerts | 0 firing alerts ✅ |
| **Multi-Cluster Smoke Test** | `./scripts/smoke-test-hub-spoke.sh` | 12/12 stages PASS | 12/12 stages PASS ✅ |

---

## 3. Status of Track 0 Steps

| Step | Plan Description | Implementation | Validation | Status |
|---|---|---|---|:---:|
| **0.1** | Change control for prod inputs | Report 01 | Validation 01 & 02 | 🟢 **PASS** |
| **0.2** | Immutable golden chart versions | Report 01 & 02 | Validation 02 | 🟢 **PASS** |
| **0.3** | Registry allowlist for tenant namespaces | Report 01 & 02 | Validation 02 | 🟢 **PASS** |
| **0.4** | README Quick Start and "What you get" | — | — | ⏳ Pending |
| **0.5** | Correct the drills playbook | — | — | ⏳ Pending |
| **0.6** | Digest-pin remaining platform images | — | — | ⏳ Pending |
| **0.7** | Repo hygiene and document status | — | — | ⏳ Pending |

**Track 0 Steps 0.1–0.3 are officially validated and completed.**
