# Lab 1: Write a Blueprint (about 60 minutes)

> **Status: Current (2026-10-07).** In [Lab 0](lab-0-guided-tour.md) you watched the platform's blueprint, `QueueBackedService`, turn one object into nine. Now you write your own, in a **disposable sandbox cluster**, never on the shared lab (guardrail G-2: blueprints add cluster-scoped CRDs and ClusterRoles). Every result and error message below is copied from a real run. **Every command is a block you can copy and paste, in order**, including the ones that create and edit files. `make test-lab1` runs these same blocks, unchanged, and checks every expected result and failure. Plan: [learner on-ramp, Track B](remediation/2026-10-06-lab-learning-assessment/2026-10-07-learner-on-ramp-plan.md).

**You need:** Lab 0 (or the [concepts page](concepts-and-glossary.md) on kro), Docker, `k3d`, `kubectl` 1.31 or newer, `helm`, GNU `sed`, and for step 6 `aws`. The repositories are expected under `~/repos` (adjust the paths if yours differ). **You will build** `WebGreeting`: a small web page whose text, replica count and exposure are chosen by whoever creates the instance.

| Step | You do | You learn |
|---|---|---|
| 0 | start the sandbox | the platform's kro (same chart and values as the spokes) |
| 1 | a ConfigMap + Deployment blueprint; **watch it fail**, then grant kro permission | RGD → CRD → instance; least-privilege kro (aggregated RBAC) |
| 2 | pass the ConfigMap's name into the Deployment | references create dependencies; kro orders by them |
| 3 | an optional Service (`includeWhen`) | conditional children, like the platform's PDB |
| 4 | `readyWhen` and a `status` field | when an instance is "Ready" |
| 5 | **break it on purpose** twice | compile-time CEL checks; why the platform validates with a ValidatingAdmissionPolicy (incident D-14) |
| 6 | *stretch:* a cloud queue (ACK + moto) | kro waits for another controller's status |

**How to read each block:** **Why** says what the commands are for. Paste the whole block into one terminal, in order, and stay in `~/lab1-work`. Blocks that start with `# output` show what you should **see**: compare them, do not run them. Where kro needs time, the block waits with `kubectl wait`, which returns as soon as the condition is met, so you never need Ctrl-C. Before each step, *predict*; afterwards, compare with **Measured** and open *Explain*.

---

## Step 0: Start the sandbox (2 min)

**Why:** your files need a home outside every repository, and later steps copy two files from the reference solution, so `SOL` points at it. If you open a new terminal later, run this block again; it is safe to repeat.

<!-- doc-test: covered by="check:test-lab1" id="setup" -->
```bash
mkdir -p ~/lab1-work && cd ~/lab1-work
SOL=~/repos/gitops-control-plane/docs/lab-1-solution
```

**Why:** a throwaway cluster with kro configured exactly like the spokes: the same chart version, the same values and the same restricted RBAC mode. Your current kube context is **not** switched, so every command passes `--context k3d-learn-sandbox`.

<!-- doc-test: covered by="check:test-lab1" id="s0-up" -->
```bash
make -C ~/repos/gitops-control-plane sandbox-up
kubectl --context k3d-learn-sandbox get pods -A
```

**Measured (2026-10-07):** ready in 34 s; pods `kro`, `coredns` and `local-path-provisioner`, all `Running`. No moto and no ACK until step 6.

**Why:** your instances need a namespace. It gets the same Pod Security level as tenant namespaces on the lab (`restricted`), so your blueprint must produce compliant pods, as the platform's does.

<!-- doc-test: covered by="check:test-lab1" id="s0-ns" -->
```bash
kubectl --context k3d-learn-sandbox create namespace lab1
kubectl --context k3d-learn-sandbox label namespace lab1 pod-security.kubernetes.io/enforce=restricted
```

---

## Step 1: A blueprint, and the permission it needs (15 min)

A *ResourceGraphDefinition* (RGD) has a **schema**, the API your users get, and **resources**: templates with `${…}` CEL expressions that kro fills in per instance.

