# Validation Report 01 — Track 0: Steps 0.1–0.3 (2026-10-03)

> **Status: Current.** Active remediation record for the 2026-10-03 assessment.

| | |
|---|---|
| **Validates** | [`2026-10-03-lab-remediation-plan-implemented-01.md`](2026-10-03-lab-remediation-plan-implemented-01.md) |
| **Against** | [Remediation plan v1.0](2026-10-03-lab-remediation-plan.md) (GREEN LIGHT, early authorization for 0.1–0.3; remarks R-0, R-1, R-2; owner decisions O-1, O-2) |
| **Commits under test** | `gitops-control-plane` `e1a196b`, `912bb52`, `3bc3f12`; `tenant-workloads` `6064fc5`; `platform-charts` `825fb40`, `522a634`; `platform-catalog` `07e9e62`, `159663b`, tag `v1.7.0`; `orders-processor` `1d0b025` |
| **Executed by** | Antigravity & platform owner. **Validated by** Claude (Opus 5.5), independent of the execution |
| **Method** | Public GitHub API (branch protection, CODEOWNERS errors, commit/PR association, Actions runs, jobs and annotations); `git ls-remote` for the Action SHA pins; the committed workflow step extracted and run locally with `helm push` stubbed; GHCR manifest digest; server-side dry runs on all three tenant namespaces, including initContainers, a look-alike registry and the `pods/ephemeralcontainers` subresource (`dryRun=All`); full regression (smoke, impersonation audit, `make test-alert-rules`, Application health) |
| **Changes made by this validation** | None (dry runs only; no push, no live object changed) |
| **Date** | 2026-10-03 |

---

## Verdict

> ### 🟡 PARTIALLY VALIDATED — 0.1 and 0.3 pass with findings; **0.2 does not pass**
>
> * **0.1 Change control:** ✅ All five `main` branches are protected; CODEOWNERS present and error-free in all five repos. The R-0 force-push/deletion test is not evidenced, and O-1's PR-only mode is not yet in effect (V-4, V-7).
> * **0.2 Chart immutability:** ❌ **The committed guard has a bash syntax error.** The real GitHub Actions run for `522a634` **failed** (exit code 2), so the guard never executes and **no chart can be released at all**. The report's evidence comes from a local simulation, not from the committed workflow. The design also **fails open** on any `helm pull` error (V-1, V-2, V-8). Prod is not exposed: GHCR `1.0.0` was not re-pushed.
> * **0.3 Registry allowlist:** ✅ Enforced on all three tenant namespaces (containers, initContainers, look-alike registries), not affected outside them, and smoke-tested. **Ephemeral containers bypass it** because the `pods/ephemeralcontainers` subresource is not matched (V-3). The Audit-first rollout was skipped (V-5).
> * **Regression:** ✅ 32/32 Applications Synced/Healthy, smoke 12/12, impersonation audit PASS, alert rule tests SUCCESS.
>
> **Required before Track 0 is closed:** V-1, V-2, V-3, plus a green run of the real release workflow (Y3). The other items are observations.

| Step | Focus | Result |
|---|---|:-:|
| **0.1** | Branch protection, CODEOWNERS (L2-2, L4-1) | ✅ with observations |
| **0.2** | Immutable golden chart versions (L2-1), SHA-pinned Actions | ❌ |
| **0.3** | Tenant registry allowlist (L4-2, O-2) | ✅ with a finding |

---

## 1. Evidence

### Step 0.1 — Change control
| Check | Result |
|---|---|
| `GET /repos/brunobml/<repo>/branches/main` | `protected: true` for all five (was `false` for `tenant-workloads`) |
| Required status checks | `enforcement_level: off`, `contexts: []` on all five (expected until Track A exists) |
| CODEOWNERS | present in `.github/CODEOWNERS` in all five; `GET …/codeowners/errors` → **0 errors** each. Prod paths named: `tenants/*/apps/*-prod.yaml`, `/deploy/values-prod.yaml`, `/charts/`, `/blueprints/`, `/controllers/`, `/projects/`, `/applicationsets/`, `/clusters/`, `/bootstrap/` (plus `*` catch-all) |
| Direct pushes after protection | `tenant-workloads` `6064fc5` and `platform-charts` `825fb40`/`522a634` were pushed to `main` **without a PR** (`/commits/<sha>/pulls` → 0). The protection does not yet require PRs (V-7) |
| R-0 (force push / deletion rejected, tested on a throwaway branch) | **Not evidenced** in the report; not verifiable from the public API, and not tested on `main` by this validation (a test that succeeds would rewrite history) (V-4) |

### Step 0.2 — Chart immutability
| Check | Result |
|---|---|
| Action SHA pins | `actions/checkout@11bd719…` = tag `v4.2.2` ✅; `azure/setup-helm@b9e5190…` = tag `v4.3.0` ✅ (resolved with `git ls-remote`) |
| `dist/` and `*.tgz` | no longer tracked; listed in `.gitignore` ✅ |
| **Real workflow run for `522a634`** | **`completed/failure`**. Failing step: *Package and Release Charts with Immutability Guard*, annotation *"Process completed with exit code 2"*. The guard only ever exits 1, so this is not the guard rejecting a chart |
| Root cause (reproduced) | The step script, extracted from the committed workflow, fails `bash -n`: `syntax error near unexpected token '('` / `unexpected EOF while looking for matching ')'`. The culprit is the quoting in `chart_name=$(… \| tr -d '"'\'')` (and the same in `chart_version=`): `'"'\''` leaves a single-quoted string open inside `$( … )`. **The guard never runs; every chart release now fails** |
| Guard logic (with the syntax fixed locally, `helm push` stubbed) | Unchanged chart vs GHCR `1.0.0`: extracted contents **identical** → skip ✅. Content diff, not git hash → R-1 satisfied ✅ |
| Fail-open path | `if helm pull … 2>/dev/null; then <compare> else <push as new>`: a pull of an unreachable registry returns rc=1, the same as "version not found". A transient GHCR/auth/network error would take the **push** branch and overwrite the existing version (V-2). The real not-found error is distinguishable (`…:9.9.9: not found`) |
| GHCR `queue-backed-service:1.0.0` | manifest digest `sha256:4668c360…25bd`; only tag present; not re-pushed (the failing workflow published nothing) |
| Report evidence | "diff guard immediately triggered … exit 1" cannot come from the committed workflow, which cannot parse. It was a local or edited version (V-8) |
| Annotation | Node.js 20 deprecation warning for both pinned Actions (they run forced on Node 24) (V-9) |

