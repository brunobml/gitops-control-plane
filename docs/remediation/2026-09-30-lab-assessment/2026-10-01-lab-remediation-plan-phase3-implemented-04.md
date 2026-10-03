# Phase 3 Implementation Report — Run #04: Track D (2026-10-01)

> **Status: Historical.** Record of the 2026-09-30 assessment and its remediation (Phases 1–5, closed 2026-10-03). Kept as evidence and not updated. For the lab as it is today, see the [README](../../../README.md) and the [2026-10-03 assessment](../../assessments/2026-10-03-lab-assessment.md).

| | |
|---|---|
| **Plan** | [`2026-10-01-lab-remediation-plan-phase3.md`](2026-10-01-lab-remediation-plan-phase3.md) v1.0 (GREEN LIGHT, R-0 to R-4) |
| **Preceded by** | [Implemented-03](2026-10-01-lab-remediation-plan-phase3-implemented-03.md), validated 🟢 in [Validation-03](2026-10-01-lab-remediation-plan-phase3-validation-03.md) |
| **Scope executed** | **D.1** (app v1.4.0), **D.2** (moto restart test + moto pin/rebind), **D.3** (CARM: canary, nonprod, prod). D.4 and D.5 externalRef were delivered in Run #03. |
| **Not executed** | **D.5 input validation (L2-5)**: ValidatingAdmissionPolicy proposed (reviewer PV3-8 concurs), not yet built. **B.4 / B.7**: end of phase. |
| **Owner approvals** | D.3 cutover procedure (finalizer removal, message-loss risk) approved by the owner before nonprod; prod cutover approved separately |
| **Commits** | `orders-processor`: `c1919f5` (tag **v1.4.0**), `8f88f7e` (values) · `platform-catalog`: `613b19e` (tag **v1.3.1**) · `gitops-control-plane`: `d79d134`, `240c987`, `304e4bd`, `5c42676` |

---

## 1. Outcome Summary

| Step | Finding | Result |
|---|---|:-:|
| D.1 | Worker credentials + recovery | ✅ v1.4.0 live on dev/test/prod; key ID from `AWS_ACCESS_KEY_ID`; DynamoDB table recreated on write failure |
| D.2 | **L3-2** moto ephemeral state | ✅ After a full moto wipe: ACK rebuilt all 6 queues in **201 s** (redrive intact); workers recreated their tables on the next order, **0 restarts**. Also: moto pinned by registry digest and bound to `127.0.0.1` (closes A.1/B.5 for moto) |
| D.3 | **L4-4** cloud account isolation | ✅ nonprod (`orders-dev`, `orders-test`) → **111111111111**; prod (`orders-prod`) → **222222222222**; default account `123456789012` emptied; isolation matrix proven |
| D.5 | L2-5 input validation | ⏳ Open: ValidatingAdmissionPolicy (no CRD change) |

**L3-2 → Closed** (self-healing infra + data stores; in-flight messages are lost on a moto restart, an accepted lab residual). **L4-4 → Closed.**

---

## 2. Findings & Deviations

| ID | Type | Detail |
|---|---|---|
| **D-24** | Finding (moto) | moto resolves an SQS queue **by name in the caller's account** and ignores the account segment of the queue URL. An isolation check that only looks at whether a call "succeeds" can be fooled by a same-named queue in the caller's own account (it happened once on nonprod before the orphans were deleted). Isolation is therefore verified by the **account in the returned ARN** (matrix in §3). |
| **D-25** | Finding (ACK, canary) | ACK **refuses in-place account changes**: `Resource already exists in account 123…, but the role used for reconciliation is in account 111…`, while the Queue status **stays `ResourceSynced=True`** (stale green). Deleting the old CR then **hangs on the ACK finalizer**; `deletion-policy: retain` doesn't help. The working migration (reviewer remark R-3, extended): drain → set namespace account → **remove the finalizer and delete each Queue CR** → kro recreates it in the new account → restart workers → delete the orphaned old-account queues. Owner-approved before use. |
| **D-26** | Design | dev and test migrated together (same ApplicationSet template, same account); prod separately afterwards. |
| **D-27** | Observation (CI) | Pushing `main` and a `v*` tag for the same commit runs CI twice, and both runs push `sha-<commit>`, so that tag is overwritten once. Harmless because deployments pin by digest, but `sha-*` tags are not strictly immutable. Fix later: build `sha-*` only on branch pushes, or skip branch builds for tagged commits. |
| **D-28** | Observation | During the v1.4.0 prod rollout one test message was received by a terminating pod and redelivered after the 30 s visibility timeout; no loss (SQS at-least-once). |
| **D-29** | Design | Credentials: `scripts/provision-worker-credentials.sh` issues an IAM key **in the target account** (re-running rotates it) into Secret `<name>-<env>-aws`; nothing printed, nothing in Git. Production equivalent: IRSA / Pod Identity, no static keys. |
| **D-30** | Gate use | The CARM map reached prod via a new blueprint tag `v1.3.1` (`v1.3.0` + that one file, verified on nonprod) through the normal promotion gate. |

---

## 3. Evidence

### D.1: orders-processor v1.4.0
* Local test against moto (throwaway account `999999999999`, cleaned up): the worker consumed from that account's queue using that account's key; its DynamoDB table was created in that account (default account: `ResourceNotFoundException`); after the table was deleted mid-run the next order logged `re-initializing table … and retrying` and was stored.
* GHCR `v1.4.0` → `sha256:c7e8f5d9…`, config `APP_VERSION=v1.4.0`, `BUILD_COMMIT=c1919f5…` (correct provenance).
* dev/test: footer `v1.4.0 · c1919f5`; end-to-end order processed. Prod promoted via `valuesRevision: 8f88f7e…` (`d79d134`); footer `v1.4.0 · c1919f5`; fresh order processed.

