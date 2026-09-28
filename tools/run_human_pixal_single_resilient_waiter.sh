#!/usr/bin/env bash
set -euo pipefail

ROOT=/data/datasets/avengine_workspaces/users/lx/human_sound_source_assets_v1
WRAPPER=/data/lx/code/spear/tools/i23d_human_bakeoff.py
PYTHON=/data/lx/conda-envs/avengine-3dgen/bin/python
EXPECTED_WRAPPER_SHA256=5f28323c11c69cafdb3263900e780cb3271e06d290fa74c1223750caf4fbc901
MIN_FREE_MIB=${PIXAL_MIN_FREE_MIB:-36000}
MAX_UTILIZATION=${PIXAL_MAX_UTILIZATION:-10}
POLL_SECONDS=${PIXAL_POLL_SECONDS:-30}
STABLE_SAMPLES=${PIXAL_STABLE_SAMPLES:-3}
ALLOW_SHARED_GPU=${PIXAL_ALLOW_SHARED_GPU:-1}
LOW_VRAM=${PIXAL_LOW_VRAM:-0}
MAX_WAIT_SECONDS=${PIXAL_MAX_WAIT_SECONDS:-43200}
MAX_ATTEMPTS=${PIXAL_MAX_ATTEMPTS:-3}
OOM_COOLDOWN_SECONDS=${PIXAL_OOM_COOLDOWN_SECONDS:-300}

usage() {
  echo "usage: $0 --asset ASSET --seed SEED --rgba-sha256 SHA --review-file FILE --review-sha256 SHA [--preflight-only]" >&2
}

ASSET=""
SEED=""
RGBA_SHA256=""
REVIEW_FILE=""
REVIEW_SHA256=""
PREFLIGHT_ONLY=0
while test "$#" -gt 0; do
  case "$1" in
    --asset) ASSET=${2:-}; shift 2 ;;
    --seed) SEED=${2:-}; shift 2 ;;
    --rgba-sha256) RGBA_SHA256=${2:-}; shift 2 ;;
    --review-file) REVIEW_FILE=${2:-}; shift 2 ;;
    --review-sha256) REVIEW_SHA256=${2:-}; shift 2 ;;
    --preflight-only) PREFLIGHT_ONLY=1; shift ;;
    *) usage; exit 2 ;;
  esac
done

[[ "$ASSET" =~ ^[a-z0-9_]+$ ]] || { usage; exit 2; }
[[ "$SEED" =~ ^[0-9]+$ ]] || { usage; exit 2; }
[[ "$RGBA_SHA256" =~ ^[0-9a-f]{64}$ ]] || { usage; exit 2; }
[[ "$REVIEW_FILE" =~ ^[a-zA-Z0-9_.-]+$ ]] || { usage; exit 2; }
[[ "$REVIEW_SHA256" =~ ^[0-9a-f]{64}$ ]] || { usage; exit 2; }

RGBA="$ROOT/$ASSET/segmentation/isnet_seed_${SEED}_v1/input_rgba_isnet.png"
REVIEW="$ROOT/$ASSET/review/$REVIEW_FILE"
OUTPUT="$ROOT/$ASSET/pixal/pixal_seed_${SEED}_v1"
GLB="$OUTPUT/pixal_raw_1024.glb"
LOCK_DIR="$ROOT/_locks"
LOCK_FILE="$LOCK_DIR/human_gpu_generation.lock"

file_sha256() {
  sha256sum "$1" | awk '{print $1}'
}

verify_inputs() {
  test -f "$WRAPPER" || { echo "PIXAL_SINGLE_ABORTED missing wrapper"; return 1; }
  test "$(file_sha256 "$WRAPPER")" = "$EXPECTED_WRAPPER_SHA256" || {
    echo "PIXAL_SINGLE_ABORTED wrapper hash mismatch"; return 1;
  }
  test -f "$RGBA" || { echo "PIXAL_SINGLE_ABORTED missing RGBA: $RGBA"; return 1; }
  test -f "$REVIEW" || { echo "PIXAL_SINGLE_ABORTED missing review: $REVIEW"; return 1; }
  test "$(file_sha256 "$RGBA")" = "$RGBA_SHA256" || {
    echo "PIXAL_SINGLE_ABORTED RGBA hash mismatch"; return 1;
  }
  test "$(file_sha256 "$REVIEW")" = "$REVIEW_SHA256" || {
    echo "PIXAL_SINGLE_ABORTED review hash mismatch"; return 1;
  }
  "$PYTHON" - "$REVIEW" <<'PY'
import json
import sys
from pathlib import Path
payload = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if payload.get("decision") != "approved_for_pixal3d":
    raise SystemExit("PIXAL_SINGLE_ABORTED review is not approved_for_pixal3d")
PY
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
      echo "PIXAL_SINGLE_GPU_STABLE_SAMPLE gpu=$gpu uuid=$uuid free_mib=$free_mib util=$utilization sample=$stable_count/$STABLE_SAMPLES"
      if test "$stable_count" -ge "$STABLE_SAMPLES"; then
        SELECTED_GPU=$gpu
        SELECTED_GPU_UUID=$uuid
        SELECTED_FREE_MIB=$free_mib
        SELECTED_UTILIZATION=$utilization
        return 0
      fi
    else
      stable_gpu=""
      stable_count=0
      echo "PIXAL_SINGLE_WAITING_FOR_GPU $(date -u +%Y-%m-%dT%H:%M:%SZ)"
      nvidia-smi --query-gpu=index,memory.free,utilization.gpu --format=csv,noheader
    fi
    if test $(( $(date +%s) - STARTED_WAITING )) -ge "$MAX_WAIT_SECONDS"; then
      echo "PIXAL_SINGLE_TIMED_OUT" >&2
      return 3
    fi
    sleep "$POLL_SECONDS"
  done
}

