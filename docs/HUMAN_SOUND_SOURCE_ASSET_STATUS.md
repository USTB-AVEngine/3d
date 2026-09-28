# Human Sound Source Asset Status

Completed runtime-standardized assets: 10/10.

| Asset | Seed | Runtime status |
| --- | ---: | --- |
| phone_call | 42002 | passed |
| guitar_player | 42003 | passed |
| violin_player | 42004 | passed |
| pianist | 42005 | passed |
| saxophone_player | 43001 | passed |
| flute_player | 43012 | passed |
| hand_drum_player | 43003 | passed with visual conditions |
| megaphone_speaker | 43004 | passed with visual conditions |
| clapping_person | 43005 | passed with visual conditions |
| coughing_person | 43006 | passed with visual conditions |

The full GLB payloads are retained under the server asset root. The lightweight
repository contains generation metadata, validation records, review decisions,
and preview sheets. GLB files are intentionally ignored unless Git LFS is
explicitly configured.

The singer asset is outside this release scope.

## Preview Selection

For the original four assets, use only these corrected review sheets:

- `phone_call/review/turntable_corrected_42002.png`
- `guitar_player/review/turntable_corrected_42003.png`
- `violin_player/review/turntable_corrected_42004.png`
- `pianist/review/turntable_corrected_42005.png`

Legacy `glb_turntable_seed_*` and `glb_turntable_bright_seed_*` previews were
rendered before the custom renderer applied the glTF-correct texture-V
orientation. They are excluded from the repository going forward. The source
and standardized GLB texture payloads were not modified by this preview issue.

## Server Archive

- Archive: `/data/datasets/avengine_workspaces/users/lx/human_sound_source_assets_v1/_releases/human_sound_sources_10_v1_20260928.tar`
- Size: 760 MB
- SHA-256: `e87e8c72123534b173b2029ace247898c015632125bd4c841ecc1abd841a5f9c`
- Inventory: `/data/datasets/avengine_workspaces/users/lx/human_sound_source_assets_v1/_releases/human_sound_sources_10_v1_20260928/runtime_inventory.tsv`
