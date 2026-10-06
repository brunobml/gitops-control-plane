# Lab Learning Assessment — 2026-10-06

> **Perspective:** Expert trainer / technical enablement. This assesses what a learner can explain and transfer after completing the lab, rather than whether the platform is operationally healthy.

| | |
|---|---|
| **Document version** | **1.0 — initial Codex assessment** |
| **Status** | Awaiting independent trainer review and revision |
| **Author / assessment date** | Codex / 2026-10-06 |
| **Planned peer reviewer** | Agy |
| **Assessment prompt** | [Expert trainer assessment prompt](../ai-prompts/ai-agent-lab-expert-trainer-assessment-prompt.md) |
| **Repository baseline** | `gitops-control-plane` `595b249`; the [2026-10-06 technical remediation](../remediation/2026-10-06-lab-assessment/2026-10-06-lab-remediation-plan-phase6-validation-02.md) is accepted |
| **Material reviewed** | Root [README](../../README.md), [student rebuild guide](../runbooks/devops-student-rebuild-guide.md), [developer tutorial](../developer-tutorial.md), [operational drills](../runbooks/operational-drills-and-failure-injection.md), [tenant IaC runbook](../runbooks/tenant-iac-operations.md), [promotion guide](../production-promotion-guardrails.md), ApplicationSets, and relevant sibling-repository claims and blueprints |
| **Method and limit** | Read-only document and source review, plus a local schema check of the tenant IaC runbook example. No learner observation, interview, timed task, or live lab run was performed. The score estimates *teachability of the material*, not measured learner outcomes. |

## Overall educational effectiveness: **6.0 / 10**

The lab gives a motivated engineer a credible platform to explore and strong operational drills. It does **not yet reliably teach the controller model from first principles**. A learner can rebuild the estate and pass smoke tests while still being unable to explain which controller owns which transition, why `Synced` differs from `Healthy`, or why a Moto `ACTIVE` EKS record is not a usable Kubernetes cluster. Several learner-facing examples have drifted far enough from the current lab to interrupt or misdirect practice.

| Dimension | Assessment |
|---|---|
| Concept coverage and explicitness | **Partial.** The parts are named, but the Argo CD → kro → ACK handoffs and ownership semantics are mostly inferred from diagrams and YAML. |
| Learning flow and scaffolding | **Weak.** The rebuild guide starts with a complex three-cluster procedure; prerequisites list tools but do not state the knowledge needed or provide a smaller first exercise. |
| Hands-on design | **Strongest area.** The failure drills name expected signals and recovery paths, but are separate from the main learner journey and rarely ask for a prediction before action. |
| Documentation effectiveness | **Uneven.** Diagrams and commands help navigation; stale counts and invalid examples reduce trust in the instructions. There is no compact glossary or comprehension check. |
| Transfer of learning | **Partial.** The Moto-versus-real-EKS distinction is explicit in the tenant IaC runbook, while broader production design documents mix deployed behavior with future options. |

## Strengths

1. **The system is observable enough to teach causality.** The [README architecture diagram](../../README.md) shows Git repositories, the hub, spokes, kro, ACK, and Moto; the [developer tutorial](../developer-tutorial.md) follows an order service from registration to worker and queue. These are useful anchors for tracing a change across layers.
2. **The operational drills teach real failure behavior.** The [drills playbook](../runbooks/operational-drills-and-failure-injection.md) states the expected signal for Moto credential loss, Kyverno outage, ACK cloud drift, tenant deregistration, and log post-mortems. In particular, the ACK drift drill shows that an out-of-band queue deletion is repaired on a controller resync, rather than immediately.
3. **The tenant infrastructure runbook exposes lifecycle and simulation limits.** It traces a claim through ApplicationSet, `TeamEKSCluster`, kro, ACK, and Moto, explains deletion/retention, and distinguishes a mock `ACTIVE` record from real EKS API, node, workload, and networking acceptance. See the [architecture and two-tier acceptance note](../runbooks/tenant-iac-operations.md).
4. **Rebuild and smoke gates provide repeatable observations.** The [student guide](../runbooks/devops-student-rebuild-guide.md) and [full rebuild runbook](../runbooks/full-rebuild-and-acceptance.md) give a known starting state. A trainer can use the same estate for comparative exercises across dev, test, and prod.

## Gaps and learner risks

### L-1 — Core controller boundaries remain implicit (**High**)

The [developer tutorial](../developer-tutorial.md) says kro “automatically generates” an AWS SQS queue in Moto. The actual [QueueBackedService blueprint](../../../platform-catalog/blueprints/queue-backed-service-rgd.yaml) creates Kubernetes child resources, including ACK `Queue` custom resources; the ACK controller then calls Moto. The distinction between an ApplicationSet generating an Argo CD Application, an Application applying a claim, kro expanding that claim, and ACK reconciling an external resource is not taught as a sequence of separate controllers. The tutorial also presents a `QueueBackedService` manifest while directing learners to `deploy/values-dev.yaml`, which is a Helm values file, without showing the render step between them.

