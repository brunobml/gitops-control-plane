# Remediation Validation — Run #03 (2026-09-30)

> **Status: Historical.** Record of the 2026-09-30 assessment and its remediation (Phases 1–5, closed 2026-10-03). Kept as evidence and not updated. For the lab as it is today, see the [README](../../../README.md) and the [2026-10-03 assessment](../../assessments/2026-10-03-lab-assessment.md).

| | |
|---|---|
| **Validates** | [`2026-09-30-lab-remediation-plan-implemented-03.md`](2026-09-30-lab-remediation-plan-implemented-03.md) (commits `55c01fc`, `34f0125`, pushed to `origin/main`) |
| **Against** | [Validation #02](2026-09-30-lab-remediation-plan-validation-02.md) observations W-1 to W-4; regression check of all earlier outcomes (plan [v3.0](2026-09-30-lab-remediation-plan.md), C1–C3, V-1 to V-9) |
| **Method** | Independent checks against the live clusters and Git. W-4 was exercised in a disposable clone with a local bare remote (scratchpad, removed afterwards). W-1 was exercised with a non-existent spoke name, so it failed before any cluster write. |
| **Changes made by this validation** | None to the lab or the repository. |

## Verdict

> ### ✅ VALIDATED — FINAL. Low-severity remediation is closed.
>
> All four Validation #02 observations are resolved and behave as described. Every outcome from Runs #01 and #02 still holds on the live clusters. `implemented-03.md` is accurate and can stand as the **audit record of record** for plan v3.0.
>
> One new **Info** item (X-1) was found: the promotion preflight accepts a revision pushed to a non-`main` branch. It does not block closure.
>
> **Validation cycle closed. No further implementation runs are needed for the Low-severity scope.**

---

## 1. Validation #02 observations: closure check

| ID | Observation | Independent check | Result |
|---|---|---|:-:|
| **W-1** | Guard failed silently on a missing key | Ran `scripts/promote-blueprints.sh spoke-bogus` on the live repo. Ran the `register-spokes.sh` guard line on its own against a file that lacks `spoke-prod` | ✅ Both print `bp_rev: no blueprints-revision for <spoke> in clusters/blueprint-revisions.env` and exit 1. `|| true` is present in both scripts (`promote-blueprints.sh:36`, `register-spokes.sh:65`). |
| **W-2** | V-6 rationale incorrect | Read `implemented-02.md` §3.1 V-6 | ✅ Now says CPython "silently ignores bytecode write failures on read-only filesystems and continues", and that the variable is kept as a hygiene choice. This is accurate. |
| **W-3** | Tutorial misstated routing | `git diff a640184 55c01fc -- docs/developer-tutorial.md` | ✅ Routing is now attributed to `applicationsets/tenant-workloads-{nonprod,prod}.yaml`, with relative links. Values files are described as *referenced by* each ApplicationSet entry. |
| **W-4** | Promotion could run from an unrecorded edit | Six scenarios in a disposable clone (table below) | ✅ All the cases it was meant to catch are blocked. ℹ️ One gap (X-1). |

### W-4 preflight scenarios

| # | Repository state | Expected | Observed |
|---|---|---|:-:|
| a | Clean, pushed to upstream `main` | Pass preflight | ✅ Passed; stopped at the W-1 guard (bogus spoke) |
| b | Unstaged edit to `blueprint-revisions.env` | Block | ✅ `Uncommitted changes … Commit and push first.` |
| c | Edit committed but not pushed | Block | ✅ `Local commits not pushed to upstream branch.` |
| d | Edit staged only | Block | ✅ `Uncommitted changes …` |
| e | Edit committed and **pushed to a feature branch** | Block (not on `main`) | ⚠️ **Passed preflight** (X-1) |
| f | Detached HEAD | Block | ✅ Blocked (the message says "not pushed", which is slightly misleading but safe) |

---

## 2. Regression check (Runs #01–#02 outcomes)

| Outcome | Live result | |
|---|---|:-:|
| Legacy `service-account-token` Secrets | 0 on hub / spoke-nonprod / spoke-prod (all namespaces) | ✅ |
| `last-applied-configuration` on credential Secrets | 0 B on `cluster-spoke-nonprod`, `cluster-spoke-prod`, `headlamp-kubeconfig` | ✅ |
| Cluster Secret annotations vs Git | `main` / `v1.1.0` on both sides; `lab/token-expires=2026-10-31` | ✅ |
| Tags on GitHub | `v1.0.0^{}` → `a8825b2`, `v1.1.0^{}` → `5dc0dfa` | ✅ |
| Argo CD cluster connectivity | `spoke-nonprod`, `spoke-prod`, `in-cluster`: Successful | ✅ |
| Applications | 7/7 Synced/Healthy, no conditions; both blueprint apps at `5dc0dfa` | ✅ |
| Workloads | dev 1 / test 1 / prod 2 pods; all Ready; 0 restarts; `orders-*-sa`; volumes = `tmp` only | ✅ |
| PSS `restricted` (server dry run) | Clean on `orders-dev`, `orders-test`, `orders-prod` | ✅ |
| PDB | `orders-prod-pdb` only; none on spoke-nonprod | ✅ |
| Orphaned CRD | NotFound on both spokes | ✅ |
| Hard-coded paths | `git grep` → 0 matches | ✅ |
| Cloud resources | 6 queues in moto (3 queues + 3 DLQs) | ✅ |

> ℹ️ `root-control-plane` reports revision `a640184` while `origin/main` is at `34f0125`. The two newer commits (`55c01fc`, `34f0125`) are 2–12 minutes old and change only `docs/` and `scripts/`, nothing under the app's path `applicationsets/`. This is ordinary poll timing (the default is 3 minutes) with no manifest change, not drift.

---

## 3. New observation

| ID | Sev | Observation | Recommended fix |
|---|---|---|---|
| **X-1** | Info | **The promotion preflight doesn't require `main`.** `merge-base --is-ancestor HEAD @{u}` checks that HEAD is pushed to *its own* upstream. A revision committed on a feature branch and pushed to `origin/feature` passes (scenario e), so prod could be promoted from a commit that was never reviewed or merged. The single-source-of-truth intent (S1) is "what's on `main`". | Replace the second check with `git -C "$REPO_DIR" fetch -q origin main && git -C "$REPO_DIR" merge-base --is-ancestor HEAD origin/main`, and optionally reject a branch other than `main`: `[[ $(git -C "$REPO_DIR" branch --show-current) == main ]]`. This is a two-line change; fold it into the first High/Critical change set. |

---

## 4. Audit trail for plan v3.0 (complete)

| Document | Role | Outcome |
|---|---|---|
| [Assessment](../../assessments/2026-09-30-lab-assessment.md) | Findings baseline | 7 Low findings in scope, plus L1-5 added |
| [Plan v3.0 (with Review Sign-Off)](2026-09-30-lab-remediation-plan.md#review--approval-sign-off) | Design and authorization | Green light with C1–C3 (after blockers B1/B2 in v2.1) |
| [Implemented-01](2026-09-30-lab-remediation-plan-implemented-01.md) / [Validation-01](2026-09-30-lab-remediation-plan-validation-01.md) | Execution | Runtime validated; V-1 to V-9 raised |
| [Implemented-02](2026-09-30-lab-remediation-plan-implemented-02.md) / [Validation-02](2026-09-30-lab-remediation-plan-validation-02.md) | Corrections | V-1 to V-9 closed; W-1 to W-4 raised |
| [Implemented-03](2026-09-30-lab-remediation-plan-implemented-03.md) / **Validation-03** | Hardening | W-1 to W-4 closed; X-1 (Info) raised; **cycle closed** |

### Final status by finding

| Finding | Status |
|---|:-:|
| B1, B2 (review blockers) | ✅ Closed |
| L1-2, L1-3, L1-5, L1-6, L2-7 | ✅ Closed |
| L4-10 Long-lived SA tokens | ✅ Closed |
| L4-11 Workload SA / PSS / PDB | ✅ Closed |
| L3-8 Imperative controller install | ⏸ Deferred to Recommendation 9 (by design) |
| L4-1 Headlamp cluster-admin gateway (**Critical**) | ⚠️ Open (High/Critical track) |

---

## 5. Carry-forward items

1. **Token expiry on 2026-10-31 at about 01:00 UTC.** Run `make rotate-spoke-tokens` beforehand. Nothing alerts on this (assessment L3-3).
2. **Promotion gate under divergence is still unobserved.** `main` and `v1.1.0` are both `5dc0dfa`. On the next `platform-catalog` commit to `main`, confirm `kro-blueprints-spoke-prod` stays at `5dc0dfa`.
3. **X-1:** pin the promotion preflight to `origin/main`.
4. **High/Critical track:** L4-1 (Headlamp: drop shared `argocd-manager` tokens, read-only per-cluster SAs, authentication), L3-1 (ACK resync 10 h → 5 min), L3-5 (immutable CI tags), L2-2 (application promotion gate and sync windows).
