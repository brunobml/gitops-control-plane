# Lab command notebook

[`lab-commands.ipynb`](lab-commands.ipynb) collects the commands of this lab that are hard to
remember or to type, each with a short explanation of the concept behind it. The sections cover
Argo CD, Helm, kro, ACK and Moto, Kyverno and Policy Reporter, Prometheus and Loki, and
troubleshooting.

**Every cell only reads**, so running the whole notebook never changes the lab. Commands that
change something are listed as text in its last section, next to the Git-first way to do the
same thing.

It runs on the lab host, not in a container. It needs what the host already has:

- the three k3d kube contexts;
- the `*.localhost` URLs;
- Moto on `localhost:5000`;
- `~/.config/gitops-lab`;
- the same `kubectl`, `argocd`, `helm`, `aws` and `jq`.

## Setup (once)

1. Install the VS Code extensions **Jupyter** (`ms-toolsai.jupyter`) and, on Windows, **WSL**
   (`ms-vscode-remote.remote-wsl`). Open this repo through WSL with `code .` in the WSL terminal.
2. Run the setup script:

   ```bash
   make notebook-setup        # same as: bash scripts/setup-notebook.sh
   ```

   The script does three things:
   - It creates `.venv-notebook/`, which is git-ignored and pinned by
     [`requirements.txt`](requirements.txt).
   - It registers the Jupyter kernel **Bash** for your user.
   - It installs the `nbstripout` Git filter in your clone, so cell outputs are removed when you
     commit.

   Re-running it is safe.
3. Open `docs/learning/notebooks/lab-commands.ipynb`. Click **Select Kernel** (top right), choose
   **Jupyter Kernel…**, then **Bash**. If Bash is missing, run **Developer: Reload Window**.
   Do **not** pick a *Python Environment*, even `.venv-notebook`: the cells are Bash, and a
   Python kernel either fails to start (`No module named ipykernel_launcher`) or doesn't run them.
   The top-right corner must read **Bash**.
4. Run the first cell (*Setup and tool check*). It defines the variables the other cells use and
   marks any missing tool or context with ✘.

To use the browser instead of VS Code:

```bash
.venv-notebook/bin/jupyter lab docs/learning/notebooks/lab-commands.ipynb
```

## Use

- The lab must be running (`make start`). Cells that query Argo CD, Prometheus or Loki need the
  hub. The Helm cells need internet access to the chart repositories.
- Section 2 logs in to Argo CD as `platform-admin` with a temporary config file, which the last
  cell removes. Your own `argocd` login is never touched.
- A cell is a normal Bash command. Copy it into a terminal to run it there.
- Restarting the kernel clears the variables. Run the first cell again.

## Rules for new cells

- **Read-only.** For a command that changes the lab, add a row to the table in *Changes go
  through Git* instead of a cell.
- **No secrets in output.** Never print `make password`, a decoded Secret, a token or a
  kubeconfig. The `nbstripout` filter stops outputs from reaching Git, but they still sit in
  your local file and on screen.
- **Name the cluster.** Use `--context "$HUB"`, `"$NONPROD"` or `"$PROD"`, never the current
  context.
- **End every cell with a command that succeeds.** The Bash kernel reports a cell as failed when
  its last command fails. For commands that exit non-zero on purpose, such as `argocd app diff`
  or a denied `--dry-run=server`, capture or print the exit code.
- **Check before committing.** Run the whole notebook headless against the running lab:

  ```bash
  make notebook-check
  ```

  It fails on the first cell that errors and saves nothing.

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| ▶ does nothing, or the cell shows no output | The kernel is not **Bash**. Check the top-right corner; choose *Select Kernel → Jupyter Kernel… → Bash*. |
| `No module named ipykernel_launcher` | A Python kernel was picked. Switch to **Bash** as above. |
| **Bash** is not in the kernel list | Run `make notebook-setup` again, then **Developer: Reload Window**. |
| Long outputs are cut off | The repo's `.vscode/settings.json` makes outputs scrollable after 50 lines. Per output: click *…open in a scrollable element* or *open in a text editor*. |
| A cell fails with "variable not set" or an empty `--context` | The kernel was restarted. Run the first cell again. |
