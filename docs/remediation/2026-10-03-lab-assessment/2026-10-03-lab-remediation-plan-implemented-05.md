# Implementation Report 05 — Track I: Canonical URLs on Ports 80/443 and Trusted Local TLS (2026-10-03)

> **Status: Current.** Active remediation record for the 2026-10-03 assessment.

| | |
|---|---|
| **Implements** | [Remediation plan v1.1](2026-10-03-lab-remediation-plan.md) Track I (§10a): I.0–I.5. Owner decisions **O-6** (a), **O-7** (a), **O-8** (document only), confirmed by the owner. Review remarks **R-9 … R-12** |
| **Executed by** | Claude (Opus 5.5), owner's assignment. **To be validated by** Antigravity, independent of the execution |
| **Commits** | `gitops-control-plane` `33503dc` (I.1 + I.2 + I.4, one atomic change); `tenant-workloads` `e068ae2` (tutorial URL) |
| **Live changes outside Git** | hub load balancer ports (`k3d cluster edit --port-add`); Secret `traefik/local-tls` and `monitoring/credential-expiry` key `local-tls` (`scripts/setup-local-tls.sh`); mkcert CA on the owner's Windows machine (`%LOCALAPPDATA%\mkcert`, created by mkcert, trusted by the owner's `mkcert -install`) |
| **Date** | 2026-10-03 |

---

## Summary

| Step | Result |
|---|---|
| **I.0** spike | Done on a throwaway cluster `itest` (created and deleted; `argolab` untouched). R-9 ✅, R-12 ✅ (with a design change), redirect ✅, R-11: `--port-add` ✅. **`--port-delete` ❌ is unsafe**: it took ingress down and the recovery attempt stopped the load balancer. It was therefore **not used on the hub** |
| **I.1** | CoreDNS `*.localhost` → CNAME `traefik.traefik.svc.cluster.local` (match `^.*\.localhost\.$`, `fallthrough`); Keycloak NetworkPolicy narrowed to **Traefik only** |
| **I.2** | 75 lines in 18 files made portless; current docs updated; new CI stage **`sso-urls`**; `setup-hub-spoke.sh` creates the hub on 80/443 and fails fast if they are taken |
| **I.3** | Live cut-over 18:00–18:20 UTC. One 7.6 s load-balancer blip; Argo CD manual sync over `http://localhost`; `post-bootstrap` and smoke 12/12 green. **Owner browser acceptance passed** (both users, Argo CD, Headlamp, Grafana; HTTPS) |
| **I.4** | Lab certificate from the **owner's mkcert CA** (`localhost`, `argocd`/`headlamp`/`grafana`/`keycloak.localhost`, valid until 2029-01-03), Traefik default TLSStore. **Every HTTPS request gets a 302 to the same HTTP URL**. Self-signed fallback when mkcert is absent; expiry is monitored |
| **I.5** | All checks below green; `https://*.localhost` validated against the **Windows trust store** |

---

## 1. I.0 — Spike (throwaway cluster `itest`, 17:39–17:45 UTC)

Setup: k3d 5.9.0, k3s v1.35.5, the hub's Traefik chart 41.6.1 with the same image digest, a `whoami` app behind an Ingress for `demo.localhost`.

