# Implementation Report 01 — Track 0: Steps 0.1–0.3 (Early Authorization)
## Production Gate Integrity, Chart Immutability & Image Allowlist

* **Remediation Plan:** [`2026-10-03-lab-remediation-plan.md`](2026-10-03-lab-remediation-plan.md) (v1.0)
* **Assessment Reference:** [`../../assessments/2026-10-03-lab-assessment.md`](../../assessments/2026-10-03-lab-assessment.md) (Findings L2-1, L2-2, L4-1, L4-2)
* **Date:** 2026-10-02 / 2026-10-03
* **Author / Implementer:** Antigravity & Platform Owner (Pair Programming)
* **Status:** 🟢 **IMPLEMENTED & READY FOR PEER VALIDATION**

---

## 1. Summary of Changes

This run executes the early authorized steps of Track 0 (Steps 0.1, 0.2, and 0.3) to close the three live bypasses of the production promotion gate:

1. **Step 0.1 (L2-2 / L4-1) — Change Control for Production Inputs:**
   - Owner configured branch protection on `tenant-workloads/main`.
   - Verified GitHub API returns `"protected": true` for all 5 repositories (`gitops-control-plane`, `platform-catalog`, `platform-charts`, `orders-processor`, `tenant-workloads`).
   - Added `.github/CODEOWNERS` to all 5 repositories, designating `@brunobml` as owner on all production-relevant manifests.