**Why:** this writes your first blueprint to `rgd.yaml`. It has a Deployment that serves a page, and a ConfigMap that holds the page's text. Read it before you continue: `${schema.metadata.name}` is the instance's name, and `${schema.spec.message}` is a field your users set.

<!-- doc-test: covered by="check:test-lab1" id="s1-rgd" -->
```bash
cat > rgd.yaml <<'EOF'
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
EOF
```

**Why:** an *instance* is what a user of your blueprint writes: only a name and the fields you allowed.

<!-- doc-test: covered by="check:test-lab1" id="s1-instance" -->
```bash
cat > instance.yaml <<'EOF'
apiVersion: kro.run/v1alpha1
kind: WebGreeting
metadata:
  name: hello
  namespace: lab1
spec:
  message: "hello from my first blueprint"
EOF
```

**Predict:** you apply the blueprint, then the instance. What appears in `lab1`?

**Why:** applying the RGD makes kro generate a new API (the CRD `webgreetings.kro.run`). The first `wait` makes sure the API exists before you use it; otherwise the instance is rejected with `no matches for kind "WebGreeting"`. The second `wait` gives kro time to try to start a controller for the new kind; this takes about 30 s here.

<!-- doc-test: covered by="check:test-lab1" id="s1-apply" -->
```bash
kubectl --context k3d-learn-sandbox apply -f rgd.yaml
kubectl --context k3d-learn-sandbox wait --for=create crd/webgreetings.kro.run --timeout=60s
kubectl --context k3d-learn-sandbox wait --for=condition=Established crd/webgreetings.kro.run --timeout=60s
kubectl --context k3d-learn-sandbox apply -f instance.yaml
kubectl --context k3d-learn-sandbox wait --for=condition=ControllerReady=false rgd/web-greeting --timeout=180s
kubectl --context k3d-learn-sandbox get rgd web-greeting \
  -o jsonpath='{range .status.conditions[*]}{.type}={.status} {.message}{"\n"}{end}'
kubectl --context k3d-learn-sandbox -n lab1 get webgreeting,configmap,deployment
```

**Measured:** the CRD existed within 3 s. The RGD stayed `Inactive`, and after about 30 s it showed:

```text
# output (compare, do not run)
ControllerReady=False add parent handler kro.run/v1alpha1, Resource=webgreetings: cache sync timeout for kro.run/v1alpha1, Resource=webgreetings
```

The instance had no status, and no ConfigMap or Deployment appeared.

**Why:** when kro cannot do its job, its log says why, and here the instance cannot tell you anything.

<!-- doc-test: covered by="check:test-lab1" id="s1-log" -->
```bash
kubectl --context k3d-learn-sandbox -n kro logs deploy/kro --since=5m | grep forbidden | tail -1
```

```text
# output (compare, do not run)
… webgreetings.kro.run is forbidden: User "system:serviceaccount:kro:kro" cannot list resource "webgreetings" in API group "kro.run" at the cluster scope
```

**Why:** on this platform, kro may manage **only the kinds a ClusterRole grants it**. You grant the new instance kind first, and nothing else yet, to see the second layer of the problem. The label `rbac.kro.run/aggregate-to-controller` merges this ClusterRole into kro's own role. The `wait` returns when kro reports the instance's next state, about 30 s later.

<!-- doc-test: covered by="check:test-lab1" id="s1-rbac" -->
```bash
cat > rbac.yaml <<'EOF'
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
EOF
kubectl --context k3d-learn-sandbox apply -f rbac.yaml
kubectl --context k3d-learn-sandbox -n lab1 wait --for=jsonpath='{.status.state}'=ERROR webgreeting/hello --timeout=180s
kubectl --context k3d-learn-sandbox -n lab1 get webgreeting hello \
  -o jsonpath='{.status.conditions[?(@.type=="Ready")].message}{"\n"}'
```

**Measured:** the RGD became `Active`, and the instance went to `ERROR`:

```text
# output (compare, do not run)
resource reconciliation failed: deployments.apps "hello" is forbidden: User "system:serviceaccount:kro:kro" cannot get resource "deployments" in API group "apps" in the namespace "lab1"
```

**Why:** now kro can watch your instances but not create their children. This appends the two child kinds to the same ClusterRole and applies it again. `rollout status` waits for the pod, because without a readiness rule (step 4) the instance says Ready before its pod runs. The last command fetches the page from inside the pod.

<!-- doc-test: covered by="check:test-lab1" id="s1-children" -->
```bash
cat >> rbac.yaml <<'EOF'
  - apiGroups: [""]
    resources: ["configmaps"]
    verbs: ["*"]
  - apiGroups: ["apps"]
    resources: ["deployments"]
    verbs: ["*"]
EOF
kubectl --context k3d-learn-sandbox apply -f rbac.yaml
kubectl --context k3d-learn-sandbox -n lab1 wait --for=jsonpath='{.status.state}'=ACTIVE webgreeting/hello --timeout=120s
kubectl --context k3d-learn-sandbox -n lab1 rollout status deployment/hello --timeout=120s
kubectl --context k3d-learn-sandbox -n lab1 get webgreeting,configmap,deployment
kubectl --context k3d-learn-sandbox -n lab1 exec deploy/hello -- wget -qO- localhost:8000; echo
```

**Measured:** `hello` was `ACTIVE`, `READY True` 3–10 s later, with `configmap/hello-page` and `deployment.apps/hello` (1/1). The page answered `hello from my first blueprint`.

<details><summary>Explain</summary>

Applying an RGD makes kro **generate a CRD** (your `WebGreeting` API) and start a controller for it. The lab runs kro with `rbac.mode: aggregation`: its service account starts with only a static role for kro's own types. Every blueprint ships a ClusterRole labelled `rbac.kro.run/aggregate-to-controller: "true"`, and Kubernetes merges it into kro's role. The platform's real one is `platform-catalog/blueprints/kro-rbac-queue-backed-service.yaml`. The failure has two layers: without the instance kind, kro cannot even *watch* `webgreetings` (`ControllerReady=False`); without the child kinds, it can watch but not create (`forbidden` on the instance). This is least privilege. A blueprint cannot make kro create kinds that nobody reviewed, such as a ClusterRoleBinding. It is also why blueprints are written here and not on the shared spokes.
</details>

---

## Step 2: Let one child depend on another (10 min)

**Question:** kro created both children. In which order?

**Why:** kro publishes the creation order it computed from your blueprint.

<!-- doc-test: covered by="check:test-lab1" id="s2-order" -->
```bash
kubectl --context k3d-learn-sandbox get rgd web-greeting -o jsonpath='{.status.topologicalOrder}{"\n"}'
```

**Measured:** `["deployment","config"]`, the order in which you declared them.

**Why:** the Deployment repeats the ConfigMap's naming rule (`${schema.metadata.name}-page`). This edit makes it **use** the ConfigMap's actual name instead, which creates a reference between the two. `grep` shows the changed line; if it prints nothing, the edit did not apply. The `sleep` gives kro a moment to compile the new revision.

<!-- doc-test: covered by="check:test-lab1" id="s2-edit" -->
```bash
sed -i 's|configMap: {name: "${schema.metadata.name}-page"}|configMap: {name: "${config.metadata.name}"}|' rgd.yaml
grep -n 'config.metadata.name' rgd.yaml
kubectl --context k3d-learn-sandbox apply -f rgd.yaml
sleep 5
kubectl --context k3d-learn-sandbox get rgd web-greeting -o jsonpath='{.status.topologicalOrder}{"\n"}'
kubectl --context k3d-learn-sandbox -n lab1 get webgreeting hello
```

**Measured:** `["config","deployment"]`. The instance stayed `ACTIVE`, and kro recorded a new graph revision (`kubectl --context k3d-learn-sandbox get graphrevisions.internal.kro.run`).

<details><summary>Explain</summary>