| Check | Result |
|---|---|
| **R-11** `--port-add` | k3s **server not restarted** (same container ID and `StartedAt`). The **load balancer container is recreated**: API and ingress unavailable for about 6–7 s per edit. Hence one edit with both ports on the hub |
| **R-11** `--port-delete` (experimental) | ❌ When old (18080→80) and new (80→80) mappings share a container port, deleting the old one **removed `80.tcp`/`443.tcp` from the load balancer config**: Docker still published the ports, nginx proxied only 6443, ingress `000`. Re-adding 80/443 failed ("address already in use"), k3d "rolled back", and the load balancer was left **Exited** (API refused) |
| Recovery | `docker start <lb>`, then `--port-add <free host port>:80` and `:443`. The proxy entries return and everything answers. Documented as runbook Issue H. **Decision: the hub keeps 8080/8443 until the Track H rebuild** (they only serve old URLs, where SSO no longer matches) |
| Redirect | `https://demo.localhost:18443/some/path?x=1` → `302 http://demo.localhost/some/path?x=1`. Path and query are kept and the port is dropped, which is why the redirect needs port 80. Through 80/443, from WSL and from Windows: `200` / `302 → http://demo.localhost/p?q=1` |
| **R-12** fallback | Without the Secret, Traefik serves its default certificate and redirects, but logs `ERR Secret traefik/local-tls does not exist` (13 lines at startup). **Design change:** `setup-local-tls.sh` always creates the Secret (self-signed fallback without mkcert). With the Secret, it is picked up **at once, without a restart**; a restart then logs **0 errors** |
| **R-9** DNS scope | `demo.localhost`, `keycloak.localhost`, `a.b.localhost` → CNAME Traefik. `kubernetes.default.svc.cluster.local` → 10.43.0.1, `github.com` resolves, `notlocalhost.example` → NXDOMAIN, bare `localhost` unaffected. A pod's `http://demo.localhost/` reached the app through Traefik |

## 2. I.1 / I.2 — Change set (`33503dc`)

* **Name resolution:** `addons/keycloak/coredns-custom.yaml` key `localhost.override` holds the template from R-9. It replaces the Phase 4 `keycloak.override` rewrite.
* **Keycloak:**
  * NetworkPolicy allows ingress from the `traefik` namespace only (it previously also allowed argocd-server, oauth2-proxy, Grafana and the blackbox exporter directly);
  * `KC_HOSTNAME=http://keycloak.localhost`;
  * realm `rootUrl`, redirect URIs and post-logout URIs for `argocd`, `headlamp` and `grafana` are portless. The Argo CD CLI callback `http://localhost:8085/auth/callback` is kept; it is not a hub port.
* **Relying parties:**
  * Argo CD: `global.domain`, `url`, `additionalUrls`, OIDC issuer and logout, Headlamp links;
  * oauth2-proxy: issuer, endpoints, `redirect_url`, `whitelist_domains`;
  * Grafana: `root_url`, auth/token/userinfo/signout.
* **Monitoring and scripts:**
  * blackbox target and regexp; alert `logs` links and their unit-test expectations;
  * `Makefile`; `setup-hub-spoke.sh` (k3d `127.0.0.1:80`/`443`, argocd CLI address, fail-fast check that no other container publishes 80/443);
  * `post-bootstrap.sh`; the smoke test (including the in-pod `/dev/tcp/keycloak.localhost/80` issuer check).
* **Docs** (current only; historical records untouched): README, Headlamp README, tutorial, naming standards, Well-Architected guide, lab progression, both runbooks (new **Issue H**), CI README; `tenant-workloads/developer-tutorial.md`.
* **Inventory check:** before the change the new CI check reports exactly **75** old-port findings, the same as the lines changed. After: 0.

**CI stage `sso-urls`** (`ci/check-sso-urls.py`, R-10). It checks:
* one issuer across Keycloak `KC_HOSTNAME`, Argo CD, oauth2-proxy (5 URLs), Grafana (4), the blackbox target and the smoke test: 13 uses;
* every relying-party URL registered in the realm, including post-logout URIs;
* no `localhost:8080/8443` in configuration or scripts.

Negative tests, each caught on a scratch copy:

| Partial change | Message |
|---|---|
| Grafana `root_url` changed alone | `…/login/generic_oauth is not a redirect URI of realm client grafana` |
| `KC_HOSTNAME` changed alone | `Argo CD oidc.config issuer … does not use the issuer …` (and the other users) |
| realm loses the Headlamp callback | `oauth2-proxy redirect_url … is not a redirect URI of realm client headlamp` |
| one `:8080` URL left in a script | `scripts/smoke-test-hub-spoke.sh:263: old hub port 8080/8443` |

