# Runbook: Host Reboot and Lab Lifecycle Management

> **Status: Current.** Describes the lab as it is today (reviewed 2026-10-03).

This runbook outlines operational procedures for managing the multi-cluster Hub-and-Spoke lab across host reboots, Docker daemon restarts, and system maintenance events. To rebuild the whole lab from Git instead, see [`full-rebuild-and-acceptance.md`](full-rebuild-and-acceptance.md).

---

## 1. Quick Reference: Lifecycle Commands

| Action | Command | Description | Data & State Impact |
|---|---|---|---|
| **Start Lab** | `make start` | Resumes Moto and all 3 k3d clusters (`hub-cluster`, `spoke-nonprod`, `spoke-prod`), waiting for API responsiveness. | **Preserved:** All etcd state, CRDs, workloads, and Argo CD sync records intact. |
| **Stop Lab** | `make stop` | Gracefully pauses all 3 k3d clusters and the Moto container without deleting containers or volumes. | **Preserved:** Full lab state is retained on disk. Ready for host reboot. |
| **Inspect State** | `make status` | Checks Argo CD applications, spoke workloads, and Moto SQS queues. | Read-only. |
| **Run Smoke Tests**| `make test` | Executes the 8-stage comprehensive test suite across Hub, Spokes, and Moto Cloud. | Non-destructive verification. |
| **Rotate Tokens** | `make rotate-spoke-tokens` | Re-issues 30-day `TokenRequest` tokens for spoke clusters and Headlamp dashboard. | Refreshes Kubernetes authentication tokens. |
| **Full Teardown** | `make teardown` | Destroys all k3d clusters, Moto container, and Docker network. | ⚠️ **Destructive:** Completely deletes all cluster state and local data. |

---

## 2. Resuming the Lab After a Host Reboot

When the host machine reboots or Docker daemon restarts, k3d cluster containers and Moto may be in an `Exited` state.

### Step 1: Ensure Docker Daemon is Active
Verify that the Docker daemon started properly during boot:
```bash
sudo systemctl is-active docker
```
If inactive or failing:
```bash
sudo systemctl start docker
```

### Step 2: Resume Lab Clusters and Services
Run the automated resume command from the repository root:
```bash
make start
make post-bootstrap   # mandatory after every start (see Issue F)
```
*Equivalent manual commands:*
```bash
# 1. Resume central Moto AWS mock
docker start moto-cloud 2>/dev/null || docker run -d --name moto-cloud --network k3d-hub-spoke-net -p 127.0.0.1:5000:5000 motoserver/moto@sha256:91fd602a21f49cf9eb82fdf474015a3c131d40104c8297ea6a2ca920708ae32c

# 2. Resume all k3d clusters
k3d cluster start hub-cluster spoke-nonprod spoke-prod
```

### Step 3: Verify Cluster Status & Applications
Check that all clusters and applications report healthy:
```bash
make status
```
Inspect Argo CD applications on the Hub:
```bash
kubectl --context k3d-hub-cluster -n argocd get applications.argoproj.io
```
All 15 applications should report `Synced` and `Healthy` within 1–2 minutes after startup.

### Step 4: Run Smoke Tests
Confirm full end-to-end functionality (Ingress routing, Kro controllers, ACK SQS queues, worker processing, and credential validity):
```bash
make test
```

---

## 3. Graceful Shutdown Before Planned Maintenance

Before intentionally rebooting the host machine or shutting down your workstation, execute a graceful stop:
```bash
make stop
```
This safely stops the Kubernetes node containers and Moto mock cloud, preventing abrupt container termination or potential etcd lock corruption.

---

## 4. Troubleshooting Common Post-Reboot Issues

### Issue A: Docker Daemon Hangs or `docker ps` Freezes
**Symptoms:** `docker ps` hangs indefinitely or commands time out.
**Resolution:**
1. Inspect systemd service logs:
   ```bash
   journalctl -u docker -n 50 --no-pager
   ```
2. Check if a hanging `containerd` process is holding the socket:
   ```bash
   sudo systemctl restart containerd
   sudo systemctl restart docker
   ```
