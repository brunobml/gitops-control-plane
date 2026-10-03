# Phase 2 Remediation Validation — Run #01 (2026-09-30)

> **Status: Historical.** Record of the 2026-09-30 assessment and its remediation (Phases 1–5, closed 2026-10-03). Kept as evidence and not updated. For the lab as it is today, see the [README](../../../README.md) and the [2026-10-03 assessment](../../assessments/2026-10-03-lab-assessment.md).

| | |
|---|---|
| **Validates** | [`2026-09-30-lab-remediation-plan-phase2-implemented-01.md`](2026-09-30-lab-remediation-plan-phase2-implemented-01.md) (commit `bf98391`). Related commits: `orders-processor@8f5e0b6` (tag `v1.3.0`), `platform-catalog@c0f8779` |
| **Against** | [Phase 2 plan v1.0](2026-09-30-lab-remediation-plan-phase2.md): authorized scope **Track 1 (Steps 1–5) and Step 8**, conditions **C-1 to C-4** |
| **Method** | Independent checks against the live clusters, GHCR (anonymous registry API), and all three Git repos. Negative tests used a fake `aws` binary on `PATH` and throwaway clones in the scratchpad. |
| **Changes made by this validation** | One deliberate drift test on **dev only**: deleted `orders-dev-dlq` in moto, and ACK recreated it on its own. Server-side dry runs (no objects created). Scratch clones removed. No commits. |
| **Validated By / Date** | Claude (Opus 5.5) · 2026-09-30 |

## Verdict

> ### 🟠 VALIDATED WITH ONE BLOCKING DEFECT
>
> | Step | Finding | Result |
> |---|---|:-:|
> | 1 | L3-5 Immutable CI tags (+ C-1) | ⛔ **Not closed** (PV-1): the pipeline is fixed, but the release workloads reference `v1.3.0`, which **does not exist on GHCR**, and they run an **unregistered local build** of a different commit |
> | 2 | L3-1 ACK resync 300 s (+ C-3) | ✅ Closed. Acceptance #6 passed live (DLQ recreated with no restart) |
> | 3 | L3-4 Honest smoke tests (+ C-2) | ✅ Closed. A negative test proves it fails closed |
> | 4 | L4-7 / L1-4 AppProjects | ✅ Closed |
> | 5 | X-1 Promotion preflight on `main` | ✅ Closed (PV-2 is a minor refinement) |
> | 8 | L4-3 (PSS part) + C-4 | ✅ Closed. Enforcement proven: a non-compliant pod is rejected |
>
> PV-1 isn't causing an outage today, because every node has the locally imported image cached. It is a **latent outage** and a **provenance failure**: the next node replacement, image garbage collection, or `make setup` rebuild leaves all three environments in `ImagePullBackOff`, and the code running in prod doesn't match the `v1.3.0` release commit. Fix PV-1 before Track 4 (P2-B6), because Track 4 pins prod to this release.
>
> **Bonus:** the blueprint promotion gate has now been **observed under divergence** (carried forward since Validation-03). `platform-catalog@main` advanced to `c0f8779`; `kro-blueprints-spoke-nonprod` followed while `kro-blueprints-spoke-prod` stayed at `5dc0dfa` (`v1.1.0`). ✅

---

## 1. Step-by-step validation

### Step 1: L3-5 immutable CI tagging and release `v1.3.0` (C-1) ⛔

| Check | Evidence | Result |
|---|---|:-:|
| Mutable raw tags removed from `ci.yaml` | `docker/metadata-action` tags are now only `type=semver,pattern={{version}}` and `type=sha,format=short,prefix=sha-`; `APP_VERSION=${{ github.ref_name }}` | ✅ |
| No mutable `main` tag (C-1) | No `type=ref,event=branch` present | ✅ (stricter than C-1 required) |
| Git release tag | `orders-processor` `v1.3.0^{}` → `8f5e0b6`, on `origin` | ✅ |
| **Values reference a published artifact** | All 3 `deploy/values-*.yaml` → `ghcr.io/brunobml/orders-processor:v1.3.0`. GHCR tag list: `[… "sha-8f5e0b6", "1.3.0"]`. **`v1.3.0` → HTTP 404**; `1.3.0` → 200 | ⛔ |
| **Running image = CI release artifact** | Pods report `imageID sha256:1dcf8f61…` with `imagePullPolicy: IfNotPresent`. The image on all 4 nodes was imported with `k3d image import`. Its embedded `BUILD_COMMIT=acfb7ab` (the commit *before* the release), which the live footer shows too: "Git Commit: acfb7ab". The CI artifact `1.3.0` = `sha-8f5e0b6` (manifest `sha256:3fc6e216…`, config `sha256:d3aeb027…`) has `BUILD_COMMIT=8f5e0b6`. **Different images, same name.** | ⛔ |

### Step 2: L3-1 ACK resync 300 s (C-3) ✅

