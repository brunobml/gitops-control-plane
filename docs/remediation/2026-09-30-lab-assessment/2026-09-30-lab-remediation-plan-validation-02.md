# Remediation Validation — Run #02 (2026-09-30)

| | |
|---|---|
| **Validates** | [`2026-09-30-lab-remediation-plan-implemented-02.md`](2026-09-30-lab-remediation-plan-implemented-02.md) (commit `a640184`, pushed to `origin/main`) |
| **Against** | [Validation #01](2026-09-30-lab-remediation-plan-validation-01.md) observations V-1 to V-9, plan [v3.0](2026-09-30-lab-remediation-plan.md), [review](2026-09-30-lab-remediation-plan.md#review--approval-sign-off) conditions C1–C3 |
| **Method** | Independent checks against the live clusters, Git, and the changed scripts and docs. The report's own output was not relied on. |
| **Changes made by this validation** | None. Script and cluster checks used guard-only paths, `--dry-run=server`, and `make -n`. |

## Verdict

> ### ✅ VALIDATED — LOW-SEVERITY REMEDIATION SCOPE CLOSED
>
> - All nine Validation #01 observations are resolved. V-6 is accepted as a deliberate decision, but the rationale recorded for it is factually wrong (W-2).
> - All Run #01 runtime outcomes still hold: tokens, annotations, promotion gate, workload hardening, PDB and application health.
> - The implementation report is now an accurate audit record: its traceability matrix matches the assessment IDs.
>
> Four new observations (W-1 to W-4) are **Low/Info**. None needs another implementation run; they can be folded into the next routine change.
>
> **The remaining open work is the High/Critical track**, starting with L4-1 (Headlamp), L3-1 (ACK resync), L3-5 (immutable CI tags) and L2-2 (app promotion gate).

---

## 1. Validation #01 observations: closure check

| ID | Observation | Independent check | Result |
|---|---|---|:-:|
| **V-1** | Traceability matrix mislabelled | Compared each row of the report's §2 with the assessment's tables | ✅ All 10 IDs match the assessment (L1-2 CRD, L1-3 containers, L1-5 docs, L1-6 paths, L2-7 secret, L3-8 deferred, L4-10 tokens, L4-11 hardening, L4-1 open). The promotion gate is correctly attributed to L4-11. |
| **V-2** | Docs still stale | `git grep -nE 'tenant-a\|MessageProcessor\|5 replicas'` on README and tutorial; read the README diagram (lines 26–38) and the tutorial (lines 28–70) | ✅ 0 matches. README shows `orders-dev` 1 / `orders-test` 1 / `orders-prod` 2 replicas; tutorial shows 2 prod replicas and the `orders-processor/deploy/values-*.yaml` layout. All match the live cluster. |
| **V-3** | C1 implemented as a warning | `git diff 5ac95f2 a640184 -- scripts/register-spokes.sh` | ✅ The warning branch is replaced with `exit 1` before the legacy-delete step. |
| **V-4** | Runbook overstated rotation; promotion minted tokens | Read `scripts/promote-blueprints.sh` and runbook §6; ran a server-side dry run of its annotate call; ran the guard with an unknown spoke | ✅ The script only `kubectl annotate`s `blueprints-revision`, with no token issued and no `last-applied` written. The dry run returns `v1.1.0`. An unknown spoke exits 1. Runbook §6.1 now says old tokens stay valid until expiry. ℹ️ The guard is silent (W-1). |
| **V-5** | Leftover `headlamp-admin-token` | Counted `kubernetes.io/service-account-token` Secrets on **all** namespaces of all 3 clusters; listed SAs in `headlamp` | ✅ **0 / 0 / 0.** SA `headlamp-admin` is gone (only `default` and `headlamp` remain). |
| **V-6** | `PYTHONDONTWRITEBYTECODE` in platform RGD | Read the report's rationale and **tested it**: Python 3 imported a module from a read-only directory | ✅ Accepted as a deliberate decision. ⚠️ The recorded rationale is incorrect (W-2). |
| **V-7** | WA guide rows removed | `grep` the guide | ✅ *Non-Root Container Execution* (line 95) and *Linux Capability Dropping* (line 96) are restored. |
| **V-8** | Make targets relative to the current directory | `cd /tmp && make -n -f …/Makefile rotate-spoke-tokens promote-blueprints test` | ✅ All targets expand to absolute `$(ROOT_DIR)/…` paths. `push`, `setup`, `bootstrap` and `teardown` are anchored too. |
| **V-9** | "Headlamp Decoupling" overstated | Read the report's §3.1 and its matrix | ✅ Reworded to "credential refresh". **L4-1 is listed as ⚠️ Open (Critical)**, with the reason stated. |

---

## 2. Regression check on Run #01 outcomes

| Outcome | Check | Result |
|---|---|:-:|
| No legacy SA-token Secrets | Field-selector count across all namespaces, all clusters | ✅ 0 / 0 / 0 |
| No plaintext `last-applied` | Annotation byte length on both cluster Secrets and `headlamp-kubeconfig`; scanned **every** hub Secret for a `last-applied` that contains `data`/`stringData` | ✅ 0 / 0 / 0; no hub Secret matches |
| Argo CD ↔ spokes | `argocd cluster list` | ✅ `spoke-nonprod`, `spoke-prod` and `in-cluster` all `Successful` |
| Applications | Sync, health and revision | ✅ 7/7 Synced/Healthy; both blueprint apps at `5dc0dfa`; root at `a640184` |
| Promotion source of truth | `clusters/blueprint-revisions.env` vs Secret annotations | ✅ `main` / `v1.1.0` on both sides; `lab/token-expires=2026-10-31` |
| Workloads | Pods, readiness, restarts, SA | ✅ dev 1, test 1, prod 2; all Ready, 0 restarts; `orders-*-sa` |
| PDB | `orders-prod` | ✅ `orders-prod-pdb` minAvailable 1, allowed disruptions 1; none in dev or test |

---

## 3. New observations

| ID | Sev | Observation | Evidence | Recommended fix |
|---|---|---|---|---|
| **W-1** | Low | **The fail-closed guard fails silently.** In both `promote-blueprints.sh` and `register-spokes.sh`, `bp_rev=$(grep … \| cut …)` runs under `set -euo pipefail`. When the spoke key is missing, `grep` exits 1, the assignment fails, and the script exits **before** reaching `: "${bp_rev:?…}"`. The behaviour is still safe (exit 1, nothing written), but the operator sees no error message, only a bare non-zero exit. The message only appears when the key is present but empty. | `bash -x scripts/promote-blueprints.sh spoke-bogus` ends at `+ bp_rev=` with exit 1 and no diagnostic | `bp_rev=$(grep -E "^${spoke}=" "$REVISIONS_FILE" \| cut -d= -f2 \|\| true)` in both scripts, so the `:?` guard is what fails, with its message. |
| **W-2** | Info | **The V-6 rationale is factually wrong.** The report says that with a read-only root FS, Python's `.pyc` writes "fail unless bytecode writing is disabled". CPython skips cache writes it can't make, silently. I ran a module import from a `chmod 555` directory: the import succeeded, exit 0, no `__pycache__`, no error. The env var is harmless, but the recorded reason will mislead future readers into thinking it's required. | Local reproduction in a temporary directory, removed afterwards | Reword to "kept to avoid futile write attempts and keep images reproducible; not required for correctness", or remove it at the next blueprint release. |
| **W-3** | Info | **The tutorial misstates how routing works.** It says the platform "uses folder names and Helm values to make decisions" and that `values-dev.yaml` "automatically routes" to `spoke-nonprod`. In fact routing comes from the `tenant-workloads-nonprod`/`-prod` **ApplicationSet List elements** (`env` → `destination.name`). A new engineer adding `values-staging.yaml` would expect it to deploy, and nothing would happen. | `docs/developer-tutorial.md` lines 66–70 vs `applicationsets/tenant-workloads-*.yaml` | One sentence: "routing is declared in `applicationsets/tenant-workloads-*.yaml`; the file name is only referenced from there." |
| **W-4** | Info | **`make promote-blueprints` reads the working copy, not Git.** It promotes whatever is in the local `clusters/blueprint-revisions.env`, committed or not. The §6.3 runbook orders it correctly (commit and push first), but nothing enforces that order. A local edit could promote prod with no Git record, which defeats S1. | `scripts/promote-blueprints.sh` has no Git check | Add a preflight: `git diff --quiet HEAD -- clusters/blueprint-revisions.env && git merge-base --is-ancestor HEAD @{u}` or abort with "commit and push revisions first". |

---

## 4. Still open (carried forward, not defects in this run)

- **Promotion gate under divergence is still unproven.** `main` and `v1.1.0` are both `5dc0dfa`. On the next `platform-catalog` commit to `main`, confirm that `kro-blueprints-spoke-prod` stays at `5dc0dfa` while non-prod advances.
- **Token expiry is 2026-10-31 at about 01:00 UTC.** Run `make rotate-spoke-tokens` before then. Nothing alerts on expiry (assessment L3-3).

---

## 5. Final closure status: plan v3.0 scope

| Finding | Status |
|---|:-:|
| B1, B2 (review blockers) | ✅ Closed |
| L1-2 Orphaned CRD | ✅ Closed |
| L1-3 Stray containers (+ `headlamp-admin` leftover) | ✅ Closed |
| L1-5 Docs vs reality (added in step 4) | ✅ Closed (W-3 wording nit) |
| L1-6 Hard-coded paths | ✅ Closed |
| L2-7 Duplicate repo secret | ✅ Closed |
| L3-8 Imperative controller install | ⏸ Deferred to Rec 9 (by design) |
| L4-10 Long-lived SA tokens | ✅ Closed |
| L4-11 Workload SA / PSS / PDB | ✅ Closed (W-2 rationale nit) |
| L4-1 Headlamp cluster-admin gateway (Critical) | ⚠️ Open (High/Critical track, as planned) |

**Validation closed.** No further implementation run is needed for the low-severity plan. W-1 and W-4 are two-line script changes; fold them into the first High/Critical change set.