3. Verify socket responsiveness:
   ```bash
   docker info
   ```

### Issue B: Argo CD Reports `ComparisonError` (Spoke Cluster Unreachable)
**Symptoms:** Argo CD displays `rpc error: code = Unknown desc = Get "https://...": dial tcp ...: connect: connection refused`.
**Cause:** Spoke cluster API servers are still starting up or k3d node IP addresses changed.
**Resolution:**
1. Verify spoke clusters are running:
   ```bash
   kubectl --context k3d-spoke-nonprod cluster-info
   kubectl --context k3d-spoke-prod cluster-info
   ```
2. If the API servers are responsive but Argo CD cannot connect, refresh cluster connection secrets:
   ```bash
   make rotate-spoke-tokens
   ```

### Issue C: Workloads Show SQS Connection Errors
**Symptoms:** `orders-processor` pods log SQS connection failures or DynamoDB errors.
**Cause:** `moto-cloud` container was restarted and lost in-memory queue state.
**Resolution:**
1. Check Moto container status:
   ```bash
   curl -s http://127.0.0.1:5000/
   ```
2. If queues were flushed by Moto restart, the ACK SQS controllers will automatically recreate them during their resync interval (300 seconds), or trigger an immediate resync:
   ```bash
   kubectl --context k3d-spoke-nonprod annotate --overwrite queue.sqs.services.k8s.aws -A kro.run/resync="$(date +%s)"
   kubectl --context k3d-spoke-prod annotate --overwrite queue.sqs.services.k8s.aws -A kro.run/resync="$(date +%s)"
   ```

### Issue D: Localhost Port Bindings
Verify that host port forwards remain bound strictly to `127.0.0.1` (Security Standard A.1):
```bash
docker port k3d-hub-cluster-serverlb
docker port k3d-spoke-nonprod-serverlb
docker port k3d-spoke-prod-serverlb
docker port moto-cloud
```
All published ports (`80`, `443`, `8081`, `8082`, `5000`) must show `127.0.0.1:<port>`.

### Issue E: Spoke Agent Node `NotReady` with `not authorized` (cross-wired after IP reshuffle)
**Seen on 2026-10-01 after a host reboot** (`k3d-spoke-nonprod-agent-0`).

**Symptoms:**
* `kubectl --context k3d-spoke-nonprod get nodes` shows `agent-0` as `NotReady` ("Kubelet stopped posting node status").
* Pods on that node crash-loop on probes (e.g. the ACK controller). Its cloud resources are not recreated, while ACK still reports the stale `ResourceSynced=True`.
* `docker logs k3d-spoke-nonprod-agent-0` repeats: `failed to retrieve configuration from server: not authorized`.

**Cause:** the k3s agent caches server **IP addresses** in `/var/lib/rancher/k3s/agent/etc/k3s-agent-load-balancer.json`. After a Docker restart, containers on `k3d-cloud-net` get new IPs, so a cached address can now belong to **another cluster's** server (on 2026-10-01 nonprod's cache pointed at `spoke-prod`'s server), which correctly rejects the agent's token.

**Diagnose:**
```bash
docker network inspect k3d-cloud-net --format '{{range .Containers}}{{.Name}} {{.IPv4Address}}{{"\n"}}{{end}}'
docker exec k3d-spoke-nonprod-agent-0 cat /var/lib/rancher/k3s/agent/etc/k3s-agent-load-balancer.json
# ServerAddresses must contain only this cluster's server-0 IP.
```

**Fix** (affects only that agent node; k3s regenerates the file by resolving K3S_URL by name):
```bash
docker exec k3d-spoke-nonprod-agent-0 rm /var/lib/rancher/k3s/agent/etc/k3s-agent-load-balancer.json
docker restart k3d-spoke-nonprod-agent-0
kubectl --context k3d-spoke-nonprod get nodes   # Ready within seconds
```
Use the same procedure for `k3d-spoke-prod-agent-0` if it shows the symptom. With the 300 s ACK resync, missing queues are recreated automatically once the controller is healthy (observed: within seconds of the node recovering).

