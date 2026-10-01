# Remediation Plan Review — 2026-09-30

**Reviewed:** [`2026-09-30-lab-remediation-plan.md`](2026-09-30-lab-remediation-plan.md) (commit `577f4d7`)
**Against:** [`../assessments/2026-09-30-lab-assessment.md`](../assessments/2026-09-30-lab-assessment.md), the live clusters, and the five lab repositories

**Verdict: approve with changes.** The plan covers the right items, sorts them sensibly by risk, and its pushback on L4-10 and on HPA is largely sound. Before execution, it needs these fixes:

- Two internal contradictions (the PDB spec and the Makefile `REPOS_DIR`).
- One concern that has the risk backwards (deleting the CRD before updating the docs).
- Path coverage that misses 6 of the 9 files containing `/home/bleite`, including the plan itself.
- A blueprint change that reaches prod and non-prod at the same moment, with no staged rollout or rollback.

---

## 1. Claims verified against the live environment

| Plan claim | Check performed | Result |
|---|---|---|
| L1-2: zero `MessageProcessor` instances remain | `kubectl get messageprocessors.kro.run -A` on both spokes | ✅ Confirmed: none on either spoke. No `GraphRevision` objects reference it either (only `queuebackedservice-r0000{1..5}`). |
| L2-7: the declarative secret may be missing OCI keys or credentials | Compared the keys and non-secret values of both secrets | ✅ **They are identical**: `type=helm`, `enableOCI=true`, `url=ghcr.io/brunobml/charts`, and **neither holds credentials**. `argocd-repo-ghcr-charts` is owned by Helm (`argo-cd` release). `repo-ghcr-charts` has no owner. |
| L2-7: a private registry might need auth | Anonymous token plus manifest `GET` for `charts/queue-backed-service:1.0.0` | ✅ **The chart is public** (HTTP 200 anonymously). Deleting the manual secret cannot break auth. |
| L4-11: Python needs `PYTHONDONTWRITEBYTECODE` to survive a read-only root FS | Read `orders-processor/src/main.py` | ⚠️ **Not needed.** The app is a single script that imports only the standard library and never writes to disk. CPython does not cache the entry script, and if it can't write a `.pyc` it skips it silently instead of raising. The variable does no harm, but the stated reason is wrong. |
| L4-11: a conditional PDB is possible | Checked the kro 0.9.4 RGD CRD schema | ✅ `includeWhen`, `readyWhen`, `externalRef` and `forEach` are all supported. |
| L1-6: the hard-coded paths are in the Makefile, the README and "several doc links" | `grep -rc /home/bleite` across all 5 repos | ⚠️ **Under-scoped.** See R3. |

---

## 2. Findings on the plan

### Must fix before execution

**R1. The PDB specification contradicts itself (L4-11 vs Phase 3.4).**
The L4-11 YAML uses `minAvailable: 1` with no condition. Two paragraphs later the plan explains why that blocks `kubectl drain` on single-replica dev, and Phase 3.4 then says `maxUnavailable: 1`. Choose one and put it in the YAML. Recommended:

```yaml
- id: pdb
  includeWhen:
    - ${schema.spec.replicas > 1}
  template:
    apiVersion: policy/v1
    kind: PodDisruptionBudget
    metadata:
      name: ${schema.spec.name}-${schema.spec.environment}
    spec:
      minAvailable: 1
      selector:
        matchLabels:
          app: ${schema.spec.name}-${schema.spec.environment}-worker
```

With `includeWhen`, dev and test (1 replica) get no PDB, and prod (2 replicas) can lose at most one pod. Using `maxUnavailable: 1` without a condition is valid but protects nothing when there is 1 replica. It also allows a full outage of a 1-replica service, which defeats the purpose.

**R2. Blueprint changes reach prod at the same moment as non-prod, and the plan has no staged rollout or rollback.**
Phase 3 edits `queue-backed-service-rgd.yaml`. `kro-blueprints` tracks `platform-catalog@main` for **both** spokes (assessment L3-6). Adding a ServiceAccount, seccomp and a read-only root FS changes the pod template, so all three Deployments, prod included, roll within one Argo CD poll. The verification step ("Pod status `Running`, zero restarts") runs only on `orders-dev`, after prod has already rolled. Add a gate:

- Minimal: add a `blueprints-revision` annotation to each cluster Secret (`nonprod: main`, `prod: <tag>`), use `targetRevision: '{{metadata.annotations.blueprints-revision}}'` in `kro-blueprints`, and promote by moving the tag after dev and test pass. This is about 10 lines and is also the first step of assessment Recommendation 10.
- Rollback: write down `git revert` on `platform-catalog` as the rollback path, and check that kro rolls back to the previous `GraphRevision`.

