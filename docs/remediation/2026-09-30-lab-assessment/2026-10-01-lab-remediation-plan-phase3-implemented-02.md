# Phase 3 Implementation Report — Run #02: Track B (2026-10-01)

> **Status: Historical.** Record of the 2026-09-30 assessment and its remediation (Phases 1–5, closed 2026-10-03). Kept as evidence and not updated. For the lab as it is today, see the [README](../../../README.md) and the [2026-10-03 assessment](../../assessments/2026-10-03-lab-assessment.md).

| | |
|---|---|
| **Plan** | [`2026-10-01-lab-remediation-plan-phase3.md`](2026-10-01-lab-remediation-plan-phase3.md) v1.0 (GREEN LIGHT, R-0 to R-4) |
| **Preceded by** | [Implemented-01](2026-10-01-lab-remediation-plan-phase3-implemented-01.md), validated 🟢 in [Validation-01](2026-10-01-lab-remediation-plan-phase3-validation-01.md) |
| **Scope executed** | **B.1, B.2, B.3, B.5, B.6** |
| **Not executed** | **B.4** (stretch: Argo CD self-management) and **B.7** (full rebuild; requires explicit owner approval) |
| **Implemented by** | Claude (Opus 5.5), the plan's author. Independent validation requested. |
| **Commits** (`gitops-control-plane`) | `7fd2adf` (B.1) · `5aeb71b`, `c938212` (B.2) · `aeed40a`, `98300d7` (B.3) · `aeddef3` (B.5/B.6) |
| **Hub `argo-cd` Helm revision** | 13 (registers the OCI chart repos; `argocd-secret` keys verified intact afterwards, so the D-4 fix holds) |

---

## 1. Outcome Summary

| Step | Finding | Result |
|---|---|:-:|
| B.1 | PV-4 `projects/` not reconciled | ✅ `platform-projects` Application; injected drift reverted in **5 s** |
| B.2 | L2-1 / L3-8 imperative spoke controllers | ✅ kro + ACK on both spokes adopted by Argo CD with **zero disruption**; Helm records removed; deleted `deploy/kro` recreated in **15 s** |
| B.3 | Hub Traefik under GitOps | ✅ Adopted with zero disruption; scaled-to-2 drift reverted in **5 s** |
| B.5 | L3-6 floating versions | ✅ k3s image and moto pinned (moto by **registry** digest, see D-9); Argo CD and Traefik were already pinned |
| B.6 | L3-7 sync resilience | ✅ `retry` on all 15 Applications |

**L2-1 / L3-8 (High) → Closed**: the spoke platform layer is declared in Git, promotion-gated and self-healing. **L3-6 → Closed.** **L3-7 → Closed** (by retry; see the design note in plan §5 B.6). **PV-4 → Closed.**

---

## 2. Deviations & Findings

