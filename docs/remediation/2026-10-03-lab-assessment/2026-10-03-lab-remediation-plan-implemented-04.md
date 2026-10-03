# Implementation Report 04 — Track A: CI and Change Control (2026-10-03)

> **Status: Current.** Active remediation record for the 2026-10-03 assessment.

| | |
|---|---|
| **Implements** | [Remediation plan v1.0](2026-10-03-lab-remediation-plan.md) Track A (L2-4): **A.1** `gitops-control-plane` CI, **A.2** `tenant-workloads` CI, **A.3** `platform-catalog` CI, **A.4** required checks per O-1 + lab alert per O-3; review remark **R-3**; also closes validation-01 **V-9** |
| **Executed by** | Claude (Opus 5.5), owner's assignment. **To be validated by** Antigravity, independent of the execution |
| **Commits** | `gitops-control-plane` `e21b024`, `cb5beb5`, `f1c6480`, `11bf637`, `c7781c6`, `88b1eb9`/`d563476` (alarm self-test, net zero), `6a16f0c`; `tenant-workloads` `f07d3cf`, `bf67915`, `4e0daf4`; `platform-catalog` `e2a96e9`, `28ec3d2`, `3fe896f`; `platform-charts` `3d7f097`, `ee8b492`, `a968e52`, `dcd58aa` |
| **Owner action pending** | **A.4 rulesets** on `tenant-workloads` and `platform-charts` (§5). The lab has no GitHub credentials by design |
| **Date** | 2026-10-03 |

---

## Summary

| Step | Result |
|---|---|
| **A.1** | `ci/check-control-plane.sh` (`make ci`, job `control-plane-checks`) renders **all 32 Applications offline exactly as the hub has them**, checked field by field against the live Applications. It renders every source, then runs kubeconform with lab CRD schemas, promtool (19 rules), the dashboards check, shellcheck, the secret scan and the Alloy syntax check. Green in 106 s on GitHub |
| **A.2** | Registration JSON Schema in `tenant-workloads` and uniqueness, file naming and values file at `valuesRevision` checks. A **render of the real tenant ApplicationSet with the PR's registrations** (same guards, `missingkey=error`), then chart render and kubeconform. Job `registration-checks`, 41 s |
| **A.3** | CEL of both VAPs **compiled with the Kubernetes CEL compiler**; Kyverno and kro CEL parsed. RGD schema compatibility with the prod tag (D-14). All 14 catalog-using Applications rendered for both spokes from the commit under test; kubeconform; Alloy; secret scan. Job `catalog-checks`, 67 s |
| **A.4** | `platform-charts` CI: lint and render with the real values, kubeconform against the QueueBackedService contract, and the release rule without pushing. Job `chart-checks`, 32 s. A red run on any `main` also raises the lab alert **`CIFailingOnMain`**, proven end to end. The required-check rulesets are an **owner action** (§5) |
| Proof | **4 real red runs** on GitHub (one per repo, `ci-selftest/*` branches, reasons visible as annotations) plus 15 local negative cases. All checks green on `main` in every repo |
| Regression | 32/32 Synced/Healthy · smoke 12/12 · impersonation audit PASS · alert tests SUCCESS (19 rules) · 0 firing · GHCR `1.0.0` digest unchanged |

---

## 1. The toolkit (`gitops-control-plane/ci/`, see [`ci/README.md`](../../../ci/README.md))

One implementation, used by `make ci*` locally and by the four workflows. The other repos' workflows check out `gitops-control-plane` `main` for it, and `/ci/` is in CODEOWNERS.

