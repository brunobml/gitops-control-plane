#!/usr/bin/env bash
# Python environment of the lab command notebook (docs/learning/notebooks/lab-commands.ipynb).
#
# - .venv-notebook/ in this repo (git-ignored) with the pinned packages of
#   docs/learning/notebooks/requirements.txt (uv if installed, otherwise python3 -m venv)
# - registers the Jupyter kernel "bash" for the current user (~/.local/share/jupyter/kernels/bash),
#   pointing at that environment; VS Code lists it under Select Kernel > Jupyter Kernel... > Bash
# - installs the nbstripout Git filter in this clone (.git/config, .git/info/attributes), so cell
#   outputs never reach a commit
# - --check runs every cell headless against the running lab and fails on the first error
#   (nothing is saved; the notebook is read-only by design)
# - --lab serves JupyterLab in the browser (no VS Code needed) on 127.0.0.1 only: it is a web shell
#   with your kubeconfig and lab secrets, so it never listens on other interfaces and keeps its token
# Re-runs are safe.
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
VENV="${ROOT_DIR}/.venv-notebook"
REQ="${ROOT_DIR}/docs/learning/notebooks/requirements.txt"
NOTEBOOK="${ROOT_DIR}/docs/learning/notebooks/lab-commands.ipynb"

if [[ "${1:-}" == "--lab" ]]; then
  [[ -x "${VENV}/bin/jupyter" ]] || { echo "Run scripts/setup-notebook.sh first." >&2; exit 1; }
  echo "JupyterLab on 127.0.0.1 only; open the http://127.0.0.1:<port>/lab?token=... link printed below."
  echo "Pick the Bash kernel. Ctrl+C stops the server."
  exec "${VENV}/bin/jupyter" lab --ip=127.0.0.1 --port="${NOTEBOOK_PORT:-8888}" --no-browser \
    --ServerApp.root_dir="$(dirname "$NOTEBOOK")" --MultiKernelManager.default_kernel_name=bash \
    --KernelSpecManager.allowed_kernelspecs=bash   # the cells are Bash: hide the venv's python3 kernel
fi

if [[ "${1:-}" == "--check" ]]; then
  [[ -x "${VENV}/bin/jupyter" ]] || { echo "Run scripts/setup-notebook.sh first." >&2; exit 1; }
  # A Jupyter without the Bash kernel (e.g. a generic Jupyter image) rewrites the notebook to
  # python3 on save; its cells then fail with SyntaxError. Fail here instead of committing that.
  kernel=$(jq -r '.metadata.kernelspec.name // "none"' "$NOTEBOOK")
  [[ "$kernel" == "bash" ]] || { echo "✘ ${NOTEBOOK##*/}: kernelspec is '${kernel}', expected 'bash'" >&2; exit 1; }
  cd "$(dirname "$NOTEBOOK")"
  exec "${VENV}/bin/jupyter" execute --kernel_name=bash "$NOTEBOOK"
fi

if command -v uv >/dev/null 2>&1; then
  uv venv -q --allow-existing "$VENV"
  uv pip install -q --python "${VENV}/bin/python" -r "$REQ"
else
  python3 -m venv "$VENV"
  "${VENV}/bin/pip" install -q -r "$REQ"
fi
echo "✔ Python environment: ${VENV}"

"${VENV}/bin/python" -m bash_kernel.install --user >/dev/null
# WSL appends the Windows PATH (/mnt/c/...), which WSL reads slowly: bash_kernel answers every
# completion request VS Code sends with `compgen -c`, a scan of the whole PATH, which then takes
# minutes and blocks the cells queued behind it. The kernel gets this PATH without /mnt/*
# (fixed at setup time: re-run after installing tools into a new directory).
KERNEL_PATH=$(tr ':' '\n' <<<"$PATH" | grep -v '^/mnt/' | awk 'NF && !seen[$0]++' | paste -sd:)
KERNEL_JSON="$("${VENV}/bin/jupyter" kernelspec list --json | jq -r '.kernelspecs.bash.resource_dir')/kernel.json"
# A tab in a cell must not trigger readline completion (see kernel.inputrc).
jq --arg path "$KERNEL_PATH" --arg inputrc "${ROOT_DIR}/docs/learning/notebooks/kernel.inputrc" \
  '.env.PATH = $path | .env.INPUTRC = $inputrc' "$KERNEL_JSON" > "${KERNEL_JSON}.tmp" && mv "${KERNEL_JSON}.tmp" "$KERNEL_JSON"
echo "✔ Jupyter kernel 'bash' registered for $(id -un) (uses ${VENV}; PATH without /mnt/*; no tab completion)"

(cd "$ROOT_DIR" && "${VENV}/bin/nbstripout" --install)
echo "✔ nbstripout filter installed in this clone: notebook outputs are stripped on commit"

echo ""
echo "Open ${NOTEBOOK#"${ROOT_DIR}"/} in VS Code, then Select Kernel > Jupyter Kernel... > Bash."
