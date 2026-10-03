#!/usr/bin/env python3
"""Check tenant registrations (2026-10-03 Track A.2).

usage: check-registrations.py <tenant-workloads checkout>

  - every tenants/<tenant>/apps/*.yaml validates against schema/registration.schema.json
    (fields, env, port per spoke, prod = full SHA, app name allowed by the AppProject);
  - file name is <app>-<env>.yaml and `tenant` equals the directory;
  - <app>-<env> is unique across all tenants;
  - the values file (valuesFile, default deploy/values-<env>.yaml) exists in orders-processor at
    valuesRevision, and a prod SHA is a real commit there.
"""
import glob, json, os, subprocess, sys
import yaml
from jsonschema import Draft202012Validator

APP_REPO = "https://github.com/brunobml/orders-processor.git"
CACHE = os.environ.get("LAB_CI_CACHE", os.path.expanduser("~/.cache/lab-ci"))


def fetch(rev):
    d = os.path.join(CACHE, "git", f"orders-processor@{rev}")
    if not os.path.isdir(os.path.join(d, ".git")):
        subprocess.run(["git", "init", "-q", d], check=True)
    r = subprocess.run(["git", "-C", d, "fetch", "-q", "--depth", "1", APP_REPO, rev], capture_output=True, text=True)
    if r.returncode != 0:
        return None
    subprocess.run(["git", "-C", d, "checkout", "-q", "-f", "FETCH_HEAD"], check=True)
    return d


def main():
    root = sys.argv[1]
    validator = Draft202012Validator(json.load(open(os.path.join(root, "schema", "registration.schema.json"))))
    errs, seen = [], {}
    files = sorted(glob.glob(os.path.join(root, "tenants", "*", "apps", "*.yaml")))
    for path in files:
        rel = os.path.relpath(path, root)
        try:
            reg = yaml.safe_load(open(path))
        except yaml.YAMLError as e:
            errs.append(f"{rel}: not valid YAML: {e}")
            continue
        problems = [f"{'.'.join(map(str, e.absolute_path)) or '(root)'}: {e.message}" for e in validator.iter_errors(reg)]
        if problems:
            errs += [f"{rel}: {p}" for p in problems]
            continue
        tenant_dir = rel.split(os.sep)[1]
        name = f"{reg['app']}-{reg['env']}"
        if reg["tenant"] != tenant_dir:
            errs.append(f"{rel}: tenant '{reg['tenant']}' does not match directory tenants/{tenant_dir}/")
        if os.path.basename(path) != f"{name}.yaml":
            errs.append(f"{rel}: file must be named {name}.yaml")
        if name in seen:
            errs.append(f"{rel}: {name} is already registered by {seen[name]}")
        seen[name] = rel
        vf = reg.get("valuesFile", f"deploy/values-{reg['env']}.yaml")
        d = fetch(str(reg["valuesRevision"]))
        if d is None:
            errs.append(f"{rel}: valuesRevision {reg['valuesRevision']} not found in orders-processor")
        elif not os.path.isfile(os.path.join(d, vf)):
            errs.append(f"{rel}: {vf} does not exist in orders-processor at {reg['valuesRevision']}")
        else:
            print(f"  ✔ {rel}: {name} -> {vf}@{str(reg['valuesRevision'])[:12]}", file=sys.stderr)
    for e in errs:
        print(f"✘ {e}", file=sys.stderr)
    if not files:
        errs.append("no registrations found")
    if errs:
        sys.exit(1)
    print(f"✔ {len(files)} registrations valid", file=sys.stderr)


if __name__ == "__main__":
    main()
