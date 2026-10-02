# Phase 4 Remediation Validation — Run #03: Track B, Supply-Chain Trust (2026-10-02)

| | |
|---|---|
| **Validates** | [`2026-10-02-lab-remediation-plan-phase4-implemented-03.md`](2026-10-02-lab-remediation-plan-phase4-implemented-03.md) |
| **Commits under test** | `orders-processor`: `5d70f42` (B.1), tag **`v1.5.0`**, `b9b00c8` (deploy)<br>`platform-catalog`: `362fbee`, `6f93215`, `2ed33a8` (B.3), `adad350`, `b7289d7`, `5c8f31b`, `ebef5e1` (B.4), tag **`v1.4.0`**<br>`gitops-control-plane`: `74c7ba4`, `b33ccfc`, `b87de82`, `5f64945`, `f2db125` |
| **Against** | [Phase 4 plan v1.0](2026-10-02-lab-remediation-plan-phase4.md): **Track B: Supply-Chain Trust** (Steps B.1–B.4, finding **L4-8**, finding **0.3 / PV3-11**, Reviewer Remark **R-2**) |
| **Method** | Independent live audit & verification: (1) code audit of `.github/workflows/ci.yaml` in `orders-processor` for commit-SHA action pinning, Trivy gates, and keyless signing; (2) host verification of container digest, cosign signature, and SPDX SBOM attestation via `cosign v3.1.3`; (3) negative tests for foreign identities and unsigned image digests; (4) cluster audit of Kyverno 1.19.1 admission controller deployments on both spokes; (5) live admission testing of `ImageValidatingPolicy/tenant-images-signed` on `orders-dev`, `orders-test`, and `orders-prod` using server-side dry runs; (6) live execution of the full 11-stage smoke test suite; (7) live execution of `scripts/post-bootstrap.sh` (idempotency verification); (8) live execution of `scripts/audit-impersonation.sh` across all 22 applications. |
| **Changes made by this validation** | Deliberate live tests: executed `cosign verify`, `cosign verify-attestation`, negative identity verification, server-side admission probes (unsigned vs. signed), `scripts/smoke-test-hub-spoke.sh` (11/11 stages passed), and `scripts/post-bootstrap.sh`. No code commits. |
| **Validated By / Date** | Antigravity (Advanced Agentic AI Peer Reviewer) · 2026-10-01 |

---

## Verdict

> ### 🟢 VALIDATED — Track B (Supply-Chain Trust) is Complete, Hardened and Production-Grade
>
> All authorized steps of Track B (Steps B.1 through B.4) and Step 0.3 / PV3-11 tag immutability have been implemented and independently validated.
>
> 1. **CI Pipeline Hardened (L4-8 Closed):** Every GitHub Action in `orders-processor` is pinned to an immutable 40-character commit SHA. Trivy scanning actively gates the build against fixable `CRITICAL` vulnerabilities prior to registry push. Base image is pinned by digest.
> 2. **Keyless Signing & SBOM Provenance Active:** `orders-processor:v1.5.0` is signed keyless with Cosign using GitHub Actions OIDC identity (`.../ci.yaml@refs/tags/v1.5.0`) and carries an attested SPDX-2.3 SBOM with 74 packages recorded in the Sigstore transparency log.
> 3. **Spoke Admission Policy Enforcing (Deny):** Kyverno 1.19.1 enforces modern CEL `ImageValidatingPolicy` (`tenant-images-signed`) on both nonprod and prod spokes. Unsigned images (`v1.4.0`) are unconditionally denied, while signed and attested images (`v1.5.0`) are admitted with `mutateDigest: true`.
> 4. **Strict Namespace & Controller Scoping (O-3):** Webhook interception is scoped strictly to namespaces carrying `platform.lab/image-verification: enabled`. System and controller namespaces (`kube-system`, `kyverno`, `kro`, `ack-system`) are completely excluded from the webhook, preventing admission deadlocks.
> 5. **Staged Promotion Followed (R-2):** Promoted to prod via catalog tag `v1.4.0` only after `orders-prod` was successfully rolled to the signed `v1.5.0` digest. Zero production disruption occurred.

| Item | Focus / Gap Addressed | Result |
|---|---|:-:|
| **B.1** | CI hardening & supply-chain provenance | ✅ **Closed**: 9 Actions pinned by commit SHA; Trivy v0.36.0/v0.70.0 gate; least-privilege permissions; base image pinned by digest. |
| **B.2** | Signed release `v1.5.0` | ✅ **Closed**: Digest `sha256:e95bb633...`; keyless signature and SPDX-2.3 SBOM (74 packages) verified; rolled to dev, test, and prod. |
| **0.3** | PV3-11 Tag immutability | ✅ **Closed**: Git tag `v1.5.0` produces only the semver tag; branch builds produce `sha-*` only; zero tag overwrite. |
| **B.3** | Spoke Kyverno controllers | ✅ **Closed**: Admission-only controller running on nonprod and prod; background/cleanup/report controllers off; 0 restarts; digests pinned. |
| **B.4** | Image verification admission policy | ✅ **Closed**: Modern CEL `ImageValidatingPolicy` active with `validationActions: [Deny]` and `failurePolicy: Fail`; unsigned rejected, signed admitted. |
| **Regression** | Control plane integrity | ✅ **22/22 Apps Synced/Healthy**; impersonation audit PASS; smoke test 11/11 passed; `post-bootstrap` idempotent (exit 0). |

