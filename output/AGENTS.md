# ComfyUI Output Rules

ComfyUI output is generated evidence, not an input source of truth.

Required roots:

```text
output/shared/<domain>/<resource>/<version>/<stage>/
output/project/<PROJECT>/<domain>/<artifact>/<source>/<version>/<stage>/
output/legacy/  # reviewed migration target for unclassified historical output
```

Rules:

- New project workflows must write under `output/project/<PROJECT>`.
- Shared tools may write under `output/shared` only when no project identity is
  present in either the inputs or outputs.
- Use the source id and artifact version in the path. Put the workflow id and
  run id in the filename or run manifest.
- Keep Front, Side, and Back outputs separately addressable.
- Do not overwrite prior runs; use ComfyUI suffixes or a unique run id.
- Do not copy output into input automatically. Promotion requires review,
  provenance, and a destination manifest.
- Do not infer ownership for legacy root files. Move only when project or shared
  classification is explicit and record the migration.
- Logs, caches, temporary previews, and provider responses are not shared assets.
