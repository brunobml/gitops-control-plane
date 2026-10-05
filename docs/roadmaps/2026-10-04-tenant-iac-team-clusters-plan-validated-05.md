# Tenant IaC plan v0.3: P3 validation report (validated-05)

> **Status: Independent validation (2026-10-05 UTC).** Validator: Claude (Opus 5.5). Executor: Antigravity. Report under review: [implemented-04](2026-10-04-tenant-iac-team-clusters-plan-implemented-04.md). Commits: `tenant-iac` `084c23f`, `gitops-control-plane` `1dd2046` (+ report `3c2eab7`), ruleset `24519842`.
>
> Changes I made during validation: one **empty** commit pushed directly to `tenant-iac` `main`, which was refused (local reset to `origin/main` afterwards). All other tests ran on a temporary copy of the repo in my scratch directory. Nothing else was changed.

## Verdict: 🟡 YELLOW: P3 exit gate met; one required fix before P4

The P3 exit gate in plan §6 is met: negative fixtures fail, positive ones pass, and a direct push to `main` is refused. But the ApplicationSet template delivered with P3 renders a **wrong values path** (V-1). The plan's CI rule that would have caught it ("render through the real ApplicationSet template + chart", §4) is not implemented. Fix both before P4 deploys the template.

## 1. Verified

| # | Check | Result | Evidence |
|---|---|---|---|
| 1 | Repository | ✅ | `brunobml/tenant-iac` public, `main` = `084c23f`, 21 tracked files: README, `teams/README.md`, `schema/cluster.schema.json`, CODEOWNERS, CI workflow, 2 positive + 14 negative fixtures |
| 2 | Ruleset `24519842` | ✅ | `active`, target `~DEFAULT_BRANCH`, no bypass actors (`current_user_can_bypass: never`), deletion + non-fast-forward blocked, **required check `cluster-checks` from GitHub Actions** (integration 15368), PR required with **0 approvals and no code-owner review**, the same as `tenant-workloads` (24430390) |
| 3 | Direct push refused | ✅ | Empty commit → `GH013 … Required status check "cluster-checks" is expected … Changes must be made through a pull request`, `[remote rejected]` |
| 4 | Schema vs admission policy | ✅ | Same rules as `teamekscluster-contract`: team/name DNS label 2–20 with no trailing dash (equivalent patterns), env, versions 1.32–1.34, `platform-default`, instance types, max 3 (dev/test) / 5 (prod), plus `additionalProperties: false` and the min ≤ desired ≤ max check in the validator. The namespace rule is covered by team = directory, and the template derives the namespace |
| 5 | `make ci-iac` | ✅ | claims (0 live), fixtures **2/2 positive, 14/14 negative**, render, kubeconform 2/2, secret scan **21** tracked files (the report says 1) |
| 6 | Live-claim rules (temp copy; no fixtures cover them) | ✅ | Rejected: team ≠ directory, file name ≠ `<name>-<env>.yaml`, 6th and 7th cluster of a team (limit 5), schema-invalid live claim (`1.31`), broken YAML. A valid live claim `teams/team-data/clusters/analytics-dev.yaml` passes all stages (rendered + kubeconform) |
| 7 | Remote CI | ✅ | Run `37350898680`: push on `main` `084c23f`, `cluster-checks` success; the test PR (#1, closed) ran `cluster-checks` on `pull_request`: success |
| 8 | Lab | ✅ | Control-plane CI green on `1dd2046` and `3c2eab7`; 40/40 Argo CD apps Synced/Healthy |

## 2. Findings

| # | Severity | Finding | Evidence | Action |
|---|---|---|---|---|
| **V-1** | **Required before P4** | **`scripts/templates/tenant-iac-appset.yaml` sets `valueFiles: '$values/{{ .path }}'`.** In goTemplate mode the git files generator's `.path` is an object (`path`, `basename`, `filename`, …), not a string. Every generated Application would point at a nonexistent values file. The plan's CI rule "render through the real ApplicationSet template + chart" (§4) is not implemented: `check-tenant-iac.sh` renders claims straight through the chart, so this passed CI | Offline render with `labci appsets` (the toolkit's Argo CD-compatible renderer), a temp copy with `teams/team-data/clusters/analytics-dev.yaml` and `scripts/tenant-iac-appset.sh team-data`: `valueFiles: - $values/map[basename:clusters basenameNormalized:clusters filename:analytics-dev.yaml …` | Use `'$values/{{ .path.path }}/{{ .path.filename }}'`. Add a CI stage that renders each team's ApplicationSet with `labci appsets` against the tenant-iac checkout, then renders each generated Application (chart + `$values` file, `ci/render.py`) and runs kubeconform. That is the plan §4 rule, and the same pattern as the `tenant-appsets` stage |
| V-2 | Minor (docs) | `tenant-iac/README.md` (l. 40–42, 89) and `teams/README.md` (l. 39) say prod claims **require** CODEOWNERS approval and that it is "enforced". The ruleset has 0 approvals and no code-owner review, so CODEOWNERS only *requests* a review. That is deliberate in a single-user lab (GitHub forbids approving your own PR) and matches `tenant-workloads`, but the docs overstate it | ruleset JSON above | Correct the wording: the prod gate is PR + required check; CODEOWNERS requests review |
| V-3 | Observation | `check-clusters.py` rejects the same `<name>-<env>` in two different teams. After P0 F-1, AWS names and Application names are `<team>-<name>-<env>`, so this is no longer needed. It matches the plan's §4 wording, so it is not a defect | temp copy: `team-web/clusters/analytics-dev.yaml` rejected as "already registered by teams/team-data/…" | Owner's call. I'd relax it to per-team uniqueness (the file name already guarantees that) |
| V-4 | Minor (report accuracy) | implemented-04 says the secret scan saw "1 tracked files" (it sees 21) and that the ruleset requires "PR review" (0 approvals) | items 2 and 5 | none beyond V-2 |

## 3. Next
- **V-1** (template fix + ApplicationSet render stage) back to the executor; I re-validate it. P4 should not deploy `tenant-iac-<team>` ApplicationSets before that.
- V-2 with the same change; V-3 on the owner's word.
