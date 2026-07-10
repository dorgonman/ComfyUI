#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
TRELLIS_DIR="${PROJECT_ROOT}/custom_nodes/ComfyUI-Trellis2"
TRELLIS_PATCH="${SCRIPT_DIR}/addon/comfyui-trellis2-windows.patch"
failures=0

while IFS= read -r -d '' git_dir; do
    repo="${git_dir%/.git}"
    branch="$(git -C "${repo}" branch --show-current)"
    managed_patch=""

    if [[ "${repo}" == "${TRELLIS_DIR}" ]] && git -C "${repo}" apply --unidiff-zero --reverse --check "${TRELLIS_PATCH}" >/dev/null 2>&1; then
        git -C "${repo}" apply --unidiff-zero --reverse "${TRELLIS_PATCH}"
        if [[ -n "$(git -C "${repo}" status --porcelain)" ]]; then
            git -C "${repo}" apply --unidiff-zero "${TRELLIS_PATCH}"
            echo "Skipping extension with changes beyond the managed patch: ${repo}"
            continue
        fi
        managed_patch="${TRELLIS_PATCH}"
    fi

    if [[ -n "$(git -C "${repo}" status --porcelain)" ]]; then
        echo "Skipping dirty extension: ${repo}"
        continue
    fi

    if [[ -z "${branch}" ]]; then
        echo "Skipping detached extension: ${repo}"
        continue
    fi

    if ! git -C "${repo}" remote get-url origin >/dev/null 2>&1; then
        echo "Skipping extension without origin: ${repo}"
        continue
    fi

    echo "Updating ${repo} on branch ${branch}"
    if ! git -C "${repo}" pull --ff-only origin "${branch}"; then
        if [[ -n "${managed_patch}" ]]; then
            git -C "${repo}" apply --unidiff-zero "${managed_patch}"
        fi
        echo "Failed to update ${repo}" >&2
        failures=$((failures + 1))
    elif [[ -n "${managed_patch}" ]]; then
        if git -C "${repo}" apply --unidiff-zero --check "${managed_patch}" && git -C "${repo}" apply --unidiff-zero "${managed_patch}"; then
            echo "Reapplied managed Windows patch to ${repo}"
        else
            echo "Failed to reapply managed Windows patch to ${repo}" >&2
            failures=$((failures + 1))
        fi
    fi
done < <(find "${PROJECT_ROOT}/custom_nodes" -path "${PROJECT_ROOT}/custom_nodes/.disabled" -prune -o -type d -name .git -prune -print0)

if (( failures > 0 )); then
    exit 1
fi
