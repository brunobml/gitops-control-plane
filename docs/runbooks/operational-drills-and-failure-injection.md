# Operational Playbook: Failure Injection & Disaster Recovery Drills
## Hub-and-Spoke GitOps Control Plane (2026-10-02)

* **Document Version:** 1.0
* **Target Audience:** Platform Engineers, SREs, and Operations Operators
* **Cluster Baseline:** Phase 5 v1.1 Complete (`k3d-hub-cluster`, `k3d-spoke-nonprod`, `k3d-spoke-prod`, `moto-cloud`)
* **Companion Runbook:** [`docs/runbooks/host-reboot-and-cluster-lifecycle.md`](host-reboot-and-cluster-lifecycle.md)

---

## 1. Executive Summary

This playbook defines guided, hands-on failure injection exercises designed to test platform resilience, validate alert thresholds, and practice recovery procedures. 

Across Phases 1–5, the platform implemented multi-layer self-healing and proactive observability. These drills allow engineers to safely induce realistic operational outages, observe telemetry across Prometheus and Loki, and execute validated single-command recovery procedures.

```
       Fault Injection                Detection Layer                   Recovery Layer
┌───────────────────────────┐   ┌──────────────────────────┐   ┌──────────────────────────────┐
│ • Stop Moto Cloud         │──►│ • Prometheus Alert Rules │──►│ • Idempotent Automation      │
│ • Expire Cluster Tokens   │   │ • Grafana Dashboards     │   │   (make post-bootstrap)      │
│ • Terminate Kyverno Pods  │   │ • Blackbox Probes        │   │ • Orphan Cleanup Script      │
│ • Delete Cloud Resources  │   │ • Loki Error Log Streams │   │ • Automatic Token Rotation   │
└───────────────────────────┘   └──────────────────────────┘   └──────────────────────────────┘
```

---

## 2. Pre-Drill Health Check

Before beginning any drill, verify that the lab is nominal and all 32 applications are healthy:

```bash
# 1. Run the comprehensive smoke test
make test

# 2. Verify all alert rules are inactive
kubectl --context k3d-hub-cluster exec -n monitoring deploy/prometheus-server \
  -c prometheus-server -- wget -qO- 'http://localhost:9090/api/v1/alerts' | jq .data.alerts

# 3. Open Grafana in your browser
# URL: http://grafana.localhost:8080 (Log in with platform-user via Keycloak)
# Navigate to: Dashboards -> GitOps Lab -> Platform overview & Logs and events
```

Expected baseline: 12/12 smoke stages pass, 0 active alerts, 32/32 applications `Synced / Healthy`.

---

## 3. Drill 1: Ephemeral Cloud Wipe & Worker Key Desynchronization (Failure Mode F-1)

### Scenario Context
Moto is in-memory by design. When Moto restarts (e.g. host reboot or container restart), all SQS queues and IAM credentials disappear. Workload pods continue running with stale credentials, causing silent message processing failures.

### Action: Induce Failure
Stop and restart the Moto cloud container:
```bash
docker restart moto-cloud
```

### Telemetry to Observe
1. **Blackbox Probe:** Within 30 seconds, `ProbeFailed{probe="moto"}` will fire or trigger warning.
2. **Synthetic Order Probe:** Within 5 minutes, `lab_order_e2e_success` drops to `0`.
3. **Alertmanager & Grafana:** Alert `OrdersNotProcessed` triggers in Prometheus and displays in the Grafana *Firing alerts* panel.
4. **Loki Logs:** In Grafana (*Logs & events*), query `{namespace=~"orders-.*"} |= "AccessDenied"` to observe credential authentication errors.

### Remediation & Recovery
Execute single-command platform reconciliation:
```bash
make post-bootstrap
```
*What happens under the hood:*
- `post-bootstrap.sh` detects that the running worker credentials fail authentication against Moto.
- Re-provisions IAM access keys in accounts `111111111111` and `222222222222`.
- Updates Kubernetes Secrets `<app>-<env>-aws`.
- Performs a rolling restart of worker pods (prod one pod at a time to satisfy PDB).
- ACK reconciles and recreates all missing SQS queues and DLQs.

### Validation
```bash
# Verify order processing is restored
make test
```
Verify `OrdersNotProcessed` transitions to inactive and all queues show 0s latency.

---

## 4. Drill 2: Spoke Token Expiration & Automated Rotation (Failure Mode PV2-5)

### Scenario Context
Argo CD spoke cluster secrets and Headlamp view tokens use 30-day bounded `TokenRequest` tokens. If left unrotated, Argo CD loses connectivity to spoke clusters (`ArgoClusterUnreachable`).

### Action: Induce Failure
Artificially backdate the recorded token expiry on `spoke-nonprod` to simulate an impending expiration:
```bash
# Update ConfigMap to simulate 2 days remaining
kubectl --context k3d-hub-cluster -n monitoring patch cm credential-expiry --type merge \
  -p "{\"data\":{\"argocd-spoke-nonprod\":\"$(( $(date +%s) + 172800 ))\"}}"
```

