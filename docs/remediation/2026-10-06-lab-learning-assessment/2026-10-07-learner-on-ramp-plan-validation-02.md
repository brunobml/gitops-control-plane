# Learner On-Ramp Plan — Independent Validation 02 (Phase 2, Lab 0)

> **Status: Changes requested (2026-10-07).** Validator: Codex. Implementer: Claude. Scope: [plan](2026-10-07-learner-on-ramp-plan.md) Phase 2 / Track A and [implementation report 02](2026-10-07-learner-on-ramp-plan-implemented-02.md), change `9da3463`.

## Verdict

The tour has the planned stations, clear links from the README and student guide, measured CLI observations, and a doc-test inventory with no unmarked bash blocks. **Phase 2 is not yet accepted:** the required tenant-user experience has not been exercised by either implementer or validator, and the optional Git exercise agreed in O-2 is absent. This review's sandbox cannot reach the running lab, so the remaining live acceptance checks need a validator with lab access.

## Findings

| ID | Finding | Required closure |
|---|---|---|
| V2-1 | **The tenant journey is inferred from policy, not tested as `tenant-a-user`.** The implementation report explicitly says the browser and CLI SSO login and station 1 tenant CLI block were skipped. The tested `argocd admin settings rbac can role:tenant-a … --policy-file` evaluates policy offline; it does not prove the Keycloak group claim, login session, Application list, or actual `can-i` responses. Station 7's automated CLI uses `platform-admin`. The plan's Track A exit gate requires every station to be run live by implementer and validator. | Run stations 0–1 and 7 with a real `tenant-a-user` SSO session, record the visible Application set and actual `can-i` outputs without recording the password or token. Have a separate validator repeat the learner path and its before/after lab snapshot. Keep the offline policy check as an additional diagnostic. |
| V2-2 | **O-2's optional Git change is missing.** The approved decision keeps the required tour Git-free but says to offer a real Git change at the end with a revert commit. The current “Optional: the Git side” only reads a revision and runs `git ls-remote`; it tells the learner to use another tutorial for a change. | Add a clearly optional, separately bounded change and revert exercise, or obtain an explicit owner revision of O-2 if the optional exercise should be deferred. Do not make a push part of the required tour or automated doc test. |
| V2-3 | **Password instruction is inaccurate.** Station 0 says “Get its password with `make password` (it reads `~/.config/gitops-lab`, never Git).” The Makefile target prints account names and the password file path; it does not read or display the password. | Say that `make password` locates the file, then tell the learner how to retrieve `keycloak-tenant-a-user.password` locally without copying the value into documentation or validation logs. |

## Checks and limits

- `python3 tests/doc_tests.py --markers-only` passed: **53 bash blocks in 7 documents** (run 25, mutating 6, covered 5, skip 17, invalid or unmarked 0). The Lab 0 source has stations 0–8, folded explanations and recovery notes; its read-only, mutating, and skipped blocks are labelled.
- Source review found the `argocd-session` prelude uses a temporary CLI config and deletes it on exit. The `aws_as` copy guard and settle-before-each-mutating-block logic are present. They were not exercised live in this review.
- `bash tests/test_doc_examples.sh --offline` failed in its tenant-IaC Step 3 render because Docker access to `/var/run/docker.sock` was denied in this validation sandbox. The schema and fixture checks before that point passed. This is an environment limit, not evidence of a Lab 0 defect.
- `curl http://localhost` could not connect and `kubectl` failed with `socket: operation not permitted` to the hub API. The terminal-browser skill requires escalated execution, which this session cannot request; its local setup also reported a read-only filesystem. Consequently I did not run the live tour, mutating checks, Bats, SSO, or before/after snapshot. The implementation report records a successful 585-second mutating run and an identical 49-line before/after snapshot, but these are implementer evidence only.

After V2-1 through V2-3 are resolved and the independent live run passes, Phase 3 (Lab 1 sandbox) can begin under the approved C → A → B → D order.
