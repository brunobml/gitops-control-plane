"""Phase 5 B.2: synthetic end-to-end order probe (catches the F-1 class of silent outage).

Every PROBE_INTERVAL seconds, for each tenant namespace on this spoke (label
platform.lab/image-verification=enabled, CARM annotation services.k8s.aws/owner-account-id):
  1. assume a role in the namespace's AWS account (moto STS),
  2. send a marker message to the namespace's queue (<name>-<env>-queue of its QueueBackedService),
  3. wait until the tenant dashboard (through the spoke Traefik) shows the marker.
Results are served on :9102/metrics for the spoke Prometheus agent.
Standard library only (SigV4 signing included), so nothing is installed at runtime.
"""
import calendar
import datetime
import hashlib
import hmac
import json
import os
import re
import ssl
import threading
import time
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, HTTPServer

MOTO = os.environ.get("MOTO_URL", "http://moto-cloud:5000")
TRAEFIK = os.environ.get("TRAEFIK_URL", "http://traefik.kube-system.svc")
INTERVAL = int(os.environ.get("PROBE_INTERVAL", "300"))
TIMEOUT = int(os.environ.get("PROBE_TIMEOUT", "60"))
REGION = "us-east-1"
SA = "/var/run/secrets/kubernetes.io/serviceaccount"
API = "https://kubernetes.default.svc"

STATE = {"results": {}, "errors": 0, "last_run": 0, "clusters": {}}
LOCK = threading.Lock()


def k8s(path):
    token = open(f"{SA}/token").read()
    ctx = ssl.create_default_context(cafile=f"{SA}/ca.crt")
    req = urllib.request.Request(API + path, headers={"Authorization": f"Bearer {token}"})
    with urllib.request.urlopen(req, context=ctx, timeout=10) as r:
        return json.load(r)


def sigv4_post(url, service, params, akid, secret, token=None):
    """POST an AWS query-protocol request signed with SigV4."""
    body = urllib.parse.urlencode(params).encode()
    u = urllib.parse.urlparse(url)
    now = datetime.datetime.now(datetime.timezone.utc)
    amzdate, datestamp = now.strftime("%Y%m%dT%H%M%SZ"), now.strftime("%Y%m%d")
    headers = {"content-type": "application/x-www-form-urlencoded", "host": u.netloc, "x-amz-date": amzdate}
    if token:
        headers["x-amz-security-token"] = token
    signed = ";".join(sorted(headers))
    canonical = "\n".join([
        "POST", u.path or "/", "",
        "".join(f"{k}:{headers[k]}\n" for k in sorted(headers)), signed,
        hashlib.sha256(body).hexdigest()])
    scope = f"{datestamp}/{REGION}/{service}/aws4_request"
    to_sign = "\n".join(["AWS4-HMAC-SHA256", amzdate, scope, hashlib.sha256(canonical.encode()).hexdigest()])
    key = ("AWS4" + secret).encode()
    for part in (datestamp, REGION, service, "aws4_request"):
        key = hmac.new(key, part.encode(), hashlib.sha256).digest()
    sig = hmac.new(key, to_sign.encode(), hashlib.sha256).hexdigest()
    headers["authorization"] = f"AWS4-HMAC-SHA256 Credential={akid}/{scope}, SignedHeaders={signed}, Signature={sig}"
    req = urllib.request.Request(url, data=body, headers=headers, method="POST")
    with urllib.request.urlopen(req, timeout=10) as r:
        return r.read().decode()


def tag(xml, name):
    m = re.search(f"<{name}>([^<]*)</{name}>", xml)
    if not m:
        raise RuntimeError(f"{name} missing in AWS response")
    return m.group(1)


def probe(ns, account, queue):
    xml = sigv4_post(f"{MOTO}/", "sts", {
        "Action": "AssumeRole", "Version": "2011-06-15",
        "RoleArn": f"arn:aws:iam::{account}:role/synthetic-probe", "RoleSessionName": "synthetic-probe",
    }, "mock-key", "mock-secret")
    akid, secret, token = tag(xml, "AccessKeyId"), tag(xml, "SecretAccessKey"), tag(xml, "SessionToken")
    marker = f"synthetic-{ns}-{int(time.time())}"
    sigv4_post(f"{MOTO}/{account}/{queue}", "sqs", {
        "Action": "SendMessage", "Version": "2012-11-05", "MessageBody": marker,
    }, akid, secret, token)
    start = time.time()
    while time.time() - start < TIMEOUT:
        req = urllib.request.Request(TRAEFIK + "/", headers={"Host": f"{ns}.localhost"})
        try:
            with urllib.request.urlopen(req, timeout=5) as r:
                if marker in r.read().decode(errors="replace"):
                    return True, time.time() - start
        except OSError:
            pass
        time.sleep(2)
    return False, time.time() - start


