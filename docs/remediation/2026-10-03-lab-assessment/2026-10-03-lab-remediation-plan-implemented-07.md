# Implementation Report 07 — v1.2 Close-out: G.3 (reduced) and C.1 (2026-10-03)

> **Status: Current.** Active remediation record for the 2026-10-03 assessment.

| | |
|---|---|
| **Implements** | [Remediation plan v1.2](2026-10-03-lab-remediation-plan.md) close-out: **G.3** reduced (`make maintain`; owner decision **O-10 = manual only**), **C.1** Pod Security labels (owner decision **O-9 = yes**); review remarks **R-13**, **R-14** |
| **Executed by** | Claude (Opus 5.5), owner's assignment. **To be validated by** Antigravity, independent of the execution |
| **Commits** | `gitops-control-plane` `16ca347` (G.3, plan records O-9/O-10), `40555a3` (C.1) |
| **Live changes outside Git** | one-time manual sync of `argo-cd` (by design) and of 7 add-on Applications (§2, why); `headlamp-access` labelled on the 3 clusters with the same command `setup-credentials.sh` now runs; a test renewal of the spoke and Headlamp tokens (§1) |
| **Date** | 2026-10-03 / 2026-10-04 UTC |

---

## Summary

| Step | Result |
|---|---|
| **G.3** | `make maintain` = token renewal (< 7 days left) + orphan clean-up, nothing else. Non-interactive; **exits 0 and logs when Docker or the hub is down**; log `~/.config/gitops-lab/logs/maintain.log` (dir 700, file 600, last 2000 lines). Renewal logic moved to `scripts/renew-credentials.sh`, shared with `post-bootstrap`. Per O-10 there is **no scheduler**; recorded as a residual. Four tests passed, including a real renewal |
| **C.1** | Pod Security labels through GitOps (`managedNamespaceMetadata`) on **13 namespaces**: `restricted` for `argocd`, `traefik`, `oauth2-proxy`, `kro`×2, `ack-system`×2, `kyverno`×2, `headlamp-access`×3; `baseline` (+ `warn`/`audit: restricted`) for `headlamp`. **R-13:** every workload of each app, **Helm hook Jobs included**, was dry-run under its target level before the change |
| Regression | smoke 12/12 (in `post-bootstrap`, rc 0); impersonation audit PASS; 32/32 Synced/Healthy; 0 pods outside Running/Completed on all clusters; `make ci` green; GitHub CI green on both commits |

---

## 1. G.3 — `make maintain` (R-14)

**Design:**
* `scripts/renew-credentials.sh` holds the former `post-bootstrap` step 1:
  * reads the expiries from `monitoring/credential-expiry`;
  * renews through `register-spokes.sh` + `addons/headlamp/setup-credentials.sh` when fewer than `RENEW_DAYS` (7) days are left or data is missing;
  * uses its own `argocd` CLI config, or the caller's;
  * stdin closed; never prints a token.
* `post-bootstrap.sh` step 1 now calls it.
* `scripts/maintain.sh` (`make maintain`):
  1. **Pre-flight:** `docker info` (20 s timeout); hub `/readyz` and `http://localhost/healthz`. If either fails, it logs "lab stopped, nothing to do" and **exits 0**.
  2. Runs `renew-credentials.sh`, then `orphans.sh` (the same clean-up `post-bootstrap` step 6 does).
  3. Exits with the worst rc of the steps.

  Every line is timestamped and appended to the log. The logger process is waited for at exit, so no line is lost; the first version lost the last line, found in testing.
* **Deviation from the plan text:** v1.2 said each run would write `lab-maintenance` into `monitoring/credential-expiry` for Grafana. Dropped: the exporter serves *every* key there as a credential **expiry**, so a past timestamp would fire `SpokeTokenExpiringSoon` at once. The run history is the log file; the plan text was updated in `16ca347`.

**Tests:**

| # | Case | Result |
|---|---|---|
| 1 | lab running, tokens 29 days | `✔ shortest credential lifetime left: 29 days`, `✔ no orphaned credentials or namespaces`, rc 0; log dir 700, file 600 |
| 2 | Docker unreachable (stub `docker` on `PATH`) | `Docker is not reachable: lab not running, nothing to do`, `== maintain end (skipped)`, **rc 0** |
| 3 | hub unreachable (stub `kubectl`) | `hub cluster or Argo CD is not reachable: lab stopped, nothing to do`, **rc 0** |
| 4 | recorded expiry of `argocd-spoke-nonprod` set to now + 2 d | `↻ renewing … (shortest left: 1 days)`. Both spokes re-registered, Headlamp kubeconfig refreshed and restarted, orphans clean, **rc 0**, 33 s. All five credentials then at 29–30 days (expire **2026-11-03**); 32/32 healthy |

After the refactor, `post-bootstrap` step 1 reports `✔ shortest credential lifetime left: 29 days`, and the full run is rc 0.

**Per O-10 (owner: manual only):** no Task Scheduler or timer. A residual row was added to plan §1.3: *Scheduled renewal*, with the safety net `SpokeTokenExpiringSoon` (7 days), `post-bootstrap` after every start, and `maintain.sh` ready to be scheduled later as-is.

