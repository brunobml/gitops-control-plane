#!/usr/bin/env python3
"""Check that each team directory has its generated tenant-iac ApplicationSet."""
import glob
import os
import re
import subprocess
import sys

cp = sys.argv[1]
ti = sys.argv[2] if len(sys.argv) > 2 else None
errors = []
files = sorted(glob.glob(os.path.join(cp, "applicationsets", "tenant-iac-*.yaml")))
teams = []
for path in files:
    name = os.path.basename(path)
    match = re.fullmatch(r"tenant-iac-([a-z0-9-]+)\.yaml", name)
    if not match:
        errors.append(f"invalid ApplicationSet filename: {name}")
        continue
    team = match.group(1)
    teams.append(team)
    result = subprocess.run(
        ["bash", os.path.join(cp, "scripts", "tenant-iac-appset.sh"), team],
        capture_output=True, text=True, check=False,
    )
    if result.returncode:
        errors.append(f"{name}: {result.stderr.strip()}")
    elif open(path, encoding="utf-8").read() != result.stdout:
        errors.append(f"{name} differs from scripts/tenant-iac-appset.sh {team}")
if not files:
    errors.append("no tenant-iac ApplicationSet found")
if ti:
    dirs = sorted(os.path.basename(p) for p in glob.glob(os.path.join(ti, "teams", "*"))
                  if os.path.isdir(os.path.join(p, "clusters")))
    for team in dirs:
        if team not in teams:
            errors.append(f"teams/{team}/ has no tenant-iac-{team} ApplicationSet")
for error in errors:
    print(f"✘ {error}", file=sys.stderr)
if errors:
    sys.exit(1)
print(f"✔ {len(files)} tenant-iac ApplicationSet(s) match templates", file=sys.stderr)
