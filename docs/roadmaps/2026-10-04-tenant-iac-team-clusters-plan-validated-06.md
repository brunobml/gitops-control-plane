# Tenant IaC plan v0.3: P3 re-validation (validated-06)

> **Status: Independent re-validation (2026-10-05 UTC).** Validator: Claude (Opus 5.5). Executor: Antigravity. Under review: `gitops-control-plane` `4bceeb9` (V-1, V-3) and `tenant-iac` PR #2 `78bf184` → merge `0f6b899` (V-2). Previous verdict: [validated-05](2026-10-04-tenant-iac-team-clusters-plan-validated-05.md) 🟡.
>
> The only change I made was a temporary edit to the ApplicationSet template for the negative test (restored with `git checkout`; working tree clean). Other tests ran on throwaway copies of `tenant-iac`.

## Verdict: 🟢 GREEN: P3 closed, P4 unblocked

| # | Item | Result | Evidence |
|---|---|---|---|
| **V-1** | ApplicationSet values path + render stage | ✅ **Closed** | The template now uses `'$values/{{ .path.path }}/{{ .path.filename }}'`. The new `render` stage generates each team's ApplicationSet with `scripts/tenant-iac-appset.sh`, renders it with `labci appsets` against the tenant-iac checkout (with no team folders yet, it uses the positive fixtures as `teams/team-data/clusters/analytics-{dev,prod}.yaml`), then renders every generated Application (chart from GHCR + `$values` file) with `ci/render.py`, then kubeconform. Output I kept and read: `valueFiles: $values/teams/team-data/clusters/analytics-dev.yaml` (and `-prod`); each `TeamEKSCluster` carries **its own claim's values** (dev: 1.33, t3.medium, 1/2/3; prod: 1.32, m5.large, 1/3/5), namespace `iac-team-data-<env>`. **Negative test:** with `{{ .path }}` restored temporarily, the stage fails: `✘ team-data-analytics-dev: valueFile $values/map[basename:clusters …` → "render through ApplicationSet template failed", schemas "no manifests", 2 checks failed |
| **V-2** | Prod-gate wording | ✅ **Closed** | `tenant-iac` PR #2 (merged through the ruleset; `cluster-checks` green on the PR and on `main` `0f6b899`): READMEs now say PR + required check, and CODEOWNERS *requests* the platform owner's review on `*-prod.yaml` |
| **V-3** | Uniqueness | ✅ **Closed** (owner-delegated decision applied) | Key is now `<team>/<name>-<env>`. Temp copy with `team-data/…/analytics-dev.yaml` and `team-web/…/analytics-dev.yaml`: both claims valid, **2 Applications `team-data-analytics-dev`, `team-web-analytics-dev`**, 2 manifests valid. Duplicates within a team are still impossible (file name = `<name>-<env>.yaml`) |
| — | Regression | ✅ | `make ci-iac`: claims, fixtures 2/2 + 14/14, render, kubeconform 2/2, secret scan 21 files; tenant-iac remote runs green (`37353163040` on `0f6b899`, PR run on `78bf184`); control-plane CI green on `4bceeb9`; 40/40 apps Synced/Healthy |

## Notes for P4
- The render stage switches to the real `teams/*` folders as soon as the first team exists. P4's first PR (`team-data/analytics-dev`) is therefore checked through its own ApplicationSet.
- Still open from validated-02 (V-4): Argo CD applies none of the lab's custom health Lua. P4 adds health for `TeamEKSCluster` and the EKS `Cluster` (amendment 7), so fix the `resource.customizations` format there and prove a health status appears.
- Still open from validated-03: R-a (no trap in `moto-restart.sh`), R-b (`|| true` in its assertion), R-c (`make start` path untested).
