# Implementation Report 08 — H.1 Full Rebuild, v1.2 Acceptance (2026-10-04)

> **Status: Current.** Active remediation record for the 2026-10-03 assessment.

| | |
|---|---|
| **Implements** | [Remediation plan v1.2](2026-10-03-lab-remediation-plan.md) **H.1** (owner decision O-5; v1.2 scope: without E and F); review remark **R-15** |
| **Executed by** | Claude (Opus 5.5), owner's go ("proceed with H.1"). **To be validated by** Antigravity, independent of the execution |
| **Built from** | `gitops-control-plane` `5a619cd`, `platform-catalog` `3fe896f` (nonprod `main`; prod tag `v1.7.2`), `platform-charts` `dcd58aa`, `tenant-workloads` `5e7e457` (PR #1 merged), `orders-processor` `6924cfd` |
| **Fix during H** | `5a619cd`: `setup-hub-spoke.sh` port pre-check aborted under `pipefail` (§2) |
| **Date** | 2026-10-04 UTC |

---

## Summary

> **🟢 Rebuild green, no manual steps: `teardown → setup → bootstrap → post-bootstrap` in 484 s (8 min 4 s), smoke 12/12.** Every closed track (0, A, B, I, C.1, G.3) verified on the fresh lab. The 8080/8443 mappings are gone (R-15).
>
> The first attempt **stopped in setup after 1 s** because of a defect in the Track I.2 port pre-check (`grep` without a match under `set -euo pipefail`). It was fixed (`5a619cd`), tested for both outcomes, and the rebuild was restarted from a clean teardown.

| Phase | Start (UTC) | Duration | rc |
|---|---|---:|:-:|
| teardown | 06:18:50 | 1 s | 0 |
| setup | 06:18:51 | 184 s | 0 |
| bootstrap | 06:21:55 | 1 s | 0 |
| post-bootstrap (incl. smoke) | 06:21:56 | 298 s | 0 |
| **total** | | **484 s** | |

For comparison: Phase 5 Track E rebuild 8 min 15 s.

## 1. Pre-flight (06:17)
* Scripts are non-interactive (no prompt in teardown or setup).
* `argolab` stopped (`0/1` servers); no other container on 80/443 (O-8).
* All five repos at `origin/main`; `tenant-workloads` PR #1 merged and its branch deleted, so `main` is complete everywhere.
* Secrets and the mkcert leaf present in `~/.config/gitops-lab` (reused by the rebuild; never in Git).
* **Validator note:** the rebuild replaced all live state that validation-07 may have looked at (G.3/C.1). Both are re-verified here on the fresh lab (§3).

## 2. Finding and fix during H
| | |
|---|---|
| **Symptom** | Attempt 1 (06:17:49): teardown ok (16 s); `setup` rc 2 after 1 s; last log line `[3/6] Creating k3d clusters…`, no error text |
| **Cause** | Track I.2's pre-check `busy=$(docker ps … \| grep -E '…:(80\|443)->' \| …)`. With no matching container, `grep` exits 1; under `set -euo pipefail` the failed pipeline aborts the script. My I.2 test ran the line outside `set -e`, so it never saw the abort |
| **Fix (`5a619cd`)** | `{ grep … \|\| true; }` inside the pipeline |
| **Test** (the exact line in a `set -euo pipefail` script) | free ports: `busy=[]`, rc 0; occupied (stub `docker` listing `k3d-argolab-serverlb 127.0.0.1:80->80/tcp`): `busy=[k3d-argolab-serverlb ]`, rc 0, so `setup` stops with its message |
| **Same pitfall elsewhere** | reviewed the other scripts added in this plan under `set -e` (`setup-local-tls.sh`, `renew-credentials.sh`; `maintain.sh` runs without `-e`): no unguarded no-match `grep` in a pipeline |
| **Lesson** | Setup and teardown paths are not exercised by CI (`bash -n` and shellcheck cannot see this). Only a rebuild does, which is why H exists |

Attempt 2 started at 06:18:50 from a clean teardown.

## 3. Verification on the fresh lab
| Track | Check | Result |
|---|---|---|
| **R-15** | hub load balancer ports | `127.0.0.1:80->80`, `127.0.0.1:443->443`, `127.0.0.1:6550->6443`. **No 8080/8443** |
| Health | Applications / AppSets | **32/32** Synced/Healthy; 8 ApplicationSets, all `ResourcesUpToDate=True` |
| **I** | portless URLs | `http://localhost/` 200, `argocd.localhost` 200, `headlamp.localhost` 302 (SSO), `grafana.localhost/login` 200 |
| **I** | issuer / in-cluster path | `http://keycloak.localhost/realms/lab`; from argocd-server, `keycloak.localhost` → `traefik.traefik.svc.cluster.local`; direct TCP to the Keycloak pod **BLOCKED** |
| **I** | HTTPS | `https://argocd.localhost/x`, `https://grafana.localhost/x` → `302 http://…/x`, certificate verified against the mkcert CA (`setup` reloaded the existing leaf: "trusted; expires 2029-01-03") |
| **B** | tenant ApplicationSet / alert | `tenant-workloads-tenant-a` only (no legacy `tenant-workloads`); `argocd_appset_info` = `ApplicationSetUpToDate`; rule `ApplicationSetNotUpToDate` loaded, health ok |
| **C.1** | Pod Security labels | 13/13 namespaces as specified (`headlamp` = baseline, the rest restricted), **applied at creation** (no manual sync needed, unlike the live change in report 07); a privileged pod in `kyverno` (spoke-prod) → `violates PodSecurity "restricted:latest"` |
| **0** | digest pins / catalog / admission | no image without `@sha256` outside `kube-system` on all 3 clusters; prod blueprints `v1.7.2`; smoke stage 11: unsigned image denied by Kyverno, `alpine` denied by the allowlist VAP, running image admitted, in all three tenant namespaces |
| **G.3** | `make maintain` | `✔ shortest credential lifetime left: 29 days`, `✔ no orphaned credentials or namespaces`, rc 0 |
| Tokens | credential expiry | 5 tokens at 29 days (new, from `setup`); `local-tls` 822 days |
| Alerts | rules / firing | **20** rules loaded; **0** firing; 5/5 probes `probe_success = 1`; CI exporter sees 6 workflows `=1` |
| **A** | CI | GitHub CI on `5a619cd`: success |
| Regression | smoke / audit | **12/12** (in `post-bootstrap`); impersonation audit **PASS** |

## 4. What H does not cover (v1.2 residuals, plan §1.3)
* **E** (encryption at rest, audit log): not in the build path.
* **F** (spoke Traefik under GitOps): spokes still run the k3s-bundled Traefik 3.6.13.
* **C.2/C.3, D, G.1, G.2, G.3 alerts, scheduled renewal, per-tenant AppProjects:** as recorded.

## 5. Notes for the validator
* **Fresh-lab facts:**
  * new Application UIDs (the rebuild recreates everything);
  * tokens expire about **2026-11-02/03**;
  * moto starts empty (workers re-keyed by `post-bootstrap` step 4).
* **Owner browser check (recommended, as in earlier rebuilds):**
  * SSO login and logout on `http://localhost`, `http://headlamp.localhost`, `http://grafana.localhost`, for `platform-user` and `tenant-a-user`;
  * `https://argocd.localhost` without a warning.

  Smoke stage 10 already proves issuer identity and that every UI reaches the Keycloak login.
* **Suggested checks:** the R-15 port list; §3 rows; the §2 test (the pre-check line under `set -euo pipefail`, free and occupied).

## 6. Plan status after H
| Item | Status |
|---|---|
| Tracks 0, A, B, I | ✅ Closed (validations 01–06) |
| G.3 (reduced), C.1 | 🔧 implemented-07; re-verified here. **Awaiting validation-07** |
| H.1 | 🔧 Done. **Awaiting validation-08** |
| Residuals | Recorded (plan §1.3) |

When validations 07 and 08 pass, **the 2026-10-03 remediation plan is closed**.
