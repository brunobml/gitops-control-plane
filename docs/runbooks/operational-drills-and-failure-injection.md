# Operational Playbook: Failure Injection & Disaster Recovery Drills
## Hub-and-Spoke GitOps Control Plane

> **Status: Current.** Version 1.1 (2026-10-03, Step 0.5 of the [2026-10-03 remediation plan](../remediation/2026-10-03-lab-assessment/2026-10-03-lab-remediation-plan.md)). Every drill below was run once against the lab before this version was committed; observed timings are from that run.

* **Target Audience:** Platform Engineers, SREs, and Operations Operators
* **Cluster Baseline:** `k3d-hub-cluster`, `k3d-spoke-nonprod`, `k3d-spoke-prod`, `moto-cloud`, 32 Applications
* **Companion Runbook:** [`host-reboot-and-cluster-lifecycle.md`](host-reboot-and-cluster-lifecycle.md)
* **Paths:** commands run from the `gitops-control-plane` checkout. The other repositories are expected next to it: `REPOS_DIR=${REPOS_DIR:-..}`

---

## 1. Executive Summary

These exercises induce realistic failures, show which control or alert detects each one, and practise the documented recovery. Every drill has an **Expected signal** line naming *which* control fires. A drill passes only if that control fires, not merely if "something" denies or alerts.

```
       Fault Injection                Detection Layer                   Recovery Layer
┌───────────────────────────┐   ┌──────────────────────────┐   ┌──────────────────────────────┐
│ • Restart moto (cloud)    │──►│ • Prometheus alert rules │──►│ • make post-bootstrap        │
│ • Expiring spoke tokens   │   │ • Admission denials      │   │   (idempotent)               │
│ • Kyverno outage          │   │   (Kyverno, VAP, PSS)    │   │ • ACK / Argo CD reconcile    │
│ • Out-of-band cloud drift │   │ • Grafana dashboards     │   │ • Orphan cleanup (O-3)       │
│ • Tenant deregistration   │   │ • Loki logs and events   │   │ • Token renewal              │
└───────────────────────────┘   └──────────────────────────┘   └──────────────────────────────┘
```

**Admission controls in tenant namespaces.** These are namespaces labelled `platform.lab/image-verification=enabled`. Know which control you are testing:

| Control | Denies | Message starts with |
|---|---|---|
| Pod Security `restricted` | non-compliant pod specs (root, privilege escalation, capabilities, no seccomp). It applies *first*, whatever the image | `violates PodSecurity "restricted:latest"` |
| VAP `tenant-image-registry-allowlist` | any image (containers, initContainers, ephemeral containers) outside `ghcr.io/brunobml/` | `ValidatingAdmissionPolicy 'tenant-image-registry-allowlist' … denied request` |
| Kyverno `tenant-images-signed` | `ghcr.io/brunobml/orders-processor*` images without the CI's cosign signature | `admission webhook "ivpol.validate.kyverno.svc-fail-finegrained-tenant-images-signed" denied the request` |
| VAP `queuebackedservice-contract` | QueueBackedService objects that break the platform contract | `ValidatingAdmissionPolicy 'queuebackedservice-contract' …` |

To reach the image controls, a test pod must pass Pod Security. Use this compliant spec in the drills:
```bash
OV='{"spec":{"securityContext":{"runAsNonRoot":true,"runAsUser":10001,"seccompProfile":{"type":"RuntimeDefault"}},"containers":[{"name":"drill","image":"IMG","securityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]}}}]}}'
SIGNED="ghcr.io/brunobml/orders-processor:v1.5.0@sha256:e95bb63320628d8541e984b668474bcc21066e54110d00ab20974132f1287510"
UNSIGNED="ghcr.io/brunobml/orders-processor@sha256:c7e8f5d9038ad202da6d37e0be76aa342a482bd4d6b37279b0891792584cf32f"   # v1.4.0, built before signing
```