### Issue F: Orders Accepted but Never Processed (worker keys lost after moto restart)
**Seen on 2026-10-01 after a host reboot** (all three environments; caught by smoke stage 9).

**Symptoms:** the dashboards accept orders but none appear as processed; `make test` fails at `[9/9] Asserting End-to-End Order Flow`. Worker logs show auth errors or reads from an empty queue.

**Cause:** moto keeps all state in memory. A moto restart (host reboot, Docker restart) wipes the IAM users that `scripts/provision-worker-credentials.sh` created, so the keys in the `orders-<env>-aws` Secrets no longer resolve to the namespace's CARM account (111111111111 / 222222222222). Queues are recreated by ACK within its 300 s resync (Issue C), but the keys are not.

**Fix** (idempotent; keeps valid keys, re-provisions only stale ones, restarts workers one pod at a time, runs the smoke test):
```bash
make post-bootstrap
```
Run it after every `make start`.

### Issue H: Hub URLs or HTTPS (ports 80/443, Track I)
**Symptoms:** `make setup` stops with "Host port 80/443 is already published by: …"; or `https://<host>.localhost` shows a certificate warning.
* **Port in use:** another container holds 80/443, typically the `argolab` cluster of the `jenkins-argo` lab (owner decision O-8). Stop it (`k3d cluster stop argolab`), or start that lab on other ports with its `HTTP_PORT`/`HTTPS_PORT` overrides. Both labs cannot use 80/443 at the same time.
* **Certificate warning:** the lab uses a self-signed fallback until mkcert is set up. On Windows: `winget install FiloSottile.mkcert`, then `mkcert -install`. Then run `make local-tls`. HTTPS only redirects to the HTTP URL; SSO stays on HTTP.
* **Do not** remove ports with `k3d cluster edit … --port-delete` on the hub. When two mappings share a container port, k3d drops that port from the load balancer completely (I.0 spike). Recovery: `docker start k3d-hub-cluster-serverlb`, then `k3d cluster edit hub-cluster --port-add <free host port>:80@loadbalancer` (and the same for 443) to restore the proxy entries.

### Issue G: Single Sign-On Unavailable (Keycloak down or misconfigured)
CLI logins (SSO and break-glass) and temporary SSO users: [`argocd-cli.md`](argocd-cli.md).
**Symptoms:** "Log in via Keycloak" in Argo CD fails or loops; Headlamp redirects to a Keycloak error page; smoke stage 10 fails.

**Break-glass (always available):** log in to Argo CD with the **local `platform-admin`** account (`make password`). It does not depend on Keycloak. Automation (`post-bootstrap.sh`, `register-spokes.sh`) only ever uses this local account. Headlamp has no local fallback; use `kubectl` until SSO is back.

**Diagnose:**
```bash
kubectl --context k3d-hub-cluster -n keycloak get pods
curl -s http://keycloak.localhost/realms/lab/.well-known/openid-configuration | jq -r .issuer
kubectl --context k3d-hub-cluster -n kube-system get cm coredns-custom -o yaml   # keycloak.localhost rewrite
kubectl --context k3d-hub-cluster -n oauth2-proxy logs deploy/oauth2-proxy --tail=20
```

**Fix:**
* Keycloak keeps no state: deleting its pod re-imports realm `lab` from Git (`addons/keycloak/realm-lab.json`), with passwords from the `keycloak-realm-secrets` Secret. Only active sessions are lost.
* If the in-cluster issuer check fails (smoke stage 10 "argocd-server" side), run `make post-bootstrap`. It restarts CoreDNS when `coredns-custom` changed (CoreDNS does not reload imported files).
* Lost or rotated SSO passwords: delete the file in `~/.config/gitops-lab/`, run `bash scripts/setup-keycloak-secrets.sh`, then restart Keycloak (`kubectl -n keycloak rollout restart deploy/keycloak`) and oauth2-proxy if its secret changed.

---

