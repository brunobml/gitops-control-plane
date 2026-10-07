# Lab 1: Write a Blueprint (about 60 minutes)

> **Status: Current (2026-10-07).** In [Lab 0](lab-0-guided-tour.md) you watched the platform's blueprint, `QueueBackedService`, turn one object into nine. Now you write your own, in a **disposable sandbox cluster**, never on the shared lab (guardrail G-2: blueprints add cluster-scoped CRDs and ClusterRoles). Every result and error message below is copied from a real run on 2026-10-07. `make test-lab1` replays the whole lab, including every expected failure, against the [reference solution](lab-1-solution/). Plan: [learner on-ramp, Track B](remediation/2026-10-06-lab-learning-assessment/2026-10-07-learner-on-ramp-plan.md).

**You need:** Lab 0 (or the [concepts page](concepts-and-glossary.md) on kro), Docker, `k3d`, `kubectl`, `helm`, and for step 6 `aws`. **You will build** `WebGreeting`: a small web page whose text, replica count and exposure are chosen by whoever creates the instance.

| Step | You do | You learn |
|---|---|---|
| 0 | start the sandbox | the platform's kro (same chart and values as the spokes) |
| 1 | a ConfigMap + Deployment blueprint; **watch it fail**, then grant kro permission | RGD → CRD → instance; least-privilege kro (aggregated RBAC) |
| 2 | pass the ConfigMap's name into the Deployment | references create dependencies; kro orders by them |
| 3 | an optional Service (`includeWhen`) | conditional children, like the platform's PDB |
| 4 | `readyWhen` and a `status` field | when an instance is "Ready" |
| 5 | **break it on purpose** twice | compile-time CEL checks; why the platform validates with a ValidatingAdmissionPolicy (incident D-14) |
| 6 | *stretch:* a cloud queue (ACK + moto) | kro waits for another controller's status |

Work in an empty directory. Each step: *predict*, run, compare with **Measured**, then open *Explain*.

---

## Step 0: Start the sandbox (2 min)

<!-- doc-test: covered by="check:test-lab1" -->
```bash
make -C ~/repos/gitops-control-plane sandbox-up WITH_MOTO=1     # WITH_MOTO=1 only for step 6; about 40 s
kubectl --context k3d-learn-sandbox get pods -A
```

**Measured:** ready in 38 s: one k3d cluster `learn-sandbox` (API `127.0.0.1:6560`), kro 0.9.4 in namespace `kro`, the ACK SQS controller and `moto-sandbox` on `127.0.0.1:5002`. Your current kube context is **not** switched; always pass `--context k3d-learn-sandbox`. kro runs exactly as on the spokes: the chart version from `applicationsets/addons-spoke.yaml`, the values from `platform-catalog/controllers/kro/values-kro.yaml`, including `rbac.mode: aggregation`.

Create the namespace for your instances, with the same Pod Security level as tenant namespaces:

<!-- doc-test: covered by="check:test-lab1" -->
```bash
kubectl --context k3d-learn-sandbox create namespace lab1
kubectl --context k3d-learn-sandbox label namespace lab1 pod-security.kubernetes.io/enforce=restricted
```

---

## Step 1: A blueprint, and the permission it needs (15 min)

A *ResourceGraphDefinition* (RGD) has a **schema** (the API your users get) and **resources** (templates with `${…}` CEL expressions). Save this as `rgd.yaml`:

<!-- lab1-file: step1-rgd -->
```yaml
apiVersion: kro.run/v1alpha1
kind: ResourceGraphDefinition
metadata:
  name: web-greeting
spec:
  schema:
    apiVersion: v1alpha1
    kind: WebGreeting
    spec:
      message: string | default="hello from kro"
      replicas: integer | default=1
  resources:
    - id: deployment
      template:
        apiVersion: apps/v1
        kind: Deployment
        metadata:
          name: ${schema.metadata.name}
        spec:
          replicas: ${schema.spec.replicas}
          selector:
            matchLabels: {app: "${schema.metadata.name}"}
          template:
            metadata:
              labels: {app: "${schema.metadata.name}"}
            spec:
              securityContext:
                runAsNonRoot: true
                runAsUser: 65534
                seccompProfile: {type: RuntimeDefault}
              containers:
                - name: web
                  image: busybox:1.37@sha256:bdf57e528e45e4433820e045b29b4597825a1c9e38353532d90a01445013f82e
                  command: ["httpd", "-f", "-p", "8000", "-h", "/www"]
                  ports: [{containerPort: 8000}]
                  securityContext:
                    allowPrivilegeEscalation: false
                    capabilities: {drop: ["ALL"]}
                  volumeMounts: [{name: page, mountPath: /www}]
              volumes:
                - name: page
                  configMap: {name: "${schema.metadata.name}-page"}
    - id: config
      template:
        apiVersion: v1
        kind: ConfigMap
        metadata:
          name: ${schema.metadata.name}-page
        data:
          index.html: ${schema.spec.message}
```

