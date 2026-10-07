# Learner On-Ramp Plan (2026-10-07)

> **Status: Approved (v1.0, owner, 2026-10-07).** Phase 1 (Track C) authorized; implementer Claude, validator a different party. **Owner decisions (2026-10-07): O-1…O-6 as recommended**: Lab 0 as `tenant-a-user`, its required tour Git-free (optional Git step at the end); Lab 1 kro-only with moto + ACK as the `--with-moto` stretch; pilot = the owner plus one or two people new to the lab (agents do not count); `make test-lab1` local only; order C → A → B → D. Phase 1 (Track C) accepted in [validation-01](2026-10-07-learner-on-ramp-plan-validation-01.md). Author: Claude (Opus 5.5).

| | |
|---|---|
| **Why** | [Validation-03](2026-10-06-lab-learning-remediation-plan-validation-03.md) re-scored the learning assessment at **8.0 / 10** and named what blocks a higher score: (1) the only way in is a **full three-cluster rebuild**; (2) kro composition is explained but never **written** by the learner (assessment concept 6); (3) `make test-docs` covers **selected** examples only; (4) **learner outcomes are not measured**. [Implemented-04](2026-10-06-lab-learning-remediation-plan-implemented-04.md) closed the remaining R-5 item (Drill 1) |
| **Goal** | A motivated learner can start on the **already-running** lab, understand the platform's core loop in about an hour without rebuilding or breaking anything, then write a small blueprint safely, with every step proven by tests and by real learners |
| **Baseline** | `gitops-control-plane` `5e3bdec`; 42 Applications `Synced/Healthy`; Bats 28/28; `make test-docs` green |

---

## 1. Facts this plan relies on (verified 2026-10-07)

| Fact | Evidence | Consequence |
|---|---|---|
| kro on the spokes runs with **aggregated RBAC**: it may only create the kinds the platform's ClusterRoles list (`kro-queue-backed-service`, `kro-team-eks-cluster`, `kro:controller:static`) | `kubectl get clusterrole kro:controller` on `spoke-nonprod` | A learner's own blueprint on the shared spokes would need a platform RBAC change and would add a cluster-scoped CRD to shared clusters, the risk behind Phase 3 incident D-14. **Blueprint authoring goes in a disposable sandbox cluster** (Track B) |
| A hand-scaled kro child is reverted in **~1 s** (`orders-dev-worker` scaled to 3 → back to 1); the Application briefly shows `Progressing`, then `Healthy` | live test 07:35 UTC | A safe, fast "watch a controller repair state" station for the first lab |
| Deleting a kro child (`configmap/orders-dev-config`) → recreated in ~1 s, Argo CD stays `Synced/Healthy`; deleting a cloud queue → ACK recreates it at its next resync (≤ 300 s) and Argo CD stays green | concepts page §2, student guide §4.6 | The tour can contrast *watch* (seconds) with *resync* (minutes) without disruption |
| A least-privilege learner identity exists: Keycloak `tenant-a-user` (group `lab-tenant-a`): sees project `tenant-workloads`, reads apps and logs, may sync only `orders-dev`/`orders-test`; password in `~/.config/gitops-lab/keycloak-tenant-a-user.password` | `argocd-rbac-cm` policy | The tour can teach tenancy by doing it as a tenant |
| The P0 spike already proved a reproducible single-cluster k3d + kro + moto sandbox (`docs/roadmaps/tenant-iac-p0-spike/spike.sh`, up in ~50 s) | tenant-IaC implemented-01 / validated-01 | Track B reuses that pattern instead of inventing one |

## 2. Guardrails
| ID | Rule |
|---|---|
| **G-1** | **Nothing in Lab 0 rebuilds, restarts or leaves residue.** Every action is read-only or self-reverting (kro or ACK repairs it) and has a written "how it goes back" line. Disruptive drills (Drill 1, a rebuild) stay in the student guide, after Lab 0 |
| **G-2** | **No learner object on the shared clusters is cluster-scoped.** Blueprints (RGDs, CRDs, ClusterRoles) are written only in the sandbox |
| **G-3** | **Every copyable block is tested** (guardrail P-0 of the 2026-10-06 plan): it is either executed by `make test-docs`, or explicitly marked as not testable, with the reason |
| **G-4** | **Expected observations are measured, not guessed**, and dated |
| **G-5** | **Outcomes are measured with real learners** before anyone claims a score above 8.0 |