## Alerts (Phase 5)
Alerts are shown in **Grafana** (`http://grafana.localhost`, Keycloak SSO; dashboard *GitOps Lab → Platform overview*, Alertmanager data source). They stay lab-local (owner decision O-1). Each alert's `runbook` annotation points to a section below.

### Alert: ArgoAppDegraded / ArgoAppOutOfSync
An Application is not Healthy for 10 min, or not Synced for 30 min (`argo-cd` itself is excluded: it is manual-sync by design).
1. Open the app in Argo CD and read the failing resource and its message.
2. Retry exhaustion after a cold start or reboot: `make post-bootstrap` (step 8 re-syncs stragglers). Do not use `--force` (Phase 3 D-31).
3. Tenant app Degraded with `FailedCreate` events in its ReplicaSet: check image verification (unsigned image, see Issue/Alert *KyvernoDown*).

### Alert: ArgoClusterUnreachable
Argo CD cannot reach a spoke (`argocd_cluster_connection_status != 1`).
1. Docker or host restart: see **Issue A/B**; agent cross-wired after an IP reshuffle: **Issue E**.
2. Expired token: `make post-bootstrap` renews tokens automatically when < 7 days are left; force it with `make rotate-spoke-tokens`.

### Alert: ApplicationSetNotUpToDate
An ApplicationSet cannot render (`argocd_appset_info{resource_update_status!="ApplicationSetUpToDate"}`): a registration file with a missing or wrong field, a template error, or two ApplicationSets claiming the same Application. Its Applications **keep running but are no longer updated**. Since Track B.2 this affects only the tenant whose ApplicationSet (`tenant-workloads-<tenant>`) fails.
1. See the reason: `kubectl -n argocd get applicationset <name> -o jsonpath='{.status.conditions}'`, or the ApplicationSet's events in Argo CD.
2. Tenant registrations: the CI check `registration-checks` names the bad file (`make ci-tenants` locally). Fix or revert it through a pull request.
3. *"already owned by another ApplicationSet"*: two ApplicationSets generate the same Application name (`<app>-<env>` must be unique across tenants).