And an instance, `instance.yaml`:

<!-- lab1-file: step1-instance -->
```yaml
apiVersion: kro.run/v1alpha1
kind: WebGreeting
metadata:
  name: hello
  namespace: lab1
spec:
  message: "hello from my first blueprint"
```

**Predict:** the instance is applied a few seconds after the RGD. What appears in `lab1`?

<!-- doc-test: covered by="check:test-lab1" -->
```bash
kubectl --context k3d-learn-sandbox apply -f rgd.yaml
kubectl --context k3d-learn-sandbox get crd webgreetings.kro.run      # kro created a new API for you
kubectl --context k3d-learn-sandbox apply -f instance.yaml
kubectl --context k3d-learn-sandbox get rgd web-greeting               # repeat for about a minute
kubectl --context k3d-learn-sandbox get rgd web-greeting \
  -o jsonpath='{range .status.conditions[*]}{.type}={.status} {.message}{"\n"}{end}'
kubectl --context k3d-learn-sandbox -n lab1 get webgreeting,configmap,deployment
```

**Measured:** the CRD `webgreetings.kro.run` existed within 3 s. (Applying the instance *before* that fails with `no matches for kind "WebGreeting"`: wait for the CRD.) The RGD then stayed `Inactive`. About 30 s later it showed:

```text
ControllerReady=False add parent handler kro.run/v1alpha1, Resource=webgreetings: cache sync timeout for kro.run/v1alpha1, Resource=webgreetings
```

The instance had no status, and no ConfigMap or Deployment appeared. kro's log said why:

<!-- doc-test: covered by="check:test-lab1" -->
```bash
kubectl --context k3d-learn-sandbox -n kro logs deploy/kro --since=5m | grep forbidden | tail -2
```

```text
webgreetings.kro.run is forbidden: User "system:serviceaccount:kro:kro" cannot list resource "webgreetings" in API group "kro.run" at the cluster scope
```

kro on this platform may manage **only the kinds a ClusterRole grants it**. Grant the new instance kind first, and nothing else yet, as `rbac.yaml`:

<!-- lab1-file: step1-rbac-instance -->
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: kro-web-greeting
  labels:
    rbac.kro.run/aggregate-to-controller: "true"
rules:
  - apiGroups: ["kro.run"]
    resources: ["webgreetings", "webgreetings/status", "webgreetings/finalizers"]
    verbs: ["*"]
```

<!-- doc-test: covered by="check:test-lab1" -->
```bash
kubectl --context k3d-learn-sandbox apply -f rbac.yaml
kubectl --context k3d-learn-sandbox -n lab1 get webgreeting hello \
  -o jsonpath='{.status.state}{"\n"}{.status.conditions[?(@.type=="Ready")].message}{"\n"}'   # after about 30 s
```

**Measured:** the RGD became `Active` within 10 s; the instance went to `ERROR`:

```text
resource reconciliation failed: deployments.apps "hello" is forbidden: User "system:serviceaccount:kro:kro" cannot get resource "deployments" in API group "apps" in the namespace "lab1"
```

Add the children's kinds to the same ClusterRole and apply it again:

<!-- lab1-file: step1-rbac-children -->
```yaml
  - apiGroups: [""]
    resources: ["configmaps"]
    verbs: ["*"]
  - apiGroups: ["apps"]
    resources: ["deployments"]
    verbs: ["*"]
