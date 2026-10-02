# Phase 4 Implementation Report — Run #02: Track A, Keycloak Single Sign-On (2026-10-02)

| | |
|---|---|
| **Plan** | [`2026-10-02-lab-remediation-plan-phase4.md`](2026-10-02-lab-remediation-plan-phase4.md) v1.0 (GREEN LIGHT; remarks R-0..R-4) |
| **Preceded by** | [Implemented-01](2026-10-02-lab-remediation-plan-phase4-implemented-01.md) (0.2, A.0 spike: issuer `http://keycloak.localhost:8080` confirmed) |
| **Scope executed** | **A.1 – A.6** (P4-2 closed). **Open:** owner browser acceptance (§4) and then O-1 (retire local `tenant-a`) |
| **Commits** | `gitops-control-plane`: `d802ed2` (A.1–A.3), `6a5a570` (A.4), `867f3a1`, `8ba6cd0`, `499cac0`, `81baf1c` (A.5), `3313e57` (A.6) |

## 1. Outcome

| Step | Result |
|---|:-:|
| A.1 secrets outside Git (`scripts/setup-keycloak-secrets.sh`, wired into `setup-hub-spoke.sh`) | ✅ |
| A.2 Keycloak addon (`addons/keycloak`, `addon-keycloak`): digest-pinned 26.8.0, stateless, PSS `restricted`, NetworkPolicy, Ingress, CoreDNS rewrite | ✅ |
| A.3 realm `lab` as code (groups, users with `${…}` password placeholders, clients `argocd` public+PKCE and `headlamp` confidential, group mapper) | ✅ |
| A.4 Argo CD native OIDC + PKCE, group RBAC, **Dex removed (P4-2)** | ✅ |
| A.5 Headlamp behind oauth2-proxy (Traefik ForwardAuth), allowed groups per O-2 | ✅ |
| A.6 rebuild path (`setup`, `post-bootstrap` step 2/7), smoke stage **10/10**, `make password`, runbook Issue G | ✅ |
| Regression | **20/20** Applications Synced/Healthy; R-1 impersonation audit PASS; smoke 10/10; `post-bootstrap` idempotent (exit 0) |

## 2. Evidence (verification matrix W-items)

| # | Check | Result |
|---|---|---|
| W2 | Issuer from host and from inside `argocd-server` (bash `/dev/tcp`, real pod network path) | both `http://keycloak.localhost:8080/realms/lab` (smoke stage 10) |
| W3 | Scripted PKCE login → Argo CD API, per user | `platform-user` (`lab-platform-admins`): 19 apps visible, `can-i sync orders-prod` **yes**, `update clusters` **yes**. `tenant-a-user` (`lab-tenant-a`): 3 apps, sync `orders-dev` **yes**, `orders-prod` **no**, `control-plane/argo-cd` get **no**, `update clusters` **no** |
| W3-neg | User in no group (temporary, deleted after the test) | Argo CD: logged in, **0 apps** (`policy.default: ""`) |
| W4 | Keycloak scaled to 0 (discovery 503; root + addon automation paused for the test, then restored) | local `platform-admin` login **OK** (19 apps); SSO login fails as expected |
| W5 | Dex | Deployment, Service, ServiceAccount, Role, RoleBinding, NetworkPolicy **pruned** (targeted prune; `prune: false` kept for the rest of `argo-cd`) |
| W6 | Headlamp | unauthenticated `/`, `/config`, cluster API → **302 to Keycloak** (`client_id=headlamp`, PKCE). After **one** login (cookie for `headlamp.localhost`): `/`, `/config`, `k3d-spoke-prod` namespaces, `k3d-hub-cluster` nodes → **200** for both users. User outside the groups → **403 at the callback**, no session |
| W7 | Generated secret values in Git (4 repos, history + worktree) | **none**; realm has only `${LAB_HEADLAMP_CLIENT_SECRET}`, `${LAB_PLATFORM_USER_PASSWORD}`, `${LAB_TENANT_A_USER_PASSWORD}`. Headlamp client secret in Keycloak = local file (compared by SHA-256 only) |
| W8 | Keycloak pod restart / scale 0→1 | realm re-imported (`Realm 'lab' imported`), SSO login works with passwords from the Secret |
| P4-1 | Cross-origin regression | smoke stage 10: no `Access-Control-Allow-Origin` on Headlamp |

## 3. Deviations, Defects and Notes

