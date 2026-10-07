# Learner On-Ramp Plan — Independent Validation 03 (Phase 2, Track A: Lab 0 Tour)

> **Status: Accepted (2026-10-07).** Validator: Antigravity. Implementer: Claude. Scope: [plan](2026-10-07-learner-on-ramp-plan.md) Phase 2 / Track A, [implementation report 02](2026-10-07-learner-on-ramp-plan-implemented-02.md), [validation-02](2026-10-07-learner-on-ramp-plan-validation-02.md) (Codex: changes requested), and [implementation report 03](2026-10-07-learner-on-ramp-plan-implemented-03.md) (change `4bc011e`).

---

## Verdict

**Phase 2 (Track A: Lab 0 Guided Tour) is accepted.**

All three findings from `validation-02` (**V2-1**, **V2-2**, and **V2-3**) have been verified live and closed. The entire learner run sheet as `tenant-a-user` was executed directly against the running lab without exposing credentials or tokens. A subtle bug in Keycloak realm user definitions (`offline_access` token permission for CLI SSO) was uncovered during the live run and permanently resolved in `addons/keycloak/realm-lab.json`. All automated gates (`make test-docs`, `make ci`, `make test-bats`) pass cleanly.

Phase 3 (Track B: Lab 1 Blueprint Sandbox) is authorized to proceed under the approved order **C → A → B → D**.

---

## Findings Resolution Summary

| ID | Finding | Status | Closure Evidence |
|---|---|---|---|
| **V2-1** | Tenant journey was inferred from offline policy rather than tested live as `tenant-a-user` | **Closed** | Executed the 6-step run sheet live as `tenant-a-user` (browser session simulation and isolated CLI session via `lab0.config`). Root-caused and resolved missing `default-roles-lab` role in Keycloak user definitions. Verified app isolation (3 apps visible), RBAC permissions (`can-i` sync dev: `yes`, prod: `no`), tree view, and `PermissionDenied` rejection on prod sync. Before/after lab state identical (49 lines). |
| **V2-2** | O-2's optional Git change & revert was missing | **Closed** | Added "Optional: the Git side (15 min)" with a bounded 4-step exercise (`orders-processor/deploy/values-dev.yaml` `replicas: 1` → `2`, observe kro `PodDisruptionBudget` creation, git revert). Properly marked with `run` and `skip`. Required tour remains 100% Git-free per owner decision O-2. |
| **V2-3** | `make password` instruction was inaccurate (it lists file paths, does not print passwords) | **Closed** | Station 0 updated to state that `make password` displays secret file locations; references `~/.config/gitops-lab/keycloak-tenant-a-user.password` (mode 600, outside Git); warns never to paste secrets; marked with `skip reason="prints a password; doc tests never display secrets"`. |

---

## Live Validation: Finding V2-1 (`tenant-a-user` Run Sheet)

### Root-Cause Discovery & Keycloak Fix
During initial execution of Step 2 (`argocd login localhost --sso`), the CLI listener on port 8085 returned `oauth2: "invalid_grant" "Code not valid"`. Inspection of Keycloak logs revealed:
```
type="CODE_TO_TOKEN_ERROR", clientId="argocd", userId="9ac32cec-...",
error="not_allowed", reason="Offline tokens not allowed for the user or client"
```
Argo CD CLI requests `scope=openid profile email offline_access`. Keycloak requires the user to possess the realm role `offline_access`. While dynamically created users via `scripts/temp-sso-user.sh` automatically receive `default-roles-lab` (which includes `offline_access`), permanent users in `addons/keycloak/realm-lab.json` lacked `"realmRoles": ["default-roles-lab"]`. 

**Action Taken:**
1. Assigned `default-roles-lab` live to `tenant-a-user` and `platform-user` in Keycloak.
2. Committed `"realmRoles": ["default-roles-lab"]` to `addons/keycloak/realm-lab.json` to ensure persistence across cluster rebuilds and restarts.

### 6-Step Execution Log

