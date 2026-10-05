#!/usr/bin/env python3
"""Check tenant cluster claims and fixtures (2026-10-05 Tenant IaC P3).

usage:
  check-clusters.py <tenant-iac checkout>
  check-clusters.py <tenant-iac checkout> --test-fixtures

Checks:
  - every teams/<team>/clusters/*.yaml validates against schema/cluster.schema.json
    (fields, DNS naming, env, allowed k8s versions, platform network, allowed instance types, bounds);
  - relational sizing: 1 <= minSize <= desiredSize <= maxSize;
  - file name is <name>-<env>.yaml and `team` equals the directory teams/<team>/;
  - <name>-<env> is unique across all teams;
  - max clusters per team (<= 5).
  - with --test-fixtures: asserts all negative fixtures fail and all positive fixtures pass.
"""
import glob, json, os, sys
import yaml
from jsonschema import Draft202012Validator

MAX_CLUSTERS_PER_TEAM = 5


def validate_claim_dict(claim, validator):
    errors = []
    for e in validator.iter_errors(claim):
        path = ".".join(map(str, e.absolute_path)) or "(root)"
        errors.append(f"{path}: {e.message}")

    ng = claim.get("nodeGroup")
    if isinstance(ng, dict):
        min_s = ng.get("minSize")
        des_s = ng.get("desiredSize")
        max_s = ng.get("maxSize")
        if isinstance(min_s, int) and isinstance(des_s, int) and isinstance(max_s, int):
            if not (1 <= min_s <= des_s <= max_s):
                errors.append(
                    f"spec.nodeGroup sizes must satisfy 1 <= minSize <= desiredSize <= maxSize "
                    f"(got minSize={min_s}, desiredSize={des_s}, maxSize={max_s})"
                )
    return errors


def test_fixtures(root, validator):
    print("Testing fixture suite...", file=sys.stderr)
    pos_files = sorted(glob.glob(os.path.join(root, "tests", "fixtures", "positive", "*.yaml")))
    neg_files = sorted(glob.glob(os.path.join(root, "tests", "fixtures", "negative", "*.yaml")))

    if not pos_files or not neg_files:
        print(f"✘ missing fixture files in {root}/tests/fixtures/", file=sys.stderr)
        return False

    failed = False
    # 1. Positive fixtures must all pass
    for pf in pos_files:
        rel = os.path.relpath(pf, root)
        try:
            doc = yaml.safe_load(open(pf))
            errs = validate_claim_dict(doc, validator)
            if errs:
                print(f"✘ positive fixture {rel} failed validation: {errs}", file=sys.stderr)
                failed = True
            else:
                print(f"  ✔ positive fixture passed: {rel}", file=sys.stderr)
        except Exception as ex:
            print(f"✘ positive fixture {rel} raised exception: {ex}", file=sys.stderr)
            failed = True

    # 2. Negative fixtures must all fail
    for nf in neg_files:
        rel = os.path.relpath(nf, root)
        try:
            doc = yaml.safe_load(open(nf))
            errs = validate_claim_dict(doc, validator)
            if not errs:
                print(f"✘ negative fixture {rel} unexpectedly passed validation!", file=sys.stderr)
                failed = True
            else:
                print(f"  ✔ negative fixture rejected as expected: {rel} ({errs[0]})", file=sys.stderr)
        except Exception as ex:
            # YAML parse error also qualifies as rejection
            print(f"  ✔ negative fixture rejected (parse error): {rel} ({ex})", file=sys.stderr)

    if failed:
        print("✘ fixture suite failed", file=sys.stderr)
        return False

    print(
        f"✔ fixture suite: {len(pos_files)}/{len(pos_files)} positive passed, "
        f"{len(neg_files)}/{len(neg_files)} negative rejected",
        file=sys.stderr
    )
    return True


def check_live_claims(root, validator):
    files = sorted(glob.glob(os.path.join(root, "teams", "*", "clusters", "*.yaml")))
    if not files:
        print("✔ 0 live team clusters found (directory ready for onboarding)", file=sys.stderr)
        return True

    errs = []
    seen = {}
    team_counts = {}

    for path in files:
        rel = os.path.relpath(path, root)
        try:
            claim = yaml.safe_load(open(path))
        except yaml.YAMLError as e:
            errs.append(f"{rel}: not valid YAML: {e}")
            continue

        if not isinstance(claim, dict):
            errs.append(f"{rel}: content must be a YAML mapping")
            continue

        problems = validate_claim_dict(claim, validator)
        if problems:
            errs += [f"{rel}: {p}" for p in problems]
            continue

        parts = rel.split(os.sep)
        team_dir = parts[1]
        name = f"{claim['name']}-{claim['env']}"

        if claim["team"] != team_dir:
            errs.append(f"{rel}: team '{claim['team']}' does not match directory teams/{team_dir}/")

        if os.path.basename(path) != f"{name}.yaml":
            errs.append(f"{rel}: file must be named {name}.yaml")

        if name in seen:
            errs.append(f"{rel}: cluster {name} is already registered by {seen[name]}")
        seen[name] = rel

        team_counts[team_dir] = team_counts.get(team_dir, 0) + 1
        if team_counts[team_dir] > MAX_CLUSTERS_PER_TEAM:
            errs.append(f"{rel}: team {team_dir} exceeds max cluster limit ({MAX_CLUSTERS_PER_TEAM})")

        print(f"  ✔ {rel}: cluster {claim['team']}/{name} valid", file=sys.stderr)

    for e in errs:
        print(f"✘ {e}", file=sys.stderr)

    if errs:
        return False

    print(f"✔ {len(files)} team cluster claims valid", file=sys.stderr)
    return True


def main():
    if len(sys.argv) < 2:
        print("usage: check-clusters.py <tenant-iac checkout> [--test-fixtures]", file=sys.stderr)
        sys.exit(1)

    root = os.path.abspath(sys.argv[1])
    test_mode = "--test-fixtures" in sys.argv

    schema_file = os.path.join(root, "schema", "cluster.schema.json")
    if not os.path.isfile(schema_file):
        print(f"✘ schema file not found: {schema_file}", file=sys.stderr)
        sys.exit(1)

    with open(schema_file) as f:
        schema = json.load(f)
    validator = Draft202012Validator(schema)

    success = True
    if test_mode:
        if not test_fixtures(root, validator):
            success = False
    else:
        if not check_live_claims(root, validator):
            success = False

    if not success:
        sys.exit(1)


if __name__ == "__main__":
    main()
