# Phase 4 Implementation Report — Run #03: Track B, Supply-Chain Trust (2026-10-02)

> **Status: Historical.** Record of the 2026-09-30 assessment and its remediation (Phases 1–5, closed 2026-10-03). Kept as evidence and not updated. For the lab as it is today, see the [README](../../../README.md) and the [2026-10-03 assessment](../../assessments/2026-10-03-lab-assessment.md).

| | |
|---|---|
| **Plan** | [`2026-10-02-lab-remediation-plan-phase4.md`](2026-10-02-lab-remediation-plan-phase4.md) v1.0 (GREEN LIGHT; remark **R-2** governs this track) |
| **Preceded by** | [Implemented-02](2026-10-02-lab-remediation-plan-phase4-implemented-02.md), validated 🟢 in [Validation-02](2026-10-02-lab-remediation-plan-phase4-validation-02.md) |
| **Scope executed** | **B.1 – B.4** (finding **L4-8**), plus **0.3 / PV3-11** (tag-side verification) |
| **Commits** | `orders-processor`: `5d70f42` (B.1), tag **`v1.5.0`**, `b9b00c8` (deploy). `platform-catalog`: `362fbee`, `6f93215`, `2ed33a8` (B.3), `adad350`, `b7289d7`, `5c8f31b`, `ebef5e1` (B.4), tag **`v1.4.0`**. `gitops-control-plane`: `74c7ba4`, `b33ccfc`, `b87de82`, `5f64945`, `f2db125` |

## 1. Outcome

| Step | Result |
|---|:-:|
| **B.1** CI: every action pinned by commit SHA; least-privilege permissions; Trivy gate before push; SPDX SBOM attestation; keyless cosign signing; base image pinned by digest | ✅ |
| **B.2** Release **v1.5.0** = first signed + attested image; rolled to dev/test, then prod via `valuesRevision` | ✅ |
| **0.3 / PV3-11** Tag build publishes `v1.5.0` only; `sha-5d70f42` keeps the branch build's digest | ✅ closed |
| **B.3** Kyverno 1.19.1 on both spokes (admission controller only, digests pinned, opt-in namespace scope), nonprod first | ✅ |
| **B.4** Policy `tenant-images-signed` (signature **and** SBOM attestation from the CI identity), Audit → Deny on nonprod → prod via catalog **v1.4.0** (R-2 order kept) | ✅ |
| Regression | **22/22** Applications Synced/Healthy; R-1 impersonation audit PASS; smoke **11/11**; `post-bootstrap` idempotent |

## 2. Evidence

### B.1 — CI (`orders-processor/.github/workflows/ci.yaml`)
| Check | Result |
|---|---|
| Action pinning (W9) | 9 actions, all `uses: …@<40-hex SHA> # vX.Y.Z`; resolved from the upstream release tags with `git ls-remote` (peeled commits) |
| Trivy | `trivy-action` **v0.36.0** (`ed142fd…`), Trivy binary pinned to **v0.70.0**. Context: in March 2026, 76 of 77 `trivy-action` tags were force-pushed to malicious commits (CVE-2026-33634); safe releases are 0.35.0+. v0.36.0 itself pins `setup-trivy` by hash. SHA pinning is exactly the control that defeats moved tags. |
| Gate | fixable **CRITICAL** fails the build (`ignore-unfixed`); CRITICAL+HIGH table printed (informational). Image is scanned **before** push |
| Permissions | workflow default `contents: read`; job adds `packages: write` and `id-token: write` only |
| Branch run `36956289073` / tag run `36957698799` | all steps success (scan, gate, push, SBOM, sign, attest) |

### B.2 — Signed release (host verification, cosign v3.1.3)
| Check | Result |
|---|---|
| `v1.5.0` digest | `sha256:e95bb63320628d8541e984b668474bcc21066e54110d00ab20974132f1287510` |
| Signature (W10) | `cosign verify` with exact identity **`…/ci.yaml@refs/tags/v1.5.0`**, issuer `token.actions.githubusercontent.com` → verified |
| SBOM attestation (W10) | `cosign verify-attestation --type spdxjson` → `https://spdx.dev/Document`, **74 packages** |
| Negative | wrong identity → `no matching CertificateIdentity`; v1.4.0 → `no signatures found` |
| Storage format | cosign v3 writes **Sigstore bundles as OCI 1.1 referrers** (no legacy `.sig` tag) — Kyverno compatibility proven before the release (B.3 spike) |
| Rollout | dev/test from `main` (`b9b00c8`), smoke green, then prod `valuesRevision` → `b9b00c8` (`b33ccfc`); prod 2/2 Running v1.5.0 |