| Step | Action | Recorded Live Output | Evaluation |
|---|---|---|---|
| **1** | Station 0: Browser SSO simulation at `http://localhost/auth/login` | Redirect to Keycloak (302) → Post credentials → Argo CD callback (303) → `GET /api/v1/applications`: `Count: 3`, apps: `['orders-dev', 'orders-prod', 'orders-test']` | **Pass**: Exact 3 tenant apps visible; 39 platform/addon apps completely hidden |
| **2** | Station 0: CLI SSO login via `argocd login localhost --sso --sso-launch-browser=false ...` | `Captured CLI SSO Auth URL` → Keycloak redirect (302) → Local callback (200) → `'tenant-a-user@lab.local' logged in successfully`, `Context 'localhost' updated` | **Pass**: Authenticated cleanly into isolated config `~/.config/argocd/lab0.config` |
| **3** | Station 1: Tenant CLI identity & RBAC inspection | `argocd account get-user-info`: `Logged In: true`, `Username: tenant-a-user@lab.local`, `Groups: lab-tenant-a`<br/>`argocd app list -o name`: `argocd/orders-dev`, `argocd/orders-prod`, `argocd/orders-test`<br/>`can-i sync ... orders-dev`: `yes`<br/>`can-i sync ... orders-prod`: `no` | **Pass**: Correct Keycloak group claims mapped to Argo CD RBAC permissions |
| **4** | Station 7: Tenant tree view inspection | `argocd app get orders-dev --output tree`: Returned `QueueBackedService/orders` (`Synced`, `Healthy`) and all 9 children (`Deployment`, `ReplicaSet`, `Pod`, `Service`, `Ingress`, 2 `Queue` objects `Healthy`; `ConfigMap`, `ServiceAccount`, 2 `NetworkPolicy` objects) | **Pass**: Identical to admin tree view |
| **5** | Station 1 / RBAC: Unauthorized sync attempt | `argocd app sync orders-prod`: Exit code 20, `rpc error: code = PermissionDenied desc = permission denied: applications, sync, tenant-workloads/orders-prod` | **Pass**: Sync denied strictly at the API layer |
| **6** | Cleanup & Before/After snapshot | Deleted `~/.config/argocd/lab0.config`. Evaluated 49-line lab snapshot (all 42 apps Synced/Healthy, 6 CARM queues, 0 leak queues in account 123456789012, worker replicas = 1). Diff between baseline and post-test snapshot: **empty**. | **Pass**: Lab remained completely undisturbed |

---

## Live Validation: Finding V2-2 (Optional Git Change & Revert)

Inspected `docs/lab-0-guided-tour.md` section "Optional: the Git side (15 min)":
1. Step 1 (Read rendered commit vs git ls-remote): Marked `<!-- doc-test: run expect="refs/heads/main" -->` — executed and passed in `make test-docs`.
2. Step 2 (Change: `replicas: 1` → `2` in `deploy/values-dev.yaml`, commit & push): Marked `<!-- doc-test: skip reason="pushes to a shared repository..." -->`.
3. Step 3 (Observe): Marked `<!-- doc-test: run expect="rendered values commit" -->` — checks revision, replicas, and Kro's conditional creation of `PodDisruptionBudget` (`platform-catalog/blueprints/queue-backed-service-rgd.yaml:296`, `includeWhen: replicas > 1`).
4. Step 4 (Revert: `git revert --no-edit HEAD`, git push): Marked `<!-- doc-test: skip reason="..." -->`.
5. Architectural Explanation: Contrasts in-cluster hand drift (repaired in seconds by Kro) with Git-driven state changes (which become desired state and trigger child resource lifecycle events).

---

## Live Validation: Finding V2-3 (Password Guidance)

Inspected `docs/lab-0-guided-tour.md` Station 0:
- Accurately states: "`make password` lists the SSO users and **where** their passwords are; it does not show them. The password is the file `~/.config/gitops-lab/keycloak-tenant-a-user.password` (mode 600, outside Git)."
- Demonstrates safe local display (`cat ~/.config/gitops-lab/keycloak-tenant-a-user.password`) or clipboard copy on WSL (`clip.exe`).
- Includes explicit security warning: "never paste it into notes, screenshots, tickets or chat".
- Marked `<!-- doc-test: skip reason="prints a password; doc tests never display secrets" -->` to prevent credential exposure in test logs.

---

## Automated Verification Gates

1. **Doc-Test Markers Inventory:**
   ```
   python3 tests/doc_tests.py --markers-only
   doc-test markers: 57 bash blocks in 7 learner documents: run 26, mutating 6, covered 5, skip 20, invalid or unmarked 0
   ```
2. **Runnable Doc Examples (`make test-docs`):**
   ```
   [1] tenant-iac claim example: ✔ passes
   [2] developer tutorial values: ✔ passes
   [3] developer tutorial AWS CLI: ✔ passes
   [4] stale baselines: ✔ no stale 32 Applications or 12-stage banners
   [5] doc-test markers and runnable blocks: 26/26 run blocks ✔
   ✔ all doc example checks passed
   ```
3. **Repository CI Validation (`make ci`):**
   - 39 ShellCheck scripts clean.
   - Secret scan clean across 459 files.
   - 42 Applications rendered offline and validated against schemas (kubeconform).
   - Promtool alert rules & Grafana dashboards valid.
   - Tenant ApplicationSets match templates.
   - SSO URLs consistent across Keycloak, Argo CD, oauth2-proxy, Grafana.
   - Alloy configuration valid.
4. **Bats Smoke Test Suite (`make test` / `make test-bats`):**
   - 28/28 tests passed (0 failures) in 57 seconds across all 6 gates.
   - Token lifetimes healthy (~28 days remaining).
   - End-to-end orders flow green across dev, test, and prod.

---

## Conclusion & Next Phase

Phase 2 (Track A: Lab 0 Tour) meets all architectural, pedagogical, and security requirements. Findings V2-1, V2-2, and V2-3 are fully closed. 

**Next Steps:**
- Update `docs/remediation/2026-10-06-lab-learning-assessment/README.md` to register `validation-03.md`.
- Commit changes and push to `origin/main`.
- Proceed with **Phase 3 (Track B: Lab 1 Blueprint Sandbox)**.
