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

```bash
make notebook-setup        # same as: bash scripts/setup-notebook.sh
```

The script does three things:

- It creates `.venv-notebook/`, which is git-ignored and pinned by
  [`requirements.txt`](requirements.txt).
- It registers the Jupyter kernel **Bash** for your user.
- It installs the `nbstripout` Git filter in your clone, so cell outputs are removed when you
  commit.

Re-running it is safe. Then open the notebook in either of the two ways below.

### Option 1: JupyterLab in the browser (no VS Code needed)

```bash
make notebook              # NOTEBOOK_PORT=8899 make notebook for another port
```

1. Open the `http://127.0.0.1:8888/lab?token=…` link the command prints. On WSL, the Windows
   browser reaches it through `127.0.0.1` as well.
2. Open `lab-commands.ipynb`. The kernel is **Bash** by default; the top right of the notebook says
   so.
3. Run the first cell (*Setup and tool check*).

The server runs on the lab host, so the notebook has the host's tools, kube contexts and
`~/.config/gitops-lab`. It listens on `127.0.0.1` only and requires its token: a notebook server is a
web shell with your cluster credentials. Don't change either, and don't paste the token anywhere.
Ctrl+C in the terminal stops it.

A generic Jupyter container (for example `quay.io/jupyter/scipy-notebook`) is **not** a substitute:
it has none of the lab's tools, no Bash kernel and no access to the clusters (its `127.0.0.1` is
the container itself). The planned lab toolbox image solves that
(`docs/roadmaps/2026-10-09-portable-lab-toolbox-plan.md`).

### Option 2: VS Code

1. Install the VS Code extensions **Jupyter** (`ms-toolsai.jupyter`) and, on Windows, **WSL**
   (`ms-vscode-remote.remote-wsl`). Open this repo through WSL with `code .` in the WSL terminal.
2. Open `docs/learning/notebooks/lab-commands.ipynb`. Click **Select Kernel** (top right), choose
   **Jupyter Kernel…**, then **Bash**. If Bash is missing, run **Developer: Reload Window**.
   Do **not** pick a *Python Environment*, even `.venv-notebook`: the cells are Bash, and a
   Python kernel either fails to start (`No module named ipykernel_launcher`) or doesn't run them.
   The top-right corner must read **Bash**.
3. Run the first cell (*Setup and tool check*). It defines the variables the other cells use and
   marks any missing tool or context with ✘.

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
- **Say why the output matters.** When a result hides something worth knowing, follow the command
  with a Markdown cell starting with **Why it matters.**: what is important in it and why (a trap,
  a design decision, the next step when it is wrong). Skip it when the output explains itself.
  Base it on what the lab actually prints, and write *kro* in lowercase.
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
| `SyntaxError: invalid syntax` on a Bash line (`Cell In[2]`, an IPython traceback) | A **Python** kernel runs the notebook. A Jupyter without the Bash kernel (for example a generic Jupyter container with the repo mounted) saves the notebook as `python3`. Restore it (`git checkout -- docs/learning/notebooks/lab-commands.ipynb`, after saving any notes you added), then open it with `make notebook`, which offers only the Bash kernel. `make notebook-check` fails while the kernel is not `bash`. |
| `No module named ipykernel_launcher` | A Python kernel was picked. Switch to **Bash** as above. |
| **Bash** is not in the kernel list | Run `make notebook-setup` again, then **Developer: Reload Window**. |
| Long outputs are cut off | The repo's `.vscode/settings.json` makes outputs scrollable after 50 lines. Per output: click *…open in a scrollable element* or *open in a text editor*. |
| Cells take minutes, hang at `[*]`, or print `--More--` / `Display all … possibilities` | The kernel predates the fix: run `make notebook-setup` again, then *Restart* the kernel. It now starts with readline completion off (`kernel.inputrc`; a tab in a cell is otherwise tab completion in Bash) and without the Windows PATH (`/mnt/c/...`, which WSL scans slowly for every completion VS Code asks for). The repo's `.vscode/settings.json` makes VS Code indent cells with spaces. |
| A cell fails with "variable not set" or an empty `--context` | The kernel was restarted. Run the first cell again. |
