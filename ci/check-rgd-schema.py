#!/usr/bin/env python3
"""RGD schema compatibility lint (2026-10-03 Track A.3; lesson of Phase 3 D-14).

usage: check-rgd-schema.py <candidate blueprints dir> <promoted blueprints dir> <promoted revision>

kro 0.9.4 refuses to update the generated CRD on a "breaking change" and the RGD goes Inactive:
in Phase 3 D-14, adding required/enum/min/max markers to existing fields took the nonprod RGD
down for ~4 min. This lint compares every RGD's spec.schema with the revision prod runs:
  - an existing spec field removed or its definition changed (type, default, markers) -> FAIL
  - a status field removed -> FAIL; a status expression changed -> reported
  - a new field                                                                     -> reported
A deliberate breaking change needs a new RGD (new kind) or a migration plan, not an in-place edit.
"""
import glob, os, sys
import yaml


def rgds(d):
    out = {}
    for f in glob.glob(os.path.join(d, "*.yaml")):
        for doc in yaml.safe_load_all(open(f)):
            if doc and doc.get("kind") == "ResourceGraphDefinition":
                out[doc["metadata"]["name"]] = doc["spec"].get("schema", {})
    return out


def flatten(v, path, out):
    if isinstance(v, dict):
        for k, x in v.items():
            flatten(x, f"{path}.{k}", out)
    else:
        out[path] = v


def main():
    new, old, rev = rgds(sys.argv[1]), rgds(sys.argv[2]), sys.argv[3]
    errs = 0
    for name, old_schema in old.items():
        if name not in new:
            print(f"✘ RGD {name}: removed (prod runs it at {rev})", file=sys.stderr)
            errs += 1
            continue
        a, b = {}, {}
        flatten(old_schema, "schema", a)
        flatten(new[name], "schema", b)
        for p in sorted(a):
            if p not in b:
                print(f"✘ RGD {name}: {p} removed (breaking for kro; prod at {rev})", file=sys.stderr)
                errs += 1
            elif a[p] != b[p] and p.startswith("schema.status."):
                # a status value is an expression; its CRD field stays, kro re-infers the type
                print(f"  ~ RGD {name}: {p} expression changed (status; reported only)", file=sys.stderr)
            elif a[p] != b[p]:
                print(f"✘ RGD {name}: {p} changed {a[p]!r} -> {b[p]!r} (breaking for kro; prod at {rev})", file=sys.stderr)
                errs += 1
        for p in sorted(set(b) - set(a)):
            print(f"  + RGD {name}: new field {p} = {b[p]!r} (additive)", file=sys.stderr)
    if errs:
        print("✘ RGD schema is not compatible with the promoted revision (Phase 3 D-14)", file=sys.stderr)
        sys.exit(1)
    print(f"✔ {len(new)} RGD schema(s) compatible with {rev}", file=sys.stderr)


if __name__ == "__main__":
    main()
