# Hunyuan3D-2 multiview geometry gate

This ComfyUI core workflow generates a shape-only GLB from front, back, left, and right RGBA references. It uses the official Hunyuan3D-2 multiview checkpoint and does not depend on a custom-node pack for shape generation.

## Run in ComfyUI

1. Run `_run/install.sh`, `_run/update_all_extension.sh`, and `_run/run.sh`.
2. Open the active ComfyUI URL printed by `run.sh`. On the current workstation the tested user instance is `http://127.0.0.1:8191`.
3. Open `Workflows > Hunyuan3D2MV_DefaultTamao_QualityV2_RTX3090`.
4. Select transparent references in the four `Load Image` nodes. The checked-in template currently expects:
   - `DefaultTamao_Hunyuan2MV_Front_Cutout_v002.png`
   - `DefaultTamao_Hunyuan2MV_Back_Cutout_v002.png`
   - `DefaultTamao_Hunyuan2MV_SideMirrored_Cutout_v002.png` as left
   - `DefaultTamao_Hunyuan2MV_Side_Cutout_v002.png` as right
5. Click `Run` once and review the exported GLB before starting any texture workflow.

The graph uses fixed seed `20260711`, 30 diffusion steps, CFG 7.5, a 3,072 latent, and octree resolution 384. The GLB is written below `output/Hunyuan2MV_DefaultTamao`.

## Geometry gate

Check front, back, and both profile renders before UV unwrap or texture generation. Reject the candidate if any of these are visible:

- incorrect head width or depth;
- melted eyes, mouth, or ears;
- concentric or rippled skull artifacts;
- inconsistent left and right profiles;
- open or fragmented bust boundaries.

The `QualityV2` DefaultTamao test completed successfully but failed this gate. The four independently prepared views were not geometrically consistent enough: the result had a flattened, oversized head, embossed eyelash artifacts, and rear-skull rippling. Texture generation was intentionally skipped.

## Measured stress-test envelope

- GPU: RTX 3090 with Unreal Engine still consuming GPU resources.
- Runtime: 4,278.885 seconds.
- Peak observed total VRAM use: about 17.6 GiB; no out-of-memory failure.
- Output: 586,370 vertices and 1,176,282 triangles at octree 384.

More polygons did not repair the conflicting reference geometry. For the next input revision, prefer a turntable-consistent reference set derived from one canonical head. Use octree 256 for the geometry gate, then raise it only after the silhouette and facial volumes pass review.

## ForgeGraph boundary

Treat the node graph as a provider adapter and preserve explicit artifacts at each boundary:

`prepare_rgba_views -> shape_generate_mv -> review_render -> geometry_gate -> mesh_optimize -> uv_unwrap -> texture_generate -> glb_publish`

The API-format prompt is stored in `templates/api/Hunyuan3D2MV_DefaultTamao_QualityV2_RTX3090_api.json`. Capture the ComfyUI prompt ID, input and model hashes, sampler settings, output hash, runtime, geometry metrics, and gate decision in the ForgeGraph execution manifest.