### Telemetry to Observe
1. **Exporter:** The credential-expiry exporter scrapes the ConfigMap and updates `lab_credential_expiry_timestamp_seconds`.
2. **Alert:** Prometheus triggers `SpokeTokenExpiringSoon{credential="argocd-spoke-nonprod"}` (fires when < 7 days remain).
3. **Smoke Test:** Running `make test` displays a warning at `[8/12] Asserting Credential Expiry`.

### Remediation & Recovery
Run the post-bootstrap self-healing automation:
```bash
make post-bootstrap
```
*What happens under the hood:*
- Step `[1/9]` of `post-bootstrap.sh` inspects `min_exp` across all credentials.
- Detects that `days_left < 7` (2 days left).
- Automatically invokes `register-spokes.sh` and `addons/headlamp/setup-credentials.sh`.
- Mints fresh 30-day tokens, updates Secrets, and verifies cluster connectivity.

### Validation
```bash
# Verify credential expiry is back to 29 days
kubectl --context k3d-hub-cluster exec -n monitoring deploy/prometheus-server \
  -c prometheus-server -- wget -qO- 'http://localhost:9090/api/v1/query?query=(lab_credential_expiry_timestamp_seconds+-+time())+/+86400' | jq .data.result
```
Verify all credentials report ~29 days and `SpokeTokenExpiringSoon` clears.

---

## 5. Drill 3: Kyverno Admission Resilience & Webhook Fail-Open Protection

### Scenario Context
Tenant namespaces enforce signed image verification via Kyverno. In Phase 5, Kyverno was upgraded to 2 replicas with a PDB (`minAvailable: 1`) to eliminate the single-point-of-failure window during rolling updates.

### Action: Phase A (Single-Replica Churn — Zero Disruption)
Gracefully terminate one Kyverno replica on `spoke-nonprod`:
```bash
POD=$(kubectl --context k3d-spoke-nonprod -n kyverno get pods -l app.kubernetes.io/component=admission-controller -o jsonpath='{.items[0].metadata.name}')
kubectl --context k3d-spoke-nonprod -n kyverno delete pod "$POD"
```
**Observation:**
- Attempt to deploy an unsigned pod immediately while pod terminates:
  ```bash
  kubectl --context k3d-spoke-nonprod -n orders-dev run test-unsigned --image=alpine:latest
  ```
- Result: **Denied immediately by the surviving replica**. Webhook configurations remain intact.

### Action: Phase B (Total Controller Failure)
Simulate total Kyverno controller outage:
```bash
# 1. Pause Argo CD auto-sync for Kyverno
argocd app set addon-kyverno-spoke-nonprod --auto-prune=false --self-heal=false

# 2. Scale Kyverno to 0
kubectl --context k3d-spoke-nonprod -n kyverno scale deploy/kyverno-admission-controller --replicas=0
```

### Telemetry to Observe
1. **Target Status:** Prometheus agent detects Kyverno metrics target down.
2. **Alert:** Within 2 minutes, Prometheus fires `KyvernoDown{cluster="spoke-nonprod"}` (severity: critical).
3. **Grafana:** Alert appears in *Platform overview* dashboard with direct runbook link.

### Remediation & Recovery
Restore Kyverno replicas and resume GitOps management:
```bash
# 1. Scale back to 2 replicas
kubectl --context k3d-spoke-nonprod -n kyverno scale deploy/kyverno-admission-controller --replicas=2

# 2. Re-enable Argo CD self-healing
argocd app set addon-kyverno-spoke-nonprod --auto-prune=true --self-heal=true
```

### Validation
Verify both replicas are ready and spread across distinct nodes:
```bash
kubectl --context k3d-spoke-nonprod -n kyverno get pods -o wide
```
Verify `KyvernoDown` alert clears in Prometheus.

---

## 6. Drill 4: Out-of-Band Cloud Drift on SQS Resources (Failure Mode L3-1)

### Scenario Context
ACK manages AWS SQS queues declaratively. If a cloud resource is deleted out-of-band directly in AWS, the local Kubernetes resource may remain `ResourceSynced=True` until the periodic resync period.

### Action: Induce Cloud Drift
Directly delete the Dead Letter Queue for `orders-dev` in Moto:
```bash
aws --endpoint-url=http://localhost:5000 --region us-east-1 sqs delete-queue \
  --queue-url http://localhost:5000/111111111111/orders-dev-dlq
```

### Observation
Check the ACK Queue resource status:
```bash
kubectl --context k3d-spoke-nonprod -n orders-dev get queue orders-dev-dlq -o jsonpath='{.status.conditions}'
```
Notice that ACK does not immediately detect the external deletion until the next reconciliation cycle.