```

<!-- doc-test: covered by="check:test-lab1" -->
```bash
kubectl --context k3d-learn-sandbox apply -f rbac.yaml
kubectl --context k3d-learn-sandbox -n lab1 get webgreeting,configmap,deployment
kubectl --context k3d-learn-sandbox -n lab1 rollout status deployment/hello
kubectl --context k3d-learn-sandbox -n lab1 exec deploy/hello -- wget -qO- localhost:8000
```

**Measured:** `hello` was `ACTIVE`, `READY True` 7 s later, with `configmap/hello-page` and `deployment.apps/hello` (1/1). The page answered `hello from my first blueprint`. Note the `rollout status`: in one run, `exec` right after `READY True` failed with `container not found ("web")`, because the instance said Ready before its pod ran. Step 4 fixes exactly that.

<details><summary>Explain</summary>

Applying an RGD makes kro **generate a CRD** (your `WebGreeting` API) and start a controller for it. The lab runs kro with `rbac.mode: aggregation`: its service account starts with only a static role for kro's own types. Every blueprint ships a ClusterRole labelled `rbac.kro.run/aggregate-to-controller: "true"`, and Kubernetes merges it into kro's role. The platform's real one is `platform-catalog/blueprints/kro-rbac-queue-backed-service.yaml`. The failure has two layers: without the instance kind, kro cannot even *watch* `webgreetings` (`ControllerReady=False`); without the child kinds, it can watch but not create (`forbidden` on the instance). This is least privilege. A blueprint cannot make kro create kinds that nobody reviewed, such as a ClusterRoleBinding. It is also why blueprints are written here and not on the shared spokes.
</details>

---

## Step 2: Let one child depend on another (10 min)

**Question:** kro created both children. In which order? Read the order kro computed:

<!-- doc-test: covered by="check:test-lab1" -->
```bash
kubectl --context k3d-learn-sandbox get rgd web-greeting -o jsonpath='{.status.topologicalOrder}{"\n"}'
```

**Measured:** `["deployment","config"]`, the order in which you declared them. Now make the Deployment **use** the ConfigMap's name instead of repeating the naming rule. In `rgd.yaml`, change the volume:

```yaml
                  configMap: {name: "${config.metadata.name}"}
```

Apply `rgd.yaml` again and read the order once more.

**Measured:** `["config","deployment"]`. The instance stayed `ACTIVE`, and kro recorded a new graph revision (`kubectl get graphrevisions.internal.kro.run`).

<details><summary>Explain</summary>

A reference to another resource's field (`config.metadata.name`) is an **edge** in kro's dependency graph (a DAG). kro creates `config` first, because the Deployment's template cannot be rendered until the value exists. The platform's `QueueBackedService` relies on the same mechanism: its ConfigMap waits for the queues' `status.queueURL`, which only ACK can fill in. That is why, with ACK down, kro creates the dead-letter queue but **waits** with everything that needs its ARN ([concepts, question 4](concepts-and-glossary.md#4-self-check-questions)). Declaration order is only a tie-breaker.
</details>

---

## Step 3: An optional child (10 min)

Add a boolean to the schema and a Service that exists **only when it is true**:

```yaml
      expose: boolean | default=false          # under spec.schema.spec
```

```yaml
    - id: service                              # under spec.resources
      includeWhen:
        - ${schema.spec.expose}
      template:
        apiVersion: v1
        kind: Service
        metadata:
          name: ${schema.metadata.name}
        spec:
          selector: {app: "${schema.metadata.name}"}
          ports: [{port: 80, targetPort: 8000}]
