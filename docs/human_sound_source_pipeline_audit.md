# Human Sound Source Pipeline Audit

Date: 2026-09-20

Status: partial audit; remote repository inspection blocked before SSH connection

## Evidence levels

- `VERIFIED_LOCAL`: measured from a file or directory available in the current workspace.
- `HANDOFF_RECORDED`: supplied by the project handoff but not re-verified in source code during this run.
- `REMOTE_UNVERIFIED`: requires inspection on `ssh avengine-lab`.
- `BLOCKED`: the attempted command did not reach the remote server.

## Remote access attempt

The requested read-only reconnaissance command targeted:

```text
ssh -o BatchMode=yes -o ConnectTimeout=15 avengine-lab <hostname/path/python/GPU checks>
```

Result: `BLOCKED`. The external permission-review service returned HTTP 503 before the command executed. This is not an SSH authentication error and not evidence that `avengine-lab` is unavailable.

## 1. Flux2 entry point

Status: `REMOTE_UNVERIFIED`.

The local workspace contains no Flux/Flux2 source, runner, manifest, or generation log. The remote audit must search `/data/lx/code/spear` for:

```text
flux, Flux, image_generation, candidate, prompt, seed
```

Required facts before generation:

- exact entry script/module;
- required model/checkpoint path;
- prompt and negative-prompt interface;
- image width/height and output format;
- seed, batch-size, and output-directory arguments;
- whether the runner writes provenance alongside the image.

## 2. Input format

Status: `HANDOFF_RECORDED`, exact dimensions `REMOTE_UNVERIFIED`.

Recorded flow:

```text
Flux2 candidate image -> ISNet -> RGBA image -> Pixal3D
```

The Pixal3D input is recorded as RGBA. Pixel dimensions, alpha convention, accepted file extensions, color space, and preprocessing behavior must be read from the deployed loader instead of guessed.

## 3. Output format

Status: `VERIFIED_LOCAL` for one animal sample.

Inspected file:

```text
C:/Users/17738/Desktop/animal_glb_check/pixal_raw_1024.glb
```

Measured directly from the GLB JSON chunk:

| Field | Value |
|---|---:|
| Container | glTF 2.0 GLB |
| File size | 37,489,760 bytes |
| Generator | `https://github.com/mikedh/trimesh` |
| Scene count | 1 |
| Node count | 2 |
| Mesh count | 1 |
| Primitive count | 1 |
| Vertex count | 707,898 |
| Triangle count | 998,962 |
| Material count | 1 |
| Texture/image count | 2 / 2 |
| Skin count | 0 |
| Animation count | 0 |
| Required extension | `EXT_texture_webp` |

The measurement applies only to this sample. It must not be copied into future human metadata.

## 4. ISNet invocation

Status: `HANDOFF_RECORDED`, invocation `REMOTE_UNVERIFIED`.

Expected worker named by the task:

```text
controlled_animal_isnet_worker.py
```

The remote audit must record:

- full repository-relative path;
- CLI arguments and manifest format;
- input/output naming rules;
- alpha polarity and mask post-processing;
- whether multiple disconnected foreground components are preserved;
- behavior on thin structures such as microphone shafts, guitar necks, and violin bows.

## 5. Pixal3D runner and manifest

Status: `HANDOFF_RECORDED`, schema `REMOTE_UNVERIFIED`.

Expected runner:

```text
tools/run_controlled_animal_pixal_jobs.py
```

Known prior behavior:

- the runner enforces an authenticated output root;
- a manifest fixed to `pixal_three_animals_v1` rejected a launch using `pixal_three_animals_v2`;
- the raw model output is named `pixal_raw_1024.glb`;
- offline NAF loading was configured through `PIXAL3D_NAF_REPO=/data/models/torch/hub/valeoai_NAF_main`;
- pipeline initialization previously reached `INIT_PIPELINE_OK`.

The exact manifest fields, validation code, job selection, resume behavior, and error-status files remain unverified.

## 6. Output-root rule

Status: `HANDOFF_RECORDED`.

Proposed human output root:

```text
/data/datasets/avengine_workspaces/users/lx/human_sound_source_assets_v1
```

This path must be authorized using the same exact string used at launch. No controlled generation job should start until the manifest and runtime argument agree.

## 7. Human-asset reuse assessment

### Directly reusable concepts

- candidate image generation and manual semantic selection;
- foreground segmentation into RGBA;
- one-image-at-a-time Pixal3D reconstruction;
- immutable preservation of `pixal_raw_1024.glb`;
- controlled output-root safety check;
- later GLB geometry inspection and metadata generation.

### Reuse risks requiring a human-specific gate

- hand-to-prop geometry and finger correctness;
- small phone and microphone geometry near the face;
- violin bow and other thin-part mask survival;
- self-occlusion around instrument bodies;
- large piano/bench composite footprint;
- likely single-mesh output, preventing object-node anchors;
- approximately one-million-triangle raw output in the inspected animal sample;
- no demonstrated rig or animation output;
- Habitat support for required `EXT_texture_webp` remains untested.

Conclusion: the animal pipeline is suitable as a starting point for `Level-1 static semantic human assets`, not as evidence of a rigged or animated human pipeline.

## Remote audit commands pending execution

These are read-only and should be run in order when SSH access is available:

```bash
cd /data/lx/code/spear
find .. -name AGENTS.md -print
rg -n -i 'flux|image[_ -]?generation|candidate|prompt|seed' .
rg -n 'controlled_animal_isnet_worker|run_controlled_animal_pixal_jobs|pixal_raw_1024|output.root|output_root' .
sed -n '1,260p' tools/run_controlled_animal_pixal_jobs.py
find . -name 'controlled_animal_isnet_worker.py' -print
git status --short
nvidia-smi --query-gpu=index,name,memory.total,memory.free,utilization.gpu --format=csv,noheader
```

No remote result should be marked verified until its actual command output is captured.