Helpers used below. They query hub Prometheus and Loki from inside the cluster (neither has an ingress):
```bash
promq()  { kubectl --context k3d-hub-cluster -n monitoring exec deploy/prometheus-server -c prometheus-server -- \
             wget -qO- "http://localhost:9090/api/v1/query?query=$(jq -rn --arg q "$1" '$q|@uri')"; }
alerts() { kubectl --context k3d-hub-cluster -n monitoring exec deploy/prometheus-server -c prometheus-server -- \
             wget -qO- http://localhost:9090/api/v1/alerts | jq -r '.data.alerts[] | "\(.labels.alertname) \(.state)"'; }
logq()   { kubectl --context k3d-hub-cluster -n monitoring exec deploy/prometheus-server -c prometheus-server -- \
             wget -qO- "http://loki.monitoring.svc:3100/loki/api/v1/query_range?since=${2:-15m}&limit=50&query=$(jq -rn --arg q "$1" '$q|@uri')"; }
moto111() {  # credentials for moto account 111111111111 (nonprod), as the smoke test does
  local c; c=$(AWS_ACCESS_KEY_ID=mock-key AWS_SECRET_ACCESS_KEY=mock-secret aws --endpoint-url=http://localhost:5000 --region us-east-1 \
    sts assume-role --role-arn arn:aws:iam::111111111111:role/drill --role-session-name drill --query Credentials --output json)
  export AWS_ACCESS_KEY_ID=$(jq -r .AccessKeyId <<<"$c") AWS_SECRET_ACCESS_KEY=$(jq -r .SecretAccessKey <<<"$c") AWS_SESSION_TOKEN=$(jq -r .SessionToken <<<"$c"); }
```

---

## 2. Pre-Drill Health Check