### Remediation & Immediate Reconcile
Restart the ACK SQS controller pod to force immediate cloud reconciliation:
```bash
kubectl --context k3d-spoke-nonprod -n ack-system rollout restart deploy/ack-sqs-controller-sqs-chart
kubectl --context k3d-spoke-nonprod -n ack-system rollout status deploy/ack-sqs-controller-sqs-chart
```

### Validation
Check that Moto has recreated the queue:
```bash
aws --endpoint-url=http://localhost:5000 --region us-east-1 sqs list-queues
```
Verify `orders-dev-dlq` is restored and the main queue's redrive policy remains intact.

---

## 7. Drill 5: Tenant Deregistration & Data Hygiene (Failure Mode D-16 / O-3)

### Scenario Context
When a tenant deregisters an application in GitOps, Kubernetes namespaces, IAM worker credentials, and DynamoDB tables may be left orphaned. Per Owner Decision **O-3**, credentials and empty namespaces are automatically cleaned up, while database tables are reported unless `PRUNE_DATA=1` is provided.

### Action: Onboard and Deregister Temporary Tenant
1. Register a temporary demo application in `tenant-workloads`:
   ```bash
   cat <<'EOF' > /home/bleite/repos/tenant-workloads/tenants/tenant-a/apps/orders-demo.yaml
   name: orders-demo
   environment: dev
   cluster: spoke-nonprod
   namespace: orders-demo
   EOF
   git -C /home/bleite/repos/tenant-workloads add .
   git -C /home/bleite/repos/tenant-workloads commit -m "test: register orders-demo"
   git -C /home/bleite/repos/tenant-workloads push origin main
   ```
2. Provision credentials and workload:
   ```bash
   make post-bootstrap
   ```
3. Deregister the application by deleting the registration file:
   ```bash
   rm /home/bleite/repos/tenant-workloads/tenants/tenant-a/apps/orders-demo.yaml
   git -C /home/bleite/repos/tenant-workloads add .
   git -C /home/bleite/repos/tenant-workloads commit -m "test: deregister orders-demo"
   git -C /home/bleite/repos/tenant-workloads push origin main
   ```
4. Wait for Argo CD to prune the `orders-demo` Application.

### Action: Inspect Orphans (Dry-Run)
Run the orphan detection report:
```bash
make orphans
```
**Expected Output:**
- Slated for deletion: empty namespace `orders-demo` (+ Secret), IAM user `orders-demo-dev-worker`.
- Slated for report-only: DynamoDB table `orders-demo-dev-history` (kept to safeguard data).

### Action: Execute Cleanup
Run `make post-bootstrap` to clean up credentials and namespaces:
```bash
make post-bootstrap
```
Verify the IAM user and namespace are removed, but the table remains.

To purge the orphaned table when confident:
```bash
PRUNE_DATA=1 bash scripts/orphans.sh
```

---

## 8. Drill 6: Log Pipeline Interruption & Terminated Pod Post-Mortem

### Scenario Context
In Track F, Alloy was deployed to stream pod logs and events over the K8s API directly into Loki. This drill validates the primary operational requirement: inspecting logs from a pod that has already been deleted or crashed.

### Action: Provoke Failure and Teardown
Deploy a temporary pod that logs a distinctive diagnostic message and terminates:
```bash
kubectl --context k3d-spoke-nonprod -n orders-dev run post-mortem-drill \
  --image=alpine:latest --restart=Never \
  -- sh -c 'echo "CRITICAL-PANIC: Memory allocation fault at address 0xDEADBEEF"; exit 1'

# Wait 10 seconds for Alloy to ingest logs
sleep 10

# Delete the pod completely
kubectl --context k3d-spoke-nonprod -n orders-dev delete pod post-mortem-drill
```

### Verification & Query
Verify that `kubectl logs` fails because the pod no longer exists:
```bash
kubectl --context k3d-spoke-nonprod -n orders-dev logs post-mortem-drill
# Expected: Error from server (NotFound): pods "post-mortem-drill" not found
```

Query Loki directly via the Grafana UI or API:
```bash
kubectl --context k3d-hub-cluster exec -n monitoring deploy/prometheus-server -c prometheus-server -- \
  wget -qO- 'http://loki.monitoring.svc:3100/loki/api/v1/query_range?query=%7Bpod%3D%22post-mortem-drill%22%7D' | jq .data.result
```

**Result:**
The log line `CRITICAL-PANIC: Memory allocation fault at address 0xDEADBEEF` is retrieved from Loki with metadata `cluster=spoke-nonprod`, `namespace=orders-dev`, `pod=post-mortem-drill`.

---

## 9. Post-Drill Restoration & Clean Slate

After completing one or all drills, restore the lab to 100% nominal state:

```bash
# 1. Ensure any paused Argo CD applications are set back to self-heal
argocd app set --all --auto-prune=true --self-heal=true

# 2. Run post-bootstrap to synchronize credentials and workloads
make post-bootstrap

# 3. Assert full 12-stage smoke test pass
make test
```
