# Lab Learning Remediation Plan — 2026-10-06 Learning Assessment: Technical Enablement, Mental Models & Pedagogical Hygiene

> **Status: Proposed (v1.0).** Awaiting peer review and sign-off before implementation.

| | |
|---|---|
| **Plan Version** | **1.0 (Proposed 2026-10-06)** |
| **Assessment Reference** | [`docs/assessments/2026-10-06-lab-learning-assessment.md`](../../assessments/2026-10-06-lab-learning-assessment.md) (v3.0, Score: **6.0 / 10**) |
| **Assessment Standard** | [`docs/ai-prompts/ai-agent-lab-expert-trainer-assessment-prompt.md`](../../ai-prompts/ai-agent-lab-expert-trainer-assessment-prompt.md) |
| **Repository Baseline** | `gitops-control-plane` commit `6fb365d` (42 Applications Synced/Healthy, 27/27 Bats gates passing) |
| **Target Documentation** | Root [`README.md`](../../../README.md), [`devops-student-rebuild-guide.md`](../../runbooks/devops-student-rebuild-guide.md), [`developer-tutorial.md`](../../developer-tutorial.md), [`operational-drills-and-failure-injection.md`](../../runbooks/operational-drills-and-failure-injection.md), [`tenant-iac-operations.md`](../../runbooks/tenant-iac-operations.md), [`production-promotion-guardrails.md`](../../production-promotion-guardrails.md), [`argocd-cli.md`](../../runbooks/argocd-cli.md), [`lab-progression-and-next-steps.md`](../../lab-progression-and-next-steps.md) |
| **Author** | Antigravity (Advanced Agentic AI) |
| **Planned Reviewers** | Codex / Claude Opus / Lab Owner |

---

## 1. Review & Approval Sign-Off

| Field | Details |
|---|---|
| **Current Status** | 🟡 **PROPOSED v1.0 (Awaiting Reviewer Sign-Off)** |
| **Target Completion** | 2026-10-07 |
| **Execution / Validation Model** | The party that implements a track authors `…-implemented-NN.md`; an independent validator authors `…-validation-NN.md`. The implementer never self-certifies acceptance. |

### Operational & Pedagogical Guardrails

| ID | Focus Area | Pedagogical & Operational Guardrail | Status |
|:---:|:---:|---|:---:|
| **P-0** | **Empirical Example Truth** | **Every copyable example must be executable without errors.** No student-facing command may fail schema validation, query non-existent queues, or reference incorrect AWS accounts. Test all commands against live Moto / k3d before committing. | 🛡️ Enforced |
| **P-1** | **The Four-Reconciler Chain** | **No single tool may be credited with another controller's work.** Documentation must explicitly depict the 4-tier chain: (1) Argo CD AppSet/App &rarr; (2) Helm Render &rarr; (3) Kro RGD Composition &rarr; (4) ACK Controller &rarr; AWS/Moto API. Kro must never be described as "generating an SQS queue". | 🛡️ Enforced |
| **P-2** | **Argo CD Health Transparency** | **Custom CRD health location must be explicitly taught.** Explain that Argo CD 3.x evaluates custom health checks in the resource tree (`argocd app get --output tree`) and UI, but does not copy them into `.status.resources[].health` of the Application CR, dispelling validator false positives. | 🛡️ Enforced |
| **P-3** | **Active Learning Scaffolding** | **No blind procedural copy-pasting.** The rebuild guide and tutorial must provide Learning Objectives and structured "Predict–Observe–Explain" reflection tables at every milestone. | 🛡️ Enforced |
| **P-4** | **Production vs Simulation Reality** | **Promotion and simulation boundaries must be realistic.** Distinguish the lab's Git SHA promotion + automated sync from traffic-weighted canary rollouts; emphasize why Moto `ACTIVE` clusters differ from schedulable AWS EKS clusters. | 🛡️ Enforced |

---

## 2. Executive Summary & Problem Statement

