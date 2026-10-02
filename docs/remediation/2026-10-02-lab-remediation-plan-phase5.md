# Lab Remediation Plan: Phase 5 — Observability, Self-Healing Operations & Residual-Risk Closure
## Hub-and-Spoke GitOps Control Plane (2026-10-02)

* **Plan Version:** 1.0 (initial submission)
* **Assessment Reference:** [`../assessments/2026-09-30-lab-assessment.md`](../assessments/2026-09-30-lab-assessment.md)
* **Phase 4 Baseline:** [`2026-10-02-lab-remediation-plan-phase4-validation-05.md`](2026-10-02-lab-remediation-plan-phase4-validation-05.md) and [`…-phase4-crosscheck-05.md`](2026-10-02-lab-remediation-plan-phase4-crosscheck-05.md) (Phase 4 complete; full rebuild accepted)
* **Target Repositories:** `gitops-control-plane`, `platform-catalog`, `tenant-workloads`
* **Author:** Claude (Opus 5.5)

---

## Review & Approval Sign-Off

| Field | Details |
|---|---|
| **Current Status** | ⏳ **AWAITING PEER REVIEW**: no step of this plan has been executed |
| **Plan Version** | `v1.0` |
| **Author** | Claude (Opus 5.5) |
| **Reviewed By** | _pending_ (Antigravity) |
| **Review Date** | _pending_ |
| **Authorization Decision** | _pending_ |
| **Execution / validation split** | Each step is executed and reported (`implemented-NN`) by one party and validated (`validation-NN`) by the other. Phase 4 run #05 was executed and validated by the same party; an independent cross-check had to be added afterwards |

### Owner decisions requested

| ID | Question | Author's recommendation |
|---|---|---|
| **O-1** | Where should alerts go? | **Lab-local only**: Alertmanager UI plus a Grafana "Firing alerts" panel. No external service, no new credentials. An external channel (e-mail, ntfy, Slack) can be added later as one receiver |
| **O-2** | Who may open Grafana? | Both SSO groups: `lab-platform-admins` → Grafana **Admin**, `lab-tenant-a` → **Viewer**. Same pattern as Headlamp in Phase 4 |
| **O-3** | Clean-up of deregistered tenant apps (Phase 4 D-16) | **Automatic** for credentials (IAM user + Secret) and the empty namespace. **Report only** for data (DynamoDB tables), deleted only with an explicit `PRUNE_DATA=1` |
| **O-4** | Token renewal | **Automatic** in `make post-bootstrap` when a spoke or Headlamp token has fewer than 7 days left. You already run it after every `make start` |
| **O-5** | End-of-phase rebuild acceptance (Track E) | **Yes**, in an owner-approved window; executed and validated by different parties |

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
| Logs aggregation (Loki) | Argo CD and Headlamp already show pod logs; revisit if a need appears |
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

## 8. Track E: Acceptance

### Step E.1: Full rebuild (O-5)
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
| 6 | E.1 | owner approval (O-5); other party validates | S (+ validation) |

Tracks A–D each get their own implementation report and independent validation.