A reference to another resource's field (`config.metadata.name`) is an **edge** in kro's dependency graph (a DAG). kro creates `config` first, because the Deployment's template cannot be rendered until the value exists. The platform's `QueueBackedService` relies on the same mechanism: its ConfigMap waits for the queues' `status.queueURL`, which only ACK can fill in. That is why, with ACK down, kro creates the dead-letter queue but **waits** with everything that needs its ARN ([concepts, question 4](concepts-and-glossary.md#4-self-check-questions)). Declaration order is only a tie-breaker.
</details>

---

## Step 3: An optional child (10 min)

**Why:** you add a boolean field `expose` to the schema (the `sed` inserts it after `replicas`). You also add a Service that exists **only when it is true** (`includeWhen`). The Service is appended as the last resource. `grep` shows both changes.

<!-- doc-test: covered by="check:test-lab1" id="s3-edit" -->
```bash
sed -i 's/^      replicas: integer | default=1$/&\n      expose: boolean | default=false/' rgd.yaml
cat >> rgd.yaml <<'EOF'
    - id: service
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
EOF
grep -n -e 'expose' -e 'id: service' rgd.yaml
```

**Why:** a second instance that asks for the Service and two replicas. Before it is applied, the `wait` makes sure kro has added `expose` to the CRD; the RGD can say `Active` a moment before that, and the API would then reject the instance with `unknown field "spec.expose"`.

<!-- doc-test: covered by="check:test-lab1" id="s3-apply" -->
```bash
cat > instance-public.yaml <<'EOF'
apiVersion: kro.run/v1alpha1
kind: WebGreeting
metadata:
  name: hello-public
  namespace: lab1
spec:
  message: "hello, world"
  replicas: 2
  expose: true
EOF
kubectl --context k3d-learn-sandbox apply -f rgd.yaml
kubectl --context k3d-learn-sandbox wait crd/webgreetings.kro.run \
  --for=jsonpath='{.spec.versions[0].schema.openAPIV3Schema.properties.spec.properties.expose.type}'=boolean --timeout=60s
kubectl --context k3d-learn-sandbox apply -f instance-public.yaml
```

If `kubectl apply -f rgd.yaml` answers `spec.resources[N]: Invalid value: exactly one of template or externalRef must be provided` (seen in a pilot run with a hand-edited file), resource N, counting from 0, lost its `template:` line or its indentation.

**Predict:** what happens to `hello-public`? (Hint: step 1.)

**Why:** you give kro 20 s, then look at the instance, the Services and kro's log.

<!-- doc-test: covered by="check:test-lab1" id="s3-observe" -->
```bash
sleep 20
kubectl --context k3d-learn-sandbox -n lab1 get webgreeting,service
kubectl --context k3d-learn-sandbox -n kro logs deploy/kro --since=1m | grep 'services is forbidden' | tail -1
```

**Measured:** `hello-public` had **no status at all**, and no children appeared. kro's log repeated `services is forbidden: … cannot list resource "services"`.

**Why:** the new child kind, Service, needs the same grant as the others. The `sed` adds `services` next to `configmaps` in your ClusterRole. Then you fetch `hello-public`'s page through its Service, from a short-lived pod that meets Pod Security `restricted`.

<!-- doc-test: covered by="check:test-lab1" id="s3-rbac" -->
```bash
sed -i 's/resources: \["configmaps"\]/resources: ["configmaps", "services"]/' rbac.yaml
grep -n 'services' rbac.yaml
kubectl --context k3d-learn-sandbox apply -f rbac.yaml
kubectl --context k3d-learn-sandbox -n lab1 wait --for=jsonpath='{.status.state}'=ACTIVE webgreeting/hello-public --timeout=120s
kubectl --context k3d-learn-sandbox -n lab1 rollout status deployment/hello-public --timeout=120s
kubectl --context k3d-learn-sandbox -n lab1 get webgreeting,service,deployment
kubectl --context k3d-learn-sandbox -n lab1 run probe --rm -i --restart=Never --quiet \
  --image=busybox:1.37@sha256:bdf57e528e45e4433820e045b29b4597825a1c9e38353532d90a01445013f82e \
  --overrides='{"spec":{"securityContext":{"runAsNonRoot":true,"runAsUser":65534,"seccompProfile":{"type":"RuntimeDefault"}},"containers":[{"name":"probe","image":"busybox:1.37@sha256:bdf57e528e45e4433820e045b29b4597825a1c9e38353532d90a01445013f82e","command":["wget","-qO-","http://hello-public"],"securityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]}}}]}}'
echo
```