## 2. C.1 — Pod Security labels (O-9, R-13)

**Pre-flight** (server-side dry-run of the label on the live namespaces): every running pod already complies with `restricted`, except `headlamp` (complies with `baseline`).

**R-13: all workloads, hooks included.**
1. Every pod-creating object (Deployment, StatefulSet, DaemonSet, Job, CronJob, Pod) of each Application was taken from the CI's offline render (`ci/check-control-plane.sh render`), Helm hook Jobs included.
2. They were applied with `--dry-run=server` into a temporary namespace labelled `warn=<target level>`, on the right cluster.
3. Temporary namespaces were deleted afterwards.

| Application | Level | Workloads | Hook objects | Result |
|---|---|:-:|:-:|---|
| `argo-cd` | restricted | 7 | 2 (`redis-secret-init`) | compliant |
| `addon-traefik` | restricted | 1 | 0 | compliant |
| `addon-oauth2-proxy` | restricted | 1 | 0 | compliant |
| `addon-headlamp` | baseline | 1 | 0 | compliant (restricted: `allowPrivilegeEscalation`, capabilities → hence baseline) |
| `addon-kro-spoke-nonprod` | restricted | 1 | 0 | compliant |
| `addon-ack-sqs-spoke-nonprod` | restricted | 1 | 0 | compliant |
| `addon-kyverno-spoke-nonprod` | restricted | 5 | 9 hook annotations (`migrate-resources`, `rm-webhooks`, `scale-to-zero` and their RBAC) | compliant |

**Change (`40555a3`):**
* `managedNamespaceMetadata` (`enforce` + `enforce-version: latest` + `warn`/`audit: restricted`) on `argo-cd`, `addon-traefik`, `addon-oauth2-proxy` (each gained `CreateNamespace=true`, which `managedNamespaceMetadata` requires), `addon-headlamp` (baseline), and the `addons-spoke` and `addons-spoke-kyverno` ApplicationSet templates.
* `headlamp-access` (ServiceAccount and token only, not an Argo CD app) is labelled by `addons/headlamp/setup-credentials.sh`.
* **Mechanism proven beforehand:** `monitoring` (pre-existing, script-created) carries PSS labels applied by field manager `argocd-controller` through the same mechanism (Phase 5 F.0), so it works for script-created namespaces too.

**Apply:**
* `argo-cd`: manual sync (by design, B.4).
* **Finding:** 7 Applications (`addon-traefik`; `addon-kro`, `addon-ack-sqs`, `addon-kyverno` × 2 spokes) went *OutOfSync* on their Namespace metadata but did **not** auto-sync. Argo CD auto-syncs a given revision only once, and a change to the sync policy alone leaves the revision (chart version + catalog SHA) unchanged. They were synced once by hand as `platform-admin` (each `Succeeded`). A fresh cluster (Track H) is unaffected: the namespaces are created with the labels.

**Result:**

| Cluster | Namespace | enforce | warn |
|---|---|---|---|
| hub | `argocd`, `traefik`, `oauth2-proxy` | restricted | restricted |
| hub | `headlamp` | **baseline** | restricted |
| hub, both spokes | `headlamp-access` | restricted | — |
| both spokes | `kro`, `ack-system`, `kyverno` | restricted | restricted |

**Negative check** (server dry-run of a privileged pod):

| Namespace | Result |
|---|---|
| `kyverno` | `violates PodSecurity "restricted:latest"` |
| `traefik` | `violates PodSecurity "restricted:latest"` |
| `headlamp` | `violates PodSecurity "baseline:latest"` |

**Owner visibility (standing preference):** unchanged. Labels do not affect the Argo CD tree or Headlamp.

## 3. Regression
| Check | Result |
|---|---|
| `make post-bootstrap` | rc 0; smoke 12/12 (*All Core Smoke Tests Passed*) |
| `scripts/audit-impersonation.sh` | PASS |
| Applications | 32/32 Synced/Healthy |
| Pods | 0 outside Running/Completed on hub, spoke-nonprod, spoke-prod |
| `make ci` | all stages green (414 resources) |
| GitHub CI | `16ca347`, `40555a3`: success |

## 4. Notes for the validator
* **Suggested checks:**
  * `make maintain` with the lab up, and with Docker or the hub made unreachable (stubs as in §1, or a stopped lab);
  * the log file and its mode;
  * the namespace labels table;
  * a privileged-pod dry-run per level;
  * the R-13 hook dry-run method on one app.
* **Remaining:** **H.1 rebuild** (v1.2 scope; owner window per O-5). It proves 0, A, B, I, C.1 and `make maintain` on a fresh lab, and removes the 8080/8443 mappings (R-15).

## 5. Status
| Step | Status |
|---|---|
| G.3 (reduced) | 🔧 Done. **Awaiting validation-07** |
| C.1 | 🔧 Done. **Awaiting validation-07** |
| H.1 | ⏳ Owner window needed |