| Part | What it does | Why |
|---|---|---|
| `labci appsets` (Go) | Renders Applications and ApplicationSets like the ApplicationSet controller: clusters / list / matrix / Git-files generators, goTemplate with sprig (minus `env`, `expandenv`, `getHostByName`), `missingkey=error`, every string value of `spec.template` rendered, duplicate names rejected. Cluster input `ci/clusters.yaml`, whose labels are checked against `register-spokes.sh` | A YAML or kubeconform check alone cannot see a template failure. That failure is exactly what froze the tenant ApplicationSet (L2-3) |
| `labci cel` (Go, `k8s.io/apiserver` v0.35) | VAP variables, validations, messageExpressions, auditAnnotations and matchConditions compiled with the API server's **CompositedCompiler** in the 1.35 base environment, including result types. Kyverno `policies.kyverno.io` expressions and kro `${…}` are parsed | "Server-free CEL check" (plan). Compiling with types goes beyond a syntax check |
| `render.py` | Each source rendered like the repo-server: `helm template` (HTTP or OCI, releaseName, namespace, `$values` at the ref's revision, valuesObject, `--include-crds`, `--kube-version 1.35.0`), `kustomize build`, or a directory (include/exclude with `{a,b}`). The repo under test is used as is; other repos are fetched at the exact revision named | Renders exactly what would be deployed: the prod catalog tag, the prod `valuesRevision` |
| `schemas/` (95 schemas, 66 CRDs) | Generated from the lab's own CRDs by `update-crd-schemas.py` (`make ci-schemas`): Argo CD, Traefik, kro (including the generated **QueueBackedService**), Kyverno, ACK. int-or-string handled; a field the API server defaults is not required | **R-3**: no false positives; versions match the lab |
| kubeconform | Built-in kinds from `yannh/kubernetes-json-schema` at a **pinned commit** for 1.35.0; custom kinds from `schemas/`. Missing schemas are errors, **except** `CustomResourceDefinition` objects (vendor CRDs shipped in charts; 82 skipped) | |
| `secret-scan.py` | Private keys, AWS key IDs, GitHub/Slack tokens, JWTs, bcrypt, kubeconfig credentials, inline password-like values. Prints only file:line and the pattern name; marker `lab-ci: not-a-secret` | The X22 pattern set, applied to Git |
| `check-rgd-schema.py` | RGD `spec.schema` against the revision prod runs: spec field changed or removed → fail; new field → reported; status expression changed → reported | Phase 3 D-14 (kro refuses breaking CRD updates) |
| `check-registrations.py` + `tenant-workloads/schema/registration.schema.json` | Schema, file naming `<app>-<env>.yaml`, `tenant` = directory, uniqueness, values file at `valuesRevision` (fetch fails → bad SHA) | A.2 |
| Pins | Images by digest in `ci/tools.env` (helm 3.19.0, kustomize 5.7.1, kubeconform 0.7.0, shellcheck 0.11.0, the lab's own Prometheus and Alloy images); Actions by SHA (checkout v7.0.1, setup-go v7.0.0, setup-python v7.0.0, all node24); Python wheels by hash (`ci/requirements.txt`); Go by `go.sum` | Plan: "pin Actions by SHA and use digest-pinned tool images" |
| Annotations | In GitHub Actions every `✘` line also becomes an `::error::` annotation | The reason for a red check is visible on the PR or commit without the authenticated job log |

**Render faithfulness (verified against the hub).**
* All 32 Applications produced offline have the same names as the live ones.
* `source(s)`, `destination`, `project` and `syncPolicy` are identical (0 differences).
* Each Application's rendered object set equals Argo CD's managed resources, except Helm hook objects (Kyverno's 2 cleanup Jobs plus their ClusterRole and ClusterRoleBinding, and Argo CD's `redis-secret-init` Job), which Argo CD runs as hooks and does not list.

## 2. Per-repo checks and evidence

### A.1 `gitops-control-plane` — `control-plane-checks`
Stages: `shell`, `secrets`, `fixtures`, `render`, `schemas`, `alert-rules`, `dashboards`, `alloy`.
* **First run:** `37112346103` (`cb5beb5`), success in 1 min 52 s, cold runner.
* **Latest:** `37114313191` (`6a16f0c`), success.
* **Output:** 412 resources from 32 Applications: 330 valid, 0 invalid, 82 CRDs skipped. 19 rules; promtool tests SUCCESS.

**Findings while building, fixed in `e21b024`:**
* 2 shellcheck warnings: unused `REPOS_DIR` in `setup-hub-spoke.sh` and `SCRIPT_DIR` in `setup-observability-secrets.sh`.
* **3 full moto access key IDs** in the historical Phase 3 `validation-04` report. They are masked in the current file. Git history keeps them. They were moto mock IAM keys, wiped by the moto restarts since (most recently Drill 1 today).

### A.2 `tenant-workloads` — `registration-checks`
* **Schema decisions (deviations from the plan's wording, made deliberately):**
  * `app` pattern is `^(orders|tenant)(-[a-z0-9]+)*$`. The plan's `orders-[a-z0-9-]+` would reject today's `app: orders`. The chosen pattern is exactly what the AppProject destinations (`orders-*`, `tenant-*`) admit as `<app>-<env>`.
  * `port` must be `"8081"` for dev/test and `"8082"` for prod: the spoke ingress host ports.
  * `additionalProperties: false`.
* **Runs:** `37112482794` (`f07d3cf`) success; latest `37113206526` (`4e0daf4`) success in 41 s.

### A.3 `platform-catalog` — `catalog-checks`
* CEL: `tenant-image-registry-allowlist` and `queuebackedservice-contract` compiled, `tenant-images-signed` and the RGD parsed.
* RGD schema compatible with `v1.7.2`.
* 14 Applications rendered for both spokes from the tree under test.
* kubeconform: 214 resources, 160 valid, 0 invalid. Alloy parses.
* **Runs:** `37112484544` success; latest `37113207812` (`3fe896f`) success in 67 s.

### A.4 `platform-charts` — `chart-checks` (+ the existing release workflow)
* **lint:** with the 4 real values files of `orders-processor` (dev, test, prod, the Drill 5 demo), instead of `image=placeholder`.
* **render:** QueueBackedService ×4, valid against the kro-generated CRD schema.
* **release:** `1.0.0` identical to GHCR, so the release would skip.
* **Runs:** `37112483571` success; latest `37113209635` (`a968e52`) success in 32 s.
* **V-9:** `release.yaml` Actions moved to node24 majors by SHA (`dcd58aa`). Release run success (skip path) with no Node 20 warning. GHCR `1.0.0` stays `sha256:4668c360…25bd`.

## 3. Negative tests

### Real GitHub runs (branches `ci-selftest/*`, deleted afterwards; Argo CD and the release workflow follow only `main` and tags)
| Repo / branch | Change | Run | Result and annotation |
|---|---|---|---|
| `tenant-workloads` `ci-selftest/drill5-v1-format` | the v1.0 Drill 5 registration (`name/environment/cluster/namespace`) | `37112732725` | ❌ `orders-demo.yaml: (root): Additional properties are not allowed…`, `'tenant' is a required property` …, **and** `ApplicationSet tenant-workloads: template: … map has no entry for key` (the freeze the hub would have) |
| `platform-charts` `ci-selftest/no-version-bump` | template comment, version not bumped | `37112734129` | ❌ `queue-backed-service:1.0.0 is already released with different content: bump version` |
| `platform-catalog` `ci-selftest/rgd-breaking-change` | `environment: string \| enum=…` (the D-14 change) | `37112735831` | ❌ `RGD queuebackedservice: schema.spec.environment changed 'string' -> 'string \| enum="dev,test,prod"' (breaking for kro; prod at v1.7.2)` |
| `gitops-control-plane` `ci-selftest/appset-template-typo` | `{{ .targetNamespce }}` in `addons-spoke.yaml` | `37112731148` | ❌ `ApplicationSet addons-spoke: template: … executing "" at <.targetNamespce>` |

### Local (scratch copies)
* **Registrations:**
  * unknown fields → rejected;
  * prod on a branch → `does not match '^[0-9a-f]{40}$'`;
  * prod port 8081 → `'8082' was expected`;
  * `app: billing` → pattern;
  * file name mismatch → rejected;
  * duplicate `orders-dev` → `already registered`;
  * missing `valuesFile` → `does not exist in orders-processor at main`;
  * unknown prod SHA → `not found in orders-processor`;
  * valid demo registration → passes.
* **CEL:**
  * missing `)` → syntax error;
  * `containers.map(...)` → `must evaluate to bool but got list(dyn)`;
  * `objekt.` → undeclared reference;
  * broken `${… +}` in the RGD → parse error.
* **kubeconform:** `replicas: "two"` in a Deployment → invalid; QueueBackedService `replicas: "abc"` → invalid.
* **RGD lint:** a new optional field is reported as additive and passes.
* **Secret scan:** a password-like value, an inline `client_secret`, an `AKIA…` key ID and an `aws_secret_access_key` line are all flagged. `existingSecret: <name>`, `${VAR}` and `mock-…` values are not.

## 4. A.4 lab alert (O-1 post-push alarm, O-3 lab-local)
* **`monitoring/ci-status-exporter`** (`addon-lab-exporters`):
  * Polls the public GitHub API every 10 min for the latest completed run of each workflow on `main`, for all 5 repos (6 workflows, including `orders-processor` "CI Pipeline" and the chart release).
  * Requests are conditional (ETag; 304s do not count against the 60/h unauthenticated limit).
  * Hardening: non-root, read-only root filesystem, no ServiceAccount token, the same digest-pinned Python image as the other exporter.
  * NetworkPolicy: ingress only from Prometheus; egress only DNS and TCP 443 to public addresses.
  * Metrics: `lab_ci_run_success{repo,workflow,sha}`, `lab_ci_run_timestamp_seconds`, `lab_ci_poll_success`, `lab_ci_poll_timestamp_seconds`, `lab_ci_github_rate_limit_remaining`.
* **Rules** (group `lab.ci`):
  * **`CIFailingOnMain`**: `max by (repo, workflow) (lab_ci_run_success) == 0`, for 5 min. A new red commit does not reset the timer.
  * **`CIStatusUnknown`**: poll missing, stale for over 1 h, or failing, for 30 min.
  * Both have promtool unit tests (19 rules total) and a runbook section (`#alert-cifailingonmain--cistatusunknown`).
* **End-to-end proof on `main`** (`ci/selftest-red.sh` with an SC2034 warning: CI goes red, nothing is deployed):

  | Time (UTC) | Event |
  |---|---|
  | 09:28:29 | red commit `88b1eb9` pushed |
  | 09:30:44 | run `37113168278` failure |
  | 09:38:44 | `CIFailingOnMain[gitops-control-plane/CI]` pending (next poll) |
  | 09:43:36 | **firing** |
  | 09:43:38 | revert `d563476` pushed |
  | 09:47:25 | run success |
  | 09:48:43 | alert cleared |

* **Workflow concurrency (`6a16f0c` and siblings):** runs on `main` are **never cancelled**. Each commit keeps its own verdict, which an alarm needs: `c7781c6`'s run had been cancelled by the next push. Superseded PR runs are still cancelled.

## 5. Owner action — required checks (O-1 mixed mode)
`main` on both repos is protected by a **ruleset** today: `deletion` and `non_fast_forward` (public `GET /repos/brunobml/<repo>/rules/branches/main`). In GitHub → *Settings → Rules → Rulesets → (the `main` ruleset)*, add:

| Repo | Add rule | Setting |
|---|---|---|
| `tenant-workloads` | **Require a pull request before merging** | required approvals **0** (a single maintainer cannot approve their own PR); keep CODEOWNERS for visibility |
| | **Require status checks to pass** | `registration-checks` (source: GitHub Actions); "require branches to be up to date": on |
| `platform-charts` | **Require a pull request before merging** | approvals 0 |
| | **Require status checks to pass** | `chart-checks` (source: GitHub Actions); "up to date": on |

* **Bypass:** keep the owner (admin) as a bypass actor for emergencies only; record any use (plan risk table).
* **Other repos** (`gitops-control-plane`, `platform-catalog`, `orders-processor`) stay direct-push. Their CI on `main` is the alarm.
* **After the change:** the playbook's Drill 5 and tenant promotions go through a PR. The playbook already says so (`6a16f0c`).
* **Verification by anyone, no token:** `curl -s https://api.github.com/repos/brunobml/<repo>/rules/branches/main | jq -c '[.[]|{type, parameters}]'` must list `pull_request` and `required_status_checks` with the context above. Optionally, open a PR from a branch with a broken registration: merge must be blocked.

Until the owner applies this, **V-7 stays open**: direct pushes to `tenant-workloads` and `platform-charts` are still possible, although every push is now checked and alarmed.

## 6. Notes for the validator
* **Toolkit trust:** the `tenant-workloads` and `platform-charts` required checks run `gitops-control-plane/ci` from `main` (CODEOWNERS `/ci/`). A change there can affect their gate, and its own CI tests the toolkit first.
* **Schema refresh:** `ci/schemas/` must be regenerated (`make ci-schemas`) when Argo CD, Traefik, kro, Kyverno or ACK are upgraded; a missing schema fails loudly.
* **Rate limit:** the CI-status exporter and anything else on the host share GitHub's 60 unauthenticated calls per hour. It makes 30 conditional calls per hour (5 repos every 10 min); 304 responses are free, so only a repo with a new run costs a call. `lab_ci_github_rate_limit_remaining` is exported.
* **Scope of the checks:**
  * kubeconform is not a server dry run (no admission, no CRD defaulting beyond "required with default");
  * `object` in VAP CEL is untyped (no OpenAPI schema), so a typo in a field *inside* `object` is not caught;
  * `alloy fmt` checks syntax, not layout.
* **Suggested checks:**
  * `make ci`, `make ci-tenants`, `make ci-catalog`, `make ci-charts`;
  * re-run one negative test (e.g. a `ci-selftest/*` branch with a bad registration);
  * the hub's `lab_ci_run_success` series;
  * after the owner action, the public `rules/branches/main` of both repos.

## 7. Track A status
| Step | Status |
|---|---|
| A.1 | 🔧 Done, green on `main`. **Awaiting validation-04** |
| A.2 | 🔧 Done, green on `main`. **Awaiting validation-04** |
| A.3 | 🔧 Done, green on `main`. **Awaiting validation-04** |
| A.4 | 🔧 Checks, alarm and lab alert done. ⏳ **Owner: rulesets (§5)**, then V-7 can close |
| V-9 | 🔧 Done (`dcd58aa`). **Awaiting validation-04** |
