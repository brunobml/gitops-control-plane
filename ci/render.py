#!/usr/bin/env python3
"""Render the sources of Argo CD Applications to manifests, offline (2026-10-03 Track A).

Input: the YAML stream `labci appsets` prints. For each Application, every source is rendered
the way the Argo CD repo-server does it:
  - Helm chart (HTTP repo or OCI): `helm template` with releaseName, destination namespace,
    valueFiles (`$values/...` resolved against the `ref` source at its targetRevision),
    valuesObject / values, --include-crds, --kube-version;
  - path with kustomization.yaml: `kustomize build`;
  - other path: plain directory (recurse, include/exclude globs with {a,b} braces).
Tools run as the digest-pinned images in ci/tools.env.

Repositories: `--repo <repoURL>=<dir>` maps a repository to a local tree (the commit under test)
for every revision. Any other repository is fetched at the exact targetRevision into the cache.

Output: <out>/<application>.yaml, one file per Application.
"""
import argparse, fnmatch, os, re, subprocess, sys, tempfile
import yaml

ROOT = os.path.dirname(os.path.abspath(__file__))
TOOLS = dict(l.strip().split("=", 1) for l in open(os.path.join(ROOT, "tools.env"))
             if "=" in l and not l.lstrip().startswith("#"))
CACHE = os.environ.get("LAB_CI_CACHE", os.path.expanduser("~/.cache/lab-ci"))
UID = f"{os.getuid()}:{os.getgid()}"


def die(msg):
    print(f"✘ {msg}", file=sys.stderr)
    sys.exit(1)


def run(cmd, **kw):
    r = subprocess.run(cmd, capture_output=True, text=True, **kw)
    if r.returncode != 0:
        die(f"{' '.join(cmd[:12])} ...\n{r.stderr.strip()[-2000:]}")
    return r.stdout


def docker(image, args, mounts, env=None, workdir=None):
    cmd = ["docker", "run", "--rm", "-u", UID]
    for host, cont in mounts:
        cmd += ["-v", f"{host}:{cont}:ro" if cont.startswith("/src") else f"{host}:{cont}"]
    for k, v in (env or {}).items():
        cmd += ["-e", f"{k}={v}"]
    if workdir:
        cmd += ["-w", workdir]
    return run(cmd + [image] + args)


class Repos:
    def __init__(self, overrides):
        self.overrides = overrides

    def checkout(self, url, rev):
        url = url.rstrip("/")
        for k in (url, url + ".git", url.removesuffix(".git")):
            if k in self.overrides:
                return self.overrides[k]
        d = os.path.join(CACHE, "git", re.sub(r"[^A-Za-z0-9.]+", "_", f"{url}@{rev}"))
        if not os.path.isdir(os.path.join(d, ".git")):
            os.makedirs(d, exist_ok=True)
            run(["git", "init", "-q", d])
            run(["git", "-C", d, "fetch", "-q", "--depth", "1", url, rev])
            run(["git", "-C", d, "checkout", "-q", "FETCH_HEAD"])
        elif not re.fullmatch(r"[0-9a-f]{40}", rev):          # branches and tags move: refresh
            run(["git", "-C", d, "fetch", "-q", "--depth", "1", url, rev])
            run(["git", "-C", d, "checkout", "-q", "-f", "FETCH_HEAD"])
        return d


def braces(pattern):
    m = re.search(r"\{([^{}]*)\}", pattern)
    if not m:
        return [pattern]
    return [p for alt in m.group(1).split(",") for p in braces(pattern[:m.start()] + alt + pattern[m.end():])]


