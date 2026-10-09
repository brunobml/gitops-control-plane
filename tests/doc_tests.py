#!/usr/bin/env python3
"""Doc-test markers for the learner path (learner on-ramp plan, Track C; guardrail G-3).

Every fenced ```bash block in the learner documents must be preceded (on the line just above the
fence) by exactly one marker:

  <!-- doc-test: run [attributes] -->        read-only: executed against the running lab
  <!-- doc-test: mutating [attributes] -->   changes state but reverts by itself (kro/ACK repair, a
                                             create followed by a delete): executed with --mutating
  <!-- doc-test: covered by="..." -->        exercised elsewhere: a check of tests/test_doc_examples.sh
                                             (by="check:<id>"), make test-lab1 (by="check:test-lab1")
                                             or a Bats gate (by="bats:Gate 10d")
  <!-- doc-test: skip reason="..." -->       not executed, with the reason (disruptive, interactive, ...)

Attributes for run/mutating:
  with="aws_as <account>"     prepend the tutorial's aws_as helper (developer-tutorial.md Step 4) and call it
  with="argocd-session"       log in to Argo CD as break-glass platform-admin into a temporary --config
                              (ARGOCD_OPTS), for blocks that need any CLI session; removed afterwards
  subst="<a>=x,<b>=y"         replace placeholders before running (e.g. "<team>=team-data")
  expect="regex"              the combined output must match (catches commands that "succeed" silently)
  cwd="../tenant-iac"         working directory relative to the repository root (default: the root)
  timeout="300"               seconds

usage:
  doc_tests.py --markers-only          static: every block marked, attributes valid (CI, no lab)
  doc_tests.py [--mutating]            run the run blocks (and the mutating ones, each from a repaired lab)
"""
import os, re, shlex, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DOCS = [
    "README.md",
    "docs/lab-0-guided-tour.md",
    "docs/lab-1-write-a-blueprint.md",
    "docs/runbooks/devops-student-rebuild-guide.md",
    "docs/developer-tutorial.md",
    "docs/concepts-and-glossary.md",
    "docs/runbooks/tenant-iac-operations.md",
    "docs/runbooks/argocd-cli.md",
]
KINDS = {"run", "mutating", "covered", "skip"}
# check:test-lab1 = make test-lab1 (Lab 1 in a fresh sandbox; local only, not part of make test-docs)
DEDICATED_CHECKS = {"tenant-iac-claim", "tenant-iac-step3", "tutorial-values", "tutorial-sqs", "test-lab1"}
ARGOCD_SESSION = r"""
_doctest_argocd=$(mktemp -d); trap 'rm -rf "$_doctest_argocd"' EXIT
export ARGOCD_OPTS="--config $_doctest_argocd/config"
argocd login localhost --username platform-admin --password "$(cat ~/.config/gitops-lab/argocd-platform-admin.password)" \
  --grpc-web --plaintext --skip-test-tls >/dev/null
"""
FENCE = re.compile(r"^(\s*)```(\S*)\s*$")
MARKER = re.compile(r"^\s*<!--\s*doc-test:\s*(\w+)(.*?)-->\s*$")
ATTR = re.compile(r'(\w+)="([^"]*)"')


def blocks(path):
    """Yield (line, lang, marker_line_text, body) for each fenced block."""
    lines = open(os.path.join(ROOT, path)).read().split("\n")
    i = 0
    while i < len(lines):
        m = FENCE.match(lines[i])
        if m and m.group(2):
            indent, lang = len(m.group(1)), m.group(2)
            j = i + 1
            while j < len(lines) and not re.match(r"^\s*```\s*$", lines[j]):
                j += 1
            body = "\n".join(l[indent:] if l[:indent].strip() == "" else l for l in lines[i + 1:j])
            prev = lines[i - 1] if i > 0 else ""
            yield i + 1, lang, prev, body
            i = j + 1
        elif m:  # opening fence without a language, or a stray closing fence
            j = i + 1
            while j < len(lines) and not re.match(r"^\s*```\s*$", lines[j]):
                j += 1
            i = j + 1
        else:
            i += 1


