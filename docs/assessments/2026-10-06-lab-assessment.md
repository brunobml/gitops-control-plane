# Hub-and-Spoke Lab Assessment — 2026-10-06

> **Status: Current point-in-time assessment.** Reviewed 2026-10-06 18:18 UTC against `gitops-control-plane` commit `4c226dc`, the live three-cluster lab, Moto, and six sibling repositories. This supersedes the [2026-10-03 assessment](2026-10-03-lab-assessment.md) as a description of the running lab; that report remains historical evidence. The [assessment prompt](../ai-prompts/ai-agent-lab-assessment-prompt.md) supplies the four-layer structure used here.

**Scope and method.** Read-only `kubectl`, Docker, repository and GitHub rules queries, plus the existing Bats smoke suite. The Bats order-flow gate sent test messages and checked their processing; no resource deletion or fault injection was performed. The prior [P5 acceptance](../roadmaps/2026-10-04-tenant-iac-team-clusters-plan-validated-09.md) and [clean rebuild record](../roadmaps/2026-10-04-tenant-iac-team-clusters-plan-implemented-08.md) were reviewed, not replayed. The six checked-out repositories were `gitops-control-plane`, `platform-catalog`, `platform-charts`, `orders-processor`, `tenant-workloads`, and `tenant-iac`.

**Live snapshot.** Five k3d nodes across the hub and two spokes were Ready; no non-running workload pods were found. Hub Argo CD had **42/42 Applications Synced and Healthy**, 10 ApplicationSets and 6 AppProjects. Each spoke had active `QueueBackedService` and `TeamEKSCluster` graph definitions; the three order claims and both team cluster claims were Ready. Prometheus had 21 alert rules with no pending or firing alert. The independent modular smoke suite passed **27/27 tests**, including order processing in dev, test and prod. The latest control-plane GitHub CI run for `4c226dc` succeeded.

## 1. Executive Summary

**Maturity: 8.4/10** (2026-10-03: 8.0). The lab is now a reproducible six-repository GitOps platform with protected production input paths, immutable chart release checks, signed workload admission, account-aware Moto resources, team EKS claims, and tested operational recovery. It gives a learner real practice with the relationships among Argo CD, kro, ACK, admission, telemetry, and cloud accounts. The largest remaining gap is the boundary between a **Moto EKS API record** and a working EKS Kubernetes cluster: the team claims prove orchestration of mock resources, not usable tenant control planes. Monitoring also names the two present claims explicitly, so a newly added team claim is less well covered than the existing ones. The production transition still needs stronger namespace boundaries, enforced human review, real IAM-based identity, network isolation, auditability, and tested real-cluster convergence. There is no live Critical finding in this single-user local lab.

## 2. Strengths

- **Rebuild and health are evidenced.** The recorded clean-slate `teardown → setup → bootstrap → post-bootstrap` path reached 42 healthy Applications and a 12-stage smoke pass. This assessment independently repeated the 27-test modular smoke suite with zero failures.
- **GitOps has clear layers.** The hub manages itself and both spokes. Tenant registration, platform catalog, golden charts, application code and team infrastructure claims occupy separate repositories and ApplicationSets. Production blueprint revisions and workload values have explicit promotion paths.
- **The cloud abstraction is exercised end to end.** kro composes tier-one network resources with IAM roles, EKS Cluster and Nodegroup ACK resources. CARM routes nonprod and prod to Moto accounts `111111111111` and `222222222222`; live mock EKS and nodegroup records are `ACTIVE` in both.
- **Pre-merge checks and artifact integrity improved since 2026-10-03.** All six repos have CI and CODEOWNERS files. `tenant-workloads`, `tenant-iac` and `platform-charts` have effective pull-request and required-check rules. The chart release workflow refuses to overwrite an existing version when its content differs.
- **Security controls are concrete.** Argo CD uses scoped deployer ServiceAccounts; the built-in admin account is disabled, with Keycloak PKCE and a local break-glass identity. Tenant namespaces enforce restricted Pod Security. VAPs constrain tenant images and both kro contracts; Kyverno checks signed application images.
- **Telemetry reflects actual flows.** Prometheus receives spoke metrics, Loki receives logs, team readiness is displayed in Grafana, and an end-to-end synthetic order probe exercises every current order environment. No alert was firing at the snapshot.

