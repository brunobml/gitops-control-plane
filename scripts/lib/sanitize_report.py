#!/usr/bin/env python3
"""
scripts/lib/sanitize_report.py

Parses Bats JUnit XML, applies exact-value and pattern-based secret redaction,
neutralizes hostnames and absolute paths, bounds diagnostic lengths, validates
fail-closed against known lab secrets, and generates metadata.json.
"""

import argparse
import base64
import hashlib
import json
import os
import re
import socket
import sys
import urllib.parse
import xml.etree.ElementTree as ET
from pathlib import Path


def load_known_secrets() -> dict[str, str]:
    """
    Collects known secrets from ~/.config/gitops-lab/ and active worker credentials.
    Returns mapping of secret_value -> label.
    """
    secrets = {}
    config_dir = Path.home() / ".config" / "gitops-lab"
    if config_dir.is_dir():
        for path in config_dir.glob("*"):
            # Only load actual secret files (passwords, secrets, tokens, keys); ignore usernames/IDs
            if path.is_file() and (path.name.endswith(".password") or path.name.endswith(".secret") or "token" in path.name or "key" in path.name):
                try:
                    content = path.read_text().strip()
                    if content and len(content) >= 4:
                        secrets[content] = path.name
                except Exception:
                    pass

    # Also inspect k3d worker secrets if accessible via kubectl
    for ns, name in [("orders-dev", "orders-dev-aws"), ("orders-test", "orders-test-aws"), ("orders-prod", "orders-prod-aws")]:
        ctx = "k3d-spoke-prod" if "prod" in ns else "k3d-spoke-nonprod"
        # Try reading without failing if cluster not ready
        try:
            import subprocess
            cmd = ["kubectl", "--context", ctx, "-n", ns, "get", "secret", name, "-o", "json"]
            res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=3)
            if res.returncode == 0:
                data = json.loads(res.stdout).get("data", {})
                for k, v in data.items():
                    val = base64.b64decode(v).decode(errors="ignore").strip()
                    if val and len(val) >= 4 and val != "mock-secret" and val != "mock-key":
                        secrets[val] = f"{name}.{k}"
        except Exception:
            pass

    return secrets


def build_redaction_pairs(known_secrets: dict[str, str]) -> list[tuple[str, str]]:
    """
    Builds sorted replacement pairs (raw, base64, url-encoded).
    Longer strings replaced first to prevent partial substrings.
    """
    pairs = []
    for secret, label in known_secrets.items():
        # Raw
        pairs.append((secret, f"[REDACTED:{label}]"))
        # Base64 (if at least 6 chars)
        if len(secret) >= 6:
            b64 = base64.b64encode(secret.encode()).decode()
            pairs.append((b64, f"[REDACTED:{label}:BASE64]"))
        # URL encoded
        url_enc = urllib.parse.quote(secret, safe="")
        if url_enc != secret:
            pairs.append((url_enc, f"[REDACTED:{label}:URL]"))

    # Sort descending by length of target string
    pairs.sort(key=lambda x: len(x[0]), reverse=True)
    return pairs


def sanitize_text(text: str, redaction_pairs: list[tuple[str, str]], home_dir: str, hostname: str, max_bytes: int = 8192) -> str:
    if not text:
        return ""

    # Truncate length if needed
    encoded = text.encode("utf-8")
    truncated = False
    if len(encoded) > max_bytes:
        text = encoded[:max_bytes].decode("utf-8", errors="ignore")
        truncated = True

    # 1. Exact-value redactions
    for secret, replacement in redaction_pairs:
        if secret in text:
            text = text.replace(secret, replacement)

    # 2. Targeted patterns
    # JWT Bearer tokens
    text = re.sub(r"Bearer\s+eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+", "Bearer [REDACTED:JWT]", text)
    # Standalone JWT tokens
    text = re.sub(r"\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]+\b", "[REDACTED:JWT]", text)
    # AWS Access Key IDs
    text = re.sub(r"\b(AKIA|ASIA)[A-Z0-9]{16}\b", "[REDACTED:AWS_KEY_ID]", text)
    # Common password/token patterns
    text = re.sub(r"(?i)\b(password|token|secret|access_key|api_key)\s*[:=]\s*['\"]?([^\s'\"&,;]{6,})['\"]?", r"\1=[REDACTED]", text)

    # 3. Path & Hostname neutralization
    if home_dir and home_dir in text:
        text = text.replace(home_dir, "~")
    if hostname and hostname != "localhost" and hostname in text:
        text = text.replace(hostname, "lab-host")

    if truncated:
        text += "\n[TRUNCATED: output exceeded 8 KiB cap]"

    return text


