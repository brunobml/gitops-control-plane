#!/usr/bin/env python3
"""Regenerate ci/schemas/ from the CRDs installed in the lab (2026-10-03 Track A, review remark R-3).

kubeconform validates custom resources against these JSON schemas, so they must match the
controller versions the lab runs: Argo CD, Traefik, kro (including the QueueBackedService CRD kro
generates), Kyverno, ACK SQS and the k3s helm controller. Re-run after upgrading any of them:

    python3 ci/update-crd-schemas.py          # reads the CRDs from all three lab clusters

Layout: ci/schemas/<group>/<kind>_<version>.json (lower-case kind), the layout kubeconform's
-schema-location '{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' expects. The conversion
follows kubeconform's openapi2jsonschema: int-or-string becomes oneOf string/integer, nullable adds
null, and a required field with a default is optional (the API server defaults
it before validation). Schemas are not strict (unknown fields are allowed, as the API server prunes them).
"""
import json, os, shutil, subprocess

ROOT = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(ROOT, "schemas")
CONTEXTS = ["k3d-hub-cluster", "k3d-spoke-nonprod", "k3d-spoke-prod"]


def convert(s):
    if isinstance(s, list):
        return [convert(x) for x in s]
    if not isinstance(s, dict):
        return s
    s = {k: convert(v) for k, v in s.items()}
    if s.get("x-kubernetes-int-or-string") or s.get("format") == "int-or-string":
        s.pop("type", None)
        s.pop("format", None)
        s["oneOf"] = [{"type": "string"}, {"type": "integer"}]
    if s.pop("nullable", False) and isinstance(s.get("type"), str):
        s["type"] = [s["type"], "null"]
    # The API server fills defaults before validating; kubeconform does not, so a required field
    # that has a default is not required in the manifest (e.g. kro RGD spec.schema.scope).
    props = s.get("properties")
    if isinstance(props, dict) and isinstance(s.get("required"), list):
        s["required"] = [r for r in s["required"] if not (isinstance(props.get(r), dict) and "default" in props[r])]
        if not s["required"]:
            del s["required"]
    return s


def main():
    crds = {}
    for ctx in CONTEXTS:
        items = json.loads(subprocess.check_output(["kubectl", "--context", ctx, "get", "crd", "-o", "json"]))["items"]
        for c in items:
            crds.setdefault(c["metadata"]["name"], c)
    if os.path.isdir(OUT):
        shutil.rmtree(OUT)
    n = 0
    for name in sorted(crds):
        spec = crds[name]["spec"]
        for v in spec["versions"]:
            schema = (v.get("schema") or {}).get("openAPIV3Schema")
            if not schema:
                continue
            d = os.path.join(OUT, spec["group"])
            os.makedirs(d, exist_ok=True)
            s = convert(schema)
            s["$schema"] = "http://json-schema.org/schema#"
            with open(os.path.join(d, f"{spec['names']['kind'].lower()}_{v['name']}.json"), "w") as f:
                json.dump(s, f, sort_keys=True, separators=(",", ":"))
                f.write("\n")
            n += 1
    print(f"✔ {n} schemas from {len(crds)} CRDs in {OUT}")


if __name__ == "__main__":
    main()