### Step 0.3 — Registry allowlist
| Check (server-side dry run, Pod Security-compliant spec) | Result |
|---|---|
| `alpine:latest` in `orders-dev`, `orders-test`, `orders-prod` | **denied** by `ValidatingAdmissionPolicy 'tenant-image-registry-allowlist'` ✅ |
| signed `ghcr.io/brunobml/orders-processor:v1.5.0` in all three | admitted ✅ |
| signed main container + `alpine` **initContainer** | **denied** ("All initContainer images …") ✅ |
| look-alike `ghcr.io/brunobml-evil/x:1` | **denied** (the prefix includes the trailing `/`) ✅ |
| `alpine` in `platform-probes` (no opt-in label) | admitted (out of scope, as designed) ✅ |
| **`alpine` ephemeral container via `PUT pods/<pod>/ephemeralcontainers?dryRun=All`** | **ADMITTED.** The policy matches `resources: ["pods"]` only; the subresource used by `kubectl debug` is not matched, so the `ephemeralContainers` validation never runs (V-3). The live pod was not changed (dry run) |
| Scope (R-2) | Policy and binding select `platform.lab/image-verification=enabled` only ✅; `failurePolicy: Fail` |
| Rollout | Single commit with `validationActions: ["Deny","Audit"]`, released in catalog `v1.7.0` and promoted to prod together. The plan's Audit → nonprod Deny → prod sequence was skipped (V-5). Risk was low: all tenant images were already `ghcr.io/brunobml/*` |
| Catalog `v1.6.1..v1.7.0` | only `.github/CODEOWNERS` and the policy file ✅; prod on `v1.7.0` |
| Bindings live | both spokes: `tenant-image-registry-allowlist=["Deny","Audit"]`, `queuebackedservice-contract=["Deny","Audit"]` ✅ |
| Smoke stage 11 | the `alpine` probe uses the compliant pod spec, so it reaches the allowlist ✅. It asserts "denied", not "denied by the VAP" (V-6) |

### Regression
32/32 Synced/Healthy · smoke **12/12** · `audit-impersonation.sh` PASS · `make test-alert-rules` SUCCESS.

---

## 2. Findings

| ID | Sev | Finding | Required action |
|---|---|---|---|
| **V-1** | **High** | Release workflow does not parse (bash syntax error from `tr -d '"'\''` inside `$( … )`); every chart release fails; the guard has never run | Fix the extraction (e.g. `yq -r .name`, or `sed -E 's/^name:[[:space:]]*["'"'"']?([^"'"'"']+).*/\1/'`, or `awk -F': ' '/^name:/{gsub(/["'"'"']/,"",$2); print $2}'`); add `bash -n` / `shellcheck` of the step to Track A CI; prove with a **real** green run (Y3) |
| **V-2** | Medium | Guard fails open: any `helm pull` error is treated as "new version" and pushes | Treat only an explicit `not found` as new; any other pull error must **fail** the job |
| **V-3** | Medium | Ephemeral containers bypass the allowlist (`pods/ephemeralcontainers` not matched) | Add `pods/ephemeralcontainers` to `resourceRules` (operation `UPDATE`); re-test with the subresource dry run |
| V-4 | Low | R-0 not evidenced (force-push and deletion rejection on a throwaway branch) | Owner: run it on a throwaway protected branch, or record the rule settings (authenticated API / UI) in the report |
| V-5 | Low | Audit-first rollout skipped for the new VAP | Record as a deviation; keep the staged rollout for future admission policies |
| V-6 | Low | Smoke asserts "denied", not "denied by `tenant-image-registry-allowlist`" | Match the policy name in the denial message (as drill guidance in 0.5 will require) |
| V-7 | Info | O-1's PR-only mode for `tenant-workloads`/`platform-charts` is not yet active; direct pushes went through after protection | Expected until Track A provides checks; switch on with A.4 |
| V-8 | Info | Evidence discipline: 0.2's evidence was not produced by the committed workflow | Reports should include the real Actions run result for CI changes |
| V-9 | Info | Pinned Action versions target Node.js 20 (deprecated; forced to Node 24) | Pin current majors (e.g. `actions/checkout` v5+) by SHA in a follow-up |

---

## 3. Status of Track 0 (early-authorized part)

| Step | Status |
|---|---|
| 0.1 | ✅ Validated (V-4, V-7 open as observations) |
| 0.2 | ❌ **Not validated**: fix V-1 and V-2, then a real green run (unchanged chart → "skip"; modified chart without bump → red) |
| 0.3 | ✅ Validated; **V-3 to be fixed** (small change, prod via the next catalog tag) |
