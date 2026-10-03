# Phase 4 Implementation Report — Run #01: Step 0.2 (P4-1) and Step A.0 spike (2026-10-02)

| | |
|---|---|
| **Plan** | [`2026-10-02-lab-remediation-plan-phase4.md`](2026-10-02-lab-remediation-plan-phase4.md) v1.0 (GREEN LIGHT, `6381836`; remarks R-0..R-4) |
| **Owner decisions** | O-1..O-3 accepted as endorsed ("read the phase4 review and proceed"). O-4 (rebuild) will be confirmed by the owner before Track D |
| **Scope executed** | **0.2** (early authorization R-0) and **A.0** (spike, nothing committed besides this report) |
| **Commits** | `gitops-control-plane`: `f176135` (0.2) |

## 1. Step 0.2 — Headlamp `-dev` removed (P4-1) ✅

| Check | Before | After |
|---|---|---|
| Container args | `… -kubeconfig=… -dev` | `-plugins-dir=… -session-ttl=86400 -kubeconfig=…` |
| `curl -H 'Origin: https://evil.example' …/config` | `Access-Control-Allow-Origin: https://evil.example` + `Allow-Credentials: true` | **no `Access-Control-*` headers** |
| Same check on a cluster API path (`/clusters/k3d-spoke-prod/api/v1/namespaces`) | — | 0 `Access-Control-*` headers; same-origin request 200 |
| Headlamp UI / config | — | 200; clusters `k3d-spoke-nonprod`, `k3d-spoke-prod`, `k3d-hub-cluster` |
| `addon-headlamp` | — | Synced / Healthy |

The flag was also removed from the example in `addons/headlamp/README.md`. One transient 502 right after the rollout (old pod terminating) — 200 on retry.

## 2. Step A.0 — Spike results

Setup (throwaway, then removed): Keycloak `26.8.0@sha256:b0f60d48…` in namespace `kc-spike`, `start-dev`, `KC_HOSTNAME=http://keycloak.localhost:8080`; Traefik Ingress `keycloak.localhost`; hub `coredns-custom` with `rewrite name keycloak.localhost keycloak.kc-spike.svc.cluster.local` and `rollout restart deploy/coredns` (**R-1 applied**).

| # | Question | Result |
|---|---|---|
| S1 | Do Go clients in the cluster resolve `keycloak.localhost` through CoreDNS (not loopback)? | ✅ **Yes.** `argocd` binary in the `argocd:v3.5.3` image reached Keycloak (HTTP 404 from Keycloak, not "connection refused"); `oauth2-proxy v7.15.5` completed OIDC discovery and stayed Running. Host discovery returns issuer `http://keycloak.localhost:8080/realms/master`. **The nip.io fallback is not needed.** |
| S2 | Does Argo CD 3.5.3 accept an `http://` issuer with PKCE? | ✅ **Yes.** With a temporary `oidc.config` (`enablePKCEAuthentication: true`), `/api/v1/settings` advertised it; a scripted PKCE S256 login (spike realm, public client, direct grants off) produced an ID token that Argo CD accepted: `userinfo` → `loggedIn: true`, `iss` = the HTTP issuer, `groups: [lab-platform-admins]`. **The HTTPS fallback is not needed; TLS stays out of scope.** |
| S2-neg | Negative checks | Tampered-signature token → `userinfo` `{}` (not logged in); reused auth code → `invalid_grant`; PKCE with wrong verifier → `invalid_grant` |

### Design corrections from the spike (applied in A.3 / A.4)

| ID | Finding | Consequence |
|---|---|---|
| S3 | With PKCE, Argo CD's **UI** performs the flow in the browser; the callback is **`/pkce/verify`**, not `/auth/callback`, and the **browser** calls the Keycloak token endpoint. | Client `argocd` redirect URIs: `http://localhost:8080/pkce/verify` and `http://argocd.localhost:8080/pkce/verify` (plus `/auth/callback` for the CLI). Keycloak `webOrigins` must list both Argo CD origins (verified: token endpoint returns `Access-Control-Allow-Origin: http://localhost:8080`). |
| S4 | Keycloak 26 sets its login cookies `Secure; SameSite=None` even over HTTP. Browsers accept Secure cookies on `*.localhost` (secure context); curl does not. | Browser login must be confirmed by the owner at A.4/A.5 acceptance. Automated checks (smoke stage 10) pass cookies explicitly. |
| S5 | Argo CD uses the `email` claim as username. | RBAC binds **groups**, not usernames; users get an `email` in the realm. |
| S6 | A client-level group-membership mapper is enough for the `groups` claim. | Use a dedicated client scope `groups` (as planned) so both clients share one mapper. |

### Clean-up evidence
`oidc.config` removed → `argocd-cm` data **byte-identical** to the pre-spike copy; `/api/v1/settings` `oidcConfig: null`; `argo-cd` Application Synced/Healthy; namespace `kc-spike` and `coredns-custom` deleted, CoreDNS restarted; the throwaway user password (scratchpad, mode 600) deleted. No generated secret was printed.

## 3. Next
A.1 → A.6 with issuer **`http://keycloak.localhost:8080/realms/lab`**.
