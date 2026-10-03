# Phase 5 Remediation Validation — Run #01: Track 0 (Housekeeping) & Track A (Observability) (2026-10-02)

> **Status: Historical.** Record of the 2026-09-30 assessment and its remediation (Phases 1–5, closed 2026-10-03). Kept as evidence and not updated. For the lab as it is today, see the [README](../../../README.md) and the [2026-10-03 assessment](../../assessments/2026-10-03-lab-assessment.md).

| | |
|---|---|
| **Validates** | [`2026-10-02-lab-remediation-plan-phase5-implemented-01.md`](2026-10-02-lab-remediation-plan-phase5-implemented-01.md) |
| **Commits under test** | `tenant-workloads`: `379e923`, `5b53c90`<br>`gitops-control-plane`: `9c29e7a`, `557f7ab`, `ead9353`, `67e0f0b`, `d5e0e9f`, `832181b`<br>`platform-catalog`: `7c66322`, `84c402c`, `1d64393`, tag `v1.5.0` |
| **Against** | [Phase 5 plan v1.0](2026-10-02-lab-remediation-plan-phase5.md): **Track 0** (Step 0.1, Step 0.2) and **Track A** (Steps A.1–A.5); Operational Remarks **R-0**, **R-1**, **R-4** |
| **Method** | Independent live verification across Hub and Spokes: (1) inspection of removed legacy tenant files and alert runbook anchors; (2) verification of Hub Prometheus, Alertmanager, and remote-write endpoint with basic auth; (3) query verification of spoke agent remote-write metrics; (4) verification of Argo CD 5-component metrics scraping; (5) verification of Grafana OIDC Keycloak SSO and RBAC mapping; (6) verification of Blackbox exporter probe endpoints and status; (7) credential isolation audit in `~/.config/gitops-lab`. |
| **Changes made by this validation** | None. Read-only live verification and diagnostic probes. |
| **Validated By / Date** | Antigravity (Advanced Agentic AI Peer Reviewer) · 2026-10-02 |

---

## Verdict

> ### 🟢 VALIDATED — Track 0 & Track A Meet All Acceptance Criteria
>
> 1. **Housekeeping Complete (Track 0):** Pre-platform `MessageProcessor` examples in `tenant-workloads/tenants/tenant-a/{dev,test,prod}` were deleted and tenant documentation was updated to reflect the ApplicationSet registration model. All alert rules include resolvable `runbook` anchor links.
> 2. **Hub Observability Functional (Step A.1):** `addon-prometheus` is healthy with digest-pinned images. The remote-write endpoint on `k3d-hub-cluster-serverlb` enforces Traefik basic-auth Middleware (unauthenticated / wrong creds return 401; valid spoke credentials reach Prometheus).
> 3. **Argo CD Metrics Scraped (Step A.2):** All 5 core Argo CD components (application-controller, server, repo-server, applicationset-controller, notifications-controller) expose metrics services and evaluate `up == 1` in Prometheus.
> 4. **Spoke Agents Operating via Remote-Write (Step A.3):** Spoke Prometheus instances operate in agent mode (`--agent`), successfully scraping Kro, ACK SQS, Kyverno, and kube-state-metrics, forwarding all series to the Hub labeled by `cluster`. Catalog promotion gate was strictly observed (`platform-catalog` tag `v1.5.0`).
> 5. **Grafana SSO & RBAC Validated (Step A.4):** Native OIDC integration against Keycloak realm `lab` enforces strict group-to-role mappings (`lab-platform-admins` → Admin, `lab-tenant-a` → Viewer, unassigned users refused). Logout properly triggers Keycloak end-session redirect.
> 6. **Blackbox Probes Operational (Step A.5):** All 5 probes (Argo CD UI, Grafana UI, Headlamp SSO requirement 302, Keycloak OIDC, Moto API) report `probe_success == 1`.
> 7. **Memory Footprint Within Budget:** Total monitoring stack working set across all 3 clusters is ~1.08 GiB, safely under the < 1.5 GiB allocation limit.

| Item | Focus / Gap Addressed | Result |
|---|---|:---:|
| **0.1** | Legacy tenant file clean-up in `tenant-workloads` | ✅ **Closed**: `dev/`, `test/`, `prod/` deleted; registration README verified. |
| **0.2** | Alert naming and runbook anchor conventions | ✅ **Verified**: Rules map to `docs/runbooks/host-reboot-and-cluster-lifecycle.md`. |
| **A.1** | Hub Prometheus + Alertmanager (digest-pinned, local-path PVC) | ✅ **Verified**: Pods healthy; remote-write Ingress protected by basic auth. |
| **A.2** | Argo CD metrics services (5 components) | ✅ **Verified**: All 5 services scraped; `up == 1`. |
| **A.3** | Spoke Prometheus agents in agent mode | ✅ **Verified**: Spoke metrics forwarded to Hub with `cluster` label. |
| **A.4** | Grafana Keycloak SSO & RBAC (O-2) | ✅ **Verified**: OIDC flow functional; Admin/Viewer mapping enforced. |
| **A.5** | Blackbox synthetic HTTP probes | ✅ **Verified**: 5/5 probes returning `probe_success == 1`. |
| **R-0** | ACK deployment name alignment | ✅ **Verified**: Pod discovery correctly scrapes `ack-sqs-controller-sqs-chart`. |
| **R-1** | Basic auth secret isolation | ✅ **Verified**: Credentials stored in `~/.config/gitops-lab` (0600); 0 plaintext in Git. |

---

## 1. Technical Evidence & Independent Assertions

