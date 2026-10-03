# Remediation Validation — Run #01 (2026-09-30)

| | |
|---|---|
| **Validates** | [`2026-09-30-lab-remediation-plan-implemented-01.md`](2026-09-30-lab-remediation-plan-implemented-01.md) (commit `5ac95f2`) |
| **Against** | Plan [v3.0](2026-09-30-lab-remediation-plan.md) and its [review](2026-09-30-lab-remediation-plan.md#review--approval-sign-off) (green light with conditions C1–C3) |
| **Method** | Independent checks against the live clusters, Git (local and `origin`), and the changed scripts and docs. The implementation report's own output was **not** relied on. |
| **Changes made by this validation** | None. All checks were read-only. |

## Verdict

> ### ✅ VALIDATED WITH OBSERVATIONS
>
> Every **security-critical and runtime outcome** of plan v3.0 was confirmed independently:
> - The leaked legacy tokens are gone.
> - No plaintext token annotations remain.
> - The new tokens are TokenRequest-bound (720 h).
> - The promotion gate is wired and prod runs the tagged hardened blueprint.
> - All 4 workload pods meet PSS `restricted`.
> - The PDB is present only in prod.
> - kro, ACK and moto are intact, and all 7 Applications are Synced/Healthy.
>
> The **implementation report** is not accurate enough to serve as the audit record yet:
> - Its findings matrix assigns the wrong assessment IDs to 5 of 8 rows (V-1).
> - It claims the documentation sync is complete, but stale content remains (V-2).
> - The C1 safety condition was implemented as a warning rather than a stop (V-3).
>
> None of these affects the running system. Fix V-1 to V-5 in a follow-up commit. No re-execution of the plan is needed.

---

## 1. Claim-by-claim validation

### Step 0: token rotation and secret scrub (B1, B2, C1, C3)

| Report claim | Independent check | Result |
|---|---|:-:|
| Legacy `argocd-manager-token` deleted on both spokes | Searched **all** `kubernetes.io/service-account-token` Secrets on both spokes for `argocd-manager`/`headlamp` | ✅ None remain. The tokens exposed during the v2.0 review are invalidated |
| `headlamp/headlamp-token` deleted | Same search on the hub | ✅ Gone. ⚠️ A different legacy Secret, `headlamp-admin-token`, remains (V-5) |
| `last-applied-configuration` absent (C3) | Annotation byte length on `cluster-spoke-nonprod`, `cluster-spoke-prod`, `headlamp-kubeconfig` | ✅ 0 / 0 / 0 |
| 30-day TokenRequest tokens | Decoded JWT **claims only** (`exp - iat`, secret binding) | ✅ 720 h on both spokes; not bound to any Secret (TokenRequest); expire `2026-10-31T01:02Z` / `01:15Z` |
| Expiry annotation (S2) | `lab/token-expires` on the cluster Secrets | ✅ `2026-10-31` on both |
| Staggered with verification before delete (C1) | Read `scripts/register-spokes.sh` | ⚠️ The order is right, but a failed check only **warns and proceeds** with the delete (V-3) |
| `argocd cluster list` Successful | Argo CD Applications reconcile against both spokes with current revisions | ✅ Both spokes are being reconciled (see Step 5–7) |

### Steps 1–2: cleanup

| Report claim | Check | Result |
|---|---|:-:|
| `messageprocessors.kro.run` deleted on both spokes | `kubectl get crd` | ✅ NotFound on both |
| Stray containers removed | `docker ps -a` | ✅ None |
| `repo-ghcr-charts` deleted | Repository-type Secrets on the hub | ✅ Only `argocd-repo-ghcr-charts` and `argocd-repo-headlamp` (both Helm-managed) |
| All 7 apps have no conditions | `.status.conditions` | ✅ `<none>` on all 7 |

### Steps 3–4: portability and docs

| Report claim | Check | Result |
|---|---|:-:|
| Zero hard-coded paths | `git grep -nE 'file:///\|/home/bleit[e]' -- ':!docs/assessments' ':!docs/remediation'` | ✅ 0 matches |
| Makefile anchored with `ROOT_DIR`/`REPOS_DIR` | `git diff 9571f2f HEAD -- Makefile` | ✅ `build-app` uses `$(REPOS_DIR)`. ℹ️ The new target uses paths relative to the current directory (V-8) |
| Tutorial updated to `orders-*` names and **2 prod replicas** | `grep` for stale terms | ❌ **Partial.** `docs/developer-tutorial.md:32` still says "Prod Worker Pods (5 replicas)", and lines 62–66 still say `tenant-a-dev/test/prod` namespaces (V-2) |
| README updated (5 repos, `orders-*` names) | `grep` README | ❌ **Partial.** The mermaid diagram (lines 29–36) still shows `tenant-a-dev` (1), `tenant-a-test` (**2**), `tenant-a-prod` (**5**). The live values are `orders-dev` 1, `orders-test` 1, `orders-prod` 2 (V-2) |

### Steps 5–7: promotion gate and blueprint hardening

| Report claim | Check | Result |
|---|---|:-:|
| `v1.0.0` → `a8825b2`, `v1.1.0` → `5dc0dfa`, pushed | `git ls-remote --tags origin` (peeled `^{}`) | ✅ Both annotated tags exist on GitHub and point at the stated commits |
| `5dc0dfa` on `platform-catalog@origin/main` | `git ls-remote origin refs/heads/main` | ✅ |
| Single source of truth (S1) | `clusters/blueprint-revisions.env` in Git | ✅ `spoke-nonprod=main`, `spoke-prod=v1.1.0`, matching the Secret annotations |
| Fail-closed guard (C2) | Ran the guard snippet in isolation for a present key, an empty value, and a missing key | ✅ Resolves `main`; **fails** for empty and missing values |
| AppSet wired to the annotation | `kro-blueprints` spec plus generated apps | ✅ nonprod `targetRevision=main`, prod `targetRevision=v1.1.0`. Both are at `5dc0dfa`, Synced/Healthy |
| Dedicated SA, automount off (N1) | Every worker pod and its SA | ✅ `orders-{dev,test,prod}-sa`, pod and SA `automount=false`, volumes = `tmp` only (no `kube-api-access`) |
| seccomp + read-only root FS | Pod spec | ✅ `RuntimeDefault`, `readOnlyRootFilesystem=true` on all 4 pods; 0 restarts, all Ready |
| PSS `restricted` (dry run) | `label --dry-run=server … enforce=restricted` on **all three** namespaces (the report checked dev and prod only) | ✅ Clean on `orders-dev`, `orders-test`, `orders-prod` |
| Conditional PDB (R1) | `get pdb` | ✅ None in dev or test (1 replica). `orders-prod-pdb` has `minAvailable=1` and `disruptionsAllowed=1` |
| Cloud resources intact after rollout | kro `QueueBackedService`, ACK `Queue` conditions, moto | ✅ 3× `ACTIVE/Ready`; 6× `ResourceSynced=True`; 6 queues in moto |
| Endpoints reachable | HTTP via the Traefik hosts | ✅ orders-dev/test/prod, Headlamp and Argo CD all return 200 |

### Step 8: documentation

| Report claim | Check | Result |
|---|---|:-:|
| WA guide updated (TokenRequest, EKS target, SA, PSS, gates, PDB) | `git show ea67e93` | ✅ All six topics added. ℹ️ The *Non-Root Container Execution* and *Linux Capability Dropping* rows were removed (V-7) |
| `make rotate-spoke-tokens` added | Makefile | ✅ Present (see V-4, V-8) |

---

## 2. Observations

| ID | Sev | Observation | Recommended fix |
|---|---|---|---|
| **V-1** | **Medium** | **The findings matrix in the implementation report mislabels assessment IDs.** Against the assessment: **L1-2** is the orphaned CRD (the report says "promotion gate"); **L1-3** is the stray containers (report: duplicate secret, which is L2-7); **L2-7** is the duplicate secret (report: SA hardening, which is L4-11); **L3-8** is extensibility, deferred (report: PDB, which is part of L4-11); **L4-11** is workload hardening (report: tutorial, which is L1-5). The work was done; the traceability is wrong. That matters because this file is the audit record that closes the findings. | Rebuild §2 from the assessment table. Add rows for **L1-5** (tutorial, Medium, partial per V-2) and **L3-8** (deferred to Rec 9). Record the promotion gate as part of L4-11's staged rollout (and a down payment on L2-2/L3-6), not as L1-2. |
| **V-2** | **Medium** | **Documentation sync is incomplete, but the report says it is done.** The tutorial still shows 5 prod replicas and `tenant-a-*` namespaces. The README diagram still shows `tenant-a-*` with 1/2/5 replicas. This is the onboarding defect (assessment L1-5) that step 4 was meant to close. | Fix `developer-tutorial.md` lines 32 and 62–66 and README lines 29–36. Change the report's step 4 status to "partial" until then. |
| **V-3** | Low | **C1 is implemented as a warning, not a stop.** In `register-spokes.sh`, if `argocd cluster list` doesn't return `Successful` (for example the CLI isn't logged in, or the token is bad), the script prints a warning, checks only that the Secret *exists*, and then deletes the legacy token anyway. During this run that happened to be safe. The legacy Secrets are now gone, so the delete is a no-op in future. But the same script backs `make rotate-spoke-tokens` and will report success even when Argo CD can't reach the spoke. | Replace the warning branch with `exit 1` (“cluster not reachable with new token; aborting”). Optionally drop the legacy-delete block now that B2 is complete. |
| **V-4** | Low | **The runbook overstates what rotation does, and promotion mints credentials.** §6.1 says rotation "deletes old tokens". TokenRequest tokens **can't be deleted**: each old token stays valid until it expires (or the SA is recreated, per §6.2). §6.3 promotes prod by rerunning `register-spokes.sh spoke-prod`, so **every promotion issues another 30-day cluster-admin token** while the earlier ones stay valid. | Correct the wording in §6.1. Add a `--annotate-only` mode (or a separate `promote-blueprints.sh`) that sets `blueprints-revision` from the env file **without** issuing a token, and use it in §6.3. |
| **V-5** | Low | **One more legacy token Secret: `headlamp/headlamp-admin-token`** (ServiceAccount `headlamp-admin`, created `2026-09-30T19:51:23Z`, during the early Headlamp debugging that also produced the stray containers). It is long-lived, but the SA has **no** RoleBindings or ClusterRoleBindings (verified: it can do nothing beyond self-review and discovery). Its `last-applied-configuration` holds no data. The assessment, the plan and the implementation all missed it. | `kubectl --context k3d-hub-cluster -n headlamp delete secret headlamp-admin-token sa headlamp-admin`. Add the check "no `service-account-token` Secrets on any cluster" to the verification checklist. |
| **V-6** | Info | **Deviation from review guidance:** `PYTHONDONTWRITEBYTECODE` was added to the platform RGD. R10/N7 said to keep runtime-specific settings out of the platform contract (and the variable isn't needed by this app). It's harmless today, but every future non-Python tenant inherits it. | Remove it from the RGD at the next blueprint release, or record it as a deliberate decision. |
| **V-7** | Info | The WA guide removed the *Non-Root Container Execution* and *Linux Capability Dropping* rows. Both controls are still in place (UID 10001, `drop: [ALL]`), so the guide now under-documents them. | Restore both rows. |
| **V-8** | Info | `make rotate-spoke-tokens` calls `scripts/…` and `addons/…` relative to the current directory, so it breaks under `make -f ../gitops-control-plane/Makefile`. That is the case L1-6 fixed for `build-app`. | Prefix with `$(ROOT_DIR)/`. |
| **V-9** | Info | The heading "Headlamp Decoupling" in the report overstates the change. Headlamp now has its own hub token, but it **still reuses Argo CD's `argocd-manager` spoke tokens** and is still `cluster-admin` everywhere. Assessment **L4-1 (Critical) remains open**, and the plan's scope framing says so correctly. | Rename to "Headlamp credential refresh" and add a line that L4-1 is still open. |

---

## 3. Not yet provable (follow-up check)

**The promotion gate has not been exercised under divergence.** Today `main` and `v1.1.0` resolve to the same commit (`5dc0dfa`), so "prod does not follow `main`" is wired correctly but not yet observed. On the next `platform-catalog` commit to `main`, confirm:

```bash
kubectl --context k3d-hub-cluster -n argocd get app kro-blueprints-spoke-nonprod kro-blueprints-spoke-prod \
  -o custom-columns=APP:.metadata.name,REV:.status.sync.revision
# expected: nonprod = new SHA, prod = 5dc0dfa…
```

**Token expiry: 2026-10-31 ~01:00 UTC.** After that, Argo CD loses both spokes and Headlamp loses all three clusters unless `make rotate-spoke-tokens` runs first. Nothing alerts on this (assessment L3-3), so put it in a calendar.

---

## 4. Closure status of plan v3.0 scope

| Finding | Assessment description | Status after Run #01 |
|---|---|:-:|
| L1-2 | Orphaned `messageprocessors` CRD | ✅ Closed |
| L1-3 | Stray Headlamp containers | ✅ Closed (V-5 is a related leftover) |
| L1-5 *(Medium, added by plan step 4)* | Docs disagree with reality | ⚠️ Partial (V-2) |
| L1-6 | Hard-coded personal paths | ✅ Closed (V-8 minor) |
| L2-7 | Duplicate Helm repo secret | ✅ Closed |
| L3-8 | Imperative controller install | ⏸ Deferred to Rec 9 by design |
| L4-10 | Long-lived SA token Secrets | ✅ Closed for `argocd-manager`/`headlamp`; V-5 leftover; V-4 runbook fix |
| L4-11 | Workload SA / PSS / PDB | ✅ Closed (V-6 deviation noted) |
| (review) B1/B2 | Leaked tokens and plaintext annotation | ✅ Closed |

**Next:** a small follow-up commit for V-1 to V-5 (docs, script `exit 1`, an annotate-only promotion path, and deleting one Secret and its ServiceAccount). After that the open items are the High/Critical track, starting with L4-1 (Headlamp), L3-1 (ACK resync) and L3-5 (immutable CI tags).
