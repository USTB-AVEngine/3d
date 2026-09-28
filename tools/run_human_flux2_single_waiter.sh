#!/usr/bin/env bash
set -euo pipefail

ROOT=/data/datasets/avengine_workspaces/users/lx/human_sound_source_assets_v1
RUNNER="$ROOT/_tools/run_human_flux2_batch.py"
JOBS="$ROOT/_plans/human_sound_source_flux2_expansion_v3.json"
PYTHON=/data/lx/conda-envs/avengine-imagegen/bin/python
MIN_FREE_MIB=${FLUX_MIN_FREE_MIB:-24000}
MAX_UTILIZATION=${FLUX_MAX_UTILIZATION:-15}
POLL_SECONDS=${FLUX_POLL_SECONDS:-15}
STABLE_SAMPLES=${FLUX_STABLE_SAMPLES:-2}
MAX_WAIT_SECONDS=${FLUX_MAX_WAIT_SECONDS:-43200}

usage() {
  echo "usage: $0 --asset ASSET" >&2
}

ASSET=""
while test "$#" -gt 0; do
  case "$1" in
    --asset) ASSET=${2:-}; shift 2 ;;
    *) usage; exit 2 ;;
  esac
done

case "$ASSET" in
  flute_player|hand_drum_player|megaphone_speaker|clapping_person|coughing_person) ;;
  *) usage; exit 2 ;;
esac

test -f "$RUNNER" || { echo "FLUX_SINGLE_ABORTED missing runner"; exit 1; }
test -f "$JOBS" || { echo "FLUX_SINGLE_ABORTED missing jobs"; exit 1; }

OUTPUT_INFO=$("$PYTHON" - "$JOBS" "$ASSET" <<'PY'
import json
import sys
from pathlib import Path
payload = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
jobs = [job for job in payload["jobs"] if job["asset_id"] == sys.argv[2]]
if len(jobs) != 1:
    raise SystemExit("asset must occur exactly once")
job = jobs[0]
print(job["seed"])
PY
)
SEED=$OUTPUT_INFO
OUTPUT="$ROOT/$ASSET/generation/flux2_seed_${SEED}_v1"

if test -s "$OUTPUT/candidate.png" && test -s "$OUTPUT/generation_manifest.json"; then
  echo "FLUX_SINGLE_SKIP_EXISTING asset=$ASSET seed=$SEED output=$OUTPUT"
  exit 0
fi
if test -e "$OUTPUT"; then
  echo "FLUX_SINGLE_ABORTED incomplete output exists: $OUTPUT"
  exit 1
fi

LOCK_DIR="$ROOT/_locks"
LOCK_FILE="$LOCK_DIR/human_gpu_generation.lock"
mkdir -p "$LOCK_DIR" "$ROOT/_review"
exec 9> "$LOCK_FILE"
if ! flock -n 9; then
  echo "FLUX_SINGLE_ABORTED another Human GPU generation process holds $LOCK_FILE"
  exit 4
fi

STARTED=$(date +%s)
STABLE_GPU=""
STABLE_COUNT=0
echo "FLUX_SINGLE_WAITER_STARTED asset=$ASSET seed=$SEED $(date -u +%Y-%m-%dT%H:%M:%SZ)"
while true; do
  SAMPLE=$(nvidia-smi --query-gpu=index,memory.free,utilization.gpu \
    --format=csv,noheader,nounits | awk -F, -v minimum="$MIN_FREE_MIB" -v maximum="$MAX_UTILIZATION" '
      {
        for (i=1; i<=3; i++) gsub(/ /,"",$i)
        if (($2+0)>=(minimum+0) && ($3+0)<=(maximum+0)) print $1,$2,$3
      }' | sort -k2,2nr | head -n 1)
  if test -n "$SAMPLE"; then
    read -r GPU FREE_MIB UTILIZATION <<< "$SAMPLE"
    if test "$GPU" = "$STABLE_GPU"; then
      STABLE_COUNT=$((STABLE_COUNT + 1))
    else
      STABLE_GPU=$GPU
      STABLE_COUNT=1
    fi
    echo "FLUX_SINGLE_GPU_STABLE_SAMPLE asset=$ASSET gpu=$GPU free_mib=$FREE_MIB util=$UTILIZATION sample=$STABLE_COUNT/$STABLE_SAMPLES"
    if test "$STABLE_COUNT" -ge "$STABLE_SAMPLES"; then
      break
    fi
  else
    STABLE_GPU=""
    STABLE_COUNT=0
    echo "FLUX_SINGLE_WAITING_FOR_GPU asset=$ASSET $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    nvidia-smi --query-gpu=index,memory.free,utilization.gpu --format=csv,noheader
  fi
  if test $(( $(date +%s) - STARTED )) -ge "$MAX_WAIT_SECONDS"; then
    echo "FLUX_SINGLE_TIMED_OUT asset=$ASSET" >&2
    exit 3
  fi
  sleep "$POLL_SECONDS"
done

echo "FLUX_SINGLE_STARTING asset=$ASSET seed=$SEED gpu=$GPU free_mib=$FREE_MIB util=$UTILIZATION"
"$PYTHON" "$RUNNER" \
  --jobs-json "$JOBS" \
  --asset-id "$ASSET" \
  --gpu "$GPU"
echo "FLUX_SINGLE_COMPLETE asset=$ASSET seed=$SEED output=$OUTPUT"
