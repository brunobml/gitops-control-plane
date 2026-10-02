"""Phase 5 B.1: serve credential expiry timestamps to Prometheus.

Reads /expiry/<credential-name> files (the mounted ConfigMap monitoring/credential-expiry,
written by register-spokes.sh and addons/headlamp/setup-credentials.sh). Each file holds the
JWT `exp` of a token in epoch seconds; the tokens themselves are never seen here.
"""
import os
import time
from http.server import BaseHTTPRequestHandler, HTTPServer

EXPIRY_DIR = os.environ.get("EXPIRY_DIR", "/expiry")


def metrics() -> str:
    lines = [
        "# HELP lab_credential_expiry_timestamp_seconds Expiry (JWT exp) of a lab credential.",
        "# TYPE lab_credential_expiry_timestamp_seconds gauge",
    ]
    for name in sorted(os.listdir(EXPIRY_DIR)):
        path = os.path.join(EXPIRY_DIR, name)
        if name.startswith("..") or not os.path.isfile(path):
            continue  # ConfigMap volume internals
        try:
            value = int(open(path).read().strip())
        except ValueError:
            continue
        lines.append(f'lab_credential_expiry_timestamp_seconds{{credential="{name}"}} {value}')
    lines += [
        "# HELP lab_credential_expiry_exporter_scrape_timestamp_seconds Time of this scrape.",
        "# TYPE lab_credential_expiry_exporter_scrape_timestamp_seconds gauge",
        f"lab_credential_expiry_exporter_scrape_timestamp_seconds {int(time.time())}",
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
    HTTPServer(("0.0.0.0", 9101), Handler).serve_forever()
