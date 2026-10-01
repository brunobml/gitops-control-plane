#!/usr/bin/env bash
# Phase 3 C.2 / reviewer remark R-1: preflight audit before (and after) enabling
# application.sync.impersonation.enabled. Fails if any AppProject lacks
# destinationServiceAccounts, if any Application has no matching entry, or if the
# referenced ServiceAccount does not exist on the target cluster.
set -euo pipefail

HUB="k3d-hub-cluster"
python3 - "$HUB" <<'PY'
import fnmatch, json, subprocess, sys, base64
hub = sys.argv[1]
def kj(ctx, *args):
    return json.loads(subprocess.check_output(["kubectl", "--context", ctx, *args, "-o", "json"]))

projects = {p["metadata"]["name"]: p for p in kj(hub, "-n", "argocd", "get", "appprojects")["items"]}
apps = kj(hub, "-n", "argocd", "get", "applications")["items"]
clusters = kj(hub, "-n", "argocd", "get", "secrets", "-l", "argocd.argoproj.io/secret-type=cluster")["items"]
name_to_server = {"in-cluster": "https://kubernetes.default.svc"}
for c in clusters:
    d = c["data"]
    name_to_server[base64.b64decode(d["name"]).decode()] = base64.b64decode(d["server"]).decode()
server_to_ctx = {"https://kubernetes.default.svc": hub}
for name, server in name_to_server.items():
    if name != "in-cluster":
        server_to_ctx[server] = f"k3d-{name}"

failures = 0
for pname, p in sorted(projects.items()):
    dsa = p["spec"].get("destinationServiceAccounts") or []
    print(f"[project] {pname}: {len(dsa)} destinationServiceAccounts entr{'y' if len(dsa)==1 else 'ies'}")
    if not dsa:
        print(f"  ✘ {pname} has no destinationServiceAccounts")
        failures += 1

sa_cache = {}
for a in sorted(apps, key=lambda x: x["metadata"]["name"]):
    n, proj = a["metadata"]["name"], a["spec"]["project"]
    dest = a["spec"]["destination"]
    server = dest.get("server") or name_to_server.get(dest.get("name", ""), "")
    ns = dest.get("namespace", "")
    entries = projects.get(proj, {}).get("spec", {}).get("destinationServiceAccounts") or []
    match = next((e for e in entries
                  if fnmatch.fnmatchcase(server, e.get("server", "")) and fnmatch.fnmatchcase(ns, e.get("namespace", ""))), None)
    if not match:
        print(f"  ✘ {n} ({proj} → {server or dest.get('name')} / {ns}): no matching destinationServiceAccounts entry")
        failures += 1
        continue
    sa = match["defaultServiceAccount"]
    sa_ns, sa_name = sa.split(":", 1) if ":" in sa else (ns, sa)
    ctx = server_to_ctx.get(server)
    key = (ctx, sa_ns, sa_name)
    if key not in sa_cache:
        sa_cache[key] = subprocess.run(["kubectl", "--context", ctx, "-n", sa_ns, "get", "sa", sa_name],
                                       capture_output=True).returncode == 0
    ok = sa_cache[key]
    print(f"  {'✔' if ok else '✘'} {n}: {proj} → {ctx}/{ns} as {sa_ns}:{sa_name}{'' if ok else '  (ServiceAccount NOT FOUND)'}")
    failures += 0 if ok else 1

flag = kj(hub, "-n", "argocd", "get", "cm", "argocd-cm")["data"].get("application.sync.impersonation.enabled", "false")
print(f"[info] application.sync.impersonation.enabled = {flag}")
print("RESULT:", "PASS" if failures == 0 else f"FAIL ({failures} problem(s))")
sys.exit(1 if failures else 0)
PY