## 3. Track A: Lab 0, "Tour the running lab" (about 60 min, no rebuild)
New document `docs/lab-0-guided-tour.md`, linked first from the README ("Start here") and from the student guide. Each station has: a **question**, *predict*, exact commands, the **measured** observation, *explain* (folded), and "how it goes back".

| Station | Learner does | Concept | Reverts by |
|---|---|---|---|
| 0. Before you start | `make test` (all `ok`), log in to Argo CD as **`tenant-a-user`** | prerequisites; a healthy baseline | — |
| 1. What can a tenant see? | Argo CD UI and CLI as `tenant-a-user`: own project only; `can-i sync orders-dev` yes, `orders-prod` no | multi-tenancy, AppProjects, RBAC | read-only |
| 2. From Git to Application | open `tenants/tenant-a/apps/orders-dev.yaml` and the ApplicationSet; read the Application's two revisions (chart `1.0.0` + values commit) | ApplicationSet generators, two-source render | read-only |
| 3. From Application to objects | `kubectl get queuebackedservice`, its children by label, their `ownerReferences`, the two `Queue` objects and their account | kro composition, ownership | read-only |
| 4. From objects to the cloud | `aws_as 111111111111` → the queues; plain `mock-key` → nothing (default account) | CARM, account isolation | read-only |
| 5. Watch, fast | scale `orders-dev-worker` to 3 → kro restores 1 in ~1 s; delete `configmap/orders-dev-config` → back in ~1 s; Argo CD stays green | watch-driven reconciliation, who owns what | kro |
| 6. Resync, slow | Drill 4 (delete `orders-dev-dlq` in moto) → ACK recreates it ≤ 300 s; Argo CD never notices | resync vs watch; cloud drift is invisible to GitOps | ACK |
| 7. Read the status right | `argocd app get orders-dev --output tree` vs `kubectl get application -o yaml` | `Synced` vs `Healthy`; where health lives | read-only |
| 8. Check yourself | 4 short questions from the concepts page, with folded answers; "next: the student guide (rebuild, Drill 1) and Lab 1" | retention | — |

**Acceptance (Track A):** each station is run on the live lab by the implementer and by the validator; measured observations are recorded with time; all copyable blocks of stations 1–7 run in `make test-docs` (stations 5–6 in a `--live-mutating` mode that waits for the repair, G-3); the lab is identical before and after (Applications, queues per account, VPCs, Bats 28/28).

