from __future__ import annotations

import json
import os
import re
import subprocess
import time
from pathlib import Path

import folder_paths
from PIL import Image


_LIVE_CONFIRMATION = "CONSUME_MESHY_CREDITS"
_DEFAULT_CLI = (
    r"C:\Users\dorgon.chang\.agents\skills\kano\kano-ai-3d-asset-skill"
    r"\scripts\kano-ai-3d.bat"
)
_DEFAULT_SECRET_FILE = r"C:\Users\dorgon.chang\.kano\secret.env"
_DEFAULT_PROJECT_ROOT = r"E:\_gamedev\KanoTamaoProject"


def _read_env_value(path: Path, name: str) -> str:
    if not path.is_file():
        return ""
    pattern = re.compile(rf"^\s*(?:export\s+)?{re.escape(name)}\s*=\s*(.*)\s*$")
    for line in path.read_text(encoding="utf-8-sig").splitlines():
        match = pattern.match(line)
        if not match:
            continue
        value = match.group(1).strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in {'"', "'"}:
            value = value[1:-1]
        return value
    return ""


def _save_tensor_png(image, path: Path) -> None:
    if image is None or len(image.shape) != 4 or image.shape[0] < 1:
        raise ValueError("Each Meshy view must be a non-empty ComfyUI IMAGE tensor.")
    pixels = image[0].detach().cpu().clamp(0, 1).mul(255).byte().numpy()
    Image.fromarray(pixels).save(path, format="PNG", compress_level=4)


def _parse_output_folder(stdout: str) -> Path | None:
    match = re.search(r"^\s*output folder:\s*(.+?)\s*$", stdout, re.MULTILINE)
    return Path(match.group(1).strip()) if match else None


