# Phase 3 Implementation Report — Run #05: B.4 Argo CD self-management + PV3-11 (2026-10-01)

| | |
|---|---|
| **Plan** | [`2026-10-01-lab-remediation-plan-phase3.md`](2026-10-01-lab-remediation-plan-phase3.md) v1.0 (GREEN LIGHT) |
| **Preceded by** | [Implemented-04](2026-10-01-lab-remediation-plan-phase3-implemented-04.md) + addendum (L2-5), validated 🟢 in [Validation-04](2026-10-01-lab-remediation-plan-phase3-validation-04.md) for Track D (the L2-5 addendum `c98e429` is not yet validated) |
| **Scope executed** | **B.4** (stretch) and **PV3-11** (Validation-04 observation, D-27) |
| **Commits** | `orders-processor`: `a8137d9` · `gitops-control-plane`: `2da1094`, `cd0d788`, `5fa6c0a` |

## 1. Outcome Summary

| Item | Result |
|---|:-:|
| **PV3-11** CI overwrote `sha-<commit>` on release | ✅ `sha-*` is published only on branch builds; `v*` only on tag builds. Each tag is written once |
| **B.4** Argo CD self-management | ✅ Application `argo-cd` owns the installation; zero-disruption adoption; a Git-only values change was applied by Argo CD to itself |

## 2. Evidence

### PV3-11
* `ci.yaml`: `type=sha,…,enable=${{ github.ref_type == 'branch' }}`.
* Branch push `a8137d9` → GHCR published `sha-a8137d9` (~45 s).
* **Pending verification:** the tag-side behaviour (a `v*` push publishes no `sha-*`) is observable only at the next release.

### B.4
| Check | Result |
|---|---|
| Live Helm values vs Git values file before adoption | identical (rev 14) |
| `argo-cd` Application safety | **no finalizer**, `prune: false`, **manual sync** (by design), ServerSideApply |
| Pre-sync review | 62 resources, 59 OutOfSync (tracking only), **0 non-tracking diff lines**; 3 "requires pruning" = the chart's `redis-secret-init` ServiceAccount/Role/RoleBinding, which are Helm `pre-install,pre-upgrade` hooks (Argo CD runs them as PreSync hooks; not deleted because prune is off) |
| First manual sync | Succeeded; **Argo CD pods unchanged (no restart)**; Redis password unchanged; `argocd-secret` keys intact (5); `platform-admin` and `tenant-a` logins OK |
| **Acceptance: Git-only change** | `ui.bannercontent` added to `clusters/values-argocd-hub.yaml` (`cd0d788`): app OutOfSync, live unchanged → manual sync → `argocd-cm` updated, `argocd-server` rolled, **banner served by the authenticated settings API**. (The unauthenticated `/api/v1/settings` omits the banner by design; my first check queried that and returned `null`.) |
| Helm | 10 release records removed; `helm list -n argocd` empty |
| Durability | `setup-hub-spoke.sh` installs Argo CD only when absent and then removes the Helm record (same pattern as Traefik, D-12); the values file header documents "commit, then sync argo-cd as platform-admin; Helm only as break-glass" |
| Regression | 18/18 Applications Synced/Healthy (incl. `argo-cd`); all clusters Successful; R-1 audit PASS; smoke test exit 0 |

## 3. Notes

| ID | Note |
|---|---|
| D-32 | Argo CD self-management uses **manual sync** on purpose: a bad values commit cannot auto-apply and lock the control plane out of itself. A change to Argo CD needs a reviewed commit plus an explicit sync. Break-glass: the pinned `helm upgrade --install` documented in `applicationsets/argo-cd.yaml`. |
| D-33 | The reviewer's `validation-03.md` and `validation-04.md` are present in the working tree but not committed (owner's documents; left untouched). |

## 4. Phase 3 Remaining

| Item | Status |
|---|---|
| **B.7** full rebuild acceptance | **Needs explicit owner approval** (destroys live lab state; Git/GHCR unaffected) |
| Validation of the L2-5 addendum (`c98e429`) and this report | Reviewer |
| 0.3 / 0.4 GitHub branch protection, GHCR cleanup | Owner UI actions |
| Credential rotation | Before **2026-10-31 07:19 UTC** |