### D.2: moto restart (07:43:21)
| Measure | Result |
|---|---|
| Queues after wipe | 0 → 4 at +147 s → **6 at +201 s** (≤ 2 × 300 s bound) |
| Redrive policies | intact (each queue → its DLQ) |
| DynamoDB tables after wipe | none → recreated on first order in dev/test/prod (1 `re-initializing table` line each), **0 restarts** |
| moto binding / image | `127.0.0.1:5000` / `motoserver/moto@sha256:91fd602a…` |

### D.3a: canary (nonprod, deleted afterwards)
* Mapped namespace → queue created in `111111111111` via the assumed role; invisible to the default account.
* In-place account change → refused (D-25); finalizer removal + recreate → new account; orphan deleted. Canary namespaces removed; account `111111111111` left empty.

### D.3c: cutovers
| | nonprod (07:56) | prod (08:01) |
|---|---|---|
| Queues drained before cutover | ✅ 0 / 0 | ✅ 0 visible / 0 in flight / 0 delayed |
| Credentials | `orders-{dev,test}-aws` keys in 111… | `orders-prod-aws` key in 222… |
| Namespace account (GitOps `managedNamespaceMetadata`) | `111111111111` | `222222222222` |
| Queue + DLQ ARNs after re-stamp | in 111… (≤ 1 s) | in 222… (3 s); deletion-policy `retain` kept |
| Redrive | same-account DLQ | same-account DLQ |
| Worker restart | pods recreated; QUEUE_URL + key from Secret | one pod at a time; ingress **200 throughout**; PDB respected |
| End-to-end order from the new account | ✅ dev, test | ✅ prod; DynamoDB table ARN in 222… |
| Orphans in 123456789012 | deleted (queues, DLQs, tables) | deleted after confirming empty |
| ACK account-mismatch errors after cutover | 0 (22 only in the 2 s cutover window) | 0 |

**Isolation matrix** (caller account × queue name → account of the returned ARN):

| caller | orders-dev-queue | orders-test-queue | orders-prod-queue |
|---|---|---|---|
| 123456789012 (old default) | NonExistentQueue | NonExistentQueue | NonExistentQueue |
| 111111111111 (nonprod) | 111111111111 | 111111111111 | NonExistentQueue |
| 222222222222 (prod) | NonExistentQueue | NonExistentQueue | 222222222222 |

### Regression
* Smoke test (account-aware stage 6): **exit 0**; queues reported in 111… (dev/test) and 222… (prod).
* 17/17 Applications Synced/Healthy; R-1 impersonation audit PASS.

---

## 4. Phase 3 Remaining

| Item | Status |
|---|---|
| D.5 L2-5 input validation (ValidatingAdmissionPolicy) | Next (reviewer PV3-8 concurs) |
| B.4 Argo CD self-management (stretch) | Open |
| B.7 full rebuild acceptance | **Needs explicit owner approval** |
| 0.3 / 0.4 GitHub branch protection, GHCR cleanup | Owner UI actions |
| Credential rotation | Due before **2026-10-31 07:19 UTC** |

---

## 5. Addendum: D.5 / L2-5 input validation (ValidatingAdmissionPolicy)

Delivered after this report's first version, on owner approval (reviewer PV3-8 concurred).

| Item | Detail |
|---|---|
| Mechanism | `ValidatingAdmissionPolicy` + binding `queuebackedservice-contract` on `kro.run/queuebackedservices` (CREATE/UPDATE; status/finalizer subresources not matched). Lives in `platform-catalog/blueprints/` so it is versioned and promoted with the RGD. kro's CRD is untouched (avoids D-14). |
| Rules | `name` DNS label (1–31), `environment` ∈ {dev,test,prod}, `replicas` 1–10, `messageRetentionPeriod` 60–1 209 600 s (SQS limits), `image` required, **namespace must end with `-<environment>`** (a dev namespace cannot create prod-named queues in the nonprod account). |
| Rollout | `456df94` Warn+Audit on nonprod → `32029f6` Deny+Audit on nonprod → tag **`v1.3.2`** (v1.3.1 + the policy only) → prod (`14580a0`). |
| Evidence (Warn) | Existing dev/test instances re-submitted as UPDATE: **0 warnings**. Argo CD syncs (as `argocd-tenant-deployer`) and kro updates: 0 warnings, 0 errors. Five invalid probes each produced their specific message. |
| Evidence (Deny) | `prood`, `replicas: 50`, env/namespace mismatch → **`denied request: …`**; a valid new instance → admitted. Syncs of `orders-dev`, `orders-test`, `kro-blueprints-spoke-nonprod`, `orders-prod` succeed; RGD Active; instances ACTIVE. Prod: existing instance UPDATE admitted; `environment: dev` in `orders-prod` denied. |
| CEL type checking | `status.typeChecking` empty (no type errors). |

**L2-5 → Closed.**

| ID | Type | Detail |
|---|---|---|
| **D-31** | Self-inflicted, recovered | To test the policy against real syncs I ran `argocd app sync --force` on `orders-dev`/`orders-test`. Argo CD rejected it for these apps (`--force cannot be used with --server-side`) and the operations sat in retry with backoff. While an operation is running, self-heal does not act, so a manual test edit (`replicas: 2`) stayed for ~2 min. Fixed with `argocd app terminate-op` + normal sync; self-heal then reverted a fresh edit in 3 s. No policy involvement. Lesson: don't use `--force` with these apps. |
