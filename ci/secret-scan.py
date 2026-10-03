#!/usr/bin/env python3
"""Scan tracked files for credential patterns (2026-10-03 Track A.1; the Phase 5 X22 pattern set
applied to Git instead of logs). Never prints a match itself, only file:line and the pattern name.

usage: secret-scan.py [repo dir]     (scans `git ls-files` of that repo; default: cwd)

A line that legitimately looks like a credential (e.g. a documented placeholder) can carry the
marker `lab-ci: not-a-secret` to be skipped.
"""
import os, re, subprocess, sys

PATTERNS = {
    "private key": re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH |DSA |PGP |ENCRYPTED )?PRIVATE KEY-----"),
    "AWS access key id": re.compile(r"\b(?:AKIA|ASIA)[0-9A-Z]{16}\b"),
    "GitHub token": re.compile(r"\b(?:gh[pousr]_[A-Za-z0-9]{36,}|github_pat_[A-Za-z0-9_]{50,})\b"),
    "JWT / service-account token": re.compile(r"\beyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}"),
    "bcrypt hash (htpasswd)": re.compile(r"\$2[aby]\$\d\d\$[./A-Za-z0-9]{53}"),
    "Slack / generic webhook token": re.compile(r"\bxox[abprs]-[A-Za-z0-9-]{10,}"),
    "kubeconfig credential": re.compile(r"^\s*(?:client-key-data|client-certificate-data|token):\s*['\"]?[A-Za-z0-9+/=._-]{40,}", re.M),
    # Keys that hold a credential value. Keys that only *name* a Secret (secret, existingSecret,
    # secretName, secretKeyRef, ...) are not matched.
    "inline password value": re.compile(
        r"""(?ix)^\s*-?\s*["']?[\w.-]*(?:password|passwd|client[_-]?secret|secret[_-]?access[_-]?key|api[_-]?key)["']?\s*[:=]\s*["']?
            (?!\$|\{\{|<|\[|\(|\*|changeme|placeholder|example|redacted|mock|dummy|none|null|true|false|""|'')
            [^\s"'#]{12,}"""),
}
SKIP_EXT = (".png", ".jpg", ".gif", ".ico", ".tgz", ".gz", ".pdf")


def main():
    repo = sys.argv[1] if len(sys.argv) > 1 else "."
    files = subprocess.check_output(["git", "-C", repo, "ls-files"], text=True).split("\n")
    hits = 0
    for f in filter(None, files):
        if f.endswith(SKIP_EXT) or f.startswith("ci/schemas/"):
            continue
        try:
            text = open(os.path.join(repo, f), encoding="utf-8").read()
        except (UnicodeDecodeError, FileNotFoundError, IsADirectoryError):
            continue
        for n, line in enumerate(text.splitlines(), 1):
            if "lab-ci: not-a-secret" in line:
                continue
            for name, rx in PATTERNS.items():
                if rx.search(line):
                    hits += 1
                    print(f"✘ {f}:{n}: looks like a {name}", file=sys.stderr)
    if hits:
        print(f"✘ {hits} possible credential(s) in tracked files (values not shown)", file=sys.stderr)
        sys.exit(1)
    print(f"✔ secret scan: {len([f for f in files if f])} tracked files, no credential patterns", file=sys.stderr)


if __name__ == "__main__":
    main()
