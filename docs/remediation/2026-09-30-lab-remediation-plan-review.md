# Remediation Plan Review — 2026-09-30

| | |
|---|---|
| **Reviewed** | [`2026-09-30-lab-remediation-plan.md`](2026-09-30-lab-remediation-plan.md) **v2.0** (commit `b2883ab`) |
| **Previous review** | v1.0 of the plan (commit `577f4d7`), review committed in `cb60a30` |
| **Against** | [`../assessments/2026-09-30-lab-assessment.md`](../assessments/2026-09-30-lab-assessment.md), the live clusters, and the five lab repositories |

**Verdict: approve with three blocking fixes.**

v2.0 is a substantial improvement. Of the 14 v1 review points, 11 are fully resolved, 2 are partially resolved, and 1 was deliberately not adopted. The plan is now internally consistent about the PDB, `REPOS_DIR`, CRD ordering and secret cleanup. It also has a staged rollout and a "done when" column for every step.

Checking v2.0 against the live environment found three new problems that would make execution fail or give a false result:

- **N1:** the RGD hardening never assigns the new ServiceAccount to the pods.
- **N2:** the portability check always passes, even when paths remain.
- **N3:** the prod pin points at a tag that doesn't exist.

These need fixing before steps 3, 5 and 6 run. The other new items are improvements, not blockers.

---

## 1. Status of v1 review points

| v1 point | Topic | Status in v2.0 | Notes |
|---|---|:-:|---|
| R1 | PDB `minAvailable` vs `maxUnavailable` contradiction | ✅ Resolved | `includeWhen: ${schema.spec.replicas > 1}` + `minAvailable: 1`. |
| R2 | Blueprint change reaches prod at the same moment as non-prod | ⚠️ Partial | The gate is designed, but see N3 (missing tag), N4 (prod promoted by an untracked `kubectl` edit, not Git) and N5 (rollback claim). |
| R3 | Path cleanup under-scoped | ⚠️ Partial | All files listed, but the verification command is broken (N2) and the file count is wrong (N8). |
| R4 | `REPOS_DIR` defined two ways / `CURDIR` | ✅ Resolved | Uses the `lastword $(MAKEFILE_LIST)` form. |
| R5 | CRD-before-docs concern inverted | ✅ Resolved | "Loud failure is safer" is now stated correctly, with the right error text. |
| R6 | "Zero-risk" label, no backups, cache-blind verification | ✅ Resolved | Renamed "Low-risk", `/tmp` backups added, hard-refresh made an explicit step. |
| R7 | L2-7 resolvable now; unsupported rate-limit claim | ✅ Resolved | Records the verified facts and adds the ESO/Sealed Secrets note. |
| R8 | L4-10 overstated cost; TokenRequest middle path | ✅ Resolved | Framed as "defer, document the next step". See also N6. |
| R9 | Don't refactor the setup script | ✅ Resolved | |
| R10 | Wrong SA verification field; no PSS check; env var placement | ✅ Resolved | PSS dry run added and SA check rewritten. The Dockerfile placement creates a new risk: see N7. |
| R11 | Scope framing vs Critical/High | ✅ Resolved | A sequencing section was added. The plan keeps lows-first, which is a legitimate choice (see §4). |
| R12 | README repo count | ✅ Resolved | |
| R13 | Owner / done-definition | ✅ Resolved | "Done When" column added. No owner or date, which is acceptable for a solo lab. |
| R14 | Residual credential exposure of stray containers | ✅ Resolved | |

---

## 2. New findings in v2.0

### Blocking

**N1. The new ServiceAccount is created but never assigned to the pods (L4-11, step 6).**
The RGD snippet adds a `ServiceAccount` resource, but nothing in the Deployment template references it. Without `serviceAccountName`, the pods keep using the namespace `default` SA with its token auto-mounted. Verification #6 would then print `default` and show a `kube-api-access-*` volume. Add it to the pod spec:

