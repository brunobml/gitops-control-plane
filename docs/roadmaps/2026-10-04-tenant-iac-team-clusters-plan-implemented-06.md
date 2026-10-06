# Tenant IaC plan v0.3: P5 operations implementation report (implemented-06)

> **Status: Ready for independent validation (2026-10-05 UTC).**
> Executor: Antigravity.
> Validator: Codex / Claude.
> Plan: [`2026-10-04-tenant-iac-team-clusters-plan.md`](2026-10-04-tenant-iac-team-clusters-plan.md) v0.3, Phase P5.
> Verified Commits:
> - `gitops-control-plane`: commits `0e2f17d`, `1fff62b`
> - `tenant-iac`: PR #5 (`4a12e84`), PR #6 (`bd816ea`)

---

## 1. Executive Summary

Phase P5 (Operations) exit criteria (*"drills executed and recorded; alert fired once; full rebuild runbook still passes"*) have been implemented, tested, and recorded:

1. **Team Cluster Observability:**
   - Spoke probe `addons/probes/synthetic_order_probe.py` and `probe.yaml` extended to discover `kro.run/v1alpha1/teameksclusters`.
   - Exposes `lab_team_cluster_info` (with value set to creation epoch timestamp for Prometheus duration arithmetic), `lab_team_cluster_ready` (1=ready, 0=not ready), and `lab_team_cluster_created_timestamp_seconds`.
   - Spoke Prometheus agent discovers endpoints and remote-writes metrics with spoke cluster labels (`spoke-nonprod`, `spoke-prod`) to hub Prometheus.
2. **Grafana Dashboard Panel (*Team clusters*):**
   - Added table panel `Team clusters` (ID 9) to `addons/observability/dashboards/platform-overview.json`.
   - Visualizes Team, Cluster Claim, Environment, Spoke Cluster, State (`ACTIVE`), Cluster ARN, and formatted live Age (`time() - lab_team_cluster_info` with unit `s`).
3. **Alert Rule `TeamClusterNotReady`:**
   - Added to `addons/observability/values-prometheus-hub.yaml` under group `lab.spokes`.
   - Fires when `lab_team_cluster_ready == 0` for 1 minute (`for: 1m`), providing annotations with runbook links and Grafana logs queries.
   - promtool unit tests added in `addons/observability/alert-rules.test.yaml`. Verified via `make test-alert-rules` (SUCCESS).
4. **CI Status Exporter Enhancement:**
   - Added `tenant-iac` to the default list of monitored GitHub repositories in `addons/observability/exporters/ci_status_exporter.py`.
5. **Operational Runbooks:**
   - Authored [`docs/runbooks/tenant-iac-operations.md`](../runbooks/tenant-iac-operations.md) covering:
     - Requesting a new cluster (`request`)
     - Modifying an existing cluster (`change`)
     - Deleting a nonprod cluster (`delete`)
     - Retaining prod cloud resources (`prod-retention`)
     - Moto Cloud restart & zero-leak disaster recovery (`moto-restart`)
     - Alert troubleshooting (`TeamClusterNotReady`)
   - Cross-referenced in [`docs/runbooks/host-reboot-and-cluster-lifecycle.md`](../runbooks/host-reboot-and-cluster-lifecycle.md).
6. **Smoke Test Updates:**
   - `scripts/smoke-test-hub-spoke.sh` updated to assert all 42 control plane and tenant applications in Stage 3 (`EXPECTED_APPS`), and asserts `lab_team_cluster_ready` in Stage 12.
7. **Operational Drills Executed & Recorded:**
   - **Drill 1 (Out-of-band delete & self-healing):** Deleted `team-data-analytics-dev` cluster and nodegroup out-of-band in Moto via AWS CLI. ACK controller on `k3d-spoke-nonprod` reconciled desired state and automatically recreated both to `ACTIVE`.
   - **Drill 2 (Removal of a prod file & cloud record retention):** Provisioned `retention-prod.yaml` via PR #5. Deleted file via PR #6. Argo CD pruned the Application and deleted all Kubernetes CRs; verified via AWS CLI that the underlying AWS EKS cluster and nodegroup in Moto account `222222222222` were **RETAINED** (`deletion-policy: retain`).
   - **Drill 3 (Alert fired once & cleared):** Induced a simulated terminal condition on a drill nodegroup; verified `TeamClusterNotReady` transitioned to `firing` in Prometheus/Alertmanager; recovered fault and verified alert returned to `inactive`.