### B.3 — Kyverno
| Check | Result |
|---|---|
| Install | `addons-spoke-kyverno` ApplicationSet (clusters labelled `kyverno=enabled`), values from `platform-catalog/controllers/kyverno` at the cluster's `blueprints-revision`; nonprod first, prod with catalog v1.4.0 |
| Footprint | 1 admission-controller pod per spoke; background/cleanup/reports controllers off; all 5 images (incl. hook/test) digest-pinned |
| Scope | webhook `namespaceSelector` = `platform.lab/image-verification=enabled` **AND** not `kube-system`/`kyverno`; label set on `orders-dev`, `orders-test`, `orders-prod` by the tenant ApplicationSets |
| Spike (before release) | throwaway policy: signed digest admitted, unsigned denied, unrelated image admitted; **wrong identity → denied** (identity really checked). Removed afterwards |

### B.4 — Admission (W11, W12, W13)
| # | Test | Result |
|---|---|---|
| W11 | nonprod Deny: unsigned v1.4.0 / signed v1.5.0 by tag / signed `sha-5d70f42` / out-of-scope busybox | **denied** / admitted, rewritten to `@sha256:e95bb633…` (`mutateDigest`) / admitted → `@sha256:3a067a1a…` / admitted |
| Audit stage | Audit on nonprod: unsigned admitted (recorded only); real dev/test workloads restarted and passed | ✅ |
| W12 | prod: Kyverno + policy arrived together (54 s, no failed sync thanks to `SkipDryRunOnMissingResource`); unsigned denied, signed admitted; `orders-prod` rollout restart under Deny | 2/2 Running |
| W13 | Kyverno **unreachable with webhooks present** (Service pointed at no endpoints, Argo CD controller paused): tenant pod | **denied** (fail closed, O-3) |
| W13 | same condition: pods in `kube-system`, `ack-system`, `kro` | admitted (out of scope) |
| Latency | uncached verification 8.2 s; warm 4.1 s (incl. kubectl) | within 30 s timeout |

## 3. Deviations, Defects and Notes

| ID | Item |
|---|---|
| D-8 | **Webhook timeout.** During the Audit stage one `orders-test` pod creation failed with `context deadline exceeded` at the default 10 s timeout (uncached verification fetches signature + attestation from GHCR/Sigstore); the ReplicaSet retried successfully. With `failurePolicy: Fail` this would surface as delayed pods. Fixed: policy `webhookConfiguration.timeoutSeconds: 30` (`b7289d7`); measured cold 8.2 s. |
| D-9 | **Permanent OutOfSync on Kyverno CRDs.** The `kyverno-api` subchart renders `labels: {}` and `annotations: {}` on 11 `policies.kyverno.io` CRDs; server-side apply never stores empty maps. Fixed with one label and one annotation via subchart values (`6f93215`, `2ed33a8`) instead of `ignoreDifferences`. |
| D-10 | **W13 residual — graceful stop fails open.** When Kyverno is scaled to 0 (graceful shutdown) it **deletes its own webhook configurations**, so tenant pods are admitted unverified until it returns. A crash / OOM / network loss leaves the webhooks and fails **closed** (tested). Accepted for the lab; mitigations if needed: >1 replica, or a PDB. Recorded as residual risk. |
| D-11 | **Two invalid W13 attempts (author), discarded.** (1) The ApplicationSet stripped a `skip-reconcile` annotation and self-heal restored Kyverno before the checks; (2) the second run tested the graceful-stop case (D-10). The valid run paused the hub's application controller (manual-sync `argo-cd` app, so nothing restores it) and made Kyverno unreachable while keeping its webhooks. |
| D-12 | Pods only (autogen off): kro owns the Deployments; a rejected Deployment would degrade the kro instance, while a rejected Pod surfaces as a ReplicaSet `FailedCreate` event. |
| D-13 | Kyverno admission logs `failed to create report … client rate limiter` (reports controller is off by design). Cosmetic. |
| D-14 | The PSS `restricted` label on tenant namespaces rejects ad-hoc probe pods before they reach Kyverno; tests use a compliant pod spec (also in smoke stage 11). |

## 4. Smoke stage 11 (new)
On each tenant namespace: policy is `Deny`, the unsigned v1.4.0 digest is **denied**, and the image actually running there is **admitted** (server-side dry-run; nothing is created).

## 5. Next
Track C (ApplicationSet modernization). Owner actions still open from Track A: browser test and O-1.