| ID | Item |
|---|---|
| D-1 | **Credential exposure during implementation (author error), contained.** A redaction filter of mine failed and printed most of the base64 values of the five freshly generated Keycloak/oauth2-proxy secrets to the session transcript. They had never been used. All five were deleted and regenerated immediately (verified: Secret no longer matches); nothing else was affected. Afterwards only key names or hashes were printed. |
| D-2 | **oauth2-proxy `invalid_scope`.** The `keycloak-oidc` provider requests a `groups` scope by default; the realm delivers groups through a client mapper (spike S6), so Keycloak refused the request. Fixed with `scope = "openid email profile"` (`499cac0`). |
| D-3 | **oauth2-proxy crashed once on every rollout.** Startup OIDC discovery ran before kube-router allowed the new pod through Keycloak's NetworkPolicy (Phase 3 gotcha); on a cold rebuild with Keycloak not yet up this would become a CrashLoopBackOff. Fixed with `skip_oidc_discovery` and explicit endpoints (`81baf1c`). Verified: with Keycloak at 0 replicas a restarted oauth2-proxy stays Running (0 restarts) and Headlamp still fails closed (302); login works once Keycloak returns. |
| D-4 | **R-1 automated.** CoreDNS's `reload` plugin hashes only the Corefile, not imported files. `post-bootstrap.sh` step 2/7 stamps the `coredns-custom` content hash on the CoreDNS pod template and restarts it only when the hash changes (observed: restart once, then "already serves"). |
| D-5 | The groups claim uses a **per-client mapper** (proven in the spike) rather than a shared client scope; no realm-level scopes to manage in the import. |
| D-6 | `argo-cd` sync: apart from `argocd-cm`/`argocd-rbac-cm` and the Dex objects, the diff was only config-checksum annotations, so all Argo CD components rolled once. The CLI returned rc=20 while `argocd-server` restarted; the operation itself Succeeded. |
| D-7 | The **first W4 attempt was invalid** (Keycloak was restored by the root app's self-heal before the check ran; discovery still answered 200). Repeated with the root app's automation paused; that run is the evidence above. |

## 4. Owner Actions (needed to close Track A)

1. **Browser acceptance** (spike S4: Keycloak's `Secure` cookies over HTTP rely on the browser treating `*.localhost` as a secure context; scripted tests cannot prove the real browser behaviour):
   * Argo CD `http://localhost:8080` → **"Log in via Keycloak"** → `platform-user`, then `tenant-a-user` (passwords: `make password` lists the files).
   * Headlamp `http://headlamp.localhost:8080` → one Keycloak login → select **All clusters**: **no re-prompt**.
2. **O-1:** after (1) succeeds, confirm removal of the local `tenant-a` Argo CD account (`platform-admin` stays as break-glass and for automation).

## 5. Addendum — owner browser test found an Argo CD login defect (fixed, `2fcec18`)

| | |
|---|---|
| **Reported by owner** | Both `http://localhost:8080` and `http://argocd.localhost:8080` failed with "Invalid redirect URL: the protocol and host (including port) must match and the path must be within allowed URLs if provided" |
| **Root cause 1 (spike S3 was wrong)** | In Argo CD 3.5 the UI login with `enablePKCEAuthentication` runs **server-side**: `argocd-server` keeps the PKCE verifier and sends `redirect_uri=<host>/auth/callback`. The realm only allowed `/pkce/verify`, so Keycloak refused the redirect URI. My scripted tests had requested tokens from Keycloak directly and never went through Argo CD's own `/auth/login` → `/auth/callback`, so they missed it. |
| **Root cause 2** | Argo CD accepts return/callback URLs only for `url` (`http://localhost:8080`); the UI is also served on `argocd.localhost:8080`, which Argo CD rejected with the message above. |
| **Fix** | Realm: client `argocd` redirect URIs `http://localhost:8080/auth/callback`, `http://argocd.localhost:8080/auth/callback`, CLI `http://localhost:8085/auth/callback`; `/pkce/verify` and `webOrigins` removed (no browser-side token call). Argo CD: `additionalUrls: [http://argocd.localhost:8080]`. Applied by commit + manual `argo-cd` sync (diff: `additionalUrls` + checksum annotations only); Keycloak re-imported the realm on its own (ConfigMap hash). |
| **Verification** | Full browser-equivalent flow through `argocd-server` (`/auth/login` → Keycloak form → `/auth/callback` → `argocd.token` cookie → `userinfo`), **4/4 pass**: both users × both hosts, callback lands on the same host's `/applications`, groups correct. Negative: unregistered redirect URI → Keycloak error page (no login form); `return_url=http://evil.example/` → Argo CD 400. |
| **Regression guard** | Smoke stage 10 now follows every SSO entry point (Argo CD on both hosts, Headlamp) to Keycloak and requires the **login form** (no password used). It would have failed on the old configuration. |
| **Lesson** | SSO acceptance must exercise the relying party's own login endpoints, not only the IdP. |
