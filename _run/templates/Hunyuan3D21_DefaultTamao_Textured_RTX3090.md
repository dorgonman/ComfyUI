# Hunyuan3D 2.1 textured GLB quick test

This workflow generates a mesh and PBR textures from one front image. It is tuned for an RTX 3090 and uses the `visualbruno/ComfyUI-Hunyuan3d-2-1` custom nodes.

## Run

1. Run `_run/install.sh`, `_run/update_all_extension.sh`, and `_run/run.sh`.
2. Open `Workflows > Hunyuan3D21_DefaultTamao_Textured_RTX3090`.
3. In `Load Image With Transparency`, select an RGBA cutout with a transparent background.
4. Keep other GPU workloads below about 2 GB when running texture generation.
5. Click `Run` once. Shape generation is followed by UV unwrap, six-view texture synthesis, PBR bake, inpaint, and GLB preview.

The template starts with these RTX 3090 settings:

- Shape: 25 steps, guidance 5, SDPA, octree 256, 8,000 chunks, force offload.
- Mesh: remove floaters and degenerate faces, smooth normals, cap at 100,000 faces.
- Texture: six views at 512, 8 steps, guidance 3, 1,024 texture, fixed seed 20260710.

The shape GLB is written under `output/Hunyuan21_DefaultTamao`. The final textured GLB is written directly under `output` using the `output_mesh_name` value.

## Constraints

- The installed wrapper's shape path consumes one image. Back and side reference images are not multi-view geometry inputs.
- Texture generation can use about 21-23 GiB of GPU memory at these settings.
- The generated portrait is suitable for workflow evaluation. Inspect eyes, eyelashes, the open bust underside, UV seams, and topology before production use.
- If the custom rasterizer wheel is incompatible with the active Torch ABI, `install.sh` rebuilds and CUDA-smoke-tests it against the current environment.

## ForgeGraph reference stages

Treat the ComfyUI graph as an execution adapter with explicit artifacts between these stages:

`prepare_rgba -> shape_generate -> mesh_postprocess -> uv_unwrap -> multiview_texture -> pbr_bake_and_inpaint -> glb_publish -> review_render`

Use ComfyUI's prompt ID and history API as provider execution evidence. Keep asset naming, retries, acceptance policy, and final publication in ForgeGraph rather than embedding those policies in the node graph.
