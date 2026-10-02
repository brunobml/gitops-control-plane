# Phase 5 Implementation Report — Run #01: Track 0 (housekeeping) and Track A (observability) (2026-10-02)

| | |
|---|---|
| **Plan** | [`2026-10-02-lab-remediation-plan-phase5.md`](2026-10-02-lab-remediation-plan-phase5.md) v1.0 (GREEN LIGHT `3654617`; remarks R-0..R-4) |
| **Owner decisions** | O-1..O-4 accepted as recommended ("review approved and proceed"); O-5 (rebuild) will be asked before Track E |
| **Executed by** | Claude (Opus 5.5). **To be validated by** Antigravity (execution/validation split) |
| **Commits** | `tenant-workloads`: `379e923`, `5b53c90` (0.1). `gitops-control-plane`: `9c29e7a` (A.1), `557f7ab` (A.2), `ead9353` (A.4), `67e0f0b` (A.3), `d5e0e9f` (A.5 + exporter), `832181b` (prod promotion). `platform-catalog`: `7c66322`, `84c402c`, `1d64393` (A.3), tag **`v1.5.0`** |

## 1. Outcome

| Step | Result |
|---|:-:|
| **0.1** legacy `MessageProcessor` examples removed; tenant README and tutorial rewritten for the registration model | ✅ |
| **0.2** every alert has a `runbook` annotation → runbook section (D.3) | ✅ |
| **A.1** hub Prometheus + Alertmanager + kube-state-metrics (`addon-prometheus`, chart 29.35.0, all images digest-pinned), 7-day retention, lab-local receiver (O-1), remote-write endpoint | ✅ |
| **A.2** Argo CD metrics Services (5 components) scraped via annotations (commit + manual `argo-cd` sync) | ✅ |
| **A.3** spoke Prometheus **agents** (`addons-spoke-observability`, values in `platform-catalog`, nonprod first, prod with catalog **v1.5.0**) | ✅ |
| **A.4** Grafana with Keycloak SSO (Admin/Viewer from groups, outsider refused, logout ends the Keycloak session), datasources + dashboard as code | ✅ |
| **A.5** blackbox probes: Argo CD UI, Grafana UI, **Headlamp requires SSO** (302 to the `lab` realm), Keycloak OIDC discovery, moto | ✅ |

## 2. Evidence

| # | Check | Result |
|---|---|---|
| X1 | `up` per `cluster` on the hub | both spokes: agent, kro, ack-sqs, kyverno, kube-state-metrics, synthetic-order-probe = 1 |
| X2 | remote-write endpoint from a spoke pod: no credential / wrong / other spoke's user / right / query API on the same host; host Host-header spoof | 401 / 401 / 401 / **400 (reached Prometheus)** / 404 / 401 |
| X3 | Grafana unauthenticated | 302 to `/login`; "Sign in with Keycloak" → Keycloak with PKCE. Prometheus/Alertmanager: **no ingress** (D-1) |
| X4 | Grafana SSO through Grafana's own endpoints | `platform-user` → **Admin**, `tenant-a-user` → **Viewer**, outsider (temporary, deleted) → **refused** and no Grafana user created; logout → Keycloak end-session (Grafana adds `id_token_hint`), old session 401, next login shows the form; local `admin` break-glass 200, wrong password 401 |
| Argo CD metrics | `up` for 5 `*-metrics` services | all 1; `argocd_app_info`, `argocd_cluster_connection_status` present |
| A.5 | `probe_success` | all 5 probes = 1 |
| Secrets (R-1) | remote-write passwords, Grafana admin, Grafana client secret | generated once into `~/.config/gitops-lab` (600); Secrets built from files; htpasswd re-run keeps bcrypt hashes (idempotent); nothing printed or committed |

## 3. Spike A.3a (R-4) — findings that changed the design

