# Kano Meshy ComfyUI Bridge

This node keeps the user workflow entirely inside ComfyUI while delegating the
provider transport, polling, artifact download, redaction, and manifest writing
to the existing native `kano-ai-3d` CLI.

Security contract:

- `MESHY_API_KEY` is read from the ComfyUI process environment first.
- The optional fallback is `C:\Users\dorgon.chang\.kano\secret.env`.
- The key is injected only into the child process and is never returned, logged,
  embedded in workflow JSON, or written to PNG metadata.
- `dry_run` is the default and performs no provider request.
- `live` requires the explicit confirmation text `CONSUME_MESHY_CREDITS`.

Inputs are three ComfyUI IMAGE values in strict Front, Side, Back order. Live
outputs include the downloaded model path, Meshy task ID, provider status, and
the Kano stage folder. Connect `model_file` to ComfyUI's `Preview3D` node after
a successful live run.
