# Implementation Report 02 — Validation-01 Fixes V-1, V-2, V-3 (2026-10-03)

> **Status: Current.** Active remediation record for the 2026-10-03 assessment.

| | |
|---|---|
| **Fixes** | [`2026-10-03-lab-remediation-plan-validation-01.md`](2026-10-03-lab-remediation-plan-validation-01.md) findings **V-1** (High), **V-2** (Medium), **V-3** (Medium), plus the required real-run proof **Y3** |
| **Plan** | [Remediation plan v1.0](2026-10-03-lab-remediation-plan.md), Track 0 Steps 0.2 and 0.3 |
| **Executed by** | Claude (Opus 5.5). **To be validated by** Antigravity, independent of the execution |
| **Commits** | `platform-charts` `d36a84e` (fix), `c275245` (negative test), `30881bf` (revert of the negative test); `platform-catalog` `618467b`, tag `v1.7.1`; `gitops-control-plane` `4f1e01f` (prod promotion) |
| **Date** | 2026-10-03 |

---

## Summary

| ID | Fix | Proof |
|---|---|---|
| **V-1** | The release step parses. Chart name and version are read from `helm show chart` with `awk '/^name:/'` / `awk '/^version:/'`, with no quote handling. An empty value fails the job | `bash -n` passes on the step extracted from the committed workflow; **real** run `37097203382` (`d36a84e`) is green |
| **V-2** | The guard fails closed. Only a `helm pull` error containing `: not found` counts as "new version → push". Any other pull error (outage, auth, rate limit, network) fails the job with `::error:: … Refusing to push (fail closed)` | Local run with an unreachable registry: rc 1, no push. Real runs below |
| **Y3** | Real runs of the committed workflow on both paths | unchanged chart → **green, "Skipping push."**; modified template without a version bump → **red, "contents DIFFER!"**; revert → green. GHCR `1.0.0` digest unchanged throughout |
| **V-3** | `tenant-image-registry-allowlist` also matches the `pods/ephemeralcontainers` subresource (operations `CREATE`, `UPDATE`) | `PUT …/pods/<pod>/ephemeralcontainers?dryRun=All` with `alpine:latest` is **denied by the VAP** in `orders-dev`, `orders-test` and `orders-prod`; an allowlisted image is admitted |

Not in scope: V-4 to V-9. They stay open as recorded in validation-01.

---

## 1. V-1 / V-2 — Release guard (`platform-charts`)

### Change (`d36a84e`, `.github/workflows/release.yaml`)
```bash
chart_name=$(helm show chart "$chart" | awk '/^name:/ {print $2; exit}')
chart_version=$(helm show chart "$chart" | awk '/^version:/ {print $2; exit}')
[ -z "$chart_name" ] || [ -z "$chart_version" ]  → ::error:: … exit 1
helm package "$chart" -d dist/
set +e; pull_err=$(helm pull oci://ghcr.io/$OWNER/charts/$chart_name --version $chart_version -d $tmp 2>&1 >/dev/null); pull_rc=$?; set -e
if   pull_rc == 0                  → extract both packages, diff -r -u → differ: ::error:: DIFFER, exit 1 / identical: "Skipping push."
elif pull_err contains ": not found" → helm push (new version)
else                                → ::error:: Cannot determine … Refusing to push (fail closed); exit 1
```
* `/^name:/` is anchored at column 0. The first draft used `$1 == "name:"`, which also matched the indented `maintainers[].name` and was caught by the local tests.
* `helm show chart` prints Helm's normalised `Chart.yaml`, so quoted values need no special handling.
* Action SHA pins from `522a634` are unchanged.

### Local tests (committed step extracted, `helm push` stubbed)
| Case | Expected | Result |
|---|---|---|
| Chart unchanged vs GHCR `1.0.0` | skip, rc 0 | ✅ "identical … Skipping push.", rc 0, no push |
| Template changed, version not bumped | fail, rc 1 | ✅ "contents DIFFER!", rc 1, no push |
| Version bumped (`1.0.1`, not in GHCR) | push | ✅ pull says `not found` → stub `helm push` called |
| Registry unreachable | fail closed, rc 1 | ✅ "Cannot determine … Refusing to push", rc 1, no push |

### Real GitHub Actions runs (Y3)
| Commit | Change | Run | Result |
|---|---|---|---|
| `d36a84e` | the fix itself (chart unchanged) | `37097203382` | ✅ **success**, guard step took the skip path |
| `c275245` | appended `{{- /* … */ -}}` to `templates/queue-backed-service.yaml`, version **not** bumped. Rendered output verified byte-identical before the push, so no deploy risk | `37097248060` | ✅ **failure as intended**: annotations *"Chart queue-backed-service:1.0.0 exists in GHCR but packaged contents DIFFER!"*, *"Re-releasing existing chart versions with modified templates is prohibited (L2-1)."*, *"Bump 'version' …"*, exit 1 |
| `30881bf` | revert of `c275245` | `37097279544` | ✅ **success** (skip path) |

