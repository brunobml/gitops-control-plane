# Remediation Plan Review — 2026-09-30

| | |
|---|---|
| **Reviewed** | [`2026-09-30-lab-remediation-plan.md`](2026-09-30-lab-remediation-plan.md) **v2.1** (commit `f04d1a4`) |
| **Review history** | v1.0 plan reviewed in `cb60a30` → v2.0 plan reviewed in `af49e63` → this review (v2.1) |
| **Against** | [`../assessments/2026-09-30-lab-assessment.md`](../assessments/2026-09-30-lab-assessment.md), the live clusters, and the five lab repositories |

## Authorization decision

> **APPROVED WITH CONDITIONS: authorized in part.**
>
> | Steps | Status |
> |---|---|
> | **1, 2, 3, 4, 5a** (cleanup, duplicate secret, portability, tutorial, baseline tag) | ✅ **Authorized now.** |
> | **5b** (cluster-Secret annotations + token scrub/rotation) | ⛔ **Not authorized as written.** Two defects (B1, B2) mean the plaintext tokens stay in the annotation and **the leaked tokens stay valid**. |
> | **5c, 6, 7** (AppSet wiring, RGD hardening, prod promotion) | ⏸ **Authorized once 5b is corrected**, because they depend on its annotations. Also apply S1 before step 7. |
> | **8** (documentation) | ✅ Authorized. It can run at any point. |
>
> The B1/B2 corrections are small text changes to §3 L4-10 and step 5b. Once they're in the plan, the remaining steps are authorized without a further full review cycle.

All three v2.0 blockers (N1 ServiceAccount assignment, N2 broken grep, N3 missing tag) are correctly fixed, and so are 9 of the 10 non-blocking items. The new blockers are both in the token-scrub step v2.1 added in response to N6. I confirmed them by testing on throwaway Secrets, not by inference.

---

## 1. Status of v2.0 review points

| Point | Topic | Status in v2.1 | Notes |
|---|---|:-:|---|
| N1 | SA never assigned to pods | ✅ Resolved | `serviceAccountName: ${serviceaccount.metadata.name}` plus pod-level `automountServiceAccountToken: false`. The DAG edge is explained. |
| N2 | Path check always passes | ✅ Resolved | Uses `git grep` with pathspecs and the `[e]` self-match guard. I re-ran it: it correctly reports the 6 remaining files and fails as it should. |
| N3 | Prod pin `v1.0.0` missing | ✅ Resolved | Step 5a tags `a8825b2` before the AppSet change. |
| N4 | Promotion via untracked Secret edit | ⚠️ Partial | "Never move tags" is adopted. Prod promotion is still "update the annotation", with the mechanism unspecified. See **S1**. |
| N5 | Rollback mechanism wrong | ✅ Resolved | Prod: repoint to the previous tag. Non-prod: revert, new GraphRevision, one poll. |
| N6 | Plaintext token in `last-applied-configuration` | ❌ **Fix doesn't work as written** | See **B1** and **B2**. |
| N7 | Dockerfile edit would overwrite the running tag | ✅ Resolved | The Dockerfile change was dropped, with the reason documented. |
| N8 | File count wording | ✅ Resolved | |
| N9 | Cross-repo relative link | ✅ Resolved | Full GitHub URL. |
| N10 | Cluster Secret naming | ✅ Resolved | `cluster-spoke-*` is used throughout. |
| N11 | Hard-refresh race | ⚠️ Partial | See **M1**: the `argocd` CLI isn't logged in, so the racy fallback is what will actually run. |
| N12 | Fragile SA-volume check | ✅ Resolved | `! … \| grep -q kube-api-access`. |
| N13 | Tag before AppSet ordering | ✅ Resolved | 5a → 5b → 5c. |

---

## 2. Blocking findings (step 5b)

### B1. `kubectl apply --server-side` does not remove an existing `last-applied-configuration`; it writes the new token into it

The plan assumes that switching the scripts to `apply --server-side` removes the annotation. That only holds for objects that **never had one**. Tested on the hub with kubectl v1.36.1 and throwaway Secrets in `default`, all deleted afterwards:

