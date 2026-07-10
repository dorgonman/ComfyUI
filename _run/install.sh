#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
VENV_DIR="${PROJECT_ROOT}/.venv"
VENV_PYTHON="${VENV_DIR}/Scripts/python.exe"
TRELLIS_DIR="${PROJECT_ROOT}/custom_nodes/ComfyUI-Trellis2"
TRELLIS_REPO="https://github.com/visualbruno/ComfyUI-Trellis2.git"
TRELLIS_PATCH="${SCRIPT_DIR}/addon/comfyui-trellis2-windows.patch"
TRELLIS_TEMPLATE_NAME="TRELLIS2_Quick_Test_RTX3090.json"
TRELLIS_TEMPLATE_SOURCE="${SCRIPT_DIR}/templates/${TRELLIS_TEMPLATE_NAME}"
TRELLIS_SAMPLE_NAME="TRELLIS2_Quick_Test.png"
TRELLIS_SAMPLE_SOURCE="${SCRIPT_DIR}/templates/assets/${TRELLIS_SAMPLE_NAME}"
TORCH_INDEX_URL="https://download.pytorch.org/whl/cu128"

if [[ ! -x "${VENV_PYTHON}" ]]; then
    if command -v py >/dev/null 2>&1; then
        py -3.12 -m venv "${VENV_DIR}"
    elif command -v python >/dev/null 2>&1; then
        python -m venv "${VENV_DIR}"
    else
        echo "Python 3.11 or 3.12 is required to create ${VENV_DIR}." >&2
        exit 1
    fi
fi

PYTHON_TAG="$("${VENV_PYTHON}" -c 'import sys; print(f"cp{sys.version_info.major}{sys.version_info.minor}")')"
case "${PYTHON_TAG}" in
    cp311|cp312) ;;
    *)
        echo "ComfyUI-Trellis2 Windows wheels require Python 3.11 or 3.12; found ${PYTHON_TAG}." >&2
        exit 1
        ;;
esac

if [[ ! -e "${TRELLIS_DIR}" ]]; then
    git clone "${TRELLIS_REPO}" "${TRELLIS_DIR}"
elif [[ ! -d "${TRELLIS_DIR}/.git" ]]; then
    echo "${TRELLIS_DIR} exists but is not a Git checkout." >&2
    exit 1
fi

if git -C "${TRELLIS_DIR}" apply --unidiff-zero --reverse --check "${TRELLIS_PATCH}" >/dev/null 2>&1; then
    echo "ComfyUI-Trellis2 Windows patch is already applied."
elif git -C "${TRELLIS_DIR}" apply --unidiff-zero --check "${TRELLIS_PATCH}"; then
    git -C "${TRELLIS_DIR}" apply --unidiff-zero "${TRELLIS_PATCH}"
else
    echo "Cannot apply ${TRELLIS_PATCH}; inspect the extension changes before continuing." >&2
    exit 1
fi

if [[ -f "${TRELLIS_TEMPLATE_SOURCE}" ]]; then
    TRELLIS_TEMPLATE_RELATIVE="example_workflows/${TRELLIS_TEMPLATE_NAME}"
    TRELLIS_TEMPLATE_DEST="${TRELLIS_DIR}/${TRELLIS_TEMPLATE_RELATIVE}"
    USER_WORKFLOW_DIR="${PROJECT_ROOT}/user/default/workflows"

    mkdir -p "$(dirname -- "${TRELLIS_TEMPLATE_DEST}")" "${USER_WORKFLOW_DIR}"
    cp -f "${TRELLIS_TEMPLATE_SOURCE}" "${TRELLIS_TEMPLATE_DEST}"
    cp -f "${TRELLIS_TEMPLATE_SOURCE}" "${USER_WORKFLOW_DIR}/${TRELLIS_TEMPLATE_NAME}"

    if ! grep -qxF "${TRELLIS_TEMPLATE_RELATIVE}" "${TRELLIS_DIR}/.git/info/exclude"; then
        printf '%s\n' "${TRELLIS_TEMPLATE_RELATIVE}" >> "${TRELLIS_DIR}/.git/info/exclude"
    fi
fi

TRELLIS_CACHE_RELATIVE="triton_caches/"
if ! grep -qxF "${TRELLIS_CACHE_RELATIVE}" "${TRELLIS_DIR}/.git/info/exclude"; then
    printf '%s\n' "${TRELLIS_CACHE_RELATIVE}" >> "${TRELLIS_DIR}/.git/info/exclude"
fi

if [[ -f "${TRELLIS_SAMPLE_SOURCE}" ]]; then
    mkdir -p "${PROJECT_ROOT}/input"
    cp -f "${TRELLIS_SAMPLE_SOURCE}" "${PROJECT_ROOT}/input/${TRELLIS_SAMPLE_NAME}"
fi