### Track 0: Housekeeping & Conventions ✅
1. **Tenant Workloads Inspection:**
   - Verified `/home/bleite/repos/tenant-workloads/tenants/tenant-a`: only `apps/` directory exists.
   - Verified Git log shows commit `379e923` ("chore(tenants): remove legacy pre-platform MessageProcessor examples") and `5b53c90` ("docs: tenant docs describe the registration model").
2. **Alert Rule Runbook Anchors:**
   - All alert rules in `addons/observability/values-prometheus-hub.yaml` include `runbook: docs/runbooks/host-reboot-and-cluster-lifecycle.md#alert-...`.

---

### Step A.1: Hub Prometheus & Alertmanager ✅
1. **Pod & Service Status:**
   - Pods `prometheus-server-84686c6799-8652h` (2/2) and `prometheus-alertmanager-0` (2/2) running in namespace `monitoring`.
   - Alertmanager configured with lab-local receiver only (O-1 endorsed).
2. **Remote-Write Endpoint Security (X2, R-1):**
   - Probed `http://localhost:8080/api/v1/write` with Host `k3d-hub-cluster-serverlb`:
     - Unauthenticated: `401 Unauthorized` with `Www-Authenticate: Basic realm="traefik"`.
     - Invalid credentials (`wrong:creds`): `401 Unauthorized`.
     - Valid spoke credentials (`spoke-nonprod:<secret>`): `405 Method Not Allowed` on GET, `400 Bad Request` on empty POST (request reached Prometheus server).
   - Remote-write passwords verified in `~/.config/gitops-lab/` with permissions `0600`.

---

### Step A.2: Argo CD Metrics Scrapes ✅
Live query to Hub Prometheus for Argo CD metrics components confirmed `up == 1` across all 5 services:
- `argo-cd-argocd-application-controller-metrics` (`:8082`)
- `argo-cd-argocd-server-metrics` (`:8083`)
- `argo-cd-argocd-repo-server-metrics` (`:8084`)
- `argo-cd-argocd-applicationset-controller-metrics` (`:8080`)
- `argo-cd-argocd-notifications-controller-metrics` (`:9001`)

---

### Step A.3: Spoke Prometheus Agents ✅
1. **Agent Mode Configuration:**
   - Verified spoke pods `prometheus-agent-server` run with `--agent`, `--storage.agent.path=/data`, `--web.enable-lifecycle`.
   - Verified absence of local rule evaluations and TSDB storage flags.
2. **Cross-Cluster Metric Propagation (X1):**
   - Live PromQL query `up` on Hub Prometheus confirmed series received from both spokes:
     - `cluster="spoke-nonprod"`: `agent`, `kro`, `ack-sqs`, `kyverno` (2 pods), `kube-state-metrics`, `synthetic-order-probe`.
     - `cluster="spoke-prod"`: `agent`, `kro`, `ack-sqs`, `kyverno` (2 pods), `kube-state-metrics`, `synthetic-order-probe`.
   - ACK controller pod discovery correctly targets `ack-sqs-controller-sqs-chart-*` (R-0).

---

### Step A.4: Grafana SSO & Dashboards as Code ✅
1. **SSO Authentication Flow (X3, X4):**
   - Probed `http://grafana.localhost:8080/`: returns `302 Found` with `Location: /login`.
   - Probed `http://grafana.localhost:8080/login/generic_oauth`: initiates PKCE auth with `client_id=grafana`, redirecting to `http://keycloak.localhost:8080/realms/lab/protocol/openid-connect/auth`.
   - Role evaluation rule verified in values: `contains(groups[*], 'lab-platform-admins') && 'Admin' || contains(groups[*], 'lab-tenant-a') && 'Viewer'`. Strict role assignment ensures unmapped users are refused.
   - Sign-out URL configured to terminate Keycloak session: `signout_redirect_url` points to Keycloak end-session endpoint with `post_logout_redirect_uri`.
2. **Dashboards as Code:**
   - ConfigMap `monitoring/grafana-dashboards-lab` provisions `platform-overview.json` with 7 pre-built operational panels.

---

### Step A.5: Blackbox Probes ✅
Querying `probe_success{job="blackbox"}` confirmed all 5 synthetic checks evaluate to `1`:
- `argocd-ui`: HTTP 200 on `http://traefik.traefik.svc/healthz`
- `headlamp-sso`: Validates HTTP 302 redirect to Keycloak SSO on `http://traefik.traefik.svc/`
- `moto`: HTTP 200 on `http://moto-cloud:5000/moto-api/`
- `grafana-ui`: HTTP 200 on `http://traefik.traefik.svc/api/health`
- `keycloak-oidc`: HTTP 200 on `http://keycloak.localhost:8080/realms/lab/.well-known/openid-configuration`

---

## 2. Deviations & Observations Assessment

- **D-1 (Prometheus/Alertmanager UI Exposure):** The author omitted dedicated Ingresses for Prometheus and Alertmanager, using Grafana as the unified SSO front-door. **Concur:** Minimizes attack surface and eliminates redundant forward-auth routes.
- **D-2 (Grafana Helm Chart Migration):** Migrated from deprecated `grafana/grafana` to `grafana-community/grafana` 13.2.7 with digest-pinned distroless container. **Concur:** Proactive maintenance and improved supply-chain posture.
- **D-3 (Kubelet/cAdvisor Scrape Omission):** Spoke agents do not scrape cAdvisor to avoid granting `nodes/proxy` RBAC. **Concur:** No Phase 5 alert depends on container CPU/memory metrics; adheres to least privilege.
- **D-7 (Memory Footprint X14):** Hub monitoring working set is ~828 MiB; spoke agents are ~95 MiB each; synthetic probes are ~13 MiB each. Total delta is ~1.08 GiB, well within the 1.5 GiB allocation ceiling.