def bats_gates():
    names = []
    for f in sorted(os.listdir(os.path.join(ROOT, "tests/smoke"))):
        if f.endswith(".bats"):
            names += re.findall(r'^@test "([^"]+)"', open(os.path.join(ROOT, "tests/smoke", f)).read(), re.M)
    return names


def aws_as_definition():
    for _, lang, _, body in blocks("docs/developer-tutorial.md"):
        if lang == "bash" and "aws_as() {" in body:
            out, depth = [], 0
            for line in body.split("\n")[body.split("\n").index(next(l for l in body.split("\n") if l.startswith("aws_as() {"))):]:
                out.append(line)
                depth += line.count("{") - line.count("}")
                if depth == 0:
                    return "\n".join(out)
    raise SystemExit("aws_as() not found in developer-tutorial.md")


def inventory():
    """Parse all markers; return (entries, errors)."""
    entries, errors, gates = [], [], bats_gates()
    tutorial_aws_as = aws_as_definition()
    for doc in DOCS:
        for line, lang, prev, body in blocks(doc):
            if lang != "bash":
                continue
            where = f"{doc}:{line}"
            m = MARKER.match(prev)
            if not m:
                errors.append(f"{where}: bash block without a doc-test marker on the line above")
                continue
            kind, attrs = m.group(1), dict(ATTR.findall(m.group(2)))
            if kind not in KINDS:
                errors.append(f"{where}: unknown doc-test kind '{kind}'")
                continue
            if kind == "skip" and not attrs.get("reason"):
                errors.append(f"{where}: skip needs reason=\"...\"")
            if kind == "covered":
                by = attrs.get("by", "")
                if by.startswith("check:") and by[6:] in DEDICATED_CHECKS:
                    pass
                elif by.startswith("bats:") and any(g.startswith(by[5:]) for g in gates):
                    pass
                else:
                    errors.append(f"{where}: covered by=\"{by}\" is not a known check:<id> or bats:<gate>")
            if "aws_as() {" in body and doc != "docs/developer-tutorial.md" and tutorial_aws_as not in body:
                errors.append(f"{where}: copy of aws_as() differs from developer-tutorial.md Step 4")
            if kind in ("run", "mutating"):
                w = attrs.get("with", "")
                if w and w != "argocd-session" and not re.fullmatch(r"aws_as [0-9]{12}", w):
                    errors.append(f"{where}: unknown with=\"{w}\" (aws_as <account> or argocd-session)")
                left = re.findall(r"<[a-z][a-z-]*>", apply_subst(body, attrs.get("subst", "")))
                if left:
                    errors.append(f"{where}: unsubstituted placeholders {sorted(set(left))} (add subst=\"...\" or skip)")
                if "expect" in attrs:
                    try:
                        re.compile(attrs["expect"])
                    except re.error as e:
                        errors.append(f"{where}: invalid expect regex: {e}")
            entries.append({"where": where, "kind": kind, "attrs": attrs, "body": body})
    return entries, errors


def apply_subst(body, subst):
    for pair in [p for p in subst.split(",") if p]:
        k, _, v = pair.partition("=")
        body = body.replace(k, v)
    return body


def run(entry, aws_as):
    a = entry["attrs"]
    script = "set -o pipefail\n"
    if a.get("with", "").startswith("aws_as "):
        script += aws_as + "\n" + a["with"] + "\n"
    elif a.get("with") == "argocd-session":
        script += ARGOCD_SESSION
    script += apply_subst(entry["body"], a.get("subst", ""))
    cwd = os.path.normpath(os.path.join(ROOT, a.get("cwd", ".")))
    env = {"HOME": os.environ["HOME"], "PATH": os.environ["PATH"], "TERM": "dumb"}
    try:
        p = subprocess.run(["bash", "-e", "-c", script], cwd=cwd, env=env, capture_output=True, text=True,
                           timeout=int(a.get("timeout", "300")))
    except subprocess.TimeoutExpired:
        return False, "timed out"
    out = p.stdout + p.stderr
    if p.returncode != 0:
        return False, f"exit {p.returncode}: {out.strip().splitlines()[-1] if out.strip() else ''}"
    if "expect" in a and not re.search(a["expect"], out):
        return False, f"output does not match expect=\"{a['expect']}\": {out.strip()[:160]!r}"
    return True, ""


