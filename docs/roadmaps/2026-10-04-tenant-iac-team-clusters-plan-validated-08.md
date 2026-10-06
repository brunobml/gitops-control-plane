# Tenant IaC plan v0.3: P5 independent validation (validated-08)

> **Status: Not accepted; remediation and a new smoke run required.**
> Validator: Codex. Checked 2026-10-06 03:53 UTC against control-plane commit `6ec74ae` and the live lab.
> Implementation report: [implemented-06](2026-10-04-tenant-iac-team-clusters-plan-implemented-06.md).

## Checks that passed

- `make test-alert-rules`: passed, including the `TeamClusterNotReady` cases.
- `make ci`: passed; 42 Applications rendered, 581 resources checked (0 invalid, 0 errors), 21 alert rules and 2 dashboards valid.
- `make ci-iac`: passed; 2 claims, 2 positive fixtures and 14 negative fixtures; both rendered claims passed schema validation.
- `make orphans`: no orphaned credentials or namespaces.
- Live hub Argo CD: 42 Applications, all Synced and Healthy at the time of inspection. The two `TeamEKSCluster` claims were Ready=True; their ACK EKS clusters were ACTIVE. Moto EKS lists contained `team-data-analytics-dev` in account `111111111111` and `team-data-analytics-prod` in account `222222222222`.
- Live Prometheus returned both `lab_team_cluster_info` series with the expected account ARNs and `lab_team_cluster_ready=1` for both claims. The loaded `TeamClusterNotReady` rule had a 60-second duration and health `ok`. A 12-hour `max_over_time(ALERTS{alertname="TeamClusterNotReady",alertstate="firing"}[12h])` query returned the `alert-drill` series, corroborating the reported firing drill. The dashboard ConfigMap contains the `Team clusters` panel and its age query.
- Tenant IaC PRs #5 and #6 are merged and respectively added and removed `teams/team-data/clusters/retention-prod.yaml`. No retention drill claim or cloud cluster remains in the current live state after the reported manual cleanup, so the transient retention state cannot be rechecked directly.

## Findings

1. **The required smoke gate failed live.** `bash scripts/smoke-test-hub-spoke.sh` passed stages 1–8, then stage 9 failed: the `orders-dev` marker `smoke-e2e-orders-dev-1791258715` was not visible on the dashboard within 60 seconds. Immediately afterward, `http://orders-dev.localhost:8081/` timed out after 5 seconds, and the `orders-dev-worker` pod had recent readiness and liveness probe timeouts. The worker remained Ready with zero restarts, and `QueueBackedService/orders` remained ACTIVE. The cause is not yet established. Stages 10–12 did not run. The P5 exit gate cannot be accepted while the full smoke check fails.
2. **The new smoke assertion can pass with no team cluster metrics.** `scripts/smoke-test-hub-spoke.sh` queries only `lab_team_cluster_ready == 0`; an absent series or a failed query produces an empty result, which passes. It also suppresses query errors with `|| true`. Check that each expected claim has a fresh readiness series before checking its value.
3. **The dashboard does not display readiness.** The `Team clusters` table uses `time() - lab_team_cluster_info` and displays that metric's `state` label. The probe populates `state` from EKS cluster status, while readiness also depends on the nodegroup. Thus the table may still show `ACTIVE` during a nodegroup readiness failure. The runbook's statement that it shows `NOT READY` is incorrect; add readiness to the panel or correct the runbook.
4. **The runbook contains instructions that do not match the current repository or branch rule.** Claim files are under `teams/<team>/clusters/<name>-<env>.yaml`, not `teams/<team>/<name>-<env>.yaml`; the example validation command points at the wrong path. The schema allows Kubernetes `1.34` in addition to `1.32` and `1.33`. The active tenant-IaC GitHub ruleset (`24519842`) has `required_approving_review_count: 0` and `require_code_owner_review: false`, so the runbook's statement that prod approval is required is not an enforced gate.
5. **The full rebuild exit criterion lacks P5 evidence.** The implementation report records CI, orphan, smoke and focused drills, but no full rebuild after the P5 changes. A rebuild was not attempted in this validation because it destroys and recreates the running lab. Record a successful full rebuild after the live smoke failure is resolved, or explicitly amend that exit criterion.

## Disposition

P5 has working metrics, a deployed dashboard, a loaded alert, and historical evidence of an alert firing. Acceptance remains open on the live smoke failure, the missing-series check, the dashboard and runbook mismatch, and the full rebuild criterion. Re-run the 12-stage smoke check after diagnosing the `orders-dev` timeout.
