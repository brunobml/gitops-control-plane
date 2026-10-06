# Tenant IaC plan v0.3: P5 acceptance validation (validated-09)

> **Status: Accepted.** Validated by Codex on 2026-10-06 14:59 UTC against `c757965` (`origin/main`).
> Reviews [validated-08](2026-10-04-tenant-iac-team-clusters-plan-validated-08.md) and the clean-slate rebuild evidence in [implemented-08](2026-10-04-tenant-iac-team-clusters-plan-implemented-08.md).

## Independent checks

| Check | Result |
| --- | --- |
| `bash scripts/smoke-test-hub-spoke-bats.sh` | 27/27 passed, including end-to-end orders in dev, test, and prod and both team cluster metrics. |
| `make test-alert-rules` | Passed. |
| `make ci` | Passed: 42 Applications rendered, 581 resources checked with 0 invalid/errors, 21 alert rules and 2 dashboards valid. |
| `make ci-iac` | Passed: 2 claims, 2 positive fixtures, 14 negative fixtures, both rendered claims schema-valid. |
| `make orphans` | Passed: no orphaned credentials or namespaces. |
| Live Argo CD and claims | 42 Applications Synced and Healthy; `analytics-dev` and `analytics-prod` Ready=True and ACTIVE. |
| Live Prometheus and Grafana configuration | Both `lab_team_cluster_ready` values are 1; `lab_team_cluster_info` carries `readiness="Ready"`; deployed Team clusters panel includes Readiness. No firing alerts. |
| Remote CI | GitHub Actions run `37433787550` completed successfully for `c757965`. |

## Closure of validated-08 findings

1. **Stage 9 timeout:** The probe loop now sleeps after each run rather than flooding Moto. Independent Bats Gate 9 processed new orders in all three environments. The implementation report also records a successful 12-stage legacy smoke run after the rebuild.
2. **Missing team metrics passed smoke:** Both the legacy smoke script and Bats Gate 12d now wait up to 60 seconds for each expected claim's metric and require value 1. Inspection of the deployed metrics confirmed both series exist.
3. **Dashboard readiness:** The probe exports a Readiness label, and the deployed Grafana panel includes it beside State. The runbook describes this distinction.
4. **Runbook consistency:** Claim paths include `clusters/`, Kubernetes 1.34 is documented, and the runbook states that the active GitHub ruleset requires zero approving reviews. The live ruleset still reports `required_approving_review_count: 0` and `require_code_owner_review: false`.
5. **Full rebuild:** The executor's implemented-08 report records successful `make teardown && make setup && make bootstrap && make post-bootstrap`, including 42 healthy Applications and a 12-stage smoke pass. I reviewed this record and independently verified the resulting live lab and gates. I did not repeat the destructive rebuild.

## Disposition

The P5 exit criteria are satisfied. Phase P5 is accepted. The earlier validated-08 report remains the record of the initial failed smoke test and review findings.