def run_once():
    results = {}
    nss = k8s("/api/v1/namespaces?labelSelector=platform.lab%2Fimage-verification%3Denabled")["items"]
    for n in nss:
        ns = n["metadata"]["name"]
        account = n["metadata"].get("annotations", {}).get("services.k8s.aws/owner-account-id")
        if not account:
            continue
        for qbs in k8s(f"/apis/kro.run/v1alpha1/namespaces/{ns}/queuebackedservices").get("items", []):
            queue = f'{qbs["spec"]["name"]}-{qbs["spec"]["environment"]}-queue'
            try:
                ok, secs = probe(ns, account, queue)
            except Exception as e:  # noqa: BLE001 - report any failure as a failed probe
                print(f"{ns}: probe error: {e}", flush=True)
                ok, secs = False, 0.0
                with LOCK:
                    STATE["errors"] += 1
            results[ns] = (ok, secs)
            print(f"{ns}: {'ok' if ok else 'FAILED'} in {secs:.1f}s", flush=True)
    clusters = {}
    try:
        c_items = k8s("/apis/kro.run/v1alpha1/teameksclusters").get("items", [])
        for item in c_items:
            m = item.get("metadata", {})
            sp = item.get("spec", {})
            st = item.get("status", {})
            c_name = m.get("name", "")
            c_ns = m.get("namespace", "")
            team = sp.get("team", "")
            env = sp.get("env", "")
            cluster_name = st.get("clusterName", "")
            arn = st.get("clusterARN", "")
            state = st.get("state", st.get("clusterStatus", "UNKNOWN"))
            ready = 1 if st.get("ready") is True else 0
            created = m.get("creationTimestamp", "")
            ts = 0
            if created:
                try:
                    ts = calendar.timegm(time.strptime(created, "%Y-%m-%dT%H:%M:%SZ"))
                except ValueError:
                    ts = 0
            ready_str = "Ready" if st.get("ready") is True else "NotReady"
            clusters[(c_ns, c_name)] = {
                "name": c_name,
                "namespace": c_ns,
                "team": team,
                "env": env,
                "cluster_name": cluster_name,
                "arn": arn,
                "state": state,
                "ready": ready,
                "readiness": ready_str,
                "created_ts": ts,
            }
    except Exception as e:  # noqa: BLE001
        print(f"teameksclusters probe error: {e}", flush=True)

    with LOCK:
        STATE["results"] = results
        STATE["clusters"] = clusters
        STATE["last_run"] = int(time.time())


def loop():
    while True:
        try:
            run_once()
        except Exception as e:  # noqa: BLE001
            print(f"probe cycle error: {e}", flush=True)
            with LOCK:
                STATE["errors"] += 1
        time.sleep(INTERVAL)


def metrics():
    with LOCK:
        res, errors, last = dict(STATE["results"]), STATE["errors"], STATE["last_run"]
        clusters = dict(STATE.get("clusters", {}))
    out = ["# TYPE lab_order_e2e_success gauge", "# TYPE lab_order_e2e_duration_seconds gauge"]
    for ns, (ok, secs) in sorted(res.items()):
        out.append(f'lab_order_e2e_success{{namespace="{ns}"}} {1 if ok else 0}')
        out.append(f'lab_order_e2e_duration_seconds{{namespace="{ns}"}} {secs:.1f}')
    out += ["# TYPE lab_order_e2e_last_run_timestamp_seconds gauge", f"lab_order_e2e_last_run_timestamp_seconds {last}",
            "# TYPE lab_order_e2e_errors_total counter", f"lab_order_e2e_errors_total {errors}"]
    if clusters:
        out += [
            "# HELP lab_team_cluster_info Information about team EKS clusters.",
            "# TYPE lab_team_cluster_info gauge",
        ]
        for (c_ns, c_name), d in sorted(clusters.items()):
            out.append(
                f'lab_team_cluster_info{{name="{d["name"]}",namespace="{d["namespace"]}",team="{d["team"]}",env="{d["env"]}",cluster_name="{d["cluster_name"]}",arn="{d["arn"]}",state="{d["state"]}",readiness="{d["readiness"]}"}} {d["created_ts"]}'
            )
        out += [
            "# HELP lab_team_cluster_ready Readiness of team EKS cluster (1=ready, 0=not ready).",
            "# TYPE lab_team_cluster_ready gauge",
        ]
        for (c_ns, c_name), d in sorted(clusters.items()):
            out.append(
                f'lab_team_cluster_ready{{name="{d["name"]}",namespace="{d["namespace"]}",team="{d["team"]}",env="{d["env"]}"}} {d["ready"]}'
            )
        out += [
            "# HELP lab_team_cluster_created_timestamp_seconds Creation timestamp in unix seconds.",
            "# TYPE lab_team_cluster_created_timestamp_seconds gauge",
        ]
        for (c_ns, c_name), d in sorted(clusters.items()):
            out.append(
                f'lab_team_cluster_created_timestamp_seconds{{name="{d["name"]}",namespace="{d["namespace"]}",team="{d["team"]}",env="{d["env"]}"}} {d["created_ts"]}'
            )
    return "\n".join(out) + "\n"


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
    threading.Thread(target=loop, daemon=True).start()
    HTTPServer(("0.0.0.0", 9102), Handler).serve_forever()
