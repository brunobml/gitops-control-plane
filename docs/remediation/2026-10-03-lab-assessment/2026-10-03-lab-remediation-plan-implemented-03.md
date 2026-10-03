# Implementation Report 03 — Track 0: Steps 0.4–0.7 (2026-10-03)

> **Status: Current.** Active remediation record for the 2026-10-03 assessment.

| | |
|---|---|
| **Implements** | [Remediation plan v1.0](2026-10-03-lab-remediation-plan.md) Track 0, Steps **0.4** (L1-2), **0.5** (L1-3), **0.6** (L3-1), **0.7** (L1-4, L1-5, L2-6); also closes validation-01 **V-6** |
| **Executed by** | Claude (Opus 5.5), owner's assignment. **To be validated by** Antigravity, independent of the execution |
| **Commits** | `gitops-control-plane` `0c1254b` (0.4), `7d0127d` (0.5 + V-6), `5afc575` (0.6 hub), `8c77f41` (prod → catalog v1.7.2), `65017de` (0.7), plus this report's commit (one link fix); `platform-catalog` `ae8e1b8`, tag **`v1.7.2`**; `platform-charts` `5a218aa`, `d36f8c2`; `orders-processor` `6924cfd`; `tenant-workloads` `51db060` / `073c953` (Drill 5 register / deregister, net zero) |
| **Date** | 2026-10-03 |

---

## Summary

| Step | Result |
|---|---|
| **0.4** README | Quick Start now has `make post-bootstrap` after `make bootstrap`. It is also added after `make start`, in the README and the lifecycle runbook. New **"What you get"** section: URLs, SSO users, `make password`, dashboards, guardrails, drills. Architecture diagram redrawn for today's addons, identity and telemetry flows (renders with mermaid-cli). Repository tree updated; `push-all.sh` "5 repos"; repo list corrected (`platform-charts`, not `helm-charts`) |
| **0.5** Drills playbook | v1.1. Every drill has an **Expected signal** that names the control. Pod Security-compliant specs; the real registration format; `${REPOS_DIR:-..}` paths. **All six drills were run once against the lab**, and the playbook carries the observed timings. Six further errors, found only by running the drills, were also fixed (§2) |
| **V-6** | Smoke stage 11 now asserts *which* control denied each probe: Kyverno `tenant-images-signed` for the unsigned image, VAP `tenant-image-registry-allowlist` for `alpine` |
| **0.6** Digest pins | Argo CD, Redis, Headlamp and **hub Traefik** (`gitops-control-plane`); kro and ACK SQS (`platform-catalog`, nonprod via `main`, prod via **v1.7.2**). **No platform pod outside `kube-system` runs an image without a digest** on any cluster |
| **0.7** Hygiene | Status banner on **every** `docs/` file (69). Naming-standards doc shows the current ApplicationSet and chart. `platform-charts` README rewritten. **`package-and-push.sh` no longer bypasses the 0.2 guard** (new finding I-1). Committed `__pycache__` removed. Host leftovers reported only (O-4) |
| Regression | 32/32 Synced/Healthy · smoke 12/12 · impersonation audit PASS · `make test-alert-rules` SUCCESS · 0 firing alerts |

---

## 1. Step 0.4 — README (L1-2)

* **Quick Start step 3** is now `make bootstrap` followed by `make post-bootstrap`. The text says what fails without it: no worker credentials, `argo-cd` OutOfSync, smoke stages 9 and 12.
* **Lifecycle:** `make start` is now followed by `make post-bootstrap` in the README and in `docs/runbooks/host-reboot-and-cluster-lifecycle.md` Step 2 (it was only in Issue F before).
* **What you get:**
  * a table of Argo CD, Headlamp, Grafana and Keycloak admin URLs, each with how to sign in;
  * the orders dashboards (`make open-*`);
  * the SSO users and their roles (Grafana role mapping taken from `values-grafana.yaml`: `lab-platform-admins` → Admin, `lab-tenant-a` → Viewer);
  * `make password`;
  * the two dashboards (panel names checked against the JSON);
  * 17 alert rules;
  * the guardrails;
  * a link to the drills.
* **Architecture:** the pre-Phase-4 diagram (3 repos, no identity or telemetry) was replaced. The new one shows 5 repos; hub Traefik, Argo CD, Keycloak, Headlamp + oauth2-proxy, Prometheus, Loki, Grafana and Alloy; and on the spokes kro, ACK (CARM), Kyverno with the native VAPs, agents and workloads, plus moto with both accounts. Rendered with `@mermaid-js/mermaid-cli` without error.
* **Tree:** all current directories and scripts. `push-all.sh` "Pushes all 5 lab repos". The AI-prompt link text now matches its path.

