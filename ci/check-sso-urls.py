#!/usr/bin/env python3
"""SSO URL consistency (2026-10-03 Track I.2, review remark R-10).

usage: check-sso-urls.py <gitops-control-plane dir>

Every OIDC relying party and Keycloak must agree on the issuer and on each other's URLs; a change
to one of them alone breaks login (the main risk of moving hosts or ports). Checks:
  1. one issuer everywhere: Keycloak KC_HOSTNAME + /realms/lab, Argo CD oidc.config issuer,
     oauth2-proxy oidc_issuer_url and endpoints, Grafana auth/token/api/signout URLs, the blackbox
     probe target, the smoke test's ISSUER;
  2. every relying-party URL is registered in the realm: Argo CD url + additionalUrls ->
     <url>/auth/callback (client argocd); oauth2-proxy redirect_url (client headlamp); Grafana
     root_url + /login/generic_oauth (client grafana); each post-logout target allowed;
  3. no hub URL with the old host ports 8080/8443 left in configuration or scripts (Track I, O-6).
"""
import json, os, re, subprocess, sys
import yaml

root = sys.argv[1] if len(sys.argv) > 1 else "."
errs = []


def load(path):
    return list(yaml.safe_load_all(open(os.path.join(root, path))))


def err(msg):
    errs.append(msg)


# --- collect -----------------------------------------------------------------
kc = load("addons/keycloak/deployment.yaml")[0]
env = {e["name"]: e.get("value") for c in kc["spec"]["template"]["spec"]["containers"] for e in c.get("env", [])}
realm = json.load(open(os.path.join(root, "addons/keycloak/realm-lab.json")))
issuer = f"{env['KC_HOSTNAME'].rstrip('/')}/realms/{realm['realm']}"
clients = {c["clientId"]: c for c in realm["clients"]}

argo = yaml.safe_load(open(os.path.join(root, "clusters/values-argocd-hub.yaml")))
cm = argo["configs"]["cm"]
argo_oidc = yaml.safe_load(cm["oidc.config"])
argo_urls = [cm["url"]] + (yaml.safe_load(cm.get("additionalUrls", "")) or [])

o2p = load("applicationsets/addon-oauth2-proxy.yaml")[0]
o2p_cfg = o2p["spec"]["source"]["helm"]["valuesObject"]["config"]["configFile"]
o2p_kv = dict(re.findall(r'^\s*(\w+)\s*=\s*"([^"]*)"', o2p_cfg, re.M))

graf = yaml.safe_load(open(os.path.join(root, "addons/observability/values-grafana.yaml")))["grafana.ini"]
g_oauth = graf["auth.generic_oauth"]

prom = open(os.path.join(root, "addons/observability/values-prometheus-hub.yaml")).read()
smoke = open(os.path.join(root, "scripts/smoke-test-hub-spoke.sh")).read()

# --- 1. one issuer -----------------------------------------------------------------
issuer_users = {
    "Argo CD oidc.config issuer": argo_oidc["issuer"],
    "oauth2-proxy oidc_issuer_url": o2p_kv.get("oidc_issuer_url"),
}
for k in ("login_url", "redeem_url", "oidc_jwks_url", "profile_url"):
    issuer_users[f"oauth2-proxy {k}"] = o2p_kv.get(k)
for k in ("auth_url", "token_url", "api_url"):
    issuer_users[f"Grafana {k}"] = g_oauth.get(k)
issuer_users["Grafana signout_redirect_url"] = graf["auth"]["signout_redirect_url"]
issuer_users["Argo CD logoutURL"] = argo_oidc.get("logoutURL")
m = re.search(r'targets:\s*\["(http[^"]*\.well-known/openid-configuration)"\]', prom)
issuer_users["blackbox target"] = m.group(1) if m else None
m = re.search(r'^ISSUER="([^"]+)"', smoke, re.M)
issuer_users["smoke ISSUER"] = m.group(1) if m else None
for who, val in issuer_users.items():
    if not val:
        err(f"{who}: not found")
    elif not (val == issuer or val.startswith(issuer + "/")):
        err(f"{who} = {val} does not use the issuer {issuer} (Keycloak KC_HOSTNAME)")


# --- 2. relying-party URLs registered in the realm --------------------------------
def allowed(uri, patterns):
    return any(uri == p or (p.endswith("*") and uri.startswith(p[:-1])) for p in patterns)


def post_logout(client):
    return [p for p in client.get("attributes", {}).get("post.logout.redirect.uris", "").split("##") if p]


for u in argo_urls:
    cb = f"{u.rstrip('/')}/auth/callback"
    if not allowed(cb, clients["argocd"]["redirectUris"]):
        err(f"Argo CD URL {u}: {cb} is not a redirect URI of realm client argocd")
    if not allowed(u.rstrip("/"), post_logout(clients["argocd"])):
        err(f"Argo CD URL {u}: not an allowed post-logout URI of realm client argocd")
if not allowed(o2p_kv.get("redirect_url", ""), clients["headlamp"]["redirectUris"]):
    err(f"oauth2-proxy redirect_url {o2p_kv.get('redirect_url')} is not a redirect URI of realm client headlamp")
g_cb = f"{graf['server']['root_url'].rstrip('/')}/login/generic_oauth"
if not allowed(g_cb, clients["grafana"]["redirectUris"]):
    err(f"Grafana {g_cb} is not a redirect URI of realm client grafana")
m = re.search(r"post_logout_redirect_uri=([^&]+)", graf["auth"]["signout_redirect_url"])
if m:
    from urllib.parse import unquote
    if not allowed(unquote(m.group(1)), post_logout(clients["grafana"])):
        err(f"Grafana post-logout {unquote(m.group(1))} is not allowed by realm client grafana")

# --- 3. no old hub ports ------------------------------------------------------------
files = subprocess.check_output(["git", "-C", root, "ls-files"], text=True).split()
old = re.compile(r"localhost(?::|%3A)(?:8080|8443)\b|127\.0\.0\.1:(?:8080|8443):")
for f in files:
    if f.startswith(("docs/", "ci/schemas/")) or f == "ci/check-sso-urls.py" or not f.endswith((".yaml", ".yml", ".json", ".sh", ".py", "Makefile")):
        continue
    for n, line in enumerate(open(os.path.join(root, f), encoding="utf-8", errors="replace"), 1):
        if old.search(line):
            err(f"{f}:{n}: old hub port 8080/8443 (Track I: hub URLs are portless)")

for e in errs:
    print(f"✘ {e}", file=sys.stderr)
if errs:
    sys.exit(1)
print(f"✔ SSO URLs consistent: issuer {issuer}; {len(issuer_users)} issuer uses; "
      f"Argo CD {argo_urls}, Headlamp {o2p_kv['redirect_url']}, Grafana {graf['server']['root_url']} registered", file=sys.stderr)
