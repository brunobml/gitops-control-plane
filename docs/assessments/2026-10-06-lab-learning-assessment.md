# Lab Learning Assessment — 2026-10-06

> **Perspective:** Senior Trainer & Technical Enablement Specialist (Platform Engineering, SRE, and GitOps).
> **Evaluation Focus:** Whether a motivated learner can extract, internalize, and transfer the underlying *concepts* and *mental models* of the platform (Argo CD, KRO, AWS ACK, multi-cluster GitOps, admission control, and observability) rather than merely executing a procedural checklist of commands.

| | |
|---|---|
| **Document version** | **3.0: evidence re-check and update** (supersedes 2.0) |
| **Status** | Current |
| **Assessment Date** | 2026-10-06 |
| **Authors & Reviewers** | Codex (v1.0 draft), Agy (v2.0 review and enablement synthesis), **Claude (Opus 5.5) (v3.0: every v2.0 claim re-verified on the repository and the live lab; corrections, new gaps, answer guidance)** |
| **Assessment Standard** | [`docs/ai-prompts/ai-agent-lab-expert-trainer-assessment-prompt.md`](../ai-prompts/ai-agent-lab-expert-trainer-assessment-prompt.md) |
| **Repository Baseline** | `gitops-control-plane` `ce13239`. No learner-facing document changed since v2.0's baseline `595b249`, so v3.0 changes the assessment, not the lab. Live lab: 42 Applications Synced/Healthy |
| **Target Documentation** | Root [`README.md`](../../README.md), [`devops-student-rebuild-guide.md`](../runbooks/devops-student-rebuild-guide.md), [`developer-tutorial.md`](../developer-tutorial.md), [`operational-drills-and-failure-injection.md`](../runbooks/operational-drills-and-failure-injection.md), [`tenant-iac-operations.md`](../runbooks/tenant-iac-operations.md), [`production-promotion-guardrails.md`](../production-promotion-guardrails.md), [`lab-progression-and-next-steps.md`](../lab-progression-and-next-steps.md) *(added in v3.0)*, [`argocd-cli.md`](../runbooks/argocd-cli.md) *(added in v3.0)*, [`host-reboot-and-cluster-lifecycle.md`](../runbooks/host-reboot-and-cluster-lifecycle.md) |
| **Methodology** | The 5 enablement dimensions of the standard. **Every copyable example cited as evidence was executed** (schema validation, AWS CLI against moto, server-side dry-run admission tests, Argo CD resource tree). The commands and results are in §9 |

### What changed in v3.0
| | Change |
|---|---|
| ✅ Confirmed | L-1 (Kro credited with creating SQS queues), L-2 (tenant-iac example fails the schema; tutorial uses the wrong AWS account; "32 Applications" baseline), L-3 (no objectives, predictions or definitions), L-4 (lifecycle semantics scattered), the 27 Bats smoke tests, Drill 4's behaviour, the two-tier acceptance note |
| ✏️ Corrected | **v2.0's SQS fix does not work**: `--queue-owner-aws-account-id 111111111111` with default credentials also returns `NonExistentQueue`, because moto resolves queues in the *caller's* account. The working fix uses account-111 credentials (§6, P0-2). **L-5 evidence was misplaced**: canary/Argo Rollouts appear in `lab-progression-and-next-steps.md` (Track 2), not in the promotion guide. The promotion guide's real problem is that it calls a *manual prod sync gate* "Current Setup", while the live `orders-prod` syncs automatically. **"Reset in under 7 minutes"**: the measured clean rebuild is 484 s (about 8 min, `full-rebuild-and-acceptance.md`). **"32 Applications" appears 5 times**, not 2 |
| ➕ Added | L-6 (tutorial "values file" is a stale rendered CR, with an image admission now rejects), L-7 (where Argo CD health lives: a trap that misled a validator in this project), L-8 (stale learner architecture views: no tier-1 network, EC2/IAM/EKS controllers or tenant IaC path), two checklist concepts, answer guidance for every trainer question, verification log |
| 🔢 Score | **6.0 / 10, unchanged**: the documents did not change; the corrections cancel out (v2.0 slightly overstated some evidence, and missed some real gaps) |

