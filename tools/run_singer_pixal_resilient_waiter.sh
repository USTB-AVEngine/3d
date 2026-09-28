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
MIN_FREE_MIB=48000
MAX_UTILIZATION=5
POLL_SECONDS=60
STABLE_SAMPLES=3
MAX_WAIT_SECONDS=43200
MAX_ATTEMPTS=3
OOM_COOLDOWN_SECONDS=300
LOCK_DIR="$ROOT/_locks"
LOCK_FILE="$LOCK_DIR/singer_pixal_seed_42001.lock"

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

eligible_gpus() {
  local busy_uuids rows
  busy_uuids=$(nvidia-smi \
    --query-compute-apps=gpu_uuid \
    --format=csv,noheader 2>/dev/null | sed '/^[[:space:]]*$/d' | sort -u)
  rows=$(nvidia-smi \
    --query-gpu=index,uuid,memory.free,utilization.gpu \
    --format=csv,noheader,nounits)

  while IFS=, read -r index uuid free_mib utilization; do
    index=${index//[[:space:]]/}
    uuid=${uuid//[[:space:]]/}
    free_mib=${free_mib//[[:space:]]/}
    utilization=${utilization//[[:space:]]/}
    if test "$free_mib" -ge "$MIN_FREE_MIB" \
      && test "$utilization" -le "$MAX_UTILIZATION" \
      && ! grep -Fqx "$uuid" <<< "$busy_uuids"; then
      echo "$index $uuid $free_mib $utilization"
    fi
  done <<< "$rows" | sort -k3,3nr
}

wait_for_stable_gpu() {
  local stable_gpu="" stable_count=0 sample gpu uuid free_mib utilization
  while true; do
    verify_inputs
    sample=$(eligible_gpus | head -n 1)
    if test -n "$sample"; then
      read -r gpu uuid free_mib utilization <<< "$sample"
      if test "$gpu" = "$stable_gpu"; then
        stable_count=$((stable_count + 1))
      else
        stable_gpu=$gpu
        stable_count=1
      fi
      echo "PIXAL_GPU_STABLE_SAMPLE gpu=$gpu uuid=$uuid free_mib=$free_mib util=$utilization sample=$stable_count/$STABLE_SAMPLES"
      if test "$stable_count" -ge "$STABLE_SAMPLES"; then
        echo "$gpu $uuid $free_mib $utilization"
        return 0
      fi
    else
      stable_gpu=""
      stable_count=0
      nvidia-smi \
        --query-gpu=index,memory.free,utilization.gpu \
        --format=csv,noheader
    fi

    if test $(( $(date +%s) - started_waiting )) -ge "$MAX_WAIT_SECONDS"; then
      echo "PIXAL_WAITER_TIMED_OUT" >&2
      return 3
    fi
    sleep "$POLL_SECONDS"
  done
}

archive_failed_output() {
  local attempt=$1 stamp destination
  test -e "$OUTPUT_DIR" || return 0
  stamp=$(date -u +%Y%m%dT%H%M%SZ)
  destination="${OUTPUT_DIR}.failed_attempt_${attempt}_${stamp}"
  test ! -e "$destination"
  mv "$OUTPUT_DIR" "$destination"
  echo "PIXAL_FAILURE_OUTPUT_ARCHIVED destination=$destination"
}

mkdir -p "$LOCK_DIR"
exec 9> "$LOCK_FILE"
if ! flock -n 9; then
  echo "PIXAL_ABORTED another Singer Pixal waiter holds $LOCK_FILE"
  exit 4
fi

verify_inputs
started_waiting=$(date +%s)
echo "PIXAL_RESILIENT_WAITER_STARTED $(date -u +%Y-%m-%dT%H:%M:%SZ)"

attempt=1
while test "$attempt" -le "$MAX_ATTEMPTS"; do
  echo "PIXAL_WAITING attempt=$attempt/$MAX_ATTEMPTS"
  selected=$(wait_for_stable_gpu)
  read -r gpu gpu_uuid free_mib utilization <<< "$(tail -n 1 <<< "$selected")"
  printf '%s\n' "$selected" | head -n -1 || true
  verify_inputs

  cd /data/lx/code/spear
  export PIXAL3D_NAF_REPO=/data/models/torch/hub/valeoai_NAF_main
  log="$ROOT/singer_microphone/review/pixal_seed_42001_attempt_${attempt}_$(date -u +%Y%m%dT%H%M%SZ).log"
  echo "PIXAL_STARTING attempt=$attempt gpu=$gpu uuid=$gpu_uuid free_mib=$free_mib util=$utilization log=$log"

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
  echo "PIXAL_ATTEMPT_EXIT_STATUS attempt=$attempt status=$status"

  if test "$status" -eq 0; then
    break
  fi

  archive_failed_output "$attempt"
  if ! grep -Eq 'OutOfMemoryError|CUDA out of memory' "$log"; then
    echo "PIXAL_ABORTED non-OOM failure is not automatically retried"
    exit "$status"
  fi
  if test "$attempt" -ge "$MAX_ATTEMPTS"; then
    echo "PIXAL_ABORTED maximum OOM attempts reached"
    exit "$status"
  fi
  echo "PIXAL_OOM_RETRY cooldown_seconds=$OOM_COOLDOWN_SECONDS"
  sleep "$OOM_COOLDOWN_SECONDS"
  attempt=$((attempt + 1))
done

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