## 3. Layered Findings

Severity describes risk in the **current lab**. A production consequence is called out where it differs. Accepted residuals from the [2026-10-03 remediation register](../remediation/2026-10-03-lab-assessment/2026-10-03-lab-remediation-plan.md) are identified rather than presented as newly discovered defects.

### Layer 1 — Foundation and Observability

| ID | Severity | Finding and evidence |
| --- | --- | --- |
| L1-1 | Info | The estate is healthy now: five Ready nodes, 42 healthy Applications, 10 ApplicationSets, 6 AppProjects, no pending/firing alerts, and 27/27 Bats smoke tests passed. This is a snapshot, not a guarantee about the next reconcile. |
| L1-2 | Low | **The main onboarding path still describes five repositories.** [README Quick Start](../../README.md) and the [student rebuild guide](../runbooks/devops-student-rebuild-guide.md) omit `tenant-iac` from the Git source-of-truth inventory. `scripts/push-all.sh` also names only five repos. A newcomer following those pages will not know where team EKS requests live or whether `make push` covers them. |
| L1-3 | Low | **The team IaC runbook gives conflicting review instructions.** It accurately says the active ruleset requires zero approvals, then says to merge only after a review is approved ([runbook](../runbooks/tenant-iac-operations.md)). The current `tenant-iac` effective rule requires a PR and `cluster-checks` but has `required_approving_review_count: 0` and `require_code_owner_review: false`. State the actual gate and the desired future gate separately. |

### Layer 2 — Architecture and GitOps Maturity

| ID | Severity | Finding and evidence |
| --- | --- | --- |
| L2-1 | Medium | **A Ready team claim is narrower than full ACK convergence.** Both live EKS Cluster CRs report `status.status=ACTIVE` while `ACK.ResourceSynced=False`, `ACK.LateInitialized=False` and `Ready=False` with a delayed late-initialization message. Their nodegroups are synced, and both parent `TeamEKSCluster` claims are Ready=True. The [blueprint](../../../platform-catalog/blueprints/team-eks-cluster-rgd.yaml) explicitly documents this Moto behavior and intentionally gates on `ACTIVE` plus absence of `ACK.Terminal`. This is a valid lab workaround, but the same green status must not be used as the real-AWS acceptance criterion. |
| L2-2 | Info | **Change control is deliberately mixed.** GitHub effective rules require PRs and status checks for `tenant-workloads`, `tenant-iac` and `platform-charts`; they require zero approving reviews. `gitops-control-plane`, `platform-catalog` and `orders-processor` allow direct pushes but prevent deletion and non-fast-forward updates. This matches owner decision O-1, while leaving a deliberate production change-control gap. |
| L2-3 | Info | **Moto EKS resources are mock records.** `TeamEKSCluster` provisions IAM, EKS and nodegroup API objects in Moto; the running Kubernetes APIs are still the three k3d clusters. The claim's endpoint and `ACTIVE` state do not demonstrate a functional tenant Kubernetes API, node registration, workload scheduling, or network reachability. Those must be separate Phase 6 tests. |

### Layer 3 — Operational Excellence and Extensibility

| ID | Severity | Finding and evidence |
| --- | --- | --- |
| L3-1 | Medium | **Smoke coverage is fixed to today's tenants.** `post-bootstrap.sh` discovers `tenant-iac` Applications dynamically, but both `scripts/smoke-test-hub-spoke.sh` and `tests/smoke/06_observability.bats` require readiness metrics only for `analytics-dev` and `analytics-prod`; the expected Application lists also name exactly today's 42. A third claim may be healthy in Argo CD while its metric is absent and the metric-presence gate still passes. Derive the expected claims from live registered team Applications or claims. |
| L3-2 | Medium | **Loss of the team probe can silence its alert.** `TeamClusterNotReady` evaluates `lab_team_cluster_ready == 0`. If a spoke's probe stops exporting that series, it becomes absent rather than zero. `SyntheticProbeStale` likewise compares the last-run timestamp but has no absent-series branch; no alert rule currently tests `up{job="synthetic-order-probe"}`. The manual smoke gate catches missing metrics for the two known claims, but unattended detection is incomplete. |
| L3-3 | Low, accepted residual | Spoke Traefik remains the k3s-bundled 3.6.13 while the GitOps-managed hub uses 3.7.13; chart signing and dependency-update automation are deferred. Existing smoke, version pinning, CI, and immutable chart-version checks reduce the immediate lab risk. Revisit these when the next spoke rebuild or additional publishers make the maintenance cost worthwhile. |

