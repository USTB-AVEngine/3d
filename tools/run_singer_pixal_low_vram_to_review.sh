#!/usr/bin/env bash
set -euo pipefail

ROOT=${HUMAN_ASSET_ROOT:-/data/datasets/avengine_workspaces/users/lx/human_sound_source_assets_v1}
REPO=/data/lx/code/spear
PYTHON=/data/lx/conda-envs/avengine-3dgen/bin/python
WRAPPER=$REPO/tools/i23d_human_bakeoff.py
STANDARDIZER=$ROOT/_tools/standardize_human_glb.py
INSPECTOR=$ROOT/_tools/inspect_glb_structure.py
RENDERER=$ROOT/_tools/render_glb_turntable.py
EXPECTED_WRAPPER_SHA256=5f28323c11c69cafdb3263900e780cb3271e06d290fa74c1223750caf4fbc901
RGBA=$ROOT/singer_microphone/segmentation/isnet_seed_42001_v1/input_rgba_isnet.png
OUTPUT_DIR=$ROOT/singer_microphone/pixal/pixal_seed_42001_v1
GLB=$OUTPUT_DIR/pixal_raw_1024.glb
PIXAL_MANIFEST=$OUTPUT_DIR/pixal_raw_1024.manifest.json
STRUCTURE=$OUTPUT_DIR/pixal_structural_validation.json
RUNTIME_DIR=$ROOT/singer_microphone/runtime/standardized_seed_42001_v1
RUNTIME_GLB=$RUNTIME_DIR/model.glb
RUNTIME_MANIFEST=$RUNTIME_DIR/model.manifest.json
RUNTIME_STRUCTURE=$RUNTIME_DIR/model.structure.json
REVIEW_DIR=$ROOT/singer_microphone/review/glb_turntable_corrected_seed_42001_v1
MIN_FREE_MIB=${SINGER_LOW_VRAM_MIN_FREE_MIB:-18000}

file_sha256() {
  sha256sum "$1" | awk '{print $1}'
}

test -x "$PYTHON" || { echo "SINGER_LOW_VRAM_ABORTED missing Python: $PYTHON"; exit 2; }
test -s "$WRAPPER" || { echo "SINGER_LOW_VRAM_ABORTED missing wrapper: $WRAPPER"; exit 2; }
test "$(file_sha256 "$WRAPPER")" = "$EXPECTED_WRAPPER_SHA256" || {
  echo "SINGER_LOW_VRAM_ABORTED wrapper hash mismatch"; exit 2;
}
for required in "$RGBA" "$STANDARDIZER" "$INSPECTOR" "$RENDERER"; do
  test -s "$required" || { echo "SINGER_LOW_VRAM_ABORTED missing $required"; exit 2; }
done
if test -s "$GLB"; then
  echo "SINGER_LOW_VRAM_ABORTED raw GLB already exists: $GLB"
  exit 3
fi
if test -e "$RUNTIME_DIR"; then
  echo "SINGER_LOW_VRAM_ABORTED runtime output already exists: $RUNTIME_DIR"
  exit 3
fi
if test -e "$REVIEW_DIR"; then
  echo "SINGER_LOW_VRAM_ABORTED corrected review already exists: $REVIEW_DIR"
  exit 3
fi

GPU_LINE=$(nvidia-smi \
  --query-gpu=index,memory.free,utilization.gpu \
  --format=csv,noheader,nounits |
  awk -F, '{gsub(/ /,"",$1); gsub(/ /,"",$2); gsub(/ /,"",$3); print $1,$2,$3}' |
  sort -k2,2nr |
  head -n 1)
read -r GPU FREE_MIB UTIL <<< "$GPU_LINE"
if test "$FREE_MIB" -lt "$MIN_FREE_MIB"; then
  echo "SINGER_LOW_VRAM_NOT_STARTED max_free_mib=$FREE_MIB required_mib=$MIN_FREE_MIB"
  exit 4
fi

mkdir -p "$OUTPUT_DIR"
echo "SINGER_LOW_VRAM_STARTING gpu=$GPU free_mib=$FREE_MIB util=$UTIL"
cd "$REPO"
export PIXAL3D_NAF_REPO=/data/models/torch/hub/valeoai_NAF_main
export PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True
"$PYTHON" "$WRAPPER" \
  --backend pixal3d \
  --image "$RGBA" \
  --output "$GLB" \
  --gpu "$GPU" \
  --seed 42001 \
  --resolution 1024 \
  --manual-fov 0.2 \
  --low-vram

test -s "$GLB" || { echo "SINGER_LOW_VRAM_FAILED missing GLB"; exit 5; }
test -s "$PIXAL_MANIFEST" || { echo "SINGER_LOW_VRAM_FAILED missing manifest"; exit 5; }
"$PYTHON" "$INSPECTOR" "$GLB" > "$STRUCTURE"
echo "SINGER_LOW_VRAM_PIXAL_COMPLETE sha256=$(file_sha256 "$GLB")"

"$PYTHON" "$STANDARDIZER" \
  --input "$GLB" \
  --output "$RUNTIME_GLB" \
  --manifest "$RUNTIME_MANIFEST" \
  --asset-id singer_microphone \
  --target-height-m 1.72 >/dev/null
"$PYTHON" "$INSPECTOR" "$RUNTIME_GLB" > "$RUNTIME_STRUCTURE"
echo "SINGER_LOW_VRAM_STANDARDIZATION_COMPLETE sha256=$(file_sha256 "$RUNTIME_GLB")"

"$PYTHON" "$RENDERER" \
  --glb "$GLB" \
  --output-dir "$REVIEW_DIR" \
  --size 640 \
  --texture-filter linear \
  --brightness 1.35 \
  --flip-texture-v >/dev/null
test -s "$REVIEW_DIR/turntable_sheet.png" || {
  echo "SINGER_LOW_VRAM_FAILED missing corrected turntable"; exit 5;
}
echo "SINGER_LOW_VRAM_REVIEW_COMPLETE sha256=$(file_sha256 "$REVIEW_DIR/turntable_sheet.png")"
echo "SINGER_LOW_VRAM_PIPELINE_COMPLETE"
sha256sum \
  "$GLB" \
  "$PIXAL_MANIFEST" \
  "$STRUCTURE" \
  "$RUNTIME_GLB" \
  "$RUNTIME_MANIFEST" \
  "$RUNTIME_STRUCTURE" \
  "$REVIEW_DIR/turntable_sheet.png" \
  "$REVIEW_DIR/render_manifest.json"