| Check | Evidence | Result |
|---|---|:-:|
| Value in source of truth only | `platform-catalog@c0f8779` `controllers/ack/values-sqs.yaml`: `reconcile.defaultResyncPeriod: 300` | ✅ |
| Live on both spokes | `RECONCILE_DEFAULT_RESYNC_SECONDS=300` on both Deployments; Helm revision 2 on both | ✅ |
| **Acceptance #6, run live by the validator** (the report didn't run it) | Deleted `orders-dev-dlq` in moto at 02:43:48 UTC. **Recreated after 15 s**, controller restarts 0 → 0. `orders-dev-queue` `RedrivePolicy` still points at `arn:…:orders-dev-dlq`. 15 s means the periodic resync happened to fall soon after the delete; the guaranteed bound is about 300 s | ✅ |

> Compare the assessment (L3-1), where the same deletion went **unnoticed for 120 s+** and would have stayed so for up to 10 h.

### Step 3: L3-4 smoke tests (C-2) ✅

| Check | Evidence | Result |
|---|---|:-:|
| Positive run | `scripts/smoke-test-hub-spoke.sh` → exit 0, 7 stages | ✅ |
| **Fails closed (negative test)** | With a fake `aws` returning `{"QueueUrls": []}` → **exit 1**, `✘ Missing expected SQS queue in Moto Cloud: orders-dev-queue` | ✅ |
| C-2: expected set **and** every app | `EXPECTED_APPS` presence loop (lines 50–61) plus an all-applications loop (lines 66–74) | ✅ |
| C-2: queues by name | `EXPECTED_QUEUES` (3 queues + 3 DLQs), checked one by one | ✅ |

### Step 4: L4-7 / L1-4 AppProjects ✅

| Check | Evidence | Result |
|---|---|:-:|
| `default` project locked down | Live spec: `sourceRepos: []`, `destinations: []`, `clusterResourceWhitelist: []`, `namespaceResourceWhitelist: []` | ✅ |
| Dead repo removed | Live `tenant-workloads.sourceRepos` = `orders-processor.git`, `ghcr.io/brunobml/charts`, matching Git. No live manifest references `tenant-workloads.git` | ✅ |
| Behaviour note | A server dry run of an `Application` with `project: default` is **admitted**. Argo CD has no admission webhook, so enforcement happens in the application controller, which refuses sources and destinations outside the project. This is expected. The report's wording ("cannot be used to deploy") is right; "cannot be created" would not be (PV-5). | ℹ️ |

### Step 5: X-1 promotion preflight ✅

Throwaway clone with a local bare `origin`:

| Scenario | Result |
|---|:-:|
| `main`, clean, pushed | ✅ passes preflight (stops at the spoke-name guard as intended) |
| **Feature branch, committed and pushed** (the X-1 gap) | ✅ `Promotion must be run from 'main' branch (current: 'feature')` |
| `main`, local commit not pushed | ✅ `Local commits not pushed to upstream origin/main` |
| `main`, **behind** `origin/main` | ⚠️ passes (PV-2) |

### Step 8: L4-3 PSS `restricted` (C-4) ✅

| Check | Evidence | Result |
|---|---|:-:|
| Declared in Git (C-4) | `managedNamespaceMetadata.labels` in both tenant ApplicationSets; the live ApplicationSets match | ✅ |
| Labels live | `orders-dev`, `orders-test`, `orders-prod`: `enforce=restricted`, `enforce-version=latest`, `warn=restricted`, `audit=restricted`; namespaces carry Argo CD metadata | ✅ |
| **Enforcement proven** | Server dry run of a privileged busybox pod in `orders-prod` → `Forbidden: violates PodSecurity "restricted:latest": privileged, allowPrivilegeEscalation, capabilities, runAsNonRoot, seccompProfile` | ✅ |
| Workloads unaffected | dev 1 / test 1 / prod 2 pods Ready, 0 restarts | ✅ |

---

## 2. Regression check (Phase 1 outcomes)

| Outcome | Live result | |
|---|---|:-:|
| Legacy SA-token Secrets | 0 / 0 / 0 (all namespaces, all clusters) | ✅ |
| Plaintext `last-applied` on credential Secrets | 0 B × 3 | ✅ |
| Argo CD ↔ clusters | `spoke-nonprod`, `spoke-prod`, `in-cluster`: Successful | ✅ |
| Applications | 7/7 Synced/Healthy | ✅ |
| Workload hardening | `orders-*-sa`, `readOnlyRootFilesystem=true`, PDB only in prod (`orders-prod-pdb`, 1 allowed disruption) | ✅ |
| Blueprint pins | nonprod `main` (`c0f8779`), prod `v1.1.0` (`5dc0dfa`); token expiry `2026-10-31` | ✅ |
| Repo path hygiene | `git grep` outside `docs/assessments` and `docs/remediation` → 0 | ✅ |
| Deferred scope unchanged | `ClusterRoleBinding/headlamp-admin` → `cluster-admin` still present (L4-1 / Track 2 not yet authorized) | ℹ️ expected |