---

## 1. Step-by-Step Validation Evidence

### 1. CI Hardening & Pipeline Verification (B.1) ✅

1. **Commit-SHA Pinning Audit:**
   - Inspected [`orders-processor/.github/workflows/ci.yaml`](file:///home/bleite/repos/orders-processor/.github/workflows/ci.yaml):
     - `actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1` (# v7.0.1)
     - `actions/setup-python@5fda3b95a4ea91299a34e894583c3862153e4b97` (# v7.0.0)
     - `docker/setup-buildx-action@f87e5991a6d7451dcb8d9637bfbc97413f497069` (# v4.4.1)
     - `docker/build-push-action@c3c9e263c25d99ce0380d002d59b67737d91b0dc` (# v7.4.0)
     - `aquasecurity/trivy-action@ed142fd0673e97e23eac54620cfb913e5ce36c25` (# v0.36.0, trivy binary v0.70.0)
     - `docker/login-action@dbcb813823bdd20940b903addbd779551569679f` (# v4.6.0)
     - `docker/metadata-action@dc802804100637a589fabce1cb79ff13a1411302` (# v6.2.0)
     - `sigstore/cosign-installer@6f9f17788090df1f26f669e9d70d6ae9567deba6` (# v4.1.2)
     - `anchore/sbom-action@3ad7283483fc7af8ff2b4ea19663c2d5ca935e26` (# v0.24.2)
   - All 9 actions are pinned to 40-hex commit hashes, neutralizing tag modification attacks (e.g. CVE-2026-33634).
2. **Pre-Push Vulnerability Gate:**
   - Trivy scan runs on a local untagged build before any registry push.
   - Severity gate fails the build (`exit-code: 1`, `ignore-unfixed: true`) on any fixable `CRITICAL` vulnerability.
3. **Least-Privilege Token Permissions:**
   - Top-level workflow permissions default to `contents: read`.
   - `build-and-push` job explicitly restricts permissions to `contents: read`, `packages: write`, and `id-token: write` (for Sigstore Fulcio keyless OIDC token issuance).
4. **Base Image Pinning:**
   - Inspected [`orders-processor/Dockerfile`](file:///home/bleite/repos/orders-processor/Dockerfile):
     `FROM python:3.11-alpine@sha256:9a725b14f2ae4e1b92ae4c7a8f575c7bf0f451276b5d38c9ec20bb005d0063a8`.

---

### 2. Host Verification of Release v1.5.0 (B.2 & 0.3 / PV3-11) ✅

Executed live host verification with `cosign v3.1.3`:
```bash
$ cosign verify \
    --certificate-identity-regexp="^https://github\.com/brunobml/orders-processor/\.github/workflows/ci\.yaml@refs/tags/v1\.5\.0$" \
    --certificate-oidc-issuer="https://token.actions.githubusercontent.com" \
    ghcr.io/brunobml/orders-processor:v1.5.0@sha256:e95bb63320628d8541e984b668474bcc21066e54110d00ab20974132f1287510
```
- **Result:**
  - Cosign claims validated successfully.
  - Certificate SAN verified: `https://github.com/brunobml/orders-processor/.github/workflows/ci.yaml@refs/tags/v1.5.0`.
  - Claims in Sigstore Rekor transparency log verified.

1. **SPDX SBOM Attestation Verification:**
   - Executed:
     ```bash
     $ cosign verify-attestation --type spdxjson ... | jq -r .payload | base64 -d | jq .predicate
     ```
   - **Result:**
     - Predicate Type: `https://spdx.dev/Document`
     - SPDX Version: `SPDX-2.3`
     - Document Name: `ghcr.io/brunobml/orders-processor`
     - Packages Documented: **74 packages**
2. **Negative Tests:**
   - Probing with foreign identity (`^https://github.com/attacker/.*$`) $\rightarrow$ Rejected: `no matching CertificateIdentity found`.
   - Probing unsigned `v1.4.0` digest $\rightarrow$ Rejected: `no signatures found`.
3. **Tag Immutability (0.3 / PV3-11):**
   - Confirmed release tag build published `v1.5.0` only without overwriting the branch commit tag `sha-5d70f42`.

---

### 3. Spoke Kyverno Controller Deployment (B.3) ✅

1. **Right-Sized Resource Footprint:**
   - `addon-kyverno-spoke-nonprod` and `addon-kyverno-spoke-prod` report `Synced / Healthy`.
   - On both spokes, only `kyverno-admission-controller` is running (`1/1 Running`, 0 restarts).
   - Background, cleanup, and reporting controllers are disabled via Helm values, preserving host memory.
2. **CRD Stability (Finding D-9):**
   - Subchart values in [`platform-catalog/controllers/kyverno/values-kyverno.yaml`](file:///home/bleite/repos/platform-catalog/controllers/kyverno/values-kyverno.yaml) annotate and label `kyverno-api` CRDs, eliminating Server-Side Apply empty map drift.

---

### 4. Admission Policy Enforcement & Staged Promotion (B.4) ✅

1. **Policy Architecture:**
   - Policy kind: `policies.kyverno.io/v1 ImageValidatingPolicy` named `tenant-images-signed`.
   - `failurePolicy: Fail` (O-3).
   - `validationActions: [Deny]` on both `k3d-spoke-nonprod` and `k3d-spoke-prod`.
   - Timeout configured to 30s (`webhookConfiguration.timeoutSeconds: 30`, closing D-8).
   - Validates both keyless signature and SPDX SBOM attestation against the workflow identity.
2. **Namespace Scoping & Control Plane Isolation:**
   - Webhook `matchConstraints.namespaceSelector.matchLabels` requires `platform.lab/image-verification: enabled`.
   - Tested pod admission in `default` namespace (lacking label) $\rightarrow$ Instantly admitted without webhook intervention.
   - Platform controllers (`kube-system`, `kyverno`, `kro`, `ack-system`) are completely unaffected.
3. **Live Server-Side Dry-Run Admission Probes:**
   - **Test 1: Unsigned `v1.4.0` in `orders-dev`:**
     ```text
     Error from server: admission webhook "ivpol.validate.kyverno.svc-fail-finegrained-tenant-images-signed" denied the request: 
     Policy tenant-images-signed failed: orders-processor images must be signed by the orders-processor CI workflow (cosign keyless)
     ```
     **Result:** Unconditionally **denied**.
   - **Test 2: Signed `v1.5.0` in `orders-dev`:**
     ```text
     pod/test-signed-probe serverside-applied (server dry run)
     ```
     **Result:** Successfully **admitted**.
   - **Test 3: Unsigned `v1.4.0` in `orders-prod`:**
     **Result:** Unconditionally **denied**.
4. **Staged Promotion Order (R-2):**
   - Verified that `orders-prod` was rolled to `v1.5.0` (`orders-processor` commit `b9b00c8` via `valuesRevision` in [`tenant-workloads-prod.yaml`](file:///home/bleite/repos/gitops-control-plane/applicationsets/tenant-workloads-prod.yaml)) **before** promoting the catalog gate to `v1.4.0` (`platform-catalog` tag `v1.4.0` in [`clusters/blueprint-revisions.env`](file:///home/bleite/repos/gitops-control-plane/clusters/blueprint-revisions.env)).
   - Both `orders-prod-worker` pods restarted cleanly under Enforce mode (`2/2 Running`).

---

### 5. Regression & Operational Health ✅

1. **Argo CD Applications:**
   - All **22/22** applications report `Synced / Healthy` (including `addon-kyverno-spoke-nonprod` and `addon-kyverno-spoke-prod`).
2. **Impersonation Audit:**
   - Executed [`scripts/audit-impersonation.sh`](file:///home/bleite/repos/gitops-control-plane/scripts/audit-impersonation.sh): **`RESULT: PASS`** across all 22 applications. Kyverno applications correctly use `platform-addons -> kube-system:argocd-platform-deployer`.
3. **Full Smoke Test Suite (All 11 Stages):**
   - Executed [`scripts/smoke-test-hub-spoke.sh`](file:///home/bleite/repos/gitops-control-plane/scripts/smoke-test-hub-spoke.sh):
     - **All 11/11 stages passed exit code 0.**
     - Stage 9 E2E order flow: dev 0s, test 0s, prod 0s.
     - Stage 10 SSO: all endpoints reach Keycloak login form; break-glass login passed.
     - Stage 11 Supply-Chain Admission: on each tenant namespace, unsigned `v1.4.0` is denied and running `v1.5.0` is admitted.
4. **Post-Bootstrap Idempotency:**
   - Executed [`scripts/post-bootstrap.sh`](file:///home/bleite/repos/gitops-control-plane/scripts/post-bootstrap.sh):
     - Completed in 28s with **0 unnecessary pod restarts**.

---

## 2. Conclusion

Track B implementation and validation are **100% complete**. 

Finding **L4-8** is closed with cryptographically verifiable software supply-chain controls. The control plane enforces image signing and SBOM provenance on all tenant workloads while insulating infrastructure controllers from webhook dependencies.
