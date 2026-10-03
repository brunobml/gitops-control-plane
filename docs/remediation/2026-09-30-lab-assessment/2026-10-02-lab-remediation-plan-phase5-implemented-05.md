# Phase 5 Implementation Report — Run #05: Track F, log aggregation (v1.1) (2026-10-02)

> **Status: Historical.** Record of the 2026-09-30 assessment and its remediation (Phases 1–5, closed 2026-10-03). Kept as evidence and not updated. For the lab as it is today, see the [README](../../../README.md) and the [2026-10-03 assessment](../../assessments/2026-10-03-lab-assessment.md).

| | |
|---|---|
| **Plan** | Phase 5 v1.1 amendment (GREEN LIGHT `659283c`; remarks **R-5..R-8**; owner decisions O-6, O-7 accepted) |
| **Executed by** | Claude (Opus 5.5). **To be validated by** Antigravity |
| **Commits** | `gitops-control-plane`: `6301a72`, `d557760`, `ef76858` (F.0); `511e84f` (F.1); `cae3976`, `6b76ebf` (F.2); `ce87320` (F.3/F.4); `5283779` (OOM alert); `430ea6c` (smoke). `platform-catalog`: `e7b5e1d`, `10d4b65`, `2470043`, tags **`v1.5.1`**, **`v1.6.0`**, **`v1.6.1`** (prod) |

## 1. Outcome

| Step | Result |
|---|:-:|
| **F.0** `monitoring` namespaces enforce PSS **`restricted`** on all three clusters (all workloads made compliant first; R-8 server dry runs) | ✅ |
| **F.1** Loki 3.7.8 single binary on the hub (`grafana-community/loki` 18.13.7), 7-day compactor retention, 5 GiB PVC, `replicas: 1` (R-6), push-only ingress with per-spoke basic auth (R-7) | ✅ |
| **F.2** Alloy v1.20.0 on hub, nonprod, prod: pod logs **and Kubernetes events** through the API; exact RBAC; non-root, read-only root FS; health-check lines and Alloy's own logs dropped (R-5) | ✅ |
| **F.3** Grafana: Loki datasource (Drilldown → Logs works), dashboard **Logs & events** (cluster/namespace/search, warning events, OOM table, log volume), overview events panel + link, alert `logs` links | ✅ |
| **F.4** alerts `LokiDown`, `LogShipperDown`, `LogsMissing`, `LokiIngestionErrors` (+ `ContainerOOMKilled`, D-23) — 17 rules, **12 promtool unit tests** pass | ✅ |
| **F.5** acceptance X17–X24 | ✅ (§2) |
| Regression | **32/32** Synced/Healthy; R-1 audit PASS; smoke **12/12** (stage 12 now also requires logs from all 3 clusters); `post-bootstrap` exit 0 |

## 2. Evidence (X17–X24)

| # | Test | Result |
|---|---|---|
| X17 | `monitoring` PSS on hub / nonprod / prod | `restricted` everywhere; all pods Running; 0 `FailedCreate`; server dry run: 0 violations |
| X18 | pod logs a marker, then pod **and namespace deleted** (`kubectl logs` → NotFound) | both marker lines still in Loki, labelled `namespace/pod/container` — **the owner's use case** |
| X19 | OOM-killed container (20 Mi limit, 50 MB allocation, restarting) | `BackOff` warning events in Loki after the namespace was gone; **`ContainerOOMKilled` fired ~60 s after start** with a `logs` link (D-23) |
| X20 | push to `/loki/api/v1/push` from a spoke pod: none / wrong / right credential; query API on the same host | 401 / 401 / **204** / 404; pushed line read back |
| X21 | `tenant-a-user` (Viewer) queries `{cluster="hub", namespace="keycloak"}` via Grafana | 200, lines returned — the accepted **O-6 residual** |
| X22 | 1 h of logs, all clusters (21 406 lines), credential patterns | 4 matches, all Grafana start-up notices "Config overridden from Environment variable `GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET`" with a masked value; the real values of 4 lab secrets checked **absent** (compared in place, never printed) |
| X23 | nonprod Alloy and hub Loki stopped (Argo CD controller paused) | `LokiDown` and `LogShipperDown[spoke-nonprod]` fired; `LokiIngestionErrors[hub]` followed (hub Alloy dropping during the outage); all resolved after restore |
| X24 | footprint | logging stack ≈ **230 Mi** working set (Loki ~50 Mi after restart, Alloy 56–64 Mi per cluster) — target < 600 Mi met; host 19 GiB available |

## 3. Deviations, defects and notes

| ID | Item |
|---|---|
| D-19 | **Chart change (pre-flight F10):** OSS Loki is `grafana-community/loki` (the `grafana/loki` chart is Enterprise-only since 2026-03-16). Alloy stays `grafana/alloy` |
| D-20 | **Alloy chart default RBAC reads `secrets` cluster-wide** (plus configmaps, nodes, …) and always appends node rules. Replaced with an exact ClusterRole `alloy-logs`: `pods`, `pods/log`, `namespaces`, `events` (get/list/watch); chart CRDs disabled |
| D-21 | **Alloy image runs as root by default** (no `User`); runs as its `alloy` user (473), non-root, read-only root FS, `emptyDir` for its storage path |
| D-22 | **My push broke the probes kustomization (~3 min):** a `monitoring` Namespace object added to `addons/probes` was renamed by kustomize's namespace transformer (ID conflict). Fixed by using Argo CD `managedNamespaceMetadata` instead (`d557760`); no workload was affected (the build failed, nothing was applied) |
| D-23 | **Kubernetes emits no OOMKilled event** (plan F.3 assumed one). OOM kills come from kube-state-metrics: new alert `ContainerOOMKilled` and an OOM table in *Logs & events* (it would have flagged the Grafana OOM of implemented-01 §5) |
| D-24 | **Sequencing slip (author):** Argo CD applied the `restricted` label to prod's `monitoring` while the prod agent still ran non-compliant values (v1.5.0). The running pod was unaffected, but a restart would have been refused. Closed within minutes by catalog **v1.5.1** (compliant agent); prod agent then restarted cleanly under `restricted` |
| D-25 | **`absent()` drops labels for comparison expressions** — found by the `LogShipperDown` unit test (hub alert without `cluster`); rule rewritten as `up == 0 or absent(<selector>)` |
| D-26 | Log lines produced **while Loki is down are dropped** after Alloy's retries (X23); `LokiIngestionErrors` makes the gap visible. Accepted for the lab (no persistent Alloy WAL) |
| D-27 | Upstream quirk: the `alertmanager` subchart template renders a trailing TAB (`apiVersion: v1\t`); Kubernetes tolerates it, strict YAML parsers do not. No action |
| D-28 | Push credentials are shared with remote write (one credential per spoke for metrics and logs) — fewer secrets, same R-1/R-7 handling |
