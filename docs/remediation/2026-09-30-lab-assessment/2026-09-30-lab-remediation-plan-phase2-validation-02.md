# Phase 2 Remediation Validation — Run #02 (2026-10-01)

| | |
|---|---|
| **Validates** | [`2026-09-30-lab-remediation-plan-phase2-implemented-02.md`](2026-09-30-lab-remediation-plan-phase2-implemented-02.md) (commit `92357b9`) |
| **Commits under test** | `orders-processor@ca4797a` · `platform-catalog@7fab51d` (tag `v1.2.0`) · `gitops-control-plane@aac4a0f`, `a7e4062`, `9d3fff6`, `81e4cb6` |
| **Against** | [Phase 2 plan v1.1](2026-09-30-lab-remediation-plan-phase2.md) and **mandatory corrections MC-1 to MC-5**; Validation-01 observations PV-1 and PV-2 |
| **Method** | Independent checks against the live clusters, the GHCR registry API, Argo CD application history, and all three Git repos. Connectivity was tested from inside the workload pods. Headlamp's own proxy was exercised over HTTP. The promotion preflight was tested in throwaway clones. |
| **Changes made by this validation** | One short-lived control pod `netpol-control-probe` in `orders-dev` (PSS-compliant, created and deleted). One **rejected** write attempt through Headlamp (HTTP 403; nothing created). Scratch clones removed. No commits. |
| **Validated By / Date** | Claude (Opus 5.5) · 2026-10-01 |

## Verdict

