# Human Sound Source Assets V1 Generation Plan

Date: 2026-09-20

Status: design only; image and 3D generation have not started

## 1. Goal

Generate five Level-1 static human sound-source assets:

1. singer with handheld microphone;
2. person talking on a phone;
3. acoustic guitar player;
4. violin player;
5. pianist at a compact keyboard/piano.

Each output must visually encode `human + sound-producing action + sound-related object`. A person merely holding a prop is not acceptable.

V1 targets static semantic assets. Rigging and animation are explicitly outside the initial Pixal3D acceptance gate.

## 2. Evidence about the existing animal pipeline

The local workspace does not contain the Flux2, ISNet, Pixal3D, animal runner, or authenticated manifest code. Exact CLI flags and input resolution therefore remain unverified until the server repository is available.

The handoff documentation establishes this workflow:

```text
Flux image generation / candidate selection
        |
        v
ISNet foreground segmentation
        |
        v
RGBA input image
        |
        v
Pixal3D image-to-3D
        |
        v
pixal_raw_1024.glb
```

Known server locations from the handoff:

- Pixal3D code: `/data/lx/code/Pixal3D`
- AVEngine code: `/data/lx/code/spear`
- AVEngine Python: `/data/lx/conda-envs/avengine/bin/python`
- 3D generation Python: `/data/lx/conda-envs/avengine-3dgen/bin/python`
- model cache: `/data/models`
- user workspace: `/data/datasets/avengine_workspaces/users/lx`
- animal runner: `tools/run_controlled_animal_pixal_jobs.py`
- raw output file name: `pixal_raw_1024.glb`

The previous authenticated-output check requires the runtime output root to exactly match the manifest. The proposed root `human_sound_source_assets_v1` must be added to the authenticated plan before any controlled job starts.

### Local GLB evidence

The existing animal output `C:/Users/17738/Desktop/animal_glb_check/pixal_raw_1024.glb` was inspected directly through its GLB JSON chunk:

| Property | Measured value |
|---|---:|
| Container | glTF 2.0 GLB |
| File size | 37,489,760 bytes |
| Generator | `trimesh` |
| Scenes / nodes | 1 / 2 |
| Meshes / primitives | 1 / 1 |
| Vertices | 707,898 |
| Triangles | 998,962 |
| Materials | 1 |
| Textures / images | 2 / 2 |
| Skins | 0 |
| Animations | 0 |
| Required extension | `EXT_texture_webp` |

This proves only the inspected animal output characteristics. It does not prove that every Pixal3D run has identical counts.

## 3. Pipeline suitability conclusion

### Supported for V1

- one isolated, full-body human and one interacting prop represented as a single foreground subject;
- static sound-producing pose;
- transparent-background RGBA after segmentation;
- raw textured GLB output;
- later authoring of fixed local sound-anchor coordinates.

### Not demonstrated by the current evidence

- armature generation;
- skeletal animation;
- separate semantic nodes for human and prop;
- stable reconstruction of hidden/back-side hand-prop contact;
- thin geometry such as violin bows, microphone shafts, phone edges, and strings;
- direct Habitat compatibility with required WebP texture extension.

### Main human-generation risks

1. Hands may merge into the prop or become malformed.
2. Small props may disappear or merge into the face.
3. Instruments create self-occlusion and ambiguous back-side geometry.
4. ISNet may remove thin bows, microphone shafts, guitar necks, or gaps between limbs.
5. The raw GLB may approach one million triangles and require later simplification.
6. A composite single mesh prevents object-node anchors; V1 must support local-point anchors.

## 4. Image input contract

The generation prompt format is plain English positive text. Whether the deployed Flux2 wrapper supports a separate negative prompt must be checked in the server code; until then, exclusions are written into the positive prompt and enforced again during candidate review.

Every selected image should satisfy:

