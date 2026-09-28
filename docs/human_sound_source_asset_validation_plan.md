# Human Sound Source Asset Validation Plan

Date: 2026-09-20

Status: design complete; no asset archives downloaded yet

## 1. Validation objective

The validation stage decides whether a candidate can become a reproducible AVEngine sound-source asset. A model passes only when all of the following are true:

1. the visible human action unambiguously implies the intended sound event;
2. the human, required prop, pose, skeleton, and animation are complete enough for the intended use;
3. a normalized GLB loads and renders correctly in the target Habitat/AVEngine build;
4. the acoustic source can be attached to a stable, semantically correct local anchor;
5. provenance and license terms are recorded for both internal use and dataset release.

Downloadability or successful Blender import alone is not acceptance.

## 2. Priority model

Candidates are scored from 1 to 5 in four dimensions:

| Dimension | Weight | Meaning |
|---|---:|---|
| Sound semantics | 40% | Action independently communicates a sound event and can be bound to audio without explanation |
| Asset completeness | 25% | Human, required prop, rig, and animation are present and correctly bound |
| AVEngine compatibility | 25% | GLB path, runtime cost, stable transforms, and source-anchor authoring are feasible |
| Development cost | 10% | Download, Blender cleanup, animation processing, and debugging effort are low |

The score is a triage score based on public evidence. It must be replaced by measured validation results after download.

## 3. First validation batch

