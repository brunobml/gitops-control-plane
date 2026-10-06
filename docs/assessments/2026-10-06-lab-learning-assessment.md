# Lab Learning Assessment — 2026-10-06

> **Perspective:** Senior Trainer & Technical Enablement Specialist (Platform Engineering, SRE, and GitOps).  
> **Evaluation Focus:** Whether a motivated learner can extract, internalize, and transfer the underlying *concepts* and *mental models* of the platform (Argo CD, KRO, AWS ACK, multi-cluster GitOps, admission control, and observability) rather than merely executing a procedural checklist of commands.

| | |
|---|---|
| **Document version** | **2.0 — Final Enablement Assessment (Peer-Reviewed & Expanded by Agy)** |
| **Status** | Completed & Published |
| **Assessment Date** | 2026-10-06 |
| **Authors & Reviewers** | Codex (v1.0 draft) & Agy (v2.0 comprehensive review & enablement synthesis) |
| **Assessment Standard** | [`docs/ai-prompts/ai-agent-lab-expert-trainer-assessment-prompt.md`](../ai-prompts/ai-agent-lab-expert-trainer-assessment-prompt.md) |
| **Repository Baseline** | `gitops-control-plane` commit `595b249` (Post-Remediation Phase 6 Accepted) |
| **Target Documentation** | Root [`README.md`](../../README.md), [`devops-student-rebuild-guide.md`](../runbooks/devops-student-rebuild-guide.md), [`developer-tutorial.md`](../developer-tutorial.md), [`operational-drills-and-failure-injection.md`](../runbooks/operational-drills-and-failure-injection.md), [`tenant-iac-operations.md`](../runbooks/tenant-iac-operations.md), [`production-promotion-guardrails.md`](../production-promotion-guardrails.md), [`host-reboot-and-cluster-lifecycle.md`](../runbooks/host-reboot-and-cluster-lifecycle.md), and ApplicationSets / blueprints across catalog repositories |
| **Methodology** | Systematic pedagogical audit against the 5 Enablement Dimensions (Coverage, Scaffolding, Hands-on Design, Documentation, Transfer), local schema and CLI verification of copyable learner examples, and cognitive load journey analysis. |

---

## 1. Executive Summary & Overall Educational Score

### Overall Educational Effectiveness Score: **6.0 / 10**

### Score Justification
The lab is an **operational and architectural tour de force**: it models a realistic, multi-cluster enterprise control plane with central AWS emulation (Moto), multi-tenant GitOps pipelines, composition engines (Kro), cloud controllers (ACK), supply-chain admission security (Kyverno + native VAPs), SSO federation (Keycloak), and full-stack observability.

However, from an **educational enablement perspective**, the lab currently suffers from a pronounced **procedural bias**:
1. **The Controller Model is Blurred:** Learners observe actions happening (e.g. an SQS queue appearing), but documentation frequently attributes multiple distinct controller responsibilities to a single umbrella term like "GitOps" or "Kro", obscuring the distinct reconciliation loops of Argo CD, Kro, and ACK.
2. **Broken Copy-Paste Examples Break Trust:** Key learner examples (such as tenant IaC dev cluster sizing, developer tutorial SQS message publishing, and historical application count baselines) fail schema validation or point to incorrect AWS accounts/versions.
3. **Checklist Execution Over Mental Models:** A learner can run `make teardown && make setup && make bootstrap && make post-bootstrap` and pass 27 Bats tests without ever understanding what `Synced` actually guarantees, why `Healthy` is independent of sync status, or why a Moto `ACTIVE` record is fundamentally different from a functioning Kubernetes cluster.
4. **Drills are Siloed from the Learning Flow:** The exceptional failure injection drills in the operational playbook are treated as operational runbooks rather than sequenced learning checkpoints with "predict-observe-explain" scaffolding.

---

## 2. Evaluation Across Assessment Dimensions