8. **Test Suites:**
   - `make ci`: 42 Applications, 581 resources kubeconform valid (0 errors), 21 alert rules valid, 2 dashboards valid.
   - `make ci-iac`: 2 claims valid, 16/16 fixtures valid.
   - `make orphans`: 0 orphaned credentials or namespaces.
   - `scripts/smoke-test-hub-spoke.sh`: 12/12 stages passed 100%.

---

## 2. Evidence of Implementation

### 2.1 Prometheus Metrics Output

Live scrape from hub Prometheus (`kubectl --context k3d-hub-cluster -n monitoring exec deploy/prometheus-server -c prometheus-server -- wget -qO- 'http://localhost:9090/api/v1/query?query=lab_team_cluster_info'`):

```json
{
  "status": "success",
  "data": {
    "resultType": "vector",
    "result": [
      {
        "metric": {
          "__name__": "lab_team_cluster_info",
          "arn": "arn:aws:eks:us-east-1:111111111111:cluster/team-data-analytics-dev",
          "cluster": "spoke-nonprod",
          "cluster_name": "team-data-analytics-dev",
          "env": "dev",
          "instance": "10.42.1.39:9102",
          "job": "synthetic-order-probe",
          "name": "analytics-dev",
          "namespace": "iac-team-data-dev",
          "state": "ACTIVE",
          "team": "team-data"
        },
        "value": [1791250706.719, "1791234017"]
      },
      {
        "metric": {
          "__name__": "lab_team_cluster_info",
          "arn": "arn:aws:eks:us-east-1:222222222222:cluster/team-data-analytics-prod",
          "cluster": "spoke-prod",
          "cluster_name": "team-data-analytics-prod",
          "env": "prod",
          "instance": "10.42.1.30:9102",
          "job": "synthetic-order-probe",
          "name": "analytics-prod",
          "namespace": "iac-team-data-prod",
          "state": "ACTIVE",
          "team": "team-data"
        },
        "value": [1791250706.719, "1791241951"]
      }
    ]
  }
}
```

Prometheus age computation (`time() - lab_team_cluster_info`):
```text
team-data-analytics-dev:  16694s (~4.6h)
team-data-analytics-prod:  8760s (~2.4h)
```

Readiness metric (`lab_team_cluster_ready`):
```text
lab_team_cluster_ready{cluster="spoke-nonprod", name="analytics-dev", env="dev"}  1
lab_team_cluster_ready{cluster="spoke-prod",    name="analytics-prod", env="prod"} 1
```

---

### 2.2 Alert Rule `TeamClusterNotReady`

Prometheus rule definition in `alerting_rules.yml`:
```yaml
- alert: TeamClusterNotReady
  expr: lab_team_cluster_ready == 0
  for: 1m
  labels: {severity: critical}
  annotations:
    summary: "Team cluster {{ $labels.name }} is not ready on {{ $labels.cluster }}"
    runbook: docs/runbooks/tenant-iac-operations.md#alert-teamclusternotready
    logs: "http://grafana.localhost/d/lab-logs?var-cluster={{ $labels.cluster }}&var-namespace={{ $labels.namespace }}"
```

`make test-alert-rules` Promtool verification:
```console
$ make test-alert-rules
  SUCCESS
```

---

## 3. Operational Drills Evidence

### 3.1 Drill 1: Out-of-Band Delete & Self-Healing

1. **Delete cluster and nodegroup out-of-band in Moto:**
   ```bash
   aws --endpoint-url=http://localhost:5000 eks delete-nodegroup \
     --cluster-name team-data-analytics-dev --nodegroup-name team-data-analytics-dev-ng
   aws --endpoint-url=http://localhost:5000 eks delete-cluster \
     --name team-data-analytics-dev
   ```
2. **Observed Reconciliation:**
   - Attempt 1: Cluster recreated in Moto with status `ACTIVE`.
   - Attempt 13: Nodegroup recreated in Moto with status `ACTIVE`.
   - Spoke `TeamEKSCluster/analytics-dev` reports `ready: true`, `state: ACTIVE`, `clusterStatus: ACTIVE`, `ngStatus: ACTIVE`.

### 3.2 Drill 2: Removal of a Prod File & Resource Retention