---

## 3. Observations

| ID | Sev | Observation | Required / recommended fix |
|---|---|---|---|
| **PV-1** | **High (blocks L3-5 closure and Track 4)** | **The release tag and the runtime artifact don't match.** (1) `type=semver,pattern={{version}}` strips the `v`, so CI published `1.3.0`; the values files reference `v1.3.0`, which returns 404 on GHCR. (2) Pods run because a **locally built** image was injected into every node with `k3d image import` under the registry name `ghcr.io/brunobml/orders-processor:v1.3.0`. That image was built from `acfb7ab`, not the release commit `8f5e0b6`, and has a different image ID from the CI artifact. This repeats L3-5's original defect (one name, different content) through a different route. It is also a **latent outage**: any pull from the registry (new node, image GC, cluster rebuild) fails for dev, test and prod at once. | (a) Point all three values files at the CI artifact **by digest**: `ghcr.io/brunobml/orders-processor:1.3.0@sha256:3fc6e216e13c22db612253d9a844d915899e490acd0815a72d92e5c1279bd70e`. (b) Remove the imported image from all 4 nodes (`crictl rmi ghcr.io/brunobml/orders-processor:v1.3.0`) so the kubelet pulls from GHCR. (c) Verify the pods' `imageID` is the GHCR digest and the footer shows `8f5e0b6`. (d) For future releases, use `type=semver,pattern=v{{version}}` (or `type=ref,event=tag`) so Git tag and image tag match. (e) Add to the runbook: **never `k3d image import` under a registry tag**; use a distinct local name (e.g. `orders-processor:dev-local`) for inner-loop testing. |
| **PV-2** | Low | **The preflight accepts a local `main` that is behind `origin/main`.** `merge-base --is-ancestor HEAD origin/main` is true for an older local commit, so a stale working copy can promote an outdated revision (for example, undo a rollback someone else just pushed). | After the fetch, require `[[ $(git rev-parse HEAD) == $(git rev-parse origin/main) ]]`, or compare the file directly: `git diff --quiet origin/main -- clusters/blueprint-revisions.env`. |
| **PV-3** | Info | **Review item F-5 is not yet addressed, and the report repeats it:** `phase2-implemented-01.md` contains 6 `file:///home/bleite/...` links. The L1-6 check excludes `docs/remediation/`, so it won't flag them. | Use repo-relative or GitHub links in remediation docs, or add a separate check over `docs/remediation/` that allows only the quoted grep pattern. |
| **PV-4** | Info | `projects/*.yaml` (including the new `default.yaml`) is still applied by `make bootstrap` / `kubectl`, not reconciled by `root-control-plane` (which syncs only `applicationsets/`). The `default` lockdown can drift silently. | Fold into L2-1 (GitOps-managed platform layer): have the root app also sync `projects/`. |
| **PV-5** | Info | The acceptance criterion for L4-7 should read "the controller refuses to sync", not "cannot be created" (see Step 4 note). | Wording only. |

---

## 4. Phase 2 status after Run #01

| Finding | Sev | Status |
|---|:-:|:-:|
| L3-1 ACK drift window | High | ✅ **Closed** (live drift test passed) |
| L3-4 Smoke tests | Medium | ✅ **Closed** |
| L4-7 `default` AppProject | Medium | ✅ **Closed** (PV-4 drift caveat) |
| L1-4 Dead `tenant-workloads` repo refs | Medium | ✅ **Closed** |
| X-1 Promotion preflight | Info | ✅ **Closed** (PV-2 refinement) |
| L4-3 Pod Security + NetworkPolicy | High | ◑ **Partial**: PSS enforced ✅; NetworkPolicy pending plan v1.1 (P2-B4) |
| L3-5 Immutable CI tags | High | ⛔ **Open**: PV-1 |
| L4-1 Headlamp gateway | Critical | ⏳ Pending plan v1.1 (P2-B1 to B3) |
| L2-2 Prod workload gate | High | ⏳ Pending plan v1.1 (P2-B6); **depends on PV-1** |
| L4-4 Multi-account (CARM) | High | ⏸ Deferred (P2-B5) |
| L4-2, L3-2, L2-1 | High | ⏳ Unscheduled: F-1 asks for an explicit deferral in v1.1 |

## 5. Next actions (in order)

1. **Fix PV-1** (digest-pin to the CI artifact, purge the imported images, fix the `v` prefix), then re-verify Step 1. A short focused re-validation is enough.
2. **Before 2026-10-31 ~01:00 UTC:** `make rotate-spoke-tokens` (unless Track 2 lands first and replaces the Headlamp tokens).
3. Submit **plan v1.1** addressing P2-B1 to B6 and F-1 to F-5 for re-review of Tracks 2–4 and Step 9.
4. Update the Phase 2 sign-off table: C-1 should read "⚠️ Reopened (PV-1)", not "✅ Resolved".