### Layer 4 — Security and Production Readiness

| ID | Severity | Finding and evidence |
| --- | --- | --- |
| L4-1 | Medium | **The team IaC deployer can patch any Namespace.** On both spokes, `kubectl auth can-i patch namespaces/kube-system --as=system:serviceaccount:kube-system:argocd-iac-deployer` returned `yes`. The same identity can create `TeamEKSCluster` but cannot create a raw ACK EKS Cluster. The broad Namespace verbs support Argo CD `CreateNamespace` and managed labels, yet are wider than the `iac-*` destination intent. A compromised deployer identity could alter labels or account annotations outside its team namespace. |
| L4-2 | Medium, accepted residual | Platform namespaces do not have the same default-deny NetworkPolicy coverage as tenant workload namespaces; tenant resource quotas, k3s secret encryption and API audit logging remain deferred. The live network policy inventory contained policies for order namespaces and `platform-probes`, but none in `iac-*` (which currently hosts only claims). The [residual register](../remediation/2026-10-03-lab-assessment/2026-10-03-lab-remediation-plan.md) records the single-user laptop rationale and Phase 6 triggers. |
| L4-3 | Medium for production | Production claims have `retain` and adoption annotations, but Moto state is in memory; a Moto restart erases even retained mock resources. This tests ACK lifecycle semantics, not durable disaster recovery. The hub's Keycloak issuer is HTTP on `*.localhost`; loopback binding and SSO reduce local exposure but do not meet real multi-user transport requirements. |
| L4-4 | Medium for production | The production-input repositories require passing checks and PRs, but no independent approval. CODEOWNERS requests are advisory with the current `0`-approval rules. This is an accepted single-maintainer lab choice and a real separation-of-duties gap before multiple humans or AWS accounts are involved. |

## 4. Prioritized Recommendations