> ### ✅ VALIDATED — Phase 2 authorized scope is complete
>
> All five mandatory corrections (MC-1 to MC-5) are implemented **as specified** and verified on the live system. PV-1 (the High defect from Validation-01) is closed: every workload runs the CI-built GHCR artifact by digest. The production workload gate has been **observed under divergence** in Argo CD's own deploy history.
>
> | Step | Finding | Result |
> |---|---|:-:|
> | 1 | L3-5 / PV-1 / MC-4 Provenance | ✅ **Closed** |
> | 5 | X-1 / PV-2 Promotion preflight | ✅ **Closed** |
> | 6–7 | L4-1 / MC-1 / MC-5 Headlamp | 🟡 **Mitigated** (as planned; residual risk noted) |
> | 9 | L4-3 / MC-2 NetworkPolicy | ✅ **Closed** (PSS from Run #01 + egress policy) |
> | 11 | L2-2 / MC-3 Prod workload gate | ✅ **Closed** |
>
> Five non-blocking observations (PV2-1 to PV2-5) follow. One is a process issue: a **force-push to `orders-processor@main`** was used to remove a test commit.

---

## 1. Step-by-step validation

### Step 1: L3-5 / PV-1 / MC-4, artifact provenance ✅

| Check | Evidence | Result |
|---|---|:-:|
| Values pinned by digest | All 3 `deploy/values-*.yaml` at `ca4797a`: `ghcr.io/brunobml/orders-processor:1.3.0@sha256:3fc6e216…d70e` | ✅ |
| CI tag pattern | `ci.yaml`: `type=semver,pattern=v{{version}}`, `type=sha,format=short,prefix=sha-` | ✅ |
| **Pods run the registry artifact** | All 4 pods: `imageID = ghcr.io/brunobml/orders-processor@sha256:3fc6e216…`; 0 restarts, Ready | ✅ |
| **Imported image purged (MC-4)** | `crictl images` on all 4 nodes: no `orders-processor:v1.3.0`. The cached `<none>/d3aeb027…` matches the **CI artifact's config digest** (see Validation-01) | ✅ |
| Runtime provenance | Live footers for dev, test and prod: `Git Commit: 8f5e0b6`, the release commit (was `acfb7ab` in Validation-01) | ✅ |

### Step 5: X-1 / PV-2 promotion preflight ✅

Throwaway clone with a local bare `origin`:

| Scenario | Result |
|---|:-:|
| `main`, in sync with `origin/main` | ✅ passes preflight (stops at the spoke-name guard as intended) |
| **`main` behind `origin/main`** (the PV-2 gap) | ✅ `Local 'main' is not in sync with origin/main` |
| `main`, unpushed local commit | ✅ rejected (same message) |
| Feature branch | ✅ `Promotion must be run from 'main' branch` |

### Track 2: L4-1 Headlamp (MC-1, MC-5) 🟡 Mitigated

| Check | Evidence | Result |
|---|---|:-:|
| **MC-1a** correct chart key | Live `addon-headlamp` values: `automountServiceAccountToken: false` (top-level) | ✅ |
| **MC-1b** binding removed at the source | Values: `clusterRoleBinding.create: false`. `ClusterRoleBinding/headlamp-admin` → **NotFound** (more than 25 min after sync, with `selfHeal: true`, so it is not coming back). No `cluster-admin`/`headlamp-admin` reference remains in `setup-credentials.sh`, `values.yaml` or `addon-headlamp.yaml` | ✅ |
| Pod token not mounted | Live pod: `automountServiceAccountToken=false`, volumes = `kubeconfig` only (no `kube-api-access-*`) | ✅ |
| `-insecure-ssl` removed | Live args: `-plugins-dir … -session-ttl … -kubeconfig=… -dev` | ✅ |
| **Strict TLS** | Kubeconfig (structure inspected; no token values printed): all 3 clusters `insecure-skip-tls-verify: false`, `certificate-authority-data` present, servers `k3d-*-server-0:6443` | ✅ |
| **Decoupled from Argo CD tokens** | JWT `sub` claim of all 3 kubeconfig tokens = `system:serviceaccount:headlamp-access:headlamp-viewer`, lifetime 720 h. Not `argocd-manager` | ✅ |
| Only bindings for Headlamp identities | On each cluster, exactly `ClusterRoleBinding/headlamp-viewer-binding → view` | ✅ |
| Aggregation in place | Built-in `view` on the spokes now includes `kro.run`, `internal.kro.run`, `sqs.services.k8s.aws`, `services.k8s.aws` | ✅ |
| `last-applied` on `headlamp-kubeconfig` | 0 B | ✅ |

**MC-5 least-privilege matrix**, re-run independently (`kubectl auth can-i --as=system:serviceaccount:headlamp-access:headlamp-viewer`):

| Cluster | pods/log | queues.sqs | rgd.kro | graphrevisions | **secrets (argocd)** | **create deploy** | **delete ns** | configmaps | **pods/exec** |
|---|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|
| hub | ✅ | n/a¹ | n/a¹ | n/a¹ | ❌ | ❌ | ❌ | ✅ | ❌ |
| spoke-nonprod | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ✅ | ❌ |
| spoke-prod | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ✅ | ❌ |

¹ kro and ACK CRDs aren't installed on the hub.

**End-to-end through Headlamp's own proxy** (`http://headlamp.localhost:8080/clusters/<ctx>/…`):

| Request | Result |
|---|:-:|
| `GET /api/v1/namespaces` on hub / nonprod / prod | ✅ 200 / 200 / 200 |
| `POST` ConfigMap into `orders-prod` | ✅ **403**; object not created |
| `GET` Secrets in hub `argocd` namespace (spoke credentials) | ✅ **403** |
| Headlamp log lines matching `x509\|certificate` | 1, benign (`TLS certificate path:` at startup) |

### Step 9: L4-3 NetworkPolicy via RGD (MC-2) ✅

| Check | Evidence | Result |
|---|---|:-:|
| RGD healthy after change | `queuebackedservice` `Active / Ready=True` on both spokes | ✅ |
| Placed by kro in the instance namespace (no `metadata.namespace`) | `orders-dev/orders-dev-netpol`, `orders-test/orders-test-netpol`, `orders-prod/orders-prod-netpol`; selectors `app: orders-<env>-worker` | ✅ |
| Shipped through the blueprint gate | `platform-catalog` tag `v1.2.0^{}` → `7fab51d`; `blueprint-revisions.env` `spoke-prod=v1.2.0` matches the cluster Secret annotation; `kro-blueprints-spoke-prod` target `v1.2.0` → `7fab51d`, Synced | ✅ |
| Probes survive kube-router | All worker pods Ready, **0 restarts** | ✅ |

**Connectivity tested from inside each worker pod:**

| Destination | orders-dev | orders-test | orders-prod |
|---|:-:|:-:|:-:|
| DNS `moto-cloud` → `172.21.0.9` | ✅ | ✅ | ✅ |
| `moto-cloud:5000` | ✅ open | ✅ open | ✅ open |
| `1.1.1.1:443` | ❌ blocked | ❌ blocked | ❌ blocked |
| `8.8.8.8:53/tcp` | ❌ blocked | ❌ blocked | ❌ blocked |
| moto host, other port (`:22`) | ❌ blocked | ❌ blocked | ❌ blocked |
| kube-apiserver `10.43.0.1:443` | ❌ blocked | ❌ blocked | ❌ blocked |

**Control sample:** an **unselected** pod in `orders-dev` (same image, PSS-compliant, deleted afterwards) reached `1.1.1.1:443` **and** `10.43.0.1:443`. This proves (a) the cluster has outbound connectivity in general, so the blocks are caused by the policy, and (b) pods outside the policy are unaffected, as MC-2 required. It also shows the policy is workload-scoped (PV2-2).

Ingress: Traefik → `orders-{dev,test,prod}` returns HTTP 200 (smoke test stage 7 and Headlamp checks).

### Step 11: L2-2 production workload gate (MC-3) ✅

| Check | Evidence | Result |
|---|---|:-:|
| Minimal diff | `tenant-workloads-prod.yaml`: List element keeps `app/tenant/env/port` and adds `valuesRevision: ca4797acbed2…`. Only the `ref: values` source changed (`'{{valuesRevision}}'`); the chart source is still `ghcr.io/brunobml/charts` / `queue-backed-service` / `1.0.0` | ✅ |
| Immutable, pullable ref | Full 40-character SHA `ca4797a…`, the PV-1 digest-pin commit | ✅ |
| Live targets | `orders-prod` targets `[1.0.0, ca4797a…]`; `orders-dev`/`orders-test` targets `[1.0.0, main]`; all Synced/Healthy | ✅ |
| Self-heal kept (F-2) | `automated: {prune: true, selfHeal: true}` | ✅ |
| **Divergence observed in Argo CD history** | `orders-dev` deployed `c594f1b` at `03:40:08Z`, then `ca4797a` at `03:40:35Z`. `orders-prod` history: `8f5e0b6 → ca4797a → ca4797a → ca4797a`. It **never** deployed `c594f1b` | ✅ |

---

## 2. Regression check

| Outcome | Live result | |
|---|---|:-:|
| Smoke test (`scripts/smoke-test-hub-spoke.sh`) | exit 0, all 7 stages | ✅ |
| Legacy SA-token Secrets | 0 / 0 / 0 | ✅ |
| `last-applied` on credential Secrets | 0 B × 3 | ✅ |
| Argo CD clusters | `spoke-nonprod`, `spoke-prod`, `in-cluster`: Successful | ✅ |
| ACK resync | 300 s on both spokes | ✅ |
| PSS | `restricted` on `orders-dev`, `orders-test`, `orders-prod` | ✅ |
| Workload SA / PDB | `orders-*-sa`; PDB only `orders-prod-pdb` | ✅ |
| `default` AppProject | `sourceRepos: []`, `destinations: []` | ✅ |
| Path hygiene | Repo `git grep` → 0; `phase2-implemented-02.md` → 0 `file:///` (PV-3 holds) | ✅ |

---

## 3. Observations (non-blocking)

| ID | Sev | Observation | Recommendation |
|---|---|---|---|
| **PV2-1** | Low | **Force-push to a release branch.** To remove the gate-test commit, `orders-processor@main` was reset (`reflog: "reset: moving to HEAD~1"`) and force-pushed. `c594f1b` had already been on `origin/main`: CI built and published **`sha-c594f1b`** to GHCR, and `orders-dev`/`orders-test` deployed it. The content was README-only, so there was no functional impact, but GHCR now holds an image of an orphaned commit, and Argo CD history references a commit that's no longer on any branch. The report's "reset … cleanly" understates this. | Use `git revert` for test commits on shared branches (history is audit evidence), or run gate tests from a throwaway branch via a temporary AppSet element. Enable branch protection ("no force pushes") on `main` in `orders-processor`, `platform-catalog` and `gitops-control-plane`. Optionally delete the `sha-c594f1b` package version. |
| **PV2-2** | Info | **The NetworkPolicy is workload-scoped, not a namespace default-deny.** The plan and report call it "default-deny", but it selects only `app: <name>-<env>-worker`. Any other pod in `orders-*` (proven by the control probe) has unrestricted egress, including to the kube-apiserver. | Either reword it as a "workload egress allow-list", or add a second RGD resource: a namespace-wide `podSelector: {}` deny-all plus a DNS allowance (policies are additive, so the worker's allow-list still applies). Ship it via `v1.3.0` through the blueprint gate. |
| **PV2-3** | Info | On the hub, the viewer cannot list `applications.argoproj.io`, so Headlamp no longer shows Argo CD objects (it did under cluster-admin). This is a deliberate least-privilege side effect. | If wanted, add a hub-only aggregated role with `get/list/watch` on `argoproj.io` `applications`, `applicationsets`, `appprojects`. These objects hold no credentials; repository and cluster credentials are Secrets and stay hidden. |
| **PV2-4** | Info | **L4-1 residual risk, now concrete.** Headlamp is still unauthenticated on `0.0.0.0:8080` with `-dev`. Anyone who can reach that port can read **pod logs and ConfigMaps on all three clusters, including prod** (no Secrets, no writes, no exec, all verified). This is the accepted, documented residual of the "Mitigated" status (F-3). | Phase 3: bind the k3d load balancer to `127.0.0.1` and/or put OIDC in front. |
| **PV2-5** | Info | **Two token expiries are close together.** `argocd-manager`: **2026-10-31 ~01:00–01:15 UTC**. `headlamp-viewer` (×3): **2026-10-31 03:31 UTC**. `make rotate-spoke-tokens` runs `register-spokes.sh` and then the new `setup-credentials.sh`, so one run renews both. Nothing alerts on expiry yet. | Rotate before 2026-10-31 ~00:00 UTC. Phase 3 (with L3-3 observability) could alert on `lab/token-expires`. |

Out of scope and unchanged (tracked for Phase 3 / Rec 18): `argocd-manager` is still bound to `cluster-admin` on both spokes.

---

## 4. Phase 2 closure status

| Finding | Sev | Status |
|---|:-:|:-:|
| L3-5 Immutable CI tags / provenance | High | ✅ Closed (Run #02) |
| L3-1 ACK drift window | High | ✅ Closed (Run #01) |
| L4-3 Pod Security + NetworkPolicy | High | ✅ Closed (PSS Run #01; NetworkPolicy Run #02; see PV2-2) |
| L2-2 Prod workload promotion gate | High | ✅ Closed (Run #02) |
| L4-1 Headlamp gateway | Critical | 🟡 **Mitigated**: least privilege, strict TLS, no hub admin; unauthenticated access remains (PV2-4) |
| L3-4 Smoke tests | Medium | ✅ Closed (Run #01) |
| L4-7 `default` AppProject | Medium | ✅ Closed (Run #01) |
| L1-4 Dead repo refs | Medium | ✅ Closed (Run #01) |
| X-1 / PV-2 Promotion preflight | Low/Info | ✅ Closed (Run #02) |
| MC-1 to MC-5 | Review | ✅ All verified |
| L4-4, L4-2, L3-2, L2-1/L3-8 | High | ⏸ Deferred to Phase 3 (F-1) |

**Phase 2 validation closed.** Recommended Phase 3 entry items, in order: rotate tokens before 2026-10-31; branch protection (PV2-1); L4-2 Argo CD auth/TLS; Headlamp authentication (L4-1 residual); L2-1 GitOps-managed platform layer (including `projects/`, PV-4); L3-2 moto persistence; L4-4 CARM with per-environment worker credentials.