**R3. Path cleanup (L1-6) misses most of the occurrences, including the plan's own.**
`grep -rc /home/bleite` finds them in 9 files:

| File | Count | In plan? |
|---|---:|:-:|
| `docs/remediation/2026-09-30-lab-remediation-plan.md` | 9 | ❌ (the L4-10 link and others) |
| `docs/lab-progression-and-next-steps.md` | 6 | ❌ |
| `README.md` | 4 | ✅ |
| `addons/headlamp/README.md` | 2 | ⚠️ ("markdown links", unnamed) |
| `docs/developer-tutorial.md` | 2 | ⚠️ |
| `tenant-workloads/developer-tutorial.md` | 2 | ❌ (archive the repo instead, per L1-4) |
| `docs/production-promotion-guardrails.md` | 1 | ❌ |
| `Makefile` | 1 | ✅ |
| `docs/assessments/…-lab-assessment.md` | 2 | n/a (these are quoted as evidence, so leave them) |

Replace the Phase 2.4 verification ("Links resolve in GitHub UI") with a check a script can run: `! grep -rn 'file:///\|/home/bleite' --include=*.md --include=Makefile --include=*.sh . ':!docs/assessments'`.

**R4. The Makefile `REPOS_DIR` is defined two different ways.**
The action plan says `$(abspath $(CURDIR)/..)`. The concerns section says `$(shell dirname $(CURDIR))`. Both rely on `CURDIR`, which is the directory `make` was *invoked from*, so they break under `make -f ../gitops-control-plane/Makefile`. Use the Makefile's own location:

```makefile
ROOT_DIR  := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
REPOS_DIR ?= $(abspath $(ROOT_DIR)/..)
```

`scripts/setup-hub-spoke.sh` already does the equivalent with `BASH_SOURCE`, so this keeps the two consistent.

### Should fix

**R5. The L1-2 docs-coupling concern has the risk backwards.**
The plan warns that deleting the CRD before updating the tutorial makes `MessageProcessor` manifests fail. Today the opposite is the dangerous case. With the CRD present and no RGD, `kubectl apply` of a `MessageProcessor` **succeeds and then nothing happens**, because nothing reconciles it. A loud failure is better than a silent no-op, so deleting the CRD first is the safer order. Keep Phase 1 before Phase 2 as written, and drop the concern, or restate it as "update the tutorial in the same PR window". The error text the plan quotes is also wrong: `kubectl apply` reports `no matches for kind "MessageProcessor" in version "kro.run/v1alpha1"`.

**R6. "Zero-Risk" is the wrong label for Phase 1, and it has no backups.**
Step 1.3 deletes a CRD on the **prod** spoke. §1 shows it is safe, but the label invites skipping checks. Rename it "Low-risk cleanup" and add a one-line backup before each delete:

```bash
kubectl --context k3d-spoke-prod get crd messageprocessors.kro.run -o yaml > /tmp/mp-crd-prod.yaml
```

The verification for step 1.4 (`get applications` → Synced) cannot detect a broken repo secret, because the repo-server serves rendered manifests from cache. Make the hard refresh a step in the table, not just prose: `argocd app get orders-dev --hard-refresh`, then check `.status.conditions` is empty.

**R7. The L2-7 nuance can be resolved now, and one claim in it is unsupported.**
§1 shows both secrets are identical and credential-free, and that the chart is public, so step 1 of the L2-7 action plan is already answered. Remove the "Argo CD logs rate-limit warnings if anonymous" claim: nothing in this environment shows it, and anonymous pulls from GHCR are normal. One forward-looking note belongs in the plan: if the chart ever goes private, credentials must go through a secret store (ESO or Sealed Secrets), **not** the Helm values file, which is in a public repo.

**R8. L4-10 overstates what replacement would cost, and a cheap middle path exists.**
The plan says replacing static tokens needs Vault or cert-manager, or changes to Argo CD. It doesn't. The TokenRequest API is available on k3s, so time-bound tokens are a change to `register-spokes.sh`:

```bash
token=$(kubectl --context "$context" -n kube-system create token argocd-manager --duration=720h)
# …write the cluster Secret as today; delete the legacy argocd-manager-token Secret
```

Rotate them with a `make rotate-spoke-tokens` target that reruns the registration. This is a small task. It also forces the change the assessment flagged as Critical in L4-1: Headlamp can no longer borrow Argo CD's tokens and must get its own (ideally `view`-only) ServiceAccount on each spoke. Accepting the long-lived tokens as a documented lab trade-off is still a defensible decision. Reword "strongly advise against" to "defer". Record the TokenRequest option in the Well-Architected guide as the next step, with the EKS Access Entries and Pod Identity end state.