| Priority | Change | Why it matters in the lab and in production | Effort |
| --- | --- | --- | --- |
| Quick win | Update README, student guide and `make push` help to describe the sixth repo and its claim path; resolve the runbook's approval wording. | A new engineer can locate and safely change team claims; accurate change-control text prevents false assurance. | Small |
| Quick win | Add `up == 0` and absent-series checks for each spoke synthetic probe, with an alert rule test and a runbook link. | A broken exporter should raise a signal rather than make readiness disappear. The same pattern is required for any production readiness metric. | Small |
| Medium | Discover expected team claims dynamically in legacy and Bats smoke, and compare them with fresh `lab_team_cluster_ready` series. | Each newly registered tenant receives the same monitoring gate without editing a fixed list. | Medium |
| Medium | Move Namespace creation and metadata ownership to a platform component or add an admission boundary for Namespace mutations by deployer identities. Re-test with `kubectl auth can-i` and a server-side dry run. | Keeps tenant infrastructure sync limited to its intended namespace and prevents a leaked deployer token from changing platform Namespace metadata. | Medium |
| Medium | Record two separate team-cluster acceptance signals: mock/API-record readiness and full Kubernetes usability. For the real AWS spike, require ACK convergence, API authentication, nodes Ready, scheduling, networking and teardown/adoption drills. | Preserves the useful Moto contract test while preventing a green mock record from being mistaken for a working EKS cluster. | Medium now; Large in AWS |
| Strategic | Before multi-user or real AWS rollout, require a distinct reviewer for prod inputs, add tenant quotas and platform network policy, sign charts, replace static Moto keys with [EKS Pod Identity](https://docs.aws.amazon.com/eks/latest/userguide/pod-identities.html), use [EKS access entries](https://docs.aws.amazon.com/eks/latest/userguide/access-entries.html), and export [EKS control-plane audit logs](https://docs.aws.amazon.com/eks/latest/userguide/control-plane-logs.html). | These are the missing identity, isolation, provenance and audit boundaries. EKS already provides [default envelope encryption on supported versions](https://docs.aws.amazon.com/eks/latest/userguide/envelope-encryption.html); verify key-management requirements instead of assuming encryption is absent. | Large |

## 5. Production Parity Gap Analysis

| Domain | Current lab | Real EKS hub-and-spoke acceptance |
| --- | --- | --- |
| Cluster contract | kro and ACK create Moto EKS Cluster/Nodegroup records; parent claim Ready means mock `ACTIVE` without Terminal. | Provision a real cluster; check ACK convergence, authenticate to its Kubernetes API, see managed nodes Ready, schedule a workload, test network and teardown. |
| Cloud identity | Moto CARM accounts and mock keys; prod retention tested in memory. | [Pod Identity](https://docs.aws.amazon.com/eks/latest/userguide/pod-identities.html) or an approved role-based credential path, real cross-account trust, durable resources and audited adoption. |
| Spoke registration | 30-day Kubernetes ServiceAccount tokens in Argo CD Secrets. | IAM principals with [EKS access entries](https://docs.aws.amazon.com/eks/latest/userguide/access-entries.html), scoped authorization and rotation-free authentication. |
| Git/change control | Immutable chart-version guard; required PR checks for prod input repos; zero mandatory approvers. | Enforced independent approval, provenance for signed charts and images, immutable promotion and separation of duties. |
| Isolation | Tenant workload policies and restricted Pod Security; broad Namespace patch for the IaC deployer; no quotas. | Per-tenant namespace/account policy, quotas, constrained Namespace ownership, private control-plane/network paths. |
| Secrets and audit | Script-created Kubernetes Secrets, loopback HTTP SSO, no local API audit log. | Managed secret and role lifecycle, TLS end to end, EKS control-plane [audit log export](https://docs.aws.amazon.com/eks/latest/userguide/control-plane-logs.html), and verified encryption/key policy. |
| Operations | 21 local alert rules, 27 smoke assertions, tested rebuild; readiness alerts rely on probe series existing. | Alert on exporter absence and reconciliation failure, routed on-call response, durable telemetry, tested backup/adoption and multi-AZ failure drills. |

## 6. Onboarding and Learnability Score

**7.4/10.** The README architecture, runbooks, six CI pipelines, P0–P5 reports and Bats gates make the system unusually inspectable for a learning lab. A newcomer can reproduce and test the five original repository flows. The new `tenant-iac` path is documented in its own runbook but missing from the first-page repository map and `make push` description. The term “team EKS cluster Ready” also needs an adjacent explanation that Moto supplies only a mock EKS record. Update those two entry points first; then add a one-page “request → claim → kro graph → ACK/Moto → metrics” map with the relevant file and command at each step.

## 7. Final Architect's Verdict

This is a strong platform learning environment. The previous assessment's most urgent GitOps integrity holes were closed, and the new team-cluster path shows how infrastructure requests can share the same GitOps contract and policy model as application requests. The current green state is well supported by a clean rebuild record, live controller state, 27 passing smoke assertions and CI. The next improvement is to make the platform's signals scale with new tenants and to tighten the Namespace mutation boundary. Then use the Phase 6 AWS spike to prove a real Kubernetes cluster, with real identity and audit controls, before treating Moto `ACTIVE` as production readiness.

### Evidence and limits

- Live commands sampled Kubernetes, Argo CD, Moto-backed ACK conditions, Prometheus, Docker port bindings and GitHub effective branch rules. No real AWS account was queried or modified.
- Bats Gate 9 sent disposable order markers through Moto; all three environments processed them. The assessment did not perform a new teardown, cloud deletion, alert fault injection or live IAM denial test.
- The working tree had a pre-existing untracked `scripts/grok/` directory, which was left untouched.