| Dimension | Rating | Trainer Findings Summary |
|---|---|---|
| **1. Concept Coverage & Explicitness** | **Partial (6/10)** | Foundational terms are named, but the boundaries between reconcilers (Argo CD ApplicationSet &rarr; Argo CD Application &rarr; Helm Chart Render &rarr; Kro RGD &rarr; ACK CRD &rarr; AWS API) are left implicit. |
| **2. Learning Flow & Scaffolding** | **Weak (4.5/10)** | Starts immediately with an overwhelming 3-cluster, 42-application distributed build. Lacks prerequisite conceptual self-checks and gradual progression from 1 application to complex composition. |
| **3. Hands-on Design Quality** | **Strong (8/10)** | The failure injection drills (cloud loss, token expiry, Kyverno outage, out-of-band cloud drift) are world-class. However, they lack structured pause-and-reflect prompts before execution. |
| **4. Documentation Effectiveness** | **Uneven (5.5/10)** | Rich architecture diagrams and runbooks, but plagued by drifted numbers (32 vs 42 apps), outdated container tags, hardcoded wrong account numbers, and absent conceptual glossaries. |
| **5. Transfer of Learning** | **Moderate (6/10)** | Strong on GitOps repository segregation and least-privilege impersonation; weak on distinguishing local emulation shortcuts from real AWS production requirements. |

---

## 3. Educational Strengths

1. **Concrete Traceability from Git to Workload:**
   The multi-repository structure (`gitops-control-plane`, `platform-catalog`, `platform-charts`, `tenant-workloads`, `tenant-iac`, `orders-processor`) mirrors real-world enterprise separation of duties. A learner can trace a single commit in `tenant-workloads` across the hub, through the ApplicationSet generator, into the spoke namespace, and out to the worker container.