## 4. Track B: Lab 1, "Write a blueprint" (about 60 min, sandbox cluster)
* **`make sandbox-up` / `sandbox-down`** (`scripts/learning-sandbox.sh`): one k3d cluster `learn-sandbox`, **kro 0.9.4 with the lab's own values** (`rbac.mode: aggregation`, the same as the spokes), no Argo CD. Optional `--with-moto` adds moto + ACK SQS for a stretch step (O-3). Separate ports, name and network from the lab; `down` removes everything.
* **Exercise** `docs/lab-1-write-a-blueprint.md`, in steps, each with predict/observe/explain:
  1. Write an RGD `WebGreeting` (schema: `name`, `message`, `replicas`, `expose`) that creates a ConfigMap and a Deployment; apply an instance. **Observe it fail**: kro may not create Deployments here until you grant it (aggregated ClusterRole). Write that ClusterRole (the platform's real least-privilege pattern, `blueprints/kro-rbac-*.yaml`).
  2. Pass the ConfigMap's name into the Deployment (CEL reference) → see kro order creation by dependency.
  3. Add a `Service` with `includeWhen: ${schema.spec.expose}` (the same mechanism as the platform's conditional PDB).
  4. Add `readyWhen` and a `status` field from a child (`availableReplicas`) → `Ready` follows the pods.
  5. **Break it on purpose:** (a) reference a field that does not exist → see `GraphResolved=False` and the message; (b) add a constraint to an existing schema field → see kro refuse the "breaking change" (incident D-14) → learn why the platform validates with a ValidatingAdmissionPolicy instead.
  6. Stretch (`--with-moto`): add an ACK `Queue` child and read its `queueURL` into the ConfigMap.
* **Reference solution** under `docs/lab-1-solution/` plus `make test-lab1` (creates the sandbox, applies the solution, asserts `Ready`, the conditional Service, the D-14 refusal, then tears down). Local only: CI has no k3d (O-5).

**Acceptance (Track B):** `make test-lab1` passes from a clean machine state twice in a row; every expected failure message in the exercise is copied from a real run; `sandbox-down` leaves no container, network or kube context behind; the shared lab is untouched (G-2).

## 5. Track C: `make test-docs` coverage (G-3)
* **Inventory** every fenced `bash` block in the learner path (README, Lab 0, Lab 1, student guide, developer tutorial, concepts page, tenant-IaC runbook, Argo CD CLI runbook): **36 blocks today** (README 6, student guide 14, developer tutorial 7, tenant-IaC runbook 6, Argo CD CLI runbook 3; counted 2026-10-07), plus those Lab 0 and Lab 1 add.
* **Mark each block** with an HTML comment just above it: `<!-- doc-test: run -->` (read-only, executed), `<!-- doc-test: mutating -->` (self-reverting, executed in `make test-docs MODE=live-mutating`, which waits for the repair), `<!-- doc-test: skip reason="…" -->` (disruptive, interactive SSO, needs a fresh rebuild).
* **Runner:** `tests/test_doc_examples.sh` extracts marked blocks by marker instead of by heading, runs them in a clean `env -i` shell, and prints coverage: *run / mutating / skipped with reason / unmarked*. **Unmarked blocks fail the check**, so new examples cannot slip in untested.
* **Acceptance (Track C):** 0 unmarked blocks; every `skip` has a reason; coverage report in the implementation report; negative test (an unmarked block and a deliberately broken `run` block both fail).

## 6. Track D: measure learning outcomes (G-5)
* **Pilot protocol** `docs/learning/pilot-protocol.md`: 2–3 learners (O-4), each does Lab 0 then Lab 1 alone; times per station; where they got stuck (a friction log template); the 8 self-check questions answered before opening the hints; a 5-question post-survey.
* **Success thresholds (proposed):** Lab 0 finished in ≤ 75 min without help; Lab 1 in ≤ 90 min with ≤ 1 hint; ≥ 6/8 self-check answers correct; every friction item either fixed or answered in the docs.
* **Output:** `docs/learning/pilot-results-YYYY-MM-DD.md` (anonymous), then an **independent re-score** of the assessment (not by the implementer).

## 7. Owner decisions
| ID | Question | Recommendation |
|---|---|---|
| **O-1** | Lab 0 identity: `tenant-a-user` (least privilege) or `platform-user` (admin)? | `tenant-a-user`; stations that need cluster-wide reads use `kubectl` (read-only commands) |
| **O-2** | Should Lab 0 include a real Git change (push `replicas: 2` to `orders-processor` `values-dev.yaml`)? It changes a shared repository | No: keep Lab 0 Git-free (station 5 shows reconciliation without Git). Offer the Git change as an optional step at the end, with its revert commit |
| **O-3** | Lab 1 sandbox: kro only, or also moto + ACK SQS? | kro only by default; moto + ACK as the `--with-moto` stretch |
| **O-4** | Who are the pilot learners? | You plus one or two people new to the lab; the agents (Claude, Codex, Antigravity) do **not** count as learners |
| **O-5** | CI for Lab 1 | Local `make test-lab1` only for now (GitHub runners would need k3d; possible later) |
| **O-6** | Order and executors | Track C first (it protects A and B), then A, then B, then D. Executor and validator alternate per track |

## 8. Phases and effort
| Phase | Content | Exit gate | Effort |
|---|---|---|---|
| 1 | Track C (markers, runner, coverage) | 0 unmarked blocks; negative tests fail | S–M |
| 2 | Track A (Lab 0) | live run by implementer and validator; lab unchanged; blocks covered | M |
| 3 | Track B (sandbox + Lab 1 + `make test-lab1`) | two clean passes; shared lab untouched | M |
| 4 | Track D (pilot) | results recorded; independent re-score | depends on learners |

## 9. Risks
| Risk | Mitigation |
|---|---|
| Lab 0 station 6 (Drill 4) runs while another drill or a moto restart is in progress | Station 0 requires `make test` all `ok` first; the station checks the queue exists before deleting it |
| Learners scale or delete the wrong object | Exact commands with names; a "how it goes back" line; mutating stations only touch `orders-dev` and kro/ACK-owned objects |
| The sandbox clashes with the lab (ports, contexts, Docker network) | Distinct cluster name, API port and network; `sandbox-down` removes its kube context; checked in Track B acceptance |
| kro version drift between the sandbox and the spokes | The sandbox takes the chart version from `applicationsets/addons-spoke.yaml` and the values from `platform-catalog/controllers/kro/values-kro.yaml` |
| Doc markers become noise | One short comment per block; the runner reports coverage so the value is visible |
