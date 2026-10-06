# Tenant IaC plan v0.3: P1 validation report (validated-02)

> **Status: Independent validation (2026-10-05 UTC).** Validator: Claude (Opus 5.5). Executor: Antigravity. Report under review: [implemented-02](2026-10-04-tenant-iac-team-clusters-plan-implemented-02.md). Commits: `gitops-control-plane` `8891999` (+ report `b79c9a8`), `platform-catalog` `78c923d` = tag `v1.8.0`. Everything below was checked on the live lab or by running the checks myself. The only change I made was a temporary edit in my local `platform-catalog` checkout for the negative CI test (restored, `git status` clean); nothing was committed to the platform repos.

## Verdict: 🟡 YELLOW: the P1 exit gate is met, 2 required follow-ups

The P1 exit gate in plan §6 is met:
- the controllers are healthy on both spokes;
- both networks are `Synced` in the right accounts;
- CI is green;
- the SQS tenants are unaffected (smoke test).

Two items from the P1 scope are missing or incomplete, though, and one of them will break the platform network at the next host reboot (V-1). Both should be closed before P2 is validated.

## 1. What I verified

| # | Check | Result | Evidence |
|---|---|---|---|
| 1 | Code matches plan v0.3 §5 and the P0 spike | ✅ | Values for ec2/iam/eks: images pinned by the registry **index digests** (`c0a979b3…`, `becbd2a3…`, `fd04f0d8…`, as resolved in P0); `reconcile.resources` = `[VPC, Subnet, InternetGateway, RouteTable, SecurityGroup]` / `[Role]` / `[Cluster, Nodegroup]`; `IgnoreFieldDrift` on EC2 + EKS; 50m/64Mi request, 200m/256Mi limit. `network/{nonprod,prod}` are identical apart from CIDR, `Name` tag and account comment; all `retain`; subnets declare the 5 defaults + `ignore-field-drift: spec.availabilityZoneID` |
| 2 | Argo CD | ✅ | **40/40** Applications Synced/Healthy, including `addon-ack-{ec2,iam,eks}-spoke-{nonprod,prod}` and `platform-network-spoke-{nonprod,prod}` (revision `78c923d`). `spoke-prod` annotation `blueprints-revision=v1.8.0` (annotated tag → `78c923d`); `spoke-nonprod` = `main` |
| 3 | Controllers | ✅ | 4/4 Ready on both spokes, 0 restarts for ec2/iam/eks (SQS: 1, from the moto recreation); running images = the pinned digests; `FEATURE_GATES` include `IgnoreFieldDrift=true`, EKS `RECONCILE_RESOURCES=Cluster,Nodegroup`; 38 `services.k8s.aws` CRDs per spoke (35 new + 2 shared + SQS `queues`) |
| 4 | Pod Security + accounts | ✅ | `ack-system` and `platform-network` are PSS `restricted` on both spokes; `platform-network` CARM annotation 111111111111 (nonprod) / 222222222222 (prod) |
| 5 | Network in moto | ✅ | Per account, **exactly one** non-default VPC (10.10.0.0/16 `platform-nonprod` in 111…, 10.20.0.0/16 `platform-prod` in 222…), 2 subnets (1a/1b), SG and IGW attached to it. The IDs in each spoke's `status` match moto exactly; `ownerAccountID` matches; all 12 objects `ACK.ResourceSynced=True` |
| 6 | Default account 123456789012 | ✅ | 0 non-default VPCs, 0 `platform-cluster-sg`, 0 IGWs, 0 queues, 0 non-service roles: no wrong-account records (P0 F-6) |
| 7 | moto settings (O-7) | ✅ | `MOTO_IAM_LOAD_MANAGED_POLICIES=true`, `MOTO_ALLOW_NONEXISTENT_SERVICES=true`, `--restart unless-stopped`; `iam get-policy …/AmazonEKSClusterPolicy` returns the ARN. `start-hub-spoke.sh` now also uses the right network (`k3d-cloud-net`, was `k3d-hub-spoke-net`) and the same flags as `setup-hub-spoke.sh`: good catch |
| 8 | kro RBAC | ✅ | `kro:controller` aggregates `teameksclusters`, `roles`, `clusters`/`nodegroups`, and EC2 read; `kro:kro` **can** `list subnets` but **cannot** `create subnets` in `platform-network` (read-only as designed) |
| 9 | Steady state over one full resync (330 s, both spokes) | ✅ | ec2, iam, eks, sqs: **0 updates, 0 reconciler errors** each (the P0 F-5 fixes hold on the lab) |
| 10 | Metrics | ✅ | Hub Prometheus: `up=1` for `ack-ec2/iam/eks/sqs` and `kro` on both spokes (10 targets); no firing alerts |
| 11 | Alert rule | ✅ (rule) / ⚠️ (test) | I added a **temporary** promtool test (not committed): `SpokeControllerDown` fires when `ack-ec2`, `ack-iam` or `ack-eks` alone is down, and stays silent when all five are up: SUCCESS. The committed test only adds *healthy* series for the three jobs (V-3) |
| 12 | CI | ✅ / ❌ | GitHub Actions green on `8891999`, `b79c9a8` and catalog `78c923d`. Local `make ci`: all stages pass, 40 apps rendered, kubeconform 571 resources (the 6 network objects per spoke are **validated**, not skipped). `make ci-catalog` passes **but does not cover `network/`** (V-2) |
| 13 | Smoke test | ✅ | `make test` twice: all stages green, 0 failures (orders end to end, SSO, VAP/Kyverno, metrics, logs, no firing alerts) |

