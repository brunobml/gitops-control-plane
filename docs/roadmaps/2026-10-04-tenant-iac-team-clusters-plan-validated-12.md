# Tenant IaC: independent validation of moto-restart residuals R-a and R-b (validated-12)

> **Status: Accepted.** Validated by Codex on 2026-10-07 against commit `bf0a042` and implementation report [implemented-11](2026-10-04-tenant-iac-team-clusters-plan-implemented-11.md) (`37125d1`). This completes the remediation and closes residuals **R-a** and **R-b** from [validated-03](2026-10-04-tenant-iac-team-clusters-plan-validated-03.md).

## Independent evidence

| Case | Result |
| --- | --- |
| **R-a: Cheap error injection (mock `docker restart` failure)** | Exported a test `docker` function that failed only `restart moto-cloud` with a simulated error. `bash scripts/moto-restart.sh` executed steps 1–2 (paused Argo CD controller to 0, scaled ACK controllers to 0). Step 3 failed on `docker restart`. The `restore_on_exit` trap fired with exit 1: scaled ACK controllers back to 1 on `spoke-nonprod` and `spoke-prod`, resumed Argo CD controller to 1 on `hub-cluster`, and accurately determined via `StartedAt` inspection that `moto was not restarted; the cloud state is unchanged.` Live inspection confirmed all ACK deployments and Argo CD application controller were 1/1 Running. |
| **R-a: Pipeline interruption & SIGPIPE immunity** | Ran `setsid --wait bash -c 'timeout -s TERM 6 bash scripts/moto-restart.sh 2>&1 | tail -5'`. The timeout sent SIGTERM to the process group while controllers were scaled down. The downstream reader (`tail`) terminated first; `restore_on_exit` masked `PIPE INT TERM` before printing, successfully restoring ACK controllers on both spokes and Argo CD on the hub back to 1 (exit 130). Live inspection confirmed controllers returned to 1/1 Running without hanging or aborting mid-cleanup. |
| **R-b: Fail-closed default account check** | Exported a test `aws` function failing only `ec2 describe-vpcs` during step 9. `read_default_account` detected the failure, output `❌ Cannot verify the default account: 'aws ec2 describe-vpcs' failed: simulated aws ec2 describe-vpcs error`, and exited 1 under `set -e`. It did **not** falsely report the account as "completely empty". The trap detected that Moto had been restarted and directed the operator to run `make moto-restart` again. |
| **R-a: ACK termination timeout enforcement** | Code review verified that the step-2 ACK pod termination loop in `scripts/moto-restart.sh` now executes `exit 1` instead of printing a warning and continuing when pods do not terminate within 60 seconds, preventing Moto restarts while controllers are running. |
| **Clean recovery & full pipeline** | Ran `make moto-restart`. All 10 steps completed cleanly (exit 0): restarted Moto, cleaned stale resources and adopted annotations, synced 6/6 platform network resources per spoke, verified default account `123456789012` is completely empty, executed `post-bootstrap.sh`, verified 0 orphan platform VPCs, and completed the full 12-stage smoke test suite in ~280 s. |
| **Gates & Final state** | All 42 Argo CD Applications are Synced and Healthy. Moto Cloud contains exactly one referenced platform VPC per CARM account (`vpc-7133bb1c4b07a4947` in `111111111111`, `vpc-399cac3e5688a5b56` in `222222222222`) and 0 resources in default account `123456789012`. Bats test suite passed **28/28** (`smoke-test-hub-spoke-bats.sh`). `make ci` passed cleanly (38 scripts syntax & ShellCheck clean, 42 Applications rendered and kubeconform-validated, 22 promtool alert rules verified). `make test-docs` passed cleanly. |

## Finding closure

1. **R-a (Failure/Interruption leaves controllers at 0 replicas / SIGPIPE in trap):** Closed.
   - `restore_on_exit` is registered on `EXIT`, and `INT`/`TERM` trigger `exit 130` into the trap.
   - Flags `ARGO_PAUSED` and `ACK_SCALED_DOWN` are tracked around scaling operations.
   - The trap ignores `PIPE INT TERM` immediately upon entry, preventing broken pipes from killing bash before restoration commands execute.
   - Moto container start timestamp comparison (`StartedAt`) provides exact restart diagnostics.
   - Controller timeout at step 2 fails closed (`exit 1`) to prevent Moto restart while pods run.
2. **R-b (Fail-open default account verification):** Closed.
   - Step 9 queries route through `read_default_account`, capturing stderr on failure and returning nonzero.
   - Under `set -e`, any failed read aborts immediately before checking resource variables.
   - `AWS_SESSION_TOKEN` is unset to ensure requests are scoped strictly to the default account.

## Disposition

Residuals **R-a** and **R-b** are **accepted**. `scripts/moto-restart.sh` reliably restores control plane and spoke controller replicas across unexpected interruptions or failures, provides exact container status reporting, and enforces fail-closed verification of the default root AWS account.