"${VENV_PYTHON}" --version
"${VENV_PYTHON}" -m pip install --upgrade pip
"${VENV_PYTHON}" -m pip install --upgrade \
    torch==2.8.0 torchvision==0.23.0 torchaudio==2.8.0 \
    --index-url "${TORCH_INDEX_URL}"

INSIGHTFACE_WHEEL="${SCRIPT_DIR}/addon/insightface-0.7.3-${PYTHON_TAG}-${PYTHON_TAG}-win_amd64.whl"
if [[ -f "${INSIGHTFACE_WHEEL}" ]]; then
    "${VENV_PYTHON}" -m pip install "${INSIGHTFACE_WHEEL}"
fi

"${VENV_PYTHON}" -m pip install -r "${PROJECT_ROOT}/requirements.txt"
"${VENV_PYTHON}" -m pip install \
    "transformers>=4.57.2,<5" "xformers==0.0.32.post2" zstandard \
    "triton-windows>=3.4,<3.5"

while IFS= read -r -d '' git_dir; do
    repo="${git_dir%/.git}"
    if [[ -f "${repo}/requirements.txt" ]]; then
        echo "Installing requirements for ${repo}"
        "${VENV_PYTHON}" -m pip install -r "${repo}/requirements.txt"
    fi
done < <(find "${PROJECT_ROOT}/custom_nodes" -path "${PROJECT_ROOT}/custom_nodes/.disabled" -prune -o -type d -name .git -prune -print0)

# Reassert the ABI expected by the bundled TRELLIS.2 Windows wheels after all
# custom-node requirements have been processed.
"${VENV_PYTHON}" -m pip install \
    torch==2.8.0 torchvision==0.23.0 torchaudio==2.8.0 \
    --index-url "${TORCH_INDEX_URL}"

TRELLIS_WHEEL_DIR="${TRELLIS_DIR}/wheels/Windows/Torch280"
TRELLIS_WHEEL_ABI="torch280-${PYTHON_TAG}-$(git -C "${TRELLIS_DIR}" rev-parse HEAD)"
TRELLIS_WHEEL_MARKER="${VENV_DIR}/.trellis2-wheel-abi"
wheel_install_args=(--no-deps)
if [[ ! -f "${TRELLIS_WHEEL_MARKER}" || "$(<"${TRELLIS_WHEEL_MARKER}")" != "${TRELLIS_WHEEL_ABI}" ]]; then
    wheel_install_args=(--force-reinstall --no-deps)
fi

for package in cumesh nvdiffrast nvdiffrec_render flex_gemm o_voxel; do
    wheels=("${TRELLIS_WHEEL_DIR}/${package}"-*-${PYTHON_TAG}-${PYTHON_TAG}-win_amd64.whl)
    if [[ ${#wheels[@]} -ne 1 || ! -f "${wheels[0]}" ]]; then
        echo "Expected one ${package} wheel for ${PYTHON_TAG} in ${TRELLIS_WHEEL_DIR}." >&2
        exit 1
    fi
    "${VENV_PYTHON}" -m pip install "${wheel_install_args[@]}" "${wheels[0]}"
done
printf '%s\n' "${TRELLIS_WHEEL_ABI}" > "${TRELLIS_WHEEL_MARKER}"

TRELLIS_CACHE_DIR="${TRELLIS_DIR}/triton_caches/shared_windows"
mkdir -p "${TRELLIS_CACHE_DIR}"
TRELLIS_CACHE_DIR_WINDOWS="$(cygpath -m "${TRELLIS_CACHE_DIR}")"
TRITON_CACHE_DIR="${TRELLIS_CACHE_DIR_WINDOWS}" "${VENV_PYTHON}" -c \
    'from triton.runtime.driver import driver; driver.active.get_benchmarker(); print("Triton shared cache is ready.")'

if [[ "${SKIP_TRELLIS_MODELS:-0}" != "1" ]]; then
    "${VENV_PYTHON}" - "${PROJECT_ROOT}" <<'PY'
import shutil
import sys
from pathlib import Path

from huggingface_hub import snapshot_download
from huggingface_hub.errors import GatedRepoError, LocalEntryNotFoundError

models_dir = Path(sys.argv[1]) / "models"
for repo_id in (
    "facebook/dinov3-vitl16-pretrain-lvd1689m",
    "microsoft/TRELLIS.2-4B",
):
    target = models_dir / Path(repo_id)
    if repo_id.startswith("facebook/") and (target / "config.json").is_file() and (target / "model.safetensors").is_file():
        print(f"Using existing {repo_id} at {target}", flush=True)
        continue
    print(f"Downloading {repo_id} to {target}", flush=True)
    try:
        snapshot_download(repo_id=repo_id, local_dir=target)
    except GatedRepoError as error:
        try:
            cached = Path(snapshot_download(repo_id=repo_id, local_files_only=True))
        except LocalEntryNotFoundError as cache_error:
            raise RuntimeError(f"Access to {repo_id} requires 'hf auth login'.") from error
        shutil.copytree(cached, target, dirs_exist_ok=True)
PY
fi