## 2. Findings

| # | Severity | Finding | Evidence | Required action |
|---|---|---|---|---|
| **V-1** | **Required** (before the next host reboot or `make start`) | **The moto restart procedure was not delivered.** It was P1 scope item 5 in validated-01 §4 and plan v0.3 §5. There is no script, Make target or `post-bootstrap` step, and the report does not mention it. With the network now live, the next moto restart (every host reboot: moto is in-memory) will leave the **InternetGateway and SecurityGroup permanently unsynced**: ACK EC2 1.21.2 does not recreate them on `InvalidInternetGatewayID.NotFound` / `InvalidGroup.NotFound` (P0 F-7). Subnets and route table will then wait forever | `grep` of `scripts/`, `Makefile`, runbooks: nothing; P0 F-7 (same controller version) | A script (e.g. `scripts/moto-restart.sh`, `make moto-restart`) that: pauses the hub app controller (Argo self-heal would undo the ACK scale-down); scales ACK to 0 on both spokes; restarts moto; scales ACK back up and resumes Argo; re-creates the `platform-network` objects (delete with `retain`, let Argo re-create them); clears stale `services.k8s.aws/adopted` markers; runs `post-bootstrap`; asserts that account 123456789012 is empty. The `make start` path also needs the network re-creation step (start-hub-spoke starts moto before the clusters, so credentials are fresh, but the IGW/SG IDs are stale). Prove it with one real run in an owner-approved window |
| **V-2** | **Required** | **Catalog CI does not check `network/`.** `ci/check-catalog.sh` renders only `kro-blueprints.yaml` and `addons-spoke*.yaml`. `platform-catalog` `main` has no ruleset and `spoke-nonprod` follows `main`, so a broken network manifest goes straight to the spoke | Negative test: `cidrBlocks: 42` in `network/nonprod/network.yaml` → `make ci-catalog` still **"all checks passed"** (20 apps). The same file fed to kubeconform with `ci/schemas` → `got number, want array` | Add `applicationsets/platform-network.yaml` to the render list in `check-catalog.sh`; show the negative test red |
| V-3 | Minor | The committed alert test does not test the new branches; "verified firing" in implemented-02 §2.2 is overstated | `alert-rules.test.yaml` diff: 3 healthy series only | Add cases with `ack-ec2` / `ack-iam` / `ack-eks` down (my temporary test can be reused) |
| V-4 | Observation (pre-existing, not P1) | **Argo CD applies none of the lab's custom health checks.** The network objects, the `queuebackedservice` RGD and the `QueueBackedService` instance all have **no health** in `app.status.resources`, although `resource.customizations` defines Lua for `kro.run/ResourceGraphDefinition`, `kro.run/*` and `services.k8s.aws/*`. So a broken network object would leave `platform-network-*` Healthy. Possible cause: the legacy single-key format (`argocd-cm` also has split `resource.customizations.ignoreResourceUpdates.*` keys). **Not verified** | `kubectl get application … -o json`: `.status.resources[].health` absent | Before P4 amendment 7 (EKS `Cluster` health): fix the format (e.g. `resource.customizations.health.<group>_<kind>`) and prove a check is applied. Note that `services.k8s.aws/*` would not match `ec2.services.k8s.aws` anyway |
| V-5 | Minor (report accuracy) | implemented-02 says "37 new ACK CRDs" in `ci/schemas` (35 committed: ec2 20, eks 8, iam 7) and does not mention how moto was recreated, or that the default account was checked | `git show --stat 8891999` | None beyond V-1; correct when convenient |

## 3. Not tested
- A real moto restart on the lab (disruptive, needs the owner's window). It belongs to V-1's proof.
- Prod-specific promotion behaviour beyond the tag pin (no team claims exist until P4).

## 4. Next
- **V-1 and V-2** to the executor (Antigravity), or as the owner decides. I re-validate both.
- **P2 (executor Claude)** can start in parallel: it doesn't depend on V-1/V-2. Until V-1 is in place, **avoid restarting the host or `make stop`/`make start`**, or run the manual recovery from P0 (`spike.sh recover` steps, adapted to the lab) afterwards.

---

**Erratum (2026-10-06, Claude): V-4 was a false positive.** Argo CD 3.x does not copy per-resource health into the Application's `status.resources`, so its absence there proves nothing. The resource tree (`argocd app get <app> --output tree`) shows the custom health checks working: `QueueBackedService/orders … Healthy`, `Queue/… Healthy`, `VPC/platform-vpc … Healthy`, `ResourceGraphDefinition/… Healthy`. The lab's split health keys (`resource.customizations.health.*`, added in P4) and the legacy `resource.customizations` key are both evaluated. Recorded as learning gap L-7 in `docs/assessments/2026-10-06-lab-learning-assessment.md` v3.0.
