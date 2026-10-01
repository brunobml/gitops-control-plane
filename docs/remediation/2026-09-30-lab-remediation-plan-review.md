# Remediation Plan Review — 2026-09-30

| | |
|---|---|
| **Reviewed** | [`2026-09-30-lab-remediation-plan.md`](2026-09-30-lab-remediation-plan.md) **v3.0** (commit `9571f2f`) |
| **Review history** | v1.0 → `cb60a30` · v2.0 → `af49e63` · v2.1 → `8f28867` (conditional; blockers B1/B2) · **v3.0 → this review** |
| **Against** | [`../assessments/2026-09-30-lab-assessment.md`](../assessments/2026-09-30-lab-assessment.md), the live clusters, and the five lab repositories |

## Authorization decision

> ### ✅ GREEN LIGHT: v3.0 is authorized for implementation, all steps 0–8.
>
> There are no blocking findings. Both v2.1 blockers are resolved:
> - **B1:** the `last-applied-configuration` annotation is stripped before the server-side apply.
> - **B2:** the legacy token Secrets are deleted, and the script no longer recreates them.
>
> All other review points are resolved. The three implementation conditions below (C1–C3) are **small adjustments to apply while executing**. They don't need another review cycle.
>
> **Start with step 0.** It invalidates the `argocd-manager` tokens exposed during the v2.0 review session, which are still valid today.

---

## 1. Status of v2.1 review points

| Point | Topic | Status in v3.0 |
|---|---|:-:|
| **B1** | `apply --server-side` keeps the existing annotation | ✅ Resolved: annotation stripped first, then `--server-side --force-conflicts`; also covers `headlamp-kubeconfig` |
| **B2** | Leaked legacy tokens stay valid | ✅ Resolved: Secret removed from the heredoc, legacy Secrets deleted (spokes and `headlamp-token`), CA read from kubeconfig |
| S1 | Prod promotion by `kubectl annotate` → silent rollback | ✅ Resolved: `clusters/blueprint-revisions.env` is the single source of truth; promotion is a commit. See C2 for one gap |
| S2 | 30-day expiry → silent outage | ✅ Resolved: `lab/token-expires` annotation + `make rotate-spoke-tokens` |
| S3 | L4-10 "defer" vs "adopt" wording | ✅ Resolved |
| M1 | `argocd` CLI not logged in | ✅ Resolved |
| M2 | Rotate non-prod first | ✅ Resolved in §3. The step table orders it differently: see C1 |
| M3 | L4-1 double-counting | ✅ Resolved: scope framing says step 0 partly completes L4-1 |
| v1/v2 points (R1–R14, N1–N13) | — | ✅ All remain resolved in v3.0; no regressions found |

---

## 2. Implementation conditions (non-blocking, apply while executing)

**C1. Step 0: rotate first, delete second, one spoke at a time.**
§3 gives the correct order: new token → verify → delete legacy. The §4 table lists "Delete legacy `argocd-manager-token` Secrets" *first*. Deleting first takes Argo CD's access to both spokes away until re-registration succeeds, and if the script fails halfway, prod is unmanaged. Run it per spoke:

```
spoke-nonprod: register (TokenRequest) → argocd cluster list = Successful → delete legacy Secret
spoke-prod:    register (TokenRequest) → argocd cluster list = Successful → delete legacy Secret
then:          setup-credentials.sh → Headlamp shows all 3 clusters
```

**C2. Make `register-spokes.sh` fail closed if the revision is missing.**
If a spoke has no entry in `clusters/blueprint-revisions.env` (for example a typo or a newly added spoke), the annotation is written empty. `'{{metadata.annotations.blueprints-revision}}'` then renders `""`, and Argo CD falls back to the default branch, so **prod would silently track `main`**. This is the failure the gate exists to prevent. Add a guard:

```bash
rev=$(grep -E "^${spoke}=" "${REPO_ROOT}/clusters/blueprint-revisions.env" | cut -d= -f2)
: "${rev:?no blueprints-revision for ${spoke} in clusters/blueprint-revisions.env}"
```

Step 0 runs before the env file exists (it's created in 5b). Either create the file in step 0, or let the guard apply only once 5c wires up the AppSet. Creating the file in step 0 is simpler.

**C3. Verification #2 should check that the annotation is gone, on all three Secrets.**
Today it greps `cluster-spoke-prod` for `bearerToken`. That misses `cluster-spoke-nonprod`. It also can't detect `headlamp-kubeconfig`: that Secret is built with `--from-file`, so its annotation holds **base64** `data`, where the string `bearerToken` never appears. Check that the annotation is absent instead:

```bash
for s in argocd/cluster-spoke-nonprod argocd/cluster-spoke-prod headlamp/headlamp-kubeconfig; do
  test -z "$(kubectl --context k3d-hub-cluster -n ${s%/*} get secret ${s#*/} \
    -o jsonpath='{.metadata.annotations.kubectl\.kubernetes\.io/last-applied-configuration}')" \
    && echo "OK  $s" || echo "FAIL $s"
done
```

---

## 3. Minor observations (no action required)

- **TokenRequest revocation:** tokens from `kubectl create token` can't be revoked one at a time before they expire. The only way to kill them early is to delete and recreate the ServiceAccount. Add one line about this to the step 8 write-up so the rotation runbook is complete.
- **`argocd login … --password admin123`** puts the password in shell history. It's already public (assessment L4-2), so there's no new exposure. `argocd login … --username admin` followed by an interactive prompt is a better habit.
- **`date -d "+30 days"`** is GNU-only. That's fine on WSL2, but it would break on macOS, which works against the portability goal of L1-6. A portable alternative is `date -u -d @$(( $(date +%s) + 2592000 )) +%F 2>/dev/null || date -u -v+30d +%F`.
- **v3.0 removed several explanations** that earlier versions had: the L1-3 root cause, the L3-8 target architecture, the ESO/Sealed Secrets note for L2-7, the kro DAG-edge note for N1, and the EKS-guide link for L4-10. The actions don't depend on them, but they explained *why*. Consider restoring them in an appendix so the plan still teaches.

---

## 4. Verified during this review

| Check | Result |
|---|---|
| `kubectl create token --duration=720h` on spoke-nonprod (throwaway SA `ttl-probe`, deleted afterwards) | Granted lifetime **720 h**. k3s does not cap it, so the 30-day design holds |
| `kube-system/argocd-manager-token` on both spokes | Still present, so step 0 has not run yet and is still needed |
| `platform-catalog` tags | None yet, consistent with step 5a |
| `clusters/blueprint-revisions.env` | Not yet created, consistent with step 5b (see C2) |
| `date -d "+30 days" +%Y-%m-%d` on this host | `2026-10-30`, which works under GNU date |
| Changes made by this review | One throwaway ServiceAccount, created and deleted. No lab resources changed |

---

## 5. Go / no-go checklist for the implementer

- [ ] Step 0 executed per C1: one spoke at a time, legacy Secret deleted only after `Successful`
- [ ] `clusters/blueprint-revisions.env` created and guarded per C2 before 5c is merged
- [ ] Verification #2 replaced with the C3 loop
- [ ] Each step's "Done when" column confirmed before starting the next step
- [ ] Prod promotion (step 7) uses the SHA verified in step 6, recorded in the commit that edits `blueprint-revisions.env`

**Review closed. Plan v3.0 is approved for implementation.**