| ID | Type | Detail |
|---|---|---|
| **D-7** | Remark implementation | R-2 applied as the ApplicationSet spec field `syncPolicy.preserveResourcesOnDeletion: true` on `addons-spoke` and `addons-spoke-ack-credentials` (the annotation named in R-2 doesn't exist for ApplicationSets). |
| **D-8** | Design addition | Controller values come from `platform-catalog` at each cluster's **`blueprints-revision`** (nonprod `main`, prod `v1.2.0`). Controller config (e.g. ACK resync) is now gated by the same promotion as the blueprints, so a values change can no longer reach prod and non-prod at once. |
| **D-9** | Plan fact error (author) | Plan fact F9 / Step B.5 quoted moto `sha256:44fa7c38…`. That is the **local image ID**, which can't be pulled. The pin uses the registry digest **`motoserver/moto@sha256:91fd602a…`** (same image, 5.2.3.dev0). |
| **D-10** | Pre-existing drift found | kro was originally installed with **no values**: `controllers/kro/values-kro.yaml` had never been applied. Adoption showed the chart defaults already equal those values (diff = tracking metadata only), so no rollout was needed. The author's prediction of "one expected kro rollout" was wrong, harmlessly. |
| **D-11** | Design choice | `prune: false` on the addon and Traefik Applications: a chart upgrade that drops an object leaves it orphaned instead of deleting it (a safe default for CRD-bearing controller charts). `platform-projects` also uses `prune: false` + per-project `Prune=false` + no resources finalizer. |
| **D-12** | Bootstrap ordering | Traefik **remains a bootstrap-only Helm install** in `setup-hub-spoke.sh` (pinned 41.6.1, skipped if present, Helm record removed): the Argo CD UI/CLI ingress needs it before the root app exists. Argo CD owns it after `make bootstrap`, the same pattern as Argo CD itself. |
| **D-13** | Operator note | The shared CLI config `~/.config/argocd/config` was found logged in as `tenant-a` (the owner's own session). The author used a separate config file for `platform-admin` automation instead of overwriting the owner's session. `register-spokes.sh` needs a `platform-admin` session (it lists clusters); run `make password` and log in as `platform-admin` before `make rotate-spoke-tokens`. |

---

## 3. Evidence

### B.1: `platform-projects`
* Pre-check: `kubectl diff -f projects/*.yaml` showed **no drift** for any of the 4 AppProjects.
* All AppProjects (now 5, including `platform-addons`) carry tracking-id `platform-projects:…` and `sync-options: Prune=false`.
* **Self-heal test:** injected `https://github.com/evil/injected.git` into `tenant-workloads.spec.sourceRepos` at 05:17:29Z; **reverted after 5 s**.

### B.2: spoke controllers
| Check | nonprod | prod |
|---|---|---|
| Generated apps | `addon-{kro,ack-sqs,ack-credentials}-spoke-nonprod` | `…-spoke-prod` |
| Values revision | `main` → `7fab51d` | `v1.2.0` → `7fab51d` |
| Pre-sync review | 0 pruning; CRDs (kro 2, ACK 3) already Synced; non-tracking diff lines **0** | same |
| Controller pods after sync | **unchanged** (`kro-…-5dgm9` restarts 4 / start 2026-09-29T22:00:02Z; `ack-…-qkk7t` 0 / 02:13:52Z) | **unchanged** (`kro-…-z2fww` 3; `ack-…-h76j2` 0) |
| ACK resync | 300 | 300 |
| Helm records | `sh.helm.release.v1.{kro.v1, ack-sqs-controller.v1,.v2}` deleted; `helm list` empty | same |
| Workloads | RGD Active; `orders-dev`, `orders-test` ACTIVE | `orders-prod` ACTIVE |

* **Self-heal (auto-sync enabled after adoption):** `kubectl delete deploy/kro` on nonprod at 05:23:17Z → **recreated and Ready after 15 s**. kro's own drift correction still works (`orders-dev-worker` scaled to 3 → reverted to 1 in 10 s).
* Durable: `register-spokes.sh` writes `addons-managed: "true"`; `setup-hub-spoke.sh` no longer installs kro/ACK or applies the ACK credentials Secret.

### B.3: hub Traefik
* Live release: `traefik-41.6.1`, values `null`, 25 CRDs from `crds/`.
* Pre-sync review: 31 resources (25 CRDs already Synced), 6 OutOfSync with tracking-only diffs, 0 pruning.
* After sync: the same pod `traefik-7786f5498d-b582x` (0 restarts); `localhost`, `argocd.localhost`, `headlamp.localhost` → 200; Argo CD → spokes `Successful`.
* **Self-heal:** scaled Traefik to 2 → **reverted to 1 after 5 s**; UIs still 200.

### B.5 / B.6
* `setup-hub-spoke.sh`: `--image rancher/k3s:v1.35.5-k3s1` ×3; `motoserver/moto@sha256:91fd602a…`; no `:latest` remaining; every Helm install has `--version`.
* All **15** Applications: `retry.limit=5`, `selfHeal=true`, Synced/Healthy.

### Regression
* Smoke test (8 stages; expected-app set now includes `platform-projects`, `addon-traefik` and the 6 addon apps): **exit 0**.
* `argocd-secret` keys intact after Helm revision 13. Both spokes `Successful`.

---

## 4. Remaining in Track B (decision needed)

| Step | Status | Note |
|---|---|---|
| **B.4** (stretch) | Not started | Argo CD self-management. The D-4 fix (`createSecret: false`) removes the main risk; can be done any time. |
| **B.7** | **Awaiting explicit owner approval** | `make teardown && make setup && make bootstrap`. Destroys live state (Git/GHCR unaffected). Also applies the durable A.1 bindings (API ports on 127.0.0.1) and the B.5 pins. Note: after a rebuild, the D.2 moto test happens implicitly and token/password provisioning runs from scratch. |

Per the plan's §8 order, **Track C** (C.1 tenant kinds → blueprint `v1.3.0` → C.3 kro aggregation) is next; B.4 and B.7 come at the end of the phase.