| Finding | Consequence |
|---|---|
| The `prometheus` chart has **no agent mode**; Prometheus v3.15 refuses its default flags in agent mode (`--storage.tsdb.path`, `--storage.tsdb.retention.time`) | spoke values use `server.defaultFlagsOverride: [--agent, --config.file, --storage.agent.path=/data, --web.enable-lifecycle]` |
| Agent mode refuses the chart's default `rule_files` (`field rule_files is not allowed in agent mode`) | `serverFiles.prometheus.yml.rule_files: null` |
| Chart quirk: with `rule_files`/`scrape_configs` consumed, the template appends a bare `{}` (invalid YAML) | harmless `scrape_config_files: []` key |
| Chart 29.x keeps 10 default jobs in a separate `scrapeConfigs` map, merged with custom jobs | all 10 disabled on spokes |
| Real metric names (R-0: ACK pod `ack-sqs-controller-sqs-chart-*`) | kro `controller_runtime_reconcile_errors_total`, `dynamic_controller_queue_length`; ACK `ack_outbound_api_requests_total`; Kyverno `kyverno_admission_review_duration_seconds`, `kyverno_image_validating_policy_results_total` |
| Final config validated with the real Prometheus binary in agent mode | "Starting Prometheus Agent", config loaded |

## 4. Deviations, defects and notes

| ID | Item |
|---|---|
| D-1 | **Prometheus/Alertmanager UIs are not exposed** (plan: behind oauth2-proxy). Grafana (SSO) is the single front door: Explore for queries, Alertmanager datasource and alert-list panel for alerts. Fewer components and hostnames to secure. The only hub ingress is the path-limited, basic-auth remote-write endpoint |
| D-2 | **`grafana/grafana` chart is deprecated** (pre-flight F4 missed it). Using the successor `grafana-community/grafana` **13.2.7** (Grafana 13.2.3), **distroless** image, digest-pinned |
| D-3 | **No cadvisor/kubelet scraping on spokes**: it needs `nodes/proxy`, which also grants kubelet API access (exec into pods). Dropped instead of granting it; no alert depends on container CPU/memory |
| D-4 | Kyverno endpoints discovery also listed the webhook port (9443 → 400); kept only `metrics-port` |
| D-5 | **My false alarm**: `kubectl auth can-i get nodes/proxy` read `proxy` as a node *name*; the correct `--subresource=proxy` check and `can-i --list` show the agent has **no** `nodes/proxy` |
| D-6 | Keycloak NetworkPolicy extended to Grafana and blackbox pods (`monitoring` namespace, by pod label) |
| D-7 | Footprint (X14): new components' working set ≈ **1.0 GiB** (hub monitoring 827 Mi, spoke agents ~90 Mi each, probes ~12 Mi each, 2nd Kyverno replica) — **within** the < 1.5 GiB target. `docker stats` container totals grew 5.79 → 8.64 GiB; on the hub 4.8 GiB of the container's 8.3 GiB is reclaimable file cache. Largest single process remains Keycloak (763 Mi, Phase 4). Host: 19 GiB available |

## 5. Addendum — owner test: Grafana "Bad Gateway" / "no available server" (fixed, `e5ab72a`)

| | |
|---|---|
| **Reported by owner** | Login as `platform-user` worked, then a red "Bad Gateway" banner; dashboards kept loading; notifications "no available server" |
| **Root cause** | Grafana was **OOM-killed** (exit 137) at its 384 Mi limit during the owner's first interactive session (idle ~260 Mi). While it restarted, Traefik had no ready endpoint ("no available server" / 502). Grafana is stateless (emptyDir), so the restart also invalidated the browser session ("user token not found" in the logs) and the UI kept retrying |
| **Why my tests missed it** | X4 tested login, roles and logout through Grafana's endpoints with scripts, which never loaded the browser frontend; memory stayed ~260 Mi |
| **Fix** | requests 256 Mi / **limit 1 Gi** (`values-grafana.yaml`) |
| **Verification** | new pod Running, limit 1 Gi; as `platform-user`: dashboard JSON + all 6 panel queries + Alertmanager alert list, 5 rounds → all 200, memory steady ~252 Mi, 0 restarts. Owner to re-test in the browser (reload, log in again) |
| **Lesson** | Acceptance for a UI must include a real browser session, not only API calls; size UI pods from their interactive peak |