| Sequence | Annotation afterwards |
|---|---|
| client-side `apply` (token=OLD) → `apply --server-side` (token=NEW) | **Present, now containing NEW in plaintext** |
| **fresh** object created with `apply --server-side` | Absent ✅ |
| client-side `apply` → `kubectl annotate … last-applied-configuration-` → `apply --server-side --force-conflicts` | Absent ✅ |

`cluster-spoke-nonprod`, `cluster-spoke-prod` and `headlamp/headlamp-kubeconfig` all already carry the annotation. As written, step 5b would put the *rotated* tokens into the same annotation, and verification #8 would fail.

**Required change:** before the first server-side apply in each script, delete the Secret or remove the annotation. Removing the annotation avoids a moment where Argo CD has no cluster credentials:

```bash
kubectl --context "$HUB_CONTEXT" -n argocd annotate secret "cluster-${spoke}" \
  kubectl.kubernetes.io/last-applied-configuration- 2>/dev/null || true
kubectl --context "$HUB_CONTEXT" -n argocd apply --server-side --force-conflicts -f - <<EOF
…
EOF
```

Do the same for `headlamp-kubeconfig` in `setup-credentials.sh`.

### B2. The leaked long-lived tokens remain valid: the plan never deletes the legacy token Secrets

Step 5b issues new TokenRequest tokens but leaves `kube-system/argocd-manager-token` on both spokes; both still exist today. A `kubernetes.io/service-account-token` Secret stays valid **until that Secret is deleted**. The tokens exposed in the previous review session would keep working indefinitely, so "rotation" would add a credential instead of replacing one. `register-spokes.sh` also **creates** that Secret in its first heredoc, so rerunning the script as written would put the old token back.

**Required change:**

1. In `register-spokes.sh`, remove the `Secret argocd-manager-token` document from the spoke-side heredoc. Keep only the ServiceAccount and binding, and replace the wait-for-token loop with `kubectl create token … --duration=720h`. Read `ca_data` from the hub's cluster Secret or from the spoke kubeconfig instead (`kubectl config view --raw -o jsonpath='{.clusters[?(@.name=="k3d-'"$spoke"'")].cluster.certificate-authority-data}'`).
2. After the new token is registered and the apps are still Synced, delete the legacy Secrets:

   ```bash
   for c in spoke-nonprod spoke-prod; do
     kubectl --context k3d-$c -n kube-system delete secret argocd-manager-token
   done
   ```
3. Do the same for the hub's `headlamp/headlamp-token` legacy Secret: issue a TokenRequest token in `setup-credentials.sh` and delete the Secret.
4. Add to step 5b's "Done when": the legacy Secrets are gone (`kubectl get secret argocd-manager-token` → NotFound on both spokes); `argocd cluster list` shows both spokes `Successful`; all Applications are Synced/Healthy; Headlamp connects to all three clusters.

> **Do this first, even ahead of the plan.** B2 is the only item here that leaves a known-exposed credential live. Deleting the two legacy Secrets and re-registering is safe to do before anything else, and it supersedes my earlier "rotate when convenient" advice.

---

## 3. Should fix

**S1. Promoting prod with `kubectl annotate` sets up a silent prod rollback.**
Under 5b, `register-spokes.sh` writes `prod: v1.0.0`. Step 7 then promotes by "updating the `cluster-spoke-prod` annotation to `v1.1.0`" without saying how. If that's done with `kubectl annotate`, then **the next time the script runs**, for example at the 30-day token rotation, it rewrites the annotation to `v1.0.0` and **prod silently rolls back** to the pre-hardening blueprint. Pick one source of truth:

- (a) Read the revision from a Git-tracked file, e.g. `clusters/blueprint-revisions.env` (`spoke-prod=v1.1.0`). Promotion is then a commit to that file plus a rerun (or `kubectl annotate` from the same value). The script and the cluster can't diverge.
- (b) Set prod's annotation to a ref that never changes, `release/prod`, and promote with `git push origin v1.1.0^{commit}:refs/heads/release/prod`. The Secret never changes, and the promotion is recorded in Git.

Also name the exact commit for `v1.1.0`, the SHA verified on non-prod in step 6, rather than tagging whatever `main` points at in step 7.

