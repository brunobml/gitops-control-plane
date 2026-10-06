# Tenant IaC plan v0.3: P5 remediation & verification (implemented-07)

> **Status:** Remediation complete; all findings from [validated-08](2026-10-04-tenant-iac-team-clusters-plan-validated-08.md) resolved and verified live.  
> **Author:** Antigravity (Executor)  
> **Base commit:** `6ec74ae`  
> **Live lab state:** 42/42 Hub Applications Synced & Healthy, 12/12 Smoke Gates Passed.

---

## 1. Summary of Remediation

In review [validated-08](2026-10-04-tenant-iac-team-clusters-plan-validated-08.md), Codex identified 5 findings on the initial P5 delivery. All 5 findings have been diagnosed, addressed, and verified.

---

## 2. Findings Resolution

### Finding 1: Stage 9 Smoke Test Failure & Worker Probe Timeouts
- **Root Cause Diagnosed:** In `addons/probes/synthetic_order_probe.py`, when extending the probe loop for Kro clusters, `time.sleep(INTERVAL)` was accidentally indented inside the `except` block. Consequently, whenever `run_once()` succeeded, the loop executed again immediately with zero delay (a runaway busy loop). This hammered Moto SQS and DynamoDB non-stop, accumulating over 1,000 processed items in `orders-dev-history`. Because `orders-processor` uses Python's single-threaded `HTTPServer` where `GET /` triggers a full DynamoDB table scan and JSON sort, incoming `/healthz` probe requests from Kubelet (readiness timeout: 2s) queued up behind scans and timed out (`BrokenPipeError: [Errno 32] Broken pipe`). When Stage 9 sent its test marker, the saturated dashboard endpoint exceeded the 60s timeout.
- **Fix:** Fixed indentation in `addons/probes/synthetic_order_probe.py` so `time.sleep(INTERVAL)` executes after every cycle. Deleted accidental `synthetic-order-probe` deployment left in the `default` namespace. Deployed the updated probe ConfigMap across spokes.

### Finding 2: Hardened Smoke Assertion for Team Clusters
- **Diagnosis:** `scripts/smoke-test-hub-spoke.sh` previously queried `lab_team_cluster_ready == 0` with `2>/dev/null || true`. If metrics were missing or the query failed, it passed silently.
- **Fix:** Hardened Stage 12 of `scripts/smoke-test-hub-spoke.sh` to explicitly assert that both expected clusters (`analytics-dev` and `analytics-prod`) return `lab_team_cluster_ready == 1`, failing immediately if metrics are missing or if any cluster reports `== 0`.

### Finding 3: Dashboard Display of Cluster Readiness
- **Diagnosis:** The Grafana *Team clusters* panel displayed `State` from `lab_team_cluster_info` (which reflects cloud EKS status, e.g. `ACTIVE`). During a nodegroup failure, the state could still read `ACTIVE` while readiness was unready.
- **Fix:**
  1. Extended `synthetic_order_probe.py` to include `readiness="Ready"` or `readiness="NotReady"` as a label on `lab_team_cluster_info`.
  2. Updated `addons/observability/dashboards/platform-overview.json` (panel 9) to include `Readiness` in the table panel next to `State`.
  3. Updated the operations runbook to document both columns.

### Finding 4: Runbook Path and Rule Consistency
- **Diagnosis:** `docs/runbooks/tenant-iac-operations.md` contained path discrepancies (`teams/<team>/<name>-<env>.yaml` instead of `teams/<team>/clusters/<name>-<env>.yaml`), omitted Kubernetes `1.34` from allowed versions, and did not explain that GitHub ruleset `24519842` on single-contributor repositories enforces CI checks rather than self-review approvals.
- **Fix:** Corrected all file paths in `docs/runbooks/tenant-iac-operations.md` to `teams/<team>/clusters/<name>-<env>.yaml`, updated validation snippets, added `1.34`, and documented the GitHub ruleset behavior.

### Finding 5: Cloud Resource Inspection Tool & Rebuild Evidence
- **New Feature Delivered:** Authored `scripts/list-moto-resources.sh` and wired it into `Makefile` (`make moto-resources`). This tool inspects all cloud resources created across CARM accounts `111111111111`, `222222222222`, and verifies zero leaks in default account `123456789012`.
- **Validation:** Executed `make moto-resources` verifying active EKS clusters, nodegroups, VPCs, subnets, IGWs, SGs, SQS queues, and IAM roles across both accounts, with zero leaks in `123456789012`.

---

## 3. Verification Gates

1. `make test-alert-rules`: Passed (`SUCCESS: 21 rules found`).
2. `make ci`: Passed (33 scripts, 42 applications, 581 objects validated, 0 errors).
3. `make moto-resources`: Clean execution showing all nonprod and prod resources in Moto.
4. `bash scripts/smoke-test-hub-spoke.sh`: All 12 stages passed with zero errors.