`make ci` before pushing: all stages green, 414 resources (330 → 332 valid; the new `TLSStore` and `Middleware` are schema-validated). GitHub CI on `33503dc`: **success**.

## 3. I.3 — Cut-over (hub, 2026-10-03 UTC)

| Time | Step | Evidence |
|---|---|---|
| 18:00:04 | Pre-flight | 32/32 Synced/Healthy; nothing else publishes 80/443; old URLs answer |
| 18:00:21 | `k3d cluster edit hub-cluster --port-add 127.0.0.1:80:80@loadbalancer --port-add 127.0.0.1:443:443@loadbalancer` | API and `:8080` unavailable 18:00:25.4–18:00:33.0 (**7.6 s**). `server-0` `StartedAt` unchanged. LB config has `80.tcp`, `443.tcp`, `6443.tcp`. `http://localhost/` 200, `:8080` 200 |
| 18:01 | `setup-local-tls.sh` | First run: mkcert not visible from WSL → self-signed fallback Secret (R-12). After the detection fix (§4), `make local-tls` issued the mkcert certificate |
| 18:02:06 | push `33503dc` | Keycloak, oauth2-proxy, Grafana, Traefik, Headlamp, Prometheus, blackbox and root synced; Healthy. `KC_HOSTNAME=http://keycloak.localhost`; `TLSStore/default` and `Middleware/redirect-to-http` present |
| 18:12:52–18:14:03 | `argo-cd` **manual sync** as `platform-admin` with its own CLI config, logged in at `http://localhost` | Diff: exactly the URL changes and config checksums. `/api/v1/settings`: `url=http://localhost`, `oidc=http://keycloak.localhost/realms/lab` |
| ~18:15 | `make post-bootstrap` | CoreDNS restarted for the new `coredns-custom`; issuer `http://keycloak.localhost/realms/lab`; stage 10 (SSO) ✅. Stage 12 ✘ on `OrdersNotProcessed`, firing **since 17:14–17:17**: the reboot before the cut-over had restarted moto empty (F-1). The same run re-keyed the workers in both accounts and orders flowed |
| 18:20:34 | Alerts cleared; **smoke 12/12** | Issuer identical from host and argocd-server; Argo CD (localhost, argocd.localhost) and Headlamp reach the Keycloak login; Headlamp refuses cross-origin; Grafana SSO; no firing alerts |
| ~20:05 | **Owner browser acceptance** | Passed: log in and out in Argo CD, Headlamp and Grafana; HTTPS opens without a warning and lands on HTTP |

Old mappings `127.0.0.1:8080`/`8443` remain (I.0 decision). They answer, but the realm no longer accepts their callbacks; the rebuild (Track H) removes them.

## 4. I.4 — Lab certificate

* `scripts/setup-local-tls.sh` (idempotent; called by `setup-hub-spoke.sh` right after Traefik, by `post-bootstrap` step 3, and as `make local-tls`):
  * mkcert if available, otherwise a self-signed fallback;
  * files in `~/.config/gitops-lab/tls` (dir 700, files 600; never printed, never in Git);
  * Secret `traefik/local-tls` labelled `app.kubernetes.io/managed-by=setup-local-tls`, `part-of=gitops-lab` (R-12);
  * `notAfter` written to `monitoring/credential-expiry` as `local-tls`, so `SpokeTokenExpiringSoon` warns 7 days ahead;
  * renews when fewer than 30 days are left, or replaces the fallback once mkcert appears.
