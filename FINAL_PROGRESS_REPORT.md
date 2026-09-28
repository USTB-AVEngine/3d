# AVEngine Human Sound Source Asset V1 Progress Report

Date: 2026-09-20

## 1. Completed work

### Pipeline audit artifact

Created:

```text
docs/human_sound_source_pipeline_audit.md
```

The audit separates locally measured evidence, handoff-recorded information, remote-unverified items, and blocked commands. It records the Flux2, ISNet, Pixal3D, manifest, and output-root questions that must be answered from `/data/lx/code/spear`.

### Existing Pixal3D output inspection

Inspected the local animal sample `pixal_raw_1024.glb` directly through its GLB JSON chunk.

Measured values:

- glTF 2.0 GLB;
- 1 mesh and 1 primitive;
- 707,898 vertices;
- 998,962 triangles;
- 1 material;
- 2 textures/images;
- no skin;
- no animation;
- required `EXT_texture_webp` extension.

This supports a static semantic Human Sound Source V1 route. It does not demonstrate rigged or animated human output.

### Human asset directory contract

Created the local workspace structure for all five categories:

```text
assets/human_sound_sources/
  singer_microphone/{source,metadata,generation}/
  phone_call/{source,metadata,generation}/
  guitar_player/{source,metadata,generation}/
  violin_player/{source,metadata,generation}/
  pianist/{source,metadata,generation}/
```

The requested remote structure under `/data/datasets/avengine_workspaces/users/lx/human_sound_source_assets_v1/` was not created because SSH never executed.

### Prompt system

Created:

```text
docs/human_sound_source_prompt_v1.md
```

The document contains a positive and negative Flux2 prompt for:

1. singer with microphone;
2. person talking on phone;
3. acoustic guitar player;
4. violin player;
5. pianist.

Each category also records required action semantics and acoustic/visual/fallback anchors.

The five category `generation_plan.yaml` and pre-generation `asset_metadata.yaml` files remain in place. All generated-file paths, seeds, checksums, polygon counts, anchor coordinates, and validation statuses remain null or not started.

## 2. Current asset counts

| Artifact | Count |
|---|---:|
| Planned human sound-source categories | 5 |
| Flux2 human candidate images | 0 |
| ISNet human RGBA images | 0 |
| Pixal3D human raw GLBs | 0 |
| Validated human sound-source GLBs | 0 |
| Registered AVEngine human assets | 0 |

## 3. Generation result

Generation did not start.

Current answer to the key question:

> Has a Human Sound Source GLB been produced?

**No.**

No candidate image, RGBA segmentation, GLB, inspection JSON, or SHA-256 was fabricated.

## 4. Blocking reason

Two read-only SSH attempts were made against the user-specified alias:

```text
ssh -o BatchMode=yes -o ConnectTimeout=15 avengine-lab <read-only checks>
```

Both attempts were rejected before process execution because the external permission-review service returned HTTP 503. The command did not reach `avengine-lab`.

Consequently, the following could not be verified:

- `/data/lx/code/spear` source and repository instructions;
- Flux2 entry point, prompt interface, model path, and image dimensions;
- `controlled_animal_isnet_worker.py` arguments;
- `run_controlled_animal_pixal_jobs.py` manifest schema;
- GPU availability;
- current model cache;
- authenticated `human_sound_source_assets_v1` output root.

This is not evidence of an SSH authentication failure or a server-side failure.

## 5. Next actions

Resume at Phase 1, not Phase 4.

1. Run the pending read-only commands listed in `docs/human_sound_source_pipeline_audit.md` once SSH execution is available.
2. Read any remote `AGENTS.md` before changing files.
3. Verify the Flux2 runner, negative-prompt support, model path, GPU state, dimensions, and seed logging.
4. Verify ISNet alpha handling and Pixal3D manifest/output-root requirements.
5. Create the five remote category directories only in the personal workspace.
6. Authenticate the exact `/data/datasets/avengine_workspaces/users/lx/human_sound_source_assets_v1` output root.
7. Generate one Singer candidate only.
8. Continue to ISNet only if the Singer image passes mouth/microphone/hand semantics.
9. Continue to Pixal3D only if the RGBA preserves the complete microphone and human silhouette.
10. Measure the produced GLB and generate SHA-256/inspection metadata only from the real file.

No AVEngine core or Habitat code should be modified during these steps.