**Learning risk:** A learner may attribute every observed change to “GitOps” or kro and cannot isolate the controller responsible when a stage stalls.

### L-2 — Learner-facing examples fail or describe an older estate (**High**)

- The [tenant IaC request example](../runbooks/tenant-iac-operations.md) uses `env: dev` with `maxSize: 4`. The current [claim schema](../../../tenant-iac/schema/cluster.schema.json) limits dev/test to 3. A local JSON Schema check returned `4 is greater than the maximum of 3` for that exact example.
- The [student guide](../runbooks/devops-student-rebuild-guide.md) says 32 Applications must be healthy, while the accepted baseline has 42. The [older drills](../runbooks/operational-drills-and-failure-injection.md) also state a 32-Application baseline. Historical screenshots should be labeled as snapshots, not current expected output.
- The [developer tutorial](../developer-tutorial.md) shows a tag-only `orders-processor:v1.2.0` image, while current dev values use a signed, digest-pinned `v1.5.0` image. Its sample SQS URL uses Moto's default account `123456789012`; dev queues belong to nonprod account `111111111111` in the current [ApplicationSet](../../applicationsets/tenant-workloads-tenant-a.yaml). The copyable `send-message` example can therefore point at the wrong queue.
- The [README repository tree](../../README.md) still labels `push-all.sh` as pushing five repositories although the Quick Start correctly lists six; it also says 20 alert rules where current CI validates 22.

**Learning risk:** The student cannot tell whether a failure is an intended lesson or stale instructions. Incorrect examples particularly weaken confidence in schema validation, account isolation, and image provenance.

### L-3 — The learner journey measures completion more than understanding (**Medium**)

The [student guide](../runbooks/devops-student-rebuild-guide.md) offers tool prerequisites, a four-command rebuild, screenshots, and checks, but no learning objectives, conceptual prerequisites, pause-and-predict points, or explanation rubric. `Synced` and `Healthy` are inspected without defining what each proves. The rich failure drills are linked as a separate playbook rather than sequenced into a core exercise. The reviewed primary learner guides contain no self-check or reflection questions.

**Learning risk:** A learner can finish the checklist by copying commands and never build a mental model of reconciliation, drift, status conditions, or ownership.

### L-4 — Ownership, deletion, and GitOps exceptions need a shared explanation (**Medium**)

The [tenant IaC runbook](../runbooks/tenant-iac-operations.md) mentions a kro finalizer, reverse deletion order, and prod retention, while the application [blueprint](../../../platform-catalog/blueprints/queue-backed-service-rgd.yaml) contains `ownerReferences`. These are important but not explained together as Kubernetes garbage collection versus controller-managed external deletion. The [student guide](../runbooks/devops-student-rebuild-guide.md) states that everything running is declared in Git, yet bootstrap, local credentials, token renewal, and recovery scripts create or update state outside Git. Those exceptions are legitimate, but the guide should name them so “Git as source of truth” is not taught as “every byte comes from Git.”

**Learning risk:** Learners may mispredict what is removed when a claim or Application is deleted, and may overlook credentials and retained cloud resources during recovery.

### L-5 — Deployed promotion and future progressive delivery blur together (**Medium**)

The [promotion guide](../production-promotion-guardrails.md) is marked a design reference and explains the current pinned-revision production flow, but most of its diagrams and examples still use pre-Phase-4 ApplicationSets and alternative gate patterns. The [progression roadmap](../lab-progression-and-next-steps.md) describes KEDA and Argo Rollouts as future tracks. No current learner exercise demonstrates a canary or traffic-weighted rollout. A learner needs an explicit comparison between **current Git revision promotion**, a normal Kubernetes rolling update, and **future** progressive delivery.

**Learning risk:** Completing the lab may be mistaken for having practiced Argo Rollouts or automated canary analysis.

## Prioritized recommendations