**Measured:** `hello-public` was `ACTIVE` 4–14 s later, with 2/2 pods and `service/hello-public`, which answered `hello, world`. `hello` got no Service.

**Why:** `includeWhen` is evaluated for each instance, every time. Switching `expose` on `hello` should create its Service, and switching it off should delete it again.

<!-- doc-test: covered by="check:test-lab1" id="s3-toggle" -->
```bash
kubectl --context k3d-learn-sandbox -n lab1 patch webgreeting hello --type merge -p '{"spec":{"expose":true}}'
kubectl --context k3d-learn-sandbox -n lab1 wait --for=create service/hello --timeout=30s
kubectl --context k3d-learn-sandbox -n lab1 patch webgreeting hello --type merge -p '{"spec":{"expose":false}}'
kubectl --context k3d-learn-sandbox -n lab1 wait --for=delete service/hello --timeout=30s
```

**Measured:** `service/hello` was created, then deleted, within 0–3 s each time.

<details><summary>Explain</summary>

`includeWhen` decides per instance whether a resource is part of the graph. When the value turns false, kro **deletes** the child, because it is no longer desired. The platform uses this for the PodDisruptionBudget: `includeWhen: ${schema.spec.replicas > 1}` in `queue-backed-service-rgd.yaml`, so prod gets a PDB and dev does not. This was Lab 0's optional Git step. The failure mode is worth remembering. When kro lacks permission for a kind the graph *might* contain, it cannot start watching it, and instances can sit **without any status**. Always check the kro log.
</details>

---

## Step 4: When is an instance Ready? (5 min)

**Why:** two additions. A `status` field copies the number of available pods into the instance, where users and Argo CD read it. A `readyWhen` rule makes the Deployment count as ready only when all its pods are available. Both are easiest to see in the complete file, so this block writes `rgd.yaml` once more: steps 1–3 unchanged, plus the two lines marked `step 4`. `diff` against the reference solution prints nothing if your file matches it.

<!-- doc-test: covered by="check:test-lab1" id="s4-rgd" -->
```bash
cat > rgd.yaml <<'EOF'
# Lab 1 reference solution (docs/lab-1-write-a-blueprint.md, steps 1-4). Sandbox only (make sandbox-up).
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
      expose: boolean | default=false
    status:                                     # step 4: copied from a child
      availableReplicas: ${deployment.status.availableReplicas}
  resources:
    # declared first, created second: it references config (step 2)
    - id: deployment
      readyWhen:                                # step 4: ready only when all pods are available
        - ${has(deployment.status.availableReplicas) && deployment.status.availableReplicas == deployment.spec.replicas}
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
                  configMap: {name: "${config.metadata.name}"}
    - id: config
      template:
        apiVersion: v1
        kind: ConfigMap
        metadata:
          name: ${schema.metadata.name}-page
        data:
          index.html: ${schema.spec.message}
    # step 3: only when the instance asks for it
    - id: service
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
EOF
diff rgd.yaml "$SOL/rgd.yaml" && echo "same as the reference solution"
kubectl --context k3d-learn-sandbox apply -f rgd.yaml
```

**Why:** scale through the instance, not the Deployment: a hand-scaled Deployment would be reverted (Lab 0, station 5). Watch the instance go not-ready, then ready, with the new `status` field showing the count. The `wait` returns once all 3 pods are available.

