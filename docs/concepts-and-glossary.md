# Concepts, Glossary & Self-Check

> **Status: Current.** Learner reference for the lab (2026-10-06, learning remediation Track 4). Every behaviour described here was checked on the running lab; where something was not tested, it says so.

**Read with:** [student guide](runbooks/devops-student-rebuild-guide.md) (rebuild, *One change, four reconcilers*, *Synced vs Healthy*, Drill 4 milestone), [developer tutorial](developer-tutorial.md), [tenant IaC runbook](runbooks/tenant-iac-operations.md).

---

## 1. Glossary

| Term | Meaning in this lab |
|---|---|
| **Desired state** | What Git says should exist: registrations in `tenant-workloads`/`tenant-iac`, values in `orders-processor`, platform config in `gitops-control-plane`/`platform-catalog`/`platform-charts` |
| **Live state** | The objects that actually exist in a cluster now (`kubectl get …`) |
| **Observed status** | What a *controller* reports about an object (`.status`): written by the controller, never by Git. For example, an ACK `Queue`'s `status.queueURL`, or a kro instance's `status.state: ACTIVE` |
| **Controller / reconciler** | A loop that compares desired with live state and acts to close the gap. Here: Argo CD's ApplicationSet and application controllers, kro, the ACK controllers, plus the built-in Kubernetes controllers |
| **Watch event vs resync** | Controllers react to *changes of Kubernetes objects* immediately (watch). External state such as a cloud resource is only re-read on a schedule (resync): every 300 s for the lab's ACK controllers. That is why cloud drift heals in seconds to minutes (Drill 4) |
| **Drift** | Live or cloud state that no longer matches desired state. Argo CD detects drift between Git and Kubernetes (`OutOfSync`, fixed by self-heal); ACK detects drift between Kubernetes and the cloud |
| **`Synced` / `OutOfSync`** | Argo CD sync status: do the live objects equal what Git renders? |
| **`Healthy` / `Progressing` / `Degraded` / `Missing`** | Argo CD health: is the object *working*, according to a health check. Built-in for core kinds; for kro and ACK kinds the lab defines Lua checks in `clusters/values-argocd-hub.yaml`. Shown in the UI and `argocd app get <app> --output tree`, not in the Application's `status.resources` |
| **`Ready` (kro)** | kro's condition on an instance (`QueueBackedService`, `TeamEKSCluster`): every child exists and each child's `readyWhen` holds |
| **`ACK.ResourceSynced`** | ACK's condition: the cloud resource matches the Kubernetes object. The moto EKS `Cluster` never reaches `True` (moto lacks fields ACK waits for), so team-cluster readiness uses `status.status == ACTIVE` instead |
| **Application** | Argo CD object: *deploy this source (repo/chart + revision) to that cluster and namespace* |
| **ApplicationSet** | A template plus a generator that produces Applications: the *cluster* generator makes one per registered spoke, the *Git files* generator one per registration file |
| **AppProject** | Argo CD's boundary for Applications: allowed source repositories, destinations and kinds (`tenant-workloads`, `tenant-iac`, `platform-addons`, …) |
| **App of apps** | `bootstrap/root-app.yaml` (`root-control-plane`) points at `applicationsets/`; everything else follows from Git |
| **Helm render** | Argo CD turns a chart plus a values file into Kubernetes objects. The chart maps values to fields (e.g. `retentionPeriod` → `messageRetentionPeriod`) |
| **CRD / custom resource** | A Kubernetes API extension (`QueueBackedService`, `Queue`, `VPC`, …) and an object of that type |
| **ResourceGraphDefinition (RGD)** | A kro blueprint: a schema for a new kind plus the graph of child objects it creates, with CEL expressions, `includeWhen` (conditional children), `readyWhen` (readiness gates) and `externalRef` (read an object kro does not own, such as the platform network) |
| **ACK service controller** | One controller per AWS service (SQS, EC2, IAM, EKS) that turns Kubernetes objects into AWS API calls |
| **CARM** | ACK cross-account resource management: the namespace annotation `services.k8s.aws/owner-account-id` decides which AWS account a resource lands in (`111111111111` nonprod, `222222222222` prod) |
| **Finalizer** | A marker that blocks the deletion of an object until its owner has cleaned up: `resources-finalizer.argocd.argoproj.io` (Argo CD), `kro.run/finalizer` (kro), `finalizers.sqs.services.k8s.aws/Queue` (ACK) |
| **ownerReferences** | Parent link on a child object; Kubernetes garbage collection deletes children whose owner is gone. kro sets them on its children (`controller: true`, `blockOwnerDeletion: true`) |
| **`deletion-policy` (ACK)** | `delete`: deleting the Kubernetes object deletes the cloud resource. `retain`: the cloud resource stays. The lab uses `retain` for prod |
| **`adopt-or-create` (ACK)** | Adopt an existing cloud resource by name if it exists, otherwise create it. Used for prod team clusters, so a retained cluster is picked up again when its claim returns |
| **Pod Security Admission** | Built-in admission check of pod security settings per namespace label (`restricted` on tenant namespaces) |
| **ValidatingAdmissionPolicy (VAP)** | Built-in admission rule written in CEL, evaluated in the API server (registry allowlist; the `QueueBackedService` and `TeamEKSCluster` contracts) |
| **Kyverno** | Admission controller running as a webhook; here it verifies image signatures (`tenant-images-signed`) |
| **Configuration promotion** | Moving a reviewed, immutable configuration to the next environment: prod's `valuesRevision` pins a full commit SHA through a pull request in `tenant-workloads` |
| **Progressive delivery** | Shifting *traffic* gradually to a new version within one environment (canary, blue/green, automated analysis and rollback). **Not implemented in this lab** (roadmap Track 2) |

