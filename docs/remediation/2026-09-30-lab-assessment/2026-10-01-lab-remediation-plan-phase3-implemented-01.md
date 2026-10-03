# Phase 3 Implementation Report — Run #01 (2026-10-01)

| | |
|---|---|
| **Plan** | [`2026-10-01-lab-remediation-plan-phase3.md`](2026-10-01-lab-remediation-plan-phase3.md) v1.0, approved (GREEN LIGHT, remarks R-0 to R-4) at `c568af6` |
| **Scope executed** | **Track 0** Steps 0.1, 0.2 · **Track A** Steps A.1, A.2, A.3 (including PV2-3) |
| **Scope not executed** | Steps **0.3, 0.4**: owner actions in the GitHub UI (see §5). Tracks **B, C, D**: next runs. |
| **Implemented by** | Claude (Opus 5.5), the plan's author. Independent validation is requested. |
| **Commits** (`gitops-control-plane`) | `704a63d` (Track 0) · `55753c1` (A.1) · `892eedb` (A.2) · `8e83632`, `9240f76`, `ab318e0` (A.3) |
| **Helm revisions** (hub `argo-cd`) | 9 (accounts + RBAC) · 10 (admin disabled; **caused D-4**) · 11 (`createSecret: false`) · 12 (no-op regression check) |

---

## 1. Outcome Summary

| Step | Finding | Result |
|---|---|:-:|
| 0.1 | PV2-5 token rotation | ✅ Rotated; new expiry **2026-10-31 04:05 UTC** (see D-1); Headlamp restart defect fixed (D-2) |
| 0.2 | L3-3 (minimal) expiry check | ✅ Smoke stage `[8/8]`; WARN/FAIL proven with negative tests |
| A.1 | L4-9 / PV2-4 localhost binding | ✅ 8080, 8443, 8081, 8082 → `127.0.0.1` live; durable fix in setup (API ports and moto as planned: B.7 / D.2) |
| A.2 | L4-2 Argo CD identities | ✅ `admin` disabled, hash removed from Git, `platform-admin` / `tenant-a` with deny-by-default RBAC. One **incident** during execution (D-4), recovered and durably fixed |
| A.3 | L4-1 residual (Headlamp auth) + PV2-3 | ✅ Basic auth enforced (401 without credentials), least privilege intact behind it; hub viewer reads Argo CD objects |

**L4-1 (Critical) → Closed** per the plan's criteria: authenticated, bound to localhost, read-only, strict TLS, no hub admin. Residual (as planned, §1.2): `-dev` CORS relaxation and HTTP.
**L4-2 (High) → Closed** for the lab scope: no published credential, no shared admin, RBAC deny-by-default. Residual: SSO and TLS deferred to Phase 4.

---

## 2. Deviations, Defects Found & Incident

