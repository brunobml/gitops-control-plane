# Tenant IaC plan v0.3: P5 clean-slate rebuild & final acceptance evidence (implemented-08)

> **Status:** Full clean-slate rebuild drill complete; all 5 findings from [validated-08](2026-10-04-tenant-iac-team-clusters-plan-validated-08.md) verified and resolved. Ready for formal P5 acceptance.  
> **Author:** Antigravity (Executor)  
> **Base commit:** `2b13d66`  
> **Live lab state:** 42/42 Hub Applications Synced & Healthy, 12/12 Smoke Gates Passed, 27/27 Bats Assertions Passed (0 failures).

---

## 1. Objective & Scope

This report provides the full clean-slate rebuild verification evidence required to close **Finding 5** of [validated-08](2026-10-04-tenant-iac-team-clusters-plan-validated-08.md) and establish formal completion of **Phase P5 (Team Cluster Observability & Runbooks)** of the [Tenant IaC Plan v0.3](2026-10-04-tenant-iac-team-clusters-plan.md).

The drill executes a cold-start destruction and recreation of the entire lab environment:
`make teardown && make setup && make bootstrap && make post-bootstrap`
followed by execution of the smoke test suites and CI validation.

---

## 2. Clean-Slate Rebuild Drill Execution

### Step 1: `make teardown` (Full Teardown)
- **Action:** Deleted all 3 k3d clusters (`hub-cluster`, `spoke-nonprod`, `spoke-prod`), removed `moto-cloud` container, and deleted Docker bridge network `k3d-cloud-net`.
- **Result:** Exit code 0; zero remaining lab containers or networks.

### Step 2: `make setup` (Infrastructure & Control Plane Setup)
- **Action:** Recreated `k3d-cloud-net` (`172.21.0.0/16`), started `moto-cloud` (`motoserver/moto@sha256:91fd602a...`), provisioned 3 k3d clusters (`rancher/k3s:v1.35.5-k3s1`), deployed Traefik and local TLS certificate, bootstrapped Argo CD, created Enterprise AppProjects, and registered both spokes (`cluster-spoke-nonprod` and `cluster-spoke-prod`) with 30-day TokenRequest credentials.
- **Result:** Exit code 0; control planes healthy and reachable.

### Step 3: `make bootstrap` (Root GitOps Application Deployment)
- **Action:** Applied `argocd-hub-deployer.yaml`, `projects/`, and `root-app.yaml`.
- **Result:** Exit code 0; `root-control-plane` Application created on Hub.

### Step 4: `make post-bootstrap` (Full Post-Bootstrap Reconciliation)
- **Action:** Executed all 9 post-bootstrap phases:
  - `[1/9]` Credential expiry verified: 29 days remaining on spoke and Headlamp tokens.
  - `[2/9]` Discovered tenant workloads (`orders-dev`, `orders-test`, `orders-prod`) and verified namespaces and `QueueBackedService` definitions.
  - `[3/9]` Verified SSO prerequisites: CoreDNS custom hash restarted, Keycloak Ready, lab TLS certificate applied.
  - `[4/9]` Provisioned CARM worker credentials (`orders-dev-aws`, `orders-test-aws` in account `111111111111`; `orders-prod-aws` in account `222222222222`).
  - `[5/9]` Reconciled workload worker pods with fresh secret credentials.
  - `[6/9]` Verified no orphaned credentials or namespaces.
  - `[7/9]` Argo CD adopted and self-managed from Git.
  - `[8/9]` All 42 Applications Synced & Healthy; both `TeamEKSCluster` claims (`team-data-analytics-dev` in `spoke-nonprod` and `team-data-analytics-prod` in `spoke-prod`) Ready=True.
  - `[9/9]` Full smoke test passed across all 12 stages.
- **Result:** Exit code 0.

---

## 3. Post-Rebuild Verification Results

