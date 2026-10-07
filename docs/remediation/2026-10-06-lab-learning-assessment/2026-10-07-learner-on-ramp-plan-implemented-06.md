# Learner On-Ramp Plan: Implementation Report 06 (validation-05 V3-4)

> **Status: For independent validation (2026-10-07).** Implementer: Claude (Opus 5.5). Answers [validation-05](2026-10-07-learner-on-ramp-plan-validation-05.md) (Codex: changes requested). Change: `gitops-control-plane`, this commit (it also commits Codex's validation-05, which Codex could not commit from its read-only session).

## V3-4: an empty k3d answer is not an inventory (fixed)
Codex was right: `jq -r '.[].name'` exits 0 on empty input, so a successful but empty `k3d cluster list -o json` read as "no cluster". `k3d_clusters()` in `scripts/learning-sandbox.sh` now requires a **non-empty JSON array** before it extracts names. `[]` is a real answer ("no clusters"); empty output, malformed text or a JSON object exits 1 with `could not verify: k3d cluster list returned nothing` or `returned no JSON array`.

Empty answers from `docker ps -a`, `docker network ls` and `kubectl config get-contexts` remain valid. A host can legitimately have no containers, networks or contexts, and their formats have no structure to check. The k3d answer is the one that decides whether a cluster exists and gets deleted.

**Guard tests** (`tests/test-sandbox-guards.sh`, CI stage `sandbox-guards`): **19 cases** (was 15). The four new cases:
- k3d answers nothing, with exit 0 → rc 1;
- k3d answers `{}` → rc 1;
- **all four reads empty, with exit 0** (Codex's reproduction) → rc 1;
- k3d answers `[]` with clean other reads → rc 0.

The stub now distinguishes an unset answer from an empty one.

**Mutation check:** the same suite run against `319441e` fails 4 cases. Three of them are `rc 0, ✔ sandbox removed`, which reproduces V3-4; the fourth is the "no JSON" case, whose message changed.

## Gates
| Test | Result |
|---|---|
| `bash tests/test-sandbox-guards.sh` | 19/19 |
| `make test-lab1` (live: real k3d JSON through the stricter check) | rc 0, 39 checks, 199 s; two earlier passes on `319441e` in implemented-05 |
| `make ci` | all checks passed |

## For the validator
Without Docker: the guard suite, and your empty-inventory reproduction against `learning-sandbox.sh down` (it must exit 1). With Docker and k3d: the live gates of implemented-04 §5 and implemented-05.
