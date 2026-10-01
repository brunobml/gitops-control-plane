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