def sanitize_xml(input_xml_path: Path, output_xml_path: Path, known_secrets: dict[str, str]) -> tuple[dict, str]:
    """
    Parses and sanitizes JUnit XML.
    Returns (summary_dict, sha256_hex).
    Fails closed if any known secret remains in the final serialized XML.
    """
    tree = ET.parse(input_xml_path)
    root = tree.getroot()

    home_dir = str(Path.home())
    hostname = socket.gethostname()
    redaction_pairs = build_redaction_pairs(known_secrets)

    total_tests = 0
    total_failures = 0
    total_errors = 0
    total_skipped = 0
    total_duration = 0.0

    # Sanitize root and testsuites
    if "hostname" in root.attrib:
        root.attrib["hostname"] = "lab-host"

    for elem in root.iter():
        if elem.tag in ("testsuite", "testsuites"):
            if "hostname" in elem.attrib:
                elem.attrib["hostname"] = "lab-host"
            if "package" in elem.attrib and home_dir in elem.attrib["package"]:
                elem.attrib["package"] = elem.attrib["package"].replace(home_dir, "~")

        if elem.tag == "testcase":
            total_tests += 1
            if "time" in elem.attrib:
                try:
                    total_duration += float(elem.attrib["time"])
                except ValueError:
                    pass

        if elem.tag in ("failure", "error"):
            if elem.tag == "failure":
                total_failures += 1
            else:
                total_errors += 1
            if "message" in elem.attrib:
                elem.attrib["message"] = sanitize_text(elem.attrib["message"], redaction_pairs, home_dir, hostname)

        if elem.tag == "skipped":
            total_skipped += 1

        if elem.tag in ("failure", "error", "system-out", "system-err"):
            if elem.text:
                elem.text = sanitize_text(elem.text, redaction_pairs, home_dir, hostname)

    # Serialize to string
    serialized_xml = ET.tostring(root, encoding="utf-8", xml_declaration=True).decode("utf-8")

    # Fail-closed check: verify no known secret string survives in the serialized XML
    for secret, label in known_secrets.items():
        if secret in serialized_xml:
            raise ValueError(f"SECURITY ALERT: Secret '{label}' detected in serialized XML! Failing closed.")

    # Write output
    output_xml_path.parent.mkdir(parents=True, exist_ok=True)
    output_xml_path.write_text(serialized_xml, encoding="utf-8")

    sha256 = hashlib.sha256(serialized_xml.encode("utf-8")).hexdigest()

    summary = {
        "total": total_tests,
        "passed": max(0, total_tests - total_failures - total_errors - total_skipped),
        "failed": total_failures + total_errors,
        "skipped": total_skipped,
        "duration_seconds": round(total_duration, 3)
    }

    return summary, sha256


def get_catalog_revisions() -> dict[str, str]:
    revisions = {}
    env_file = Path(__file__).resolve().parent.parent.parent / "clusters" / "blueprint-revisions.env"
    if env_file.is_file():
        for line in env_file.read_text().splitlines():
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                revisions[k.strip()] = v.strip().strip('"').strip("'")
    return revisions


def main():
    parser = argparse.ArgumentParser(description="Sanitize Bats JUnit XML and generate metadata.")
    parser.add_argument("--input", required=True, type=Path, help="Path to input report.xml")
    parser.add_argument("--output-dir", required=True, type=Path, help="Directory for sanitized report.xml and metadata.json")
    parser.add_argument("--run-id", required=True, help="Unique UTC run ID (YYYYMMDDTHHMMSSZ-xxxxxx)")
    parser.add_argument("--start-time", required=True, help="Start UTC time in ISO 8601")
    parser.add_argument("--end-time", required=True, help="End UTC time in ISO 8601")
    parser.add_argument("--exit-code", required=True, type=int, help="Bats exit code")
    parser.add_argument("--bats-version", default="1.14.0", help="Bats version string")
    parser.add_argument("--suite", default="smoke", help="Test suite name")
    parser.add_argument("--filter", default=None, help="Bats filter argument")
    parser.add_argument("--commit", required=True, help="gitops-control-plane commit SHA")
    parser.add_argument("--quarantine-dir", type=Path, default=Path.home() / ".config" / "gitops-lab" / "quarantine", help="Quarantine directory on failure")

    args = parser.parse_args()

    known_secrets = load_known_secrets()
    output_xml = args.output_dir / "report.xml"
    output_meta = args.output_dir / "metadata.json"

    try:
        summary, sha256 = sanitize_xml(args.input, output_xml, known_secrets)
    except Exception as e:
        sys.stderr.write(f"✘ Sanitization failure: {e}\n")
        # Quarantine raw report
        args.quarantine_dir.mkdir(parents=True, exist_ok=True)
        q_target = args.quarantine_dir / f"{args.run_id}-quarantine.xml"
        try:
            import shutil
            shutil.copy(args.input, q_target)
            sys.stderr.write(f"  Quarantined raw report to: {q_target}\n")
        except Exception:
            pass
        sys.exit(2)

    metadata = {
        "schema_version": "1.0.0",
        "run_id": args.run_id,
        "start_time_utc": args.start_time,
        "end_time_utc": args.end_time,
        "bats_version": args.bats_version,
        "suite": args.suite,
        "filter": args.filter if args.filter else None,
        "exit_code": args.exit_code,
        "summary": summary,
        "source": {
            "gitops_control_plane_commit": args.commit,
            "catalog_revisions": get_catalog_revisions()
        },
        "report_sha256": sha256
    }

    output_meta.write_text(json.dumps(metadata, indent=2), encoding="utf-8")
    print(f"✔ Sanitized report generated: {output_xml} (SHA-256: {sha256[:12]}...)")


if __name__ == "__main__":
    main()