```

Apply `rgd.yaml`, then a second instance with `expose: true` and `replicas: 2` (named `hello-public`, message `hello, world`; see [`instances.yaml`](lab-1-solution/instances.yaml)).

If the instance is rejected with `strict decoding error: unknown field "spec.expose"` (seen in one test run), kro has not yet updated the CRD; the RGD can already say `Active`. Wait a few seconds and apply again.

**Predict:** what happens to `hello-public`? (Hint: step 1.)

**Measured:** `hello-public` had **no status at all**, and no children appeared. kro's log repeated `services is forbidden: … cannot list resource "services"`. After `services` was added to the ClusterRole next to `configmaps` ([solution](lab-1-solution/rbac.yaml)), `hello-public` was `ACTIVE` 9 s later, with 2/2 pods and `service/hello-public`, which answered `hello, world`. `hello` got no Service. Toggling `expose` on `hello` with `kubectl patch` created, then deleted, `service/hello` within a second each time.

<details><summary>Explain</summary>

`includeWhen` decides per instance whether a resource is part of the graph. When the value turns false, kro **deletes** the child, because it is no longer desired. The platform uses this for the PodDisruptionBudget: `includeWhen: ${schema.spec.replicas > 1}` in `queue-backed-service-rgd.yaml`, so prod gets a PDB and dev does not. This was Lab 0's optional Git step. The failure mode is worth remembering. When kro lacks permission for a kind the graph *might* contain, it cannot start watching it, and instances can sit **without any status**. Always check the kro log.
</details>

---

## Step 4: When is an instance Ready? (5 min)

Add a `status` field and a readiness rule:

```yaml
    status:                                    # under spec.schema, next to spec
      availableReplicas: ${deployment.status.availableReplicas}
```

```yaml
    - id: deployment
      readyWhen:
        - ${has(deployment.status.availableReplicas) && deployment.status.availableReplicas == deployment.spec.replicas}
```

Apply, then scale through the instance, not the Deployment (Lab 0, station 5):

<!-- doc-test: covered by="check:test-lab1" -->
```bash
kubectl --context k3d-learn-sandbox -n lab1 patch webgreeting hello --type merge -p '{"spec":{"replicas":3}}'
kubectl --context k3d-learn-sandbox -n lab1 get webgreeting hello -w \
  -o custom-columns='STATE:.status.state,AVAILABLE:.status.availableReplicas'          # Ctrl-C after it settles
```

**Measured:** `ACTIVE`/`Ready=True`/`available=1` → after 1 s `IN_PROGRESS`/`Ready=False` → after 3 s `ACTIVE`/`Ready=True`/`available=3`.

<details><summary>Explain</summary>

`status` fields copy facts from children into the instance, where users (and Argo CD's health check) read them. The platform publishes `queueURL` and `serviceURL` this way. `readyWhen` makes a child count as ready only when your condition holds, and the instance is Ready only when all its children are. The `has(…)` guard matters: right after creation, `availableReplicas` does not exist yet. The team-cluster blueprint uses `readyWhen` to stay *not Ready* while ACK reports a terminal error.
</details>

---

## Step 5: Break it on purpose (10 min)

**(a) A typo in a reference.** In `rgd.yaml`, change `${config.metadata.name}` to `${config.metadata.nmae}`, apply, and read the RGD's conditions (step 1's command).

**Measured:** the RGD became `Inactive` at once:

```text
GraphAccepted=False failed to validate resource "deployment": failed to compile template expression "config.metadata.nmae" at path "spec.template.spec.volumes[0].configMap.name": ERROR: <input>:1:16: undefined field 'nmae'
```

Both instances stayed `ACTIVE` on the last good revision. Fix the typo and apply: `Active` again within 3 s.

**(b) A rule on an existing field.** You want at most 5 replicas. The obvious way is a schema marker: `replicas: integer | default=1 minimum=1 maximum=5`. Apply it.

**Measured:**

```text
KindReady=False cannot update CRD webgreetings.kro.run: breaking changes detected: Minimum constraint 1 was added; Maximum constraint 5 was added
```

The CRD kept its old schema (`{"default":1,"type":"integer"}`). Remove the markers and apply again (`Active` within 2 s). Then enforce the rule the way the platform does, with [`policy.yaml`](lab-1-solution/policy.yaml), a ValidatingAdmissionPolicy:

<!-- doc-test: covered by="check:test-lab1" -->
```bash
kubectl --context k3d-learn-sandbox apply -f policy.yaml
kubectl --context k3d-learn-sandbox -n lab1 patch webgreeting hello --type merge -p '{"spec":{"replicas":9}}'
```

**Measured:**

```text
The webgreetings "hello" is invalid: : ValidatingAdmissionPolicy 'webgreeting-contract' with binding 'webgreeting-contract' denied request: spec.replicas must be between 1 and 5
```

<details><summary>Explain</summary>

(a) kro **type-checks** every CEL expression against the referenced resource's schema when you apply the RGD, not when an instance happens to hit it. A bad revision is rejected, and running instances keep the last good one. (b) Adding a constraint to a field that already exists could make stored instances invalid, so kro 0.9.4 refuses the CRD update. This happened to the platform on 2026-10-01 (**incident D-14**: the `QueueBackedService` RGD went `Inactive` on the nonprod spoke). The fix is in production today: the schema stays unconstrained, and `platform-catalog/blueprints/queue-backed-service-policy.yaml` enforces the contract at admission. It rejects bad input with a clear message and leaves kro's CRD untouched.
</details>

---

## Step 6 (stretch): A cloud resource (10 min, needs `WITH_MOTO=1`)

Add an ACK `Queue` and write its URL into the page's ConfigMap and the instance's status. kro also needs permission for `queues.sqs.services.k8s.aws` ([`rbac-queue.yaml`](lab-1-solution/rbac-queue.yaml)). The complete RGD is [`rgd-with-queue.yaml`](lab-1-solution/rgd-with-queue.yaml). Try writing it yourself first: the new child, one `data` key, one `status` field.

<!-- doc-test: covered by="check:test-lab1" -->
```bash
kubectl --context k3d-learn-sandbox -n lab1 get webgreeting -o custom-columns='NAME:.metadata.name,STATE:.status.state,QUEUE:.status.queueURL'
AWS_ACCESS_KEY_ID=mock-key AWS_SECRET_ACCESS_KEY=mock-secret \
  aws --endpoint-url=http://localhost:5002 --region us-east-1 sqs list-queues --query QueueUrls --output text
