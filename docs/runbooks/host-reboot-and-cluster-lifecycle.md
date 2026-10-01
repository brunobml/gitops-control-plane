# Runbook: Host Reboot and Lab Lifecycle Management

This runbook outlines operational procedures for managing the multi-cluster Hub-and-Spoke lab across host reboots, Docker daemon restarts, and system maintenance events.

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
All published ports (`8080`, `8443`, `8081`, `8082`, `5000`) must show `127.0.0.1:<port>`.

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