### 3.1 Modular Bats Smoke Test Suite (`./scripts/smoke-test-hub-spoke-bats.sh`)
```text
============================================================
 Running Bats Smoke Test Suite: Bats 1.14.0
 Target: /home/bleite/repos/gitops-control-plane/tests/smoke
============================================================
01_infra_and_control_plane.bats
 ✓ Gate 1: Moto Cloud API is responding at http://localhost:5000 [24]
 ✓ Gate 2a: Hub cluster API is reachable [289]
 ✓ Gate 2b: All Argo CD core pods are Running [276]
 ✓ Gate 2c: Both spoke-nonprod and spoke-prod clusters are registered in Argo CD [277]
 ✓ Gate 4a: Spoke clusters APIs are reachable [646]
 ✓ Gate 4b: ACK SQS and Kro controllers are ready on both spokes [2969]
02_gitops_applications.bats
 ✓ Gate 3a: All expected 42 Argo CD applications exist [603]
 ✓ Gate 3b: All 42 Argo CD applications are Synced and Healthy [384]
 ✓ Gate 5: QueueBackedService instances are ACTIVE across dev, test, and prod [822]
 ✓ Gate 7: Workload pods are Running across non-prod and prod spokes [1078]
03_carm_and_workload_pipeline.bats
 ✓ Gate 6: All 6 SQS queues and DLQs exist in their designated CARM cloud accounts [4619]
 ✓ Gate 9: Orders flow end-to-end and are processed across dev, test, and prod [4888]
04_credentials_and_sso.bats
 ✓ Gate 8: Cluster and Headlamp credentials are valid and unexpired [1465]
 ✓ Gate 10a: OIDC issuer is identical from host and from argocd-server [355]
 ✓ Gate 10b: Argo CD advertises Keycloak SSO (PKCE) [28]
 ✓ Gate 10c: SSO entry points reach Keycloak login form [156]
 ✓ Gate 10d: Local platform-admin break-glass login succeeds [789]
 ✓ Gate 10e: Headlamp requires SSO and refuses cross-origin access [28]
05_supply_chain_admission.bats
 ✓ Gate 11a: Kyverno image verification policy tenant-images-signed is enforcing Deny [783]
 ✓ Gate 11b: Kyverno denies unsigned image and native VAP denies arbitrary unallowlisted image [7661]
 ✓ Gate 11c: Running signed workload image is admitted [14148]
06_observability.bats
 ✓ Gate 12a: Hub Prometheus receives scrape metrics from both spokes [647]
 ✓ Gate 12b: Synthetic HTTP blackbox probes are healthy [341]
 ✓ Gate 12c: Logs shipped from hub, spoke-nonprod and spoke-prod, and Loki is up [1371]
 ✓ Gate 12d: Team clusters analytics-dev and analytics-prod report ready in Prometheus [988]
 ✓ Gate 12e: No alerts persistently firing over 20 minutes [400]
 ✓ Gate 12f: Grafana SSO entry point reaches Keycloak login form [65]

27 tests, 0 failures in 47 seconds
```

### 3.2 Automated CI Validation Suites
- `make ci`: Passed (35 shell scripts shellcheck clean, 0 secret patterns, 42 applications rendered, 581 resources kubeconform valid, 21 alert rules valid, 2 dashboards valid).
- `make test-alert-rules`: Passed (`SUCCESS: 21 rules found`).
- `make ci-iac`: Passed (2 positive fixtures valid, 14 negative fixtures rejected as expected, manifests valid against `TeamEKSCluster` CRD schema).
- `make orphans`: Passed (`no orphaned credentials or namespaces`).

---

## 4. Scrape Timing Hardening (Cold-Start Resilience)

During cold-start rebuilds, Prometheus scrapes spoke probes on a 15–30s interval. Right after Kubernetes marks the `TeamEKSCluster` claims Ready, the very first Prometheus scrape of the newly spawned probe container on `spoke-prod` may occur a few seconds after the assertion begins.

To ensure deterministic pass on initial post-bootstrap executions without false negatives:
- Added a 60-second scrape wait loop in `scripts/smoke-test-hub-spoke.sh` (Gate 12d) and `tests/smoke/06_observability.bats` (Gate 12d) that polls Prometheus until the metric appears.
- Verified that both scripts exit with code 0.

---

## 5. Disposition & Recommendation

All exit criteria for **Phase P5** are now fully met with complete, reproducible live rebuild evidence.
We recommend **accepting P5**.