1. **Claim Provisioning:**
   - Branch `drill/retention-test-prod` created `teams/team-data/clusters/retention-prod.yaml`.
   - PR #5 merged (`4a12e84`) after passing CI in 50s.
   - Argo CD created Application `team-data-retention-prod`.
   - Moto account `222222222222` provisioned cluster `team-data-retention-prod` (`ACTIVE`).
2. **File Removal:**
   - Branch `drill/remove-retention-prod` deleted `retention-prod.yaml`.
   - PR #6 merged (`bd816ea`) after passing CI in 58s.
   - Argo CD ApplicationSet pruned `team-data-retention-prod`.
   - Kubernetes `TeamEKSCluster/retention-prod` and child CRs deleted from `k3d-spoke-prod`.
3. **Retention Verification:**
   - AWS CLI verification in Moto account `222222222222`:
     ```json
     {
         "name": "team-data-retention-prod",
         "status": "ACTIVE",
         "arn": "arn:aws:eks:us-east-1:222222222222:cluster/team-data-retention-prod"
     }
     ```
   - Cloud record **retained** in Moto per `services.k8s.aws/deletion-policy: retain`.
   - Test cluster cleaned up manually via AWS CLI.

### 3.3 Drill 3: Alert Fired Once

1. **Fault Injection:**
   - Created `TeamEKSCluster/alert-drill` on `k3d-spoke-nonprod`.
   - Simulated terminal condition on child nodegroup (`ACK.Terminal: True`).
   - `TeamEKSCluster/alert-drill` status transitioned to `ready: false`.
   - Spoke probe emitted `lab_team_cluster_ready{name="alert-drill", ...} 0`.
2. **Alert Triggered:**
   - Hub Prometheus evaluated `lab_team_cluster_ready == 0`.
   - At $t=0$, alert transitioned to `pending`.
   - At $t=60\text{s}$, alert transitioned to `firing`:
     ```json
     {
       "labels": {
         "alertname": "TeamClusterNotReady",
         "cluster": "spoke-nonprod",
         "env": "dev",
         "instance": "10.42.1.39:9102",
         "job": "synthetic-order-probe",
         "name": "alert-drill",
         "namespace": "iac-team-data-dev",
         "severity": "critical",
         "team": "team-data"
       },
       "annotations": {
         "logs": "http://grafana.localhost/d/lab-logs?var-cluster=spoke-nonprod&var-namespace=iac-team-data-dev",
         "runbook": "docs/runbooks/tenant-iac-operations.md#alert-teamclusternotready",
         "summary": "Team cluster alert-drill is not ready on spoke-nonprod"
       },
       "state": "firing"
     }
     ```
3. **Recovery:**
   - Cleaned up `alert-drill`.
   - Alert returned to `inactive` in Prometheus.

---

## 4. Smoke & Quality Gates

```console
$ make ci
✔ 33 scripts: syntax and shellcheck clean
✔ secret scan: 400 tracked files, no credential patterns
✔ 42 Applications rendered offline
✔ manifests valid (581 resources, 0 errors)
✔ alert rules valid and unit tests pass (21 rules)
✔ 2 dashboards valid
✔ 1 tenant ApplicationSet(s) match template
✔ 1 tenant-iac ApplicationSet(s) match templates
✔ all checks passed

$ make ci-iac
✔ 2 team cluster claims valid
✔ fixture suite: 2/2 positive passed, 14/14 negative rejected
✔ ApplicationSets and charts rendered successfully
✔ manifests valid against TeamEKSCluster CRD schema
✔ secret scan: 23 tracked files, no credential patterns
✔ all checks passed

$ make orphans
✔ no orphaned credentials or namespaces

$ bash scripts/smoke-test-hub-spoke.sh
✔ All 42 Argo CD applications are Synced and Healthy
✔ All Core Smoke Tests Passed! (12/12)
```

---

## 5. Next Steps

Phase P5 execution is complete and ready for independent validation by **Codex / Claude** per the team division of labor.
Exit gate:
1. Validate Grafana dashboard panel and Prometheus metrics.
2. Verify unit tests for `TeamClusterNotReady` (`make test-alert-rules`).
3. Verify test suites (`make ci`, `make ci-iac`, `make orphans`, `scripts/smoke-test-hub-spoke.sh`).
4. Validate operational runbook [`docs/runbooks/tenant-iac-operations.md`](../runbooks/tenant-iac-operations.md).