```bash
make test        # 12/12 smoke stages
alerts           # nothing firing
```
In Grafana (http://grafana.localhost, Keycloak user `platform-user`), open *Dashboards → Platform overview* and *Logs & events*.

Expected baseline:
* 12/12 smoke stages pass;
* no firing alerts;
* 32/32 Applications `Synced / Healthy`.

---

## 3. Drill 1: Cloud Restart Wipes Worker Keys (Failure Mode F-1)

### Scenario Context
Moto keeps everything in memory. A restart (host reboot, container restart) loses every queue, table and IAM key. The workers keep running with keys that no longer exist, so orders are accepted but never processed.

### Action: Induce Failure
```bash
docker restart moto-cloud
```

### Expected signal
* **Synthetic order probe:** `lab_order_e2e_success` drops to **0** at the probe's next run. It runs every 5 min per environment. Observed after the restart at 07:58:55: nonprod at 07:59:44, prod at 08:01:50.
* **`OrdersNotProcessed{cluster=…}`** (critical): pending at once, **firing after 10 min** (`for: 10m`). Observed: nonprod firing 08:10:03, prod 08:12:34. It is visible in Grafana *Platform overview → Firing alerts*.
* **Not a signal:**
  * `ProbeFailed{probe="moto"}` does not fire, because moto is back within seconds and the rule needs 5 min.
  * The workers log **nothing** while their keys are invalid. Loki shows no error lines for `orders-*` during the outage. This silence is why F-1 needs the synthetic probe.

### Remediation & Recovery
```bash
make post-bootstrap
```
*What happens:*
* ACK recreates the queues on its own (resync ≤ 5 min).
* `post-bootstrap.sh` step `[4/9]` finds that each worker Secret's key no longer authenticates, and creates a new IAM key in the namespace's account (111111111111 nonprod, 222222222222 prod).
* Step `[5/9]` restarts only the workers whose running key differs from their Secret.
* Step `[9/9]` runs the smoke test, including one end-to-end order per environment.

### Validation
```bash
promq 'lab_order_e2e_success' | jq -c '[.data.result[] | {(.metric.namespace): .value[1]}] | add'   # all 1
alerts   # OrdersNotProcessed cleared
```
Observed:
* `post-bootstrap` ran 08:10:04 to 08:12:17 (rc 0, smoke 12/12);
* the probe reported 1 again at nonprod 08:14:40 and prod 08:17:02;
* all alerts cleared at 08:17:33.

Expect up to one probe interval (5 min) after `post-bootstrap` before the alert clears.

---

## 4. Drill 2: Spoke Token Expiration & Automated Renewal (Failure Mode PV2-5)

### Scenario Context
The Argo CD spoke cluster Secrets and the Headlamp kubeconfig use bounded 30-day `TokenRequest` tokens. When they expire, Argo CD loses its spokes (`ArgoClusterUnreachable`). Their expiry is recorded in the ConfigMap `monitoring/credential-expiry` whenever a token is minted. The credential-expiry exporter turns that ConfigMap into `lab_credential_expiry_timestamp_seconds`.

### Action: Induce Failure
Record that the `spoke-nonprod` token expires in 2 days. The token itself is unchanged; only the recorded expiry moves:
```bash
kubectl --context k3d-hub-cluster -n monitoring patch cm credential-expiry --type merge \
  -p "{\"data\":{\"argocd-spoke-nonprod\":\"$(( $(date +%s) + 172800 ))\"}}"
```

### Expected signal
* **`SpokeTokenExpiringSoon{credential="argocd-spoke-nonprod"}`**: pending at once, **firing after 5 min** (`for: 5m`). Observed: pending 07:41, firing 07:46.
* The smoke test does **not** warn here. Stage `[8/12]` reads the `exp` claim of the real tokens, which are still valid. To see that warning, run `TOKEN_WARN_DAYS=40 make test`.

### Remediation & Recovery
```bash
make post-bootstrap
```
Step `[1/9]` reads the shortest expiry from the ConfigMap ("shortest left: 1 days" < 7). It then runs `register-spokes.sh` and `addons/headlamp/setup-credentials.sh`, which mint new 30-day tokens for both spokes and Headlamp and rewrite the ConfigMap.

### Validation
```bash
promq 'round((lab_credential_expiry_timestamp_seconds - time()) / 86400)' | jq -c '[.data.result[] | {(.metric.credential): .value[1]}] | add'
# observed: all five credentials = 30 days
alerts   # SpokeTokenExpiringSoon gone (observed within 1 min of renewal)
```

---

## 5. Drill 3: Kyverno Admission Resilience & Total Outage

### Scenario Context
Tenant namespaces verify `orders-processor` image signatures with Kyverno. Kyverno runs 2 replicas spread over two nodes, with a PDB (`minAvailable: 1`).

### Phase A: one replica lost (no disruption)
```bash
POD=$(kubectl --context k3d-spoke-nonprod -n kyverno get pods -l app.kubernetes.io/component=admission-controller -o jsonpath='{.items[0].metadata.name}')
kubectl --context k3d-spoke-nonprod -n kyverno delete pod "$POD" --wait=false
# immediately, and again while the replacement starts:
kubectl --context k3d-spoke-nonprod -n orders-dev run drill-unsigned --image="$UNSIGNED" --restart=Never \
  --dry-run=server --overrides="${OV/IMG/$UNSIGNED}"
```
**Expected signal:** denied by **Kyverno** (`admission webhook "ivpol.validate.kyverno.svc-fail-finegrained-tenant-images-signed" … Policy tenant-images-signed failed`) at every attempt. Observed: denied at +0 s, +6 s and +11 s.

> Do not use `--image=alpine:latest` here. Without the compliant spec it is denied by **Pod Security**. With the compliant spec it is denied by the **registry allowlist VAP**. Neither proves Kyverno works.

### Phase B: total Kyverno outage
Argo CD self-heals the Kyverno Deployment within seconds, and the ApplicationSet controller reverts any change to a generated Application's sync policy. To hold the outage you must **pause the hub application controller**. That pauses *all* GitOps reconciliation, so keep the window short.
```bash
kubectl --context k3d-hub-cluster -n argocd scale statefulset argo-cd-argocd-application-controller --replicas=0
kubectl --context k3d-spoke-nonprod -n kyverno scale deploy/kyverno-admission-controller --replicas=0
kubectl --context k3d-spoke-nonprod get validatingwebhookconfiguration | grep -c kyverno     # 0
kubectl --context k3d-spoke-nonprod -n orders-dev run drill-unsigned --image="$UNSIGNED" --restart=Never \
  --dry-run=server --overrides="${OV/IMG/$UNSIGNED}"                                          # ADMITTED
kubectl --context k3d-spoke-nonprod -n orders-dev run drill-alpine --image=alpine:latest --restart=Never \
  --dry-run=server --overrides="${OV/IMG/alpine:latest}"                                       # denied by the VAP
```
**Expected signal:**
* **`KyvernoDown{cluster="spoke-nonprod"}`** (critical): pending after about 1.7 min, **firing 2 min later** (`for: 2m`). Observed: scaled down 07:31:18, pending 07:32:59, firing 07:35:02.
* **Known residual (Phase 4 D-10 / Phase 5 C.2):** on a graceful stop, Kyverno **removes its own webhooks**. During the outage an **unsigned `orders-processor` image is admitted**, so signature verification fails open. The **registry allowlist VAP still denies** foreign images (`alpine`), because it runs inside the API server. `KyvernoDown` is the control for this window.

### Remediation & Recovery
```bash
kubectl --context k3d-hub-cluster -n argocd scale statefulset argo-cd-argocd-application-controller --replicas=1
```
Argo CD self-heal restores `replicas: 2`, and Kyverno re-creates its webhooks. Observed: 2/2 ready and 5 webhooks back within 50 s, and the unsigned image denied again.

### Validation
```bash
kubectl --context k3d-spoke-nonprod -n kyverno get pods -o wide   # 2 Running, on different nodes
alerts                                                            # KyvernoDown cleared
```

---

## 6. Drill 4: Out-of-Band Cloud Drift on SQS Resources

### Scenario Context
ACK manages the SQS queues declaratively. A queue deleted directly in the cloud is recreated at the next reconciliation of its `Queue` resource. The resync period is `reconcile.defaultResyncPeriod: 300` s (`platform-catalog/controllers/ack/values-sqs.yaml`).

### Action: Induce Cloud Drift
```bash
moto111
aws --endpoint-url=http://localhost:5000 --region us-east-1 sqs delete-queue \
  --queue-url http://localhost:5000/111111111111/orders-dev-dlq
```

### Expected signal
**ACK recreates the queue by itself**, with no restart and no alert. Observed: **150 s** in this run, 11 s in the 2026-10-03 assessment. The time depends on where the resource is in its resync cycle, and is at most about 300 s. The controller logs it:
```bash
kubectl --context k3d-spoke-nonprod -n ack-system logs deploy/ack-sqs-controller-sqs-chart --since=10m | grep '"created new resource".*orders-dev-dlq'
```

### Optional: faster reconcile
`kubectl --context k3d-spoke-nonprod -n ack-system rollout restart deploy/ack-sqs-controller-sqs-chart` forces an immediate reconcile of every resource. It is not needed for recovery.

### Validation
```bash
moto111
aws --endpoint-url=http://localhost:5000 --region us-east-1 sqs get-queue-url --queue-name orders-dev-dlq
aws --endpoint-url=http://localhost:5000 --region us-east-1 sqs get-queue-attributes --attribute-names RedrivePolicy \
  --queue-url http://localhost:5000/111111111111/orders-dev-queue   # deadLetterTargetArn …:111111111111:orders-dev-dlq
```

---

## 7. Drill 5: Tenant Registration, Deregistration & Data Hygiene (Failure Mode D-16 / O-3)

### Scenario Context
A tenant app is one **registration file** in `tenant-workloads`: `tenants/<tenant>/apps/<app>-<env>.yaml`. The `tenant-workloads` ApplicationSet turns each file into an Application `<app>-<env>` in namespace `<app>-<env>`, on the spoke and cloud account that `env` selects.

When the file is removed, Argo CD prunes the workload. The namespace, the worker IAM user and the DynamoDB table are left behind. Per owner decision **O-3**, `post-bootstrap` removes the credentials and the empty namespace, and data is only reported unless `PRUNE_DATA=1`.

The demo app's values live permanently in `orders-processor/deploy/values-orders-demo-dev.yaml` (`name: orders-demo`). Its queues, table and IAM user therefore never collide with the real `orders-dev` ones.

> ⚠️ **The registration format is strict.** Use exactly these fields: `tenant`, `app` (must match `orders-*`), `env` (`dev`/`test`/`prod`), `port` (quoted), `valuesRevision` (a full 40-character SHA for `prod`), and optional `valuesFile`. The ApplicationSet uses `missingkey=error`, so a file with other field names makes the **whole `tenant-workloads` ApplicationSet stop rendering**, for every tenant, until it is fixed (assessment L2-3).

### Action: Register
> Once Track A.4 is active (pull requests required on `tenant-workloads` `main`), replace each `git push origin main` below with a branch push and a pull request. The required check `registration-checks` must pass before merging. Then wait for the merge instead of the push. Before that, the commands work as shown.

```bash
TW=${REPOS_DIR:-..}/tenant-workloads
cat > "$TW/tenants/tenant-a/apps/orders-demo-dev.yaml" <<'EOF'
tenant: tenant-a
app: orders-demo
env: dev
port: "8081"
valuesRevision: main
valuesFile: deploy/values-orders-demo-dev.yaml
EOF
git -C "$TW" add tenants/tenant-a/apps/orders-demo-dev.yaml
git -C "$TW" commit -m "test(tenants): drill 5 - register orders-demo (temporary)"
git -C "$TW" push origin main
```
**Expected signal:** Application **`orders-demo-dev`** becomes `Synced / Healthy` (observed after 3 min). The QueueBackedService `orders-demo` is ACTIVE, with queues `orders-demo-dev-queue` and `orders-demo-dev-dlq`.

Then provision the worker's cloud credentials:
```bash
make post-bootstrap
```
**Expected signal:**
* step `[2/9]` lists `spoke-nonprod/orders-demo-dev (orders-demo, dev)`;
* step `[4/9]` creates Secret `orders-demo-dev-aws` for IAM user `orders-demo-dev-worker` in account 111111111111;
* step `[5/9]` restarts the worker; the smoke test passes.

### Action: Deregister
```bash
git -C "$TW" rm tenants/tenant-a/apps/orders-demo-dev.yaml
git -C "$TW" commit -m "test(tenants): drill 5 - deregister orders-demo"
git -C "$TW" push origin main
```
**Expected signal:** Application `orders-demo-dev` is pruned, along with its workload and queues (observed after 1.5 min). Namespace `orders-demo-dev` remains, empty except for the credential Secret.

### Action: Inspect Orphans (dry run)
```bash
make orphans
```
**Expected output** (observed):
```
[dry-run] would remove: − spoke-nonprod/orders-demo-dev: not registered and empty -> namespace deleted (incl. its credential Secret)
[dry-run] would remove: − account 111111111111: IAM user orders-demo-dev-worker (deregistered app) deleted
! account 111111111111: DynamoDB table orders-demo-dev-history belongs to no registered app (data kept; PRUNE_DATA=1 deletes it)
```

### Action: Clean Up
```bash
make post-bootstrap               # step [6/9]: namespace and IAM user removed, table reported
PRUNE_DATA=1 bash scripts/orphans.sh   # only when the data may go: deletes orders-demo-dev-history
```

### Validation
* `kubectl --context k3d-spoke-nonprod get ns orders-demo-dev` → NotFound.
* With `moto111`: `aws … iam get-user --user-name orders-demo-dev-worker` → NoSuchEntity.
* `aws … dynamodb list-tables` → only `orders-dev-history` and `orders-test-history`.

---

## 8. Drill 6: Terminated Pod Post-Mortem from Loki

### Scenario Context
Alloy ships pod logs and Kubernetes events from all three clusters to Loki on the hub. This drill checks that the logs of a pod that has already been **deleted** can still be read.

### Action: Provoke Failure and Teardown
The pod must pass every admission control. That means the compliant spec and the **signed** image, which has a shell.
```bash
OVPM='{"spec":{"securityContext":{"runAsNonRoot":true,"runAsUser":10001,"seccompProfile":{"type":"RuntimeDefault"}},"containers":[{"name":"post-mortem-drill","image":"IMG","command":["sh","-c","echo CRITICAL-PANIC: drill marker $(date +%s); exit 1"],"securityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]}}}]}}'
kubectl --context k3d-spoke-nonprod -n orders-dev run post-mortem-drill --image="$SIGNED" --restart=Never \
  --overrides="${OVPM/IMG/$SIGNED}"
kubectl --context k3d-spoke-nonprod -n orders-dev wait --for=jsonpath='{.status.phase}'=Failed pod/post-mortem-drill --timeout=120s
sleep 20   # let Alloy ship the line
kubectl --context k3d-spoke-nonprod -n orders-dev delete pod post-mortem-drill
kubectl --context k3d-spoke-nonprod -n orders-dev logs post-mortem-drill   # Error … NotFound
```
> With `--image=alpine:latest` (v1.0 of this playbook), the pod is never created. It is denied by Pod Security, and with a compliant spec by the registry allowlist VAP. There would be nothing to investigate.

### Expected signal
**Loki** returns the line with the deleted pod's labels:
```bash
logq '{cluster="spoke-nonprod", namespace="orders-dev", pod="post-mortem-drill"}' \
  | jq -c '.data.result[] | {stream: (.stream | {cluster, namespace, pod, container}), line: .values[0][1]}'
# observed: {"stream":{"cluster":"spoke-nonprod","namespace":"orders-dev","pod":"post-mortem-drill","container":"post-mortem-drill"},
#            "line":"CRITICAL-PANIC: drill marker 1791013171\n"}
```
The pod's scheduling and lifecycle **events** are in Loki as well, under `job="kubernetes-events"`. In Grafana, *Logs & events* shows the same with the filters cluster `spoke-nonprod` and namespace `orders-dev`.

---

## 9. Post-Drill Restoration & Clean Slate

```bash
# 1. The hub application controller must be running (Drill 3 Phase B pauses it)
kubectl --context k3d-hub-cluster -n argocd scale statefulset argo-cd-argocd-application-controller --replicas=1

# 2. No drill registration left behind (Drill 5)
ls ${REPOS_DIR:-..}/tenant-workloads/tenants/*/apps/    # only orders-dev, orders-test, orders-prod

# 3. Credentials, sync state and the full smoke test
make post-bootstrap
alerts    # nothing firing
```