2. **Real-World Asynchronous Drift & Healing in Failure Drills:**
   The ACK drift drill ([`operational-drills-and-failure-injection.md`](../runbooks/operational-drills-and-failure-injection.md#drill-4-out-of-band-cloud-drift-repaired-by-ack)) is a masterclass in teaching controller reconciliation. When an SQS queue is deleted directly out-of-band in Moto, the learner sees that Kubernetes does *not* detect it instantly; rather, the ACK controller detects and heals it on its scheduled resync loop. This concretely dispels the misconception that Kubernetes controllers are instantaneous event listeners.
3. **Explicit Distinction Between Infrastructure Simulation and Real EKS:**
   The recent addition of the **Two-Tier Acceptance Model** note in [`tenant-iac-operations.md`](../runbooks/tenant-iac-operations.md#runbook-1-onboarding-a-new-team-cluster-create) clearly articulates why a mock ACK `status.status == ACTIVE` in Moto validates declarative composition and CARM account boundaries, but does not prove Kubernetes API reachability, node joining, CNI networking, or workload scheduling.
4. **Repeatable, Idempotent Baseline:**
   The rebuild scripts (`make setup`, `make bootstrap`, `make post-bootstrap`) provide a reliable, deterministic foundation. When an experiment goes wrong, the student can reset to a verified clean slate in under 7 minutes.

---

## 4. Key Gaps & Learning Risks

### ⚠️ Gap L-1: Multi-Controller Reconciliation Boundaries are Conflated (**Severity: High**)
* **Evidence:** In [`developer-tutorial.md`](../developer-tutorial.md#step-2-understand-the-service-manifest), lines 122–126 state:
  > *"Under the hood, **Kro** automatically generates: 1. A Kubernetes `Deployment`... 2. An AWS SQS Queue in Central Moto Cloud... 3. Passes the `QUEUE_URL` and `QUEUE_ARN` directly to your worker container."*
* **Pedagogical Flaw:** Kro does **not** create SQS queues in AWS/Moto. Kro is a Kubernetes-native resource composition engine; it only creates Kubernetes child custom resources defined in its ResourceGraphDefinition (RGD)—specifically an ACK `Queue` custom resource (`queue.sqs.services.k8s.aws`). The AWS ACK SQS controller is the component that talks to AWS/Moto. Furthermore, the developer writes a Helm values file (`deploy/values-dev.yaml`), which Argo CD renders into the `QueueBackedService` custom resource.
* **Learning Risk:** The learner attributes all automation to a single magic tool ("Kro" or "GitOps"), leaving them unable to isolate failure boundaries when an ACK controller is down or an Argo CD render fails.

```
What the docs say:
[ Developer commits values.yaml ] ──────► [ Kro Engine ] ──────► [ AWS SQS Queue ]

What actually happens (The 4 Reconcilers):
[ Git Commit ]
      │
      ▼ (Reconciler 1: Argo CD ApplicationSet & Application Controller)
[ Rendered QueueBackedService CR on Spoke ]
      │
      ▼ (Reconciler 2: Kro Controller)
[ ACK Queue CR + Kubernetes Deployment CR on Spoke ]
      │
      ▼ (Reconciler 3: ACK SQS Service Controller)
[ AWS SQS Queue in Moto Cloud (Account 111111111111) ]
```

---

### ⚠️ Gap L-2: Learner-Facing Examples Fail Local Validation or Hardcode Wrong Accounts (**Severity: High**)
* **Evidence:**
  1. **Schema Rejection in Tenant IaC Runbook:** [`tenant-iac-operations.md`](../runbooks/tenant-iac-operations.md#runbook-1-onboarding-a-new-team-cluster-create) (line 65) provides a copyable cluster claim example for `env: dev` with `maxSize: 4`. The repository's schema (`schema/cluster.schema.json`) enforces a strict rule: for `env: dev` or `test`, `maxSize <= 3`. Running the documented validation script (`python3 -c "import jsonschema..."`) immediately crashes with:
     ```text
     jsonschema.exceptions.ValidationError: 4 is greater than the maximum of 3
     ```
  2. **Wrong Account Number in SQS CLI Example:** [`developer-tutorial.md`](../developer-tutorial.md#step-4-interacting-with-simulated-aws-via-aws-cli) (line 196) gives a copyable command:
     ```bash
     aws --endpoint-url=http://localhost:5000 sqs send-message \
       --queue-url "http://localhost:5000/123456789012/orders-dev-queue" ...
     ```
     Under CARM (Cross-Account Resource Management), `orders-dev` belongs to AWS account `111111111111` (nonprod), NOT the default Moto account `123456789012`. If a student copies this command, it sends a message to a non-existent or wrong queue.
  3. **Stale Baseline Application Counts:** [`devops-student-rebuild-guide.md`](../runbooks/devops-student-rebuild-guide.md#2-verify-argo-cd-application-status) (line 226) and [`operational-drills-and-failure-injection.md`](../runbooks/operational-drills-and-failure-injection.md#2-pre-drill-health-check) (line 71) repeatedly instruct the student to verify that "all 32 applications report Synced and Healthy". The current accepted baseline contains **42 Applications**.
* **Learning Risk:** When advertised copyable examples fail or output does not match documentation, students lose confidence in the material and cannot distinguish their own mistakes from platform bugs.

---

### ⚠️ Gap L-3: Procedural Execution Dominates over Conceptual Scaffolding (**Severity: Medium**)
* **Evidence:** [`devops-student-rebuild-guide.md`](../runbooks/devops-student-rebuild-guide.md) provides an excellent 4-step sequence (`make teardown`, `make setup`, `make bootstrap`, `make post-bootstrap`), but:
  - It contains zero **Learning Objectives** at the start of each section.
  - It contains zero **Pause-and-Predict** reflection stops (e.g., "Before running `make bootstrap`, what resources exist on the hub? What will Argo CD do when `root-control-plane` is created?").
  - It inspects `Synced` and `Healthy` in Argo CD without ever defining the difference (e.g., an Application can be `Synced` because Git matches Kubernetes, but `Degraded` because pod containers are in CrashLoopBackOff).
* **Learning Risk:** The student completes the guide in 15 minutes, observes 100% green checkmarks, and acquires purely muscle-memory/procedural skills without internalizing the underlying declarative model.

---

### ⚠️ Gap L-4: Lifecycle Semantics (Pruning, Finalizers, OwnerReferences, Retention) are Disjointed (**Severity: Medium**)
* **Evidence:**
  - Kro finalizers and reverse-topological deletion are mentioned in [`tenant-iac-operations.md`](../runbooks/tenant-iac-operations.md).
  - Argo CD Application pruning is configured across ApplicationSets (`prune: false` vs `prune: true`).
  - Kubernetes `ownerReferences` are used in the Kro RGD blueprint.
  - Production cloud retention policies (`deletion-policy: retain` on prod vs `delete` on dev) are specified in Kro blueprints.
* **Pedagogical Flaw:** These concepts are scattered across disparate runbooks. There is no unified explanation of the **Kubernetes Garbage Collection Lifecycle vs External Cloud Resource Lifecycle**.
* **Learning Risk:** Students conflate deleting a Git file with deleting a Kubernetes resource, and conflate deleting a Kubernetes CR with terminating an external cloud resource.

---

### ⚠️ Gap L-5: Git Promotion vs Progressive Delivery (Canary/Rollouts) is Ambiguous (**Severity: Medium**)
* **Evidence:** [`production-promotion-guardrails.md`](../production-promotion-guardrails.md) discusses Git revision pinning (e.g. `valuesRevision: <commit-sha>`) for production promotion, but references Argo Rollouts, KEDA, and canary deployments as conceptual targets.
* **Pedagogical Flaw:** A student might complete the lab believing they practiced progressive delivery or canary traffic routing, when they actually practiced **declarative branch/commit promotion with standard rolling updates**.
* **Learning Risk:** Failure to understand the fundamental difference between **deployment promotion** (moving an immutable artifact/config across environments) and **traffic-weighted progressive delivery** (canary/blue-green within an environment).

---

## 5. Must-Understand Concept Checklist

| Must-Understand Concept | Educational Verdict | Detailed Assessment / Gap |
|---|:---:|---|
| **1. Declarative Desired State vs Observed Status** | **Partially Covered** | Covered procedurally via Git sync. Missing clear explanation of controller status fields and why status is owned by controllers, not Git. |
| **2. Controller Pattern & Continuous Reconciliation Loops** | **Partially Covered** | Observed during ACK out-of-band drift healing. Missing explicit diagram showing the periodic resync loop vs watch event loop. |
| **3. The 4-Tier Reconciler Chain (Argo CD &rarr; Kro &rarr; ACK &rarr; Cloud)** | **Missing / Conflated** | **Major gap:** Documentation repeatedly claims Kro generates SQS queues, hiding the ACK controller layer and Helm render step. |
| **4. Argo CD `Synced` vs `Healthy` Distinction** | **Partially Covered** | Both statuses are checked, but their architectural independence (sync = Git spec parity; health = runtime readiness) is never explained. |
| **5. ApplicationSet Generators & Dynamic Multi-Cluster Routing** | **Fully Covered** | Excellent coverage via Git and cluster generators routing between `spoke-nonprod` and `spoke-prod`. |
| **6. Custom Resource Definitions (CRDs) & Composition (Kro RGD)** | **Partially Covered** | Claims and RGDs are shown, but the CEL schema expressions and child dependency graph resolution are not taught. |
| **7. Multi-Tenant Account Isolation (CARM & IAM Impersonation)** | **Fully Covered** | Clear mapping between spoke namespaces, role assumptions (`arn:aws:iam::<account>:role/...`), and Moto accounts (`111111111111` vs `222222222222`). |
| **8. Deletion Lifecycles: Pruning, Finalizers, OwnerReferences, & Retention** | **Partially Covered** | Documented for tenant IaC, but lacks a comparative model showing Kubernetes garbage collection vs external cloud retention. |
| **9. Admission Governance: Webhooks (Kyverno) vs Native In-Tree Policies (VAP)** | **Fully Covered** | Clear distinction between image signature verification (Kyverno webhook) and registry allowlisting / deployer boundary (native VAPs). |
| **10. Immutable Production Artifact Promotion vs Progressive Delivery** | **Partially Covered** | Git SHA pinning for prod is well documented, but needs explicit contrast against canary/traffic-weighted delivery. |
| **11. Simulation Fidelity: Moto Mock Cloud vs Production AWS EKS** | **Partially Covered** | Two-tier acceptance model is documented in tenant IaC, but missing in student rebuild guide and developer tutorial. |

---

## 6. Prioritized Enablement Recommendations

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                       ENABLEMENT ROADMAP PRIORITY                           │
│                                                                             │
│  [ P0: Immediate Fixes ]    Fix Broken Examples & Stale Baselines (L-2)     │
│             │                                                               │
│             ▼                                                               │
│  [ P1: Structural Scaffolding ] Disentangle the 4 Reconcilers (L-1)         │
│                               Embed "Predict-Observe-Explain" Drills (L-3)  │
│             │                                                               │
│             ▼                                                               │
│  [ P2: Conceptual Transfer ] Add Concept Glossary & Lifecycle Guide (L-4)   │
│                               Clarify Git Promotion vs Canary (L-5)         │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Priority P0: Fix Stale Examples and Schema Violations (Immediate)
1. **Fix Tenant IaC Example:** In [`tenant-iac-operations.md`](../runbooks/tenant-iac-operations.md#runbook-1-onboarding-a-new-team-cluster-create), update the copyable dev cluster claim to use `maxSize: 3` (or `env: prod` with `maxSize: 4`) so that the local `python3 jsonschema.validate` verification succeeds.
2. **Fix Developer Tutorial SQS Command:** In [`developer-tutorial.md`](../developer-tutorial.md#step-4-interacting-with-simulated-aws-via-aws-cli), replace the hardcoded account `123456789012` with dynamic queue discovery or the correct CARM nonprod account:
   ```bash
   QUEUE_URL=$(aws --endpoint-url=http://localhost:5000 --region us-east-1 sqs get-queue-url --queue-name orders-dev-queue --queue-owner-aws-account-id 111111111111 --output text --query QueueUrl)
   aws --endpoint-url=http://localhost:5000 sqs send-message --queue-url "$QUEUE_URL" --message-body '{"orderId": "ORD-1234", "customer": "Alice", "amount": 99.50}'
   ```
3. **Synchronize Application Baselines:** Update [`devops-student-rebuild-guide.md`](../runbooks/devops-student-rebuild-guide.md) and [`operational-drills-and-failure-injection.md`](../runbooks/operational-drills-and-failure-injection.md) from 32 to **42 Applications**.

### Priority P1: Disentangle Reconcilers and Add Pedagogical Scaffolding
1. **Create the "One Claim, Four Reconcilers" Guide:** Add an illustrated section in `developer-tutorial.md` and `devops-student-rebuild-guide.md` explicitly defining the boundary between:
   - *Argo CD Application Controller:* Reconciles Git manifests &rarr; Kubernetes cluster.
   - *Helm Engine:* Renders `values.yaml` into `QueueBackedService` custom resource.
   - *Kro Engine:* Expands `QueueBackedService` into ACK `Queue` CR and Kubernetes `Deployment`.
   - *ACK SQS Controller:* Reconciles ACK `Queue` CR &rarr; AWS/Moto SQS Queue.
2. **Incorporate "Predict-Observe-Explain" Checkpoints:** In [`devops-student-rebuild-guide.md`](../runbooks/devops-student-rebuild-guide.md), add reflection tables after each step:
   - *Step 2 (Setup):* Before running, what is running on the host? After running, what is the difference between `k3d-hub-cluster` and the two spokes?
   - *Step 3 (Bootstrap):* Why does creating a single Argo CD application (`root-control-plane`) cause 41 other applications to appear?
   - *Step 4 (Post-Bootstrap):* Why is `argo-cd` set to manual sync by default?
3. **Promote Drills to Learning Milestones:** Move Drill 4 (Out-of-Band Cloud Drift) directly into the core student tutorial so every learner personally deletes an SQS queue in Moto and watches the ACK controller heal it.

### Priority P2: Concept Glossaries & Conceptual Boundaries
1. **Add an Enterprise GitOps Glossary:** Create a reference table contrasting:
   - `Synced` vs `Healthy` vs `Ready`.
   - `ApplicationSet` vs `Application` vs `AppProject`.
   - `ownerReferences` (Kubernetes cascade deletion) vs `Finalizers` (pre-delete blocking hook) vs `deletion-policy: retain` (external cloud preservation).
2. **Explicit Promotion vs Progressive Delivery Note:** Add a clear callout in `production-promotion-guardrails.md` contrasting the lab's declarative Git revision promotion model with traffic-based canary deployments (Argo Rollouts).

---

## 7. Suggested Trainer Reflection & Validation Questions

A trainer or enablement lead should use these 8 questions to evaluate whether a student has achieved true conceptual understanding or merely executed commands:

1. **The Reconciler Trace:**  
   *"You edit `replicas: 3` in `deploy/values-dev.yaml` and push to GitHub. Name the four distinct software components that process this change before the third pod starts, and name one log or status field you would check to verify each component's success."*
2. **The Status Disconnect (`Synced` vs `Healthy`):**  
   *"In the Argo CD UI, your application is showing `Synced` with a green checkmark, but `Degraded` with a red heart. Explain how this state is possible. What does `Synced` prove, and what does `Degraded` prove?"*
3. **Out-of-Band Cloud Drift:**  
   *"An operator manually deletes the `orders-dev-queue` directly in the AWS console (or Moto API). Does Argo CD detect this drift? Why or why not? What component will detect it, and when?"*
4. **Composition vs Cloud Control:**  
   *"What is the difference between what Kro does and what AWS ACK does? If the ACK SQS controller pod is killed, can Kro still reconcile a new `QueueBackedService`? What state will the system be in?"*
5. **Deletion & Cascade Semantics:**  
   *"You delete `tenants/tenant-a/apps/orders-dev.yaml` from Git. Describe the cascade sequence: What does Argo CD do? What does Kubernetes garbage collection do to the worker pods? What does ACK do to the Moto SQS queue? How would this behavior change in production if the deletion policy was set to `retain`?"*
6. **GitOps Exceptions:**  
   *"The guide states that 'Git is the single source of truth for everything running'. Name two pieces of state in this lab that are intentionally NOT stored in Git, and explain why storing them in Git would violate security or operational best practices."*
7. **Admission Control Layering:**  
   *"You attempt to run an unapproved container image `docker.io/library/nginx:latest` in the `orders-dev` namespace. Which admission control denies it first: Pod Security Standards (`restricted`), the native ValidatingAdmissionPolicy (`tenant-image-registry-allowlist`), or Kyverno (`tenant-images-signed`)? Why?"*
8. **The Simulation Reality Gap:**  
   *"A student shows you that their new `TeamEKSCluster` claim reports `Ready=True` in Prometheus metrics on the hub. Does this prove that a developer can run `kubectl get pods` against that team's new EKS cluster? Explain the difference between Moto's ACK simulation and real AWS EKS convergence."*

---

## 8. Final Trainer Verdict

The lab provides an **exceptionally mature and stable technical platform**. Its operational mechanics, multi-cluster topology, security boundaries, and telemetry are production-grade. 

To transform this platform into an **elite training program**, the project must now invest in its **enablement layer**:
1. Correct the copyable examples so students never encounter false-negative errors.
2. Disentangle the controller chain so students understand the distinct roles of Argo CD, Kro, and ACK.
3. Transform passive command execution into an active "Predict & Observe" discovery journey.