```yaml
    - id: serviceaccount
      template:
        apiVersion: v1
        kind: ServiceAccount
        metadata:
          name: ${schema.spec.name}-${schema.spec.environment}
        automountServiceAccountToken: false
    # …
    - id: deployment
      template:
        spec:
          template:
            spec:
              serviceAccountName: ${serviceaccount.metadata.name}   # also makes kro order SA → Deployment
              automountServiceAccountToken: false                    # belt and braces at pod level
```

Referencing `${serviceaccount.metadata.name}` instead of repeating the name string also adds the edge to kro's dependency graph, so the SA always exists before the pods are scheduled.

**N2. The portability check always passes, whether paths remain or not (step 3, verification #4).**
`':!docs/assessments'` is **git pathspec** syntax. Plain `grep` treats it as a filename that doesn't exist, prints a warning, and exits with status 2 even when it found matches. The leading `!` turns that error into success. I ran the exact command against the current tree, which still has 8 matching files, and it **passed**. Two further problems:

- The plan and this review both *quote* the pattern, so a correct grep will always match them.
- `docs/remediation/` therefore needs excluding (or the pattern needs to avoid matching itself).

A replacement that works:

```bash
! git grep -nE 'file:///|/home/bleit[e]' -- ':!docs/assessments' ':!docs/remediation'
```

`git grep` understands the pathspecs. The `[e]` character class matches `/home/bleite` in real files but not in the literal text of the command itself. Excluding `docs/remediation` is still the simpler option.

**N3. The prod pin `v1.0.0` doesn't exist, and pinning to the wrong commit would roll prod *backwards* (step 5).**
`platform-catalog` has **no tags** (`git tag -l` is empty, HEAD = `a8825b2`). If step 5 runs as written, Argo CD cannot resolve `v1.0.0` and `kro-blueprints-spoke-prod` goes into `ComparisonError`. If someone creates `v1.0.0` on an older commit, prod's RGD reverts to that blueprint (for example, before the DLQ or probes hardening). Make tag creation step 5a, pin it to the commit prod runs today, and verify the revision didn't change:

```bash
git -C ../platform-catalog tag -a v1.0.0 a8825b2 -m "Blueprint baseline currently running on spoke-prod"
git -C ../platform-catalog push origin v1.0.0
# Done when: kro-blueprints-spoke-prod .status.sync.revision == a8825b2… and the app stays Synced (no-op)
```

### Should fix

**N4. Prod promotion is an untracked `kubectl` edit, not a Git change (steps 5 and 7).**
The `blueprints-revision` annotation lives on the cluster Secrets. Those Secrets are created by `register-spokes.sh` and are not in Git. Consequences:

- Promoting to prod means editing a Secret by hand, with no PR, no review and no history. That cuts against the guardrails doc this plan builds on.
- Rerunning `register-spokes.sh` (for example after a spoke is recreated, or during token rotation per L4-10) **silently erases the annotation**. `{{metadata.annotations.blueprints-revision}}` then renders empty, and the prod app falls back to the default branch.

Two cheap fixes, either is fine:

- (a) Have `register-spokes.sh` write the annotation, with prod's value pointing at a moving **ref name** such as `release/prod`. Promotion becomes `git push origin <sha>:refs/heads/release/prod` (reviewable and in history), and the Secret never changes.
- (b) Move the per-cluster revision into Git: a `clusters/<name>.yaml` that the AppSet reads through a matrix of the Cluster generator × a Git-files generator.

Option (a) is about five lines and keeps the current design.

Also: step L4-11.5 says "moving the git tag `v1.1.0`". Create a **new** tag. Never move an existing one. Moving release tags is exactly the L3-5 anti-pattern the plan lists as High.

**N5. The rollback claim is unverified, and it describes the wrong mechanism.**
"`git revert` … kro automatically restores the previous `GraphRevision` in under 5 seconds" doesn't hold:

- A revert is a *new* commit. Argo CD only picks it up on its next poll (up to about 3 minutes, unless a webhook or manual refresh triggers it).
- kro then creates a **new** `GraphRevision` (`r00006`). It does not restore `r00005`.
- The "under 5 seconds" figure came from my child-drift test, a different mechanism.

For **prod**, the gate gives a better rollback path: point prod back at the previous tag (or ref, per N4) without touching `main`. Restate the rollback this way:

- **Prod:** repoint to the previous tag. Expect seconds after a refresh.
- **Non-prod:** `git revert`. Expect up to one poll interval.
- **Verify:** `kubectl get graphrevisions` shows a new revision, and the Deployment rolls.

**N6. New finding (related to L4-10): spoke bearer tokens are stored in plaintext in an annotation.**
`register-spokes.sh` creates the cluster Secrets with `kubectl apply -f -` using `stringData`. kubectl therefore records the **entire manifest, bearer token included**, in `metadata.annotations["kubectl.kubernetes.io/last-applied-configuration"]`. Annotations are displayed in places where Secret data is normally hidden: `kubectl describe secret`, Headlamp's metadata panel, and `kubectl get -o jsonpath='{.metadata}'`. This review exposed the tokens the same way: an annotation query printed both `argocd-manager` tokens into the session transcript.

**Fix:** use `kubectl create secret generic … --dry-run=client -o yaml | kubectl apply --server-side -f -`, or `kubectl apply --server-side` directly, which does not write `last-applied-configuration`. Then rotate both tokens: delete the `argocd-manager-token` Secrets on the spokes and rerun registration. This fits naturally into L4-10's `make rotate-spoke-tokens`, so the TokenRequest middle path is worth doing now rather than only documenting it. `addons/headlamp/setup-credentials.sh` uses the `--dry-run | apply` pattern too, so it has the same exposure for its kubeconfig Secret.

**N7. Adding `PYTHONDONTWRITEBYTECODE` to the Dockerfile would overwrite the running prod image (L4-11.4).**
`orders-processor` CI runs on every push to `main` and tags the result `v1.2.0` **and** `v1.1.0` (`ci.yaml` lines 52–53, unchanged). A Dockerfile commit therefore builds a new image under the tag all three environments currently run. That image then appears on any node that pulls it, with no Git change to the deploy values and no promotion. As v1 R10 found, the variable isn't needed (the app writes nothing to disk). Either **drop L4-11.4**, or make it explicitly depend on L3-5 (immutable tags) and release it as `v1.3.0` through `deploy/values-*.yaml`.

### Minor

- **N8. File count.** Step 3 says "all 7 markdown files", but the set is Makefile + README + 5 docs: 7 files, of which 6 are Markdown. The plan's own scope table says "7 files (including … Makefile)". Align the wording. `tenant-workloads/developer-tutorial.md` is still out of scope; note that it is covered by archiving the repo (L1-4) so it isn't forgotten.
- **N9. Cross-repo relative link.** `../../platform-catalog/blueprints/queue-backed-service-rgd.yaml` resolves locally but returns 404 on GitHub, because it leaves the repo. Use `https://github.com/brunobml/platform-catalog/blob/main/blueprints/queue-backed-service-rgd.yaml`. This applies the plan's own L1-6 rule.
- **N10. Naming.** The plan calls the cluster Secrets `k3d-spoke-nonprod` / `k3d-spoke-prod`. The objects are named `cluster-spoke-nonprod` / `cluster-spoke-prod`, with Argo CD cluster names `spoke-nonprod` / `spoke-prod`.
- **N11. Race in the hard-refresh check.** Reading `.status.conditions` right after setting the `refresh=hard` annotation can read the old status. Poll until Argo CD removes the `argocd.argoproj.io/refresh` annotation, which is its signal that the refresh finished. Simpler still, use `argocd app get orders-dev --hard-refresh`, which blocks until the refresh is done.
- **N12. Fragile SA-volume check.** `jsonpath … | grep -v "kube-api-access"` passes or fails by exit code on a single space-joined line, and it fails falsely when the pod has no volumes. Use `! kubectl … -o jsonpath='{.items[0].spec.volumes[*].name}' | grep -q kube-api-access`.
- **N13. AppSet change applies through the root app.** `applicationsets/kro-blueprints.yaml` is synced by `root-control-plane` from `main`. Step 5's AppSet edit and step 5a's tag must therefore land in the right order: tag first, then AppSet. Otherwise N3's `ComparisonError` happens in the window between them.

---

## 3. Verified during this review

| Check | Result |
|---|---|
| Plan's grep check (`! grep … ':!docs/assessments'`) on the current tree | **Passes falsely**: grep warns about the missing file `:!docs/assessments` and exits non-zero despite 8 matches |
| `git grep -lE 'file:///\|/home/bleite' -- ':!docs/assessments'` | 8 files: Makefile, README, headlamp README, 3 docs, plus the plan and this review |
| `git -C ../platform-catalog tag -l` | Empty. HEAD `a8825b2` is the revision both `kro-blueprints` apps run |
| Cluster Secret annotations on hub | No `blueprints-revision` yet. `last-applied-configuration` contains the plaintext bearer token (N6) |
| `orders-processor` CI triggers | `push: main` and `tags: v*`. Hard-coded `v1.2.0`/`v1.1.0` tags still present (N7) |
| RGD snippet in plan §3 L4-11 | No `serviceAccountName` in the Deployment (N1) |

---

## 4. On sequencing (not blocking)

The plan keeps the order "lows first, then L4-1 → L3-1 → L3-5 → L2-2", which is a reasonable owner decision. Two of the findings above argue for pulling one High item forward:

- **L3-5 (immutable CI tags) before step 6/L4-11.4,** because of N7. Otherwise the blueprint hardening and an image rebuild can collide on the same mutable tag.
- **L4-1's token decoupling alongside N6,** since rotating `argocd-manager` tokens breaks Headlamp anyway: it reads them from the same Secrets. Doing both in one change window avoids breaking Headlamp twice.

---

## 5. Suggested execution order (v2.0 + this review)

| Step | Change | Done when |
|---|---|---|
| 1 | Back up and delete the CRD on both spokes; remove the stray containers | NotFound on both spokes; `docker ps -a` clean |
| 2 | Delete `repo-ghcr-charts`; `argocd app get orders-dev --hard-refresh` | No conditions; Synced/Healthy |
| 3 | Portability fixes across the 7 files | `! git grep -nE 'file:///\|/home/bleit[e]' -- ':!docs/assessments' ':!docs/remediation'` passes |
| 4 | Tutorial sync | Matches the live cluster |
| 5a | Tag `platform-catalog` `v1.0.0` at `a8825b2` and push | Tag visible on GitHub |
| 5b | Write `blueprints-revision` from `register-spokes.sh` (prod → `release/prod` ref or `v1.0.0`); switch the AppSet `targetRevision` | Prod app revision is still `a8825b2`, no resources changed |
| 5c | Switch `register-spokes.sh` to server-side apply; rotate `argocd-manager` tokens; regenerate Headlamp credentials | `last-applied-configuration` absent on cluster Secrets; all apps Synced; Headlamp connects to all 3 clusters |
| 6 | RGD hardening, **including `serviceAccountName`** (N1); **skip the Dockerfile env var** (N7) | Non-prod pods Running, 0 restarts, SA ≠ `default`, no `kube-api-access` volume, PSS dry run clean, no PDB in dev |
| 7 | Create a **new** tag `v1.1.0`; promote prod through Git (N4) | `orders-prod` rolled; PDB present; Synced/Healthy |
| 8 | Document L4-10 trade-off and next step (the TokenRequest part is partly done in 5c) | Well-Architected guide updated |
