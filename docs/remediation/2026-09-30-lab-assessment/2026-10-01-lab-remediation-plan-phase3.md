# Lab Remediation Plan: Phase 3 — Identity, Platform-as-GitOps, Least Privilege & Cloud Isolation
## Hub-and-Spoke GitOps Control Plane (2026-10-01)

> **Status: Historical.** Record of the 2026-09-30 assessment and its remediation (Phases 1–5, closed 2026-10-03). Kept as evidence and not updated. For the lab as it is today, see the [README](../../../README.md) and the [2026-10-03 assessment](../../assessments/2026-10-03-lab-assessment.md).

* **Plan Version:** 1.0 (initial submission)
* **Assessment Reference:** [`../assessments/2026-09-30-lab-assessment.md`](../../assessments/2026-09-30-lab-assessment.md)
* **Phase 2 Baseline:** [`2026-09-30-lab-remediation-plan-phase2-validation-02.md`](2026-09-30-lab-remediation-plan-phase2-validation-02.md) (Phase 2 authorized scope closed; L4-1 *Mitigated*)
* **Target Repositories:** `gitops-control-plane`, `platform-catalog`, `orders-processor`
* **Author:** Claude (Opus 5.5)

---

## Review & Approval Sign-Off

| Field | Details |
|---|---|
| **Current Status** | 🟢 **APPROVED & AUTHORIZED FOR IMPLEMENTATION (Plan v1.0)** |
| **Plan Version** | `v1.0` (commit [`c568af6`](https://github.com/brunobml/gitops-control-plane/commit/c568af6)) |
| **Author** | Claude (Opus 5.5) |
| **Reviewed By** | Antigravity (Advanced Agentic AI Peer Reviewer) |
| **Review Date** | 2026-10-01 |
| **Authorization Decision** | ✅ **GREEN LIGHT** — Fully approved for execution following the sequenced tracks (§8). Remarks R-0 through R-4 apply. |

### Reviewer Decision & Feedback

> ### ✅ REVIEW VERDICT: APPROVED (GREEN LIGHT)
>
> The Phase 3 remediation plan is exceptionally well-conceived, technically rigorous, and grounded in verified pre-flight facts (F1–F12). The phasing appropriately balances urgent security posture, platform GitOps adoption, and cloud isolation.
>
> **All tracks (Track 0, Track A, Track B, Track C, Track D) are authorized for implementation.** The specific remarks and operational guardrails below govern execution.

| ID | Focus Area | Reviewer Remark & Operational Guardrail | Status |
|:---:|:---:|---|:---:|
| **R-0** | Step 0.1 | **Token Rotation Immediate Authorization:** Step 0.1 (`make rotate-spoke-tokens`) is granted immediate execution approval to neutralize the 2026-10-31 expiration deadline before other tracks commence. | ✅ Immediate Go |
| **R-1** | Step C.2 | **Impersonation Preflight Verification:** Before toggling `application.sync.impersonation.enabled: "true"` in `argocd-cm`, an automated audit script must verify that *all* active AppProjects (`tenant-workloads`, `platform-catalog`, `platform-addons`, `control-plane`, `default`) define and have applied their corresponding `destinationServiceAccounts`. | 🛡️ Guardrail Approved |
| **R-2** | Step B.2 | **Adoption Resource Safety:** Ensure `argocd.argoproj.io/preserve-resources-on-deletion: "true"` is annotated on the `addons-spoke` ApplicationSet template *before* applying the cluster label `addons-managed=true`, ensuring controllers are never deleted if the ApplicationSet is modified. | 🛡️ Guardrail Approved |
| **R-3** | Step D.3 | **CARM Canary Migration Gate:** If the non-prod canary (D.3a) demonstrates that modifying `services.k8s.aws/owner-account-id` causes ACK reconciliation errors rather than in-place recreation, execute D.3c by draining prod, deleting the namespace Queue CRs, and allowing Kro to re-stamp them in the target account. | 🛡️ Guardrail Approved |
| **R-4** | Step A.1 | **Experimental Port Deletion Fallback:** If `k3d cluster edit --port-delete` produces unexpected container recreation or port conflict errors on running clusters, leave the live loadbalancer mapping intact and enforce the durable `127.0.0.1` binding during the Step B.7 rebuild window. | 🛡️ Guardrail Approved |

---

## 1. Executive Summary & Scope

Phases 1 and 2 closed every Low finding and the Phase 2 Critical/High scope that could be fixed without new identity or platform machinery. What remains is structural: **who can reach and change the platform**, **whether the platform itself is declared in Git**, **least privilege for the controllers that deploy into the spokes**, and **real per-environment cloud isolation**.

### 1.1 Objectives

| Track | Theme | Findings addressed |
|---|---|---|
| **0** | Time-critical operations and repository hygiene | PV2-5 (token expiry), PV2-1 (force-push / branch protection), L3-3 (minimal: expiry check) |
| **A** | Access and exposure | **L4-2** (Argo CD admin/admin123), **L4-1 residual** (unauthenticated Headlamp, PV2-4), **L4-9** (0.0.0.0 bindings), PV2-3 |
| **B** | Platform layer as GitOps | **L2-1 / L3-8** (imperative controller installs), PV-4 (`projects/` not reconciled), L3-6 (unpinned versions), L3-7 (sync retries) |
| **C** | Least privilege and tenant guardrails | **L4-6** (tenant `*:*` kinds), **L4-5** (kro `*/*`), **Rec 18** (`argocd-manager` = cluster-admin), PV2-2 (namespace default-deny) |
| **D** | Cloud isolation and resilience | **L4-4** (CARM multi-account, deferred from Phase 2 P2-B5), **L3-2** (moto ephemeral), L3-9 (deletion policy), L2-5 / L2-6 (blueprint contract) |

### 1.2 Out of scope (deferred to Phase 4, with reasons)

| Item | Reason for deferral |
|---|---|
| L3-3 full observability (kube-prometheus-stack, alerts) | Heavy for a laptop lab; Step 0.2 adds the one alert that is urgent today (token expiry). |
| L4-8 image signing and admission verification (cosign + Kyverno) | Depends on the CI pipeline and admission tooling; independent of this phase's tracks. |
| SSO for Argo CD / Headlamp (Dex + GitHub OAuth) | Needs an external GitHub OAuth App (credentials outside the lab). Track A delivers local accounts + RBAC + authentication now. |
| TLS on the Argo CD / Headlamp UIs | Once A.1 binds them to `127.0.0.1`, plain HTTP is a documented residual; certificates (mkcert/cert-manager) follow in Phase 4. |
| L2-3 / L2-4 ApplicationSet modernization (`goTemplate`, Git-files generator) | Large template rewrite; deliberately not mixed with the B.2 adoption change. |
| Argo CD HA, real EKS translation | Beyond lab parity goals for this phase. |

---

## 2. Pre-flight Facts (verified live on 2026-10-01 by the author)

Every design choice below depends on these facts. The reviewer is invited to re-check any of them.

| # | Fact | Evidence | Used by |
|---|---|---|---|
| F1 | Spoke `argocd-manager` tokens expire **2026-10-31 ~01:00–01:15 UTC**; Headlamp viewer tokens **2026-10-31 03:31 UTC** | `lab/token-expires` annotations; JWT `exp` claims (Phase 2 Validation-02) | 0.1 |
| F2 | All 4 GitHub repos are **public**; `main` is **not protected** in `orders-processor` (`protected=false`) | GitHub REST API | 0.3 |
| F3 | `k3d v5.9.0` supports `cluster edit --port-add` and **`--port-delete` [EXPERIMENTAL]** | `k3d cluster edit --help` | A.1 |
| F4 | Hub Traefik has the `middlewares.traefik.io` CRD | `kubectl get crd` | A.3 |
| F5 | Argo CD chart `10.9.4` / app `v3.5.3`; `admin.enabled=true`; the admin bcrypt hash is committed at `clusters/values-argocd-hub.yaml:36`; no `accounts.*` defined | live `argocd-cm`, Git | A.2 |
| F6 | `application.sync.impersonation.enabled=false`; the AppProject CRD supports `destinationServiceAccounts` and `sourceNamespaces` | live `argocd-cm`, CRD schema | C.2 |
| F7 | kro chart `0.9.4` offers `rbac.mode: aggregation` (aggregates ClusterRoles labelled `rbac.kro.run/aggregate-to-controller: "true"`); default `unrestricted` | `helm show values` | C.3 |
| F8 | The golden chart `queue-backed-service:1.0.0` renders **only** `kro.run/v1alpha1 QueueBackedService` | `helm template` | C.1 |
| F9 | moto image `motoserver/moto:latest` (= `5.2.3.dev0`, image `sha256:44fa7c38…`), **no volumes**, restart `unless-stopped`; recorder endpoint not enabled (HTTP 500) | `docker inspect`, `pip show`, `curl` | B.5, D.2 |
| F10 | **CARM is feasible with a small app change.** In moto, a queue in account `999999999999` is visible to a worker-style raw request whose `Credential=` carries an **IAM access key created in that account**, but returns `NonExistentQueue` with today's `Credential=mock` | Live probe (assume-role → IAM user + key → raw `GetQueueAttributes`); probe resources deleted | D.1, D.3 |
| F11 | ACK SQS chart `1.7.1`: `enableCARM: true` (running with `--enable-carm=true`); controller RBAC can `get/list/watch` ConfigMaps; feature gates `ServiceLevelCARM=false`, `TeamLevelCARM=false`, `IAMRoleSelector=false` | `helm show values` / `helm template` / live ClusterRole | D.3 |
| F12 | Repository server has outbound internet (an unselected pod reached `1.1.1.1:443`); OCI chart registries are reachable for Argo CD | Phase 2 Validation-02 control probe | B.2 |

---

## 3. Track 0: Time-Critical Operations & Repository Hygiene

### Step 0.1: Rotate cluster and Headlamp tokens (PV2-5) ⏰ before 2026-10-31 00:00 UTC
* Run `make rotate-spoke-tokens` (it runs `register-spokes.sh`, then the Phase 2 `setup-credentials.sh`).
* **Acceptance:** `lab/token-expires` ≈ today + 30 days on both cluster Secrets; Headlamp viewer JWT `exp` ≈ today + 30 days; `argocd cluster list` all `Successful`; smoke test passes; Headlamp loads 3 clusters.

### Step 0.2: Smoke-test token-expiry stage (L3-3, minimal)
* Add stage `[8/8]` to `scripts/smoke-test-hub-spoke.sh`: read `lab/token-expires` on every cluster Secret, and the `exp` claim of each Headlamp kubeconfig user (decode claims only; never print tokens). **WARN** if < 7 days, **FAIL** if expired.
* **Acceptance:** a negative test (fake expiry via a temporary annotation on a *copy*, or a shim) fails; the normal run passes and prints days remaining.

### Step 0.3: Branch protection on all four repos (PV2-1)
* Owner action in the GitHub UI (the `gh` CLI is not installed): on `main` of `gitops-control-plane`, `platform-catalog`, `orders-processor` and `platform-charts`, **block force pushes** and **block deletion**. "Require a pull request" is optional for a solo owner. If enabled, use 0 required approvals so solo work isn't blocked.
* Runbook rule: test commits on shared branches are undone with **`git revert`**, never `reset` + force-push.
* **Acceptance:** `GET /repos/brunobml/<repo>/branches/main` → `"protected": true` for all 4.

### Step 0.4: Orphaned artifact clean-up (optional)
* Delete GHCR package version `sha-c594f1b` (built from the force-pushed test commit) in the GitHub UI.

---

## 4. Track A: Access & Exposure

### Step A.1: Bind every host port to `127.0.0.1` (L4-9, PV2-4)
* **Durable fix (for rebuilds):** in `scripts/setup-hub-spoke.sh` use `--port "127.0.0.1:8080:80@loadbalancer"` (and `8443`, `8081`, `8082`), `--api-port 127.0.0.1:<port>`, and `docker run -p 127.0.0.1:5000:5000` for moto.
* **Live clusters (no rebuild):** per cluster, add the localhost mapping first, then delete the wildcard one:
  `k3d cluster edit <c> --port-add 127.0.0.1:8080:80@loadbalancer` → verify → `k3d cluster edit <c> --port-delete 8080:80@loadbalancer`. Back up first: `k3d kubeconfig get --all > /tmp/kubeconfig-backup`.
* **API ports** (`0.0.0.0:<random>`) are **only** rebound in a rebuild (B.7). `--port-delete` on the API mapping would break kubeconfigs mid-flight.
* **moto** is rebound when its container is recreated in **D.2** (one planned restart, not two).
* **Acceptance:** `docker port` shows only `127.0.0.1` for 8080/8443/8081/8082 (and 5000 after D.2). URLs still work from WSL and from the Windows browser via `localhost` (WSL2 NAT localhost forwarding); verify manually.
* **Risk:** `--port-delete` is experimental. Rollback: `--port-add 0.0.0.0:…` restores the old mapping.

### Step A.2: Argo CD identities (L4-2)
1. **Stop publishing a credential.** Remove `configs.secret.argocdServerAdminPassword(Mtime)` from `clusters/values-argocd-hub.yaml`. Its hash stays in Git history; rotating the password (step 3) is what neutralises it.
2. **Local accounts + RBAC** (in Helm values → Git):
   ```yaml
   configs:
     cm:
       accounts.platform-admin: login
       accounts.tenant-a: login
     rbac:
       policy.default: ""            # deny by default
       policy.csv: |
         g, platform-admin, role:admin
         p, role:tenant-a, applications, get,  tenant-workloads/*, allow
         p, role:tenant-a, applications, sync, tenant-workloads/orders-dev,  allow
         p, role:tenant-a, applications, sync, tenant-workloads/orders-test, allow
         p, role:tenant-a, logs,         get,  tenant-workloads/*, allow
         g, tenant-a, role:tenant-a
   ```
3. Set passwords **only in the cluster** (`argocd account update-password --account …`), generated randomly and never written to Git. Rotate the `admin` password to a random value at the same time.
4. After `platform-admin` is verified, set `admin.enabled: "false"`.
5. Change `make password` to print retrieval instructions instead of `admin123`, and update the README and tutorial.
* **Acceptance:** `admin123` login fails. `admin` is disabled. `platform-admin` can sync everything. `tenant-a` can view tenant apps and sync dev/test, but `argocd app sync orders-prod` → `permission denied`, and it cannot see `control-plane` or `platform-catalog` apps. `git grep -n '\$2a\$'` → 0 matches.

### Step A.3: Authenticate Headlamp (L4-1 residual → Closed)
1. Create a Traefik `Middleware` `headlamp-auth` (basicAuth) in namespace `headlamp`, versioned in Git (`addons/headlamp/manifests/middleware.yaml`), deployed by a new Application `addon-headlamp-auth` (project `control-plane`, path `addons/headlamp/manifests`).
2. Generate the htpasswd Secret `headlamp-basic-auth` with a script (`addons/headlamp/setup-auth.sh`); it is **not in Git**. Use a random password and print it once.
3. Add the ingress annotation in `addon-headlamp.yaml`: `traefik.ingress.kubernetes.io/router.middlewares: headlamp-headlamp-auth@kubernetescrd`.
4. **PV2-3:** on the hub only, add an aggregated read role for `argoproj.io` `applications`, `applicationsets`, `appprojects` (no Secrets) to `setup-credentials.sh`.
* **Acceptance:** `curl` without credentials → **401**; with credentials → 200; all 3 clusters load. Phase 2 checks still hold (write → 403, Secrets → 403). The hub viewer `can-i list applications.argoproj.io` → yes. Combined with A.1, Headlamp is local-only, authenticated and read-only. **L4-1 → Closed** (residual: `-dev` CORS relaxation and HTTP; see §1.2).

---

## 5. Track B: Platform Layer as GitOps

### Step B.1: Reconcile `projects/` (PV-4)
* Add `applicationsets/platform-projects.yaml`: an Application `platform-projects` (project `control-plane`, path `projects`, `selfHeal: true`, **`prune: false`** and `argocd.argoproj.io/sync-options: Prune=false` on each AppProject, so an AppProject that apps still reference is never deleted by accident).
* **Acceptance:** a manual live edit to `tenant-workloads.spec.sourceRepos` is reverted by self-heal; `platform-projects` Synced/Healthy.

### Step B.2: Spoke controllers as an ApplicationSet (L2-1, L3-8, L3-6)
1. **New AppProject `platform-addons`:** `sourceRepos` = `https://github.com/brunobml/platform-catalog.git`, `public.ecr.aws/aws-controllers-k8s`, `registry.k8s.io/kro/charts`; destinations = both spokes, namespaces `kro`, `ack-system`; cluster-scoped `*` (the controllers ship CRDs and ClusterRoles). Register both OCI Helm repos (`enableOCI: "true"`) in `values-argocd-hub.yaml`.
2. **New `applicationsets/addons-spoke.yaml`:** a matrix of the Cluster generator (label `addons-managed: "true"`) × a List generator:
   | addon | chart | version | releaseName / namespace | values |
   |---|---|---|---|---|
   | kro | `registry.k8s.io/kro/charts/kro` | `0.9.4` | `kro` / `kro` | `$values/controllers/kro/values-kro.yaml` |
   | ack-sqs | `public.ecr.aws/aws-controllers-k8s/sqs-chart` | `1.7.1` | `ack-sqs-controller` / `ack-system` | `$values/controllers/ack/values-sqs.yaml` |
   Multi-source with `ref: values` → `platform-catalog@main`. Sync options `ServerSideApply=true` (large ACK CRDs), `CreateNamespace=true`, `retry` with backoff. The ACK credentials Secret is a separate source (`controllers/ack/credentials-secret.yaml`) with `sync-wave: "-1"`. *It contains mock values; in production this is replaced by Pod Identity, see §1.2 of the assessment.*
3. **Adoption without downtime, one cluster at a time:** label **only** `cluster-spoke-nonprod` with `addons-managed=true`. Argo CD adopts the existing objects (same release names, so the same object names). Confirm Synced/Healthy with **no controller restart beyond one rolling update**, then remove Helm's ownership records so `helm` no longer claims them: `kubectl -n kro delete secret -l owner=helm,name=kro` and `kubectl -n ack-system delete secret -l owner=helm,name=ack-sqs-controller`. Repeat for prod.
4. Remove the kro/ACK `helm upgrade --install` lines from `setup-hub-spoke.sh`. Bootstrap labels the clusters instead.
* **Acceptance:** `helm list -A` on the spokes shows no kro/ACK releases. Both addon apps × 2 spokes Synced/Healthy. `RECONCILE_DEFAULT_RESYNC_SECONDS=300` still set (now from Git). Deleting `deploy/kro` on nonprod → Argo CD recreates it. kro drift test (scale a worker) still reverts. Smoke test passes.
* **Rollback:** remove the cluster label (Argo CD stops managing; set `preserveResourcesOnDeletion: true` on the AppSet *before* the first label so nothing is deleted), then reinstall with Helm.

### Step B.3: Hub Traefik under GitOps
* Application `addon-traefik` (project `control-plane`; `traefik.github.io/charts` is already whitelisted), chart pinned to the deployed **`41.6.1`**, `releaseName: traefik`, namespace `traefik`. Adopt it the same way as B.2 (Helm secret removal afterwards). Remove the Traefik install from `setup-hub-spoke.sh`.
* **Acceptance:** Synced/Healthy; Argo CD, Headlamp and orders URLs unaffected; `helm list -n traefik` empty.

### Step B.4 (stretch): Argo CD self-management
* Application `argo-cd` (chart `10.9.4`, values `clusters/values-argocd-hub.yaml`), **manual sync** and `prune: false` at first. The bootstrap installs Argo CD once with Helm; from then on it is managed through Git.
* **Acceptance:** a values change in Git (e.g. a new RBAC line) applies through Argo CD. Rollback: `helm upgrade` from the script.

### Step B.5: Pin what is still floating (L3-6)
* moto: `motoserver/moto@sha256:44fa7c38…` (the image running now), applied in D.2.
* k3s: `--image rancher/k3s:v1.35.5-k3s1` in `setup-hub-spoke.sh`.
* Argo CD chart `--version 10.9.4` in the bootstrap Helm install.
* **Acceptance:** `grep -nE 'latest|helm upgrade --install [^-]*$' scripts/setup-hub-spoke.sh` → no unpinned installs.

### Step B.6: Sync resilience (L3-7)
* Add `syncPolicy.retry: {limit: 5, backoff: {duration: 10s, factor: 2, maxDuration: 3m}}` to every ApplicationSet template.
* *Design note:* sync waves don't order separately generated Applications (they aren't app-of-apps children), so cross-app ordering on a fresh cluster relies on retry. This is documented rather than over-engineered.

### Step B.7: Reproducibility acceptance (owner-approved, end of phase)
* `make teardown && make setup && make bootstrap` (then `setup-auth.sh` and Step 0.1 equivalents). **Requires explicit owner approval**: it destroys the live lab state; Git, GHCR and tags are unaffected.
* **Acceptance:** all apps Synced/Healthy and the smoke test passes **without any manual `helm` or `kubectl apply` beyond the documented bootstrap**. Record the wall-clock time. API ports are now bound to `127.0.0.1` (A.1 durable fix).

---

## 6. Track C: Least Privilege & Tenant Guardrails

### Step C.1: Narrow the tenant AppProject (L4-6)
* `projects/tenant-workloads.yaml`: `namespaceResourceWhitelist: [{group: kro.run, kind: QueueBackedService}]`; cluster whitelist stays `Namespace` only (F8: the golden chart renders only `QueueBackedService`).
* **Acceptance:** `orders-*` Synced/Healthy. A temporary Application in `tenant-workloads` rendering a `ConfigMap` is refused by the controller (`resource :ConfigMap is not permitted in project`); delete it afterwards.

### Step C.2: Destination impersonation & a non-admin `argocd-manager` (Rec 18)
1. On each spoke create two ServiceAccounts in `kube-system`:
   * `argocd-tenant-deployer`: a ClusterRole for `namespaces` (get/list/watch/create/patch) and `queuebackedservices.kro.run` (all verbs).
   * `argocd-platform-deployer`: `cluster-admin` (explicit, for `platform-catalog` / `platform-addons`).
2. Add `destinationServiceAccounts` to **every** AppProject: `tenant-workloads` → `argocd-tenant-deployer`; `platform-catalog`, `platform-addons` → `argocd-platform-deployer`; `control-plane` (in-cluster) → a hub `argocd-platform-deployer`.
3. Enable `application.sync.impersonation.enabled: "true"`.
4. Replace `ClusterRoleBinding/argocd-manager-cluster-admin` with a ClusterRole that has **read (`get/list/watch` on `*`) + `impersonate` on `serviceaccounts`**. Apply it on nonprod first, then prod. Update `register-spokes.sh`.
* **Hazard (author-flagged):** with impersonation enabled, a project **without** `destinationServiceAccounts` fails every sync. Step 2 must be complete and synced **before** step 3. Run `argocd proj list -o yaml` to check that all projects are covered.
* **Acceptance:** `kubectl auth can-i create deployments --as=system:serviceaccount:kube-system:argocd-manager` → **no** on both spokes. All apps still Synced/Healthy. A forced sync of each app succeeds. Argo CD events/logs show the impersonated SA.
* **Rollback:** set impersonation to `"false"` and re-bind `cluster-admin` (kept as `scripts/rollback-argocd-manager-admin.sh`).

### Step C.3: kro least privilege (L4-5)
* Requires B.2 (kro values in Git). Set `rbac.mode: aggregation` in `platform-catalog/controllers/kro/values-kro.yaml`.
* Ship a ClusterRole `kro-queue-backed-service` (label `rbac.kro.run/aggregate-to-controller: "true"`) **next to the RGD in `platform-catalog/blueprints/`**, so the blueprint and its permissions are versioned and promoted together. Verbs `*` on: `sqs.services.k8s.aws/queues`; core `configmaps`, `services`, `serviceaccounts`; `apps/deployments`; `networking.k8s.io/ingresses`, `networkpolicies`; `policy/poddisruptionbudgets`.
* Nonprod first (main), then promote via the blueprint gate.
* **Acceptance:** kro SA `can-i create secrets` → no; `can-i create clusterrolebindings` → no. RGD Active; all instances ACTIVE; the scale-drift test still reverts; deleting a child ConfigMap → recreated.

### Step C.4: Namespace default-deny (PV2-2)
* Add RGD resource `ns-default-deny`: a NetworkPolicy with `podSelector: {}`, `policyTypes: [Ingress, Egress]`, egress allowed only to kube-dns:53. The worker's allow-list (Phase 2) still applies (policies are additive). Ship it in blueprint **`v1.3.0`** (see §8).
* **Acceptance:** repeat the Phase 2 control probe. An unselected pod is now **blocked** from `1.1.1.1:443` and the API server. Workers still reach moto. Traefik → 200. 0 restarts.

---

## 7. Track D: Cloud Isolation & Resilience

### Step D.1: Worker credentials (prerequisite for CARM; mirrors IRSA / Pod Identity)
1. **App (`orders-processor`):** take the `Credential=` key ID in both `sqs_call` and `ddb_call` from `AWS_ACCESS_KEY_ID` (default `mock`). Make DynamoDB table creation lazy and retried, so the app recovers after a moto restart (see D.2). Release **`v1.4.0`** through CI (the Phase 2 `pattern=v{{version}}` fix means GHCR gets `v1.4.0`, matching the Git tag). Pin by **digest** in `deploy/values-{dev,test}.yaml`, then move prod's `valuesRevision` to that commit's SHA.
2. **RGD (`v1.3.0`):** the worker gets `envFrom: [{secretRef: {name: <name>-<env>-aws, optional: true}}]`. With no Secret present, behaviour is unchanged (falls back to `mock`), so this is safe to ship first.
* **Acceptance:** with no Secret, all workloads behave as today (smoke passes). `v1.4.0` runs from GHCR by digest, and the footer shows the release commit.

### Step D.2: moto restart resilience test (L3-2) and pin/rebind (B.5, A.1)
* A planned maintenance window: recreate `moto-cloud` with `-p 127.0.0.1:5000:5000` and the pinned digest, which **is** a restart from moto's point of view (all state lost).
* **Hypothesis to test:** with resync at 300 s (Phase 2), ACK recreates all 6 queues within ≤ 2 × 300 s; DLQ redrive policies are restored; workers recover (D.1 lazy table creation). Messages in flight are lost; this is documented as accepted lab behaviour.
* **Acceptance:** time to all 6 queues present, redrive verified, smoke passes; record the numbers. **If the hypothesis fails** (e.g. a queue is recreated before its DLQ and the redrive policy is rejected), add a moto state snapshot/restore (`MOTO_ENABLE_RECORDING` + replay) as Step D.2b. This plan does not assume it is needed.

### Step D.3: CARM multi-account isolation (L4-4)
* **D.3a Canary (nonprod, no workload):** create the ConfigMap `ack-system/ack-role-account-map` (`"111111111111": arn:aws:iam::111111111111:role/ack-sqs`, `"222222222222": arn:aws:iam::222222222222:role/ack-sqs`); create a namespace `carm-canary` annotated `services.k8s.aws/owner-account-id: "111111111111"`; apply a raw `Queue`. **Prove:** (1) the queue ARN is in `111111111111`; (2) **what ACK does to an existing Queue when the namespace annotation changes** (it adopts, recreates, or errors). The answer decides the migration method below. Delete the canary afterwards.
* **D.3b Per-account worker credentials:** `scripts/provision-worker-credentials.sh <env> <account>` assumes a role into the account, creates an IAM user and access key, and creates the Secret `<name>-<env>-aws` in the namespace. **Not in Git.** In production this whole step is replaced by Pod Identity.
* **D.3c Migrate, one environment at a time (dev → test → prod):**
  1. Declare `services.k8s.aws/owner-account-id` via `managedNamespaceMetadata.annotations` in the tenant ApplicationSets (Git).
  2. Provision the worker Secret.
  3. Apply the migration method chosen by D.3a (expected: delete the namespace's Queue CRs and let kro recreate them in the new account).
  4. Verify.
  5. Delete the orphaned queues in `123456789012`.
  For prod, drain first: wait for `ApproximateNumberOfMessages=0`.
* Non-prod (`orders-dev`, `orders-test`) → `111111111111`; prod (`orders-prod`) → `222222222222`.
* **Acceptance:** queue and DLQ ARNs in the expected accounts. **End to end:** a message sent with that account's credentials is consumed by the worker (worker log line). A message sent with default credentials → `NonExistentQueue` (isolation proven). The smoke test is updated to query each account. No queues remain in `123456789012`.
* **Rollback:** reverse the annotation, which is itself a migration. This is why D.3a must pass first and prod goes last.

### Step D.4: Retain prod cloud resources on deletion (L3-9)
* RGD (`v1.3.0`): Queue templates get `services.k8s.aws/deletion-policy: ${schema.spec.environment == "prod" ? "retain" : "delete"}`.
* **Acceptance:** the annotation is `retain` on `orders-prod-*` Queue CRs and `delete` on dev/test.

### Step D.5: Blueprint contract quality (L2-5, L2-6)
* Schema markers: `environment: string | enum="dev,test,prod"`; `replicas: integer | default=1 minimum=1 maximum=10`; `messageRetentionPeriod: string | default="345600"`.
* Remove environment-specific constants from the RGD (`MOTO_ENDPOINT`, ingress ports `8081`/`8082`). Read them from a per-cluster ConfigMap `kube-system/platform-config` via kro `externalRef` (supported in the CRD schema). The ConfigMap is managed by the B.2 addons AppSet per cluster.
* **Acceptance:** server-side dry run of a `QueueBackedService` with `replicas: 50` or `environment: prood` → **rejected**. Existing instances unchanged. Moto endpoint and ingress links come from `platform-config`.
* **Risk:** if a marker isn't supported by kro 0.9.4, it is dropped and recorded; the step does not fail.

---

## 8. Release Bundling & Sequencing

Blueprint changes are batched to limit promotions through the gate:

| Blueprint release | Contents | Promotion |
|---|---|---|
| `platform-catalog v1.3.0` | C.3 ClusterRole (inert until kro switches to aggregation), C.4 namespace default-deny, D.1 `envFrom optional`, D.4 deletion policy, D.5 schema + `externalRef` | nonprod on `main` → validate → tag → `blueprint-revisions.env` + `make promote-blueprints` |

**Execution order** (each arrow = previous step's acceptance met):

```
0.1 rotate (deadline) ─► 0.2 expiry check ─► 0.3 branch protection
  ─► A.1 port rebind (8080/8443/8081/8082) ─► A.2 Argo CD identities ─► A.3 Headlamp auth
  ─► B.1 projects ─► B.2 spoke addons (nonprod → prod) ─► B.3 hub Traefik ─► B.5/B.6 pin + retry
  ─► C.1 tenant kinds ─► blueprint v1.3.0 (nonprod) ─► C.3 kro aggregation (nonprod) ─► promote v1.3.0 + C.3 to prod
  ─► D.1 app v1.4.0 ─► D.2 moto restart test (+ moto pin/rebind)
  ─► D.3a CARM canary ─► D.3b/c migrate dev → test → prod
  ─► C.2 impersonation + non-admin argocd-manager (nonprod → prod)
  ─► B.4 (stretch) ─► B.7 rebuild acceptance (owner-approved)
```

C.2 deliberately comes late: it changes how *every* sync authenticates, so it lands once all other Argo CD-managed objects (B.x) exist and are stable.

---

## 9. Verification Matrix

| # | Area | Check | Expected |
|---|---|---|---|
| V1 | Tokens | expiry annotations / JWT `exp` | ≈ +30 days; smoke stage 8 green; negative test fails |
| V2 | Repos | GitHub API `protected` | `true` × 4 |
| V3 | Exposure | `docker port` all serverlbs + moto | only `127.0.0.1` (API ports after B.7) |
| V4 | Argo CD auth | `admin123` / `admin` / `tenant-a` sync prod | fail / disabled / denied |
| V5 | Headlamp | no-cred / cred / write / secrets | 401 / 200 / 403 / 403 |
| V6 | GitOps platform | `helm list -A` spokes + hub traefik | no kro / ACK / traefik releases; apps Synced |
| V7 | Projects | live edit of AppProject | reverted by self-heal |
| V8 | Tenant kinds | temp app rendering ConfigMap | refused by controller |
| V9 | Impersonation | `argocd-manager can-i create deployments` | no; all apps Synced |
| V10 | kro RBAC | kro SA `can-i create secrets` | no; instances ACTIVE |
| V11 | NetPol | unselected probe → `1.1.1.1:443` | blocked; worker → moto OK |
| V12 | Resilience | moto restart | 6 queues back ≤ 600 s, redrive intact, smoke green |
| V13 | CARM | ARNs + e2e message + default-cred probe | `111…`/`222…`; consumed; `NonExistentQueue` |
| V14 | Retain | Queue annotations | prod `retain`, others `delete` |
| V15 | Contract | dry-run invalid instance | rejected |
| V16 | Rebuild | teardown → setup → bootstrap | all Synced/Healthy, smoke green, time recorded |
| V17 | Regression | Phase 1–2 checks (tokens, PSS, PDB, digests, gate, smoke) | unchanged |

---

## 10. Risk Register & Rollback

| Risk | Likelihood | Impact | Mitigation / Rollback |
|---|:-:|:-:|---|
| Tokens expire before 0.1 | Low | High (Argo CD loses spokes) | Deadline in the header; early authorization requested |
| `--port-delete` (experimental) leaves the LB without a mapping | Med | Med | Add the new mapping before deleting the old; `--port-add` to restore; kubeconfig backup |
| Losing access after `admin.enabled=false` | Low | High | Disable only after `platform-admin` is proven; `kubectl` access to `argocd-cm` remains the break-glass |
| Adoption churn (B.2) restarts controllers or deletes CRDs | Med | High | `preserveResourcesOnDeletion: true`, ServerSideApply, nonprod first, Helm secrets removed only after Synced |
| Impersonation breaks a project's syncs (C.2) | Med | High | All projects get `destinationServiceAccounts` before the flag; rollback script; nonprod first |
| kro aggregation misses a kind → instances degrade | Med | Med | RBAC ships with the blueprint; nonprod first; revert = `rbac.mode: unrestricted` |
| CARM migration loses messages / orphans queues | High (by design) | Low (lab) | Canary first; drain prod; documented orphan clean-up |
| moto restart hypothesis fails | Med | Low | D.2b snapshot/restore fallback |
| B.7 rebuild fails mid-way | Med | Med | Owner-approved window; Git is the source of truth; prior phases' runbooks |

---

## 11. Effort Estimate

| Track | Effort |
|---|---|
| 0 | S (≈ 1 h, mostly owner UI actions) |
| A | M (≈ ½–1 day) |
| B | L (≈ 1–2 days incl. adoption + rebuild) |
| C | M–L (≈ 1 day; C.2 is the riskiest) |
| D | L (≈ 1–2 days incl. app release + migration) |
