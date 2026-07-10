#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
VENV_PYTHON="${PROJECT_ROOT}/.venv/Scripts/python.exe"

export HF_HOME="${COMFYUI_HF_HOME:-${PROJECT_ROOT}/models/huggingface}"
export HF_HUB_DISABLE_XET="${HF_HUB_DISABLE_XET:-1}"
export HF_HUB_DOWNLOAD_TIMEOUT="${HF_HUB_DOWNLOAD_TIMEOUT:-60}"

if [[ ! -x "${VENV_PYTHON}" ]]; then
    echo "Missing ${VENV_PYTHON}; run ${SCRIPT_DIR}/install.sh first." >&2
    exit 1
fi

mkdir -p "${SCRIPT_DIR}/logs"
cd "${PROJECT_ROOT}"
exec "${VENV_PYTHON}" -s "${PROJECT_ROOT}/main.py" --windows-standalone-build --listen "$@"