## 2. Step 0.5 — Drills playbook (L1-3)

### Corrections required by the plan
| Drill | v1.0 error | v1.1 |
|---|---|---|
| 3 (Kyverno; the assessment's "Drill 2") | `kubectl run --image=alpine:latest`, which is denied by **Pod Security**, not Kyverno | Compliant spec + **unsigned `orders-processor` digest** → denied by Kyverno. A note explains why `alpine` proves nothing about Kyverno |
| 5 (tenant lifecycle) | fields `name/environment/cluster/namespace` (would freeze the whole ApplicationSet, L2-3) | real fields `tenant/app/env/port/valuesRevision/valuesFile`, with a ⚠️ note on `missingkey=error`. The demo values file is now **permanent** in `orders-processor/deploy/values-orders-demo-dev.yaml` (`6924cfd`) |
| 6 (post-mortem) | `alpine` pod with no compliant spec (never created) | Compliant spec + **signed** image (it has `sh`) |
| all | absolute `/home/bleite/...` paths | `${REPOS_DIR:-..}`, plus helper functions (`promq`, `alerts`, `logq`, `moto111`) |
| all | — | **Expected signal** per drill, and a table of the four admission controls with the exact message prefix each produces |

### Further errors found by executing the drills (also fixed)
| Drill | v1.0 claim | What actually happens (observed) |
|---|---|---|
| 1 | `ProbeFailed{probe="moto"}` fires; Loki shows `AccessDenied` | Moto is back in seconds, so `ProbeFailed` (`for: 5m`) **does not fire**. The workers **log nothing** while their keys are invalid: Loki has no error lines for `orders-*` in the outage window. The real signals are `lab_order_e2e_success` → 0 and `OrdersNotProcessed` after 10 min |
| 2 | smoke stage 8 warns after the ConfigMap patch | stage 8 reads the real JWT `exp` and **does not warn**. Documented with `TOKEN_WARN_DAYS=40 make test` as the way to see it |
| 3 B | pause with `argocd app set … --self-heal=false` | the ApplicationSet controller reverts that on a generated Application. The working method, used in Phase 5 X8, is to **pause the hub application controller** (documented, with the warning that it pauses all GitOps) |
| 3 B | (not mentioned) | **Kyverno removes its own webhooks on a graceful stop: unsigned images are admitted during a total outage** (known residual D-10). The VAP allowlist still denies foreign images. Now an explicit expected signal |
| 4 | ACK waits until resync, so restart the controller | ACK **recreates the queue by itself** within its 300 s resync (observed 150 s; 11 s in the assessment). The restart is optional |
| §9 | `argocd app set --all …` | not a valid command. Replaced by "controller replicas back to 1, no drill registration left, `make post-bootstrap`" |

### Execution evidence (2026-10-03, UTC)
| Drill | Injection | Expected signal observed | Recovery |
|---|---|---|---|
| 3 A | one Kyverno replica deleted 07:30:29 | unsigned image denied by Kyverno at +0, +6 and +11 s | replacement Ready (rollout complete) |
| 3 B | hub app-controller → 0, Kyverno → 0 at 07:31:18 | 0 Kyverno webhooks; **unsigned admitted** (dry run); `alpine` denied by the VAP; `KyvernoDown[spoke-nonprod]` pending 07:32:59, **firing 07:35:02** | controller → 1 at 07:35:02. Kyverno 2/2 on two nodes and 5 webhooks at 07:35:50; unsigned denied again; alert cleared |
| 4 | `orders-dev-dlq` deleted in moto 07:36:35 | ACK log `created new resource … orders-dev-dlq` 07:39:02; queue back at **+150 s**; redrive policy intact | none needed |
| 6 | `post-mortem-drill` pod (signed image) failed and was deleted | `kubectl logs` NotFound. **Loki** returned `CRITICAL-PANIC: drill marker 1791013171` with `cluster/namespace/pod/container` labels; the scheduling events are in `job="kubernetes-events"` | — |
| 2 | recorded expiry of `argocd-spoke-nonprod` = now + 2 d at 07:41 | `SpokeTokenExpiringSoon` pending at once, **firing 07:46:51** | `make post-bootstrap` 07:46:51–07:48:44 ("shortest left: 1 days" → renewed). All 5 credentials at 30 days; alert cleared 07:49:44 |
| 5 | registration `tenant-workloads` `51db060` at 07:49:59 | `orders-demo-dev` Synced/Healthy 07:53:04; QBS ACTIVE; queues Synced. `post-bootstrap` created `orders-demo-dev-aws` / IAM user `orders-demo-dev-worker` (acct 111111111111) and restarted the worker | deregistration `073c953` at 07:55:07, Application pruned 07:56:40. `make orphans` showed exactly ns + IAM user (remove) and table (report). `post-bootstrap` step 6 removed the ns and IAM user and kept the table; `PRUNE_DATA=1 orphans.sh` deleted the table. Tables left: `orders-dev-history`, `orders-test-history` only |
| 1 | `docker restart moto-cloud` 07:58:55 | `lab_order_e2e_success` 0: nonprod 07:59:44, prod 08:01:50. `OrdersNotProcessed` firing: nonprod 08:10:03, prod 08:12:34. No worker error logs | `make post-bootstrap` 08:10:04–08:12:17: new keys in both accounts, workers restarted, smoke 12/12. e2e back to 1 at 08:14:40 (nonprod) and 08:17:02 (prod); alerts cleared 08:17:33 |

### V-6 — smoke asserts the control
Stage 11 captures the denial message. It fails unless the unsigned probe's message contains `Policy tenant-images-signed failed` and the `alpine` probe's contains `ValidatingAdmissionPolicy 'tenant-image-registry-allowlist'`.
* **Negative check:** a non-compliant `alpine` is denied by Pod Security, and that message does **not** satisfy the check.
* The smoke run after the change passed. Output per namespace: "unsigned image denied by Kyverno, alpine denied by the allowlist VAP, running image admitted".

## 3. Step 0.6 — Digest pins (L3-1)

* **Digest source:** each digest is the **multi-arch index digest of the deployed tag**. It was resolved with `docker buildx imagetools inspect` and is identical to the `imageID` the running pods already had, so nothing was re-pulled.
* **Redis:** `ecr-public.aws.com` rate-limited the lookup. It was cross-checked against `docker.io/library/redis:8.6.4-alpine`, which has the same index digest as the running `imageID`.

| Image | Digest | Where |
|---|---|---|
| `quay.io/argoproj/argocd:v3.5.3` | `sha256:dd3f47d5…4bfa` | `clusters/values-argocd-hub.yaml` `global.image.tag` |
| `…/redis:8.6.4-alpine` | `sha256:2cc044fc…0763` | same file, `redis.image.tag` |
| `ghcr.io/headlamp-k8s/headlamp:v0.45.0` | `sha256:db3f0e0f…db49` | `applicationsets/addon-headlamp.yaml` |
| `docker.io/traefik:v3.7.13` (hub) | `sha256:24841fe2…44a0` | `applicationsets/addon-traefik.yaml` **and** the bootstrap install in `scripts/setup-hub-spoke.sh` |
| `registry.k8s.io/kro/kro:v0.9.4` | `sha256:eaf9fbad…6fb9` | `platform-catalog/controllers/kro/values-kro.yaml` |
| `…/sqs-controller:1.7.1` | `sha256:0b506001…f420` | `platform-catalog/controllers/ack/values-sqs.yaml` |

**Method:**
* All six charts accept `tag: "<tag>@sha256:…"`.
* Rendering each chart with and without the pin changes **only the image line**, except Argo CD.
* In Argo CD the chart turns the tag into the label `app.kubernetes.io/version: v3.5.3-sha256-dd3f47d5…`. That label is valid, it appears on metadata and pod-template labels, and it is **not** in any selector. The Argo CD diff before syncing was exactly 6 image lines, 1 Redis image line, and those labels.

**Rollout:**
1. Hub: `5afc575`. Headlamp and Traefik auto-synced and rolled out. Argo CD by **manual sync of `argo-cd` as `platform-admin` with its own `--config`** (08:20:30); all 6 pods ran by digest at 08:22:56; Synced/Healthy.
2. Nonprod: catalog `ae8e1b8` on `main`. kro and ACK rolled out; QueueBackedServices ACTIVE; queues Synced.
3. Prod: tag **`v1.7.2`** (= `ae8e1b8`; `v1.7.1..v1.7.2` changes only the two values files), `blueprint-revisions.env` (`8c77f41`), `make promote-blueprints`. kro and ACK rolled out; `addon-kro/ack-sqs/kro-blueprints-spoke-prod` at `ae8e1b8`, Synced/Healthy.

**Scope notes:**
* Hub Traefik was not in the plan's 0.6 list, but it is in the assessment's L3-1. It is pinned here the same way.
* Still on tags, **by design** (plan 0.6): the k3s system images in `kube-system`, i.e. CoreDNS, local-path, metrics-server, klipper, and the spokes' **k3s-bundled Traefik** `rancher/mirrored-library-traefik:3.6.13` (moves to GitOps in Track F).

## 4. Step 0.7 — Repo hygiene & document status (L1-4, L1-5, L2-6)

* **Status banners:** a `> **Status: …**` line after the title of every `docs/**/*.md`, 69 files. The diff for each is +2 lines, except the naming-standards rewrite below.

  | Status | Files |
  |---|---|
  | Current | developer tutorial, both runbooks, AI-assessment prompt, the 2026-10-03 assessment, this remediation folder |
  | Design reference | naming standards, Well-Architected guide, lab progression, promotion guardrails, Phase 6 roadmap |
  | Historical | the 2026-09-30 assessment and all 52 files in `docs/remediation/2026-09-30-lab-assessment/` |

* **Naming standards** (`argocd-visual-design-and-naming-standards.md`):
  * `message-processor` → `queue-backed-service`; `MessageProcessor` → `QueueBackedService`.
  * Pillar examples in goTemplate syntax.
  * §4 now shows the live single `tenant-workloads` ApplicationSet (Git files generator, registration format) instead of `tenant-workloads-nonprod`.
  * §5 checklist now lists the steps of the current onboarding model.
  * §1's `tenant-a-*` names are kept: they are the deliberate "anti-pattern" examples.
* **Well-Architected guide:** its only `tenant-a-dev` mention describes the rename, so the banner is enough.
* **`production-promotion-guardrails.md`:** the one broken link (to the deleted `tenant-workloads-prod.yaml`) now points to `tenant-workloads.yaml`.
* **`platform-charts`** (`5a218aa`, `d36f8c2`):
  * The README is rewritten: the real chart, what kro expands it into, GHCR OCI, the immutable-release table, the workflow's trigger paths, and how Argo CD consumes the chart.
  * `message-processor-*.tgz` and `dist/` were already untracked (0.2).
  * **I-1 (new):** `make package-all` / `scripts/package-and-push.sh` ran `helm push` to GHCR **unconditionally**. A local run with registry credentials could therefore overwrite `1.0.0` and bypass the 0.2 workflow guard. The script now applies the same rule as the workflow: identical → skip; different → refuse; only an explicit `not found` → push; any other error → refuse.
  * Tested locally: the unchanged chart printed "identical; nothing to push" (rc 0); a template changed without a version bump printed "DIFFERENT content. Bump 'version'" (rc 1). The push path was not exercised.
* **`gitops-control-plane`:** committed `addons/probes/__pycache__/*.pyc` removed; `__pycache__/` and `*.pyc` added to `.gitignore`.
* **Host leftovers (L1-5, O-4: report only, untouched):**
  * k3d `argolab`: 5 containers, Exited for 2 weeks;
  * `k3d-registry`: Exited for 2 weeks;
  * kind `helm-lab-control-plane`: **Up 35 hours**.

## 5. Regression (after all steps)
| Check | Result |
|---|---|
| Applications | 32/32 Synced/Healthy |
| `scripts/smoke-test-hub-spoke.sh` | ✅ All passed (rc 0, 0 `✘`), including the new stage 11 assertions |
| `scripts/audit-impersonation.sh` | ✅ PASS |
| `make test-alert-rules` | ✅ SUCCESS |
| Firing alerts | 0 |
| Images without digest outside `kube-system` | **none** on hub, spoke-nonprod or spoke-prod |

## 6. Notes for the validator
* **Live-state side effects of the drills:**
  * Spoke and Headlamp tokens were **renewed** by Drill 2; they now expire about **2026-11-02**.
  * Moto restarted and the worker IAM keys were re-issued (Drill 1).
  * Kyverno pods were replaced (Drill 3).
  * `orders-demo` was created and fully removed (Drill 5; `tenant-workloads` net zero).
* **Observation (no action in Track 0):** the `orders-processor` worker is **silent** when its SQS calls fail with invalid keys. The synthetic probe is the only signal. Logging receive errors in the app would make F-1 visible in Loki. Suggest an app backlog item.
* **Process:** all commits went directly to `main`; PR-only mode arrives with A.4 (V-7).
* **Suggested checks:**
  * render `README.md`'s diagram;
  * re-run any drill from the playbook as written (Drills 3 A, 4 and 6 are fast);
  * compare the six digests with the registries and with the running `imageID`s;
  * `git diff --numstat` of `65017de` (only +2 per file outside the naming-standards doc);
  * `bash platform-charts/scripts/package-and-push.sh` (must say "identical; nothing to push").

## 7. Track 0 status after this report
| Step | Status |
|---|---|
| 0.1–0.3 | ✅ Closed (validation-02) |
| 0.4 | 🔧 Done. **Awaiting validation-03** |
| 0.5 | 🔧 Done; all drills executed. **Awaiting validation-03** |
| 0.6 | 🔧 Done on hub, nonprod and prod (catalog v1.7.2). **Awaiting validation-03** |
| 0.7 | 🔧 Done; host leftovers reported only. **Awaiting validation-03** |
| V-6 | 🔧 Fixed. **Awaiting validation-03** |
