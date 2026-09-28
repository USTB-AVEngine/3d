#!/usr/bin/env bash
set -euo pipefail

ROOT=/data/datasets/avengine_workspaces/users/lx/human_sound_source_assets_v1
RENDERER="$ROOT/_tools/render_glb_turntable.py"
PYTHON=/data/lx/conda-envs/avengine-3dgen/bin/python
EXPECTED_RENDERER_SHA256=ffbe0e57456c5c71eaf5cc08b54df92189104d65e9a0a282b43aa9eb19a0c667

actual=$(sha256sum "$RENDERER" | awk '{print $1}')
test "$actual" = "$EXPECTED_RENDERER_SHA256" || {
  echo "TURNTABLE_BATCH_ABORTED renderer hash mismatch"
  exit 1
}
"$PYTHON" -m py_compile "$RENDERER"

for specification in \
  phone_call:42002 \
  guitar_player:42003 \
  violin_player:42004 \
  pianist:42005; do
  asset=${specification%%:*}
  seed=${specification##*:}
  glb="$ROOT/$asset/pixal/pixal_seed_${seed}_v1/pixal_raw_1024.glb"
  output="$ROOT/$asset/review/glb_turntable_bright_seed_${seed}_v1"
  echo "TURNTABLE_RENDER_START asset=$asset"
  LIBGL_ALWAYS_SOFTWARE=1 "$PYTHON" "$RENDERER" \
    --glb "$glb" \
    --output-dir "$output" \
    --size 640
  sha256sum "$output/turntable_sheet.png" "$output/render_manifest.json"
  echo "TURNTABLE_RENDER_COMPLETE asset=$asset"
done

echo "TURNTABLE_BATCH_COMPLETE assets=4"