| Rank | Asset | Semantics | Completeness | Compatibility | Cost | Weighted score | Why it is in the first batch |
|---:|---|---:|---:|---:|---:|---:|---|
| 1 | [Animated Model Singing with Microphone in Hand](https://sketchfab.com/3d-models/animated-model-singing-with-microphone-in-hand-dade090dddcb4d1b8614972b2133d22e) | 5 | 5 | 5 | 5 | **100/100** | Singing pose, microphone, rig, loop animation, low polygon count, and native GLB provide the cheapest end-to-end baseline |
| 2 | [Rory - Plays Strat - Marshall](https://sketchfab.com/3d-models/rory-plays-strat-marshall-369sim-9b03b06a9da948659682aa88a1b9916f) | 5 | 5 | 4 | 3 | **91/100** | Both hands visibly perform the correct guitar roles; native GLB and two animations test articulated person-prop interaction and an instrument-local source |
| 3 | [Business Woman - Pacing And Talking On A Phone](https://sketchfab.com/3d-models/business-woman-pacing-and-talking-on-a-phone-309dfbc06d4f4667bc1444208cb5e451) | 5 | 4 | 3 | 3 | **81/100** | Phone-to-ear behavior is visually explicit and adds the important moving-source/root-motion case |
| 4 | [Man talking on phone](https://sketchfab.com/3d-models/man-talking-on-phone-5170123e83ec4eaca01492e3856512cd) | 4 | 4 | 4 | 4 | **80/100** | Known FBX, armature, and one animation make it the controlled FBX-to-GLB test; score remains below the businesswoman until phone geometry and the clip are inspected |

### Deferred from the first batch

- **Animated pianist** is semantically strong, but its 100 MB source and large footprint introduce optimization and scene-placement issues before the baseline path is proven.
- **Violin candidates** are static, stylized, or multi-million-face printable models. They do not yet provide a clean animation validation case.
- **Static scans/sculpts** remain useful for static-pose assets, but should not define the initial animation pipeline.

## 4. Asset-specific validation work

### 4.1 Animated singer

1. Preserve source GLB, source page, license, author, retrieval time, and SHA-256.
2. Import into a clean pinned Blender version.
3. Confirm one armature, one usable animation, microphone geometry, hand attachment, and mouth proximity.
4. Play the entire loop; check hand penetration, microphone drift, foot sliding, and loop discontinuity.
5. Inspect all materials and texture references; reject missing external textures or unsupported shader dependencies unless easily converted.
6. Add `mouth` as the default acoustic anchor and `microphone_head` as a visual-cue anchor.
7. Export normalized GLB, re-import into a clean Blender scene, and compare pose, clip duration, materials, and bounds.
8. Test Habitat static representative-frame loading first; then test skeletal playback only if the current runtime explicitly supports it.

### 4.2 Rory guitar player

1. Preserve the 17.9 MB source GLB and license evidence.
2. Identify human mesh, guitar, amplifier stack, armature, and the two animation clips.
3. Confirm left hand remains on the fretboard and right hand acts near the strings/pickups throughout the accepted clip.
4. Determine whether guitar and amplifier are separate nodes and whether either is skinned or rigidly attached.
5. Measure triangle count per object and remove the amplifier only if it is not needed for the selected acoustic interpretation.
6. Add `guitar_body` and optional `amplifier_speaker` anchors; do not use the human origin as the primary source.
7. Export one intact normalized GLB and, if useful, one reduced variant without the amplifier stack.
8. Validate representative static pose and animation behavior separately in Habitat/AVEngine.

### 4.3 Businesswoman phone caller

1. Confirm actual archive format, license file, phone mesh, armature, and animation clips after download.
2. Inspect whether the phone is a separate object, a skinned mesh, or absent geometry represented only by the hand pose.
3. Measure root translation and rotation over the full clip.
4. Produce an in-place animation variant for AVEngine-controlled trajectory. Preserve the original root-motion variant as source evidence.
5. Verify that hand-to-ear contact and phone orientation remain stable throughout the clip.
6. Add a `mouth` acoustic anchor and optional `phone_speaker` anchor.
7. Export GLB, re-import, and verify that root-motion removal did not alter pose or foot contact.
8. Compare an AVEngine path-driven run with the original animated motion; only one system may own world translation.

### 4.4 Man talking on phone

1. Preserve the original FBX and all texture/sidecar files.
2. Import FBX with no automatic destructive cleanup; record axis, units, armature, meshes, and actions.
3. Confirm phone geometry actually exists and the talking animation, rather than the default T-pose, is the intended clip.
4. Inspect bone hierarchy, clip frame range, animation FPS, root motion, and prop attachment.
5. Bake constraints only when required for glTF export; retain a source FBX copy.
6. Export GLB with skinning and animation, then re-import into a clean Blender scene.
7. Add `mouth` and optional `phone_speaker` anchors after transforms are normalized.
8. Compare animation duration, pose, materials, and bounding box between FBX and exported GLB.

## 5. Validation pipeline

```text
Original asset page
        |
        v
Download immutable source + license + checksum
        |
        v
Blender import inventory
        |
        +--> Geometry check
        +--> Skeleton/animation check
        +--> Material/texture check
        +--> Semantic review
        |
        v
Working-copy normalization
        |
        v
Sound/visual anchor authoring
        |
        v
GLB export
        |
        v
Clean re-import and glTF validation
        |
        v
Habitat static-pose smoke test
        |
        v
Habitat animation test, if supported
        |
        v
AVEngine registration + audio/video smoke sample
        |
        v
ACCEPT / ACCEPT_STATIC_ONLY / REWORK / REJECT
```

### Gate G0: provenance and license

- Save immutable source URL, platform asset ID, author, license identifier/URL, attribution text, retrieval date, and raw archive SHA-256.
- Record commercial-use and raw-redistribution permissions separately.
- Fail if the license cannot be reconstructed later.

### Gate G1: Blender import inventory

Record, without modifying the source:

- object and mesh counts;
- vertex and triangle counts, globally and per mesh;
- hidden, disabled, duplicate, collision, light, camera, and decorative objects;
- armature count, bone count, bone hierarchy, and mesh skinning;
- animation actions, duration, FPS, loop behavior, and root motion;
- materials, textures, missing files, alpha modes, and unsupported shaders;
- units, up axis, forward axis, origin, ground height, transforms, and bounds.

No geometry should be deleted merely because it is hidden. Hidden objects are first classified as required, optional, helper, or disposable.

### Gate G2: semantic acceptance

Review the representative pose and the full animation from front, left, right, and rear three-quarter views.

Required examples:

- guitar: one hand frets the neck and the other acts at the strings/pickups;
- violin: violin rests at shoulder/chin, one hand fingers the neck, and bow contacts the string region;
- singer: mouth/performance pose and microphone are coherently aligned;
- phone call: phone is at the ear/mouth region and the gesture persists during the clip;
- piano: seated body and both hands remain related to the keys.

Reject `human holding prop` when the action does not communicate sound production.

### Gate G3: normalized GLB

- Normalize units to meters and define project-standard up/forward axes.
- Place ground contact at local floor height and define a stable asset origin.
- Preserve skinning and animation; bake only unsupported constraints.
- Convert materials to glTF-compatible PBR and resolve texture paths.
- Export GLB, run a glTF validator, then re-import into a clean scene.
- Require matching clip duration, representative pose, textures, hierarchy, and bounds after round trip.

### Gate G4: Habitat compatibility

Validation is deliberately split into two levels:

- `static_pose`: bake or select one semantically clear representative frame and verify GLB load, transform, lighting, depth, semantic rendering, and scene placement.
- `skeletal_runtime`: verify that the current Habitat/AVEngine build actually advances the skeleton and produces stable frame-by-frame bounds.

If skeletal animation is unsupported, the asset may pass as `ACCEPT_STATIC_ONLY`. This is preferable to immediately modifying the Habitat fork. Animated rendering can later be implemented at the AVEngine layer through frame baking or another deterministic path.

### Gate G5: AVEngine compatibility

- Register normalized asset and metadata.
- Instantiate it at at least two scales/positions and three view directions.
- Bind the selected event to a named local anchor, not an untracked world-space coordinate.
- Generate a short RGB/depth/semantic/audio smoke sample.
- Verify visual action, audio event, source transform, listener transform, and timestamps agree.

## 6. Sound-source binding policy

The asset origin remains useful for placement, culling, and fallback localization, but it should not be the default acoustic source when a more meaningful emitter exists.

| Event | Primary acoustic anchor | Direction | Notes |
|---|---|---|---|
| Unamplified speech / singing | Mouth or head-mouth bone offset | Forward from face | Microphone is a visual receiver, not normally the physical emitter |
| Phone user's own speech | Mouth | Forward from face | Use for the visible person's local speech |
| Remote voice from phone | Phone earpiece/speaker | Outward normal of phone speaker | This is a different event role from the person's own speech |
| Acoustic guitar | Sound hole / guitar body | Body front normal; broad directivity | Bind to the instrument, not the pelvis or hands |
| Electric guitar without modeled amp | Guitar body/pickup region as a documented proxy | Body front normal | A proxy is acceptable only when metadata states it |
| Electric guitar with active amp | Amplifier speaker | Speaker forward axis | Keep guitar body as the visual-cue anchor |
| Violin | Violin body near bridge/f-holes | Instrument front/top normal | Bow and hands are action cues, not acoustic origins |
| Trumpet / saxophone | Bell center | Bell axis | Strong directional source |
| Piano | Soundboard/body center; optional multiple anchors later | Broad/omnidirectional approximation | Large instrument; do not bind to player hands |

Each asset may contain multiple named anchors. The audio event selects one anchor through `source_location.default_anchor_id` or an event-level override. This avoids forcing singer, phone caller, and amplified guitarist into one incorrect asset-level source position.

Store visual and acoustic grounding separately:

- `acoustic_anchor`: where the simulated sound propagates from;
- `visual_cue_anchor`: the object/region that visually explains the event;
- `fallback_anchor`: usually the asset root, used only when a local emitter cannot be resolved.

## 7. Suggested asset directory contract

```text
human_sound_sources/<asset_id>/
  metadata.yaml
  source/
    original_archive_or_model
    source_url.txt
  license/
    license.txt
    attribution.txt
  working/
    normalized.blend
  runtime/
    model.glb
  validation/
    report.json
    gltf_validator.json
    previews/
```

`source/` is immutable. Blender edits and exported runtime assets live in separate directories.

## 8. Status vocabulary

Use explicit finite states rather than free-form status strings:

- `conversion_status`: `not_started`, `downloaded`, `import_checked`, `normalizing`, `exported`, `roundtrip_passed`, `rework`, `failed`.
- `habitat_status`: `not_tested`, `static_load_passed`, `static_render_passed`, `animation_passed`, `static_only`, `failed`.
- `avengine_status`: `not_registered`, `registered`, `smoke_test_passed`, `accepted`, `accepted_static_only`, `rework`, `rejected`.

An asset is production-ready only at `avengine_status: accepted` or, for explicitly static datasets, `accepted_static_only`.