archive_output() {
  local label=$1 destination
  test -e "$OUTPUT" || return 0
  destination="${OUTPUT}.${label}_$(date -u +%Y%m%dT%H%M%SZ)"
  mv "$OUTPUT" "$destination"
  echo "PIXAL_SINGLE_OUTPUT_ARCHIVED destination=$destination"
}

validate_output() {
  local validation="$OUTPUT/pixal_structural_validation.json"
  test -s "$GLB"
  test -s "$OUTPUT/pixal_raw_1024.manifest.json"
  cd /data/lx/code/spear
  GLB="$GLB" RGBA="$RGBA" ASSET="$ASSET" SEED="$SEED" "$PYTHON" -c '
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
  sha256sum "$GLB" "$OUTPUT/pixal_raw_1024.manifest.json" "$validation"
}

mkdir -p "$LOCK_DIR" "$ROOT/_review"
exec 9> "$LOCK_FILE"
if ! flock -n 9; then
  echo "PIXAL_SINGLE_ABORTED another Human GPU generation process holds $LOCK_FILE"
  exit 4
fi

verify_inputs
if test "$PREFLIGHT_ONLY" -eq 1; then
  echo "PIXAL_SINGLE_PREFLIGHT_OK asset=$ASSET seed=$SEED min_free_mib=$MIN_FREE_MIB max_utilization=$MAX_UTILIZATION stable_samples=$STABLE_SAMPLES low_vram=$LOW_VRAM"
  exit 0
fi

if test -s "$GLB" && validate_output; then
  echo "PIXAL_SINGLE_SKIP_VALID asset=$ASSET seed=$SEED output=$GLB"
  exit 0
fi
test ! -e "$OUTPUT" || archive_output stale

STARTED_WAITING=$(date +%s)
echo "PIXAL_SINGLE_STARTED asset=$ASSET seed=$SEED $(date -u +%Y-%m-%dT%H:%M:%SZ)"
attempt=1
while test "$attempt" -le "$MAX_ATTEMPTS"; do
  echo "PIXAL_SINGLE_WAITING asset=$ASSET seed=$SEED attempt=$attempt/$MAX_ATTEMPTS"
  SELECTED_GPU=""
  SELECTED_GPU_UUID=""
  SELECTED_FREE_MIB=""
  SELECTED_UTILIZATION=""
  wait_for_stable_gpu
  gpu=$SELECTED_GPU
  gpu_uuid=$SELECTED_GPU_UUID
  free_mib=$SELECTED_FREE_MIB
  utilization=$SELECTED_UTILIZATION
  log="$ROOT/$ASSET/review/pixal_seed_${SEED}_attempt_${attempt}_$(date -u +%Y%m%dT%H%M%SZ).log"
  echo "PIXAL_SINGLE_ASSET_STARTING asset=$ASSET seed=$SEED attempt=$attempt gpu=$gpu uuid=$gpu_uuid free_mib=$free_mib util=$utilization log=$log"
  mkdir -p "$OUTPUT"
  cd /data/lx/code/spear
  export PIXAL3D_NAF_REPO=/data/models/torch/hub/valeoai_NAF_main
  set +e
  pixal_args=(
    --backend pixal3d
    --image "$RGBA"
    --output "$GLB"
    --gpu "$gpu"
    --seed "$SEED"
    --resolution 1024
    --manual-fov 0.2
  )
  if test "$LOW_VRAM" = "1"; then
    pixal_args+=(--low-vram)
  fi
  { time "$PYTHON" "$WRAPPER" "${pixal_args[@]}"; } 2>&1 | tee "$log"
  status=${PIPESTATUS[0]}
  set -e
  echo "PIXAL_SINGLE_ASSET_EXIT asset=$ASSET attempt=$attempt status=$status"
  if test "$status" -eq 0 && validate_output; then
    echo "PIXAL_SINGLE_COMPLETE asset=$ASSET seed=$SEED output=$GLB"
    exit 0
  fi
  test ! -e "$OUTPUT" || archive_output "failed_attempt_${attempt}"
  if test "$status" -ne 0 && ! grep -Eq 'OutOfMemoryError|CUDA out of memory' "$log"; then
    echo "PIXAL_SINGLE_FAILED_NON_OOM asset=$ASSET status=$status"
    exit "$status"
  fi
  attempt=$((attempt + 1))
  test "$attempt" -le "$MAX_ATTEMPTS" || break
  echo "PIXAL_SINGLE_OOM_RETRY asset=$ASSET cooldown_seconds=$OOM_COOLDOWN_SECONDS"
  sleep "$OOM_COOLDOWN_SECONDS"
done

echo "PIXAL_SINGLE_FINISHED_WITH_FAILURE asset=$ASSET attempts=$MAX_ATTEMPTS"
exit 1
