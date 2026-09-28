#!/usr/bin/env bash
set -euo pipefail

ROOT=/data/datasets/avengine_workspaces/users/lx/human_sound_source_assets_v1
RGBA="$ROOT/singer_microphone/segmentation/isnet_seed_42001_v1/input_rgba_isnet.png"
REVIEW="$ROOT/singer_microphone/review/singer_isnet_seed_42001_segmentation_review.json"
OUTPUT_DIR="$ROOT/singer_microphone/pixal/pixal_seed_42001_v1"
GLB="$OUTPUT_DIR/pixal_raw_1024.glb"
WRAPPER=/data/lx/code/spear/tools/i23d_human_bakeoff.py
PYTHON=/data/lx/conda-envs/avengine-3dgen/bin/python
EXPECTED_RGBA=fb7e5f3bd6d297f42db06673bd6649a64468c158dc8f20b44be0d02cc4e61741
EXPECTED_REVIEW=9d87a76f50b4c1d92353b3971f45a4ae8416ec7776a19c74dcd9a8f68086e55a
EXPECTED_WRAPPER=5f28323c11c69cafdb3263900e780cb3271e06d290fa74c1223750caf4fbc901
MIN_FREE_MIB=44000
MAX_UTILIZATION=10
POLL_SECONDS=60
MAX_WAIT_SECONDS=21600

file_sha256() {
  sha256sum "$1" | awk '{print $1}'
}

verify_inputs() {
  test "$(file_sha256 "$RGBA")" = "$EXPECTED_RGBA" || {
    echo "PIXAL_ABORTED RGBA hash mismatch"; return 1;
  }
  test "$(file_sha256 "$REVIEW")" = "$EXPECTED_REVIEW" || {
    echo "PIXAL_ABORTED segmentation review hash mismatch"; return 1;
  }
  test "$(file_sha256 "$WRAPPER")" = "$EXPECTED_WRAPPER" || {
    echo "PIXAL_ABORTED wrapper hash mismatch"; return 1;
  }
  test ! -e "$OUTPUT_DIR" || {
    echo "PIXAL_ABORTED output already exists: $OUTPUT_DIR"; return 1;
  }
}

eligible_gpu() {
  nvidia-smi \
    --query-gpu=index,memory.free,utilization.gpu \
    --format=csv,noheader,nounits |
    awk -F, -v minimum="$MIN_FREE_MIB" -v maximum="$MAX_UTILIZATION" '
      {
        for (i=1; i<=3; i++) gsub(/ /, "", $i)
        if (($2 + 0) >= (minimum + 0) && ($3 + 0) <= (maximum + 0)) {
          print $1, $2, $3
        }
      }
    ' |
    sort -k2,2nr |
    head -n 1
}

verify_inputs
started_waiting=$(date +%s)
echo "PIXAL_WAITER_STARTED $(date -u +%Y-%m-%dT%H:%M:%SZ)"

while true; do
  first_sample=$(eligible_gpu)
  if test -n "$first_sample"; then
    read -r first_gpu first_free first_util <<< "$first_sample"
    echo "PIXAL_GPU_CANDIDATE gpu=$first_gpu free_mib=$first_free util=$first_util"
    sleep "$POLL_SECONDS"
    verify_inputs
    second_sample=$(eligible_gpu)
    if test -n "$second_sample"; then
      read -r gpu free_mib utilization <<< "$second_sample"
      if test "$gpu" = "$first_gpu" \
        && test "$free_mib" -ge "$MIN_FREE_MIB" \
        && test "$utilization" -le "$MAX_UTILIZATION"; then
        break
      fi
    fi
    echo "PIXAL_GPU_CANDIDATE_REJECTED availability was not stable"
  else
    nvidia-smi \
      --query-gpu=index,memory.free,utilization.gpu \
      --format=csv,noheader
  fi

  elapsed=$(( $(date +%s) - started_waiting ))
  if test "$elapsed" -ge "$MAX_WAIT_SECONDS"; then
    echo "PIXAL_WAITER_TIMED_OUT waited_seconds=$elapsed"
    exit 3
  fi
  sleep "$POLL_SECONDS"
done

verify_inputs
cd /data/lx/code/spear
export PIXAL3D_NAF_REPO=/data/models/torch/hub/valeoai_NAF_main
log="$ROOT/singer_microphone/review/pixal_seed_42001_$(date -u +%Y%m%dT%H%M%SZ).log"
echo "PIXAL_STARTING gpu=$gpu free_mib=$free_mib util=$utilization log=$log"

set +e
{ time "$PYTHON" "$WRAPPER" \
  --backend pixal3d \
  --image "$RGBA" \
  --output "$GLB" \
  --gpu "$gpu" \
  --seed 42001 \
  --resolution 1024 \
  --manual-fov 0.2; } 2>&1 | tee "$log"
status=${PIPESTATUS[0]}
set -e
echo "PIXAL_EXIT_STATUS=$status"
test "$status" -eq 0 || exit "$status"

sha256sum "$GLB" "$OUTPUT_DIR/pixal_raw_1024.manifest.json"
validation="$OUTPUT_DIR/pixal_structural_validation.json"
GLB="$GLB" RGBA="$RGBA" "$PYTHON" -c '
import json
import os
from pathlib import Path
from tools.human_attribute_pixal_contract import validate_staged_pixal_glb
glb = Path(os.environ["GLB"])
rgba = Path(os.environ["RGBA"])
document, record = validate_staged_pixal_glb(
    glb, staging=glb.parent, input_rgba=rgba
)
print(json.dumps({
    "schema": "human_sound_source_pixal_structural_validation_v1",
    "status": "passed",
    "mesh_count": len(document.get("meshes", [])),
    "primitive_count": sum(
        len(mesh.get("primitives", [])) for mesh in document.get("meshes", [])
    ),
    "material_count": len(document.get("materials", [])),
    "texture_count": len(document.get("textures", [])),
    "image_count": len(document.get("images", [])),
    "glb": record,
}, indent=2, sort_keys=True))
' > "$validation.tmp"
mv "$validation.tmp" "$validation"
sha256sum "$validation"
cat "$validation"
echo "PIXAL_COMPLETE output=$GLB"
