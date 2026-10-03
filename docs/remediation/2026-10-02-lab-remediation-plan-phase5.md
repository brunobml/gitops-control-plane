# Lab Remediation Plan: Phase 5 — Observability, Self-Healing Operations & Residual-Risk Closure
## Hub-and-Spoke GitOps Control Plane (2026-10-02)

* **Plan Version:** 1.1 (v1.0 approved and implemented for Tracks 0–D; **v1.1 adds Track F, log aggregation**)
* **Assessment Reference:** [`../assessments/2026-09-30-lab-assessment.md`](../assessments/2026-09-30-lab-assessment.md)
* **Phase 4 Baseline:** [`2026-10-02-lab-remediation-plan-phase4-validation-05.md`](2026-10-02-lab-remediation-plan-phase4-validation-05.md) and [`…-phase4-crosscheck-05.md`](2026-10-02-lab-remediation-plan-phase4-crosscheck-05.md) (Phase 4 complete; full rebuild accepted)
* **Target Repositories:** `gitops-control-plane`, `platform-catalog`, `tenant-workloads`
* **Author:** Claude (Opus 5.5)

---

## Review & Approval Sign-Off

| Field | Details |
|---|---|
| **Current Status** | 🟢 **COMPLETED & ACCEPTED (Full Cold-Start Rebuild Validated)** |
| **Plan Version** | `v1.1` (commit [`f11e0eb`](https://github.com/brunobml/gitops-control-plane/commit/f11e0eb)) |
| **Author** | Claude (Opus 5.5) |
| **Reviewed & Validated By** | Antigravity (Advanced Agentic AI Peer Reviewer) |
| **Review / Completion Date** | 2026-10-02 |
| **Authorization Decision** | ✅ **GREEN LIGHT** — Fully approved, implemented, and validated across all sequenced tracks (§11). |
| **Validation Reports** | [`validation-01.md`](2026-10-02-lab-remediation-plan-phase5-validation-01.md) (Tracks 0/A) · [`validation-02.md`](2026-10-02-lab-remediation-plan-phase5-validation-02.md) (Track B) · [`validation-03.md`](2026-10-02-lab-remediation-plan-phase5-validation-03.md) (Track C) · [`validation-04.md`](2026-10-02-lab-remediation-plan-phase5-validation-04.md) (Track D) · [`validation-05.md`](2026-10-02-lab-remediation-plan-phase5-validation-05.md) (Track F) · [`validation-06.md`](2026-10-02-lab-remediation-plan-phase5-validation-06.md) (Track E Rebuild Acceptance) |
| **Track E Rebuild Acceptance** | 🟢 **PASSED**: Validated in [`validation-06.md`](2026-10-02-lab-remediation-plan-phase5-validation-06.md); 8m15s zero-touch rebuild; 32/32 Synced/Healthy; smoke 12/12 PASS. |
| **Execution / validation split** | Each step is executed and reported (`implemented-NN`) by one party and validated (`validation-NN`) by the other. All 6 implementation runs have corresponding independent validation reports. |

### Reviewer Decision & Feedback

> ### ✅ REVIEW VERDICT: APPROVED (GREEN LIGHT)
>
> The Phase 5 remediation plan is architecturally disciplined, appropriately right-sized for a local multi-cluster lab, and directly attacks the remaining operational friction points identified in Phases 3 and 4:
>
> 1. **Right-Sized Observability (Track A):** The explicit rejection of heavyweight operators (`kube-prometheus-stack`) and log aggregation (Loki) in favor of core `prometheus-community/prometheus` (hub server + spoke agent mode with remote-write) respects the local developer host constraints (< 1.5 GiB delta) while providing cross-cluster visibility. Native OIDC integration for Grafana with Keycloak extends the SSO boundary established in Phase 4.
> 2. **Proactive Failure Detection (Track B):** The alerting strategy focuses on verified historical failure modes (F-1 silent SQS processing failure, D-10 Kyverno fail-open, PV2-5 token expiration, Argo CD sync drift). The synthetic e2e order probe and token-expiry exporter provide blackbox assurance without bloating tenant application code.
> 3. **Kyverno High Availability (Track C):** Scaling Kyverno admission controllers to 2 replicas backed by a PDB (`minAvailable: 1`) prevents webhook fail-open windows during rolling updates, while `KyvernoDown` monitors the zero-replica failure case.
> 4. **Self-Healing Operations (Track D):** Idempotent orphan discovery and automated 7-day spoke token renewal eliminate repetitive manual maintenance chores while preserving break-glass isolation and safeguarding persistent tenant data.
>
> ### ✅ v1.1 AMENDMENT VERDICT (TRACK F): APPROVED (GREEN LIGHT)
>
> The Track F amendment directly addresses the core operational requirement for post-mortem log retention (querying logs of terminated/evicted pods) and natively integrates with Grafana 13's *Drilldown → Logs* workflow:
>
> 1. **Right-Sized Log Ingestion (Step F.1):** Selecting `grafana-community/loki` SingleBinary with local filesystem TSDB on a 5 GiB PVC completely eliminates external object storage (MinIO/S3) complexity and operator overhead.
> 2. **Zero-HostPath Architecture (Step F.2):** Deploying Grafana Alloy as a single Deployment streaming via the Kubernetes API (`pods/log` and `events`) avoids privileged daemonsets, security context escalation, and `hostPath` volume bindings on k3d nodes.
> 3. **Consistent Security Boundary:** Extending Traefik basic-auth Middleware on `k3d-hub-cluster-serverlb` for `/loki/api/v1/push` mirrors the proven Prometheus remote-write architecture (R-1), keeping all ingestion authenticated and internal.
> 4. **Pod Security Governance (Step F.0):** Addressing the unlabelled `monitoring` namespace (finding F14) brings observability namespaces into compliance with the platform Pod Security standard.
>
> **All tracks (Track 0–D complete; Track F authorized) are approved.** The operational guardrails below govern execution.

| ID | Focus Area | Reviewer Remark & Operational Guardrail | Status |
|:---:|:---:|---|:---:|
| **R-0** | Step A.3 (Scrapes) | **Controller Deployment Naming:** Note that the ACK SQS controller deployment on spokes is named `ack-sqs-controller-sqs-chart` in namespace `ack-system` (F2). Ensure Prometheus scrape configs and pod discovery target the actual deployment/pod labels. | 🛡️ Guardrail Approved |
| **R-1** | Step A.1 / A.3 | **Basic Auth Secret Isolation:** Remote-write credentials generated for spoke Prometheus agents must remain strictly in `~/.config/gitops-lab/` (mode 600) and injected via out-of-band secret creation or local templating. Plaintext credentials must never be committed to Git. | 🛡️ Guardrail Approved |
| **R-2** | Step C.1 | **Kyverno PDB Safety:** When scaling Kyverno to 2 replicas on spokes (Track C), ensure the PDB specifies `minAvailable: 1` and nodes have sufficient allocatable resources before applying Enforce policies. | 🛡️ Guardrail Approved |
| **R-3** | Step B.2 | **Synthetic Probe Isolation:** Blackbox and synthetic order probes (Track B) must run in isolated namespaces (`platform-probes`) with strict egress NetworkPolicies restricting traffic to Moto and spoke Traefik only. | 🛡️ Guardrail Approved |
| **R-4** | Step A.3a / C.1a | **Spike Before Wide Promotion:** Rigorously execute Spike A.3a (verifying Prometheus v3.15 agent mode flags and metric endpoints) and Spike C.1a (verifying 2-replica Kyverno behavior during pod termination) prior to wide catalog promotion. | 🛡️ Guardrail Approved |
| **R-5** | Step F.2 (Alloy Tail) | **API Server Stream Rate-Limiting:** Because Alloy tails pod logs via the Kubernetes `pods/log` API rather than host filesystem tailing, ensure scrape configs filter out chatty high-frequency probes or self-logs to minimize control-plane overhead. | 🛡️ Guardrail Approved |
| **R-6** | Step F.1 (Loki SingleBinary) | **Single-Replica Concurrency Safety:** In `deploymentMode: SingleBinary` with local filesystem storage and compactor enabled, strictly maintain `replicas: 1` to prevent concurrent write locks on the shared PVC volume. | 🛡️ Guardrail Approved |
| **R-7** | Step F.1 / F.2 (Push Auth) | **Loki Basic Auth Secret Isolation:** Spoke Alloy push credentials must follow Remark R-1: generated securely into `~/.config/gitops-lab/` (mode 0600) and mounted as Secrets without plaintext in Git. | 🛡️ Guardrail Approved |
| **R-8** | Step F.0 (PSS Labeling) | **Monitoring PSS Calibration:** Perform server dry-run validation (`--dry-run=server`) on all three clusters before applying PSS labels to `monitoring` to ensure Prometheus, Alertmanager, Grafana, and Alloy are not rejected. | 🛡️ Guardrail Approved |

### Owner decisions requested

| ID | Question | Author's recommendation | Reviewer Endorsement |
|---|---|---|:---:|
| **O-1** | Where should alerts go? | **Lab-local only**: Alertmanager UI plus a Grafana "Firing alerts" panel. No external service, no new credentials. An external channel (e-mail, ntfy, Slack) can be added later as one receiver | **Endorsed** |
| **O-2** | Who may open Grafana? | Both SSO groups: `lab-platform-admins` → Grafana **Admin**, `lab-tenant-a` → **Viewer**. Same pattern as Headlamp in Phase 4 | **Endorsed** |
| **O-3** | Clean-up of deregistered tenant apps (Phase 4 D-16) | **Automatic** for credentials (IAM user + Secret) and the empty namespace. **Report only** for data (DynamoDB tables), deleted only with an explicit `PRUNE_DATA=1` | **Endorsed** |
| **O-4** | Token renewal | **Automatic** in `make post-bootstrap` when a spoke or Headlamp token has fewer than 7 days left. You already run it after every `make start` | **Endorsed** |
| **O-5** | End-of-phase rebuild acceptance (Track E) | **Yes**, in an owner-approved window; executed and validated by different parties | **Endorsed** (runs after Track F) |

### v1.1 Amendment summary (2026-10-02)

| | |
|---|---|
| **Trigger** | Owner, after the Phase 5 Grafana acceptance: *"if the pod goes away I cannot see the logs anyways, so having Loki and Alloy would bring me more close to real life"*. Grafana 13's *Drilldown → Logs* also expects a Loki data source |
| **Change** | Move **log aggregation** from out-of-scope (§1.2) into scope as **Track F** (§7a), executed **before** Track E so the final rebuild proves logging from Git as well |
| **Also in F** | **F.0**: Pod Security labels for the Phase 5 `monitoring` namespaces (gap found in the v1.1 pre-flight: they have none, unlike every other platform namespace) |
| **New owner decisions** | O-6 (who may read logs), O-7 (retention) |
| **Unchanged** | Tracks 0–D, remarks R-0..R-4, owner decisions O-1..O-5 |

#### Owner decisions requested (v1.1)

| ID | Question | Author's recommendation | Reviewer Endorsement |
|---|---|---|:---:|
| **O-6** | Loki in this design has no per-tenant isolation: anyone who can open Grafana can query **all** namespaces' logs (platform namespaces included). Accept for the lab? | **Accept** as a recorded residual. It matches the lab preference "I need to see everything"; `tenant-a-user` is Viewer. Restricting it later = Loki multi-tenancy (`X-Scope-OrgID` per tenant) plus a per-team data source | **Endorsed** (documented lab residual) |
| **O-7** | Log retention | **7 days** (same as metrics); compactor-enforced, 5 GiB volume | **Endorsed** (matches metrics retention) |

---

## 1. Executive Summary & Scope

Phases 1–4 made the lab secure, reproducible from Git, and trustworthy in what it runs. Two operational weaknesses remain, and both were shown live during Phases 3 and 4:

1. **Silent failures go unnoticed until someone runs `make test`.** Examples: worker credentials lost after a moto restart (F-1, all environments silently stopped processing orders), an expiring token, Kyverno stopped (Phase 4 D-10).
2. **Recurring manual chores:** token rotation every 30 days, and clean-up after a tenant deregisters an app (Phase 4 D-16).

Phase 5 adds **lightweight, SSO-protected observability** with alerts for exactly the failures we have seen, and turns the manual chores into idempotent automation.

### 1.1 Objectives

| Track | Theme | Findings / residuals addressed |
|---|---|---|
| **0** | Housekeeping | legacy tenant files (Phase 4 C.2 note), alert-rule naming conventions |
| **A** | Observability (hub Prometheus + Grafana, spoke agents, blackbox probes) | **L3-3** (no metrics or alerting; deferred since Phase 3) |
| **B** | Alerts for known failure modes | F-1 (silent processing outage), D-10 (Kyverno down), PV2-5 (token expiry), Argo CD drift and health |
| **C** | Kyverno resilience | **D-10** (graceful stop fails open) |
| **D** | Self-healing operations | **D-16** (deregistration residue), token renewal (PV2-5 recurrence) |
| **E** | Acceptance | full rebuild with the observability stack in the build path |

### 1.2 Out of scope (deferred, with reasons)

| Item | Reason |
|---|---|
| kube-prometheus-stack (Prometheus Operator, node-exporter, full dashboards) | Too heavy for the laptop lab and pulls in a CRD-based operator. The plain Prometheus chart with config-file rules covers the needs |
| ~~Logs aggregation (Loki)~~ | *v1.1: moved into scope as Track F (owner request: logs of pods that no longer exist)* |
| TLS on lab UIs | Unchanged Phase 4 residual (loopback only, `*.localhost` secure context) |
| Renovate / automated digest bumps | Needs a GitHub App or token outside the lab (owner action); can be added later |
| Argo CD HA, EKS translation | Beyond lab parity goals |
| Application-level metrics in `orders-processor` | The F-1 class of failure is caught by a synthetic end-to-end probe (B.2) without changing the app |

---

## 2. Pre-flight Facts (verified live on 2026-10-02 by the author)

| # | Fact | Evidence | Used by |
|---|---|---|---|
| F1 | No metrics stack. No ServiceMonitor CRD; Argo CD has **no metrics Services** (chart `*.metrics.enabled` false), although every component exposes a metrics port (controller 8082, server 8083, repo-server 8084, applicationset 8080, notifications 9001) | `get crd`, pod ports | A.2 |
| F2 | Spoke controllers expose metrics on pod ports: kro `8078` (`--metrics-bind-address`), ACK `8080`, Kyverno Service `kyverno-svc-metrics:8000` | pod specs, Services | A.3 |
| F3 | **Spokes reach the hub** through the k3d network: spoke CoreDNS has `k3d-hub-cluster-serverlb` (172.21.0.4); an HTTP request from a spoke pod to it returned 200 | live test from `spoke-nonprod` | A.3 |
| F4 | Charts: `prometheus-community/prometheus` **29.35.0** (Prometheus v3.15.0), `grafana/grafana` **10.5.15** (12.3.1), `prometheus-community/prometheus-blackbox-exporter` **11.19.1** (v0.28.0) | `helm search` | A.1–A.4 |
| F5 | Host: 31 GiB RAM, about 21 GiB available; lab uses about 5.8 GiB | `free`, `docker stats` | sizing |
| F6 | Kyverno: 1 admission-controller replica, no PDB, on both spokes; a graceful scale-to-0 deletes its webhook configurations (fails open), an unreachable Kyverno with webhooks present fails closed | Phase 4 W13 / D-10 | C.1 |
| F7 | Spoke and Headlamp tokens are 30-day TokenRequest tokens with annotation `lab/token-expires` (now 2026-11-01). `make rotate-spoke-tokens` renews them idempotently | cluster Secrets, Makefile | D.2 |
| F8 | Keycloak realm `lab` is code in Git (`addons/keycloak/realm-lab.json`), with secrets as `${ENV}` placeholders, so a new SSO client (Grafana) is a Git change plus one generated secret | Phase 4 A.3 | A.4 |
| F9 | `post-bootstrap.sh` already discovers tenant workloads from `tenant-workloads` registrations (Phase 4 C.2), so orphans can be computed as "exists but not registered" | script | D.1 |

---

### 2.1 Pre-flight facts for v1.1 (verified 2026-10-02)

| # | Fact | Evidence | Used by |
|---|---|---|---|
| F10 | **`grafana/loki` is enterprise-only now.** Since 2026-03-16 the OSS Loki chart is `grafana-community/loki` (**18.13.7**, Loki **3.7.8**); `grafana/loki` 7.3.0 is maintained for GEL only (chart README) | `helm show readme` | F.1 |
| F11 | A minimal **SingleBinary** Loki (filesystem storage, no gateway, caches, canary or MinIO) renders to 1 StatefulSet + Services; it adds a `k8s-sidecar` for rules (can be disabled) | `helm template` | F.1 |
| F12 | `grafana/alloy` **1.13.0** (Alloy **v1.20.0**) is maintained; as a `controller.type: deployment` it renders one Deployment + RBAC; the chart's config-reloader runs as 65534/non-root, the Alloy container's securityContext is empty by default | `helm template` | F.2 |
| F13 | Alloy can tail pod logs **through the Kubernetes API** (`loki.source.kubernetes`) and collect **events** (`loki.source.kubernetes_events`): no hostPath, no privileged pod, no DaemonSet needed at lab scale | Alloy components | F.2 |
| F14 | The Phase 5 **`monitoring` namespaces have no Pod Security labels** (hub and spokes); `platform-probes`, `keycloak` and tenant namespaces do | `get ns --show-labels` | F.0 |

## 3. Track 0: Housekeeping

### Step 0.1: Legacy tenant files
Remove `tenant-workloads/tenants/tenant-a/{dev,test,prod}/orders-service.yaml` (pre-platform `MessageProcessor` examples, old local registry, not deployed) and update `tenants/README.md`. This avoids confusing them with real registrations.

### Step 0.2: Conventions
Alert rules, dashboards and probes live as code under `addons/observability/`. Every alert has a `runbook` annotation that points to a section of `docs/runbooks/host-reboot-and-cluster-lifecycle.md`.

---

## 4. Track A: Observability

**Target design**

```
spoke-nonprod / spoke-prod                          hub
┌──────────────────────────────┐   remote_write   ┌──────────────────────────────────────────┐
│ Prometheus (agent mode)      │ ───────────────► │ Prometheus server (rules, 7 d retention)  │
│  scrapes kro, ACK, Kyverno,  │  k3d network,    │  + remote-write receiver (auth required)  │
│  kube-state-metrics, kubelet │  basic auth      │  + Alertmanager (UI, O-1)                 │
└──────────────────────────────┘                  │  + kube-state-metrics, Argo CD metrics    │
                                                  │  + blackbox-exporter (synthetic probes)   │
browser ── SSO (Keycloak) ──► Grafana ───────────►│  Grafana: dashboards + alert list as code │
                                                  └──────────────────────────────────────────┘
```

### Step A.1: Hub Prometheus + Alertmanager (GitOps addon)
* Application `addon-prometheus` (project `control-plane`), chart `prometheus` 29.35.0, images digest-pinned.
* Enabled: `server` (7-day retention, 2 GiB PVC on local-path, `--web.enable-remote-write-receiver`), `alertmanager`, `kube-state-metrics`. Disabled: `prometheus-node-exporter` (k3d nodes are containers on one kernel), `pushgateway`.
* Requests about 400 MiB in total.
* The remote-write endpoint is exposed through a Traefik Ingress on host `k3d-hub-cluster-serverlb`, which is the name spokes use (F3), behind a **basic-auth Middleware**: one credential per spoke, generated into `~/.config/gitops-lab/` by a setup script and never in Git.
* Prometheus and Alertmanager UIs (`prometheus.localhost`, `alertmanager.localhost`) sit behind the existing **oauth2-proxy ForwardAuth** (Phase 4 A.5 pattern), allowed group `lab-platform-admins`.

### Step A.2: Argo CD metrics
`clusters/values-argocd-hub.yaml` sets `metrics.enabled: true` for controller, server, repo-server, applicationset and notifications. That's Services only, no ServiceMonitors (F1). Hub Prometheus scrapes them through Kubernetes service discovery. Applied by commit plus manual `argo-cd` sync, as Phase 3 D-32 requires.

### Step A.3: Spoke agents (GitOps addon on spokes)
* ApplicationSet `addons-spoke-observability` (Go template, cluster generator on `addons-managed=true`): chart `prometheus` with `server` in **agent mode** (no local storage or rules), `kube-state-metrics` on, everything else off.
* Scrape jobs: kro pods `:8078`, ACK pods `:8080`, Kyverno `kyverno-svc-metrics:8000`, kube-state-metrics, kubelet/cAdvisor. Every series gets external label `cluster=<spoke>`.
* `remote_write` → `http://k3d-hub-cluster-serverlb/api/v1/write` with the spoke's basic-auth credential (Secret created by the setup script on each spoke).
* Values live in `platform-catalog/controllers/observability/` at the cluster's `blueprints-revision`, so the promotion gate applies: nonprod first, prod with the next catalog tag.
* **Spike first (A.3a, read-only):** confirm that the chart's agent mode (`server.extraFlags: [agent]` or the chart's equivalent) produces a valid agent config with Prometheus v3.15, and check the real kro and ACK metric names before rules depend on them.

### Step A.4: Grafana with Keycloak SSO
* Application `addon-grafana`, chart 10.5.15, digest-pinned, Ingress `grafana.localhost`.
* Native OIDC (`auth.generic_oauth`) against realm `lab`, with a new confidential client `grafana` in `realm-lab.json`. Its secret is a `${…}` placeholder generated by `setup-keycloak-secrets.sh`.
* Role mapping per O-2 via `role_attribute_path` on the `groups` claim. Local Grafana admin is kept as break-glass, with its password in `~/.config/gitops-lab/`.
* Lessons from Phase 4 applied from the start:
  * callback URL registered per host;
  * `signout_redirect_url` → Keycloak end-session, so users can switch;
  * test login **through Grafana's own endpoints**, not only against the IdP.
* Datasource (hub Prometheus) and dashboards provisioned from ConfigMaps (dashboards as code):
  1. **Platform overview**: Argo CD apps by sync and health, cluster connection, controller up/restarts per spoke.
  2. **Tenant workloads**: kro instance states, worker restarts, synthetic order latency (B.2).
  3. **Supply chain**: Kyverno admission requests, denials and latency (the Phase 4 D-8 timeout issue becomes visible).

### Step A.5: Synthetic probes
`prometheus-blackbox-exporter` 11.19.1 on the hub probes:
* HTTP 200 for Argo CD, Keycloak discovery, Headlamp (expects **302** to Keycloak), Grafana;
* each tenant dashboard through its spoke load balancer (`Host: <app>-<env>.localhost`);
* moto `:5000`.

---

## 5. Track B: Alerts for Known Failure Modes

Rules live in Prometheus config, as code in `addons/observability/rules/`. Each has `severity`, `summary` and `runbook`. Every alert is **tested by causing its failure** (§9).

| Alert | Expression (sketch) | Catches | Seen in |
|---|---|---|---|
| `ArgoAppDegraded` | `argocd_app_info{health_status!="Healthy"}` for 10m | broken sync or app | all phases |
| `ArgoAppOutOfSync` | `argocd_app_info{sync_status="OutOfSync"}` for 30m, excluding `argo-cd` (manual sync by design) | drift, retry exhaustion | Phase 3 R3 |
| `ArgoClusterUnreachable` | `argocd_cluster_connection_status == 0` for 5m | expired token, Docker IP reshuffle (Issue E) | Phase 3 |
| `SpokeTokenExpiringSoon` | probe on a tiny **expiry exporter** (B.1) < 7 days | PV2-5 before it bites | Phase 2/3 |
| `KyvernoDown` | `up{job="kyverno"} == 0` (per spoke) for 2m | **D-10 fail-open window** | Phase 4 |
| `KyvernoSlowAdmission` | p95 admission latency > 15 s | D-8 timeout risk | Phase 4 |
| `SpokeControllerDown` | `up{job=~"kro|ack-sqs"} == 0` for 5m | controller crash (e.g. Issue E agent cross-wire) | Phase 3 |
| `OrdersNotProcessed` | synthetic e2e probe (B.2) failing for 10m | **F-1 silent processing outage** | Phase 3 |
| `ProbeFailed` | `probe_success == 0` for 5m (A.5 targets) | UI, IdP or moto down | — |
| `MotoRestarted` | moto uptime reset (blackbox target change or `process_start_time`) | trigger to run `make post-bootstrap` | F-1 |

### Step B.1: Token-expiry exporter
A minimal **exporter on the hub**: one small Deployment running a short Python script from a ConfigMap, on the digest-pinned `python:3.11-alpine` base already used by `orders-processor`. It has a read-only Role on the cluster Secrets in `argocd` and on the Headlamp kubeconfig Secret. Every 10 minutes it computes `lab_token_expiry_timestamp_seconds{credential=…}` from the `lab/token-expires` annotations and the JWT `exp` claims, and serves it on `/metrics` for hub Prometheus to scrape. No secret values leave the pod; only expiry timestamps are exported.

### Step B.2: Synthetic order probe (F-1 class)
* A small exporter Deployment per spoke (same pattern as B.1, scraped by the spoke agent). It loops every 5 minutes using a dedicated **probe identity** (IAM role `smoke-test` in the namespace's account, as smoke stage 9 does).
* It sends a marker message to each registered tenant queue and checks that the dashboard shows it. Registered queues are discovered from the namespace label and QueueBackedService.
* It exports `lab_order_e2e_success{namespace}` and `lab_order_e2e_seconds{namespace}`, which drive `OrdersNotProcessed`.
* Kept outside tenant namespaces: probe namespace `platform-probes`, NetworkPolicy egress to moto and the spoke Traefik only.

---

## 6. Track C: Kyverno Resilience (D-10)

### Step C.1: Two replicas + PDB
* `admissionController.replicas: 2` and `podDisruptionBudget` (minAvailable 1) in `platform-catalog/controllers/kyverno`.
* Promoted nonprod first, then prod with a catalog tag.
* **Spike first (C.1a):** with 2 replicas, confirm that a graceful stop or rolling restart of **one** replica leaves the webhook configurations in place, and that admission keeps working throughout.

### Step C.2: Residual after C.1
Scaling Kyverno to 0 still removes its webhooks; that's Kyverno's own design. `KyvernoDown` (B) turns that window from silent into alerted. Recorded as an accepted, monitored residual.

---

## 7. Track D: Self-Healing Operations

### Step D.1: Deregistration clean-up (D-16)
`post-bootstrap.sh` gets a new step **"orphans"** that compares what exists with what is registered (F9):

| Orphan | Detection | Action (O-3) |
|---|---|---|
| Worker IAM user in account 111…/222… with no registered workload | moto IAM `*-worker` users vs registrations | **delete** (keys, policies, user) |
| `<name>-<env>-aws` Secret in a namespace without a registration | Secrets vs registrations | **delete** |
| Tenant namespace (`platform.lab/image-verification=enabled`) without an Application and with no remaining workload | namespaces vs Applications | **delete** if empty of Deployments, Pods and QueueBackedServices; otherwise report |
| DynamoDB `<name>-<env>-history` table without a registration | moto tables vs registrations | **report**; delete only with `PRUNE_DATA=1` |

Safety:
* The step never touches the three Phase 1–4 environments while they are registered.
* It runs only after discovery succeeded with at least one registration.
* A dry-run listing is printed before any deletion.
* `make orphans` runs the report alone.

### Step D.2: Automatic token renewal (O-4)
* `post-bootstrap.sh` checks `lab/token-expires` and the Headlamp token `exp`.
* With fewer than **7 days** left, it runs `register-spokes.sh` and `addons/headlamp/setup-credentials.sh` (= `make rotate-spoke-tokens`), then verifies cluster connections. Otherwise it reports the days left.
* Smoke stage 8 (warning at 7 days) and `SpokeTokenExpiringSoon` stay as the safety net.

### Step D.3: Runbook alignment
Every alert's `runbook` annotation resolves to a section. New sections cover `OrdersNotProcessed` (→ `make post-bootstrap`, Issue F), `KyvernoDown`, `ArgoClusterUnreachable` (→ Issues B and E) and `SpokeTokenExpiringSoon`.

---

## 7a. Track F: Log Aggregation (v1.1)

**Target design**

```
every cluster (hub, spoke-nonprod, spoke-prod)                hub
┌─────────────────────────────────────────────┐  push     ┌────────────────────────────────────────┐
│ Alloy (1 Deployment, non-root, no hostPath) │ ────────► │ Loki SingleBinary (monitoring)          │
│  pod logs   via Kubernetes API (pods/log)   │  spokes:  │  filesystem TSDB, 7 d retention (O-7)   │
│  K8s events via Kubernetes API (events)     │  basic    │  no UI ingress; push path only          │
│  labels: cluster, namespace, pod, container │  auth     │ Grafana: Loki datasource (SSO), links   │
└─────────────────────────────────────────────┘           └────────────────────────────────────────┘
```

### Step F.0: Pod Security for `monitoring` (gap F14)
Label `monitoring` on all three clusters at the strictest level its pods pass (`restricted` where possible, otherwise `baseline` with the reason recorded). The setup script and the Argo CD Applications (`managedNamespaceMetadata`) keep the labels after a rebuild. Verify with `kubectl label --dry-run=server` warnings before enforcing.

### Step F.1: Loki on the hub
* Application `addon-loki`, chart **`grafana-community/loki` 18.13.7**, `deploymentMode: SingleBinary`, filesystem storage on a 5 GiB PVC, `auth_enabled: false` (single tenant, O-6).
* Retention 7 days through the compactor (O-7).
* Gateway, caches, canary, MinIO and the rules sidecar disabled. Images digest-pinned.
* Ingress: **only** `/loki/api/v1/push` on host `k3d-hub-cluster-serverlb`, behind a basic-auth Middleware. Same pattern as remote write; credentials per spoke from `setup-observability-secrets.sh`, outside Git.
* NetworkPolicy: Loki is reachable from Traefik (push), Grafana, the hub Alloy and Prometheus (metrics) only.

### Step F.2: Alloy on every cluster
* Hub: Application `addon-alloy`. Spokes: ApplicationSet `addons-spoke-logging` (label `observability=enabled`), values in `platform-catalog` (promotion gate, nonprod first).
* `controller.type: deployment`, 1 replica, non-root, read-only root FS. RBAC limited to `get/list/watch` on pods, `pods/log`, namespaces, events.
* Components: `loki.source.kubernetes` (pod logs) and `loki.source.kubernetes_events`, labelled `cluster`, `namespace`, `pod`, `container`, `app`. `loki.write` goes to the hub (spokes with basic auth from a mounted Secret; the hub writes in-cluster).
* **Drop noisy or sensitive streams**: Alloy's own logs, and kube-system debug noise if volume demands it. The `orders-processor` worker does not log credentials; that is checked once in F.5 by a search for `AWS_SECRET`/`password` patterns.

### Step F.3: Grafana
* Loki datasource (provisioned, `uid: loki`), so *Drilldown → Logs* works.
* Dashboard links: from *Platform overview* and the tenant panels to Explore with `{cluster="…", namespace="…"}`.
* Alert annotations get a `logs` link for `OrdersNotProcessed`, `KyvernoDown`, `SpokeControllerDown` and `ArgoAppDegraded`.
* A small *Events* panel: the last Kubernetes warnings per cluster (OOMKilled, BackOff, FailedCreate). Today's Grafana OOM would have been visible there.

### Step F.4: Alerts
* `LogsMissing`: a cluster sent no log lines for 15 min.
* `LokiDown`: Loki scrape target down for 5 min.
* `LokiIngestionErrors`: push errors on the Alloy side, from Alloy's metrics scraped by the agents.
* Unit tests added to `make test-alert-rules`; live fire tests in F.5.

### Step F.5: Acceptance tests (Track F)
* Logs of a **deleted pod** are still queryable.
* Events show a provoked OOMKill / CrashLoop.
* The push endpoint refuses wrong credentials.
* `tenant-a-user` (Viewer) can query logs (O-6 residual demonstrated).
* No secret patterns in a 1-hour sample.
* Footprint measured.
* Smoke: stage 12 also checks that the hub has log lines from all three clusters in the last 10 min.

## 8. Track E: Acceptance

### Step E.1: Full rebuild (O-5)
*v1.1: Track E runs **after** Track F; the rebuild must also restore logging (log lines from all three clusters, Loki datasource in Grafana).*

* `make teardown → setup → bootstrap → post-bootstrap` with the observability stack in the build path.
* **Expected:**
  * all Applications Synced/Healthy (count recorded: about 22 + 4–5 new);
  * smoke 11/11 plus a new **stage 12 (observability)**: hub has series from both spokes, no unexpected firing alerts, Grafana SSO entry point reaches the Keycloak login form;
  * every alert in §5 shown firing during its §9 test and resolved afterwards.
* Executed and validated by different parties.

---

## 9. Verification Matrix

| # | Area | Test (cause the failure) | Expected |
|---|---|---|---|
| X1 | Data path | query `up` per `cluster` label | hub, spoke-nonprod, spoke-prod series present |
| X2 | Remote-write auth | write without / with wrong credential | 401 |
| X3 | UI protection | Prometheus, Alertmanager, Grafana unauthenticated | 302 to Keycloak |
| X4 | Grafana SSO | both users through Grafana's own login and logout | Admin / Viewer; logout allows a user switch |
| X5 | `ArgoAppOutOfSync` | manual drift on a test app (self-heal paused) | fires, then resolves |
| X6 | `ArgoClusterUnreachable` | stop a spoke serverlb briefly | fires; resolves after restart |
| X7 | `SpokeTokenExpiringSoon` | exporter fed a test annotation < 7 d on a throwaway Secret | fires |
| X8 | `KyvernoDown` | scale Kyverno to 0 on nonprod (Argo CD controller paused, as in Phase 4) | fires within 2–3 min |
| X9 | `OrdersNotProcessed` | delete the worker key in moto (reproduces F-1) | fires; `make post-bootstrap` resolves it |
| X10 | `ProbeFailed` | stop moto briefly | fires; resolves |
| X11 | Kyverno HA | rolling restart and graceful stop of 1 of 2 replicas | webhooks remain; signed pod admitted, unsigned denied throughout |
| X12 | Orphans | register → deregister a demo app, run `post-bootstrap` | IAM user, Secret, empty namespace removed; table reported; registered apps untouched |
| X13 | Token renewal | set `lab/token-expires` to tomorrow on one spoke | `post-bootstrap` rotates; connection Successful; smoke stage 8 green |
| X14 | Footprint | `docker stats` before and after | increase recorded (target < 1.5 GiB) |
| X15 | Rebuild | E.1 | all green; time recorded |
| X16 | Regression | Phase 4 W1–W17, smoke 11/11 | unchanged |

---


**v1.1 additions (Track F)**

| # | Area | Test (cause the failure) | Expected |
|---|---|---|---|
| X17 | PSS | `monitoring` namespaces labelled; dry-run admission of every monitoring pod | no violations at the chosen level |
| X18 | Deleted pod | delete a pod after it logged a marker, then query Loki | marker still found (owner's use case) |
| X19 | Events | provoke an OOMKill / CrashLoop in a scratch namespace | event visible in Loki / Grafana *Events* panel |
| X20 | Push auth | push without / with wrong credential to `/loki/api/v1/push`; query path on the same host | 401 / 401 / 404 |
| X21 | Viewer access (O-6) | `tenant-a-user` queries a platform namespace's logs | allowed (documented residual) |
| X22 | Secret hygiene | search 1 h of logs for credential patterns | none found |
| X23 | Log alerts | stop a spoke's Alloy; stop Loki | `LogsMissing` / `LokiDown` fire and resolve |
| X24 | Footprint | `docker stats` / `kubectl top` before and after | increase recorded (target < 600 MiB working set) |

## 10. Risk Register & Rollback

| Risk | Likelihood | Impact | Mitigation / Rollback |
|---|:-:|:-:|---|
| Agent-mode or metric names differ from assumptions | Med | Low | Spike A.3a before rules depend on them |
| Remote-write endpoint reachable from the host without auth | Low | Low | Basic auth on the Ingress; host ports stay on 127.0.0.1 (Phase 3 A.1) |
| Alert noise (flapping, e.g. kube-router policy gaps after restarts) | Med | Low | `for:` windows; every alert tested; tuning documented |
| Prometheus PVC lost on rebuild | High (by design) | Low | Monitoring data is not authoritative; 7-day retention only |
| Orphan clean-up deletes something registered | Low | High | Runs only after successful discovery; dry-run listing; data deletion opt-in; registered names excluded explicitly; tested with a demo app first |
| Automatic token renewal fails mid-way | Low | Med | `register-spokes.sh` verifies each spoke before removing anything (Phase 3 G8 logic); smoke stage 8 still warns |
| Grafana SSO repeats a Phase 4 defect (redirect, logout, stale session) | Med | Low | Phase 4 lessons applied from the start; X4 tests through Grafana's endpoints |
| Footprint too high for the laptop | Low | Med | Agents instead of full Prometheus on spokes; no node-exporter or operator; measured (X14) |

| *v1.1* Log volume fills the Loki PVC | Low | Med | 7-day compactor retention; 5 GiB PVC; `kube_persistentvolumeclaim` usage panel; drop noisy streams |
| *v1.1* Secrets leak into logs | Low | High | F.5 pattern search; Alloy drop stage for matching lines if ever found; Loki not exposed (Grafana SSO only) |
| *v1.1* Viewer can read platform logs (O-6) | High (by design) | Low (lab) | Recorded residual; multi-tenancy path documented |
| *v1.1* API-based log tailing load on the API server | Low | Low | 1 Alloy per cluster; lab-scale pod count; measured in X24 |

Rollback for any addon: remove its Application from Git (the root app prunes it; data is disposable).

---

## 11. Sequencing & Effort

| Order | Steps | Gate | Effort |
|---|---|---|---|
| 1 | 0.1, 0.2 | plan approval | XS |
| 2 | A.1, A.2, A.4 (hub), then spike A.3a, then A.3 (nonprod, then prod), A.5 | each step live-verified | L (≈ 1 day) |
| 3 | B.1, B.2, rules + X5–X10 | every alert fired once | M (≈ ½ day) |
| 4 | spike C.1a, then C.1 | X11 | S |
| 5 | D.1, D.2, D.3 | X12, X13 | M |
| 5a | *v1.1*: F.0 → F.1 → F.2 (hub, then nonprod, then prod via a catalog tag) → F.3 → F.4 → F.5 | v1.1 review approval; each step live-verified | M (≈ ½ day) |
| 6 | E.1 | owner approval (O-5); other party validates; **after Track F** | S (+ validation) |

Tracks A–D each get their own implementation report and independent validation.