| Priority | Change | Acceptance evidence for a trainer |
|---|---|---|
| **P0** | Repair copyable examples and current-state claims in the student guide, developer tutorial, tenant IaC runbook, README, and drill preflight. Use schema-valid dev values, discover the SQS QueueUrl with AWS CLI instead of hard-coding an account URL, and label older screenshots with their snapshot date/count. | A new learner can run each advertised example against the current lab; a docs check validates embedded claim fixtures and flags stale fixed counts. |
| **P1** | Add a one-page “one claim, four reconcilers” map: registration file → ApplicationSet/Application → Helm-rendered CR → kro children → ACK CR/Moto resource. Name each desired-state source, controller, status signal, and failure boundary. Show the values file and rendered CR side by side. | A learner can identify the owner of a stalled queue or workload without being told which log to open. |
| **P1** | Reorder the core learner path into a small read-only trace, one safe dev change, one deliberate drift/failure exercise, then the full rebuild and multi-cluster comparison. State required knowledge (Git branches/PRs, Kubernetes objects/controllers, Helm values) and mark advanced SSO/security material as a later layer. | Each stage has an objective, a prediction, an observed state, and a short explanation in the learner's own words. |
| **P1** | Promote selected existing drills into guided exercises. Before deleting a dev queue or changing a dev replica value, ask learners to predict which controller acts, which status/metric changes first, and what remains if reconciliation is paused; include restoration steps. | An instructor can assess reasoning from a prediction/observation table, not only a green smoke result. |
| **P2** | Add a concise concept glossary and comparison table for ApplicationSet/Application/AppProject, CRD/CR/RGD, `Synced`/`Healthy`/`Ready`, owner reference/finalizer, Git drift/cloud drift, and mock record/usable cluster. Explain bootstrap and credential exceptions to GitOps. | A learner can answer the reflection questions below without relying on tool names alone. |
| **P2** | Separate current promotion behavior from optional KEDA and Argo Rollouts material. Make the Moto-to-real-EKS acceptance checklist a learner exercise: identify which current green signals transfer and which must be newly tested. | A learner can distinguish a pinned prod revision from a canary rollout and a mock `ACTIVE` record from a schedulable EKS cluster. |

## Must-understand concept checklist

“Fully covered” means the learner-facing material explains the idea and supplies an observation or exercise that demonstrates it; this is a documentation verdict, not a claim that every learner has mastered it.

| Concept | Verdict | Evidence / gap |
|---|---|---|
| Git holds desired declarative configuration; reconciliation closes drift | **Partially covered** | README and drills show self-heal, but GitOps exceptions and controller responsibility are not taught together. |
| k3d hub/spoke topology and environment routing | **Fully covered** | README, student guide, and ApplicationSet examples identify hub, spokes, and dev/test/prod routing. |
| ApplicationSet generates Applications; Application syncs rendered resources; AppProject constrains scope | **Partially covered** | Config and diagrams exist; the learner path does not explicitly contrast the three objects. |
| Helm values versus rendered `QueueBackedService` CR | **Partially covered** | Tutorial shows both ideas but skips the render handoff. |
| CRD/custom resource and kro ResourceGraphDefinition semantics | **Partially covered** | Runbooks show claims and resource graphs; definition, `readyWhen`, and generated child ownership need a guided trace. |
| ACK service controller reconciles Kubernetes CRs with Moto cloud resources | **Partially covered** | Drift drill observes ACK repair; tutorial wording obscures kro/ACK division of work. |
| `Synced`, `Healthy`, kro `Ready`, and ACK status/conditions | **Partially covered** | Checks and the Moto readiness caveat exist, but the meanings and non-equivalence are not a core lesson. |
| Owner references, finalizers, pruning, and external retain/delete policy | **Partially covered** | Tenant IaC deletion is described; a general comparison and learner exercise are missing. |
| Diagnose Git drift versus out-of-band cloud drift and controller outage | **Partially covered** | Good drills exist, but are not required or reflected on in the primary learning flow. |
| Production promotion versus progressive rollout/canary | **Partially covered** | Current pinned-revision promotion is documented; canary delivery remains a future design. |
| Moto simulation boundary versus real EKS usability | **Partially covered** | Explicit in tenant IaC runbook, not reinforced at the student guide's green-state checks. |

## Reflection and validation questions

1. A tenant commits a new dev registration file. Which component creates the Argo CD Application, which component applies the `QueueBackedService`, which creates the ACK `Queue` CR, and which calls Moto? Name one object or log you would inspect at each boundary.
2. The Application is `Synced`, but the `TeamEKSCluster` reports `Ready=False`. What does `Synced` prove? Which kro/ACK status or condition would you inspect next?
3. A dev queue is deleted directly in Moto. What should happen during ACK's next resync? How does that differ from deleting the claim from Git?
4. Why can a prod cluster claim remain `Ready=True` in the Moto lab while no tenant Kubernetes API accepts `kubectl` commands? What additional observations would real EKS acceptance require?
5. When a nonprod team claim is removed, what do Argo CD pruning, kro finalizers/owner references, and ACK deletion each do? Why does the prod retention path differ?
6. If a developer changes `deploy/values-prod.yaml` but the production registration still pins the old `valuesRevision`, should prod change? How is that different from a canary rollout?
7. Which parts of the lab are intentionally created or renewed outside Git, and how do you reconcile those exceptions with the principle that Git is the source of desired configuration?
8. A new team claim has no `lab_team_cluster_ready` series. Why is an absent metric different from a zero metric, and which gate or alert should detect the loss?

## Overall trainer verdict

The lab is **operationally complete but educationally unfinished**. Keep the platform baseline intact; improve the teaching layer first. Correct the examples, teach the controller handoffs explicitly, and make learners predict and explain one successful reconciliation and one failure recovery. A follow-up assessment should include a learner trial: ask someone unfamiliar with the implementation to complete those tasks and answer the questions above without coaching.
