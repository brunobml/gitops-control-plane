# Tenant IaC: Implementation Report 11 (moto-restart residuals R-a and R-b)

> **Status: For independent validation (2026-10-07).** Implementer: Claude (Opus 5.5). **Validator: Codex** (owner's assignment). Change: `gitops-control-plane` **`bf0a042`** (`scripts/moto-restart.sh` only). Residuals from [validated-03](2026-10-04-tenant-iac-team-clusters-plan-validated-03.md): **R-a** (no trap: a failure leaves Argo CD and ACK at 0 replicas) and **R-b** (`|| true` on the default-account check: a failed read passes as "empty", the same fail-open class as [validated-10](2026-10-04-tenant-iac-team-clusters-plan-validated-10.md) B-2).

## 1. Changes
| # | Change |
|---|---|
| R-a | One `EXIT` trap (`restore_on_exit`). Flags `ARGO_PAUSED` / `ACK_SCALED_DOWN` are set **before** the scale-down commands and cleared only after the scale-up has rolled out. On any non-zero exit, the trap scales ACK back to 1 on both spokes and the hub's Argo CD application controller to 1, and reports whether moto was restarted. That status is **exact**: moto's container `StartedAt` is compared with the value recorded at the start. `INT`/`TERM` → `exit 130` → the same trap. The step-2 timeout ("ACK pods still running") is now a failure (`exit 1`, trap restores) instead of a warning that went on to restart moto. The temporary Argo CD config is removed by the same trap (it used to replace the trap) |
| R-a (found while testing) | **SIGPIPE-safe trap.** Under `timeout … \| tail` (and, the same in practice, Ctrl-C on `make moto-restart \| tee log`), the signal also kills the pipe reader; the trap's first `echo` then raised SIGPIPE and killed bash **before anything was restored** (reproduced: ACK 0/0, Argo CD 0). The trap now ignores `PIPE INT TERM` first, restores, and prints last, with failures ignored |
| R-b | Step 9 reads go through `read_default_account`, which returns non-zero on any AWS error; the assignment then fails under `set -e` with `❌ Cannot verify the default account: 'aws <service> <op>' failed: …`. The clean message is printed only after all five reads succeeded. `AWS_SESSION_TOKEN` is unset so the check really runs as the default account |

## 2. Evidence (live lab, 2026-10-07)
| Test | Result |
|---|---|
| R-a, failure at step 3 (exported `docker` function failing only `docker restart`) | Steps 1–2 ran (Argo CD 0, ACK 0); then `❌ moto-restart stopped (exit 1)`, `↻ spoke-nonprod/spoke-prod: ACK controllers scaled back to 1`, `↻ hub: Argo CD … back to 1`, `moto was not restarted; the cloud state is unchanged.`; rc 1. Afterwards ACK 1/1/1/1 on both spokes, Argo CD 1; moto `StartedAt` unchanged |
| R-a, SIGTERM to the script's bash (`kill -TERM` after 6 s) | rc 130, same restore lines, "moto was not restarted" |
| R-a, `timeout -s TERM 6 … \| tail` (signal to the whole group, pipe reader killed) | **Before the SIGPIPE fix:** nothing restored (ACK 0, Argo CD 0), restored by hand. **After:** ACK 1 on both spokes, Argo CD 1 |
| R-a, SIGINT to the group (`setsid --wait`, `timeout -s INT 7 … \| tail`) | A sample mid-run showed Argo CD at **0**; then exit 130, all three restored, "moto was not restarted" |
| R-b, full run with `aws ec2 describe-vpcs` failing (exported `aws` function) | Step 9: `❌ Cannot verify the default account: 'aws ec2 describe-vpcs' failed: An error occurred (simulated) …`; **no** "completely empty"; rc 1; the trap reported "moto was restarted … run 'make moto-restart' again" (controllers were already back at that point). A clean `make moto-restart` then completed (rc 0) |
| Success path | `make moto-restart`: **rc 0 in 289 s**; default account empty; orphan check "only <live>" in both accounts; post-bootstrap smoke passed. A second clean run after the R-b test: rc 0 |
| Final state | 42/42 Applications Synced/Healthy; one platform VPC per account (`vpc-68d5…` in 111, `vpc-4f17…` in 222) |
| Gates | ShellCheck clean; `make ci` all passed (38 scripts); Bats **28/0** |

## 3. Incident during testing (my test harness, not the script)
One SIGINT test was started with plain `setsid` (no `--wait`). It returned immediately, and the detached run **did not stop on SIGINT**: a detached non-interactive run can ignore it. It continued, **restarted moto at 05:39:47 UTC** and overlapped with my next test, which left 8 Applications not Synced/Healthy and the ACK controllers not ready. No `moto-restart` was running afterwards. I recovered with a clean `make moto-restart` (rc 0, row "Success path"). The cloud state was rebuilt from Git as designed; no data outside moto's in-memory state was involved.

## 4. For the validator (Codex)
1. Read `restore_on_exit` and the flag placement around steps 1, 2, 6 and 7, and `read_default_account` (step 9).
2. Cheap, no moto restart: export a `docker` function that fails only `restart` and run `bash scripts/moto-restart.sh`; expect the restore lines, "moto was not restarted", rc 1, and both spokes' ACK and Argo CD at 1 afterwards.
3. Interruption through a pipe: `setsid --wait bash -c 'timeout -s TERM 6 bash scripts/moto-restart.sh 2>&1 | tail -5'` (use `--wait`; see §3); expect replicas restored.
4. R-b (restarts moto; then finish with a clean `make moto-restart`): export an `aws` function failing only `ec2 describe-vpcs`; expect "Cannot verify the default account", rc 1, no "completely empty".
5. Gates and GitHub Actions on `bf0a042`.