---

## 2. What deletes what: Git, Kubernetes and the cloud

Three different events, three different owners. The chain below was verified on `orders-dev` (2026-10-06).

| You do this | What happens next | Kubernetes objects | Cloud resources |
|---|---|---|---|
| **Delete the registration file** (`tenant-workloads/tenants/tenant-a/apps/orders-dev.yaml`) and merge | The ApplicationSet no longer generates `orders-dev` and deletes the Application. Its finalizer `resources-finalizer.argocd.argoproj.io` makes Argo CD delete what it deployed (the `QueueBackedService`) | `kro.run/finalizer` holds the instance until kro has deleted its children: Deployment, Service, Ingress, ConfigMap, NetworkPolicies, `Queue` objects. Their `ownerReferences` are the garbage-collection backstop | Each `Queue` carries `finalizers.sqs.services.k8s.aws/Queue`: ACK deletes the SQS queue (`deletion-policy: delete`, dev/test) **or leaves it in place** (`retain`, prod), then lets the object go |
| **Delete a Kubernetes object by hand** | Depends on **who owns it**. A kro child (e.g. `configmap/orders-dev-config`): kro gets a *watch event* and recreates it within about **1 s**; Argo CD never notices, because it only tracks the `QueueBackedService` it deployed (verified 2026-10-06: `Synced/Healthy` throughout). An object Argo CD deployed itself (e.g. the `QueueBackedService`): the Application turns `OutOfSync` and self-heal re-applies it from Git | recreated (by its owner) | none |
| **Delete the cloud resource directly** (moto, AWS console) | Nothing in Git or Kubernetes changes. Argo CD stays `Synced/Healthy`. The ACK controller notices at its next resync (≤ 300 s) and recreates it ([Drill 4 milestone](runbooks/devops-student-rebuild-guide.md#6-milestone-watch-a-controller-heal-the-cloud-drill-4)) | unchanged | recreated |
| **Delete a retained prod resource's claim, then restore it** | prod `TeamEKSCluster`: the IAM roles, EKS cluster and node group stay in account 222…; restoring the claim adopts them again (`adopt-or-create`, verified in the tenant-IaC P0 spike). Prod SQS queues are retained too, but **re-creating a retained prod queue has not been tested** in this lab | recreated | kept, then adopted (team clusters) |

**Remember:** removing a file from Git is a request; Argo CD, kro and ACK each carry it out in their own layer. `retain` only protects the **cloud** side.

---

## 3. Lab shortcuts that must not reach production

| Lab | Why it is acceptable here | Production |
|---|---|---|
| moto in memory, one container | A local, free emulation of AWS APIs; restarts lose everything (`make moto-restart` recovers) | Real AWS accounts; state is durable |
| moto EKS `ACTIVE` = "ready" | Proves the declarative chain, account isolation and guardrails, not a usable cluster (no API server, nodes or CNI) | Readiness includes a reachable endpoint, joined nodes, add-ons, access entries |
| One IAM role name for all ACK controllers per account (`ack-sqs-controller`, residual R-1) | moto does not check it | One least-privilege role per controller (`ServiceLevelCARM`) |
| `allow_unsafe_aws_endpoint_urls`, mock keys in a Secret | Points ACK at moto | IRSA / Pod Identity, no static keys |
| Single-user repositories: PRs with 0 approvals | GitHub forbids approving your own PR | Required reviews and CODEOWNERS approval |
| Local plain HTTP behind `*.localhost`, mkcert certificate | Workstation only | Public TLS, real DNS |

---

## 4. Self-check questions

Answer before opening the hint. If you cannot, revisit the linked section.

1. **The reconciler trace.** You set `replicas: 3` in `orders-processor/deploy/values-dev.yaml` and push. Which components act before the third pod runs, and where do you check each one?
   <details><summary>Answer</summary>The Argo CD application controller notices the new values commit, renders the chart and updates the <code>QueueBackedService</code> (Application <code>Synced</code>); kro updates the Deployment (instance <code>Ready</code>); the Deployment and ReplicaSet controllers start the pod (<code>readyReplicas</code>). The ApplicationSet controller and ACK have nothing to do. See <a href="runbooks/devops-student-rebuild-guide.md#one-change-four-reconcilers">One change, four reconcilers</a>.</details>
2. **Synced but Degraded.** How can an Application be `Synced` and `Degraded` at the same time?
   <details><summary>Answer</summary>Sync compares live objects with Git; health judges whether they work. Git was applied exactly, but what it describes is failing (e.g. a crash-looping pod). For kro and ACK kinds, health exists only because the lab defines Lua checks; read it in the tree view, not in <code>status.resources</code>.</details>
3. **Cloud drift.** Someone deletes `orders-dev-dlq` directly in moto. Who notices, and when?
   <details><summary>Answer</summary>Not Argo CD: no Kubernetes object changed, so it stays <code>Synced/Healthy</code>. The ACK SQS controller re-reads the queue on its next resync (≤ 300 s; observed 11–150 s) and recreates it.</details>
4. **Composition vs cloud control.** If the ACK SQS controller is down, what happens to a new `QueueBackedService`?
   <details><summary>Answer</summary>kro evaluates resource dependencies in its ResourceGraphDefinition DAG. kro creates the Deployment and the DLQ ACK <code>Queue</code> CR (which has no status dependencies), but because ACK is down, the DLQ is never reconciled and <code>dlq.status.ackResourceMetadata.arn</code> is not populated. kro treats unresolved status references as unmet dependencies and <b>waits</b>: it does <i>not</i> create the main <code>Queue</code> CR (whose <code>redrivePolicy</code> requires the DLQ's ARN) nor the <code>ConfigMap</code> (which requires both queue URLs and ARNs). The worker pods fail or stay unready waiting for the missing ConfigMap, and the <code>QueueBackedService</code> stays <code>IN_PROGRESS</code> (<code>Ready: False</code>). Argo CD shows the Application <code>Synced</code> (Git matches live); its health reflects the custom Lua checks (<code>Progressing</code> or <code>Degraded</code>). On Prometheus, the <code>SpokeControllerDown</code> alert fires after the controller has been down for 5 minutes (<code>for: 5m</code>).</details>
5. **Deletion cascade.** You delete `orders-dev.yaml` from `tenant-workloads`. What happens layer by layer, and how would `retain` change it?
   <details><summary>Answer</summary>See §2: Application deleted → Argo CD deletes the instance → kro deletes its children → ACK deletes the queues (dev, <code>delete</code>). With <code>retain</code> (prod), the Kubernetes objects go and the queues stay.</details>
6. **GitOps exceptions.** Name state that is deliberately not in Git, and why.
   <details><summary>Answer</summary>Passwords and cluster tokens (<code>~/.config/gitops-lab</code>, mode 600), the workers' IAM keys (Kubernetes Secrets created by <code>post-bootstrap</code>), the TLS key, moto's in-memory state. Secrets in Git leak; cloud state is observed, not declared.</details>
7. **Admission layering.** An `nginx:latest` pod is created in `orders-dev`. Which layer rejects it first?
   <details><summary>Answer</summary>Tested on the lab: <b>Pod Security</b> <code>restricted</code> first (no compliant <code>securityContext</code>). With a compliant one, the <b>VAP</b> registry allowlist (only <code>ghcr.io/brunobml/</code>). An allowed-registry but unsigned image (<code>orders-processor:v1.2.0</code>) is rejected by <b>Kyverno</b>. Created through a Deployment, the rejection appears on the ReplicaSet's events, not on <code>kubectl apply</code>.</details>
8. **The simulation gap.** A `TeamEKSCluster` is `Ready` and `TeamClusterNotReady` is silent. Can the team run `kubectl` against it?
   <details><summary>Answer</summary>No. moto stores an <code>ACTIVE</code> record with a fake endpoint: no control plane, nodes or network. <code>Ready</code> proves the declarative chain, the accounts and the guardrails (§3).</details>
