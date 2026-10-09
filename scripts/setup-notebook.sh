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
# Re-runs are safe.
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
VENV="${ROOT_DIR}/.venv-notebook"
REQ="${ROOT_DIR}/docs/learning/notebooks/requirements.txt"
NOTEBOOK="${ROOT_DIR}/docs/learning/notebooks/lab-commands.ipynb"

if [[ "${1:-}" == "--check" ]]; then
  [[ -x "${VENV}/bin/jupyter" ]] || { echo "Run scripts/setup-notebook.sh first." >&2; exit 1; }
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
echo "✔ Jupyter kernel 'bash' registered for $(id -un) (uses ${VENV})"

(cd "$ROOT_DIR" && "${VENV}/bin/nbstripout" --install)
echo "✔ nbstripout filter installed in this clone: notebook outputs are stripped on commit"

echo ""
echo "Open ${NOTEBOOK#"${ROOT_DIR}"/} in VS Code, then Select Kernel > Jupyter Kernel... > Bash."
