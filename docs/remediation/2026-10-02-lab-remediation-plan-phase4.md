# Lab Remediation Plan: Phase 4 — Single Sign-On, Supply-Chain Trust & ApplicationSet Modernization
## Hub-and-Spoke GitOps Control Plane (2026-10-02)

* **Plan Version:** 1.0 (initial submission)
* **Assessment Reference:** [`../assessments/2026-09-30-lab-assessment.md`](../assessments/2026-09-30-lab-assessment.md)
* **Phase 3 Baseline:** [`2026-10-01-lab-remediation-plan-phase3-validation-07.md`](2026-10-01-lab-remediation-plan-phase3-validation-07.md) (Phase 3 complete; B.7 full rebuild accepted; V1–V17 PASS)
* **Target Repositories:** `gitops-control-plane`, `platform-catalog`, `orders-processor`, `tenant-workloads`
* **Author:** Claude (Opus 5.5)

---

## Review & Approval Sign-Off

| Field | Details |
|---|---|
| **Current Status** | ⏳ **AWAITING PEER REVIEW** — no step of this plan has been executed |
| **Plan Version** | `v1.0` |
| **Author** | Claude (Opus 5.5) |
| **Reviewed By** | _pending_ (Antigravity) |
| **Review Date** | _pending_ |
| **Authorization Decision** | _pending_ |
| **Early authorization requested** | **Step 0.2** (remove Headlamp `-dev`, new finding P4-1): a one-line fix for a live cross-origin data exposure, independent of every other track |

### Owner decisions requested