<!-- doc-test: covered by="check:test-lab1" id="s4-scale" -->
```bash
kubectl --context k3d-learn-sandbox -n lab1 patch webgreeting hello --type merge -p '{"spec":{"replicas":3}}'
kubectl --context k3d-learn-sandbox -n lab1 get webgreeting hello -o custom-columns='STATE:.status.state,AVAILABLE:.status.availableReplicas'
kubectl --context k3d-learn-sandbox -n lab1 wait --for=jsonpath='{.status.availableReplicas}'=3 webgreeting/hello --timeout=120s
kubectl --context k3d-learn-sandbox -n lab1 wait --for=jsonpath='{.status.state}'=ACTIVE webgreeting/hello --timeout=60s
kubectl --context k3d-learn-sandbox -n lab1 get webgreeting hello -o custom-columns='STATE:.status.state,AVAILABLE:.status.availableReplicas'
```

**Measured:** `ACTIVE`/`available=1` → within 1 s `IN_PROGRESS` (`Ready=False`) → after 2–3 s `ACTIVE`/`available=3`. The first `get` may already show `IN_PROGRESS`, or still `ACTIVE`, depending on timing.

<details><summary>Explain</summary>

`status` fields copy facts from children into the instance, where users (and Argo CD's health check) read them. The platform publishes `queueURL` and `serviceURL` this way. `readyWhen` makes a child count as ready only when your condition holds, and the instance is Ready only when all its children are. The `has(…)` guard matters: right after creation, `availableReplicas` does not exist yet. The team-cluster blueprint uses `readyWhen` to stay *not Ready* while ACK reports a terminal error.
</details>

---

## Step 5: Break it on purpose (10 min)

**(a) A typo in a reference.**

**Why:** this misspells `name` as `nmae` in the Deployment's reference to the ConfigMap, applies the broken blueprint, and waits for kro to refuse it. Then it checks that your running instances are unaffected.

<!-- doc-test: covered by="check:test-lab1" id="s5a-break" -->
```bash
sed -i 's/${config.metadata.name}/${config.metadata.nmae}/' rgd.yaml
grep -n 'nmae' rgd.yaml
kubectl --context k3d-learn-sandbox apply -f rgd.yaml
kubectl --context k3d-learn-sandbox wait --for=condition=GraphAccepted=false rgd/web-greeting --timeout=60s
kubectl --context k3d-learn-sandbox get rgd web-greeting \
  -o jsonpath='{range .status.conditions[?(@.type=="GraphAccepted")]}{.type}={.status} {.message}{"\n"}{end}'
kubectl --context k3d-learn-sandbox -n lab1 get webgreeting
```

**Measured:** the RGD became `Inactive` at once:

```text
# output (compare, do not run)
GraphAccepted=False failed to validate resource "deployment": failed to compile template expression "config.metadata.nmae" at path "spec.template.spec.volumes[0].configMap.name": ERROR: <input>:1:16: undefined field 'nmae'
 | config.metadata.nmae
 | ...............^
```

Both instances stayed `ACTIVE` on the last good revision.

**Why:** fix the typo and confirm that the blueprint is accepted again.

<!-- doc-test: covered by="check:test-lab1" id="s5a-fix" -->
```bash
sed -i 's/${config.metadata.nmae}/${config.metadata.name}/' rgd.yaml
kubectl --context k3d-learn-sandbox apply -f rgd.yaml
kubectl --context k3d-learn-sandbox wait --for=condition=Ready rgd/web-greeting --timeout=60s
```

**(b) A rule on an existing field.** You want at most 5 replicas.

**Why:** the obvious way is a schema marker, `minimum=1 maximum=5` on `replicas`. This adds it and applies it, so you can see what kro does with a constraint on a field that existing instances already use.

<!-- doc-test: covered by="check:test-lab1" id="s5b-break" -->
```bash
sed -i 's/replicas: integer | default=1$/& minimum=1 maximum=5/' rgd.yaml
grep -n 'maximum=5' rgd.yaml
kubectl --context k3d-learn-sandbox apply -f rgd.yaml
kubectl --context k3d-learn-sandbox wait --for=condition=KindReady=false rgd/web-greeting --timeout=60s
kubectl --context k3d-learn-sandbox get rgd web-greeting \
  -o jsonpath='{range .status.conditions[?(@.type=="KindReady")]}{.type}={.status} {.message}{"\n"}{end}'
kubectl --context k3d-learn-sandbox get crd webgreetings.kro.run \
  -o jsonpath='{.spec.versions[0].schema.openAPIV3Schema.properties.spec.properties.replicas}{"\n"}'
```

**Measured:**

```text
# output (compare, do not run)
KindReady=False cannot update CRD webgreetings.kro.run: breaking changes detected: Minimum constraint 1 was added; Maximum constraint 5 was added
{"default":1,"type":"integer"}
```

The CRD kept its old schema: the rule was **not** applied.

**Why:** remove the markers again, so the blueprint is back to a state kro accepts.

<!-- doc-test: covered by="check:test-lab1" id="s5b-fix" -->
```bash
sed -i 's/ minimum=1 maximum=5//' rgd.yaml
kubectl --context k3d-learn-sandbox apply -f rgd.yaml
kubectl --context k3d-learn-sandbox wait --for=condition=Ready rgd/web-greeting --timeout=60s
```

**Why:** enforce the rule the way the platform does: a ValidatingAdmissionPolicy that checks every create and update of a `WebGreeting` before it is stored. `cat` shows you the policy's two CEL rules; read them. The last command **should fail**: it is the test of the policy.

<!-- doc-test: covered by="check:test-lab1" id="s5b-policy" -->
```bash
cp "$SOL/policy.yaml" .
cat policy.yaml
kubectl --context k3d-learn-sandbox apply -f policy.yaml
sleep 5
kubectl --context k3d-learn-sandbox -n lab1 patch webgreeting hello --type merge -p '{"spec":{"replicas":9}}'
```

**Measured:**

```text
# output (compare, do not run)
The webgreetings "hello" is invalid: : ValidatingAdmissionPolicy 'webgreeting-contract' with binding 'webgreeting-contract' denied request: spec.replicas must be between 1 and 5
```

If the patch is accepted instead, the policy was not active yet (it takes a second or two). Set `replicas` back to 3 and run the patch again.

**Why:** a valid value still passes the policy.

<!-- doc-test: covered by="check:test-lab1" id="s5b-ok" -->
```bash
kubectl --context k3d-learn-sandbox -n lab1 patch webgreeting hello --type merge -p '{"spec":{"replicas":2}}'
```

<details><summary>Explain</summary>

(a) kro **type-checks** every CEL expression against the referenced resource's schema when you apply the RGD, not when an instance happens to hit it. A bad revision is rejected, and running instances keep the last good one. (b) Adding a constraint to a field that already exists could make stored instances invalid, so kro 0.9.4 refuses the CRD update. This happened to the platform on 2026-10-01 (**incident D-14**: the `QueueBackedService` RGD went `Inactive` on the nonprod spoke). The fix is in production today: the schema stays unconstrained, and `platform-catalog/blueprints/queue-backed-service-policy.yaml` enforces the contract at admission. It rejects bad input with a clear message and leaves kro's CRD untouched.
</details>

---

## Step 6 (stretch): A cloud resource (10 min)

**Why:** a cloud resource needs a cloud. This adds moto (the mock AWS) and the ACK SQS controller to your **running** sandbox; your blueprint and instances stay.

<!-- doc-test: covered by="check:test-lab1" id="s6-moto" -->
```bash
make -C ~/repos/gitops-control-plane sandbox-up WITH_MOTO=1
kubectl --context k3d-learn-sandbox -n lab1 get webgreeting
```

**Measured:** 19 s; `moto-sandbox` on `127.0.0.1:5002` and the ACK SQS controller (the lab's chart version and values) in `ack-system`. Your instances stayed `ACTIVE`. (Running it again refuses: the sandbox already has moto.)

**Why:** the stretch blueprint adds three things: an ACK `Queue` child, its URL in the page's ConfigMap (`queue-url`), and the URL in the instance's status (`queueURL`). kro also needs permission for `queues.sqs.services.k8s.aws`. Read the copied files to see the three additions (`grep` points at them), then apply them.

<!-- doc-test: covered by="check:test-lab1" id="s6-apply" -->
```bash
cp "$SOL/rbac-queue.yaml" "$SOL/rgd-with-queue.yaml" .
grep -n -i 'queue' rgd-with-queue.yaml
kubectl --context k3d-learn-sandbox apply -f rbac-queue.yaml -f rgd-with-queue.yaml
kubectl --context k3d-learn-sandbox -n lab1 wait --for=jsonpath='{.status.queueURL}' webgreeting/hello --timeout=120s
kubectl --context k3d-learn-sandbox -n lab1 wait --for=jsonpath='{.status.queueURL}' webgreeting/hello-public --timeout=120s
```

**Why:** check all three places: the instance's status, the ConfigMap kro wrote, and the cloud itself (moto, through the AWS CLI).

<!-- doc-test: covered by="check:test-lab1" id="s6-observe" -->
```bash
kubectl --context k3d-learn-sandbox -n lab1 get webgreeting -o custom-columns='NAME:.metadata.name,STATE:.status.state,QUEUE:.status.queueURL'
kubectl --context k3d-learn-sandbox -n lab1 get configmap hello-page -o jsonpath='{.data.queue-url}{"\n"}'
AWS_ACCESS_KEY_ID=mock-key AWS_SECRET_ACCESS_KEY=mock-secret \
  aws --endpoint-url=http://localhost:5002 --region us-east-1 sqs list-queues --query QueueUrls --output text
```

**Measured:** `status.queueURL` was `http://moto-sandbox:5000/123456789012/lab1-hello-jobs` within 3–5 s, the same URL was in `configmap/hello-page`, and moto listed `lab1-hello-jobs` and `lab1-hello-public-jobs`.

**Why:** deleting an instance should clean up everything it created, all the way into the cloud. The queue list afterwards shows only `lab1-hello-public-jobs`.

<!-- doc-test: covered by="check:test-lab1" id="s6-delete" -->
```bash
kubectl --context k3d-learn-sandbox -n lab1 delete webgreeting hello --timeout=120s
sleep 5
kubectl --context k3d-learn-sandbox -n lab1 get deployment,configmap,service,queue.sqs.services.k8s.aws
AWS_ACCESS_KEY_ID=mock-key AWS_SECRET_ACCESS_KEY=mock-secret \
  aws --endpoint-url=http://localhost:5002 --region us-east-1 sqs list-queues --query QueueUrls --output text
```

**Measured:** the delete took 7 s: kro removed `hello`'s Deployment, ConfigMap and `Queue` object, and ACK deleted the queue in moto. Only `hello-public`'s objects and queue remained.

<details><summary>Explain</summary>

The ConfigMap now depends on a field that **another controller** fills in: ACK writes `status.queueURL` after it has created the queue. kro waits for it, exactly as the platform's ConfigMap waits for the real queues. The sandbox's ACK has no CARM, so the queue lands in moto's default account `123456789012`. The lab maps each namespace to an account instead (Lab 0, station 4). Deletion runs the other way: kro deletes the children, and ACK's finalizer deletes the cloud resource. On the lab, prod uses `deletion-policy: retain` instead.
</details>

---

## Clean up

**Why:** the sandbox and your files were only for this lab. `sandbox-down` removes the cluster, its kube context, its Docker network and `moto-sandbox`, and then checks that nothing is left. The `cd` leaves the directory before it is removed.

<!-- doc-test: covered by="check:test-lab1" id="cleanup" -->
```bash
make -C ~/repos/gitops-control-plane sandbox-down
cd ~ && rm -r ~/lab1-work
```

**Measured:** `✔ sandbox removed (no cluster, container, network or kube context left)`.

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
