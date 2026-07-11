# KTO ComfyUI Input Rules

This directory contains KTO-only ComfyUI inputs and reviewed stage handoffs.

Use this layout:

```text
source/<source_kind>/<character>/<asset_id>/vNNN/
reference/<domain>/<character>/<artifact>/vNNN/
stage/<domain>/<character>/<artifact>/<stage>/vNNN/
approved/<domain>/<character>/<artifact>/vNNN/
```

Rules:

- Use English identifiers and stable KTO/Tamao asset ids.
- Keep original sources immutable; create a new version for changed bytes.
- Record external source path, SHA-256, role, and review state in a manifest.
- Generated output is not input truth until a human explicitly promotes it.
- Stage handoffs must identify the producing workflow id, model, seed, and view.
- Do not store API keys, secret files, provider tokens, or unredacted responses.
- Do not place project inputs under `input/shared`.
- Do not overwrite an approved input or silently reuse a stale stage image.

For multi-view character work, `Front`, `Side`, and `Back` are separate assets.
`Side` means strict right profile unless the artifact manifest says otherwise.