| ID | Question | Author's recommendation |
|---|---|---|
| **O-1** | After SSO is accepted, retire the local `tenant-a` Argo CD account? | **Yes.** Keep local `platform-admin` as break-glass and for automation (`post-bootstrap.sh`, `register-spokes.sh`) |
| **O-2** | Which SSO groups may open Headlamp? | **Both** `lab-platform-admins` and `lab-tenant-a` (Headlamp's cluster tokens are read-only, Secrets excluded) |
| **O-3** | Kyverno failure mode for tenant namespaces when Kyverno is down | **Fail closed** for tenant namespaces only (`kube-system`, `kyverno`, controllers unaffected) |
| **O-4** | Run the end-of-phase rebuild acceptance (Track D)? | **Yes**, in an owner-approved window as in Phase 3 B.7 |

---

## 1. Executive Summary & Scope

Phase 3 made the lab reproducible from Git, least-privileged and cloud-isolated. Phase 4 covers what Phase 3 deliberately deferred:

* **who you are**: one sign-on for Argo CD and Headlamp,
* **what runs**: provenance for every image that reaches a spoke,
* **how tenants are declared**: safer templating and tenant self-registration.

### 1.1 Objectives

| Track | Theme | Findings addressed |
|---|---|---|
| **0** | Carry-overs and an urgent exposure | **P4-1** (new: Headlamp cross-origin), PV3-11 tag side, token deadline 2026-11-01 |
| **A** | Identity: Keycloak SSO | Phase 3 §1.2 deferral "SSO for Argo CD / Headlamp"; **P4-2** (new: Dex runs but is unused) |
| **B** | Supply-chain trust | **L4-8** (no signing, SBOM, scanning or admission verification; Actions pinned by tag) |
| **C** | ApplicationSet modernization | **L2-4** (fasttemplate), **L2-3** (List generators; tenants cannot self-register) |
| **D** | Acceptance | Full rebuild with SSO + signing in the build path |

### 1.2 Why Keycloak in the lab, rather than Dex + GitHub OAuth (the Phase 3 deferral)

| | Keycloak in the hub | Dex + GitHub OAuth App |
|---|---|---|
| External credentials | None (everything stays inside the lab) | GitHub OAuth App secret, created outside the lab |
| Works offline / after rebuild | Yes; the realm is code in Git | Needs the external app and network |
| Groups for RBAC | Native groups → `groups` claim | GitHub org/team membership (no org exists for this account) |
| Learning value | Realistic enterprise IdP pattern (OIDC, PKCE, groups, break-glass) | Simpler, but less representative |

### 1.3 Out of scope (deferred, with reasons)

| Item | Reason |
|---|---|
| L3-3 metrics and alerting stack | Still heavy for a laptop lab; smoke stages 8 and 9 cover the two failure modes that actually happened (token expiry, silent processing outage) |
| TLS on the lab UIs | Every UI is bound to `127.0.0.1`, and browsers treat `http://*.localhost` as a secure context. TLS would require trusting a local CA in the Windows browser (owner friction). **Residual risk: tokens cross loopback in clear text**; recorded per the lab security preferences. Fallback if A.0 shows OIDC needs HTTPS: §4 A.0 |
| Kubernetes API OIDC (Headlamp native OIDC) | Needs an HTTPS issuer and API-server flags on every cluster (cluster re-creation). oauth2-proxy gives the same sign-on without it (A.5) |
| Signing of platform Helm charts (OCI) | Images first; charts follow the same pattern later |
| Argo CD HA, EKS translation, moto persistence | Beyond lab parity goals; F-1 is handled by `make post-bootstrap` |

---

## 2. Pre-flight Facts (verified live on 2026-10-02 by the author)

| # | Fact | Evidence | Used by |
|---|---|---|---|
| F1 | **Headlamp v0.45.0 runs with `-dev`** = "Allow connections from other origins". A request with `Origin: https://evil.example` gets `Access-Control-Allow-Origin: https://evil.example` + `Access-Control-Allow-Credentials: true` | `headlamp-server -h`; `curl -H Origin` against `headlamp.localhost:8080/config` | 0.2 |
| F2 | Spoke tokens expire **2026-11-01** (`lab/token-expires`), issued by the B.7 rebuild | cluster Secret annotations | 0.1 |
| F3 | Argo CD `url=http://localhost:8080`, `server.insecure: true`, `admin.enabled=false`, local accounts `platform-admin`, `tenant-a`; `argocd-rbac-cm` `scopes: [groups]`, `policy.default: ""` | live `argocd-cm`, `argocd-rbac-cm` | A.4 |
| F4 | **Dex is deployed** (`argo-cd-argocd-dex-server`) but no connector is configured | live Deployment; no `dex.config` | A.4 (P4-2) |
| F5 | Hub CoreDNS imports `/etc/coredns/custom/*.override` and `*.server` from the optional ConfigMap `coredns-custom`, **which does not exist yet** | `coredns` Corefile, Deployment volumes | A.2 |
| F6 | Hub Traefik service exposes 80/443 only; Traefik `Middleware` CRD present (Phase 3 F4) | live Service, CRDs | A.2, A.5 |
| F7 | Keycloak `quay.io/keycloak/keycloak:26.8.0` = `sha256:b0f60d48…352bcc`; oauth2-proxy `v7.15.5` = `sha256:8498b0d0…017916`, chart `oauth2-proxy/oauth2-proxy` 10.7.1 | registry manifests, `helm search` | A.2, A.5 |
| F8 | Kyverno chart 3.9.1 (app v1.19.1); admission, background, cleanup and reports controllers can be toggled individually | `helm show values` | B.3 |
| F9 | `orders-processor` CI has **no** signing, SBOM, scanning or `id-token` permission; `cosign` is installed on the host | `ci.yaml`, `which cosign` | B.1, B.2 |
| F10 | 6 of 10 ApplicationSets use fasttemplate (`{{…}}`, no `goTemplate`); none use `goTemplate` | `grep` | C.1 |
| F11 | Tenant apps are hard-coded `list` elements in `tenant-workloads-{nonprod,prod}.yaml`; `tenant-workloads/tenants/tenant-a/{dev,test,prod}/orders-service.yaml` already exist per env | Git | C.2 |
| F12 | Host: 31 GiB RAM (≈ 22 GiB available), 16 CPUs; the lab uses ≈ 5 GiB | `free`, `docker stats` | A.2, B.3 sizing |
| F13 | `argocd` CLI v3.5.0 supports `argocd appset generate` (offline render) | `--help` | C.1 |

---

## 3. Track 0: Carry-overs & Urgent Exposure

### Step 0.1: Token deadline (PV2-5 recurrence)
Tokens expire **2026-11-01**. Either the Track D rebuild or `make rotate-spoke-tokens` renews them; whichever comes first, **no later than 2026-10-29**. Smoke stage 8 already alerts at < 7 days.

### Step 0.2: Remove Headlamp `-dev` (P4-1, **early authorization requested**)
* **Finding P4-1 (Medium):** with `-dev`, Headlamp answers cross-origin requests with credentials. Any web page open in the owner's browser can read cluster data through `headlamp.localhost:8080`. The tokens are read-only and exclude Secrets (Phase 3 A.3), so the impact is information disclosure (topology, ConfigMaps, events, logs).
* **Change:** delete `-dev` from `extraArgs` in `applicationsets/addon-headlamp.yaml` and `addons/headlamp/values.yaml`.
* **Verify:** the same `curl -H 'Origin: https://evil.example'` returns no `Access-Control-Allow-*` headers; Headlamp UI and "all clusters" view still work.
* **Rollback:** re-add the flag (one commit).

### Step 0.3: PV3-11 tag-side verification
The Track B release (B.2) is the next tag: confirm that GHCR receives `v*` and **no** `sha-*` tag for it.

---

## 4. Track A: Identity — Keycloak Single Sign-On

**Target design**

```
browser ──http://keycloak.localhost:8080──► hub Traefik ──► keycloak:8080        (issuer, login pages)
argocd-server / oauth2-proxy ──same URL──► CoreDNS rewrite ──► keycloak.keycloak.svc:8080
                                           (no Traefik hop; same host:port, so the issuer string matches)

Argo CD   : native OIDC, public client + PKCE (no client secret), groups → RBAC; Dex disabled
Headlamp  : Traefik ForwardAuth → oauth2-proxy (confidential client) → Headlamp (unchanged read-only kubeconfig)
Break-glass: local platform-admin (Argo CD) + kubectl; Keycloak bootstrap admin for the IdP itself
```

The issuer URL must be byte-identical for the browser and for in-cluster clients. Keycloak listens on 8080 and the browser reaches the hub on `127.0.0.1:8080`, so a CoreDNS rewrite to the Keycloak Service on port 8080 makes `http://keycloak.localhost:8080` valid on both paths.

### Step A.0: Spike (read-only; nothing committed)
Two assumptions decide the design. Verify them on a throwaway Keycloak in a scratch namespace, then delete it:
1. **Go resolvers inside `argocd-server` and `oauth2-proxy` resolve `keycloak.localhost` through CoreDNS** rather than short-circuiting `*.localhost` to loopback.
   * **Fallback:** issuer `http://keycloak.127.0.0.1.nip.io:8080`. Public DNS maps it to 127.0.0.1 for the browser, and the CoreDNS rewrite overrides it in-cluster.
2. **Argo CD 3.5 accepts an `http://` issuer with PKCE**, and the login round-trip works on `http://localhost:8080`.
   * **Fallback:** Keycloak on HTTPS via cert-manager with a lab CA and `oidc.rootCA` in Argo CD. This brings TLS into scope and needs owner consent (browser CA trust).

The outcome (hostname, HTTP/HTTPS) is recorded in the implementation report before A.1 starts.

### Step A.1: Lab identity secrets (outside Git)
New `scripts/setup-keycloak-secrets.sh`, same pattern as `setup-argocd-accounts.sh`:
* Generates, once, into `~/.config/gitops-lab/` (mode 600):
  * the Keycloak bootstrap admin password,
  * the passwords for `platform-user` and `tenant-a-user`,
  * the oauth2-proxy client secret and cookie secret.
* Applies them as Kubernetes Secrets in `keycloak` and `oauth2-proxy` on the hub. Never prints a value; re-runs keep existing values.
* Called by `setup-hub-spoke.sh` before Argo CD is installed, like the account step today. `make password` lists the new files.

### Step A.2: Keycloak as a GitOps addon (hub)
* `addons/keycloak/` (plain manifests), Application `addon-keycloak` in project `control-plane`:
  * Deployment of `quay.io/keycloak/keycloak:26.8.0@sha256:b0f60d48…`.
  * `start-dev --import-realm`, `KC_HOSTNAME=<issuer from A.0>`, `KC_HTTP_ENABLED=true`.
  * Health on the management port 9000 (`/health/ready`).
  * Requests 512Mi / 250m, limit 1Gi (F12).
  * `runAsNonRoot`; PSS `baseline` namespace label (as Phase 2).
* **Stateless by design:** storage is the pod's file DB on `emptyDir`, and the realm is re-imported from Git at every start. Git is always the truth: no realm drift, no backup. User passwords come back from the A.1 Secret via the import's `${ENV}` placeholders. Residual: active SSO sessions end on a Keycloak restart (re-login only).
* Traefik Ingress `keycloak.localhost`; hub `coredns-custom` ConfigMap with the rewrite. The ConfigMap is created by this addon, which also keeps the rewrite in Git.
* NetworkPolicy: ingress to Keycloak only from Traefik, `argocd-server` and `oauth2-proxy`.

### Step A.3: Realm as code
`addons/keycloak/realm-lab.json` (ConfigMap):

| Object | Configuration |
|---|---|
| Realm `lab` | brute-force detection on; password policy `length(12)`; SSO session 10 h; access token 5 min |
| Groups | `lab-platform-admins`, `lab-tenant-a` |
| Users | `platform-user` ∈ `lab-platform-admins`; `tenant-a-user` ∈ `lab-tenant-a`; credentials = `${…}` placeholders (A.1) |
| Client `argocd` | public, standard flow + **PKCE S256**, redirect `http://localhost:8080/auth/callback` and `http://argocd.localhost:8080/auth/callback`; direct grants **off** |
| Client `headlamp` | confidential (oauth2-proxy), redirect `http://headlamp.localhost:8080/oauth2/callback`; direct grants off |
| Client scope `groups` | group-membership mapper, `full.path=false`, claim `groups` in ID and access tokens |

### Step A.4: Argo CD OIDC (P4-2)
Changes in `clusters/values-argocd-hub.yaml`. Applied the Phase 3 D-32 way: commit, then a manual sync of `argo-cd` as `platform-admin`.
* `oidc.config`:
  * name `Keycloak`, issuer, `clientID: argocd`, `enablePKCEAuthentication: true`,
  * `requestedScopes: [openid, profile, email, groups]`.
* `dex.enabled: false`. Closes P4-2: one fewer pod and one fewer exposed component.
* `argocd-rbac-cm` additions: `g, lab-platform-admins, role:admin` and `g, lab-tenant-a, role:tenant-a`. Existing local-account lines stay.
* **Order (no lock-out):**
  1. SSO login works for both groups.
  2. Local `platform-admin` still works.
  3. Only then, if owner decision O-1 is yes, `accounts.tenant-a` is removed.
* CLI: `argocd login --sso` documented for humans. Automation keeps using the local `platform-admin` account with its own `--config`.

### Step A.5: Headlamp behind oauth2-proxy
* Application `addon-oauth2-proxy` (chart 10.7.1, image digest-pinned).
  * Provider `keycloak-oidc`, client `headlamp`, `--allowed-group` per owner decision O-2.
  * Cookie bound to `headlamp.localhost`, `SameSite=Lax`, session refresh 1 h.
* Traefik `Middleware` (ForwardAuth → oauth2-proxy) on the Headlamp ingress, plus the `/oauth2/*` path on the same host. Headlamp keeps its read-only kubeconfig unchanged.
* **Owner-facing acceptance:** one login, then "All clusters" view **without any re-prompt**. This is the issue that made the owner remove basic auth in Phase 3.

### Step A.6: Rebuild path, smoke test, runbook
* `setup-hub-spoke.sh` runs A.1. `post-bootstrap.sh` waits for Keycloak Ready.
* New smoke **stage 10/10 (SSO)**:
  * OIDC discovery is served from the host and from inside `argocd-server`, and the two issuers are equal.
  * Argo CD `/api/v1/settings` advertises the OIDC config.
  * An unauthenticated Headlamp request gets a **302 to Keycloak**.
  * Local break-glass login still succeeds.
  * No password is used in the smoke test except the existing local account.
* Runbook Issue G: "SSO down". Use local `platform-admin`; the Keycloak admin console uses the bootstrap admin; restart re-imports the realm.

---

## 5. Track B: Supply-Chain Trust (L4-8)

### Step B.1: CI hardening (`orders-processor`)
* Pin every GitHub Action **by commit SHA**, with the version as a comment.
* Trivy scan of the built image: **fail on CRITICAL with a fix available**; HIGH reported only, to avoid owner friction from base-image churn.
* SBOM (SPDX, via syft or `docker buildx --sbom`) attached as a **cosign attestation**.
* **cosign keyless signing** of the pushed **digest** (`permissions: id-token: write`). Identity:
  * `https://github.com/brunobml/orders-processor/.github/workflows/ci.yaml@refs/…`
  * issuer `https://token.actions.githubusercontent.com`.

### Step B.2: Release v1.5.0
* No application change; the release produces the first signed, attested image. Also verifies PV3-11 (0.3).
* Host check: `cosign verify` and `cosign verify-attestation --type spdxjson` with the exact identity regexp pass.
* Rollout: dev/test via `main`, prod via the usual digest bump (Phase 2 gate).

### Step B.3: Kyverno on spokes (GitOps addon)
* Added to the `addons-spoke` ApplicationSet (project `platform-addons`, `preserveResourcesOnDeletion` per R-2).
* Chart 3.9.1: admission controller only (background, cleanup and reports controllers off), one replica, image digests pinned.
* Webhook `namespaceSelector` matches **tenant namespaces only** (a label added through the tenant AppSets' `managedNamespaceMetadata`, next to the CARM annotation), `failurePolicy` per owner decision O-3. `kube-system`, `kyverno` and platform controllers are never in scope.
* Rollout: nonprod first, then prod.

### Step B.4: Image verification policy (blueprint-owned)
* Policy in `platform-catalog/blueprints/` (Kyverno `ImageValidatingPolicy` if the 1.19 CRD fits, otherwise a `ClusterPolicy` with `verifyImages`; chosen by `helm template` + dry-run in B.3).
  * Images `ghcr.io/brunobml/orders-processor*` must carry a keyless signature with the B.1 identity.
  * `mutateDigest: true`, so the admitted pod runs the verified digest.
* **Promotion:** the policy ships through the existing blueprint gate.
  1. Nonprod `main` in **Audit**, then **Enforce**.
  2. Prod via a new `platform-catalog` tag (v1.4.0), only after prod already runs the signed v1.5.0 digest. Order matters: Enforce before the signed rollout would block prod restarts.
* **Negative tests** (nonprod, dry-run and live): the unsigned v1.4.0 digest and an image signed by another identity are **rejected**. Signed v1.5.0 is admitted. Kyverno policy reports (or audit events) record the decision.

---

## 6. Track C: ApplicationSet Modernization

### Step C.1: `goTemplate` everywhere (L2-4)
* For each of the 6 fasttemplate ApplicationSets (F10), one commit per ApplicationSet, platform ones first, tenants last:
  * `goTemplate: true`, `goTemplateOptions: ["missingkey=error"]`, `{{ .name }}` syntax.
* **Zero-diff gate:** `argocd appset generate` of the new file must equal the live Applications (normalised JSON diff = empty) before the commit is applied.
* **Safety:** during the migration each ApplicationSet carries `syncPolicy.applicationsSync: create-update`, so a rendering mistake cannot delete Applications. It is removed once all six are done.

### Step C.2: Tenant self-registration (L2-3)
* Replace the two tenant `list` ApplicationSets with **one** ApplicationSet. Generator: matrix of
  * a **Git-files** generator over `tenant-workloads/tenants/*/*/app.yaml` (`tenant`, `app`, `env`, `port`, `valuesRevision`), and
  * the **cluster** generator selecting by `environment` label (nonprod/prod).
* `app.yaml` files sit next to the existing per-env manifests (F11).
* **Guardrails:** the tenant AppProject (Phase 3 C.1) still limits namespaces and kinds. Templates come from the control plane; tenants supply only data. `missingkey=error` rejects incomplete files.
* **Migration without deletion:**
  1. The new ApplicationSet renders the same Application names (`orders-dev`, …). Gate: zero-diff, as in C.1.
  2. The old ApplicationSets are switched to `create-only` and the new one is applied.
  3. Ownership is verified to have moved.
  4. The old ApplicationSets are deleted, with the Applications preserved (non-cascading).
* **Acceptance:** adding `tenants/tenant-a/dev/app.yaml` for a second demo app in `tenant-workloads` (PR only, no control-plane change) creates its Application, which is then removed again.

---

## 7. Track D: Acceptance

### Step D.1: Full rebuild (owner-approved, O-4)
* `make teardown → setup → bootstrap → post-bootstrap` on the final state.
* **Expected:**
  * all Applications Synced/Healthy (count recorded; Keycloak, oauth2-proxy and 2× Kyverno added),
  * impersonation audit PASS,
  * smoke **10/10**,
  * SSO login for both groups,
  * signed images admitted, unsigned rejected,
  * new tokens issued (closes 0.1).

### Step D.2: Report & validation
`phase4-implemented-NN.md` per track; independent validation per the workflow.

---

## 8. Sequencing & Bundling

| Order | Step(s) | Gate |
|---|---|---|
| 1 | **0.2** (early) | Reviewer early authorization |
| 2 | A.0 spike | Plan approval; outcome recorded before A.1 |
| 3 | A.1 → A.2 → A.3 → A.4 → A.5 → A.6 | Each step verified live; A.4 never removes the local admin path |
| 4 | B.1 → B.2 → B.3 → B.4 | Prod Enforce only after prod runs the signed digest |
| 5 | C.1 → C.2 | Zero-diff gates; Applications never deleted |
| 6 | D.1 | Owner approval (O-4) |

Tracks A, B and C are independent and can be validated separately (one implementation report each).

---

## 9. Verification Matrix

| # | Area | Check | Expected |
|---|---|---|---|
| W1 | Headlamp CORS | `curl -H 'Origin: https://evil.example'` | no `Access-Control-Allow-*` headers; UI works |
| W2 | Issuer | discovery from host and from `argocd-server` | identical `issuer` |
| W3 | Argo CD SSO | `platform-user` / `tenant-a-user` | admin / tenant-a permissions (tenant cannot sync prod) |
| W4 | Break-glass | local `platform-admin` login with Keycloak scaled to 0 | succeeds |
| W5 | Dex | `get deploy` | absent |
| W6 | Headlamp SSO | unauthenticated → 302; one login → all clusters, no re-prompt; user outside allowed groups | 302 / 200 / 403 |
| W7 | Secrets | `git grep` for generated secret values, realm JSON | none; only `${…}` placeholders |
| W8 | Keycloak restart | delete pod | realm re-imported; logins work; only sessions lost |
| W9 | CI | workflow file | every `uses:` pinned by SHA; Trivy, SBOM, sign steps present |
| W10 | Signature | `cosign verify` / `verify-attestation` with identity | pass for v1.5.0 |
| W11 | Admission | unsigned v1.4.0 / foreign-signed / signed v1.5.0 on nonprod | rejected / rejected / admitted (`mutateDigest` applied) |
| W12 | Prod gate | prod Enforce only after signed digest | prod pods restart cleanly under Enforce |
| W13 | Kyverno scope | pod in `kube-system` with Kyverno scaled to 0 | admitted (not in scope) |
| W14 | goTemplate | `argocd appset generate` vs live | zero diff × 6; no Application deleted |
| W15 | Self-registration | add / remove a tenant `app.yaml` in `tenant-workloads` | Application created / removed; no control-plane commit |
| W16 | Rebuild | D.1 | all Synced/Healthy; smoke 10/10; time recorded |
| W17 | Regression | Phase 3 V1–V17 | unchanged |

---

## 10. Risk Register & Rollback

| Risk | Likelihood | Impact | Mitigation / Rollback |
|---|:-:|:-:|---|
| Go resolver short-circuits `*.localhost` | Med | Med | A.0 spike; nip.io fallback |
| Argo CD refuses an HTTP issuer | Low–Med | Med | A.0 spike; HTTPS fallback needs owner consent |
| Lock-out of Argo CD after the OIDC change | Low | High | Local `platform-admin` kept; manual-sync `argo-cd` app; break-glass Helm (D-32); no local account removed before W3/W4 pass |
| Keycloak restart drops sessions / passwords | Med | Low | Stateless by design; passwords re-imported from Secret; documented |
| oauth2-proxy re-prompts across Headlamp clusters | Low | Med (owner friction) | Single host cookie; explicit acceptance A.5; rollback = remove Middleware |
| Kyverno blocks tenant pods (bad policy or Kyverno down) | Med | Med (nonprod) / High (prod) | Audit first; nonprod first; tenant-only selector; prod Enforce after signed rollout; rollback = Audit mode via blueprint revert |
| Keyless verification needs Sigstore/GHCR reachability | Med | Med | Same dependency as image pulls; Audit fallback; documented |
| Trivy fails builds on base-image CVEs | Med | Low | CRITICAL + fixable only; `.trivyignore` with expiry dates |
| AppSet migration deletes Applications | Low | High | `create-update` / `create-only` policies; zero-diff gate; non-cascading delete |
| Rebuild (D.1) fails | Med | Med | Owner-approved window; Phase 3 runbooks; fix forward as in B.7 |

---

## 11. Effort Estimate

| Track | Effort |
|---|---|
| 0 | XS (0.2 is one commit) |
| A | L (≈ 1–2 days incl. spike) |
| B | M–L (≈ 1 day; mostly CI and policy staging) |
| C | M (≈ ½–1 day; C.2 is the riskiest) |
| D | S (≈ 1 h + validation) |