* **Finding during execution:** WSL keeps the Windows `PATH` from its own start, so a fresh `winget install` of mkcert was invisible, and winget's alias folder does not contain it on this machine. The script now looks mkcert up on the **persistent** Machine and User `PATH` (found at `…\WinGet\Packages\FiloSottile.mkcert_…\mkcert.exe`). It also creates namespaces only when missing, which avoids `kubectl apply` warnings on Argo CD-managed namespaces.
* **Issued:** issuer `mkcert development CA` (owner's machine), SAN `localhost`, `argocd.localhost`, `headlamp.localhost`, `grafana.localhost`, `keycloak.localhost`, notAfter **2029-01-03**.
* **Traefik** (`addon-traefik` values):
  * `tlsStore.default.defaultCertificate.secretName: local-tls`;
  * `ports.websecure.http.middlewares: [traefik-redirect-to-http@kubernetescrd]`;
  * Middleware `redirect-to-http` (RedirectScheme `http`, non-permanent) via `extraObjects`.

## 5. I.5 — Verification

| Check | Result |
|---|---|
| Portless HTTP | `http://localhost/` 200, `argocd.localhost` 200, `headlamp.localhost` 302 (SSO), `grafana.localhost/login` 200, Keycloak discovery 200 |
| HTTPS, WSL with the mkcert CA | all five hosts: `302 → http://<host>/x`, `ssl_verify_result=0` |
| HTTPS, **Windows trust store** (`curl.exe`, Schannel) | mkcert CA present in `Cert:\CurrentUser\Root`; all five hosts `302 → http://<host>/x`. Control with an empty CA bundle: `certificate chain is incomplete`, so validation is real. Note: Schannel's *revocation* check fails for mkcert certificates (no CRL/OCSP), so `curl.exe` needs `--ssl-no-revoke`; browsers do not hard-fail on this, as the owner's test showed |
| In-cluster path | from argocd-server, `keycloak.localhost` resolves to `traefik.traefik.svc.cluster.local`; a **direct** TCP connection to `keycloak.keycloak.svc:8080` is **BLOCKED** by the NetworkPolicy |
| Certificate expiry | `lab_credential_expiry_timestamp_seconds{credential="local-tls"}` = 1862161310 (2029-01-03T19:01:50Z), equal to the certificate's `notAfter` |
| Probes | all 5 `probe_success = 1`, including `http://keycloak.localhost/realms/lab/.well-known/openid-configuration` |
| Regression | smoke **12/12**; impersonation audit PASS; 32/32 Synced/Healthy; `make ci` green, 19 alert rules; GitHub CI green on `33503dc` |

## 6. Notes for the validator
* **Deviation from the plan:** I.4's Git part shipped in the same commit as I.1/I.2, not after them. This is safe because the cut-over order puts the 80/443 mapping and the Secret in place before the push. Plan step I.3.5 (`--port-delete`) was **not executed**, per the I.0 result.
* **Residuals:**
  * old 8080/8443 mappings until H;
  * the mkcert CA is trusted on the owner's machine (its key never left Windows; the leaf names are limited to the five lab hosts);
  * SSO itself remains HTTP (planned as a separate item);
  * `argolab` cannot run on 80/443 at the same time (O-8, runbook Issue H).
* **Cosmetic:** the Argo CD chart derives `notifications.argocdUrl: https://localhost` from `global.domain`. Notifications are not configured, so this has no effect.
* **Suggested checks:**
  * `make ci` (including `sso-urls`) and a negative edit;
  * `curl -sI https://argocd.localhost` from WSL with `--cacert` pointing at the mkcert root, and the redirect;
  * DNS from a hub pod (`*.localhost` vs `*.svc.cluster.local` vs external);
  * the Keycloak NetworkPolicy (direct vs via Traefik);
  * `lab_credential_expiry_timestamp_seconds{credential="local-tls"}`;
  * one owner-independent SSO flow (smoke stage 10).

## 7. Track I status
| Step | Status |
|---|---|
| I.0 | ✅ Spike done (§1) |
| I.1, I.2 | 🔧 Done (`33503dc`). **Awaiting validation-05** |
| I.3 | 🔧 Cut-over done; owner browser acceptance ✅. **Awaiting validation-05** |
| I.4 | 🔧 Done (mkcert certificate). **Awaiting validation-05** |
| I.5 | 🔧 Verified (§5). The Track H rebuild later proves it from scratch |