def _read_provider_state(output_folder: Path | None) -> tuple[str, str]:
    if output_folder is None:
        return "", "Unknown"
    task_file = output_folder / "provider_task.json"
    if not task_file.is_file():
        return "", "Unknown"
    try:
        payload = json.loads(task_file.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return "", "Unknown"
    task_id = str(payload.get("external_task_id") or "")
    status = str(payload.get("status") or "Unknown")
    return task_id, status


def _find_model(output_folder: Path | None) -> str:
    if output_folder is None or not output_folder.is_dir():
        return ""
    models = sorted(
        (
            path
            for path in output_folder.rglob("*")
            if path.is_file() and path.suffix.lower() in {".glb", ".fbx"}
        ),
        key=lambda path: (path.suffix.lower() != ".glb", path.name.lower()),
    )
    return str(models[0].resolve()) if models else ""


def _resolve_native_cli(cli: Path) -> Path:
    if cli.suffix.lower() not in {".bat", ".cmd"}:
        return cli
    repo_root = cli.parent.parent
    candidates = (
        repo_root / "src/cpp/out/bin/windows-msbuild/Release/kano-ai-3d.exe",
        repo_root / "src/cpp/out/bin/windows-msbuild/Debug/kano-ai-3d.exe",
        repo_root / "src/cpp/out/bin/default/Debug/kano-ai-3d.exe",
    )
    for candidate in candidates:
        if candidate.is_file():
            return candidate.resolve()
    return cli


def _clean_child_environment(source: dict[str, str]) -> dict[str, str]:
    env = source.copy()
    comfy_root = Path(__file__).resolve().parents[2]
    path_entries = []
    for entry in env.get("PATH", "").split(os.pathsep):
        if not entry:
            continue
        try:
            resolved = Path(entry).resolve()
        except OSError:
            path_entries.append(entry)
            continue
        if str(resolved).lower().startswith(str(comfy_root).lower()):
            continue
        path_entries.append(entry)
    env["PATH"] = os.pathsep.join(path_entries)
    for name in ("PYTHONHOME", "PYTHONPATH", "VIRTUAL_ENV"):
        env.pop(name, None)
    return env


def _write_bridge_config(workdir: Path, project_root: Path) -> None:
    studio = project_root / "Studio"
    assetlab = studio / "_AssetLab"
    incubation = assetlab / "BaseGame/00_Incubation"
    cache = project_root / ".kano/cache/ai_asset_jobs"
    temp = project_root / ".kano/tmp/ai_asset_generation"

    def q(path: Path) -> str:
        return path.resolve().as_posix()

    config = f'''[project]
id = "kto"
display_name = "Kano Tamao"

[providers]
default_3d = "meshy"

[providers.meshy]
api_base_url = "https://api.meshy.ai"
api_key_env = "MESHY_API_KEY"
poll_interval_seconds = 5
timeout_seconds = 2700

[paths]
assetlab_root = "{q(assetlab)}"
job_cache_root = "{q(cache)}"
temp_root = "{q(temp)}"

[paths.assetlab]
stage_root = "{q(incubation)}"
inbox = "{q(incubation / '00_Inbox')}"
ai_generated = "{q(incubation / '01_AI_Generated')}"
internal_work = "{q(incubation / '02_Internal_Work')}"
assembly_lab = "{q(incubation / '04_AssemblyLab')}"
rejected = "{q(incubation / '90_Rejected')}"
archive = "{q(incubation / '99_Archive')}"
registry = "{q(incubation / '_Registry')}"

[outputs]
default_stage = "ai_generated"
overwrite = false
create_timestamped_job_folder = true
write_prompt_file = true
write_provider_task_file = true
write_manifest = true

[outputs.model_3d]
default_subdir = "Model3D"
default_format = "glb"
default_readiness = "Candidate"

[manifest]
filename = "kano-ai-asset-manifest.json"
schema_version = 1
default_review_status = "NeedsReview"
default_readiness = "Candidate"
human_gate_required = true
'''
    (workdir / "kano_ai_asset_config.toml").write_text(config, encoding="utf-8")


class KanoMeshyMultiImageTo3D:
    @classmethod
    def INPUT_TYPES(cls):
        return {
            "required": {
                "front": ("IMAGE",),
                "side": ("IMAGE",),
                "back": ("IMAGE",),
                "execution_mode": (["dry_run", "live"], {"default": "dry_run"}),
                "confirm_live": (
                    "STRING",
                    {
                        "default": "",
                        "multiline": False,
                        "tooltip": f"For live execution enter exactly: {_LIVE_CONFIRMATION}",
                    },
                ),
                "output_name": (
                    "STRING",
                    {"default": "DefaultTamao_BodyCore_Meshy_Control_v001"},
                ),
                "seed": (
                    "INT",
                    {"default": 2026071101, "min": 0, "max": 2147483647},
                ),
            },
            "optional": {
                "secret_file": ("STRING", {"default": _DEFAULT_SECRET_FILE}),
                "project_root": ("STRING", {"default": _DEFAULT_PROJECT_ROOT}),
                "cli_path": ("STRING", {"default": _DEFAULT_CLI}),
                "timeout_minutes": (
                    "INT",
                    {"default": 45, "min": 5, "max": 180},
                ),
            },
        }

    RETURN_TYPES = ("STRING", "STRING", "STRING", "STRING")
    RETURN_NAMES = ("model_file", "meshy_task_id", "status", "output_folder")
    FUNCTION = "run"
    CATEGORY = "KTO/Provider/Meshy"
    OUTPUT_NODE = True
    DESCRIPTION = (
        "Pure ComfyUI bridge to kano-ai-3d Meshy multi-image-to-3D. "
        "The API key is injected only into the child process and is never stored in the workflow."
    )

    def run(
        self,
        front,
        side,
        back,
        execution_mode,
        confirm_live,
        output_name,
        seed,
        secret_file=_DEFAULT_SECRET_FILE,
        project_root=_DEFAULT_PROJECT_ROOT,
        cli_path=_DEFAULT_CLI,
        timeout_minutes=45,
    ):
        del seed  # Cache-busting input; Meshy multi-image generation is non-deterministic.

        safe_name = re.sub(r"[^A-Za-z0-9_-]+", "_", output_name).strip("_")
        if not safe_name:
            raise ValueError("output_name must contain at least one letter or number.")

        cli = Path(os.path.expandvars(os.path.expanduser(cli_path))).resolve()
        root = Path(os.path.expandvars(os.path.expanduser(project_root))).resolve()
        if not cli.is_file():
            raise FileNotFoundError(f"kano-ai-3d CLI wrapper not found: {cli}")
        if not root.is_dir():
            raise FileNotFoundError(f"Kano project root not found: {root}")

        if execution_mode == "live" and confirm_live != _LIVE_CONFIRMATION:
            raise ValueError(
                f"Live Meshy execution requires confirm_live={_LIVE_CONFIRMATION}"
            )

        stamp = time.strftime("%Y%m%dT%H%M%S")
        input_dir = (
            Path(folder_paths.get_temp_directory())
            / "kano_meshy_comfy"
            / f"{safe_name}_{stamp}"
        )
        input_dir.mkdir(parents=True, exist_ok=False)
        image_paths = [input_dir / "front.png", input_dir / "side.png", input_dir / "back.png"]
        for tensor, path in zip((front, side, back), image_paths, strict=True):
            _save_tensor_png(tensor, path)

        command_root = root
        if not (command_root / "kano_ai_asset_config.toml").is_file():
            command_root = input_dir / "cli_project"
            command_root.mkdir(parents=True, exist_ok=False)
            _write_bridge_config(command_root, root)

        args = [
            "generate",
            "multi-image-to-3d",
            "--provider",
            "meshy",
        ]
        for path in image_paths:
            args.extend(("--image", str(path)))
        args.extend(("--output-name", safe_name))
        if execution_mode == "dry_run":
            args.append("--dry-run")

        env = _clean_child_environment(os.environ)
        secret_value = ""
        if execution_mode == "live":
            secret_value = env.get("MESHY_API_KEY", "") or _read_env_value(
                Path(os.path.expandvars(os.path.expanduser(secret_file))),
                "MESHY_API_KEY",
            )
            if not secret_value:
                raise RuntimeError(
                    "MESHY_API_KEY is not set in the ComfyUI environment or configured secret file."
                )
            env["MESHY_API_KEY"] = secret_value

        native_cli = _resolve_native_cli(cli)
        if native_cli.suffix.lower() in {".bat", ".cmd"}:
            command_line = subprocess.list2cmdline([str(cli), *args])
            command = [os.environ.get("COMSPEC", "cmd.exe"), "/d", "/s", "/c", command_line]
        else:
            command = [str(native_cli), *args]

        try:
            result = subprocess.run(
                command,
                cwd=str(command_root),
                env=env,
                capture_output=True,
                text=True,
                encoding="utf-8",
                errors="replace",
                timeout=int(timeout_minutes) * 60,
                check=False,
            )
        finally:
            if secret_value:
                secret_value = ""
            env.pop("MESHY_API_KEY", None)

        combined = "\n".join(part for part in (result.stdout, result.stderr) if part)
        if result.returncode != 0:
            safe_tail = combined[-2000:]
            raise RuntimeError(
                f"kano-ai-3d exited with code {result.returncode}.\n{safe_tail}"
            )

        output_folder = _parse_output_folder(result.stdout)
        task_id, provider_status = _read_provider_state(output_folder)
        model_file = _find_model(output_folder)
        status = (
            f"mode={execution_mode}; provider_status={provider_status}; "
            f"network_attempted={'true' if execution_mode == 'live' else 'false'}; "
            f"model_downloaded={'true' if model_file else 'false'}"
        )
        return (
            model_file,
            task_id,
            status,
            str(output_folder.resolve()) if output_folder else "",
        )


NODE_CLASS_MAPPINGS = {
    "KanoMeshyMultiImageTo3D": KanoMeshyMultiImageTo3D,
}

NODE_DISPLAY_NAME_MAPPINGS = {
    "KanoMeshyMultiImageTo3D": "Kano Meshy Multi-Image to 3D (BYOK)",
}