---

## 1. Executive Summary & Overall Educational Score

### Overall Educational Effectiveness Score: **6.0 / 10**

### Score Justification
The platform is operationally excellent and realistic: a hub and two spokes, central AWS emulation with per-environment accounts, multi-tenant GitOps, kro composition, ACK controllers, layered admission control, SSO and full observability. Its failure drills are the best teaching material in the repository.

As **teaching material**, it still has a procedural bias, and in places it **teaches the wrong model**:
1. **The controller chain is blurred.** The developer tutorial credits Kro with creating the SQS queue. The Helm render step and the ACK controller, the component that actually talks to the cloud, are invisible in the prose.
2. **Copyable examples fail.** A learner who follows the tenant-IaC runbook, the developer tutorial or the tutorial's cheat sheet gets schema errors, `NonExistentQueue` or an empty queue list, and cannot tell their own mistakes from documentation bugs. v2.0's own fix for the SQS example also fails.
3. **Status vocabulary is never defined.** No document explains `Synced` vs `Healthy`, or where Argo CD evaluates health for custom resources. That gap misled even an expert validator during the tenant-IaC work (L-7).
4. **The learner's map is out of date.** The student guide's architecture shows only ACK SQS, and the "current baseline" diagram in the progression guide predates SSO, Kyverno, the platform network and tenant IaC.
5. **The drills are excellent but sit outside the learning path**, with no predict-observe-explain structure.

---

## 2. Evaluation Across Assessment Dimensions

| Dimension | Rating | Trainer Findings Summary |
|---|---|---|
| **1. Concept Coverage & Explicitness** | **Partial (5.5/10)** | Tools are named, but the boundaries between reconcilers (ApplicationSet → Application → Helm render → kro RGD → ACK CR → AWS API) are implicit or wrong. `Synced`/`Healthy`, health customizations, finalizers vs ownerReferences vs deletion policies are never defined in one place |
| **2. Learning Flow & Scaffolding** | **Weak (4.5/10)** | Starts with a 3-cluster, 42-Application build. No learning objectives, no prerequisite self-check, no predict/observe points. The "Lessons learned" section teaches shell and k3d pitfalls, not GitOps concepts |
| **3. Hands-on Design Quality** | **Strong (8/10)** | Drills cover cloud state loss, token expiry, admission outage, out-of-band drift, tenant deregistration and a Loki post-mortem, with real timings and correct account handling (`moto111`). Missing: prediction prompts before each drill |
| **4. Documentation Effectiveness** | **Uneven (5/10)** | Good diagrams and runbooks, but 5 stale "32 Applications" baselines, a wrong account in the tutorial and its cheat sheet, a stale tutorial manifest, a promotion guide that contradicts the live lab, and stale architecture views. No glossary, no key takeaways |
| **5. Transfer of Learning** | **Moderate (6.5/10)** | Strong on repository separation of duties, per-environment accounts (CARM), least-privilege impersonation, the moto-vs-EKS gap (tenant IaC two-tier note) and admission layering. Weak on promotion vs progressive delivery, and on which lab shortcuts must not reach production |

---

## 3. Educational Strengths

