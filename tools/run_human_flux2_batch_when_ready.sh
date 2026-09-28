#!/usr/bin/env bash
set -euo pipefail

ROOT=/data/datasets/avengine_workspaces/users/lx/human_sound_source_assets_v1
RUNNER="$ROOT/_tools/run_human_flux2_batch.py"
JOBS="$ROOT/_plans/human_sound_source_flux2_remaining_v1.json"
PYTHON=/data/lx/conda-envs/avengine-imagegen/bin/python
EXPECTED_RUNNER_SHA256=15082924579352ea5f706bb783405a428c04596564acfee1e737594bc08325c9
EXPECTED_JOBS_SHA256=6fde21dc3ca07d12ba333b2d7cb323f2c1f6e7d9b02f71aca0761de530a79995
MIN_FREE_MIB=45000
MAX_UTILIZATION=5
POLL_SECONDS=30
STABLE_SAMPLES=2
MAX_WAIT_SECONDS=43200
MAX_ATTEMPTS=3
OOM_COOLDOWN_SECONDS=120
LOCK_DIR="$ROOT/_locks"
LOCK_FILE="$LOCK_DIR/human_flux2_remaining_v1.lock"
REVIEW_DIR="$ROOT/_review"

file_sha256() {
  sha256sum "$1" | awk '{print $1}'
}

verify_inputs() {
  test -f "$RUNNER" || {
    echo "HUMAN_FLUX2_BATCH_ABORTED runner missing: $RUNNER"; return 1;
  }
  test -f "$JOBS" || {
    echo "HUMAN_FLUX2_BATCH_ABORTED jobs JSON missing: $JOBS"; return 1;
  }
  test "$(file_sha256 "$RUNNER")" = "$EXPECTED_RUNNER_SHA256" || {
    echo "HUMAN_FLUX2_BATCH_ABORTED runner hash mismatch"; return 1;
  }
  test "$(file_sha256 "$JOBS")" = "$EXPECTED_JOBS_SHA256" || {
    echo "HUMAN_FLUX2_BATCH_ABORTED jobs JSON hash mismatch"; return 1;
  }
  "$PYTHON" -m py_compile "$RUNNER"
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
      echo "HUMAN_FLUX2_GPU_STABLE_SAMPLE gpu=$gpu uuid=$uuid free_mib=$free_mib util=$utilization sample=$stable_count/$STABLE_SAMPLES"
      if test "$stable_count" -ge "$STABLE_SAMPLES"; then
        echo "$gpu $uuid $free_mib $utilization"
        return 0
      fi
    else
      stable_gpu=""
      stable_count=0
      echo "HUMAN_FLUX2_WAITING_FOR_GPU $(date -u +%Y-%m-%dT%H:%M:%SZ)"
      nvidia-smi \
        --query-gpu=index,memory.free,utilization.gpu \
        --format=csv,noheader
    fi

    if test $(( $(date +%s) - started_waiting )) -ge "$MAX_WAIT_SECONDS"; then
      echo "HUMAN_FLUX2_BATCH_TIMED_OUT" >&2
      return 3
    fi
    sleep "$POLL_SECONDS"
  done
}

mkdir -p "$LOCK_DIR" "$REVIEW_DIR"
exec 9> "$LOCK_FILE"
if ! flock -n 9; then
  echo "HUMAN_FLUX2_BATCH_ABORTED another batch waiter holds $LOCK_FILE"
  exit 4
fi

verify_inputs
started_waiting=$(date +%s)
echo "HUMAN_FLUX2_BATCH_WAITER_STARTED $(date -u +%Y-%m-%dT%H:%M:%SZ)"

attempt=1
while test "$attempt" -le "$MAX_ATTEMPTS"; do
  echo "HUMAN_FLUX2_BATCH_WAITING attempt=$attempt/$MAX_ATTEMPTS"
  selected=$(wait_for_stable_gpu)
  read -r gpu gpu_uuid free_mib utilization <<< "$(tail -n 1 <<< "$selected")"
  printf '%s\n' "$selected" | head -n -1 || true
  verify_inputs

  log="$REVIEW_DIR/human_flux2_remaining_attempt_${attempt}_$(date -u +%Y%m%dT%H%M%SZ).log"
  echo "HUMAN_FLUX2_BATCH_STARTING attempt=$attempt gpu=$gpu uuid=$gpu_uuid free_mib=$free_mib util=$utilization log=$log"

  set +e
  { time "$PYTHON" "$RUNNER" \
    --jobs-json "$JOBS" \
    --gpu "$gpu"; } 2>&1 | tee "$log"
  status=${PIPESTATUS[0]}
  set -e
  echo "HUMAN_FLUX2_BATCH_EXIT_STATUS attempt=$attempt status=$status"

  if test "$status" -eq 0; then
    break
  fi
  if ! grep -Eq 'OutOfMemoryError|CUDA out of memory' "$log"; then
    echo "HUMAN_FLUX2_BATCH_ABORTED non-OOM failure is not automatically retried"
    exit "$status"
  fi
  if test "$attempt" -ge "$MAX_ATTEMPTS"; then
    echo "HUMAN_FLUX2_BATCH_ABORTED maximum OOM attempts reached"
    exit "$status"
  fi
  echo "HUMAN_FLUX2_BATCH_OOM_RETRY cooldown_seconds=$OOM_COOLDOWN_SECONDS"
  sleep "$OOM_COOLDOWN_SECONDS"
  attempt=$((attempt + 1))
done

for specification in \
  phone_call:42002 \
  guitar_player:42003 \
  violin_player:42004 \
  pianist:42005; do
  asset=${specification%%:*}
  seed=${specification##*:}
  output="$ROOT/$asset/generation/flux2_seed_${seed}_v1"
  sha256sum "$output/candidate.png" "$output/generation_manifest.json"
done

echo "HUMAN_FLUX2_BATCH_COMPLETE"
