"""2026-10-03 Track A.4 (owner decision O-3): the result of the latest CI run on main, as metrics.

Polls the public GitHub API (no token) for each lab repository and exposes, per workflow, the
conclusion of the most recent completed run on `main`. A red post-push alarm (O-1 mixed mode)
thereby also becomes a lab alert (CIFailingOnMain), next to GitHub's own notification.

Rate limit: unauthenticated calls allow 60 requests/hour per IP, shared with anything else on the
host. Requests are conditional (ETag); a 304 Not Modified does not count against the limit, so
the steady state costs nothing. Interval: CI_POLL_SECONDS (default 600).
"""
import calendar
import json
import os
import threading
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, HTTPServer

OWNER = os.environ.get("CI_OWNER", "brunobml")
REPOS = os.environ.get("CI_REPOS", "gitops-control-plane,platform-catalog,tenant-workloads,platform-charts,orders-processor").split(",")
INTERVAL = int(os.environ.get("CI_POLL_SECONDS", "600"))
FINAL = {"success", "failure", "timed_out", "startup_failure"}   # cancelled/skipped/neutral say nothing

state = {"runs": {}, "etag": {}, "poll_ok": 0, "poll_ts": 0, "rate_remaining": -1}
lock = threading.Lock()


def poll_repo(repo):
    url = f"https://api.github.com/repos/{OWNER}/{repo}/actions/runs?branch=main&status=completed&per_page=30"
    req = urllib.request.Request(url, headers={"Accept": "application/vnd.github+json", "User-Agent": "lab-ci-status-exporter"})
    if repo in state["etag"]:
        req.add_header("If-None-Match", state["etag"][repo])
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            state["rate_remaining"] = int(r.headers.get("X-RateLimit-Remaining", -1))
            body = json.load(r)
            etag = r.headers.get("ETag")
    except urllib.error.HTTPError as e:
        if e.code == 304:
            return True
        print(f"poll {repo}: HTTP {e.code}", flush=True)
        return False
    except (urllib.error.URLError, TimeoutError, ValueError) as e:
        print(f"poll {repo}: {e}", flush=True)
        return False
    latest = {}
    for run in body.get("workflow_runs", []):            # newest first
        if run.get("conclusion") in FINAL and run["name"] not in latest:
            latest[run["name"]] = run
    with lock:
        for wf, run in latest.items():
            state["runs"][(repo, wf)] = {
                "success": 1 if run["conclusion"] == "success" else 0,
                "ts": calendar.timegm(time.strptime(run["updated_at"], "%Y-%m-%dT%H:%M:%SZ")),
                "sha": run["head_sha"][:7],
            }
        if etag:
            state["etag"][repo] = etag
    return True


def poller():
    while True:
        ok = all([poll_repo(r) for r in REPOS])
        with lock:
            state["poll_ok"] = 1 if ok else 0
            state["poll_ts"] = int(time.time())
        time.sleep(INTERVAL)


def metrics():
    with lock:
        lines = [
            "# HELP lab_ci_run_success 1 if the latest completed CI run of the workflow on main succeeded.",
            "# TYPE lab_ci_run_success gauge",
        ]
        for (repo, wf), r in sorted(state["runs"].items()):
            lines.append(f'lab_ci_run_success{{repo="{repo}",workflow="{wf}",sha="{r["sha"]}"}} {r["success"]}')
        lines += ["# HELP lab_ci_run_timestamp_seconds When that run finished.", "# TYPE lab_ci_run_timestamp_seconds gauge"]
        for (repo, wf), r in sorted(state["runs"].items()):
            lines.append(f'lab_ci_run_timestamp_seconds{{repo="{repo}",workflow="{wf}"}} {r["ts"]}')
        lines += [
            "# HELP lab_ci_poll_success 1 if the last poll of every repository worked.",
            "# TYPE lab_ci_poll_success gauge", f"lab_ci_poll_success {state['poll_ok']}",
            "# HELP lab_ci_poll_timestamp_seconds Time of the last poll.",
            "# TYPE lab_ci_poll_timestamp_seconds gauge", f"lab_ci_poll_timestamp_seconds {state['poll_ts']}",
            "# HELP lab_ci_github_rate_limit_remaining Unauthenticated GitHub API calls left this hour (-1 unknown).",
            "# TYPE lab_ci_github_rate_limit_remaining gauge", f"lab_ci_github_rate_limit_remaining {state['rate_remaining']}",
        ]
    return "\n".join(lines) + "\n"


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path not in ("/metrics", "/healthz"):
            self.send_error(404)
            return
        body = (metrics() if self.path == "/metrics" else "ok\n").encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; version=0.0.4")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    threading.Thread(target=poller, daemon=True).start()
    HTTPServer(("0.0.0.0", 9102), Handler).serve_forever()
