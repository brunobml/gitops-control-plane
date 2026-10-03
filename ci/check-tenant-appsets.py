#!/usr/bin/env python3
"""Tenant ApplicationSets (2026-10-03 Track B.2).

usage: check-tenant-appsets.py <gitops-control-plane dir> [<tenant-workloads dir>]

  - every applicationsets/tenant-workloads-<tenant>.yaml is exactly what
    `scripts/tenant-appset.sh <tenant>` prints (no hand edits, no drift between tenants);
  - with the tenant-workloads checkout: every tenants/<tenant>/ directory has its ApplicationSet,
    so a new tenant's registrations cannot be silently ignored; an ApplicationSet without a
    tenant directory is reported.
"""
import glob, os, re, subprocess, sys

cp = sys.argv[1]
tw = sys.argv[2] if len(sys.argv) > 2 else None
errs = []
files = sorted(glob.glob(os.path.join(cp, "applicationsets", "tenant-workloads-*.yaml")))
tenants = [re.match(r"tenant-workloads-(.+)\.yaml$", os.path.basename(f)).group(1) for f in files]
for f, t in zip(files, tenants):
    want = subprocess.run([os.path.join(cp, "scripts", "tenant-appset.sh"), t], capture_output=True, text=True)
    if want.returncode != 0:
        errs.append(f"{t}: {want.stderr.strip()}")
    elif open(f).read() != want.stdout:
        errs.append(f"{os.path.relpath(f, cp)} differs from `scripts/tenant-appset.sh {t}` (regenerate it; do not edit by hand)")
if not files:
    errs.append("no applicationsets/tenant-workloads-<tenant>.yaml found")
if tw:
    dirs = sorted(os.path.basename(d) for d in glob.glob(os.path.join(tw, "tenants", "*")) if os.path.isdir(os.path.join(d, "apps")))
    for d in dirs:
        if d not in tenants:
            errs.append(f"tenants/{d}/ has no ApplicationSet: its registrations would be ignored. Platform onboarding: "
                        f"scripts/tenant-appset.sh {d} > applicationsets/tenant-workloads-{d}.yaml (gitops-control-plane)")
    for t in tenants:
        if t not in dirs:
            print(f"  ! tenant-workloads-{t}: no tenants/{t}/apps/ directory (no registrations yet)", file=sys.stderr)
for e in errs:
    print(f"✘ {e}", file=sys.stderr)
if errs:
    sys.exit(1)
print(f"✔ {len(files)} tenant ApplicationSet(s) match the template: {', '.join(tenants)}", file=sys.stderr)