**R9. L3-8: don't invest in the script.**
Parameterizing `setup-hub-spoke.sh` with `ACK_SERVICES=("sqs")` is work you will throw away once Recommendation 9 lands. As sketched, it also doesn't work: each ACK controller has its own chart version and values file, so it needs at least `declare -A ACK_VERSIONS=([sqs]=1.7.1)` and a per-service values path. The "chicken-and-egg" concern is also weaker than stated:

- ACK and kro charts ship their CRDs, and Argo CD applies CRDs before the custom resources within a sync.
- The only real ordering dependency is the `ack-aws-creds` Secret. Put it in the same Application with `sync-wave: "-1"`.
- Ordering **across** Applications (blueprints before tenant apps) does need waves on the child Applications. That only works if the hub has a health check for `argoproj.io/Application` (removed by default since Argo CD 1.8). Add it to `resource.customizations` when you get there.

Recommendation: skip the script refactor and keep L3-8 attached to L2-1 / Recommendation 9.

**R10. The L4-11 verification checks the wrong field and skips the actual standard.**
- Check #4 reads `pod.spec.automountServiceAccountToken`. If the RGD sets this on the **ServiceAccount**, as the plan proposes, the pod field stays empty and the check reads as a false negative. Instead, check `.spec.serviceAccountName` and that no `kube-api-access-*` volume is mounted.
- Nothing proves `restricted` PSS compliance, which is the point of 3.2. Add a server-side dry run, which prints a warning for every violating pod without enforcing anything:

  ```bash
  kubectl --context k3d-spoke-nonprod label --dry-run=server --overwrite ns orders-dev \
    pod-security.kubernetes.io/enforce=restricted
  ```

  No warnings means compliant. This is also the entry criterion for assessment Recommendation 13.
- Put `PYTHONDONTWRITEBYTECODE` (if you keep it) in the `orders-processor` **Dockerfile** (`ENV`). The plan currently puts it in "the deployment spec", which is the platform RGD, and that would push an app-runtime detail into the platform contract for every future non-Python tenant.

### Minor

- **R11. Scope framing.** The plan covers only the 7 Low findings and doesn't mention the order relative to the open Critical and High items (L4-1 Headlamp, L3-1 ACK resync, L3-5 mutable tags, L2-2 prod gate). Add one line stating that the Highs follow, and in what order. Two of the assessment's quick wins (#1 CI tags, #6 ACK resync) take under an hour each and close High findings. They give more value per hour than most of this plan.
- **R12.** The README lines touched in Phase 2.2 still list 3 repositories (assessment L1-5). Fix that in the same edit.
- **R13.** No owner, target date or done-definition per phase. Even for a solo lab, a "done when" column turns the tables into a checklist you can tick.
- **R14.** The L1-3 note that the containers are "decoupled from `k3d-cloud-net`" is correct (they are on the default `bridge`). The host kubeconfig they mounted (`/tmp/headlamp-test/kubeconfig`) no longer exists, so the plan can say the residual credential exposure is already gone.

---

## 3. Points where the plan is right and the assessment should yield

- **HPA:** agreed. A CPU-based HPA is the wrong tool for an SQS worker. The assessment listed "no HPA" without that qualification. KEDA on `ApproximateNumberOfMessagesVisible` is the right pattern, and it works against moto.
- **L4-10 as a documented trade-off:** with the R8 middle path recorded, accepting it is reasonable for a local lab.
- **Verifying before deleting** (zero instances, secret contents) is the right habit, and §1 shows both checks pass.

---

## 4. Suggested revised execution order

| Step | Change | Done when |
|---|---|---|
| 1 | Back up, then delete the `messageprocessors` CRD on both spokes; `docker rm -f` the 3 stray containers | `get crd` → NotFound; `docker ps -a` clean |
| 2 | Delete `repo-ghcr-charts`; hard-refresh the 3 tenant apps | No `ComparisonError` conditions; still Synced/Healthy |
| 3 | Fix the Makefile (`ROOT_DIR`/`REPOS_DIR`), README (paths and repo count), and all 7 files with `/home/bleite` (R3) | The path grep in R3 returns nothing |
| 4 | Update `docs/developer-tutorial.md` (`QueueBackedService`, `orders-*` names, 2 prod replicas) | A new reader can follow it end to end |
| 5 | Add the per-cluster `blueprints-revision` gate (R2) and tag the current `platform-catalog` HEAD for prod | Prod's `kro-blueprints` app shows the tag as its revision |
| 6 | Change the RGD: ServiceAccount (automount off), seccomp, read-only root FS + `/tmp` emptyDir, conditional PDB | On non-prod: pods Running, 0 restarts; PSS dry run (R10) shows no warnings |
| 7 | Promote the blueprint to prod by moving the tag | `orders-prod` rolled out; PDB present; Synced/Healthy |
| 8 | Document L4-10 as a trade-off, including the TokenRequest next step (R8) | The Security section of the Well-Architected guide is updated |