kubectl --context k3d-learn-sandbox -n lab1 delete webgreeting hello          # and list the queues again
```

**Measured:** `status.queueURL` was `http://moto-sandbox:5000/123456789012/lab1-hello-jobs` within 5 s, and the same URL was in `configmap/hello-page`. Deleting `hello` took 7 s: kro removed the Deployment, ConfigMap and `Queue` object, and ACK deleted the queue in moto.

<details><summary>Explain</summary>

The ConfigMap now depends on a field that **another controller** fills in: ACK writes `status.queueURL` after it has created the queue. kro waits for it, exactly as the platform's ConfigMap waits for the real queues. The sandbox's ACK has no CARM, so the queue lands in moto's default account `123456789012`. The lab maps each namespace to an account instead (Lab 0, station 4). Deletion runs the other way: kro deletes the children, and ACK's finalizer deletes the cloud resource. On the lab, prod uses `deletion-policy: retain` instead.
</details>

---

## Clean up

<!-- doc-test: covered by="check:test-lab1" -->
```bash
make -C ~/repos/gitops-control-plane sandbox-down
```

**Measured:** this removes the cluster, its kube context, the Docker network and `moto-sandbox`, and checks that nothing is left: `✔ sandbox removed (no cluster, container, network or kube context left)`.

## Check yourself

1. Why does kro on this platform need a ClusterRole per blueprint, and what would `rbac.mode: unrestricted` risk?
   <details><summary>Answer</summary>Aggregation limits kro to reviewed kinds. Unrestricted kro (<code>*/*</code>) would create whatever any RGD author writes, including RBAC objects, so writing a blueprint would effectively grant cluster-admin.</details>
2. Your instance has no status at all. What is your first command?
   <details><summary>Answer</summary>The kro log (<code>kubectl -n kro logs deploy/kro | grep forbidden</code>), then the RGD's conditions. A missing permission for a kind in the graph shows up there, not on the instance.</details>
3. Two children; B's template uses `${a.status.x}`. In what order are they created, and what if `x` never appears?
   <details><summary>Answer</summary>A first, then B, once <code>a.status.x</code> exists. If it never appears, kro waits and B is never created (the ACK-outage case of the platform).</details>
4. You need `replicas ≤ 5` on a blueprint that already has instances. How?
   <details><summary>Answer</summary>Not with schema markers (kro refuses: breaking change, D-14). Use a ValidatingAdmissionPolicy on the instance kind, versioned with the RGD.</details>

**Next:** the [developer tutorial](developer-tutorial.md) shows how a tenant uses the platform's blueprint through Git. The platform's blueprints live in `platform-catalog/blueprints/`; promoting one to the spokes is a platform change (`make promote-blueprints`), never a learner exercise on the shared lab.