**S2. TokenRequest expiry turns into a silent outage in 30 days.**
The plan sets `--duration=720h` but no longer includes the `make rotate-spoke-tokens` target from v2.0. There is no alerting (assessment L3-3). When the tokens expire, both spokes go `Unknown` in Argo CD and Headlamp loses them at the same moment. Either add the make target and record the expiry date in the cluster Secret (e.g. annotation `lab/token-expires: 2026-10-30`), or use a longer duration that you choose on purpose. The trade-off belongs in the L4-10 write-up either way.

**S3. Inconsistent wording in L4-10.** The §2 table says "Defer TokenRequest migration", but §3 and step 5b *perform* it. Change the table to "Adopt TokenRequest (30-day) now; EKS Access Entries / Pod Identity is the documented end state."

---

## 4. Minor

- **M1.** The `argocd` CLI is installed but **not logged in** (`Logged In: false`). Step 2's `argocd app get --hard-refresh` will fail and fall through to the `kubectl patch` path, which has the N11 race. Prefix it with `argocd login localhost:8080 --plaintext --grpc-web --username admin` (or use `--core`). Alternatively, poll until the `argocd.argoproj.io/refresh` annotation disappears before reading `.status.conditions`.
- **M2.** Step 5b rotates the credentials Argo CD uses for **both** spokes at once. Do non-prod first, confirm `argocd cluster list` shows `Successful`, then do prod. The script already loops over the spokes, so this is just two invocations or a `SPOKES` override.
- **M3.** The headline bullets in §1 still describe L4-1 as later work. With B2, the Headlamp token decoupling partly happens in 5b. Say so, so the L4-1 effort isn't double-counted.

---

## 5. Verified during this review

| Check | Result |
|---|---|
| `git grep -nE 'file:///\|/home/bleit[e]' -- ':!docs/assessments' ':!docs/remediation'` | Lists 6 files, so the `!` check fails as it should until step 3 is done ✅ |
| Client-side apply → server-side apply, on a throwaway Secret | Annotation **kept and updated with the new value** (B1) |
| Fresh server-side create / remove annotation then server-side apply | No annotation ✅ (validates the B1 fix) |
| `kube-system/argocd-manager-token` on both spokes | **Still present**, so the exposed tokens are still valid (B2) |
| `argocd account get-user-info` | `Logged In: false` (M1) |
| Throwaway test Secrets | Deleted. No lab resources were changed by this review |

---

## 6. Corrected execution order

| Step | Change | Authorized | Done when |
|---|---|:-:|---|
| **0** | **Kill the exposed tokens:** delete `argocd-manager-token` on both spokes, rerun registration with TokenRequest (non-prod first), refresh Headlamp credentials (B2, M2) | ✅ (urgent) | Legacy Secrets NotFound; `argocd cluster list` both `Successful`; apps Synced/Healthy |
| 1 | Back up + delete the CRD; remove the stray containers | ✅ | NotFound; `docker ps -a` clean |
| 2 | Delete `repo-ghcr-charts`; log in to the CLI, then hard-refresh (M1) | ✅ | No conditions; Synced/Healthy |
| 3 | Portability fixes | ✅ | The `git grep` check passes |
| 4 | Tutorial sync | ✅ | Matches the live cluster |
| 5a | Tag `v1.0.0` at `a8825b2`, push | ✅ | Tag on GitHub |
| 5b | Annotations + strip `last-applied-configuration` + server-side apply (B1); single revision source (S1); expiry recorded (S2) | after fix | Verification #8 empty on both Secrets; prod revision unchanged |
| 5c | AppSet `targetRevision` from annotation | after 5b | Prod still on `a8825b2`, no resource changes |
| 6 | RGD hardening (non-prod) | after 5b | SA ≠ default, no `kube-api-access`, PSS dry run clean, no dev PDB |
| 7 | Tag `v1.1.0` **at the SHA verified in step 6**, promote via the S1 mechanism | after 5b | `orders-prod` rolled; PDB present; Synced/Healthy |
| 8 | Docs (L4-10 trade-off, S2 expiry, S3 wording) | ✅ | Well-Architected guide updated |
