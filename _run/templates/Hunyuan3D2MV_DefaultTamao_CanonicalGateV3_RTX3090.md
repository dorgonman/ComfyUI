# Hunyuan3D-2 canonical multiview geometry gate

This workflow is a controlled reconstruction test. It renders four transparent views from one existing textured GLB, then asks the ComfyUI core Hunyuan3D-2 multiview model to reconstruct the same geometry. The goal is to separate model limitations from inconsistent independently generated reference images.

## Prepare the canonical views

Run Blender in background mode with the reusable review renderer:

```powershell
& 'C:\Program Files\Blender Foundation\Blender 3.4\blender.exe' `
  --background `
  --python 'D:\Web\ComfyUI\_run\hunyuan_render_review.py' `
  -- '<source.glb>' 'D:\Web\ComfyUI\input\DefaultTamao_MeshyV5_Canonical' preserve transparent
```

The renderer creates `front.png`, `back.png`, `left.png`, and `right.png` with RGBA transparency. The current DefaultTamao control source is `Meshy_AI_DefaultTamao_L01_Port_v5.glb`; derived renders remain local test inputs and are not checked into the ComfyUI repository.

## Run the gate

1. Open the active ComfyUI URL printed by `_run/run.sh`.
2. Open `Workflows > Hunyuan3D2MV_DefaultTamao_CanonicalGateV3_RTX3090`.
3. Confirm that all four `Load Image` nodes show the canonical views.
4. Click `Run` once.
5. Render the exported GLB from the same four cameras and compare silhouette, facial volumes, ears, neck, and bust boundary against the canonical inputs.

The gate uses seed `20260712`, 20 steps, CFG 7.5, a 3,072 latent, and octree resolution 256. It is intentionally cheaper than the QualityV2 stress profile. Promote a candidate to octree 384 and PBR texture only after the geometry passes.

When another workflow is using most GPU memory, append `cpu` after the renderer arguments. This switches the review render to 16-sample Cycles CPU mode without interrupting the active ComfyUI queue.

## Interpretation

- If this consistent-view control passes while the independent-image workflow fails, input-view consistency is the primary bottleneck.
- If this control also fails, more octree resolution or texture work will not repair the underlying Hunyuan shape reconstruction.
- This control is not a replacement for producing a new asset from concept art because the source geometry already exists. It is provider-fidelity evidence for ForgeGraph routing and quality policy.

The API-format prompt is stored in `templates/api/Hunyuan3D2MV_DefaultTamao_CanonicalGateV3_RTX3090_api.json`.

## DefaultTamao V3 measured result

- Prompt ID: `00f4a4ff-78e7-46b2-97e3-1dfd58da15d6`.
- Runtime under concurrent Unreal Engine GPU load: 2,515.509 seconds.
- Output: 107,784 vertices, 216,512 triangles, 546 connected components, not watertight.
- Global silhouette gate: passed. Head, neck, shoulders, and rear skull remained coherent across all four views.
- Hero identity gate: failed. Eyes and eyelids collapsed into narrow recessed forms, nose and mouth volumes were over-smoothed, and the lower bust retained visible distortion.
- Promotion decision: skip octree 384 and PBR texture for this candidate.

The controlled result shows that consistent reference views fix the large proportion failure seen with independently generated images. They do not make the Hunyuan3D-2 multiview shape model reproduce hero-face identity at Meshy v5 fidelity. Route this provider to blockout or silhouette work, and keep a stricter provider for hero-head production unless a later model passes the same control.