1. **Traceability from Git to workload.** The six-repository split (`gitops-control-plane`, `platform-catalog`, `platform-charts`, `tenant-workloads`, `tenant-iac`, `orders-processor`) mirrors real separation of duties. One commit in `tenant-workloads` can be followed through the ApplicationSet, onto a spoke, into kro and ACK, and out to moto.
2. **Drift and healing you can watch.** Drill 4 ([operational-drills](../runbooks/operational-drills-and-failure-injection.md#6-drill-4-out-of-band-cloud-drift-on-sqs-resources)) deletes a DLQ directly in moto, as account 111, and shows ACK recreating it on its resync cycle ("observed 150 s … at most about 300 s"). That dispels the idea that controllers react instantly to everything, and teaches that Argo CD does not see cloud-side drift at all.
3. **Honest simulation boundaries.** The two-tier acceptance note in [`tenant-iac-operations.md`](../runbooks/tenant-iac-operations.md) (line 84) states that a moto EKS `ACTIVE` record proves the declarative chain and account isolation, not a reachable Kubernetes API, nodes, CNI or workloads.
4. **Layered admission control that can be demonstrated.** The lab really has three independent admission layers on tenant namespaces, and they fire in a teachable order (verified in §9: Pod Security → ValidatingAdmissionPolicy → Kyverno).
5. **Repeatable baseline.** `make teardown && make setup && make bootstrap && make post-bootstrap` rebuilds everything from Git without manual steps (484 s measured), and 27 Bats smoke tests confirm the result. Learners can experiment without fear.

---

## 4. Key Gaps & Learning Risks

### ⚠️ Gap L-1: The reconciler chain is conflated (**Severity: High**) — *confirmed*
* **Evidence:** [`developer-tutorial.md`](../developer-tutorial.md) lines 122–126: *"Under the hood, **Kro** automatically generates: 1. A Kubernetes `Deployment` … 2. An AWS SQS Queue in Central Moto Cloud …"*. The tutorial's diagram draws `KroNP -->|ACK SQS Controller| DevQueue`, so the ACK controller is a label on an arrow, not a component.
* **What actually happens:**
```
[ Git: tenant-workloads registration + orders-processor/deploy/values-dev.yaml ]
      │  Reconciler 1: Argo CD ApplicationSet controller (generates the Application)
      ▼  Reconciler 2: Argo CD application controller (renders the Helm chart, applies to the spoke)
[ QueueBackedService CR on spoke-nonprod ]
      │  Reconciler 3: kro (expands the RGD: Deployment, Service, Ingress, NetworkPolicies, ACK Queue CRs)
      ▼
[ ACK Queue CRs (sqs.services.k8s.aws) ]
      │  Reconciler 4: ACK SQS controller (assumes the account role via CARM, calls the SQS API)
      ▼
[ SQS queue + DLQ in moto, account 111111111111 ]
```
* **Learning risk:** the learner cannot isolate a failure. "My queue is missing" has four different owners, each with its own status field and log.

### ⚠️ Gap L-2: Copyable examples fail or use the wrong account (**Severity: High**) — *confirmed, extended, fix corrected*
1. **Tenant IaC example fails the schema.** [`tenant-iac-operations.md`](../runbooks/tenant-iac-operations.md) lines 56–66: `env: dev` with `maxSize: 4`. The runbook's own validation command (line 71) fails: `jsonschema.exceptions.ValidationError: 4 is greater than the maximum of 3` (executed, §9).
2. **The developer tutorial uses moto's default account.** Lines 152 (sample log) and 196 (`send-message` URL) use `…/123456789012/orders-dev-queue`. The live worker logs `…/111111111111/orders-dev-queue`, and the documented URL returns `NonExistentQueue`. The **cheat sheet** (line 233) lists queues with plain mock credentials, which also queries the default account and finds nothing.
   *v2.0's proposed fix (`get-queue-url --queue-owner-aws-account-id 111111111111` with default credentials) also returns `NonExistentQueue`:* moto resolves the queue in the caller's account. What works is credentials *for* account 111, which is exactly what Drill 4's `moto111` helper does.
3. **"32 Applications" is stale in five places:** `devops-student-rebuild-guide.md` lines 226 and 307, `operational-drills-and-failure-injection.md` lines 7 and 71, `argocd-cli.md` line 134. The live count is 42.
* **Learning risk:** when advertised commands fail, learners lose trust and start guessing. Worse, the account example teaches a wrong mental model of CARM: "the queue is in the default account".

### ⚠️ Gap L-3: Procedure dominates conceptual scaffolding (**Severity: Medium**) — *confirmed*
* **Evidence:** a search of the README, `docs/` and the runbooks for "learning objective", "you will learn", "predict", "reflect", "takeaway", "glossary" or "self-check" finds nothing. No document defines `Synced` vs `Healthy`. The student guide's §7 "Common Pitfalls & DevOps Lessons Learned" covers `set -euo pipefail`, k3d port edits and headless scheduling: useful operator trivia, but none of it is about reconciliation, desired state or controllers.
* **Learning risk:** a learner completes the rebuild, sees 42 green Applications and 27 passing tests, and still cannot explain what `Synced` guarantees.

### ⚠️ Gap L-4: Lifecycle semantics are scattered (**Severity: Medium**) — *confirmed*
* **Evidence:** finalizers and kro's reverse-order deletion (tenant-iac runbook), `prune` settings (ApplicationSets), `deletion-policy: retain|delete` (both RGDs), `adopt-or-create` for prod team clusters (TeamEKSCluster RGD), and Argo CD's `preserveResourcesOnDeletion` all exist, but no document compares them.
* **Learning risk:** learners conflate "delete the Git file", "delete the Kubernetes object" and "delete the cloud resource". These are three different events with three different owners.

### ⚠️ Gap L-5: Promotion model vs progressive delivery, and a guide that contradicts the lab (**Severity: Medium**) — *re-evidenced*
* **Evidence (corrected):**
  - [`production-promotion-guardrails.md`](../production-promotion-guardrails.md) is a design reference with five patterns. Its banner correctly says that the lab promotes prod through a PR that pins `valuesRevision` to a 40-character SHA. But its closing "Summary Recommendation … **Short Term (Current Setup)**: Disable `automated` sync for prod" contradicts the live lab: `orders-prod` has `automated: {prune: true, selfHeal: true}`.
  - Canary and Argo Rollouts appear only as **future Track 2** in [`lab-progression-and-next-steps.md`](../lab-progression-and-next-steps.md).
* **Learning risk:** the learner cannot say which promotion pattern the lab implements, and may believe they practised progressive delivery when they practised **immutable configuration promotion with rolling updates**.

### ➕ Gap L-6: The tutorial's "values file" is a stale rendered CR (**Severity: Medium**) — *new*
* **Evidence:** [`developer-tutorial.md`](../developer-tutorial.md) Step 2 says *"Look at `deploy/values-dev.yaml` … (or the rendered `QueueBackedService` CR)"*, then shows a **CR**: `apiVersion: kro.run/v1alpha1`, `messageRetentionPeriod`, `image: …:v1.2.0`. The real `values-dev.yaml` is five Helm values (`name`, `environment`, `replicas`, `retentionPeriod`, `image: …:v1.5.0@sha256:…`). `v1.2.0` is **refused by admission** today (Kyverno `tenant-images-signed`, §9).
* **Learning risk:** this hides the Helm render layer (L-1), teaches field names that do not exist in the values file, and a learner who copies the image gets an admission denial without knowing why.

### ➕ Gap L-7: Where Argo CD health lives is never explained (**Severity: Medium**) — *new*
* **Evidence:** the lab ships custom health checks (`resource.customizations.health.kro.run_QueueBackedService`, `…_TeamEKSCluster`, `…_ResourceGraphDefinition`, `…eks.services.k8s.aws_Cluster`). The resource tree shows them working (`QueueBackedService/orders … Healthy`, `TeamEKSCluster/analytics-dev … Healthy`, `VPC/platform-vpc … Healthy`). But Argo CD 3.x **does not copy per-resource health into the Application's `status.resources`**: `kubectl get application -o yaml` shows no health for those kinds. No document says this, or that kro and ACK objects only get a health status because the lab defines one.
* **Real consequence in this project:** during the tenant-IaC P1 validation, the validator concluded from `status.resources` that "Argo CD applies none of the custom health checks" (validated-02 V-4). That was a false positive, corrected on 2026-10-06. If an expert falls into it, a learner will.
* **Learning risk:** wrong conclusions about health, and no understanding that health for CRDs is something the platform defines, not something Kubernetes provides.

### ➕ Gap L-8: The learner's architecture views are stale and omit tenant IaC (**Severity: Medium**) — *new*
* **Evidence:**
  - The student guide's architecture (§1) shows moto as "AWS SQS" with only the ACK SQS controller: no EC2/IAM/EKS controllers, no tier-1 `platform-network`, no tenant-IaC flow, although its tenets list `tenant-iac` as one of the six repositories.
  - [`lab-progression-and-next-steps.md`](../lab-progression-and-next-steps.md) asks the learner to *"ensure you understand what is currently deployed"* and then shows a pre-SSO, pre-Kyverno, SQS-only baseline. Its "Track 3: Kyverno" is presented as future work, although Kyverno is live.
  - The only tenant-IaC learning material is an **operations** runbook.
* **Learning risk:** the learner's mental model of the system is incomplete. The richest composition example in the lab (claim → ApplicationSet → chart → kro → ACK IAM/EKS, reading a platform-owned network through `externalRef`) is not taught at all.

---

## 5. Must-Understand Concept Checklist

| Must-Understand Concept | Verdict | Detailed Assessment / Gap |
|---|:---:|---|
| **1. Declarative desired state vs observed status** | **Partially Covered** | Practised through Git sync. Never explained that `status` belongs to controllers, not Git |
| **2. Controller pattern & reconciliation loops (watch vs periodic resync)** | **Partially Covered** | Drill 4 shows resync (≤ 300 s) concretely. No explanation of watch events vs resync, or why Argo CD cannot see cloud drift |
| **3. The reconciler chain (ApplicationSet → Application/Helm → kro → ACK → cloud)** | **Missing / Conflated** | L-1, L-6: Kro credited with SQS; Helm render hidden |
| **4. `Synced` vs `Healthy`; where health is evaluated; custom health for CRDs** | **Missing** | L-3, L-7: never defined; health location undocumented |
| **5. ApplicationSet generators & multi-cluster routing** | **Fully Covered** | Git-files and cluster generators routing to `spoke-nonprod`/`spoke-prod`; per-tenant and per-team ApplicationSets |
| **6. CRDs & composition (kro RGD: schema, CEL, dependency graph, `readyWhen`, `externalRef`)** | **Partially Covered** | RGDs and claims shown. CEL expressions, dependency ordering, `readyWhen` and cross-namespace `externalRef` are not taught |
| **7. Multi-account isolation (CARM, STS role assumption)** | **Partially Covered** *(v2.0: Fully)* | Well modelled in the platform and in the drills (`moto111`), but the developer tutorial contradicts it (L-2.2) |
| **8. Deletion lifecycles: prune, finalizers, ownerReferences, retain/adopt** | **Partially Covered** | L-4: present, never compared |
| **9. Admission layering (Pod Security, VAP, Kyverno webhook)** | **Fully Covered** | Clear split of responsibilities; the order is demonstrable (§9) |
| **10. Configuration promotion vs progressive delivery** | **Partially Covered** | L-5: the guide contradicts the live promotion model |
| **11. Simulation fidelity: moto vs real AWS/EKS** | **Partially Covered** | Explicit for tenant IaC only; absent from the student guide and tutorial |
| **12. Cloud-state loss and recovery (in-memory moto, credential caching, re-adoption)** *(new)* | **Partially Covered** | Drill 1 and `make moto-restart` cover it, and `tenant-iac-operations.md` Runbook 5 gives a one-line reason per step. The mechanisms behind them (ACK's cached STS credentials, IGW/SG not recreated, IDs that change) are explained only in the roadmap reports |
| **13. Platform-owned vs team-owned infrastructure (two tiers)** *(new)* | **Missing** (learner docs) | L-8: taught only in the tenant-IaC plan and operations runbook |

---

## 6. Prioritized Enablement Recommendations

### Priority P0: Make every copyable example true (small, immediate)
1. **Tenant IaC example:** `maxSize: 3` for `env: dev` in `tenant-iac-operations.md`, so the runbook's validation command passes.
2. **SQS account (corrected fix):** in `developer-tutorial.md` (Step 3 sample log, Step 4, cheat sheet), use account-111 credentials, as Drill 4 does:
   ```bash
   moto111() {   # credentials for moto account 111111111111 (nonprod), see operational-drills §2
     local c; c=$(AWS_ACCESS_KEY_ID=x AWS_SECRET_ACCESS_KEY=x aws --endpoint-url=http://localhost:5000 --region us-east-1 \
       sts assume-role --role-arn arn:aws:iam::111111111111:role/learner --role-session-name learner --query Credentials --output json)
     export AWS_ACCESS_KEY_ID=$(jq -r .AccessKeyId <<<"$c") AWS_SECRET_ACCESS_KEY=$(jq -r .SecretAccessKey <<<"$c") AWS_SESSION_TOKEN=$(jq -r .SessionToken <<<"$c")
   }
   moto111
   QUEUE_URL=$(aws --endpoint-url=http://localhost:5000 --region us-east-1 sqs get-queue-url --queue-name orders-dev-queue --output text)
   aws --endpoint-url=http://localhost:5000 --region us-east-1 sqs send-message --queue-url "$QUEUE_URL" --message-body '{"orderId":"ORD-1234"}'
   ```
   (Verified: `get-queue-url` → `http://localhost:5000/111111111111/orders-dev-queue`.) Better still, document the existing `make moto-resources` helper for listing.
3. **Baselines:** 32 → 42 in all five places, or better, *"all Applications (`argocd app list`)"* so the number cannot drift again.
4. **Tutorial Step 2:** show the real `deploy/values-dev.yaml`, and then, separately and labelled, the rendered `QueueBackedService` (`kubectl get queuebackedservice orders -o yaml`). This turns L-6 into a lesson about the Helm layer.

### Priority P1: Teach the model, not just the procedure
1. **"One change, four reconcilers" section** (tutorial and student guide), using the chain in L-1. For each reconciler: what it watches, what it writes, where its status is, and what you see when it is down.
2. **Status & health primer:** `Synced` (live = rendered Git) vs `Healthy` (runtime readiness as judged by health checks); built-in vs custom health (`resource.customizations.health.*` in `clusters/values-argocd-hub.yaml`); **where to read health in Argo CD 3.x** (UI, `argocd app get --output tree`, not `status.resources`).
3. **Predict–Observe–Explain checkpoints** in the student guide (before `make bootstrap`: "what will one root Application create?"; after: "why 42?"; before Drill 4: "will Argo CD notice?").
4. **Promote Drill 4 (and Drill 1) into the learning path**, each with a prediction prompt and an "explain what you saw" prompt.
5. **Refresh the learner architecture** (student guide §1, progression baseline): ACK EC2/IAM/EKS, `platform-network`, tenant IaC, Keycloak, Kyverno; mark progression tracks already implemented.

### Priority P2: Make concepts transferable
1. **Glossary / concept sheet:** `Synced`/`Healthy`/`Ready`; `ApplicationSet`/`Application`/`AppProject`; `ownerReferences` vs finalizers vs `deletion-policy: retain` vs `adopt-or-create`; CARM; RGD/`readyWhen`/`externalRef`.
2. **Lifecycle comparison table:** "delete the Git file", "delete the K8s object", "delete the cloud resource", each with owner, trigger and the prod vs nonprod difference.
3. **Promotion guide:** replace "Short Term (Current Setup)" with what the lab actually does (SHA pin + PR + required check, automated sync), and add a callout: promotion ≠ progressive delivery (link Track 2).
4. **A learner path for tenant IaC** (concepts, not operations): two tiers, `externalRef`, why the EKS `Cluster` never reports `ResourceSynced` in moto, and what changes on real AWS.
5. **Rewrite "Lessons learned"** around concepts (drift, reconciliation timing, account isolation), keeping the shell/k3d items as an appendix.

---

## 7. Trainer Reflection & Validation Questions (with answer guidance)

| # | Question | A strong answer includes |
|---|---|---|
| 1 | **The reconciler trace.** You set `replicas: 3` in `deploy/values-dev.yaml` and push. Name every component that acts before the third pod runs, and one status field or log you would check for each | Argo CD application controller notices the new revision (the ApplicationSet is unchanged: the registration did not change), renders the chart, applies the `QueueBackedService` (Application `Synced`); kro updates the Deployment (instance `Ready`); the Deployment/ReplicaSet controllers create pods (`readyReplicas`). ACK is **not** involved: no queue field changed |
| 2 | **Synced but Degraded.** How can an Application be `Synced` and `Degraded`? | Sync = live objects match the rendered Git; health = runtime readiness judged by health checks (e.g. CrashLoopBackOff). For kro/ACK kinds, health exists only because the lab defines Lua health checks; in Argo CD 3.x you read it in the resource tree, not in `status.resources` |
| 3 | **Out-of-band cloud drift.** Someone deletes `orders-dev-dlq` directly in moto. Who notices, and when? | Argo CD does not (its desired state is the Kubernetes object, which is unchanged). The ACK SQS controller notices on its next resync (≤ 300 s; observed 11–150 s) and recreates it. A controller restart forces it immediately |
| 4 | **Composition vs cloud control.** If the ACK SQS controller is down, what happens to a new `QueueBackedService`? | kro evaluates dependencies in its RGD DAG: it creates the Deployment and the DLQ ACK `Queue` CR (no status dependencies), but waits for the DLQ's ARN before creating the main `Queue` CR and for both queue statuses before creating the ConfigMap. Since ACK is down, the DLQ is not reconciled, so the main Queue and ConfigMap are never created, pods cannot start, and the instance stays `IN_PROGRESS` (`Ready: False`). Argo CD shows the Application `Synced`; health is `Progressing` (the `QueueBackedService` Lua check only knows Ready → `Healthy`, otherwise `Progressing`). `SpokeControllerDown` fires after 5m (`for: 5m`) |
| 5 | **Deletion cascade.** You delete `tenants/tenant-a/apps/orders-dev.yaml`. What happens, layer by layer, and how would `retain` change it? | The ApplicationSet drops the Application; Argo CD deletes its resources (finalizer); kro deletes its children; ACK deletes the queues because of `deletion-policy: delete`. With `retain` (prod), the Kubernetes objects go but the cloud queues stay. Garbage collection via ownerReferences is not the same as cloud deletion |
| 6 | **GitOps exceptions.** Name state that is intentionally **not** in Git, and why | Passwords and tokens (`~/.config/gitops-lab`, mode 600), worker IAM keys (Secrets created by `post-bootstrap`), the TLS leaf key, moto's in-memory state. Secrets in Git leak; cloud state is observed, not declared |
| 7 | **Admission layering.** An `nginx:latest` pod is created in `orders-dev`. Which layer denies it first? | Verified on the lab: **Pod Security `restricted`** (in-tree, runs first) denies a pod without a compliant `securityContext`. With a compliant one, the **ValidatingAdmissionPolicy** registry allowlist denies it. An allowed-registry but unsigned image (`orders-processor:v1.2.0`) is denied by **Kyverno**'s validating webhook. Bonus: via a Deployment, the denial shows on the ReplicaSet's events, not on the `kubectl apply` |
| 8 | **The simulation gap.** A `TeamEKSCluster` shows `Ready` and `TeamClusterNotReady` is silent. Can a team run `kubectl` against it? | No. moto creates an `ACTIVE` API record with a fake endpoint; there is no control plane, node or CNI. `Ready` proves the declarative chain, the accounts and the guardrails. On real AWS, readiness would also require a reachable endpoint, nodes and access entries |

---

## 8. Final Trainer Verdict

The **platform** is mature, realistic and stable. The **enablement layer** is where the work is, and it is mostly small, concrete work:
1. **P0, about an hour:** make every copyable example true (the tenant-IaC claim, account-111 SQS commands, the 42-Application baseline, the real values file).
2. **P1:** teach the reconciler chain and the status vocabulary, including *where* health lives. This gap was strong enough to mislead an expert validator.
3. **P1/P2:** turn the drills into predict-observe-explain milestones, refresh the architecture views, and give tenant IaC a learner path.

Done well, these would raise the score to about 8/10 without changing a single platform component.

---

## 9. Verification Log (2026-10-06, live lab)

| Claim | Command (abridged) | Result |
|---|---|---|
| Tenant-IaC example fails | runbook lines 56–66 → `jsonschema.validate(…, tenant-iac/schema/cluster.schema.json)` | `ValidationError: 4 is greater than the maximum of 3` |
| Tutorial URL wrong | `aws sqs get-queue-attributes --queue-url …/123456789012/orders-dev-queue` (default creds) | `NonExistentQueue` |
| v2.0 fix wrong | `aws sqs get-queue-url --queue-name orders-dev-queue --queue-owner-aws-account-id 111111111111` (default creds) | `NonExistentQueue` |
| Working fix | STS assume-role into 111, then `get-queue-url` | `http://localhost:5000/111111111111/orders-dev-queue` |
| Live worker account | `kubectl -n orders-dev logs <worker>` | `listening on http://moto-cloud:5000/111111111111/orders-dev-queue` |
| "32" occurrences | `grep` in docs | student guide l.226, l.307; drills l.7, l.71; argocd-cli l.134. Live: 42 Applications |
| Real values file | `orders-processor/deploy/values-dev.yaml` | `retentionPeriod`, `image: …:v1.5.0@sha256:e95bb633…` |
| Prod sync policy | `kubectl get application orders-prod -o jsonpath='{.spec.syncPolicy.automated}'` | `{"prune":true,"selfHeal":true}` |
| Health customizations present | `argocd-cm` keys | `resource.customizations.health.{kro.run_QueueBackedService, kro.run_TeamEKSCluster, kro.run_ResourceGraphDefinition, eks.services.k8s.aws_Cluster}` |
| Health not in `status.resources` | `kubectl get application orders-dev -o json` | `QueueBackedService` health absent |
| Health evaluated | `argocd app get orders-dev --output tree` | `QueueBackedService/orders Synced Healthy`, `Queue/orders-dev-dlq Healthy`; `TeamEKSCluster/analytics-dev Healthy`; `VPC/platform-vpc Healthy` |
| Admission order | `kubectl apply --dry-run=server` in `orders-dev` | nginx, no securityContext → **PodSecurity restricted**; nginx, compliant → **VAP** `tenant-image-registry-allowlist`; `ghcr.io/brunobml/orders-processor:v1.2.0`, compliant → **Kyverno** `tenant-images-signed` |
| Smoke tests | `grep -c @test tests/smoke/*.bats` | 6+4+2+6+3+6 = **27** |
| Rebuild time | `full-rebuild-and-acceptance.md` l.56 | 484 s |
| Scaffolding absent | `grep -i` for objectives/predict/reflect/glossary/takeaway/self-check | no matches |
