# Human Sound Source Prompt V1

Date: 2026-09-20

Status: ready for Flux2 runner integration; no images generated yet

## Shared image contract

Every candidate must contain exactly one adult human and the complete sound-related prop. Use a clean light-gray studio background, soft even lighting, sharp focus, realistic proportions, full-body framing, and a three-quarter view chosen to expose both hands and the prop interaction.

Reject any candidate whose action reads as merely holding or standing beside the prop.

The deployed Flux2 runner's support for a separate negative-prompt parameter is not yet verified. If it does not support one, append the category exclusions to the positive prompt and enforce them during candidate selection.

## 1. Singer With Microphone

Sound event: `human.singing`

Positive prompt:

```text
Full-body realistic studio image of one adult singer actively singing into a handheld dynamic microphone, mouth visibly open mid-vocal phrase, microphone head held a short distance directly in front of the mouth, one hand firmly gripping the microphone and the other hand making a natural expressive performance gesture, confident balanced standing pose, natural human proportions, both hands and both feet fully visible, three-quarter front view, the entire person and entire microphone inside the frame, clean light-gray studio background, soft even lighting, sharp focus, clear connected foreground silhouette.
```

Negative prompt:

```text
multiple people, backup singer, microphone stand, cable, stage, audience, speaker, instrument, closed mouth, microphone far from mouth, microphone covering face, floating microphone, broken microphone, fused hand, extra fingers, missing fingers, malformed hands, extra limbs, cropped head, cropped hands, cropped feet, cropped microphone, motion blur, text, watermark, logo, busy background
```

Required visual semantics:

- mouth open in an active vocal pose;
- microphone head aligned with the mouth;
- visible gripping hand and full microphone;
- pose reads as singing without relying on the label.

Anchors: acoustic `mouth`; visual `microphone_head`; fallback `asset_root`.

## 2. Person Talking On Phone

Sound event: `human.speech.phone_call`

Positive prompt:

```text
Full-body realistic studio image of one adult person actively talking on a smartphone call, mouth slightly open mid-sentence, right hand holding a clearly visible modern smartphone against the right ear with the outer phone surface visible to the camera, free hand making a natural conversational gesture, attentive speaking expression, relaxed balanced standing pose, natural human proportions, both hands and both feet visible, three-quarter front-left view, entire person and complete phone inside the frame, clean light-gray studio background, soft even lighting, sharp focus, clear connected foreground silhouette.
```

Negative prompt:

```text
multiple people, looking at phone screen, texting, selfie pose, phone away from ear, phone hidden by hand, invisible phone, phone fused into head, headset, earbuds, bag, furniture, extra fingers, missing fingers, malformed hands, extra limbs, cropped phone, cropped head, cropped hands, cropped feet, motion blur, text, watermark, logo, busy background
```

Required visual semantics:

- visible smartphone touching the ear;
- mouth and expression communicate active speech;
- phone orientation remains readable;
- pose does not read as texting or taking a selfie.

Anchors: local speech `mouth`; remote speech `phone_speaker`; visual `phone_body`; fallback `asset_root`.

## 3. Acoustic Guitar Player

Sound event: `instrument.acoustic_guitar`

Positive prompt:

```text
Full-body realistic studio image of one adult musician actively playing an acoustic guitar, guitar body resting naturally against the torso, left hand pressing the fretboard with visible finger placement, right hand actively strumming directly across the strings above the sound hole, focused performance expression, stable standing pose with a guitar strap, natural human proportions, both hands and both feet visible, three-quarter front view showing the complete guitar body, sound hole, neck and headstock, entire person and guitar inside the frame, clean light-gray studio background, soft even lighting, sharp focus, clear connected foreground silhouette.
```

Negative prompt:

```text
multiple people, electric guitar, amplifier, cable, guitar stand, extra instrument, person merely holding guitar, hand away from fretboard, hand away from strings, missing guitar neck, missing headstock, broken guitar body, floating guitar, fused hand, extra fingers, missing fingers, malformed hands, extra limbs, cropped guitar, cropped hands, cropped feet, motion blur, text, watermark, logo, busy background
```

Required visual semantics:

- fretting hand on the neck;
- strumming hand over the string/sound-hole region;
- complete acoustic-guitar silhouette including headstock;
- pose reads as active playing rather than carrying.

Anchors: acoustic `guitar_sound_hole`; visual `guitar_playing_region`; fallback `asset_root`.

## 4. Violin Player

Sound event: `instrument.violin`

Positive prompt:

```text
Full-body realistic studio image of one adult violinist actively playing a violin, violin securely positioned between the left shoulder and chin, left hand fingers pressing the violin fingerboard, right hand holding a complete bow with the bow hair visibly contacting the violin string region, elbows raised in a natural performance posture, focused expression, balanced standing pose, natural human proportions, both hands and both feet visible, three-quarter front view showing the violin body, neck, scroll and the full diagonal bow, entire person, violin and bow inside the frame, clean light-gray studio background, soft even lighting, sharp focus, clear connected foreground silhouette.
```

Negative prompt:

```text
multiple people, violin away from shoulder, violin held at waist, bow away from strings, missing bow, broken bow, cropped bow, missing scroll, music stand, chair, extra instrument, floating violin, fused hands, extra fingers, missing fingers, malformed hands, extra limbs, cropped head, cropped hands, cropped feet, motion blur, text, watermark, logo, busy background
```

Required visual semantics:

- shoulder/chin violin support;
- left hand on fingerboard;
- full bow crossing the string region;
- both instrument and bow remain inside the frame.

Anchors: acoustic `violin_body`; visual `bow_string_contact`; fallback `asset_root`.

## 5. Pianist

Sound event: `instrument.piano`

Positive prompt:

```text
Realistic studio image of one adult pianist actively playing a compact digital piano with a complete keyboard and built-in speaker body, seated naturally on a simple backless bench, both hands visibly pressing different groups of keys, wrists and elbows in a credible playing posture, focused performance expression, both feet visible below the keyboard, natural human proportions, side three-quarter view showing the face, both hands, full keyboard, piano body, support legs and bench, entire human and instrument inside the frame, clean light-gray studio background, soft even lighting, sharp focus, clear connected foreground silhouette.
```

Negative prompt:

```text
multiple people, grand piano, piano lid, sheet music, music stand, extra instrument, hands away from keys, one hand hidden, person sitting beside piano, cropped keyboard, cropped piano body, cropped bench, cropped hands, cropped feet, hands fused into keys, extra fingers, missing fingers, malformed hands, extra limbs, cable, motion blur, text, watermark, logo, busy background
```

Required visual semantics:

- both hands visibly contact keys;
- seated torso is oriented toward the keyboard;
- entire compact piano, bench, hands, and feet are visible;
- pose reads as active performance.

Anchors: acoustic `piano_body`; visual `keyboard_hands`; fallback `asset_root`.

## Candidate selection record

For each generated image record:

```yaml
asset_id: ""
prompt_version: "v1"
positive_prompt: ""
negative_prompt: ""
seed: null
model_id: ""
model_revision: ""
image_path: ""
semantic_pass: false
hand_prop_pass: false
framing_pass: false
segmentation_ready: false
rejection_reasons: []
```

