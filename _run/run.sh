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

launch_args=("$@")
has_explicit_port=0
for arg in "${launch_args[@]}"; do
    if [[ "${arg}" == "--port" || "${arg}" == --port=* ]]; then
        has_explicit_port=1
        break
    fi
done

if [[ ${has_explicit_port} -eq 0 ]]; then
    requested_port="${COMFYUI_PORT:-8188}"
    selected_port="$("${VENV_PYTHON}" - "${requested_port}" <<'PY'
import socket
import sys

requested = int(sys.argv[1])
candidates = [requested, *range(max(requested + 1, 8191), 8300)]
for port in candidates:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as probe:
        probe.settimeout(0.2)
        if probe.connect_ex(("127.0.0.1", port)) == 0:
            continue
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        try:
            sock.bind(("0.0.0.0", port))
            sock.listen(1)
        except OSError:
            continue
    print(port)
    break
else:
    raise SystemExit("No free ComfyUI port found in the configured range.")
PY
)"
    launch_args+=(--port "${selected_port}")
    echo "ComfyUI URL: http://127.0.0.1:${selected_port}"
fi

exec "${VENV_PYTHON}" -s "${PROJECT_ROOT}/main.py" --windows-standalone-build --listen "${launch_args[@]}"
