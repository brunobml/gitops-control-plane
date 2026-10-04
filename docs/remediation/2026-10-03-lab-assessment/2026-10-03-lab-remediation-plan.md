# Lab Remediation Plan — 2026-10-03 Assessment: Integrity of the GitOps Inputs, Platform Baseline & Production Hygiene
## Hub-and-Spoke GitOps Control Plane (2026-10-03)

> **Status: Current.** Active remediation record for the 2026-10-03 assessment.

* **Plan Version:** 1.2 (commit [`fd0f315`](https://github.com/brunobml/gitops-control-plane/commit/fd0f315)). Tracks 0, A, B, and I closed; **v1.2 close-out approved** (G.3 reduced, C.1 per O-9, H rebuild; residuals recorded in §1.3).
* **Assessment:** [`../../assessments/2026-10-03-lab-assessment.md`](../../assessments/2026-10-03-lab-assessment.md) (maturity 8.0 / 10)
* **Baseline:** Phases 1–5 of the 2026-09-30 assessment complete and accepted ([`../2026-09-30-lab-assessment/`](../2026-09-30-lab-assessment/)); last full rebuild 2026-10-03 (8 min 15 s)
* **Target Repositories:** `gitops-control-plane`, `platform-catalog`, `platform-charts`, `orders-processor`, `tenant-workloads`
* **Author:** Claude (Opus 5.5)

---

## Review & Approval Sign-Off

| Field | Details |
|---|---|
| **Current Status** | 🟢 **TRACKS 0, A, B, & I COMPLETED & VALIDATED** · 🟢 **v1.2 CLOSE-OUT APPROVED** (Executing G.3 reduced, C.1, H) |
| **Plan Version** | `v1.2` (commit [`fd0f315`](https://github.com/brunobml/gitops-control-plane/commit/fd0f315)) |
| **Author** | Claude (Opus 5.5) |
| **Reviewed By** | Antigravity (Advanced Agentic AI Peer Reviewer) |
| **Review Date** | 2026-10-03 (v1.2 Close-Out Scope Review) |
| **Authorization Decision** | ✅ **GREEN LIGHT** — Full plan approved; **Tracks 0, A, B, & I Closed**; **v1.2 Close-Out Scope Approved**. |
| **Track 0 Status** | 🟢 **CLOSED**: Validated in [`validation-01.md`](2026-10-03-lab-remediation-plan-validation-01.md), [`validation-02.md`](2026-10-03-lab-remediation-plan-validation-02.md), and [`validation-03.md`](2026-10-03-lab-remediation-plan-validation-03.md) across all steps (0.1–0.7). |
| **Track A Status** | 🟢 **CLOSED**: Validated in [`validation-04.md`](2026-10-03-lab-remediation-plan-validation-04.md) across all steps (A.1–A.4, V-9). |
| **Track B Status** | 🟢 **CLOSED**: Validated in [`validation-06.md`](2026-10-03-lab-remediation-plan-validation-06.md) across all steps (B.1–B.2, R-4, L2-3). |
| **Track I Status** | 🟢 **CLOSED**: Validated in [`validation-05.md`](2026-10-03-lab-remediation-plan-validation-05.md) across all steps (I.0–I.5, R-9..R-12, O-6..O-8). |
| **Execution / validation split** | The party that executes a step writes `…-implemented-NN.md`; the other party writes `…-validation-NN.md` |

### Reviewer Decision & Feedback

> ### ✅ REVIEW VERDICT: APPROVED (GREEN LIGHT)
>
> The 2026-10-03 Remediation Plan provides a thorough, rigorous, and well-targeted blueprint responding directly to the findings of the second full lab assessment ([`../../assessments/2026-10-03-lab-assessment.md`](../../assessments/2026-10-03-lab-assessment.md)). While the running platform has reached strong operational maturity (8.0 / 10), this plan effectively tackles the remaining upstream input vulnerabilities, change-control gaps, and platform namespace baselines:
>
> 1. **Immediate Prod-Gate Integrity (Track 0, Steps 0.1–0.3 Early Go-Ahead):** Approving the early authorization request for Steps 0.1–0.3 directly plugs the three most critical promotion bypasses (findings L2-1, L2-2, L4-1, L4-2). Enforcing golden chart immutability in `platform-charts/release.yaml` stops silent production tampering, protecting `tenant-workloads/main` stops unreviewed workload definitions from reaching clusters, and implementing a native `ValidatingAdmissionPolicy` for image registry allowlisting closes the Kyverno bypass where arbitrary public images (`alpine:latest`) could be admitted.
> 2. **Pre-Merge Quality Gates & Blast Radius Isolation (Tracks A & B):** Adding pre-merge CI workflows (offline `helm template` / `kubectl kustomize`, `kubeconform`, `promtool`, and JSON Schema registration validation) ensures syntax errors and broken references are trapped before reaching `main`. Splitting the monolithic ApplicationSet into per-tenant ApplicationSets (`applicationsets/tenants/<tenant>.yaml`) paired with the `ApplicationSetNotUpToDate` alert structurally eliminates cross-tenant blast radius.
> 3. **Defense-in-Depth & Platform Hardening (Tracks C & D):** Hardening platform namespaces (`traefik`, `headlamp`, `oauth2-proxy`, `kro`, `ack-system`, `kyverno`, `monitoring`) with PSS `baseline`/`restricted` labels and default-deny ingress NetworkPolicies brings the management plane to parity with tenant namespaces. Introducing platform-owned `ResourceQuota` and `LimitRange` via ApplicationSet enforces predictable resource boundaries per environment.
> 4. **Infrastructure Security & Engine Parity (Tracks E, F, G, H):** Adding `--secrets-encryption` and API audit logging directly into `setup-hub-spoke.sh`, transitioning spoke Traefik to the GitOps-managed 3.7.13 deployment, signing golden charts with Cosign, and automating dependency hygiene with Renovate elevate the entire system toward enterprise compliance. A final cold rebuild (Track H) ensures full reproducible validation.
>
> **Execution is authorized to begin immediately with Track 0 (Steps 0.1–0.3).** The operational guardrails below govern execution.

| ID | Focus Area | Reviewer Remark & Operational Guardrail | Status |
|:---:|:---:|---|:---:|
| **R-0** | Step 0.1 (Branch Protection) | **Branch Protection Safe Verification:** Verify branch protection rules on temporary/throwaway branches first to confirm rejection of force-pushes and unauthorized branch deletions without disrupting active daily work. | 🛡️ Guardrail Approved |
| **R-1** | Step 0.2 (Chart Immutability) | **OCI Digest/Checksum Verification:** In `release.yaml`, the check must compare OCI layer digests or chart metadata checksums rather than purely git commit hashes, ensuring true immutability against re-packaging. | 🛡️ Guardrail Approved |
| **R-2** | Step 0.3 (VAP Image Allowlist) | **VAP Match Scope & Dry-Run:** Ensure the `ValidatingAdmissionPolicyBinding` matches solely namespaces with `platform.lab/image-verification=enabled`. Perform `kubectl apply --dry-run=server` against existing pods in `orders-dev`, `orders-test`, and `orders-prod` before setting validation action to `Deny`. | 🛡️ Guardrail Approved |
| **R-3** | Track A (CI Pre-Merge) | **Kubeconform Schema Coverage:** Ensure `kubeconform` schemas include custom resource definitions for Kro (`ResourceGraphDefinition`), Kyverno, Traefik, and Argo CD to prevent false positive CI failures. | 🛡️ Guardrail Approved |
| **R-4** | Track B (Tenant AppSets) | **Zero-Diff Migration Protocol:** When splitting the `tenant-workloads` ApplicationSet into per-tenant ApplicationSets (`tenants/<tenant>.yaml`), use the established zero-diff migration protocol (`syncPolicy.preserveResourcesOnDeletion: true`, `create-only`, adopt in place) so that tenant applications are not interrupted during migration. | 🛡️ Guardrail Approved |
| **R-5** | Track C (NetworkPolicies) | **Platform Ingress Port Calibration:** Controllers like `kro`, `ack-system`, and `kyverno` require egress to kube-apiserver and Moto. Egress must remain unrestricted as designed. For ingress, carefully whitelist the spoke Prometheus agent scrape source pod IPs/namespaces and the kube-apiserver webhook callbacks. | 🛡️ Guardrail Approved |
| **R-6** | Track D (Quotas) | **Usage Baseline Calibration:** Measure peak observed resource usage across `orders-dev`, `orders-test`, and `orders-prod` prior to generating `ResourceQuota` limits to avoid throttling or eviction of legitimate workloads. | 🛡️ Guardrail Approved |
| **R-7** | Track E (Secrets & Audit Spike) | **Throwaway Cluster Spike:** Rigorously execute Spike E.0 on a temporary k3d cluster to verify that `--secrets-encryption` and `--kube-apiserver-arg=audit-log-*` flags are fully compatible with k3s v1.31 / v1.32 before modifying `scripts/setup-hub-spoke.sh`. | 🛡️ Guardrail Approved |
| **R-8** | Track F (Spoke Traefik) | **IngressClass & Port Parity:** When switching spokes to GitOps Traefik in Track H, ensure the `IngressClass` name matches `traefik` exactly, and the service nodeports / host ports (8081 for spoke-1, 8082 for spoke-2) match the host port mappings in `scripts/setup-hub-spoke.sh`. | 🛡️ Guardrail Approved |
| **R-9** | Track I (In-Cluster DNS Scope) | **CoreDNS Template Specificity:** The CoreDNS `template` override for `*.localhost` must strictly match regex `.*\.localhost\.$` and include `fallthrough` so it never intercepts cluster-internal service discovery (`*.svc.cluster.local`) or external resolution queries. | 🛡️ Guardrail Approved |
| **R-10** | Track I (SSO URL Consistency) | **Lockstep Cut-Over & Pre-Merge CI Guard:** Manifests for Keycloak (`KC_HOSTNAME`, redirect URIs), Argo CD, oauth2-proxy, and Grafana must be updated in a single atomic commit. The new `sso-urls` check in `ci/check-control-plane.sh` must be executed and green before applying manifests to prevent breaking active SSO sessions. | 🛡️ Guardrail Approved |
| **R-11** | Step I.0 (k3d Port Edit Safety) | **Non-Disruptive Port Edit Verification:** The spike on the throwaway cluster must verify that `k3d cluster edit --port-add` does not bounce or recreate control-plane containers, and test whether `--port-delete` introduces proxy instability before attempting either on `k3d-hub-cluster-serverlb`. | 🛡️ Guardrail Approved |
| **R-12** | Step I.4 (TLS Secret Isolation & Fallback) | **mkcert Secret Security & Graceful Fallback:** Secrets generated by `setup-local-tls.sh` must be kept out of git, given `0600` permissions on host files, and properly labeled. Traefik configuration must gracefully fall back to default self-signed certificates without error if `local-tls` secret is absent prior to owner setup. | 🛡️ Guardrail Approved |
| **R-13** | Step C.1 (Hook Job & Namespace Validation) | **C.1 Hook Job & Namespace Validation:** Dry-run admission on all namespace-scoped resources and verify Helm chart pre/post-install hook Jobs (e.g. Kyverno CRD migration, Argo CD install jobs) to ensure they do not get blocked upon re-sync. | 🛡️ Guardrail Approved |
| **R-14** | Step G.3 (Headless Maintenance Resilience) | **G.3 Headless Maintenance Resilience:** `scripts/maintain.sh` must be fully non-interactive; when clusters or Docker are stopped, it must exit cleanly with code 0. Log output to `~/.config/gitops-lab/logs/maintain.log`. | 🛡️ Guardrail Approved |
| **R-15** | Step H.1 (Rebuild Port Cleanliness) | **H.1 Rebuild Port Cleanliness:** Ensure `setup-hub-spoke.sh` creates the hub cluster exclusively with `-p 127.0.0.1:80:80@loadbalancer -p 127.0.0.1:443:443@loadbalancer`, completely eliminating legacy ports 8080 and 8443. | 🛡️ Guardrail Approved |

### Reviewer Feedback on v1.1 Amendment (Track I)

> ### ✅ AMENDMENT VERDICT: APPROVED (GREEN LIGHT)
>
> The v1.1 amendment introducing **Track I** (Canonical URLs on Ports 80/443 and Trusted Local TLS) is technically sound, cleanly isolates concerns, and directly solves the user-experience friction (port clutter, certificate warnings) while achieving in-cluster / browser URL parity for OIDC:
>
> 1. **URL Uniformity & SSO Parity:** Mapping hub ports 1:1 on 80/443 eliminates the discrepancy where Keycloak required custom port rewrites in CoreDNS. With `*.localhost` resolving to Traefik in-cluster, both pods and browsers share identical URLs, eliminating configuration divergence across manifests.
> 2. **Controlled Scope & Rollback:** Keeping SSO on HTTP avoids the complexity of secure cookie policies across subdomains while delivering immediate trusted TLS and seamless HTTPS-to-HTTP redirects via mkcert. The zero-downtime cutover strategy (binding 80/443 before removing 8080/8443) paired with the new `sso-urls` pre-merge CI check guarantees that URL shifts cannot cause undetected login outages.
> 3. **Isolation of External Labs:** Respecting Owner Decision O-4 by documenting the `argolab` port conflict rather than mutating external clusters maintains strict isolation boundaries.
>
> **Track I is approved for execution according to the schedule (Spike I.0 early execution permitted; Step I.3 live cut-over requires owner window). Guardrails R-9 through R-12 govern Track I execution.**

### Reviewer Feedback on v1.2 Close-Out Amendment

> ### ✅ CLOSE-OUT AMENDMENT VERDICT: APPROVED (GREEN LIGHT)
>
> The v1.2 close-out amendment provides an optimal, risk-calibrated trajectory to conclude the 2026-10-03 remediation plan. With the core security posture and promotion gates fully established and validated (Tracks 0, A, B, and I 100% closed), the plan prunes low-value friction from this single-maintainer local lab while maintaining rigorous production roadmapping:
>
> 1. **Pragmatic Scope Calibration:** Executing G.3 (scheduled token renewal before the 2026-11-02 expiration), C.1 (platform Pod Security admission labels), and H (clean rebuild from Git dropping legacy port bindings) resolves all imminent operational hazards and validates reproducible infrastructure-as-code from cold start.
> 2. **Explicit Residual Risk Accounting (§1.3):** Converting Tracks C.2/C.3 (platform NetworkPolicies), D (tenant quotas), E (encryption at rest / API audit logging), F (spoke Traefik 3.7.13), G.1 (signed golden chart), G.2 (Renovate bot), and G.3 alerts into formal residuals with recorded compensating controls and Phase 6 triggers strikes the right balance between enterprise rigor and local developer velocity.
> 3. **Owner Decision Endorsements:** Endorsing **O-9 (Yes to C.1)** captures high-value security baseline coverage with minimal friction given existing pod compliance. Endorsing **O-10 (Windows Task Scheduler)** directly accommodates WSL lifecycle realities, ensuring unattended credential rotation without relying on open interactive terminal sessions.
>
> **The v1.2 close-out amendment is approved for immediate implementation. Guardrails R-13 through R-15 govern execution.**

### Owner Decisions Endorsement

| ID | Decision Question | Endorsed Option | Rationale |
|---|---|---|---|
| **O-1** | Branch protection model | **Option (c): Mixed mode** | **Endorsed.** Prod-input repos (`tenant-workloads`, `platform-charts`) enforce strict change control via PRs and required CI checks. Daily platform repos (`gitops-control-plane`, `platform-catalog`, `orders-processor`) allow direct push with post-push CI alarms, preserving development velocity and avoiding GitHub self-approval blocks in a single-maintainer lab. |
| **O-2** | Tenant image policy | **Yes (ghcr.io/brunobml/* only)** | **Endorsed.** Restricting tenant namespaces to `ghcr.io/brunobml/*` via native Kubernetes VAP provides robust, controller-independent supply chain enforcement. |
| **O-3** | Alert delivery channel | **Lab-local only (deferred)** | **Endorsed.** Keeps the lab hermetic, zero-cost, and credential-free. Scheduled self-healing (G.3), Alertmanager local UI, Grafana dashboards, and Loki logs provide full operational visibility. External channels (e.g. ntfy) remain an optional future enhancement. |
| **O-4** | Host leftovers outside lab | **Leave untouched / Report only** | **Endorsed.** Preserves strict scope isolation. External k3d/kind clusters belonging to other projects must not be modified or deleted by lab automation. |
| **O-5** | Acceptance rebuild (Track H) | **Yes** | **Endorsed.** Essential to validate Track E (secrets encryption, audit logging) and Track F (spoke Traefik replacement), which modify immutable cluster creation flags in `setup-hub-spoke.sh`. |


### v1.1 Amendment summary (2026-10-03)

| | |
|---|---|
| **Trigger** | The owner opened Argo CD over HTTPS and got a certificate warning, then asked to *"move from port 8080 and just use port 80 and 443"*, citing the owner's other lab `jenkins-argo`. That lab maps its cluster 1:1 to host ports 80/443 *"so that the OIDC issuer URL is identical from the browser and from inside the cluster"* |
| **Change** | New **Track I** (§10a): **canonical, portless URLs** on host ports 80/443; a general `*.localhost` → Traefik resolution inside the hub (replacing the Keycloak-only rewrite); a **trusted local certificate** with HTTPS redirected to HTTP; a CI guard that keeps all SSO URLs consistent |
| **Not changed** | SSO stays on HTTP (moving the issuer and cookies to HTTPS is a larger, separate item, see §1.2). The spokes keep 8081/8082. Tracks 0–H, remarks R-0..R-8, owner decisions O-1..O-5 |
| **New owner decisions** | O-6 (port model), O-7 (HTTPS behaviour), O-8 (coexistence with `jenkins-argo`'s `argolab`) |

#### Owner decisions requested (v1.1)

| ID | Question | Author's recommendation | Reviewer Endorsement |
|---|---|---|---|
| **O-6** | Port model for the hub | **(a) 1:1 on `127.0.0.1:80` / `:443`**; all hub URLs become portless (`http://argocd.localhost`, `http://grafana.localhost`, …). (b) Keep 8080/8443 | **Endorsed Option (a).** Standardizes hub access on standard HTTP/HTTPS ports, achieving URL identity between browser and in-cluster pods and eliminating port clutter. |
| **O-7** | What HTTPS does | **(a) Trusted local certificate (mkcert, CA trusted on Windows once) as Traefik's default, and HTTPS answered with a redirect to the HTTP URL**: no warning, then the working HTTP/SSO path. (b) Redirect with Traefik's self-signed default cert (warning first, then redirect). (c) Do not publish 443 | **Endorsed Option (a).** Provides a clean, warning-free browser experience when users type `https://` while keeping SSO implementation simple on HTTP. |
| **O-8** | `argolab` (k3d cluster of the owner's `jenkins-argo` lab, stopped; a host leftover under O-4) also binds 80/443 when started | **Document only** (O-4 unchanged): both labs cannot run on 80/443 at the same time; `jenkins-argo` would need `HTTP_PORT`/`HTTPS_PORT` overrides (its own script supports them; its SSO assumes 80) | **Endorsed Document only.** Respects O-4 scope boundaries by leaving external clusters untouched while clearly documenting port exclusivity. |

### v1.2 Close-out amendment (2026-10-03)

| | |
|---|---|
| **Trigger** | After Tracks 0, A, I and B were validated, the owner asked *"is the lab as is good enough, or should we continue improving"*. The author's assessment: the high-value findings (prod-gate bypasses, CI, tenant blast radius, entry docs, pins, URLs/TLS) are closed. What remains is mostly defence in depth with little value on a single-user laptop lab, and some of it with real friction (the owner's standing preference: no high-friction controls whose risk is already covered; record residuals explicitly). The owner agreed to close the plan with a short finish |
| **Remaining scope** | **G.3 (reduced):** scheduled credential renewal, because spoke tokens expire **2026-11-02** and renewal today depends on someone running `post-bootstrap`. **C.1 (optional, O-9):** Pod Security labels on the platform namespaces that have none. **H:** the full rebuild, which proves the many live changes since the last rebuild (Track I cut-over, B.2 migration, digest pins) from Git alone and drops the leftover 8080/8443 mappings |
| **Not executed** | C.2, C.3 (NetworkPolicies), D, E, F, G.1, G.2 and the G.3 alerts become **recorded residuals** (§1.3), each with a reason, the compensating controls and a trigger to revisit |
| **Closure criteria** | G.3 implemented and validated, C.1 per O-9, H rebuild green and validated. Then the 2026-10-03 plan is closed; the next work is the Phase 6 roadmap (production parity on EKS), where most residuals belong |
| **New owner decisions** | O-9 (include C.1), O-10 (how the renewal is scheduled) |

#### Owner decisions requested (v1.2)

| ID | Question | Author's recommendation | Reviewer Endorsement |
|---|---|---|---|
| **O-9** | Include C.1 (Pod Security labels on `argocd`, `headlamp`, `headlamp-access`, `oauth2-proxy`, `traefik`, `ack-system`, `kro`, `kyverno`)? | **Yes.** Low friction: a server-side dry-run on 2026-10-03 shows every running pod already complies with `restricted`, except `headlamp` (complies with `baseline`). Labels go through GitOps; Kyverno's chart hook Jobs are dry-run under the new labels before `enforce` is set | **Endorsed (Yes).** Applies baseline/restricted PSS standards to platform namespaces via GitOps with dry-run verification, achieving consistency with tenant workloads at near-zero friction. (See R-13). |
| **O-10** | How is renewal scheduled? WSL runs systemd (`systemd=true`), but this distro only runs while it has sessions; Docker Desktop keeps its own distro alive, not `Ubuntu` | **Windows Task Scheduler**, daily: `wsl.exe -d Ubuntu -- …make maintain`. It starts WSL when needed and is independent of open terminals. A systemd user timer only fires while the distro is up | **Endorsed (Windows Task Scheduler).** Guarantees scheduled execution even when no interactive WSL session is open, preventing silent expiration of spoke cluster tokens on 2026-11-02. (See R-14). |

---

## 1. Executive Summary & Scope

The 2026-10-03 assessment found the running platform strong. The gaps are in **the integrity of the inputs that drive it** and in the **baseline of the platform namespaces**:
- three ways around the prod gate;
- no pre-merge checks;
- a tenant blast radius of "all tenants";
- inconsistent pinning;
- no encryption at rest or API audit;
- open platform namespaces;
- unmanaged spoke ingress;
- docs that start newcomers on a broken path.

### 1.1 Objectives

| Track | Theme | Assessment findings |
|---|---|---|
| **0** | Close the three prod-gate bypasses and fix the entry docs | L2-1, L2-2/L4-1, L4-2, L1-2, L1-3, L3-1, L1-4/L1-5/L2-6 |
| **A** | CI and change control for the GitOps repos | L2-4, L2-3 (pre-merge part), L4-3 (pipeline part) |
| **B** | Tenant blast radius and ApplicationSet health | L2-3 |
| **C** | Platform namespace baseline (NetworkPolicy, Pod Security) | L4-5 |
| **D** | Tenant resource governance | L4-6 |
| **E** | Secrets encryption at rest and API audit logging | L4-4 |
| **F** | Spoke Traefik under GitOps | L2-5 |
| **G** | Supply-chain integrity of platform artefacts and operations hygiene | L4-3, L3-2, L3-3, L3-4, L3-5 |
| **H** | Acceptance rebuild | — |

### 1.2 Out of scope (deferred, with reasons)

| Item | Reason |
|---|---|
| Keycloak production mode, TLS everywhere (v1.1 Track I only adds a trusted certificate and an HTTPS → HTTP redirect; SSO itself stays on HTTP), separate per-signal telemetry credentials (L4-7, L4-8) | They belong to the EKS translation (Phase 6 roadmap: ACM/ALB, managed IdP or Keycloak with RDS). In the lab they are recorded residuals |
| Per-tenant log tenancy and Headlamp scoping (L4-9) | Accepted owner decisions (Phase 4 O-2, Phase 5 O-6) for a single-user lab |
| Kyverno verification of upstream platform images (assessment rec. 14, second half) | High risk of locking the platform out of itself, for little lab value; reconsider on EKS with ECR pull-through and signed mirrors |
| Argo CD HA | Lab scale |

### 1.3 Residual register (v1.2 close-out)

| Item | Finding | Why not now | Compensating controls today | Revisit when |
|---|---|---|---|---|
| **C.2, C.3** NetworkPolicies on platform namespaces | L4-5 | Highest breakage risk of all tracks (webhooks, metrics scrapes, UIs) for little gain. The owner holds cluster-admin on the laptop, and anyone on the host can already reach everything | Tenant namespaces, Keycloak, Loki and the lab exporters already have policies; everything is bound to `127.0.0.1`; SSO on all UIs | Phase 6 (EKS, multi-user), or a second human user of the lab |
| **D** Tenant quotas | L4-6 | One tenant; quotas would mainly risk blocking pods | Golden chart fixes replicas and resources per env; `ContainerOOMKilled` and Kyverno/VAP admission controls | A second tenant is onboarded |
| **E** Secrets encryption at rest, API audit log | L4-4 | Laptop datastore; audit log adds disk use and rebuild flags with no reviewer of the log | Secrets never in Git (values in `~/.config/gitops-lab`, mode 600); short-lived tokens with expiry alerts; Argo CD impersonation audit | Phase 6: EKS envelope encryption (KMS) and CloudTrail / control-plane logs |
| **F** Spoke Traefik under GitOps | L2-5 | Spokes run k3s-bundled Traefik 3.6.13 (hub 3.7.13); tenant ingress works; the change needs a rebuild and widens H's risk | Smoke and synthetic probe cover tenant ingress; version recorded | The next rebuild that changes spoke creation anyway, or a Traefik CVE affecting 3.6 |
| **G.1** Signed golden chart | L4-3 | Chart versions are already immutable (release guard, local guard) and CI-checked before merge; prod changes need a PR | Release immutability, `chart-checks` required, CODEOWNERS | More than one chart or chart publisher |
| **G.2** Renovate | L3-2 | Bot PRs need reviewing in a single-maintainer lab; pins are recent (2026-10-03) | All images, charts and Actions pinned by digest/SHA; CI validates any bump | Pins older than ~3 months, or a CVE |
| **G.3 alerts** `ArgoCDSelfOutOfSync`, `AckReconcileErrors`, `AckResourceNotSynced`; notifications | L3-3..L3-5 | Nice to have; not seen as a real failure in this lab | `ArgoAppOutOfSync` (excludes `argo-cd` by design), `SpokeControllerDown`, ACK drift self-heals (Drill 4) | A real incident they would have caught |
| Per-tenant AppProjects (from Track B) | — | One tenant; CI blocks duplicate `<app>-<env>` across tenants | Per-tenant ApplicationSets, tenant guard in the template, required `registration-checks` | A second tenant is onboarded |

---

## 2. Pre-flight Facts (verified live on 2026-10-03 by the author)

| # | Fact | Evidence | Used by |
|---|---|---|---|
| F1 | `tenant-workloads` → `main`: `protected: false`; the other four repos are protected; no repo has required status checks or CODEOWNERS | GitHub REST `branches/main`; repo trees | 0.1, A |
| F2 | `platform-charts` release workflow re-pushes every chart on every push to `charts/**`; GHCR holds only `queue-backed-service:1.0.0`, used by all three environments; Actions pinned by tag (`checkout@v4`, `setup-helm@v4`); `dist/message-processor-1.0.0.tgz` committed | workflow file, GHCR tag list, tenant AppSet | 0.2, G.1 |
| F3 | Image verification policy matches only `ghcr.io/brunobml/orders-processor*`; `alpine:latest` with a compliant spec is admitted in `orders-dev`; the lab already runs a native ValidatingAdmissionPolicy (`queuebackedservice-contract`, `failurePolicy: Fail`) | policy, server-side dry run | 0.3 |
| F4 | `argocd_appset_info{resource_update_status}` is scraped (all ApplicationSets `ApplicationSetUpToDate` today); one malformed registration makes the whole `tenant-workloads` render fail | hub Prometheus, `argocd appset generate` | B |
| F5 | Images by tag: Argo CD `v3.5.3`, Redis `8.6.4-alpine`, Headlamp `v0.45.0`, hub Traefik `v3.7.13`, kro `v0.9.4`, ACK SQS `1.7.1` | pod specs | 0.6 |
| F6 | No NetworkPolicy: hub `traefik`, `headlamp`, `oauth2-proxy`; spokes `kro`, `ack-system`, `kyverno`, `monitoring`. No PSS label: hub `argocd`, `traefik`, `headlamp`, `oauth2-proxy`; spokes `kro`, `ack-system`, `kyverno` | per-namespace inventory | C |
| F7 | Tenant namespaces have no ResourceQuota/LimitRange; the tenant AppProject only allows golden-path kinds (so quotas must come from a platform-owned source) | inventory, AppProject | D |
| F8 | `k3s secrets-encrypt status` → *Disabled, no configuration file*; no `audit-*` API server flags on any cluster | node exec | E |
| F9 | Spokes run k3s-bundled Traefik 3.6.13 in `kube-system` (hub: GitOps Traefik 3.7.13 in `traefik`, bundled one disabled with `--disable=traefik`) | pods, setup script | F |
| F10 | README Quick Start omits `make post-bootstrap`; drills 2/6 are denied by Pod Security (not Kyverno); drill 5's registration format breaks the tenant render | README, dry runs | 0.4, 0.5 |

### 2.1 Pre-flight facts for v1.1 (verified live on 2026-10-03 by the author)

| # | Fact | Source |
|---|---|---|
| P1 | Hub load balancer publishes `127.0.0.1:8080→80` and `127.0.0.1:8443→443`; HTTPS answers with Traefik's self-signed **"TRAEFIK DEFAULT CERT"** | `docker ps`, `openssl s_client` |
| P2 | Nothing listens on 80/443 on Windows (IIS service absent) and no container publishes them | `Get-NetTCPConnection`, `docker ps` |
| P3 | k3d v5.9.0: `k3d cluster edit <lb> --port-add` and `--port-delete` (the latter marked experimental) change load-balancer ports **without recreating the cluster** | `k3d cluster edit --help` |
| P4 | Public `:8080` URLs exist only in `gitops-control-plane` (75 lines in 18 files, comments included): Argo CD values (domain, url, additionalUrls, OIDC issuer/logout, Headlamp links), Keycloak (`KC_HOSTNAME`, realm `rootUrl`/redirect/post-logout URIs), oauth2-proxy, Grafana, blackbox target and regexp, alert `logs` links (and their expected values in `alert-rules.test.yaml`), `Makefile`, `setup-hub-spoke.sh`, `post-bootstrap.sh`, smoke test, ingress links. The `8080` occurrences in `platform-catalog` and `orders-processor` are **container ports** and do not change | `grep` inventory |
| P5 | In-cluster OIDC today works only because the Keycloak Service also listens on 8080: CoreDNS rewrites `keycloak.localhost` → `keycloak.keycloak.svc` (`addons/keycloak/coredns-custom.yaml`). Other `*.localhost` names do not resolve in-cluster | CoreDNS ConfigMap, Service |
| P6 | Keycloak runs `start-dev --import-realm` without a persistent DB, so the realm (including redirect URIs) is re-imported on every restart | `addons/keycloak/deployment.yaml` |
| P7 | Traefik chart 41.6.1 supports `tlsStore.default.defaultCertificate.secretName` and entrypoint middlewares (`ports.websecure.http.middlewares`) | chart `values.yaml`, `templates/tlsstore.yaml` |
| P8 | `jenkins-argo` proves the CoreDNS pattern on k3s: `template IN ANY localhost { match ".*\.localhost\.$"; answer "{{ .Name }} 60 IN CNAME traefik…svc.cluster.local." }`. It does **not** solve TLS (no certificate config; same default-cert warning on 443) and keeps OIDC secrets in Git (**not** adopted) | `jenkins-argo/bootstrap/` |
| P9 | `mkcert` is installed neither on Windows nor in WSL | `Get-Command`, `command -v` |

---

## 3. Track 0: Close the Prod-Gate Bypasses and Fix the Entry Docs

### Step 0.1: Change control for the prod inputs (L2-2 / L4-1) — *early authorization requested*
* **Owner action (GitHub UI or API with the owner's token):** protect `tenant-workloads/main` like the other repos (no force push, no deletion), then apply O-1. The author cannot set branch protection (no GitHub credentials in the lab, by design).
* **Author:** add `CODEOWNERS` to all five repos. The owner is listed on prod-relevant paths:
  * `tenants/*/apps/*-prod.yaml`;
  * `charts/**`;
  * `blueprints/**`, `controllers/**`;
  * `projects/**`, `applicationsets/**`, `clusters/**`;
  * `orders-processor/deploy/values-prod.yaml`.
* **Verify:** GitHub API shows `protected: true` for all five; a force push to `tenant-workloads/main` is rejected (tested on a throwaway branch protected the same way, never on `main`).

### Step 0.2: Immutable golden chart versions (L2-1) — *early authorization requested*
* `platform-charts/release.yaml`: for each chart, check whether `oci://ghcr.io/brunobml/charts/<name>:<version>` exists (`helm show chart` or the OCI manifest). If it exists **and the packaged content differs, fail the job** ("bump the version"); if identical, skip the push. Only new versions are pushed.
* Pin the workflow's Actions by commit SHA (same method as Phase 4 B.1).
* Remove `dist/` (build output) and the deprecated `message-processor` archive from Git, and add `dist/` to `.gitignore`.
* **Verify:**
  * A test commit that changes a template without a version bump fails the workflow, and GHCR `1.0.0` keeps its digest.
  * A version bump publishes `1.0.1` without touching `1.0.0`. Discarded afterwards, unless a real change is due.

### Step 0.3: Registry allowlist for tenant namespaces (L4-2) — *early authorization requested*
* A **native ValidatingAdmissionPolicy** `tenant-image-registry-allowlist` in `platform-catalog/blueprints/`. No webhook: it cannot fail open when a controller is down.
  * Every `containers`, `initContainers` and `ephemeralContainers` image must start with `ghcr.io/brunobml/` (O-2).
  * Scope: namespaces labelled `platform.lab/image-verification=enabled`.
  * The existing Kyverno policy keeps verifying signatures and SBOMs for `orders-processor` images.
* Rollout as in Phase 4 B.4: `Audit` on nonprod → `Deny` on nonprod → prod via a catalog tag.
* **Verify:**
  * `alpine:latest` with a compliant spec → **denied** by the new VAP.
  * The signed `orders-processor` digest → admitted.
  * Pods in `kube-system`, `monitoring`, `platform-probes` → unaffected.
  * Smoke stage 11 gets the `alpine` negative case.

### Step 0.4: README Quick Start and "What you get" (L1-2)
* Add `make post-bootstrap` after `make bootstrap` and after `make start`.
* Add a short "What you get" section: URLs, SSO users, `make password`, Grafana dashboards, the drills playbook.
* Correct the `push-all.sh` comment (5 repos), and replace the pre-Phase-4 architecture diagram with today's hub/spoke addons, identity and telemetry flows.

### Step 0.5: Correct the drills playbook (L1-3)
* Drills 2 and 6: use a Pod Security-compliant pod spec. Drill 2 uses an image the controls actually cover (unsigned `orders-processor` digest for Kyverno; `alpine` for the new allowlist VAP).
* Drill 5: the real registration format (`tenant`, `app`, `env`, `port`, `valuesRevision`, `valuesFile`), plus the demo values file in the app repo.
* Every drill gets an "Expected signal" line naming *which* control fires. Absolute paths become `${REPOS_DIR:-..}`.
* **Each drill is executed once against the lab before the change is merged** (report evidence).

### Step 0.6: Digest-pin the remaining platform images (L3-1)
Pin by digest, through their values:
* Argo CD, Redis and Headlamp in `gitops-control-plane`, with Argo CD applied by the manual `argo-cd` sync (Phase 3 D-32);
* kro and ACK SQS in `platform-catalog` (nonprod via `main`, prod via a tag).

The k3s system images stay as delivered by the pinned k3s image.

### Step 0.7: Repo hygiene and document status (L1-4, L1-5, L2-6)
* A status banner ("Current" / "Design reference" / "Historical") at the top of every file in `docs/`.
* Fix the stale names in the visual-standards, Well-Architected and `platform-charts` READMEs.
* Host leftovers: report only, unless O-4 says otherwise.

---

## 4. Track A: CI and Change Control for the GitOps Repositories (L2-4)

All workflows pin Actions by SHA and use digest-pinned tool images. Checks are designed to run in under 3 minutes.

### Step A.1: `gitops-control-plane` CI
* Render every Application and ApplicationSet source offline:
  * `helm template` with the values files;
  * `kubectl kustomize` for every kustomize path.
* Validate the output with `kubeconform` (CRD schemas for Argo CD, kro, Kyverno, Traefik).
* Run `make test-alert-rules` (promtool).
* Validate the dashboards' JSON.
* Scan for secret patterns (the Phase 5 X22 pattern set).
* Also: `bash -n` / `shellcheck` on `scripts/*.sh`, and Alloy config `fmt` check.

### Step A.2: `tenant-workloads` CI
* A JSON Schema for registration files: required fields, `env ∈ {dev,test,prod}`, `port` pattern, `valuesRevision` = 40-hex for prod, `app` pattern `orders-[a-z0-9-]+`, and an optional `valuesFile`.
* A uniqueness check on `<app>-<env>`.
* A check that the referenced `valuesFile` exists at `valuesRevision` in the app repo.
* Same rules as the template guards, so a merge can no longer break the render (complements Track B).

### Step A.3: `platform-catalog` CI
* Render the blueprints, policies and controller values (helm templates for the addon values).
* `kubeconform` plus a server-free CEL syntax check of the ValidatingAdmissionPolicies.
* The RGD schema lint used in Phase 3 (`kro` RGD dry-run where possible).

### Step A.4: Required checks per O-1
Per O-1 (recommended mixed mode), the A.1–A.3 checks become **required** status checks on `tenant-workloads` and `platform-charts` (owner action in GitHub), and run as **post-push alarms** on the other repos. A red run on `main` raises a visible GitHub notification; with O-3, also a lab alert.

---

## 5. Track B: Tenant Blast Radius and ApplicationSet Health (L2-3)

### Step B.1: Alert on ApplicationSet render errors
* `ApplicationSetNotUpToDate`: `argocd_appset_info{resource_update_status!="ApplicationSetUpToDate"}` for 5m, severity critical, with a runbook section.
* Unit test plus a live fire test, using a malformed registration on a throwaway branch: an ApplicationSet copy pointed at that branch, never `main`.

### Step B.2: One ApplicationSet per tenant
* Split `tenant-workloads` into **one ApplicationSet per tenant**: `applicationsets/tenants/<tenant>.yaml`, Git-files path `tenants/<tenant>/apps/*.yaml`.
* Onboarding a *tenant* stays a platform change; onboarding an *app or environment* stays a tenant change.
* A broken file then freezes only that tenant.
* Migration exactly as Phase 4 C.2: zero-diff gate, `create-only` on the old ApplicationSet, orphan delete, adopt in place, UIDs unchanged.

---

## 6. Track C: Platform Namespace Baseline (L4-5)

### Step C.1: Pod Security labels
> **v1.2:** optional, per O-9.
> * `enforce: restricted` on the compliant namespaces and `enforce: baseline` + `warn/audit: restricted` on `headlamp`, set through GitOps (`managedNamespaceMetadata` / namespace manifests).
> * Before enforcing, `warn` is set and the charts' hook Jobs (Kyverno, Argo CD) are applied with `--dry-run=server` to surface violations.
> * C.2/C.3 are residuals (§1.3).

For each namespace in F6, run `kubectl label --dry-run=server` first (as in Phase 5 F.0). Then:
* label it `restricted` where every pod passes after small securityContext fixes in its values;
* otherwise `baseline`, with the reason recorded;
* `kube-system` excepted.

Labels are set by the owning Application's `managedNamespaceMetadata` (and by the setup scripts for namespaces they create), so they survive rebuilds.

### Step C.2: NetworkPolicies
Default-deny ingress plus explicit allows per namespace:

| Namespace | Allowed ingress |
|---|---|
| `traefik` | from anywhere on 8000/8443 (it is the ingress) |
| `headlamp` | from Traefik only |
| `oauth2-proxy` | from Traefik |
| `kro`, `ack-system`, `kyverno` | metrics from the spoke `monitoring` namespace; Kyverno also its webhook port from the API server (node network) |
| spoke `monitoring` | from the namespace itself only (the agent scrapes kube-state-metrics and Alloy; both push to the hub, nothing calls in) |

Egress stays open in the platform namespaces (controllers need the API server and moto). It is recorded as such.

### Step C.3: Smoke check
A new smoke assertion: every non-system namespace has at least one NetworkPolicy and a PSS enforce label.

---

## 7. Track D: Tenant Resource Governance (L4-6)

> **v1.2: not executed**, recorded residual (§1.3).

### Step D.1: Per-namespace quotas from the registrations
* A platform-owned ApplicationSet `tenant-namespace-baseline` (project `platform-addons`, Git-files generator over the same registrations).
* It renders one `ResourceQuota` and one `LimitRange` per tenant namespace, sized per `env`:
  * dev/test: 1 CPU, 1 Gi requests, 10 pods;
  * prod: 2 CPU, 2 Gi, 20 pods;
  * LimitRange defaults equal to the blueprint's container defaults.
* Tenants cannot change it: the kinds are outside the tenant AppProject.

### Step D.2: Verify
* `orders-*` workloads keep running.
* A demo registration that requests more than its quota → `FailedCreate` with a quota message, visible in Loki events.
* `ContainerOOMKilled` and warning events stay intact.

---

## 8. Track E: Secrets Encryption at Rest and API Audit Logging (L4-4)

> **v1.2: not executed**, recorded residual (§1.3).

### Step E.0: Spike (read-only)
On a throwaway k3d cluster:
* confirm `--secrets-encryption` (k3s, aescbc) works with the pinned k3s image and `k3s secrets-encrypt status` reports enabled and re-encrypted;
* confirm the API audit flags with a policy file mounted through k3d (`--volume`) and log rotation (`audit-log-maxage/maxbackup/maxsize`).

### Step E.1: `setup-hub-spoke.sh`
* All three clusters are created with `--secrets-encryption` and an audit policy:
  * Metadata level for all requests;
  * RequestResponse for `secrets`, `rbac.authorization.k8s.io` and `argoproj.io` writes;
  * Secret bodies excluded.
* The audit log is written to a host directory per cluster (`~/.local/share/gitops-lab/audit/<cluster>/`, mode 700), rotated.
* `make audit-log CLUSTER=…` tails it.

### Step E.2: Shipping (spike outcome decides)
Preferred: an audit **webhook** backend to the hub Alloy (`loki.source.api`), keeping Alloy free of hostPath. Fallback: file only, documented as a residual.

### Step E.3: Verify
* `secrets-encrypt status` → Enabled on all clusters.
* A Secret read from the datastore is not plaintext (k3s `etcdctl`/sqlite check on a throwaway Secret).
* A break-glass login and an RBAC change appear in the audit log (and in Loki if E.2 succeeds).

Applied by the **Track H rebuild** (cluster flags cannot be changed in place with k3d).

---

## 9. Track F: Spoke Traefik under GitOps (L2-5)

> **v1.2: not executed**, recorded residual (§1.3).

* `setup-hub-spoke.sh` creates the spokes with `--disable=traefik@server:*` (as on the hub).
* A spoke addon (in `addons-spoke`, values in `platform-catalog/controllers/traefik/`) deploys the **same pinned Traefik chart** as the hub into namespace `traefik`. It has the same IngressClass name, so tenant Ingresses and the `queue-backed-service` blueprint do not change.
* NetworkPolicy and Pod Security as in Track C.
* Applied by the **Track H rebuild**: on running spokes two Traefik controllers would compete for the same IngressClass.
* **Verify:**
  * Dashboards `orders-*.localhost:8081/8082` answer.
  * The synthetic probe passes (its egress rule moves from `kube-system` Traefik pods to the `traefik` namespace).
  * Hub and spokes run the same Traefik version.

---

## 10. Track G: Supply-Chain Integrity and Operations Hygiene

### Step G.1: Signed golden chart (L4-3)
> **v1.2: not executed**, recorded residual (§1.3).

* `platform-charts` CI signs each newly pushed chart version keyless with cosign (same identity model as `orders-processor`).
* The Track A CI in `tenant-workloads`/`gitops-control-plane` verifies the signature of every chart version referenced by an ApplicationSet before merge.
* **Spike first:** whether Argo CD 3.5 can verify OCI Helm chart signatures natively; if yes, enable it, otherwise the CI check is the gate.

### Step G.2: Automated dependency updates (L3-2)
> **v1.2: not executed**, recorded residual (§1.3).

Renovate (GitHub App, owner action to install; or Renovate as a GitHub Action with a fine-scoped token, also owner action) for:
* Helm chart versions in ApplicationSets and values;
* image digests in values files;
* Action SHAs.

Grouped weekly PRs. Track A CI is the gate; prod-relevant bumps follow the normal promotion.

### Step G.3: Scheduled self-healing and visibility (L3-3, L3-4, L3-5)
> **v1.2 scope:**
> * `scripts/maintain.sh` (`make maintain`): only `post-bootstrap` step 1 (token renewal, < 7 days left) and step 6 (orphans), with no smoke test. The step logic moves out of `post-bootstrap.sh` so both share it.
>   * When the hub is unreachable (lab stopped, Docker Desktop not running), it logs and exits 0.
>   * Each run writes `lab-maintenance` (epoch) to `monitoring/credential-expiry`, so its last run is visible in Grafana.
> * Scheduled per O-10, by default a **Windows Task Scheduler** daily task. `scripts/register-maintenance-task.ps1` registers it as an owner action; the command is printed for review first.
> * The safety net stays `SpokeTokenExpiringSoon` (7 days).
> * The new alerts and notifications below are **residuals** (§1.3).
> * **Verify:** a run on a stopped hub exits 0; a run with a recorded expiry under 7 days renews the tokens (as Drill 2); the scheduled task runs once on demand.

* A host-side schedule runs the idempotent `post-bootstrap` steps 1 (token renewal) and 6 (orphans) daily: a systemd user timer if WSL systemd is enabled, otherwise documented as a manual step. So token expiry no longer depends on someone remembering.
* New alerts, each with a runbook section and a unit test:
  * `ArgoCDSelfOutOfSync`: `argo-cd` OutOfSync for 24h;
  * `AckReconcileErrors`: rate of `controller_runtime_reconcile_errors_total{job="ack-sqs"}` > 0 for 15m;
  * `AckResourceNotSynced`: via kube-state-metrics custom resource state for `ACK.ResourceSynced`, if the spike shows it is cheap; otherwise reconcile errors only.
* Argo CD notifications: `on-sync-failed` and `on-health-degraded` triggers to the O-3 channel if chosen. Otherwise leave the controller unconfigured and record it.

---

## 10a. Track I: Canonical URLs on Ports 80/443 and Trusted Local TLS (v1.1, owner request)

Goal: the browser and every pod use **the same portless URL** for every hub UI and for the OIDC issuer. HTTPS opens without a warning and leads to that URL. SSO behaves exactly as today.

### Step I.0: Spike (throwaway cluster, no change to the lab)
* On a throwaway k3d cluster (O-4: never touch `argolab`), check three things:
  1. `k3d cluster edit <lb> --port-add 127.0.0.1:80:80@loadbalancer` and `--port-delete` work on k3d 5.9 with Docker Desktop.
  2. The CoreDNS `template` override resolves `x.localhost` to the Traefik Service from a pod.
  3. A RedirectScheme middleware attached to the `websecure` entrypoint answers `https://h.localhost/p` with `302 http://h.localhost/p`.
* Result recorded before I.1. If `--port-delete` misbehaves, the old mappings stay until the Track H rebuild (harmless; they would only serve the old URLs).

### Step I.1: One name resolution path for `*.localhost` (hub)
* Replace `addons/keycloak/coredns-custom.yaml` with a `localhost.override` template: every `*.localhost` name becomes a CNAME to `traefik.traefik.svc.cluster.local`.
* Pods (Argo CD, Grafana, oauth2-proxy, blackbox, smoke) then reach `keycloak.localhost` (and any hub UI) **through Traefik on port 80, like the browser**.
* `post-bootstrap` already restarts CoreDNS when that ConfigMap's hash changes (R-1, Phase 4).
* Keycloak's NetworkPolicy is narrowed to **Traefik only**, since in-cluster clients no longer connect to the pod directly. The Keycloak Service port becomes an implementation detail.
* Ships **in the same change set as I.2**: the Traefik Service has no port 8080, so `:8080` URLs would break in-cluster without I.2.

### Step I.2: Portless URLs everywhere (one change set)
* Every item in P4 moves from `http://<host>.localhost:8080` / `http://localhost:8080` to `http://<host>.localhost` / `http://localhost`:
  * Argo CD (`global.domain`, `url`, `additionalUrls`, OIDC issuer, logout, Headlamp links);
  * Keycloak (`KC_HOSTNAME`, realm `rootUrl`, redirect and post-logout URIs for `argocd`, `headlamp`, `grafana`);
  * oauth2-proxy (issuer, endpoints, `redirect_url`, `whitelist_domains`);
  * Grafana (`root_url`, auth/token/userinfo/signout);
  * blackbox target and regexp;
  * alert `logs` links;
  * `Makefile`, `setup-hub-spoke.sh` (k3d `-p 127.0.0.1:80:80@loadbalancer -p 127.0.0.1:443:443@loadbalancer`, argocd CLI address), `post-bootstrap.sh`, the smoke test (including the in-pod `/dev/tcp/keycloak.localhost/80` check);
  * README, runbooks, tutorial.
* **New CI stage `sso-urls`** in `ci/check-control-plane.sh` (Track A toolkit). It fails if:
  * the issuer differs between Argo CD, Grafana, oauth2-proxy and Keycloak `KC_HOSTNAME`;
  * an app URL has no matching redirect URI in the realm;
  * any public `:8080`/`:8443` URL remains.

  A partial change, the main risk of this track, becomes a red check instead of a login outage.

### Step I.3: Live cut-over (owner-announced window, about 15 min, hub only)
1. `k3d cluster edit k3d-hub-cluster-serverlb --port-add 127.0.0.1:80:80@loadbalancer --port-add 127.0.0.1:443:443@loadbalancer`. Old and new ports now both work at the TCP level.
2. Push I.1 + I.2 with CI green. Argo CD syncs Keycloak (realm re-import, P6), Grafana, oauth2-proxy and Headlamp. The `argo-cd` app gets its **manual sync** as `platform-admin` with its own CLI config (B.4 rule), over the new address.
3. `make post-bootstrap`: CoreDNS restart (I.1), credentials, smoke test with the new URLs.
4. Browser acceptance by the owner: Argo CD, Headlamp and Grafana log in and out for `platform-user` and `tenant-a-user`.
5. `--port-delete` 8080/8443 (or leave them until H, per I.0).
* **Rollback:** revert the I.1/I.2 commit and sync `argo-cd`. The 8080 mapping is still present until step 5, so the old URLs work again at once.
* Everyone signs in again after the cut-over (new issuer string, so old tokens are invalid). Expected and harmless.

### Step I.4: Trusted local TLS and HTTPS → HTTP (per O-7)
* **Owner, once, on Windows:** install mkcert and run `mkcert -install` (adds a local CA to the Windows trust store used by Chrome/Edge). Then issue a certificate for `localhost`, `argocd.localhost`, `headlamp.localhost`, `grafana.localhost`, `keycloak.localhost` into `~/.config/gitops-lab/tls/` (mode 600). The CA key never leaves Windows; the lab only receives the leaf cert and key.
* `scripts/setup-local-tls.sh` (idempotent, like the other `setup-*-secrets.sh`; values never printed):
  * creates Secret `traefik/local-tls`, never in Git;
  * records the certificate's `notAfter` in `monitoring/credential-expiry`, so the existing `SpokeTokenExpiringSoon` rule (generic over `lab_credential_expiry_timestamp_seconds`) warns 7 days before expiry.
* `addon-traefik` values:
  * `tlsStore.default.defaultCertificate.secretName: local-tls`;
  * a `Middleware` `redirect-to-http` (RedirectScheme `http`, `permanent: false`) on `ports.websecure.http.middlewares`.

  Every HTTPS request is answered with a trusted certificate and a 302 to the same URL over HTTP. While SSO is on HTTP, nothing is served over HTTPS itself.
* Without the Secret, Traefik keeps its default certificate: option (b) behaviour, with no breakage. The script is called by `post-bootstrap` if the files exist.

### Step I.5: Verify
* `curl -sI http://argocd.localhost` → 200; `https://argocd.localhost` → 302 to `http://argocd.localhost/…`, with a certificate issued by the mkcert CA.
* From a hub pod, `keycloak.localhost` resolves to the Traefik Service, and the issuer matches the browser's byte for byte.
* Smoke 12/12 with the new URLs; impersonation audit; alert tests; `make ci` including `sso-urls`.
* Owner browser acceptance (I.3 step 4). No certificate warning on any hub host.
* The Track H rebuild later proves the result from scratch: `setup-hub-spoke.sh` creates the hub directly on 80/443.

---

## 11. Track H: Acceptance

### Step H.1: Full rebuild (O-5)
> **v1.2 scope:** the rebuild runs **without E and F** (residuals). It proves from Git alone:
> * Track I: hub created on 80/443 only, so the 8080/8443 leftovers are gone; `*.localhost` via Traefik in-cluster; lab certificate through `setup-local-tls.sh`; SSO on portless URLs;
> * Track B: per-tenant ApplicationSet, render-error alert;
> * Track 0: digest pins, allowlist;
> * Track A: CI green on the commit built;
> * C.1 labels if O-9 = yes; G.3 `make maintain` on the fresh lab.
>
> Expected list below; the items for E, F and the deferred alerts no longer apply.

* `make teardown → setup → bootstrap → post-bootstrap` with Tracks E and F in the build path.
* **Expected:**
  * all Applications Synced/Healthy;
  * smoke green, including the new assertions: allowlist negative case, namespace baseline, quota;
  * encryption at rest enabled and the audit log written on all three clusters;
  * one Traefik version everywhere;
  * (v1.1) hub created directly on 80/443; portless URLs, SSO for all three UIs and the HTTPS → HTTP redirect work from scratch;
  * every new alert fired once during its track's tests.
* Executed and validated by different parties.

---

## 12. Verification Matrix

| # | Area | Test (cause the failure) | Expected |
|---|---|---|---|
| Y1 | Branch protection | GitHub API; force push on a protected throwaway branch | 5/5 protected; rejected |
| Y2 | CODEOWNERS | file present; owner listed on prod paths | 5/5 repos |
| Y3 | Chart immutability | template change without version bump | workflow fails; GHCR `1.0.0` digest unchanged |
| Y4 | Registry allowlist | `alpine:latest` (compliant spec) in `orders-dev` / signed orders image / pod in `monitoring` | denied / admitted / admitted |
| Y5 | Quick Start | follow README on a fresh rebuild | working lab, smoke green |
| Y6 | Drills | run drills 2, 5, 6 as written | each produces its documented signal |
| Y7 | Digest pins | no running platform image without `@sha256` (k3s system images excepted) | none |
| Y8 | CI | a broken kustomization / an invalid registration / a failing rule test in a PR | check fails before merge |
| Y9 | AppSet health | malformed registration on a throwaway ApplicationSet | `ApplicationSetNotUpToDate` fires; other tenants unaffected (B.2) |
| Y10 | Namespace baseline | inventory; dry-run admission | every non-system namespace has netpol + PSS label; no violations |
| Y11 | NetworkPolicy | probe from a scratch pod to `kro`/`ack-system`/`kyverno` metrics | denied; agent scrape still up |
| Y12 | Quotas | demo app over quota | `FailedCreate` (quota), visible in Loki |
| Y13 | Encryption at rest | `secrets-encrypt status`; datastore read of a test Secret | Enabled; not plaintext |
| Y14 | Audit | break-glass login, RBAC change | recorded (file; Loki if E.2) |
| Y15 | Spoke Traefik | versions; dashboards; synthetic probe | one version; all green |
| Y16 | Signed chart | `cosign verify` on the chart version; CI rejects an unsigned version | pass / reject |
| Y17 | New alerts | `ArgoCDSelfOutOfSync`, `AckReconcileErrors`, `ApplicationSetNotUpToDate` | unit tests pass; live fire where feasible |
| Y18 | Rebuild | H.1 | all green; time recorded |
| Y20 | Portless URLs (I.2) | `make ci` stage `sso-urls`; a deliberately mismatched redirect URI | green; red with the mismatch named |
| Y21 | In-cluster resolution (I.1) | resolve `keycloak.localhost` / `grafana.localhost` from a hub pod; compare issuer in-pod vs browser | Traefik Service; identical issuer |
| Y22 | Cut-over (I.3) | SSO login/logout in all three UIs for both users; rollback rehearsal on the throwaway cluster (I.0) | works; rollback restores the old URLs |
| Y23 | HTTPS (I.4) | `https://<host>.localhost` for the five hosts | trusted cert (mkcert CA), 302 to `http://` |
| Y24 | TLS expiry | `lab_credential_expiry_timestamp_seconds{credential="local-tls"}` present | value = cert `notAfter` |
| Y19 | Regression | Phase 5 smoke 12/12, alert tests, impersonation audit | unchanged |

---

## 13. Risk Register & Rollback

| Risk | Likelihood | Impact | Mitigation / Rollback |
|---|:-:|:-:|---|
| Registry allowlist blocks a legitimate tenant image | Low | Med | Audit first; allowlist lives in the blueprint (one PR to extend); VAP binding switched back to Audit to roll back |
| Required checks slow down or block urgent fixes | Med | Low | Mixed mode (O-1); checks under 3 minutes; owner (admin) can still merge in an emergency, recorded |
| NetworkPolicy breaks controller traffic (webhooks, metrics) | Med | High | One namespace at a time; webhook ports from the node network explicitly allowed; `KyvernoDown`/`SpokeControllerDown` alerts as tripwires; delete the policy to roll back |
| Quotas evict or block existing workloads | Low | Med | Sized above today's usage (measured first); applied to nonprod first |
| Audit log fills the host disk | Low | Med | Rotation flags (size, age, backups); log volume measured in E.0 |
| Encryption-at-rest key lost on rebuild | Low | Low (lab) | Datastore is recreated on rebuild anyway; key lives with the cluster |
| Spoke Traefik migration breaks tenant ingress | Med | Med | Only on the rebuild (no in-place switch); same chart and IngressClass name as the hub; smoke and synthetic probe gate the rebuild |
| (v1.1) Partial URL change breaks SSO login | Med | High | Single change set (I.1+I.2); CI `sso-urls` guard; old port mapping kept until verified; revert + `argo-cd` sync restores it |
| (v1.1) Port 80/443 taken on the host later (IIS, another lab such as `argolab`) | Low | Med | Pre-flight P2 repeated at cut-over and in `setup-hub-spoke.sh` (fail fast with a clear message); O-8 documents the `argolab` conflict |
| (v1.1) Local CA trusted on the owner's machine | Low | Low | mkcert CA key stays on Windows; certificate names limited to `*.localhost` lab hosts; residual recorded |
| CI false positives block merges | Med | Low | Run as advisory for one week on the "alarm" repos before relying on them |

---

## 14. Sequencing & Effort

| Order | Steps | Gate | Effort |
|---|---|---|---|
| 1 | **0.1, 0.2, 0.3** (early) | Early authorization + owner actions (O-1, O-2) | S |
| 2 | 0.4 – 0.7 | Plan approval | S–M |
| 3 | A.1 – A.4 | each workflow green on `main` before becoming required | M |
| 4 | B.1, B.2 | zero-diff gate for B.2 | M |
| 5 | C.1 – C.3, D.1 – D.2 | nonprod first, then prod | M |
| 6 | E.0 spike, F prepared, G.1 – G.3 | spikes recorded before implementation | M–L |
| 6b | (v1.1) I.0 spike → I.1 + I.2 → I.3 cut-over → I.4 (after the owner's mkcert step) → I.5 | v1.1 approval; owner decisions O-6..O-8; owner window for I.3 | M |
| 6c | (v1.2) G.3 reduced, C.1 (if O-9), then H | v1.2 approval; O-9, O-10; owner window for H (O-5) | S–M |
| 7 | H.1 rebuild (v1.2: proves 0, A, B, I, G.3, C.1; E and F are residuals) | owner approval (O-5); other party validates | S (+ validation) |

Tracks 0, A–D, G and I each get their own implementation report and independent validation. E and F are reported with H.
