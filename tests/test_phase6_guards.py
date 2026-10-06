#!/usr/bin/env python3
"""Failure-path checks for the Phase 6 push and claim-discovery guards."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
REPOS = (
    "gitops-control-plane",
    "platform-catalog",
    "tenant-workloads",
    "orders-processor",
    "platform-charts",
    "tenant-iac",
)


class PushPreflightTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.script = self.root / "gitops-control-plane/scripts/push-all.sh"
        self.script.parent.mkdir(parents=True)
        shutil.copy2(ROOT / "scripts/push-all.sh", self.script)
        bin_dir = self.root / "bin"
        bin_dir.mkdir()
        stub = bin_dir / "git"
        stub.write_text(
            '#!/usr/bin/env bash\n'
            'if [[ "$*" == *rev-parse* ]]; then\n'
            '  if [[ "${FAIL_PREFLIGHT:-0}" == 1 && "$*" == *tenant-iac* ]]; then exit 1; fi\n'
            '  echo true; exit 0\n'
            'fi\n'
            'printf "%s\\n" "$*" >> "$PUSH_LOG"\n'
            'if [[ "${FAIL_PUSH:-0}" == 1 && "$*" == *tenant-iac* ]]; then exit 1; fi\n'
        )
        stub.chmod(0o755)
        self.log = self.root / "push.log"
        self.env = dict(
            os.environ,
            PATH=f'{bin_dir}:{os.environ["PATH"]}',
            PUSH_LOG=str(self.log),
        )

    def run_push(self):
        self.log.write_text("")
        result = subprocess.run(
            ["bash", str(self.script), "--dry-run"],
            env=self.env,
            capture_output=True,
            text=True,
            check=False,
        )
        return result, self.log.read_text().splitlines()

    def add_repos(self, names):
        for name in names:
            (self.root / name / ".git").mkdir(parents=True, exist_ok=True)

    def test_missing_last_repo_prevents_every_push(self):
        self.add_repos(REPOS[:-1])
        result, pushes = self.run_push()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(pushes, [])
        self.assertIn("no pushes attempted", result.stderr)

    def test_all_valid_repos_make_six_dry_run_attempts(self):
        self.add_repos(REPOS)
        result, pushes = self.run_push()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(pushes), 6)
        self.assertTrue(all("--dry-run" in push for push in pushes))

    def test_invalid_git_repository_prevents_every_push(self):
        self.add_repos(REPOS)
        self.env["FAIL_PREFLIGHT"] = "1"
        result, pushes = self.run_push()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(pushes, [])

    def test_one_push_failure_returns_nonzero_after_all_attempts(self):
        self.add_repos(REPOS)
        self.env["FAIL_PUSH"] = "1"
        result, pushes = self.run_push()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(len(pushes), 6)


class ClaimDiscoveryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        bin_dir = Path(self.temp.name)
        stub = bin_dir / "kubectl"
        stub.write_text(
            """#!/usr/bin/env python3
import json, os, sys
mode = os.environ.get('CLAIM_MODE', 'equal')
args = ' '.join(sys.argv[1:])
if 'spoke-nonprod' in args:
    if mode == 'spoke_error': sys.exit(9)
    if mode == 'bad_json': print('{'); sys.exit(0)
    items = [] if mode == 'zero' else [{'metadata': {'namespace': 'iac-team-data-dev', 'name': 'analytics-dev'}}]
elif 'spoke-prod' in args:
    items = [] if mode == 'zero' else [{'metadata': {'namespace': 'iac-team-data-prod', 'name': 'analytics-prod'}}]
else:
    if mode == 'app_error': sys.exit(8)
    count = 3 if mode == 'mismatch' else 2
    items = [{'spec': {'project': 'tenant-iac'}} for _ in range(count)]
print(json.dumps({'items': items}))
"""
        )
        stub.chmod(0o755)
        self.env = dict(os.environ, PATH=f'{bin_dir}:{os.environ["PATH"]}')

    def discover(self, mode):
        self.env["CLAIM_MODE"] = mode
        helper = ROOT / "scripts/lib/discover-iac-claims.sh"
        return subprocess.run(
            ["bash", "-c", f'source "{helper}"; discover_iac_claims || exit 1; printf "%s\\n" "${{IAC_CLAIM_TUPLES[@]}}"; echo "count=$IAC_APPS_COUNT"'],
            env=self.env,
            capture_output=True,
            text=True,
            check=False,
        )

    def test_equal_nonzero_counts_pass(self):
        result = self.discover("equal")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("spoke-nonprod|iac-team-data-dev|analytics-dev", result.stdout)
        self.assertIn("count=2", result.stdout)

    def test_nonzero_count_mismatch_fails(self):
        result = self.discover("mismatch")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("claim count (2)", result.stderr)
        self.assertIn("Applications (3)", result.stderr)

    def test_empty_discovery_and_query_errors_fail(self):
        for mode in ("zero", "spoke_error", "app_error", "bad_json"):
            with self.subTest(mode=mode):
                result = self.discover(mode)
                self.assertNotEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