The 2026-10-06 Learning Assessment evaluated the lab through the lens of a **Senior Technical Enablement Specialist**. While the platform achieved an operational maturity of **8.4 / 10** with 42 applications and 27 passing Bats tests, its educational enablement score was rated **6.0 / 10**.

### Core Educational Deficiencies
1. **Procedural Bias Over Mental Models (L-3):** Students execute commands sequentially (`make setup && make bootstrap && make post-bootstrap`) without building an understanding of reconciliation loops, drift detection, or status ownership.
2. **Conflated Reconciler Chains (L-1, L-6):** The developer tutorial claims "Kro generates an SQS Queue" and shows a raw Kro CR labeled as a Helm values file with an outdated, unsigned image tag (`v1.2.0`) rejected by Kyverno.
3. **Broken Copy-Paste Commands (L-2):**
   * Tenant IaC dev cluster claim uses `maxSize: 4` (crashes schema check: `4 is greater than maximum of 3`).
   * Developer tutorial SQS commands use Moto's default account `123456789012` instead of CARM nonprod account `111111111111` (returns `NonExistentQueue`).
   * Documentation across 5 files still references an obsolete "32 Applications" baseline instead of 42.
4. **Hidden Health Architecture (L-7):** The absence of health fields in `Application.status.resources` for CRDs is undocumented, confusing learners and expert validators alike.
5. **Scattered Lifecycle & Promotion Models (L-4, L-5, L-8):** Deletion semantics (pruning, finalizers, `ownerReferences`, retention) are scattered, the promotion guide contradicts the live lab's automated sync, and architecture diagrams omit tier-1 networking, ACK EC2/IAM/EKS controllers, and tenant IaC.

This plan systematically addresses all 8 findings (`L-1` through `L-8`) across four actionable phases.

---

## 3. Track Phasing & High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                       REMEDIATION PHASING ARCHITECTURE                      │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  [ TRACK 1: Priority P0 — Example Hygiene & Baseline Alignment ]            │
│    • Fix tenant IaC schema dev sizing (L-2.1)                               │
│    • Fix SQS cross-account STS assume-role commands (L-2.2)                 │
│    • Align 5 stale "32 Applications" baselines to 42 (L-2.3)                │
│    • Fix tutorial manifest to real Helm values + rendered CR (L-6)          │
│                                      │                                      │
│                                      ▼                                      │
│  [ TRACK 2: Priority P1 — The 4-Tier Reconciler Model & Health ]            │
│    • Author "One Change, Four Reconcilers" architectural map (L-1)          │
│    • Author "Status & Health Primer" (tree vs status.resources) (L-7)       │
│                                      │                                      │
│                                      ▼                                      │
│  [ TRACK 3: Priority P1 — Pedagogical Scaffolding & Drills ]                │
│    • Embed "Predict–Observe–Explain" tables in Rebuild Guide (L-3)          │
│    • Promote SQS Cloud Drift (Drill 4) to mandatory learner milestone (L-3) │
│    • Refresh architecture views (tier-1 VPC, EC2/IAM/EKS, tenant IaC) (L-8) │
│                                      │                                      │
│                                      ▼                                      │
│  [ TRACK 4: Priority P2 — Conceptual Transfer & Reference ]                 │
│    • Author Unified Lifecycle & Deletion Comparison Matrix (L-4)            │
│    • Align Promotion Guide with live SHA-pinning + clarify canary (L-5)     │
│    • Author Enterprise GitOps Glossary and concept lessons (L-3, L-4)       │
│                                      │                                      │
│                                      ▼                                      │
│  [ TRACK 5: Verification, Validation & Trainer Sign-off ]                   │
│    • Run full CI, Alert Rules, Smoke Tests, and Automated Doc Verifier      │
│    • Independent Trainer Validation & Sign-off                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 4. Track 1: Immediate Example Hygiene & Baseline Alignment (Priority P0)

