#!/usr/bin/env bash
set -euo pipefail

ROOT=/data/datasets/avengine_workspaces/users/lx/human_sound_source_assets_v1
WRAPPER=/data/lx/code/spear/tools/i23d_human_bakeoff.py
PYTHON=/data/lx/conda-envs/avengine-3dgen/bin/python
EXPECTED_WRAPPER_SHA256=5f28323c11c69cafdb3263900e780cb3271e06d290fa74c1223750caf4fbc901
MIN_FREE_MIB=${PIXAL_MIN_FREE_MIB:-48000}
MAX_UTILIZATION=${PIXAL_MAX_UTILIZATION:-5}
POLL_SECONDS=${PIXAL_POLL_SECONDS:-60}
STABLE_SAMPLES=${PIXAL_STABLE_SAMPLES:-3}
ALLOW_SHARED_GPU=${PIXAL_ALLOW_SHARED_GPU:-0}
MAX_WAIT_SECONDS=43200
MAX_ATTEMPTS=3
OOM_COOLDOWN_SECONDS=300
LOCK_DIR="$ROOT/_locks"
LOCK_FILE="$LOCK_DIR/human_pixal_batch_v1.lock"
SUMMARY="$ROOT/_review/human_pixal_batch_v1_summary.tsv"

ASSETS=(
  singer_microphone
  phone_call
  guitar_player
  violin_player
  pianist
)
SEEDS=(42001 42002 42003 42004 42005)
RGBA_HASHES=(
  fb7e5f3bd6d297f42db06673bd6649a64468c158dc8f20b44be0d02cc4e61741
  3d19528830050b6fd6bf524bf41fa6a0c44c059eae43874735dc269916b66844
  e951e92469d3f354e2aa5b84c3ca041cd9b286c731a155239c96b49aa4575a53
  0e4c25f53f9716163db4e3c6190190ff373d59e43279aafe3865dad0a30b9872
  5a92fa3ac6a2a414b6a2d124f443a6ac02c2dc68ccb39db415ef9748d63f7f2c
)
REVIEW_FILES=(
  singer_isnet_seed_42001_segmentation_review.json
  phone_call_isnet_seed_42002_segmentation_review.json
  guitar_player_isnet_seed_42003_segmentation_review.json
  violin_player_isnet_seed_42004_segmentation_review.json
  pianist_isnet_seed_42005_segmentation_review.json
)
REVIEW_HASHES=(
  9d87a76f50b4c1d92353b3971f45a4ae8416ec7776a19c74dcd9a8f68086e55a
  896d3477b2f6bb71333393bb4abd40210d6c3e69384c40fee99dc0657559947e
  4f93a19530c9c0935fdb57a8b38be08b218407107962c1919eda66c65b9731a4
  2784f0f2fc708c25a852a4fc241fdff5ac991171c3450d8a0042d51a958815ea
  76b7ab544fdf0e46794c01b7fb359fdd9be564257b54a949cf8135bdeba422ba
)

file_sha256() {
  sha256sum "$1" | awk '{print $1}'
}

asset_rgba() {
  local asset=$1 seed=$2
  echo "$ROOT/$asset/segmentation/isnet_seed_${seed}_v1/input_rgba_isnet.png"
}

asset_review() {
  local asset=$1 review_file=$2
  echo "$ROOT/$asset/review/$review_file"
}

asset_output() {
  local asset=$1 seed=$2
  echo "$ROOT/$asset/pixal/pixal_seed_${seed}_v1"
}

verify_all_inputs() {
  test "$(file_sha256 "$WRAPPER")" = "$EXPECTED_WRAPPER_SHA256" || {
    echo "PIXAL_BATCH_ABORTED wrapper hash mismatch"; return 1;
  }
  local i asset seed rgba review
  for i in "${!ASSETS[@]}"; do
    asset=${ASSETS[$i]}
    seed=${SEEDS[$i]}
    rgba=$(asset_rgba "$asset" "$seed")
    review=$(asset_review "$asset" "${REVIEW_FILES[$i]}")
    test -f "$rgba" || { echo "PIXAL_BATCH_ABORTED missing RGBA: $rgba"; return 1; }
    test -f "$review" || { echo "PIXAL_BATCH_ABORTED missing review: $review"; return 1; }
    test "$(file_sha256 "$rgba")" = "${RGBA_HASHES[$i]}" || {
      echo "PIXAL_BATCH_ABORTED RGBA hash mismatch asset=$asset"; return 1;
    }
    test "$(file_sha256 "$review")" = "${REVIEW_HASHES[$i]}" || {
      echo "PIXAL_BATCH_ABORTED review hash mismatch asset=$asset"; return 1;
    }
  done
}

