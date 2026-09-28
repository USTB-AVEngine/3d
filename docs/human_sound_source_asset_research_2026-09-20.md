# Human Sound Source Asset Candidate Research

Research date: 2026-09-20

## Scope and verification level

This is a pre-download candidate list for AVEngine. Every listed item has a live public asset page, is marked downloadable/free by the platform, and has a visually or descriptively identifiable sound-producing action. No item should be considered ingestion-ready until its downloaded archive, textures, animation clips, scale, origin, and Habitat rendering have been tested.

For Sketchfab downloadable models, `glTF` is normally available as a platform-generated archive. Where the public page exposed the original source file, the exact source format is recorded. Otherwise, the format is marked as `glTF export; source pending` rather than guessed.

Priority meanings:

- `P0`: download and perform technical validation first.
- `P1`: useful candidate with a known remediation step or second-stage scope.
- `P2`: semantically useful reference or fallback, but expensive to normalize.
- `Reject`: title matched the query, but the asset does not express a usable sound action.

## Formal candidate table

| Asset name | Source link | Author / platform | Format | Free | Commercial license | Human action description | Sound event type | Matching prop included | Suitable for AVEngine sound source asset | Conversion difficulty | Priority |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Animated Model Singing with Microphone in Hand | [Sketchfab](https://sketchfab.com/3d-models/animated-model-singing-with-microphone-in-hand-dade090dddcb4d1b8614972b2133d22e) | LasquetiSpice / Sketchfab | Original `GLB`, 5.3 MB; rigged; 1 animation; 14,945 faces | Yes | `CC BY 4.0`: commercial use allowed with attribution | Full-body singer holds the microphone close to her mouth in a looping performance animation | Singing / vocal | Yes, handheld microphone | **Yes.** Clear action, mouth-area source anchor, low geometry cost, and native GLB make this the strongest singer candidate | Low: inspect animation loop, hand/mic contact, and material import | **P0** |
| Man talking on phone | [Sketchfab](https://sketchfab.com/3d-models/man-talking-on-phone-5170123e83ec4eaca01492e3856512cd) | Characteranimations / Sketchfab | Original `FBX`; rigged; 1 animation; 50,266 faces | Yes | `CC BY 4.0`: commercial use allowed with attribution | Standing person performs a phone conversation animation | Human speech / phone call | Listed as phone action; handset visibility and mesh binding require archive check | **Conditionally yes.** Excellent behavior class, but the default thumbnail is T-pose, so the animation clip must be inspected before acceptance | Medium: FBX to GLB, animation baking, prop/hand verification | **P0** |
| Business Woman - Pacing And Talking On A Phone | [Sketchfab](https://sketchfab.com/3d-models/business-woman-pacing-and-talking-on-a-phone-309dfbc06d4f4667bc1444208cb5e451) | Walter Araujo / Sketchfab | `glTF` export; original source pending; 8,730 faces | Yes | `CC BY 4.0`: commercial use allowed with attribution | Businesswoman walks while holding a phone to her ear | Human speech / phone call; moving source | Yes, phone is visible at the ear | **Yes, after root-motion review.** Particularly valuable for moving-source trajectories; must decide whether motion comes from the animation or AVEngine trajectory | Medium: identify root motion, bake or remove translation, then export GLB | **P0** |
| Rory - Plays Strat - Marshall | [Sketchfab](https://sketchfab.com/3d-models/rory-plays-strat-marshall-369sim-9b03b06a9da948659682aa88a1b9916f) | TG13730 / Sketchfab | Original `GLB`, 17.9 MB; rigged; 2 animations; 195,988 faces | Yes | `CC BY 4.0`: commercial use allowed with attribution | Standing guitarist places fretting hand on the neck and picking hand over the strings | Electric guitar | Yes, guitar and amplifier stack | **Yes.** The playing posture is unambiguous and animation is present. Amplifier can be separated if the acoustic source should follow the guitar body | Medium: reduce geometry/material count, inspect both clips, separate optional amplifier | **P0** |
| Idle Talking By Phone Free Animation (180f loop) | [Sketchfab](https://sketchfab.com/3d-models/idle-talking-by-phone-free-animation-180f-loop-e6699dea686146f085fa1f737655b18e) | Denys Almaral / Sketchfab | `glTF` export; original source pending; 1,552 faces; 180-frame loop | Yes | Sketchfab/Fab `Free Standard`; commercial project use appears intended, but raw redistribution and dataset release require terms review | Low-poly man performs a looping hand-to-ear phone conversation gesture | Human speech / phone call | Phone is not clearly resolved in the preview; archive inspection required | **Conditionally yes.** Very efficient animation candidate, but it fails the prop-binding test unless a phone mesh is actually present or is added | Low to medium: inspect clip and attach a phone if missing | **P1** |
| Paul Personne Guitar Playing | [Sketchfab](https://sketchfab.com/3d-models/paul-personne-guitar-playing-2c97cd4a51c54130a833e7216088f9b0) | TG13730 / Sketchfab | Original `GLB`, 70.7 MB; static/unrigged; 1,582,920 faces | Yes | `CC BY 4.0`: commercial use allowed with attribution | Seated guitarist has both hands in credible fretting/picking positions | Electric guitar | Yes, guitar, amplifier, and seat | **Conditionally yes.** Semantics are excellent, but it is too heavy for direct batch simulation | High: aggressive decimation/retopology, component separation, material cleanup | **P1** |
| Pianist at the Grand Piano (Animated) | [Sketchfab](https://sketchfab.com/3d-models/pianist-at-the-grand-piano-animated-4ecb1d35cee44352afe03d03289532e8) | ronedo / Sketchfab | Original `GLB`, 100.3 MB; rigged; 2 animations; 196,767 faces | Yes | `CC BY 4.0`: commercial use allowed with attribution | Seated pianist faces the keyboard with both hands at the keys | Piano | Yes, grand piano, bench, and pianist | **Yes for second stage.** It has the required interaction and animation, but the large footprint constrains scene placement and navigation | Medium to high: optimize 100 MB asset, validate hand/key motion and piano origin | **P1** |
| Cute Little Girl Playing Violin | [Sketchfab](https://sketchfab.com/3d-models/cute-little-girl-playing-violin-an-adorable-l-43aa8f1f1a5a48e1b63234c9069b0ec6) | klrxyz / Sketchfab | `glTF` export; original source pending; 20,000 faces | Yes | `CC BY 4.0`: commercial use allowed with attribution | Stylized seated child holds violin at the shoulder and bow at the strings | Violin | Yes, violin and bow | **Conditionally yes.** Low geometry and clear props are useful, but the stylized proportions and static pose reduce realism | Medium: inspect back geometry, hand/bow contact, provenance, and materials | **P1** |
| Trumpet Player Scene | [Sketchfab](https://sketchfab.com/3d-models/trumpet-player-scene-1270613938d14a8683a4983ac61a3eb7) | emperial.rat / Sketchfab | `glTF` export; original source pending; 106,537 faces | Yes | `CC BY 4.0`: commercial use allowed with attribution | Seated performer holds a trumpet in a performance pose | Trumpet / brass | Yes, trumpet and chair | **Conditionally yes.** Pose and prop are strong, but the preview does not conclusively prove mouthpiece-to-lip contact | Medium: inspect contact from multiple angles and isolate optional scene elements | **P1** |
| Melody Kaze Anime | [Sketchfab](https://sketchfab.com/3d-models/melody-kaze-anime-49a9f929b3454b89b03ace24dcc5bd91) | Ar3Designer / Sketchfab | `glTF` export; original source pending; 120,000 faces | Yes | `CC BY 4.0`: commercial use allowed with attribution | Stylized singer holds a microphone beside the mouth in a stage pose | Singing / vocal | Yes, handheld microphone | **Conditionally yes.** Clear microphone semantics, but likely static and less natural than the P0 animated singer | Medium: inspect rig, reduce geometry, correct mic-to-mouth distance if needed | **P1** |
| Polina Plays The Violin | [Sketchfab](https://sketchfab.com/3d-models/polina-plays-the-violin-a8f97cec2ee54b91a2844a12b54595af) | Gnossiennes / Sketchfab | Original described as `STL`; `glTF` export; static; 2,036,248 faces; no textures | Yes | `CC BY 4.0`: commercial use allowed with attribution | Full-body violinist has shoulder placement, fretting hand, bow, and bowing posture | Violin | Yes, violin and bow; decorative base also included | **Only after heavy cleanup.** Sound action is very clear, but this is a dense printable statue rather than a simulation-ready character | High: remove base, decimate/retopologize, UV/material work, GLB export | **P2** |
| Jonathan Davis Inspired Rock Vocalist | [Sketchfab](https://sketchfab.com/3d-models/jonathan-davis-inspired-rock-vocalist-264a2ce5036a45e6b2addfe0e5fc4e55) | PixForge / Sketchfab | Original `OBJ` + `MTL`; static/unrigged; 1,875,394 faces | Yes | `CC BY 4.0`: commercial use allowed with attribution; likeness/branding risk still requires review | Vocalist leans into a microphone in an unmistakable live-performance pose | Singing / rock vocal | Yes, microphone and stand | **Only as fallback/reference.** Strong semantics, but very high geometry, static sculpt construction, and possible performer-likeness concerns | High: decimation, base removal, material conversion, legal/provenance review | **P2** |
| Saxophone Player One | [Sketchfab](https://sketchfab.com/3d-models/saxophone-player-one-a56391e2e842443899f8009768eef6f2) | w4dek / Sketchfab | `glTF` export; original source pending; static; 37,724 faces | Yes | `CC BY 4.0`: commercial use allowed with attribution | Figurine holds saxophone at the mouth with both hands on the instrument | Saxophone | Yes, saxophone; streetlamp/base also included | **Only after cleanup.** The sound action is readable, but the asset is a decorative figurine with attached environmental geometry | Medium: detach base/lamp, normalize material and scale | **P2** |

## Recommended validation order

1. **Singer GLB**: best end-to-end smoke test because it is light, animated, rigged, and already GLB.
2. **Rory guitar GLB**: validates articulated instrument interaction and a source anchor on a non-vocal prop.
3. **Man talking on phone FBX**: validates FBX-to-GLB animation conversion and phone/mouth source-anchor policy.
4. **Business Woman phone**: validates root motion versus AVEngine-controlled trajectory.
5. **Animated pianist**: validates a large stationary instrument and scene-footprint constraints.

## Explicitly rejected search matches

| Asset | Rejection reason |
|---|---|
| [Guitarist](https://sketchfab.com/3d-models/guitarist-f9c681c0962f4750acd5a1cf1008aac9) | Person is standing beside/holding the guitar by the neck; the preview does not depict playing. |
| [Guitarist in the park](https://sketchfab.com/3d-models/guitarist-in-the-park-0ad41f87aae24d45a67a135a3bfa15c8) | Diorama contains a guitar and environment, but no visible performing human. |
| [Vocalist, Guitarist - T-pose](https://sketchfab.com/3d-models/vocalist-guitarist-the-supreme-leaders-tpose-8846601cabf044f69ac8222dadf27ca2) | T-pose does not encode a sound-producing behavior. |
| [NEWS Reporter](https://sketchfab.com/3d-models/news-reporter-f43235f675f546ad9b94033659a05b57) | Microphone hangs at the side; it does not visually express speaking/reporting. |
| [Sci-Fi News Reporter Handphone and Mic](https://sketchfab.com/3d-models/sci-fi-news-reporter-handphone-and-mic-rigged-c8412371385b48009fde4d3c75407209) | Public preview shows isolated props rather than a bound person-action-prop asset. |
| [Every gig, ever...](https://sketchfab.com/3d-models/every-gig-ever-c8cddb7d1538477380445d2f0d2531b2) | Stage and instruments are present, but there is no performing person. |
| [Flute Player](https://sketchfab.com/3d-models/flute-player-3b51eb0480d148688483071e4a0cc072) | Abstract line figure lacks a sufficiently identifiable human visual entity for the target dataset. |

## Platform coverage and limitations

| Platform | Result of this pass | Decision |
|---|---|---|
| Sketchfab | Public API and asset pages exposed downloadability, CC license, geometry, animation, and in several cases exact source format | Primary source for the first download-validation batch |
| CGTrader | Public search page returned anti-bot/empty responses in this environment; no product page could be fully verified | Do not add unverified listings. Revisit manually or with authenticated browser access |
| TurboSquid | Public search was blocked with HTTP 403 | Do not infer format/license from snippets; revisit manually |
| Fab / Unreal Marketplace | Public search was blocked with HTTP 403 | Revisit through an authenticated Epic/Fab session; check whether the license permits dataset generation and release |
| Unity Asset Store | Page was reachable, but query results were client-rendered and the returned HTML did not expose reliable matching products | Revisit through a browser session; Unity packages also require extraction/export testing |
| Mixamo | Useful for action clips and rigging, but it does not provide a stable, publicly verifiable complete person+prop listing for this pass | Treat as a composition route, not a complete candidate. Phone/instrument props must be bound separately |
| Ready Player Me | Useful for standardized avatars, but not a complete sound-action asset by itself | Use only after current service/license terms and raw-avatar redistribution constraints are reviewed |

## License and simulation cautions

- `CC BY 4.0` permits commercial use and adaptation, but attribution and license records must remain in the asset registry.
- A platform's permission to use an asset in a commercial project does not automatically permit redistribution of the raw mesh in a released dataset. Raw-asset packaging and rendered-data release must be reviewed separately.
- Models depicting named performers or branded instruments/amplifiers may carry likeness or trademark risk even when the uploader selected `CC BY`. Prefer generic-looking models for the final dataset when equivalent assets exist.
- A source positioned at the mouth is appropriate for speech/singing/phone-call audio. Instrument events should use an instrument-specific anchor, such as guitar body/bridge, violin body, trumpet bell, saxophone bell, or piano soundboard, plus a forward vector.
- For moving animation clips, root motion must not silently compete with AVEngine trajectory control. Either bake the character in place or explicitly export the root trajectory into metadata.

## Download acceptance checklist

Each P0/P1 archive must pass all of the following before registry admission:

- archive and license text saved with immutable source URL and author;
- actual source format, animation clip names, skeleton, texture paths, and material count recorded;
- prop is present and spatially attached to the correct hand/mouth/body region;
- action remains recognizable from front, side, and rear three-quarter views;
- no severe hand penetration, floating prop, missing back geometry, or broken normals;
- meters, up axis, forward axis, ground contact, origin, and bounding box normalized;
- sound-source anchor and forward vector authored on the correct emitting component;
- GLB loads in the AVEngine/Habitat target build with correct textures;
- static and animated frame samples render correctly under batch conditions;
- raw-asset redistribution and generated-dataset usage are recorded separately.