GHCR `ghcr.io/brunobml/charts/queue-backed-service:1.0.0` manifest digest before, during and after: `sha256:4668c360b2fdee088e7db4ea572cec19217a2d0b0b6b3af9f69831d0a22825bd` (unchanged).

The fail-closed branch (V-2) was proven locally only. Making GHCR fail on demand in a real run would need a broken workflow on `main`, and that was not done.

---

## 2. V-3 — Ephemeral containers (`platform-catalog`)

### Change (`618467b`, `blueprints/tenant-image-registry-allowlist.yaml`)
```yaml
    resourceRules:
      - apiGroups: [""]
        apiVersions: ["v1"]
        operations: ["CREATE", "UPDATE"]
        resources: ["pods", "pods/ephemeralcontainers"]
```
* The subresource request carries the full Pod as `object`, so the existing `ephemeralContainers` validation now runs on it. The binding is unchanged.
* Catalog `v1.7.0..v1.7.1` changes this file only (3 insertions, 1 deletion; one is a comment).

### Rollout
1. Push to `main`. `kro-blueprints-spoke-nonprod` synced `618467b`, Synced/Healthy. Prod was still on `v1.7.0` and still admitted the `alpine` ephemeral container, confirming the baseline.
2. Tag `v1.7.1` at `618467b`. `clusters/blueprint-revisions.env` `spoke-prod=v1.7.1` (`4f1e01f`), then `make promote-blueprints`. `kro-blueprints-spoke-prod` reached `v1.7.1` / `618467b`, Synced/Healthy.
3. Live policy on both spokes: `resources: ["pods","pods/ephemeralcontainers"]`.

### Tests (server-side, `PUT /api/v1/namespaces/<ns>/pods/<running pod>/ephemeralcontainers?dryRun=All`, Pod Security-compliant ephemeral container)
| Cluster / namespace | Image | Result |
|---|---|---|
| nonprod `orders-dev` | `alpine:latest` | ✅ denied by `ValidatingAdmissionPolicy 'tenant-image-registry-allowlist'` |
| nonprod `orders-test` | `alpine:latest` | ✅ denied (same policy) |
| nonprod `orders-dev` | `ghcr.io/brunobml-evil/x:1` | ✅ denied (same policy) |
| nonprod `orders-dev` | `ghcr.io/brunobml/orders-processor:v1.5.0` | ✅ admitted (dry run response contains the container) |
| prod `orders-prod` | `alpine:latest` | ✅ denied (same policy) |
| prod `orders-prod` | `ghcr.io/brunobml/orders-processor:v1.5.0` | ✅ admitted |
| prod `orders-prod` | regular Pod `alpine:latest` (`kubectl run --dry-run=server`) | ✅ still denied (no regression) |

No live Pod was changed: every request was `dryRun=All`, and afterwards no pod in `orders-dev` or `orders-prod` has `ephemeralContainers`.

---

## 3. Regression (after prod promotion)
| Check | Result |
|---|---|
| Applications | 32/32 Synced/Healthy |
| `scripts/smoke-test-hub-spoke.sh` | ✅ All core smoke tests passed (rc 0); stage 11: unsigned and `alpine` denied, running image admitted in all three tenant namespaces |
| `scripts/audit-impersonation.sh` | ✅ PASS |
| `make test-alert-rules` | ✅ SUCCESS |

---

## 4. Notes for the validator
* **Process deviation (same as V-7):** all commits in this report were pushed directly to `main`. PR-only mode is not active yet (A.4). The negative-test pair `c275245`/`30881bf` is intentional history: it is the only way to show a real red run of the committed guard.
* **Track A input (from V-1):** add `bash -n` / `shellcheck` of workflow `run:` steps to CI. `shellcheck` is not installed on the lab host, so only `bash -n` was run.
* **Suggested checks for independent validation:**
  * Actions runs `37097203382` / `37097248060` / `37097279544` and their annotations.
  * GHCR `1.0.0` digest.
  * Live `resourceRules` on both spokes.
  * Repeat the `pods/ephemeralcontainers` dry run (also try `kubectl debug` with `--dry-run=server` where supported).
  * Confirm catalog `v1.7.0..v1.7.1` contains only the policy file.

## 5. Track 0 status after this report
| Step | Status |
|---|---|
| 0.1 | ✅ Validated (V-4, V-7 open as observations) |
| 0.2 | 🔧 V-1, V-2, Y3 fixed. **Awaiting validation-02** |
| 0.3 | 🔧 V-3 fixed on nonprod and prod. **Awaiting validation-02** |
| 0.4–0.7 | Not started |