eligible_gpus() {
  local busy_uuids rows busy_ok
  busy_uuids=$(nvidia-smi --query-compute-apps=gpu_uuid --format=csv,noheader 2>/dev/null \
    | sed '/^[[:space:]]*$/d' | sort -u)
  rows=$(nvidia-smi --query-gpu=index,uuid,memory.free,utilization.gpu \
    --format=csv,noheader,nounits)

  while IFS=, read -r index uuid free_mib utilization; do
    index=${index//[[:space:]]/}
    uuid=${uuid//[[:space:]]/}
    free_mib=${free_mib//[[:space:]]/}
    utilization=${utilization//[[:space:]]/}
    busy_ok=0
    if test "$ALLOW_SHARED_GPU" = "1" || ! grep -Fqx "$uuid" <<< "$busy_uuids"; then
      busy_ok=1
    fi
    if test "$free_mib" -ge "$MIN_FREE_MIB" \
      && test "$utilization" -le "$MAX_UTILIZATION" \
      && test "$busy_ok" -eq 1; then
      echo "$index $uuid $free_mib $utilization"
    fi
  done <<< "$rows" | sort -k3,3nr
}

wait_for_stable_gpu() {
  local stable_gpu="" stable_count=0 sample gpu uuid free_mib utilization
  while true; do
    verify_all_inputs
    sample=$(eligible_gpus | head -n 1)
    if test -n "$sample"; then
      read -r gpu uuid free_mib utilization <<< "$sample"
      if test "$gpu" = "$stable_gpu"; then
        stable_count=$((stable_count + 1))
      else
        stable_gpu=$gpu
        stable_count=1
      fi
      echo "PIXAL_BATCH_GPU_STABLE_SAMPLE gpu=$gpu uuid=$uuid free_mib=$free_mib util=$utilization sample=$stable_count/$STABLE_SAMPLES"
      if test "$stable_count" -ge "$STABLE_SAMPLES"; then
        echo "$gpu $uuid $free_mib $utilization"
        return 0
      fi
    else
      stable_gpu=""
      stable_count=0
      echo "PIXAL_BATCH_WAITING_FOR_GPU $(date -u +%Y-%m-%dT%H:%M:%SZ)"
      nvidia-smi --query-gpu=index,memory.free,utilization.gpu --format=csv,noheader
    fi
    if test $(( $(date +%s) - started_waiting )) -ge "$MAX_WAIT_SECONDS"; then
      echo "PIXAL_BATCH_TIMED_OUT" >&2
      return 3
    fi
    sleep "$POLL_SECONDS"
  done
}

archive_output() {
  local output=$1 label=$2 destination
  test -e "$output" || return 0
  destination="${output}.${label}_$(date -u +%Y%m%dT%H%M%SZ)"
  mv "$output" "$destination"
  echo "PIXAL_BATCH_OUTPUT_ARCHIVED destination=$destination"
}

validate_output() {
  local asset=$1 seed=$2 rgba=$3 output=$4 glb validation
  glb="$output/pixal_raw_1024.glb"
  validation="$output/pixal_structural_validation.json"
  test -s "$glb"
  test -s "$output/pixal_raw_1024.manifest.json"
  cd /data/lx/code/spear
  GLB="$glb" RGBA="$rgba" ASSET="$asset" SEED="$seed" "$PYTHON" -c '
import json
import os
from pathlib import Path
from tools.human_attribute_pixal_contract import validate_staged_pixal_glb
glb = Path(os.environ["GLB"])
rgba = Path(os.environ["RGBA"])
document, record = validate_staged_pixal_glb(glb, staging=glb.parent, input_rgba=rgba)
print(json.dumps({
    "schema": "human_sound_source_pixal_structural_validation_v1",
    "status": "passed",
    "asset_id": os.environ["ASSET"],
    "seed": int(os.environ["SEED"]),
    "mesh_count": len(document.get("meshes", [])),
    "primitive_count": sum(len(m.get("primitives", [])) for m in document.get("meshes", [])),
    "material_count": len(document.get("materials", [])),
    "texture_count": len(document.get("textures", [])),
    "image_count": len(document.get("images", [])),
    "glb": record,
}, indent=2, sort_keys=True))
' > "$validation.tmp"
  mv "$validation.tmp" "$validation"
  sha256sum "$glb" "$output/pixal_raw_1024.manifest.json" "$validation"
}

mkdir -p "$LOCK_DIR" "$ROOT/_review"
exec 9> "$LOCK_FILE"
if ! flock -n 9; then
  echo "PIXAL_BATCH_ABORTED another Human Pixal batch holds $LOCK_FILE"
  exit 4
fi

verify_all_inputs
if test "${1:-}" = "--preflight-only"; then
  echo "PIXAL_BATCH_PREFLIGHT_OK assets=${#ASSETS[@]} allow_shared_gpu=$ALLOW_SHARED_GPU min_free_mib=$MIN_FREE_MIB max_utilization=$MAX_UTILIZATION stable_samples=$STABLE_SAMPLES"
  exit 0
fi
started_waiting=$(date +%s)
printf 'asset\tseed\tstatus\tcompleted_at_utc\n' > "$SUMMARY.tmp"
echo "PIXAL_BATCH_STARTED $(date -u +%Y-%m-%dT%H:%M:%SZ) allow_shared_gpu=$ALLOW_SHARED_GPU min_free_mib=$MIN_FREE_MIB max_utilization=$MAX_UTILIZATION stable_samples=$STABLE_SAMPLES"

failed=0
for i in "${!ASSETS[@]}"; do
  asset=${ASSETS[$i]}
  seed=${SEEDS[$i]}
  rgba=$(asset_rgba "$asset" "$seed")
  output=$(asset_output "$asset" "$seed")
  glb="$output/pixal_raw_1024.glb"

  if test -s "$glb" && validate_output "$asset" "$seed" "$rgba" "$output"; then
    echo "PIXAL_BATCH_SKIP_VALID asset=$asset seed=$seed"
    printf '%s\t%s\t%s\t%s\n' "$asset" "$seed" "passed_existing" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$SUMMARY.tmp"
    continue
  fi
  test ! -e "$output" || archive_output "$output" stale

  success=0
  attempt=1
  while test "$attempt" -le "$MAX_ATTEMPTS"; do
    echo "PIXAL_BATCH_WAITING asset=$asset seed=$seed attempt=$attempt/$MAX_ATTEMPTS"
    selected=$(wait_for_stable_gpu)
    read -r gpu gpu_uuid free_mib utilization <<< "$(tail -n 1 <<< "$selected")"
    printf '%s\n' "$selected" | head -n -1 || true
    log="$ROOT/$asset/review/pixal_seed_${seed}_attempt_${attempt}_$(date -u +%Y%m%dT%H%M%SZ).log"
    echo "PIXAL_BATCH_ASSET_STARTING asset=$asset seed=$seed attempt=$attempt gpu=$gpu uuid=$gpu_uuid free_mib=$free_mib util=$utilization log=$log"

    cd /data/lx/code/spear
    export PIXAL3D_NAF_REPO=/data/models/torch/hub/valeoai_NAF_main
    set +e
    { time "$PYTHON" "$WRAPPER" \
      --backend pixal3d \
      --image "$rgba" \
      --output "$glb" \
      --gpu "$gpu" \
      --seed "$seed" \
      --resolution 1024 \
      --manual-fov 0.2; } 2>&1 | tee "$log"
    status=${PIPESTATUS[0]}
    set -e
    echo "PIXAL_BATCH_ASSET_EXIT asset=$asset attempt=$attempt status=$status"

    if test "$status" -eq 0 && validate_output "$asset" "$seed" "$rgba" "$output"; then
      success=1
      echo "PIXAL_BATCH_ASSET_COMPLETE asset=$asset output=$glb"
      break
    fi
    test ! -e "$output" || archive_output "$output" "failed_attempt_${attempt}"
    if test "$status" -ne 0 && ! grep -Eq 'OutOfMemoryError|CUDA out of memory' "$log"; then
      echo "PIXAL_BATCH_ASSET_FAILED_NON_OOM asset=$asset status=$status"
      break
    fi
    attempt=$((attempt + 1))
    test "$attempt" -le "$MAX_ATTEMPTS" || break
    echo "PIXAL_BATCH_OOM_RETRY asset=$asset cooldown_seconds=$OOM_COOLDOWN_SECONDS"
    sleep "$OOM_COOLDOWN_SECONDS"
  done

  if test "$success" -eq 1; then
    printf '%s\t%s\t%s\t%s\n' "$asset" "$seed" "passed" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$SUMMARY.tmp"
  else
    failed=$((failed + 1))
    printf '%s\t%s\t%s\t%s\n' "$asset" "$seed" "failed" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$SUMMARY.tmp"
  fi
done

mv "$SUMMARY.tmp" "$SUMMARY"
cat "$SUMMARY"
if test "$failed" -ne 0; then
  echo "PIXAL_BATCH_FINISHED_WITH_FAILURES failed=$failed"
  exit 1
fi
echo "PIXAL_BATCH_COMPLETE assets=${#ASSETS[@]}"
