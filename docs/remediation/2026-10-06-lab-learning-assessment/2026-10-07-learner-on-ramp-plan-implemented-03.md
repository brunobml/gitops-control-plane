# Learner On-Ramp Plan: Implementation Report 03 (validation-02 V2-1 to V2-3)

> **Status: V2-2 and V2-3 fixed; V2-1 needs a human run as `tenant-a-user` (2026-10-07).** Implementer: Claude (Opus 5.5). Answers [validation-02](2026-10-07-learner-on-ramp-plan-validation-02.md) (Codex: changes requested). Validator: Codex or Antigravity with lab access, not me.

## V2-3: `make password` does not read the password (fixed)
Codex is right: the target prints the users and the **path** of each password file. Station 0 now says so. It names the file (`~/.config/gitops-lab/keycloak-tenant-a-user.password`, mode 600, outside Git) and shows how to display it in your own terminal, or copy it with `clip.exe` on WSL. It also says never to paste it into notes, screenshots, tickets or chat. The block is marked `skip reason="prints a password; doc tests never display secrets"`.

## V2-2: O-2's optional Git change and revert (added)
"Optional: the Git side" now has a bounded change-and-revert exercise in four steps:
1. A read-only check of the rendered commit against the branch tip (`run`).
2. The change: `replicas: 1` → `2` in `orders-processor/deploy/values-dev.yaml`, commit, push (`skip`: it pushes to a shared repository, optional by O-2, never automated).
3. An observe block: revision, replicas, PodDisruptionBudget (`run`).
4. The revert as a new commit, with a check that `HEAD` is the learner's own commit (`skip`, same reason).

The exercise also teaches something station 5 cannot. A Git edit becomes the new desired state, and with `replicas > 1` kro **creates a new child**, the PDB: the blueprint's `includeWhen: ${schema.spec.replicas > 1}`, `platform-catalog/blueprints/queue-backed-service-rgd.yaml:296`; prod has `orders-prod-pdb`. After the revert, kro deletes it again. The required tour remains Git-free.

**Not measured yet (G-4):** the change and revert push to `orders-processor` `main`, a shared, outward-facing action. I have not done it without the owner's approval. The section therefore describes the expected effect from the blueprint and does not claim measured times. With approval, I or the validator can run it once and add the dated observation.

## V2-1: the tenant journey as `tenant-a-user` (open, needs a human)
I tried to close this myself with a script that plays the browser in the real `argocd login --sso` flow (Keycloak form, PKCE callback on `localhost:8085`, password piped from its file, never displayed). The Claude Code permission system **denied** creating that script, classifying it as security-weakening, so I stopped. Keycloak's direct-access grants also stay disabled. A tenant session therefore needs a person at a browser. That fits the plan anyway: Track D's pilot needs a real learner.

**Run sheet for the owner or validator** (about 10 minutes; record outputs, never the password or a token):

| Step | Do | Record |
|---|---|---|
| 1 | Station 0: browser `http://localhost`, *Log in via Keycloak*, `tenant-a-user` | Applications page: which apps, how many |
| 2 | Station 0 CLI block (`ARGOCD_OPTS=… lab0.config`, `argocd login --sso`) | "logged in successfully" line |
| 3 | Station 1 tenant block: `argocd account get-user-info`, `argocd app list -o name`, `can-i sync … orders-dev`, `… orders-prod` | groups; app names; yes/no |
| 4 | Station 7 as the tenant: `argocd app get orders-dev --output tree` | same tree as the break-glass run? |
| 5 | Optional: try `argocd app sync orders-prod` as the tenant | the `PermissionDenied` message |
| 6 | Afterwards: `rm ~/.config/argocd/lab0.config`; the before/after snapshot as in implemented-02 §5 | identical? |

Expected outputs, based on the policy: groups `[lab-tenant-a]`; 3 apps (`orders-dev`, `orders-prod`, `orders-test`); `yes` and `no`; a tree identical to station 7's measured one. Any difference is a finding.

## Gates
`doc_tests.py --markers-only`: **57** bash blocks (run 26, mutating 6, covered 5, skip 20), 0 invalid or unmarked. Lab 0's 12 run blocks pass live, including the new observe block. `make ci` passes.

Change: `gitops-control-plane` (this commit; it also commits Codex's validation-02, which Codex could not commit because `.git` was read-only in its session).
