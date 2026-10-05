# Tenant IaC plan v0.3: P3 tenant repo implementation report (implemented-04)

> **Status: Executed (2026-10-05 UTC). Ready for peer validation.**
> Executor: Antigravity.
> Validator: Claude (Opus 5.5).
> Plan: [`2026-10-04-tenant-iac-team-clusters-plan.md`](2026-10-04-tenant-iac-team-clusters-plan.md) v0.3, Phase P3.
> Verified Commits & Configuration:
> - `tenant-iac`: commit **`084c23f`** on `main` (repository public: [`brunobml/tenant-iac`](https://github.com/brunobml/tenant-iac))
> - `gitops-control-plane`: commit **`1dd2046`** on `main` (CI runner, validator, ApplicationSet template, `make ci-iac`)
> - GitHub Ruleset **`24519842`** (*Require a pull request*) active on `main`

---

## 1. Delivered Scope

Phase P3 establishes the public tenant repository [`brunobml/tenant-iac`](https://github.com/brunobml/tenant-iac) and its governance framework for self-service EKS clusters:

### 1.1 `tenant-iac` Repository
1. **JSON Schema (`schema/cluster.schema.json`):**
   - Enforces Draft 2020-12 schema matching the `teamekscluster-contract` admission policy.
   - Properties: `team` (lowercase DNS 2–20 chars), `name` (lowercase DNS 2–20 chars), `env` (`dev`, `test`, `prod`), `kubernetesVersion` (`1.32`, `1.33`, `1.34`), `network` (`platform-default`), `nodeGroup` (`instanceType` in `t3.medium`, `t3.large`, `m5.large`; `minSize` $\ge 1$, `desiredSize` $\ge 1$, `maxSize` $\ge 1$).
   - Conditional sizing bounds: `maxSize <= 3` for `dev`/`test`; `maxSize <= 5` for `prod`.
   - `additionalProperties: false`.
2. **Directory Structure (`teams/README.md`):**
   - Documented directory layout: `teams/<team>/clusters/<name>-<env>.yaml`.
   - Enforces strict directory matching (`team` field must equal directory name `teams/<team>/`) and naming convention (`<name>-<env>.yaml`).
3. **Fixture Suite (`tests/fixtures/`):**
   - **Positive fixtures (`tests/fixtures/positive/`):** `dev.yaml`, `prod.yaml`.
   - **Negative fixtures (`tests/fixtures/negative/`):** 14 test cases covering uppercase team name, trailing hyphen in cluster name, invalid env `staging`, versions `1.31` and `9.99`, custom network `custom-vpc`, disallowed instance `c5.24xlarge`, `minSize: 0`, relational bounds (`min > desired`, `desired > max`), dev `maxSize: 4`, prod `maxSize: 6`, extra fields, and missing `nodeGroup`.
4. **Code Owners (`.github/CODEOWNERS`):**
   - Global repository owner: `* @brunobml`
   - Production gate: `/teams/*/clusters/*-prod.yaml @brunobml`
5. **CI Workflow (`.github/workflows/ci.yaml`):**
   - Job: `cluster-checks` (timeout 10m).
   - Triggers on `push` (`main`, `ci-selftest/**`), `pull_request` (`main`), and `workflow_dispatch`.
   - Runs `gitops-control-plane/ci/check-tenant-iac.sh`.
6. **Documentation (`README.md`):**
   - Architectural flow diagram (Mermaid), claim specification, guardrails table, repository layout, and local testing instructions.

### 1.2 `gitops-control-plane` CI & Templates
1. **Cluster Validator (`ci/check-clusters.py`):**
   - Validates live claims under `teams/*/clusters/*.yaml` against `schema/cluster.schema.json`.
   - Enforces relational sizing (`1 <= minSize <= desiredSize <= maxSize`), team directory matching, filename convention, uniqueness of `<name>-<env>` across teams, and team cluster limit ($\le 5$).
   - Implements `--test-fixtures` mode: asserts that all 14 negative fixtures fail with descriptive errors and both positive fixtures pass.
2. **CI Runner (`ci/check-tenant-iac.sh`):**
   - Stages: `claims`, `fixtures`, `render` (offline template through `team-cluster:1.0.0` Helm chart), `schemas` (kubeconform validation against `teamekscluster_v1alpha1.json`), `secrets` (`secret-scan.py`).
   - Supports both local chart mount (`platform-charts/charts/team-cluster`) and direct anonymous OCI pull (`oci://ghcr.io/brunobml/charts/team-cluster:1.0.0`).
3. **ApplicationSet Template (`scripts/templates/tenant-iac-appset.yaml` & `scripts/tenant-iac-appset.sh`):**
   - One ApplicationSet per team (`tenant-iac-<team>`), destination namespace `iac-<team>-<env>`, CARM accounts `111111111111` (nonprod) and `222222222222` (prod), restricted PSS.
4. **Tooling Integration:**
   - Added `ci-iac` target to `Makefile` (`make ci-iac`).
   - Added `tenant-iac` with required check `cluster-checks` to `ci/README.md`.

---

## 2. Verification Evidence

### 2.1 Local Test Suite (`make ci-iac`)

```console
$ make ci-iac

[claims] Cluster claim files
✔ 0 live team clusters found (directory ready for onboarding)

[fixtures] Fixture suite verification (positive and negative fixtures)
Testing fixture suite...
  ✔ positive fixture passed: tests/fixtures/positive/dev.yaml
  ✔ positive fixture passed: tests/fixtures/positive/prod.yaml
  ✔ negative fixture rejected as expected: tests/fixtures/negative/01-bad-team-dns.yaml (team: 'TeamData' does not match '^[a-z][a-z0-9-]{0,18}[a-z0-9]$')
  ✔ negative fixture rejected as expected: tests/fixtures/negative/02-bad-name-dns.yaml (name: 'analytics-' does not match '^[a-z][a-z0-9-]{0,18}[a-z0-9]$')
  ✔ negative fixture rejected as expected: tests/fixtures/negative/03-bad-env.yaml (env: 'staging' is not one of ['dev', 'test', 'prod'])
  ✔ negative fixture rejected as expected: tests/fixtures/negative/04-bad-version-1.31.yaml (kubernetesVersion: '1.31' is not one of ['1.32', '1.33', '1.34'])
  ✔ negative fixture rejected as expected: tests/fixtures/negative/05-bad-version-9.99.yaml (kubernetesVersion: '9.99' is not one of ['1.32', '1.33', '1.34'])
  ✔ negative fixture rejected as expected: tests/fixtures/negative/06-bad-network.yaml (network: 'platform-default' was expected)
  ✔ negative fixture rejected as expected: tests/fixtures/negative/07-bad-instance-type.yaml (nodeGroup.instanceType: 'c5.24xlarge' is not one of ['t3.medium', 't3.large', 'm5.large'])
  ✔ negative fixture rejected as expected: tests/fixtures/negative/08-min-size-zero.yaml (nodeGroup.minSize: 0 is less than the minimum of 1)
  ✔ negative fixture rejected as expected: tests/fixtures/negative/09-min-greater-than-desired.yaml (spec.nodeGroup sizes must satisfy 1 <= minSize <= desiredSize <= maxSize (got minSize=3, desiredSize=2, maxSize=3))
  ✔ negative fixture rejected as expected: tests/fixtures/negative/10-desired-greater-than-max.yaml (spec.nodeGroup sizes must satisfy 1 <= minSize <= desiredSize <= maxSize (got minSize=1, desiredSize=4, maxSize=3))
  ✔ negative fixture rejected as expected: tests/fixtures/negative/11-dev-max-greater-than-3.yaml (nodeGroup.maxSize: 4 is greater than the maximum of 3)
  ✔ negative fixture rejected as expected: tests/fixtures/negative/12-prod-max-greater-than-5.yaml (nodeGroup.maxSize: 6 is greater than the maximum of 5)
  ✔ negative fixture rejected as expected: tests/fixtures/negative/13-extra-fields.yaml ((root): Additional properties are not allowed ('extraField' was unexpected))
  ✔ negative fixture rejected as expected: tests/fixtures/negative/14-missing-nodegroup.yaml ((root): 'nodeGroup' is a required property)
✔ fixture suite: 2/2 positive passed, 14/14 negative rejected

[render] Render cluster claims through chart
✔ rendered: tests/fixtures/positive/dev.yaml -> team-data-dev.yaml
✔ rendered: tests/fixtures/positive/prod.yaml -> team-data-prod.yaml

[schemas] Schema validation (kubeconform)
Summary: 2 resources found in 2 files - Valid: 2, Invalid: 0, Errors: 0, Skipped: 0
✔ manifests valid against TeamEKSCluster CRD schema

[secrets] Secret patterns in tracked files
✔ secret scan: 1 tracked files, no credential patterns

✔ all checks passed
```

### 2.2 Remote GitHub Actions CI Run

- **Run ID:** `37350898680` (job `cluster-checks` ID `111901168904`).
- **Conclusion:** `success` in 30 seconds.
- Checked out `tenant-iac` and `gitops-control-plane` (`main`), pulled `alpine/helm:3.19.0`, verified 14 negative and 2 positive fixtures, pulled `oci://ghcr.io/brunobml/charts/team-cluster:1.0.0`, rendered manifests, and validated with `kubeconform`.

### 2.3 Ruleset Enforcement (Exit Gate: Direct Push Refused)

Configured GitHub Ruleset **`24519842`** (*Require a pull request*) on `brunobml/tenant-iac` with `enforcement: active`, targeting `~DEFAULT_BRANCH`, requiring status check `cluster-checks` and PR review, with `current_user_can_bypass: never`.

Tested direct push attempt on `main`:
```console
$ git commit -am "test: verify direct push is refused"
$ git push origin main
remote: error: GH013: Repository rule violations found for refs/heads/main.
remote: Review all repository rules at https://github.com/brunobml/tenant-iac/rules?ref=refs%2Fheads%2Fmain
remote: 
remote: - Required status check "cluster-checks" is expected.
remote: 
remote: - Changes must be made through a pull request.
remote: 
To github.com:brunobml/tenant-iac.git
 ! [remote rejected] main -> main (push declined due to repository rule violations)
error: failed to push some refs to 'github.com:brunobml/tenant-iac.git'
```
Direct push was **refused**. Test commit was reset locally.

### 2.4 Pull Request Validation

Opened PR #1 (`test/pr-check`) on `brunobml/tenant-iac`:
- Status check `CI/cluster-checks (pull_request)` ran automatically and passed in **29s**.
- PR closed and test branch deleted; repository remains completely clean.

### 2.5 Zero Lab Regressions

All suites verified locally and green:
- `make ci`: 31 scripts clean, 388 files scanned, 40 apps rendered, 577 resources validated, promtool 20 rules passed.
- `make ci-catalog`: CEL 6 objects checked, 2 RGD schemas compatible, 22 apps rendered, 376 resources validated.
- `make ci-charts`: `queue-backed-service:1.0.0` and `team-cluster:1.0.0` lint clean and released.
- `make ci-tenants`: 3 tenant registrations valid, 3 apps rendered, kubeconform valid.
- `make test-alert-rules`: 20 rules passed.
- All 40 Argo CD applications remain `Synced` and `Healthy` on Hub.

---

## 3. For the Validator (Claude)

1. **Verify `tenant-iac` repository:**
   ```bash
   cd /home/bleite/repos/tenant-iac
   git status
   git log -n 2 --oneline
   ```
2. **Verify ruleset on `tenant-iac`:**
   ```bash
   gh api repos/brunobml/tenant-iac/rulesets
   # Observe ruleset 24519842 active, current_user_can_bypass: never, required check: cluster-checks
   ```
3. **Verify direct push refusal:**
   Attempt a commit on `main` and verify `git push origin main` is refused by GitHub with `GH013`.
4. **Verify test suite:**
   ```bash
   cd /home/bleite/repos/gitops-control-plane
   make ci-iac
   ```
   Confirm all stages (`claims`, `fixtures`, `render`, `schemas`, `secrets`) pass.
5. **Verify GitHub Actions remote run:**
   ```bash
   gh run list --repo brunobml/tenant-iac
   gh run view 37350898680 --repo brunobml/tenant-iac
   ```
6. **Verify lab health:**
   Confirm 40/40 Argo CD applications are `Synced` and `Healthy`, and `make ci` is clean.
