# Human Sound Source Expansion V3 Review Checklist

## Shared gate

Each candidate must satisfy all items before ISNet:

- Exactly one person and one intended sound-producing object or action.
- Full head, both hands and both feet remain inside the frame.
- The sound action is readable without relying on the prompt.
- Hands have usable anatomy and do not merge into the prop or face.
- Clothing and accessories match the planned identity.
- Accessories remain attached to the body and do not create loose thin geometry.
- Background is plain and has adequate edge contrast.
- No text, logo, watermark, furniture or unintended secondary object.

## Flute Player 43002

- Complete silver flute from headjoint to footjoint.
- Straight tube with no duplicated or broken section.
- Embouchure hole aligned at the lips.
- Both hands visibly occupy separate key regions.
- Flute contrasts against the emerald blouse and background.
- Jade hairpin and pearl studs remain subtle and attached.

Reject if the flute is cropped, bent, fused with both hands, or resembles a recorder.

## Hand Drum Player 43003

- One palm contacts the drumhead and the other is raised above the rim.
- Complete djembe drumhead, rim, rope tuning and tapered body.
- Both feet, seated body and simple stool are complete.
- Hands do not merge into the rim.
- Printed overshirt remains readable without producing loose cloth.

Reject if the pose reads as holding the drum or if both hands miss the drumhead.

## Megaphone Speaker 43004

- Open mouth meets the rear mouthpiece.
- Megaphone bell, cone, body and handle are complete.
- Free hand forms a readable speaking gesture.
- Scarf is tucked into the collar; pouch and watch remain attached.
- No sign, placard, crowd or readable lettering.

Reject if the subject only carries the megaphone or if the cone points directly at the camera.

## Clapping Person 43005

- Palms face each other with a small visible gap.
- All fingers are plausible and readable.
- Hands and elbows remain separated from the torso.
- The pose reads as clapping, not praying or waving.
- Brooch, earrings and watch remain small and attached.

Reject if the hands are fused, pressed together, far apart or anatomically unusable.

## Coughing Person 43006

- One hand is close to the open mouth without hiding the whole face.
- The other hand rests on the upper chest.
- Slight forward lean and facial expression make coughing unambiguous.
- Cross-body bag lies close against the back; strap remains flat.
- Both feet and the bent elbow remain fully visible.

Reject if the pose reads as yawning, laughing, smoking, shouting or drinking.

## ISNet gate

- Main silhouette is connected and complete.
- Intended sound object and action hands survive the alpha mask.
- Thin parts are preserved where possible.
- No background islands remain outside the subject.
- Alpha extrema are 0 and 255.

## Pixal3D gate

- GLB passes structural validation.
- Four corrected views use flipped texture V and linear sampling.
- Action semantics remain readable from at least the front and one side view.
- Prop and hands have no catastrophic fusion.
- Model is standardized only after visual approval.