- exactly one adult human;
- full body and complete prop visible inside the frame;
- three-quarter view unless the category specifies a side three-quarter view;
- clean neutral studio background and even lighting;
- no floor clutter, stage, audience, extra people, text, logos, cables, or motion blur;
- hands clearly visible at the sound-producing interaction points;
- separated limb silhouette where practical;
- realistic proportions and a stable standing or seated pose;
- one connected foreground mask containing both human and required prop;
- no crop at hair, hands, feet, bow, instrument neck, or piano edges.

The exact accepted pixel resolution, color-space handling, alpha convention, and Pixal3D preprocessing command remain `TBD_SERVER_CODE` rather than being guessed.

## 5. Candidate and rejection workflow

For each category:

1. generate a small candidate set with fixed prompt version and recorded seeds;
2. reject images that fail action semantics before segmentation;
3. run ISNet only on approved candidates;
4. inspect alpha masks at hands, face, prop edges, and thin parts;
5. submit one approved RGBA at a time to Pixal3D;
6. preserve raw `pixal_raw_1024.glb` without edits;
7. inspect geometry and anchor feasibility before attempting cleanup.

Suggested first-pass candidate count: 12 images per category, retain at most 3 for segmentation, and reconstruct one at a time. This is a design target, not a command executed in this phase.

## 6. Category order

Recommended reconstruction order based on geometry risk:

1. `guitar_player`: large prop and strong two-hand semantics;
2. `singer_microphone`: simple body pose but thin microphone;
3. `phone_call`: very small prop close to face;
4. `violin_player`: thin bow and heavy hand/instrument overlap;
5. `pianist`: large composite object, seated occlusion, and broad footprint.

All five prompts and metadata are prepared before generation. The order only controls which Pixal3D job is attempted first.

## 7. Directory design

```text
assets/human_sound_sources/
  human_sound_source_assets_v1.yaml
  singer_microphone/
    generation_plan.yaml
    metadata/asset_metadata.yaml
    images/candidates/       # created when generation starts
    images/selected/
    segmentation/
    pixal3d/raw/
    validation/
  phone_call/
    ...
  guitar_player/
    ...
  violin_player/
    ...
  pianist/
    ...
```

No image, segmentation, or GLB output directory is populated during this design phase.

Proposed server output root:

```text
/data/datasets/avengine_workspaces/users/lx/human_sound_source_assets_v1/
```

Each Pixal3D job should write under its category and immutable variant ID. The controlled-job manifest and launch argument must use the same root string.

## 8. Anchor design for static Pixal3D assets

Because the inspected Pixal3D GLB has no bones and only one mesh, V1 anchors are planned semantic regions and later resolved to local coordinates after mesh generation.

| Category | Acoustic anchor | Visual cue anchor | Fallback |
|---|---|---|---|
| Singer | mouth center | microphone head | asset root |
| Phone call | mouth for local speech; phone speaker for remote speech | phone body | asset root |
| Acoustic guitar | sound hole / guitar body | strumming and fretting regions | asset root |
| Violin | violin body near bridge | bow-string contact | asset root |
| Pianist | piano body/soundboard or built-in speaker region | hands/keyboard | asset root |

Anchor coordinates, forward vectors, and mesh-relative attachment data must remain null until the generated GLB is inspected.

## 9. Pre-generation gates

Before any generation command runs:

- verify Flux2 runner and prompt schema in `/data/lx/code/spear`;
- verify expected image resolution and output naming;
- verify ISNet invocation, alpha polarity, and edge processing;
- verify Pixal3D RGBA loader and accepted dimensions;
- create and authenticate the `human_sound_source_assets_v1` output root;
- confirm disk quota and deterministic seed logging;
- confirm generated-content license/provenance policy;
- copy the five plan files to the server-side workspace without altering their IDs.

## 10. Acceptance boundary

A generated V1 asset can proceed to validation only when:

- the action reads correctly without a text label;
- the sound-related prop is present and geometrically connected to the interaction;
- the raw GLB opens as a valid container;
- no critical component is missing from multiple views;
- a meaningful acoustic anchor can be expressed as a local position;
- provenance includes prompt version, seed, image generator, segmentation model, and Pixal3D version.

Rigging and animation are not required for V1 acceptance and must not be fabricated in metadata.