def main():
    markers_only = "--markers-only" in sys.argv
    mutating = "--mutating" in sys.argv
    entries, errors = inventory()
    counts = {k: sum(1 for e in entries if e["kind"] == k) for k in KINDS}
    total = len(entries) + sum(1 for e in errors if "without a doc-test marker" in e)
    for e in errors:
        print(f"  ✘ {e}")
    print(f"  doc-test markers: {total} bash blocks in {len(DOCS)} learner documents: "
          f"run {counts['run']}, mutating {counts['mutating']}, covered {counts['covered']}, "
          f"skip {counts['skip']}, invalid or unmarked {len(errors)}")
    if markers_only:
        return 1 if errors else 0
    failed = len(errors)
    aws_as = aws_as_definition()
    # read-only blocks first: a mutating block (e.g. the Drill 4 delete) would make the next
    # observation block fail while the repair is still pending
    for kind in ("run", "mutating"):
        for e in [x for x in entries if x["kind"] == kind]:
            if kind == "mutating" and not mutating:
                print(f"  - mutating {e['where']}: not run (use MODE=live-mutating)")
                continue
            # each mutating block starts from a repaired lab, as a learner would after station 0
            # (Lab 0 station 6 and Drill 4 delete the same queue)
            if kind == "mutating" and not settle(aws_as, bats=False, quiet=True):
                failed += 1
                continue
            ok, why = run(e, aws_as)
            print(f"  {'✔' if ok else '✘'} {kind:8} {e['where']}{'' if ok else ': ' + why}")
            failed += 0 if ok else 1
    if mutating:
        failed += 0 if settle(aws_as) else 1
    return 1 if failed else 0


SETTLE = r"""
apps=$(kubectl --context k3d-hub-cluster -n argocd get applications --no-headers | grep -vc "Synced *Healthy" || true)
aws_as 111111111111
dlq=$(aws --endpoint-url=http://localhost:5000 sqs get-queue-url --queue-name orders-dev-dlq --output text 2>/dev/null || true)
users=$(scripts/temp-sso-user.sh list 2>/dev/null | grep -c doctest-learner || true)
# Lab 0 station 5: kro restores the hand-scaled worker and the deleted ConfigMap
replicas=$(kubectl --context k3d-spoke-nonprod -n orders-dev get deployment orders-dev-worker -o jsonpath='{.spec.replicas}' || true)
cm=$(kubectl --context k3d-spoke-nonprod -n orders-dev get configmap orders-dev-config -o name 2>/dev/null || true)
echo "apps-not-green=$apps dlq=${dlq:-missing} doctest-users=$users worker-replicas=${replicas:-?} config=${cm:-missing}"
[[ "$apps" == 0 && -n "$dlq" && "$users" == 0 && "$replicas" == 1 && -n "$cm" ]]
"""


def settle(aws_as, limit=480, bats=True, quiet=False):
    """After the mutating blocks, wait until the lab has repaired itself, then confirm with Bats."""
    import time
    env = {"HOME": os.environ["HOME"], "PATH": os.environ["PATH"], "TERM": "dumb"}
    t0 = time.time()
    while True:
        p = subprocess.run(["bash", "-c", aws_as + "\n" + SETTLE], cwd=ROOT, env=env, capture_output=True, text=True)
        state = (p.stdout.strip().splitlines() or ["?"])[-1]
        if p.returncode == 0:
            waited = int(time.time() - t0)
            if not quiet or waited:
                print(f"  ✔ settle: lab repaired after {waited} s ({state})")
            break
        if time.time() - t0 > limit:
            print(f"  ✘ settle: lab not repaired after {limit} s ({state})")
            return False
        time.sleep(20)
    if not bats:
        return True
    env["BATS_REPORT_CALLER"] = "test-docs"
    b = subprocess.run(["bash", "scripts/smoke-test-hub-spoke-bats.sh"], cwd=ROOT, env=env, capture_output=True, text=True)
    notok = sum(1 for l in b.stdout.splitlines() if l.startswith("not ok"))
    good = b.returncode == 0 and notok == 0
    print(f"  {'✔' if good else '✘'} settle: Bats smoke suite {'all ok' if good else f'{notok} not ok'}")
    return good


if __name__ == "__main__":
    sys.exit(main())