### Step 1.1: Fix Dev Cluster Claim Schema Violation (`L-2.1`)
* **File:** `docs/runbooks/tenant-iac-operations.md` (lines 56–66)
* **Problem:** The copyable dev claim example specifies `maxSize: 4`. Running the advertised verification command (`python3 -c "import jsonschema..."`) fails with `ValidationError: 4 is greater than the maximum of 3`.
* **Fix:** Update `maxSize` to `3` for `env: dev` to comply with `tenant-iac/schema/cluster.schema.json`:
  ```yaml
  team: team-data
  name: ml-feature-store
  env: dev
  kubernetesVersion: "1.33"
  network: platform-default
  nodeGroup:
    instanceType: t3.medium
    minSize: 1
    desiredSize: 2
    maxSize: 3
  ```
* **Verification:** Run the schema validation command locally; assert exit code `0`.

---

### Step 1.2: Fix SQS Cross-Account Commands in Developer Tutorial (`L-2.2`)
* **File:** `docs/developer-tutorial.md` (lines 152, 195–198, 233–234)
* **Problem:** Hardcodes default Moto account `123456789012` for `orders-dev-queue`. Under CARM, `orders-dev` belongs to account `111111111111`. Running the sample AWS CLI command returns `AWS.SimpleQueueService.NonExistentQueue` because Moto resolves queue names in the caller's authenticated account.
* **Fix:**
  1. In Step 3 (line 152), update the sample log output:
     ```text
     🚀 Worker started for [dev] listening on http://moto-cloud:5000/111111111111/orders-dev-queue
     ```
  2. In Step 4 (lines 186–198), introduce the nonprod STS role assumption helper (matching Drill 4's `moto111`) before calling `get-queue-url` and `send-message`:
     ```bash
     # Assume the nonprod tenant role for account 111111111111 (CARM isolation)
     creds=$(AWS_ACCESS_KEY_ID=mock-key AWS_SECRET_ACCESS_KEY=mock-secret aws --endpoint-url=http://localhost:5000 --region us-east-1 \
       sts assume-role --role-arn arn:aws:iam::111111111111:role/learner --role-session-name learner --query Credentials --output json)
     export AWS_ACCESS_KEY_ID=$(jq -r .AccessKeyId <<<"$creds")
     export AWS_SECRET_ACCESS_KEY=$(jq -r .SecretAccessKey <<<"$creds")
     export AWS_SESSION_TOKEN=$(jq -r .SessionToken <<<"$creds")

     # Discover your dev queue URL dynamically
     QUEUE_URL=$(aws --endpoint-url=http://localhost:5000 --region us-east-1 sqs get-queue-url --queue-name orders-dev-queue --output text)

     # Publish a test message
     aws --endpoint-url=http://localhost:5000 --region us-east-1 sqs send-message \
       --queue-url "$QUEUE_URL" \
       --message-body '{"orderId": "ORD-1234", "customer": "Alice", "amount": 99.50}'
     ```
  3. In the Developer Cheat Sheet (lines 233–234), update the commands and cross-reference `make moto-resources`.
* **Verification:** Run the assumed-role commands against Moto; assert message publishes successfully and worker processes it.

---

### Step 1.3: Update Stale 32-to-42 Applications Baselines (`L-2.3`)
* **Files:**
  * `docs/runbooks/devops-student-rebuild-guide.md` (lines 226, 307)
  * `docs/runbooks/operational-drills-and-failure-injection.md` (lines 7, 71)
  * `docs/runbooks/argocd-cli.md` (line 134)
* **Problem:** Text tells learners to verify "all 32 applications are Synced and Healthy", while the live estate contains 42 applications.
* **Fix:** Replace `32` with `42` in all 5 locations. Add a note explaining the breakdown: 37 platform baseline applications + 5 tenant applications (`orders-dev`, `orders-test`, `orders-prod`, `team-data-analytics-dev`, `team-data-analytics-prod`).
* **Verification:** Run `grep -n "32" <files>` to ensure zero stale baseline counts remain.

---

### Step 1.4: Fix Developer Tutorial Manifest Presentation (`L-6`)
* **File:** `docs/developer-tutorial.md` (Step 2, lines 97–126)
* **Problem:** Section says "Look at `deploy/values-dev.yaml` ... (or the rendered `QueueBackedService` CR)" and displays a raw Kro Custom Resource with incorrect key `messageRetentionPeriod` and unsigned image tag `orders-processor:v1.2.0` (which Kyverno admission rejects).
* **Fix:** Clearly separate the developer input from the platform output:
  1. First, show the actual developer input from `orders-processor/deploy/values-dev.yaml`:
     ```yaml
     name: orders
     environment: dev
     replicas: 1
     retentionPeriod: "86400"
     image: ghcr.io/brunobml/orders-processor:v1.5.0@sha256:e95bb63320628d8541e984b668474bcc21066e54110d00ab20974132f1287510
     ```
  2. Next, show the rendered Kro Custom Resource generated by Helm on the spoke (`kubectl --context k3d-spoke-nonprod -n orders-dev get queuebackedservice orders -o yaml`):
     ```yaml
     apiVersion: kro.run/v1alpha1
     kind: QueueBackedService
     metadata:
       name: orders
       namespace: orders-dev
     spec:
       name: orders
       environment: dev
       replicas: 1
       retentionPeriod: "86400"
       image: ghcr.io/brunobml/orders-processor:v1.5.0@sha256:e95bb63320628d8541e984b668474bcc21066e54110d00ab20974132f1287510
     ```
  3. Explain the transformation: Helm reads `values-dev.yaml` and stamps out the `QueueBackedService` CR; Kro then reads that CR.
* **Verification:** Confirm all fields and image digests match `orders-processor/deploy/values-dev.yaml` exactly.

---

## 5. Track 2: The Multi-Reconciler Mental Model & Status Transparency (Priority P1)

### Step 2.1: Author "One Change, Four Reconcilers" Guide (`L-1`)
* **Files:** `docs/developer-tutorial.md`, `docs/runbooks/devops-student-rebuild-guide.md`
* **Problem:** Learners attribute all automation to "Kro" or "GitOps" and cannot isolate failure boundaries.
* **Content to Add:**
  * Embed the 4-tier reconciler diagram:
    ```
    [ Git Repository ]
          │  Reconciler 1: Argo CD ApplicationSet Controller
          ▼  (Detects registration file, dynamically generates Argo CD Application)
    [ Argo CD Application ]
          │  Reconciler 2: Argo CD Application Controller
          ▼  (Renders Helm chart values into QueueBackedService CR, applies to Spoke)
    [ QueueBackedService CR on Spoke ]
          │  Reconciler 3: Kro Engine Controller
          ▼  (Expands RGD: creates Deployment, Service, and ACK Queue CRs)
    [ ACK Queue CR (sqs.services.k8s.aws) ]
          │  Reconciler 4: AWS ACK SQS Service Controller
          ▼  (Assumes IAM CARM role in account 111111111111, calls Moto SQS API)
    [ AWS SQS Queue in Moto Cloud ]
    ```
  * Add a "Diagnostic Cheat Sheet for the 4 Reconcilers":
    | Reconciler | What It Watches | What It Writes | Where Status Is Reported | How to Diagnose Stalls |
    |---|---|---|---|---|
    | **1. ApplicationSet** | `tenant-workloads` Git files | Argo CD `Application` CR on Hub | Hub: `kubectl get appset` | Hub: `kubectl logs deploy/argocd-applicationset-controller` |
    | **2. App Controller** | `orders-processor` Helm chart + values | K8s manifests on Spoke | Hub: `argocd app get <app>` | Hub: `kubectl logs deploy/argocd-application-controller` |
    | **3. Kro Engine** | `QueueBackedService` CR on Spoke | K8s Deployment + ACK `Queue` CRs | Spoke: `kubectl get queuebackedservice -o yaml` | Spoke: `kubectl -n kro logs deploy/kro` |
    | **4. ACK SQS Controller** | ACK `Queue` CR on Spoke | AWS SQS Queue in Moto Cloud | Spoke: `kubectl get queue.sqs -o yaml` | Spoke: `kubectl -n ack-system logs deploy/sqs-chart` |

---

### Step 2.2: Add "Status & Health Primer" (`L-7`)
* **Files:** `docs/runbooks/devops-student-rebuild-guide.md`, `docs/runbooks/argocd-cli.md`
* **Problem:** In Argo CD 3.x, custom health check results for CRDs (`QueueBackedService`, ACK `Cluster`, `VPC`) are not written to `.status.resources[].health` in Application JSON. Learners and validators mistakenly conclude health checks are broken.
* **Content to Add:**
  * Explain the fundamental difference between **Sync** and **Health**:
    * `Sync Status (Synced / OutOfSync)`: Measures whether the live Kubernetes resource spec matches the Git-rendered spec.
    * `Health Status (Healthy / Progressing / Degraded)`: Measures runtime readiness based on health evaluation rules.
  * Explain **where health status lives in Argo CD 3.x**:
    * In Argo CD 3.x, per-resource health for CRDs is maintained in memory and displayed in the **UI** and in `argocd app get <app> --output tree`.
    * It is **not** duplicated into the Application's `.status.resources` JSON block in etcd to reduce etcd payload bloat.
    * Show how to verify custom health checks properly:
      ```bash
      argocd app get orders-dev --output tree
      # Output proves custom health checks are active:
      # KIND/NAME                  STATUS  HEALTH
      # QueueBackedService/orders  Synced  Healthy
      # Queue/orders-dev-queue             Healthy
      ```

---

## 6. Track 3: Pedagogical Scaffolding & Active Learning Milestones (Priority P1)

### Step 3.1: Add "Predict–Observe–Explain" Checkpoints (`L-3`)
* **File:** `docs/runbooks/devops-student-rebuild-guide.md`
* **Content to Add:** Insert structured learning checkpoints at each rebuild step:
  * **Step 2 (Setup) Checkpoint:**
    * *Objective:* Understand multi-cluster topology and ingress routing.
    * *Predict:* What happens to ports 80 and 443 on the host? Will the two spoke clusters expose any web ports?
    * *Observe:* Inspect `docker ps` and Traefik load balancer bindings.
    * *Explain:* Why is Argo CD installed only on the hub while Kro and ACK run on spokes?
  * **Step 3 (Bootstrap) Checkpoint:**
    * *Objective:* Understand the App-of-Apps and ApplicationSet discovery pattern.
    * *Predict:* When `root-control-plane` is applied, how does Argo CD know about the other 41 applications?
    * *Observe:* Watch `kubectl -n argocd get applications -w`.
    * *Explain:* What role do ApplicationSets play compared to standalone Application manifests?
  * **Step 4 (Post-Bootstrap) Checkpoint:**
    * *Objective:* Understand initialization hooks and secrets outside Git.
    * *Predict:* Why is `argo-cd` set to manual sync by default? What happens if it auto-syncs immediately?
    * *Observe:* Verify IAM worker credentials created in Moto and token expiration alert status.

---

### Step 3.2: Promote Drills to Core Tutorial Milestones (`L-3`)
* **Files:** `docs/developer-tutorial.md`, `docs/runbooks/devops-student-rebuild-guide.md`
* **Content to Add:**
  * Incorporate **Drill 4 (Out-of-Band Cloud Drift)** as an explicit exercise in the developer tutorial:
    1. *Action:* The student uses AWS CLI to delete `orders-dev-queue` in Moto.
    2. *Predict:* Will Argo CD show `OutOfSync`? (No, Git and Kubernetes are unchanged).
    3. *Observe:* Watch ACK SQS controller logs. Observe the queue reappear within 150 seconds.
    4. *Takeaway:* Controllers continuously reconcile against real-world state, not just Git commits.
  * Incorporate **Drill 1 (Cloud Loss & Worker Key Recovery)** into the post-rebuild verification section.

---

### Step 3.3: Refresh Learner Architecture Views (`L-8`)
* **Files:** `docs/runbooks/devops-student-rebuild-guide.md` (§1), `docs/lab-progression-and-next-steps.md`
* **Problem:** Architecture diagrams show only ACK SQS, omitting ACK EC2/IAM/EKS controllers, tier-1 `platform-network`, Keycloak, Kyverno, and tenant IaC.
* **Content to Add:**
  * Update Mermaid diagrams in `devops-student-rebuild-guide.md` to display:
    * Hub: Argo CD, Keycloak SSO, Traefik, Prometheus, Loki, Alloy.
    * Spokes: Kro Engine, ACK SQS Controller, ACK EC2 Controller (VPC/Subnets), ACK IAM Controller, ACK EKS Controller, Kyverno Admission Controller, Traefik Ingress.
    * Moto Cloud: Central emulation partitioned by CARM accounts `111111111111` (nonprod) and `222222222222` (prod).
  * Update `lab-progression-and-next-steps.md` to reflect that SSO, Kyverno, Platform Network, and Tenant IaC are fully delivered.

---

## 7. Track 4: Conceptual Transfer, Lifecycle Matrices & Promotion Reality (Priority P2)

### Step 4.1: Unified Lifecycle & Deletion Comparison Matrix (`L-4`)
* **Files:** `docs/runbooks/devops-student-rebuild-guide.md` (or new `docs/concepts/lifecycle-and-garbage-collection.md`)
* **Content to Add:** A comprehensive comparative matrix clarifying deletion behaviors:
  | Action | What Triggers It | Kubernetes Objects Impacted | Cloud Resources Impacted | Reversal / Recovery Path |
  |---|---|---|---|---|
  | **Delete Git File** | `git rm` + push | Argo CD Application pruned; cascade deletion initiated on spoke | ACK triggers cloud deletion (dev) or cloud retention (prod) | Re-commit file to Git |
  | **K8s `ownerReferences` Cascade** | Deleting parent CR (`QueueBackedService`) | Child Deployment, Service, and ACK `Queue` CRs deleted automatically by K8s GC | ACK receives deletion event for `Queue` CR | Re-apply parent CR |
  | **Kro Finalizer (`kro.run/finalizer`)** | Deletion request on Kro parent CR | Blocks parent deletion until children are deleted in strict reverse-topological order | Prevents orphaned child CRs | Controller must be running to process finalizer |
  | **Cloud Deletion Policy (`delete` vs `retain`)** | ACK `Queue` or `Cluster` CR deletion | Kubernetes CR is removed from cluster | If `delete`: Moto/AWS terminates cloud resource.<br>If `retain`: Cloud resource remains running in AWS. | If retained, requires `adopt-or-create` annotation to re-link |

---

### Step 4.2: Production Promotion Correction & Canary Demarcation (`L-5`)
* **File:** `docs/production-promotion-guardrails.md`
* **Problem:** States that disabling automated sync for production is the "Current Setup", which contradicts the running lab (`orders-prod` uses automated sync with immutable SHA pinning).
* **Fix:**
  1. Update Section 4 ("Summary Recommendation"):
     ```markdown
     ### Current Lab Setup (Immutable Git Revision Pinning)
     * Production applications operate with automated sync (`automated: {prune: true, selfHeal: true}`).
     * Production safety is enforced at the Git boundary: `valuesRevision` must pin a reviewed, 40-character commit SHA.
     * Developers cannot alter production workloads by pushing to `main` in `orders-processor`; promotion requires an approved pull request in `tenant-workloads` updating `valuesRevision`.
     ```
  2. Add an explicit comparison note:
     > **Git Revision Promotion vs Progressive Delivery (Canary/Rollouts):**  
     > The lab implements *declarative environment promotion*: transitioning an immutable release artifact across environments via Git PRs. It does *not* currently implement traffic-weighted canary rollouts or automated rollbacks (e.g. Argo Rollouts / Flagger). Progressive canary delivery remains a future roadmap track.

---

### Step 4.3: Tenant IaC Learner Guide (`L-8`)
* **File:** `docs/runbooks/tenant-iac-operations.md`
* **Content to Add:** Add a conceptual enablement intro explaining:
  * **Two-Tier Platform Infrastructure:** Tier-1 platform infrastructure (`platform-network` VPC, subnets, IGW, security groups) is owned by platform administrators and shared. Tier-2 team infrastructure (`TeamEKSCluster`) is owned by application teams and references tier-1 via Kro `externalRef`.
  * **Simulation Fidelity Limits:** Re-emphasize why ACK EKS in Moto remains `ACK.ResourceSynced=False` (due to unpopulated late-initialization fields) and why the lab considers `ACTIVE` sufficient for declarative composition validation.

---

### Step 4.4: Enterprise GitOps Glossary (`L-3`, `L-4`)
* **File:** `docs/runbooks/devops-student-rebuild-guide.md`
* **Content to Add:** A glossary defining:
  * `Desired State` vs `Observed State` vs `Live State`.
  * `Reconciliation Loop` (Watch Event vs Periodic Resync).
  * `Synced` vs `OutOfSync` vs `Healthy` vs `Degraded` vs `Progressing`.
  * `ApplicationSet` vs `Application` vs `AppProject`.
  * `CARM` (Cross-Account Resource Management).
  * `ValidatingAdmissionPolicy` (In-tree CEL) vs `ValidatingWebhookConfiguration` (Kyverno).

---

## 8. Track 5: Verification, Validation & Acceptance Criteria

### Step 5.1: Automated CI & Smoke Test Quality Gates
All repository test suites must pass without errors:
1. `make test-alert-rules`: All 22 Promtool alert rule unit tests pass (`SUCCESS`).
2. `make ci`: All 42 Applications render offline, 585 resources pass kubeconform, 36 shell scripts ShellCheck clean, secret scan clean.
3. `make ci-iac`: Tenant IaC claim validation and fixture tests (2 positive, 14 negative) pass.
4. `make orphans`: Zero orphaned credentials or namespaces.
5. `bash scripts/push-all.sh --dry-run`: 6/6 repositories validated.
6. `bash scripts/smoke-test-hub-spoke.sh`: 12/12 stages pass against live lab.
7. `bash scripts/smoke-test-hub-spoke-bats.sh`: 27/27 Bats tests pass in < 60s.

### Step 5.2: Empirical Copy-Paste Documentation Verification
Create a test script (`tests/test_doc_examples.sh` or Python fixture) that executes every learner-facing code block:
1. Validate `tenant-iac-operations.md` dev claim against `schema/cluster.schema.json` &rarr; Must exit 0.
2. Execute the `developer-tutorial.md` nonprod SQS message publishing snippet &rarr; Must resolve `http://localhost:5000/111111111111/orders-dev-queue` and publish message successfully.
3. Verify that zero documentation files contain the string "32 Applications".

### Step 5.3: Reporting & Peer Review Sign-Off
1. The implementer records complete execution evidence in `docs/remediation/2026-10-06-lab-learning-assessment/2026-10-06-lab-learning-remediation-plan-implemented-01.md`.
2. An independent validator audits the results and authors `docs/remediation/2026-10-06-lab-learning-assessment/2026-10-06-lab-learning-remediation-plan-validation-01.md`.
3. Following acceptance, the educational effectiveness score in `docs/assessments/2026-10-06-lab-learning-assessment.md` is re-evaluated with an expected target of **8.0+ / 10**.