### Alert: SpokeTokenExpiringSoon
A spoke or Headlamp token expires within 7 days (`lab_credential_expiry_timestamp_seconds`).
Run `make post-bootstrap` (renews automatically) or `make rotate-spoke-tokens`. For `credential="local-tls"` (the https://*.localhost certificate, Track I.4): `make local-tls` issues a new one. *CredentialExpiryUnknown* means the exporter or the `monitoring/credential-expiry` ConfigMap is missing: `make rotate-spoke-tokens` rewrites it.

### Alert: SpokeAgentDown / SpokeControllerDown
No metrics from a spoke's Prometheus agent, or kro / ACK is not running there.
1. `kubectl --context k3d-<spoke> -n monitoring get pods` / `-n kro` / `-n ack-system get pods`.
2. Node NotReady after a reboot: **Issue E**. Agent cannot write to the hub: check `monitoring/remote-write-credentials` on the spoke (`bash scripts/setup-observability-secrets.sh` re-creates it).

### Alert: KyvernoDown
Kyverno is not running on a spoke. A graceful stop removes its webhooks, so **tenant images are not verified** until it is back (Phase 4 D-10; two replicas + PDB make this rare, Phase 5 C.1).
1. `kubectl --context k3d-<spoke> -n kyverno get pods,deploy`; Argo CD app `addon-kyverno-<spoke>` self-heals the Deployment.
2. *KyvernoSlowAdmission*: p95 admission > 15 s (timeout is 30 s); usually GHCR/Sigstore reachability.

### Alert: ProbeFailed
A synthetic HTTP probe fails (Argo CD UI, Grafana UI, Keycloak OIDC discovery, moto, or **Headlamp no longer requiring SSO**). Check the named component; for `headlamp-sso` see Issue G and the Traefik middleware `headlamp/oauth2-forward-auth`.

### Alert: OrdersNotProcessed
The synthetic order probe on a spoke could not get a marker message processed for 10 min (`lab_order_e2e_success == 0`). This is the Phase 3 F-1 failure (worker keys lost after a moto restart) or a broken worker.
1. `make post-bootstrap` (re-provisions worker keys, restarts stale workers) — **Issue F**.
2. Probe logs: `kubectl --context k3d-<spoke> -n platform-probes logs deploy/synthetic-order-probe`.
*SyntheticProbeStale*: the probe itself stopped running; check that Deployment.

### Alert: SyntheticProbeDown
The synthetic order probe exporter is not running on a spoke cluster (`up{job="synthetic-order-probe"} == 0` or missing). Both end-to-end order processing verification and team cluster readiness telemetry (`lab_team_cluster_ready`) are interrupted.
1. Check probe pod status: `kubectl --context k3d-<spoke> -n platform-probes get pods -l app.kubernetes.io/name=synthetic-order-probe`.
2. Inspect probe logs: `kubectl --context k3d-<spoke> -n platform-probes logs deploy/synthetic-order-probe`.
3. Reconcile deployment via Argo CD: `argocd app sync addon-observability-<spoke>`.


### Alert: LokiDown / LogShipperDown / LogsMissing
Logs are not being collected or stored (Phase 5 Track F). Metrics and alerts keep working; only Grafana's log panels are affected.
1. `LokiDown`: `kubectl --context k3d-hub-cluster -n monitoring get pods loki-0`; its volume: `get pvc storage-loki-0` (7-day retention, 5 GiB).
2. `LogShipperDown`: Alloy pod on that cluster: `kubectl --context k3d-<cluster> -n monitoring get pods -l app.kubernetes.io/name=alloy`; Argo CD app `addon-alloy` (hub) / `addon-logging-<spoke>`.
3. `LogsMissing` / `LokiIngestionErrors`: Alloy runs but cannot push: `kubectl -n monitoring logs deploy/alloy -c alloy`; a spoke needs `monitoring/remote-write-credentials` (`bash scripts/setup-observability-secrets.sh` re-creates it) and the hub ingress `monitoring/loki-push`.

### Alert: ContainerOOMKilled
A container restarted because it exceeded its memory limit (Kubernetes emits no event for this; the reason comes from kube-state-metrics). Example: Grafana at 384 Mi on 2026-10-02.
1. Grafana → *Logs & events* (the alert's `logs` link): the container's last lines before the kill, and the *Containers OOM-killed* table.
2. Raise the limit in the component's values (Git) if the usage is legitimate; otherwise investigate the leak.

### Alert: CIFailingOnMain / CIStatusUnknown
*CIFailingOnMain*: the latest CI run of a workflow on `main` of a lab repository failed (2026-10-03 Track A). On `gitops-control-plane`, `platform-catalog` and `orders-processor`, CI is a post-push alarm (O-1), so the change is already on `main`. For the catalog, nonprod already follows it.
1. Open the `link` annotation. The failure reasons are shown as annotations on the run.
2. Reproduce locally: `make ci`, `make ci-catalog`, `make ci-tenants` or `make ci-charts` from `gitops-control-plane` (see `ci/README.md`).
3. Fix forward with a new commit, or revert. Do not promote a catalog revision to prod while its CI is red.

*CIStatusUnknown*: the ci-status exporter (`monitoring/ci-status-exporter`) could not read the GitHub API for 30 min. Causes: no internet from the hub; GitHub's unauthenticated limit of 60 calls/hour, shared with everything on the host (see `lab_ci_github_rate_limit_remaining`); or the exporter is down.

### Alert: TeamClusterNotReady
A self-service team EKS cluster is not ready (`lab_team_cluster_ready == 0`) on a spoke for 5 min.
1. Check the cluster status on the spoke: `kubectl --context k3d-<spoke> -n iac-<team>-<env> get teamekscluster,cluster.eks,nodegroup.eks,role.iam`.
2. Check ACK EKS/IAM controller logs in `ack-system`: `kubectl --context k3d-<spoke> -n ack-system logs -l app.kubernetes.io/name=eks-controller`.
3. For full procedures, see [Tenant IaC Operations Runbook](tenant-iac-operations.md#alert-teamclusternotready).
