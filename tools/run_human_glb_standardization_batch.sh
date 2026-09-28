#!/usr/bin/env bash
set -euo pipefail

ROOT=${HUMAN_ASSET_ROOT:-/data/datasets/avengine_workspaces/users/lx/human_sound_source_assets_v1}
PYTHON=${HUMAN_3D_PYTHON:-/data/lx/conda-envs/avengine-3dgen/bin/python}
STANDARDIZER=$ROOT/_tools/standardize_human_glb.py
INSPECTOR=$ROOT/_tools/inspect_glb_structure.py
SUMMARY=$ROOT/_review/human_glb_standardization_v1_summary.tsv

ASSETS=(singer_microphone phone_call guitar_player violin_player pianist)
SEEDS=(42001 42002 42003 42004 42005)
TARGET_HEIGHTS=(1.72 1.75 1.75 1.75 1.55)

test -s "$STANDARDIZER" || { echo "STANDARDIZATION_ABORTED missing $STANDARDIZER"; exit 2; }
test -s "$INSPECTOR" || { echo "STANDARDIZATION_ABORTED missing $INSPECTOR"; exit 2; }

preflight=${1:-}
available=0
for i in "${!ASSETS[@]}"; do
  asset=${ASSETS[$i]}
  seed=${SEEDS[$i]}
  target_height=${TARGET_HEIGHTS[$i]}
  input=$ROOT/$asset/pixal/pixal_seed_${seed}_v1/pixal_raw_1024.glb
  output=$ROOT/$asset/runtime/standardized_seed_${seed}_v1/model.glb
  if test ! -s "$input"; then
    echo "STANDARDIZATION_INPUT_PENDING asset=$asset input=$input"
    continue
  fi
  available=$((available + 1))
  "$PYTHON" "$STANDARDIZER" \
    --input "$input" \
    --output "$output" \
    --asset-id "$asset" \
    --target-height-m "$target_height" \
    --preflight-only >/dev/null
  echo "STANDARDIZATION_PREFLIGHT_OK asset=$asset target_height_m=$target_height"
done

test "$available" -gt 0 || { echo "STANDARDIZATION_ABORTED no raw GLBs available"; exit 3; }
if test "$preflight" = "--preflight-only"; then
  echo "STANDARDIZATION_BATCH_PREFLIGHT_OK available=$available"
  exit 0
fi

mkdir -p "$ROOT/_review"
printf 'asset\tseed\tstatus\ttarget_height_m\toutput_sha256\n' > "$SUMMARY.tmp"
completed=0
skipped=0
for i in "${!ASSETS[@]}"; do
  asset=${ASSETS[$i]}
  seed=${SEEDS[$i]}
  target_height=${TARGET_HEIGHTS[$i]}
  input=$ROOT/$asset/pixal/pixal_seed_${seed}_v1/pixal_raw_1024.glb
  output_dir=$ROOT/$asset/runtime/standardized_seed_${seed}_v1
  output=$output_dir/model.glb
  manifest=$output_dir/model.manifest.json
  structure=$output_dir/model.structure.json

  if test ! -s "$input"; then
    printf '%s\t%s\t%s\t%s\t%s\n' "$asset" "$seed" "input_pending" "$target_height" "-" >> "$SUMMARY.tmp"
    continue
  fi
  if test -s "$output" && test -s "$manifest" && test -s "$structure"; then
    output_sha=$(sha256sum "$output" | awk '{print $1}')
    echo "STANDARDIZATION_SKIP_EXISTING asset=$asset sha256=$output_sha"
    printf '%s\t%s\t%s\t%s\t%s\n' "$asset" "$seed" "passed_existing" "$target_height" "$output_sha" >> "$SUMMARY.tmp"
    skipped=$((skipped + 1))
    continue
  fi
  if test -e "$output_dir"; then
    echo "STANDARDIZATION_ABORTED partial output exists: $output_dir"
    exit 4
  fi

  echo "STANDARDIZATION_STARTING asset=$asset target_height_m=$target_height"
  "$PYTHON" "$STANDARDIZER" \
    --input "$input" \
    --output "$output" \
    --manifest "$manifest" \
    --asset-id "$asset" \
    --target-height-m "$target_height" >/dev/null
  "$PYTHON" "$INSPECTOR" "$output" > "$structure"
  output_sha=$(sha256sum "$output" | awk '{print $1}')
  echo "STANDARDIZATION_COMPLETE asset=$asset sha256=$output_sha output=$output"
  printf '%s\t%s\t%s\t%s\t%s\n' "$asset" "$seed" "passed" "$target_height" "$output_sha" >> "$SUMMARY.tmp"
  completed=$((completed + 1))
done

mv "$SUMMARY.tmp" "$SUMMARY"
cat "$SUMMARY"
echo "STANDARDIZATION_BATCH_COMPLETE available=$available completed=$completed skipped=$skipped summary=$SUMMARY"