def render_helm(app, src, refs, repos, work):
    helm = src.get("helm", {})
    name = app["metadata"]["name"]
    repo, chart, ver = src["repoURL"], src["chart"], str(src["targetRevision"])
    args = ["template", helm.get("releaseName", name)]
    args += [chart, "--repo", repo] if repo.startswith("http") else [f"oci://{repo}/{chart}"]
    args += ["--version", ver, "--namespace", app["spec"]["destination"].get("namespace", "default"),
             "--include-crds", "--kube-version", TOOLS["KUBERNETES_VERSION"]]
    mounts = [(os.path.join(CACHE, "helm"), "/cache"), (work, "/work")]
    n = 0
    for vf in helm.get("valueFiles", []):
        m = re.match(r"\$(\w+)/(.*)", vf)
        if not m or m.group(1) not in refs:
            die(f"{name}: unsupported valueFile {vf}")
        ref = refs[m.group(1)]
        d = repos.checkout(ref["repoURL"], str(ref["targetRevision"]))
        f = os.path.join(d, m.group(2))
        if not os.path.isfile(f):
            die(f"{name}: valueFile {vf} not found in {ref['repoURL']}@{ref['targetRevision']}")
        n += 1
        mounts.append((f, f"/src/values-{n}.yaml"))
        args += ["-f", f"/src/values-{n}.yaml"]
    for key in ("valuesObject", "values"):
        if key in helm:
            n += 1
            p = os.path.join(work, f"inline-{n}.yaml")
            with open(p, "w") as fh:
                v = helm[key]
                fh.write(v if isinstance(v, str) else yaml.safe_dump(v))
            args += ["-f", f"/work/inline-{n}.yaml"]
    os.makedirs(os.path.join(CACHE, "helm"), exist_ok=True)
    env = {"HELM_CACHE_HOME": "/cache/cache", "HELM_CONFIG_HOME": "/cache/config", "HELM_DATA_HOME": "/cache/data"}
    return docker(TOOLS["HELM_IMAGE"], args, mounts, env)


def render_path(app, src, repos):
    d = os.path.join(repos.checkout(src["repoURL"], str(src.get("targetRevision", "HEAD"))), src["path"])
    if not os.path.isdir(d):
        die(f"{app['metadata']['name']}: path {src['path']} not found in {src['repoURL']}")
    if any(os.path.isfile(os.path.join(d, k)) for k in ("kustomization.yaml", "kustomization.yml", "Kustomization")):
        return docker(TOOLS["KUSTOMIZE_IMAGE"], ["build", "/src/k"], [(d, "/src/k")])
    opts = src.get("directory", {})
    inc = braces(opts.get("include", "*")) if opts.get("include") else None
    exc = braces(opts["exclude"]) if opts.get("exclude") else []
    out = []
    for root, dirs, files in os.walk(d):
        if not opts.get("recurse"):
            dirs[:] = []
        for f in sorted(files):
            rel = os.path.relpath(os.path.join(root, f), d)
            if not f.endswith((".yaml", ".yml", ".json")):
                continue
            if inc and not any(fnmatch.fnmatch(rel, p) for p in inc):
                continue
            if any(fnmatch.fnmatch(rel, p) for p in exc):
                continue
            out.append(open(os.path.join(root, f)).read())
    return "\n---\n".join(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("apps")
    ap.add_argument("--out", required=True)
    ap.add_argument("--repo", action="append", default=[])
    ap.add_argument("--only", action="append", default=[], help="render only these Applications")
    ap.add_argument("--only-repo", help="render only Applications with a source from this repoURL")
    a = ap.parse_args()
    repos = Repos(dict(r.split("=", 1) for r in a.repo))
    os.makedirs(a.out, exist_ok=True)
    apps = [x for x in yaml.safe_load_all(open(a.apps)) if x]
    for app in apps:
        name = app["metadata"]["name"]
        spec = app["spec"]
        sources = spec.get("sources") or [spec["source"]]
        if a.only and name not in a.only:
            continue
        if a.only_repo and not any(s.get("repoURL", "").rstrip("/") == a.only_repo.rstrip("/") for s in sources):
            continue
        refs = {s["ref"]: s for s in sources if s.get("ref")}
        parts = []
        with tempfile.TemporaryDirectory() as work:
            os.chmod(work, 0o777)
            for s in sources:
                if s.get("chart"):
                    parts.append(render_helm(app, s, refs, repos, work))
                elif s.get("path") is not None:
                    parts.append(render_path(app, s, repos))
        text = "\n---\n".join(parts)
        with open(os.path.join(a.out, f"{name}.yaml"), "w") as fh:
            fh.write(text)
        try:
            # trailing tabs are valid for Argo CD's Go YAML parser but not for PyYAML (prometheus chart)
            docs = [d for d in yaml.safe_load_all(re.sub(r"[ \t]+$", "", text, flags=re.M)) if d]
        except yaml.YAMLError as e:
            die(f"{name}: rendered output is not valid YAML: {e}")
        print(f"  ✔ {name}: {len(docs)} objects", file=sys.stderr)


if __name__ == "__main__":
    main()