2. **Step 0.2 (L2-1) — Golden Chart Immutability Guard:**
   - Updated `platform-charts/.github/workflows/release.yaml`:
     - Pinned Actions by commit SHA (`actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683` # v4.2.2, `azure/setup-helm@b9e51907a09c216f16ebe8536097933489208112` # v4.3.0).
     - Added an automated OCI immutability guard: pulls existing released chart versions from GHCR (`oci://ghcr.io/brunobml/charts/<name>:<version>`), extracts both packages, and runs `diff -r -u`. If content has changed without a version bump in `Chart.yaml`, the job fails with an error. If identical, the push is safely skipped.
     - Cleaned up stale untracked artifacts (`dist/`, `.tgz`) and verified `.gitignore`.

3. **Step 0.3 (L4-2 / O-2) — Native VAP Image Registry Allowlist:**
   - Created native Kubernetes `ValidatingAdmissionPolicy` and `ValidatingAdmissionPolicyBinding` `tenant-image-registry-allowlist` in `platform-catalog/blueprints/tenant-image-registry-allowlist.yaml`.
   - Evaluated natively inside `kube-apiserver` (no out-of-process webhook hop, cannot fail open or time out).
   - Scoped strictly to namespaces with label `platform.lab/image-verification=enabled`.
   - Enforces that all `containers`, `initContainers`, and `ephemeralContainers` must originate from `ghcr.io/brunobml/`.
   - Released `platform-catalog` tag `v1.7.0`.
   - Promoted to `spoke-nonprod` and `spoke-prod` via `scripts/promote-blueprints.sh` and synced through Argo CD `kro-blueprints`.
   - Extended Stage 11 of `scripts/smoke-test-hub-spoke.sh` to include `alpine:latest` negative admission testing.

---

## 2. Commit Manifest Across Repositories

| Repository | Commit | Description |
|---|---|---|
| `gitops-control-plane` | [`e1a196b`](https://github.com/brunobml/gitops-control-plane/commit/e1a196b) | `ci: add .github/CODEOWNERS for control plane definitions` |
| `gitops-control-plane` | [`912bb52`](https://github.com/brunobml/gitops-control-plane/commit/912bb52) | `chore(clusters): promote spoke-prod to platform-catalog v1.7.0 (Step 0.3)` |
| `gitops-control-plane` | [`3bc3f12`](https://github.com/brunobml/gitops-control-plane/commit/3bc3f12) | `test(smoke): add unallowlisted image (alpine:latest) denial assertion to Stage 11 (Step 0.3)` |
| `tenant-workloads` | [`6064fc5`](https://github.com/brunobml/tenant-workloads/commit/6064fc5) | `ci: add .github/CODEOWNERS for prod workload manifests` |
| `platform-charts` | [`825fb40`](https://github.com/brunobml/platform-charts/commit/825fb40) | `ci: add .github/CODEOWNERS for golden charts` |
| `platform-charts` | [`522a634`](https://github.com/brunobml/platform-charts/commit/522a634) | `ci: add Action SHA pins and OCI chart immutability guard (Step 0.2)` |
| `platform-catalog` | [`07e9e62`](https://github.com/brunobml/platform-catalog/commit/07e9e62) | `ci: add .github/CODEOWNERS for blueprints and controllers` |
| `platform-catalog` | [`159663b`](https://github.com/brunobml/platform-catalog/commit/159663b) | `feat(blueprints): add tenant-image-registry-allowlist ValidatingAdmissionPolicy (Step 0.3)` |
| `platform-catalog` | Tag `v1.7.0` | Released `v1.7.0` with `tenant-image-registry-allowlist` |
| `orders-processor` | [`1d0b025`](https://github.com/brunobml/orders-processor/commit/1d0b025) | `ci: add .github/CODEOWNERS for prod deployment values` |

---

## 3. Verification Evidence

### 3.1 GitHub Branch Protection (Step 0.1)

```bash
for repo in gitops-control-plane platform-catalog platform-charts orders-processor tenant-workloads; do
  curl -s "https://api.github.com/repos/brunobml/$repo/branches/main" | jq -c '{repo: "'$repo'", protected: .protected}'
done
```
**Output:**
```json
{"repo":"gitops-control-plane","protected":true}
{"repo":"platform-catalog","protected":true}
{"repo":"platform-charts","protected":true}
{"repo":"orders-processor","protected":true}
{"repo":"tenant-workloads","protected":true}
```

### 3.2 Chart Immutability Guard Verification (Step 0.2)

1. **Unmodified chart:** Compared packaged local `queue-backed-service:1.0.0` against OCI registry package `oci://ghcr.io/brunobml/charts/queue-backed-service:1.0.0`. `diff -r -u` produced 0 diff; push skipped.
2. **Simulated modification without version bump:** Injected dummy comment in template; diff guard immediately triggered:
   `::error::Chart queue-backed-service:1.0.0 exists in GHCR but packaged contents DIFFER!`
   `exit 1`

### 3.3 Image Registry Allowlist Admission Verification (Step 0.3)

1. **Unallowlisted `alpine:latest` (with fully compliant Pod Security spec) in `orders-dev`:**
   ```bash
   cat <<'EOF' | kubectl --context k3d-spoke-nonprod apply --dry-run=server -f -
   apiVersion: v1
   kind: Pod
   metadata:
     name: test-alpine-bypass
     namespace: orders-dev
   spec:
     securityContext:
       runAsNonRoot: true
       runAsUser: 10001
       seccompProfile:
         type: RuntimeDefault
     containers:
       - name: worker
         image: alpine:latest
         securityContext:
           allowPrivilegeEscalation: false
           readOnlyRootFilesystem: true
           capabilities:
             drop: ["ALL"]
   EOF
   ```
   **Result:**
   ```text
   The pods "test-alpine-bypass" is invalid: : ValidatingAdmissionPolicy 'tenant-image-registry-allowlist' with binding 'tenant-image-registry-allowlist' denied request: All container images in tenant namespaces must originate from 'ghcr.io/brunobml/' (O-2 allowlist)
   ```

2. **Unallowlisted `alpine:latest` in `orders-prod`:**
   **Result:**
   ```text
   The pods "test-alpine-prod-bypass" is invalid: : ValidatingAdmissionPolicy 'tenant-image-registry-allowlist' with binding 'tenant-image-registry-allowlist' denied request: All container images in tenant namespaces must originate from 'ghcr.io/brunobml/' (O-2 allowlist)
   ```

3. **Signed `orders-processor` image in `orders-dev`:**
   ```text
   pod/test-signed-admitted created (server dry run)
   ```

4. **Public image in non-tenant namespace (`platform-probes`):**
   ```text
   pod/test-probe-alpine created (server dry run)
   ```
   Unlabelled namespaces remain unaffected.

### 3.4 Smoke Test Suite (12/12 Stages Passed)

Executed `scripts/smoke-test-hub-spoke.sh`:
```text
[11/12] Asserting Supply-Chain Admission (Kyverno image verification)...
  orders-dev: unsigned image & unallowlisted alpine denied, running image admitted (e95bb63320628d8541e984b668474bcc21066e54110d00ab20974132f1287510)
  orders-test: unsigned image & unallowlisted alpine denied, running image admitted (e95bb63320628d8541e984b668474bcc21066e54110d00ab20974132f1287510)
  orders-prod: unsigned image & unallowlisted alpine denied, running image admitted (e95bb63320628d8541e984b668474bcc21066e54110d00ab20974132f1287510)
✔ Image registry allowlist (VAP) and CI signature/SBOM policies (Kyverno) enforced in tenant namespaces

[12/12] Asserting Observability (metrics, logs, probes, alerts, Grafana SSO)...
✔ Hub receives metrics from both spokes
✔ HTTP probes green
✔ Logs shipped from hub, spoke-nonprod and spoke-prod; Loki up
✔ No firing alerts
✔ Grafana SSO entry point reaches the Keycloak login form

============================================================
  All Core Smoke Tests Passed!                             
============================================================
```

---

## 4. Next Step

Ready for independent peer validation: [`2026-10-03-lab-remediation-plan-validation-01.md`](2026-10-03-lab-remediation-plan-validation-01.md).
