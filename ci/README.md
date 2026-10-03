# Lab CI toolkit

> **Status: Current.** Track A of the [2026-10-03 remediation plan](../docs/remediation/2026-10-03-lab-assessment/2026-10-03-lab-remediation-plan.md).

One set of checks for the GitOps repositories, run the same way **locally** (`make ci*`) and in **GitHub Actions** (`.github/workflows/ci.yaml` of each repo). All tools are pinned:
* container images by digest, in [`tools.env`](tools.env): helm, kustomize, kubeconform, shellcheck, promtool and alloy;
* Actions by commit SHA;
* Python packages by hash, in [`requirements.txt`](requirements.txt);
* Go modules by `go.sum`.

| Repo | Command | Workflow job (status check) | O-1 role |
|---|---|---|---|
| `gitops-control-plane` | `make ci` → `check-control-plane.sh` | `control-plane-checks` | post-push alarm |
| `tenant-workloads` | `make ci-tenants` → `check-tenant-workloads.sh` | `registration-checks` | **required** for PRs |
| `platform-catalog` | `make ci-catalog` → `check-catalog.sh` | `catalog-checks` | post-push alarm |
| `platform-charts` | `make ci-charts` → `check-charts.sh` | `chart-checks` | **required** for PRs |

The other repos' workflows check out this repository's `main` for the toolkit and the ApplicationSets. `/ci/` is owned in CODEOWNERS.

## Building blocks
* **`labci`** (Go, [`labci/`](labci/)):
  * `labci appsets` renders Applications and ApplicationSets **offline, like the ApplicationSet controller**: clusters, list, matrix and Git-files generators; goTemplate with sprig; `missingkey=error`. Cluster generator input is [`clusters.yaml`](clusters.yaml); its labels are checked against `scripts/register-spokes.sh`. Verified against the hub: the 32 rendered Applications equal the 32 live ones (source, destination, project, sync policy).
  * `labci cel` compiles the CEL of ValidatingAdmissionPolicies with the **Kubernetes CEL compiler and environment** (`k8s.io/apiserver`, 1.35), including result types and variables. It parses Kyverno CEL policies and kro `${…}` expressions.
* **[`render.py`](render.py)** renders each Application's sources the way the repo-server does:
  * `helm template`, with `$values` resolved at the ref source's revision;
  * `kustomize build`;
  * plain directories, with include/exclude globs.

  The repo under test is used as-is. Other repositories are fetched at the exact revision each Application names: prod catalog tag, tenant `valuesRevision`.
* **kubeconform** validates against the pinned upstream schemas for Kubernetes 1.35, plus [`schemas/`](schemas/): CRD schemas generated from the lab by [`update-crd-schemas.py`](update-crd-schemas.py) (`make ci-schemas` after upgrading Argo CD, Traefik, kro, Kyverno or ACK; review remark R-3). Missing schemas are errors, except for `CustomResourceDefinition` objects themselves.
* **[`secret-scan.py`](secret-scan.py)** looks for credential patterns in tracked files and never prints the match. Mark a deliberate placeholder line with `lab-ci: not-a-secret`.
* **[`check-rgd-schema.py`](check-rgd-schema.py)**: an RGD spec field changed or removed against the revision prod runs fails the check. kro refuses such changes (Phase 3 D-14).
* **[`check-registrations.py`](check-registrations.py)** checks tenant registrations against `tenant-workloads/schema/registration.schema.json`, plus file naming, uniqueness and that the values file exists at `valuesRevision`.

## Running a single stage
```bash
ci/check-control-plane.sh render schemas     # stages: shell secrets fixtures render schemas alert-rules dashboards alloy
LAB_CI_OUT=/tmp/ci make ci                   # keep the rendered manifests for inspection
```