| ID | Type | What happened | Resolution |
|---|---|---|---|
| **D-1** | Plan premise (author error) | Step 0.1 was framed as "neutralise the 2026-10-31 deadline". A 30-day TokenRequest token issued now expires 30 days from now, so rotating moved expiry only from **01:00** to **04:05 UTC on 2026-10-31**. The previous tokens had been issued about 27 h earlier. Rotation buys exactly the time since the last rotation. | Expiry is managed by **cadence**, not a one-off: Step 0.2 now WARNs at < 7 days and FAILs on expiry, covering all 8 credentials. **Next rotation is due before 2026-10-31 04:05 UTC.** |
| **D-2** | Latent defect (pre-existing) | `make rotate-spoke-tokens` never actually renewed Headlamp. The kubeconfig Secret is mounted with `subPath`, which is never refreshed in a running pod, and `setup-credentials.sh` didn't restart the pod. Evidence: after rotation the Secret had exp 04:05:10 while the pod still had 03:31:13. | `setup-credentials.sh` now restarts Headlamp and waits for the rollout. Smoke stage 8 also checks the token **mounted in the running pod**, so a missed restart is detected. |
| **D-3** | Plan procedure (author error) | A.1's "add 127.0.0.1 mapping, then delete 0.0.0.0" can't work, because the same host port conflicts. `k3d cluster edit` also refuses `--port-add` and `--port-delete` in one call (`FATA Cannot combine port addition and deletion`). | Used **delete, then add**: two load-balancer recreations per cluster, about 37 s of ingress interruption each (nonprod → prod → hub). API, Argo CD and pods were unaffected (Argo CD reaches spokes over the Docker network). R-4's fallback was not needed. |
| **D-4** | **Incident** (Helm behaviour) | Helm revision 10 (removing the admin hash and disabling admin) **wiped the account passwords** that Argo CD had written into `argocd-secret`. The chart renders that Secret from values only; the author wrongly assumed Helm's three-way merge would keep runtime-written keys. From **04:15:02Z until recovery about 1–2 min later**, no account could log in. Argo CD controllers and all apps were unaffected (0 out of sync). | **Recovered** via the plan's break-glass: bcrypt hashes of the existing passwords were patched directly into `argocd-secret` with `kubectl`. **Durable fix:** `configs.secret.createSecret: false` plus `helm.sh/resource-policy: keep` on the live Secret. Verified: the Secret is no longer in the Helm manifest, and its keys survived **two** further upgrades (rev 11, 12). This also protects Step B.4 (Argo CD self-management). |
| **D-5** | Tooling | `argocd login … --plaintext` failed: `127.0.0.1:8080` also completes a TLS handshake (Traefik), and the CLI's TLS probe runs before `--plaintext` applies. | Use `--skip-test-tls`. Applied in `setup-hub-spoke.sh`. |
| **D-6** | Scope pulled forward | While editing the setup flow for A.2: pinned the Argo CD chart `--version 10.9.4` (a B.5 item), and added a CLI login so `register-spokes.sh` works on a fresh rebuild. That was a latent gap: its connectivity check needs a logged-in CLI, and nothing provided one. | Recorded so B.5 and B.7 validation can account for them. |
| **D-7** | Reviewer remark interpretation (for B.2) | R-2 asks for an `argocd.argoproj.io/preserve-resources-on-deletion` *annotation*; for an ApplicationSet the setting is `spec.syncPolicy.preserveResourcesOnDeletion: true`. | Will be applied as the spec field in B.2 (R-2's intent), and recorded there. |

---

## 3. Step Evidence

### Step 0.1: rotation
* Pre-flight: CLI logged in, all 3 clusters `Successful`, scripts confirmed not to echo token values.
* `make rotate-spoke-tokens` → exit 0; both spokes re-registered and verified `Successful`.
* JWT claims (no token values shown): `cluster-spoke-nonprod` iat `04:05:04Z` exp `2026-10-31T04:05:04Z`; `cluster-spoke-prod` exp `…04:05:06Z`; Headlamp Secret ×3 exp `…04:05:10Z`.
* After the D-2 fix, the Headlamp **pod** mounts exp `…04:05:10Z`. Proxy reads: hub/nonprod/prod 200 (one transient 504 on the first nonprod request after restart, then 15/15 × 200).

### Step 0.2: smoke stage `[8/8]`
| Run | Result |
|---|---|
| Normal | 8 credentials, "29d left", ✔, exit 0 |
| `SMOKE_NOW_EPOCH` = now + 27 d | 8 × ⚠ "2d left … run 'make rotate-spoke-tokens'", exit 0 |
| `SMOKE_NOW_EPOCH` = now + 31 d | 8 × ✘ EXPIRED, **exit 1** |
| Leak check | 0 JWT-like strings in output |

### Step A.1: bindings (`docker ps`)
```
k3d-hub-cluster-serverlb     127.0.0.1:8080->80, 127.0.0.1:8443->443, 0.0.0.0:34643->6443
k3d-spoke-nonprod-serverlb   127.0.0.1:8081->80, 0.0.0.0:37837->6443
k3d-spoke-prod-serverlb      127.0.0.1:8082->80, 0.0.0.0:45133->6443
moto-cloud                   0.0.0.0:5000->5000            (rebound in D.2, as planned)
```
* All UIs and apps return 200 on `localhost`, `argocd.localhost`, `headlamp.localhost` and `orders-{dev,test,prod}.localhost`.
* The external negative test from the Windows host IP was **inconclusive**: the control port 5000, still on `0.0.0.0`, was also unreachable from that vantage point. The binding table is the evidence.
* Docker Desktop is in use, so `0.0.0.0` meant *all Windows host interfaces*. A.1 matters more than the assessment's WSL-NAT assumption suggested.
* Durable: `setup-hub-spoke.sh` creates all ingress ports, API ports (`127.0.0.1:6550–6552`) and moto on `127.0.0.1`.

### Step A.2: Argo CD identities
| Check | Result |
|---|---|
| `admin` / `admin123` | ✘ `Invalid username or password` (`admin.enabled=false`) |
| `platform-admin` | ✔ login; 7 → 8 apps, 3 clusters |
| `tenant-a` visible apps | `orders-dev`, `orders-test`, `orders-prod` only; `addon-headlamp` → permission denied; clusters: none; projects: `tenant-workloads` only |
| `tenant-a` sync `orders-dev` (dry run) | ✔ Succeeded |
| `tenant-a` sync `orders-prod` / delete `orders-dev` | ✘ permission denied / ✘ permission denied |
| `git grep '\$2a\$'` (working tree) | 0 |
| `admin123` references outside audit docs | 0 (Makefile, README, tutorial, setup script updated) |
| Passwords | Generated into `~/.config/gitops-lab/*.password` (dir 700, files 600); set as bcrypt via `scripts/setup-argocd-accounts.sh` (idempotent: files unchanged on re-run, 0 secret-like strings in output) |

### Step A.3: Headlamp authentication
| Request | Result |
|---|:-:|
| No credentials / wrong password / wrong user | 401 / 401 / 401 |
| Correct credentials | 200 |
| Authenticated read: hub / nonprod / prod | 200 / 200 / 200 |
| Unauthenticated read of prod | 401 |
| Authenticated **write** to `orders-prod` | **403**; probe ConfigMap NotFound |
| Authenticated read of hub `argocd` Secrets | **403** |
| Authenticated read of hub Argo CD Applications (PV2-3) | 200; `can-i list applications.argoproj.io` → yes |
| Middleware `removeHeader` | `true` (credentials not forwarded upstream) |
| `addon-headlamp`, `addon-headlamp-auth` | Synced / Healthy |

* Delivered in two stages: the Middleware first, unattached (confirmed loaded, no Traefik errors), then the ingress annotation, so live traffic was never exposed to an unverified Middleware.
* The htpasswd Secret holds only a bcrypt hash and has no `last-applied` annotation.

---

## 4. Regression

* Full smoke test (8 stages, including the new expiry stage and the new expected app `addon-headlamp-auth`): **exit 0**.
* All Argo CD Applications Synced/Healthy. Both spokes `Successful`.
* No change to workloads, blueprints, ACK, PSS, NetworkPolicy, PDB or the promotion gates.

## 5. Owner Actions Pending (Track 0)

| Step | Action | Verification |
|---|---|---|
| **0.3** | GitHub UI → Settings → Branches → `main` of `gitops-control-plane`, `platform-catalog`, `orders-processor`, `platform-charts`: **block force pushes** and **block deletion** | `curl -s https://api.github.com/repos/brunobml/<repo>/branches/main \| jq .protected` → `true` |
| **0.4** (optional) | GitHub → Packages → `orders-processor` → delete version `sha-c594f1b` | absent from the GHCR tag list |

## 6. Carry-forward

* **Rotation due before 2026-10-31 04:05 UTC** (smoke stage 8 starts warning on 2026-10-24).
* API ports remain on `0.0.0.0` until the B.7 rebuild; moto until D.2.
* Next: Track B (B.1 → B.2 with R-2 as D-7 → B.3 → B.5/B.6).

---

## 7. Post-run Changes (2026-10-01, after owner feedback)

| ID | Change | Reason | Commits |
|---|---|---|---|
| **P-1** | **Headlamp RBAC: added read-only `headlamp-cluster-viewer`** (nodes, persistentvolumes, storage classes, CSI, ingress/runtime/priority classes, node/pod metrics) on all 3 clusters | **Defect** reported by the owner: Headlamp could not show nodes. The built-in `view` role (adopted in Phase 2 MC-5 on the author's recommendation) excludes cluster-scoped objects; the author missed this. Secrets, writes and exec remain denied (re-verified with `can-i`). | `b95e543` |
| **P-2** | **Headlamp basic auth removed** (owner decision). Detached the ingress annotation first (`ac6e304`), then removed the Middleware, the `addon-headlamp-auth` Application, `setup-auth.sh`, the htpasswd Secret and its password file. | The owner reported repeated credential prompts (Headlamp's background requests don't reuse basic-auth credentials reliably). The author advised that for a **single-user** lab the password adds high friction for little protection: after A.1 Headlamp is reachable only from `127.0.0.1`, and anyone on the machine already has a **cluster-admin** `~/.kube/config`. Production would use OIDC SSO (Phase 4), not basic auth. | `ac6e304`, this commit |

**Revised status:** **L4-1 → Closed with accepted residual risk.** Headlamp is localhost-only, read-only (no Secrets, writes or exec), uses strict TLS and dedicated tokens, and has no hub admin. It has no login, and runs with `-dev` (relaxed CORS). The accepted residual risk is that a malicious web page open in the owner's browser could read (not change) cluster state through `localhost`. SSO is scheduled for Phase 4.
