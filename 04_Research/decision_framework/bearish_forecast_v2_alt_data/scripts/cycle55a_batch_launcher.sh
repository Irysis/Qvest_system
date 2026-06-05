#!/usr/bin/env bash
# cycle55a_batch_launcher.sh — Sequential 4-cycle batch runner.
#
# Runs 4 cycles back-to-back (no parallel) to avoid GPU memory contention with
# concurrent training processes (139, 153, 155). Waits for GPU free memory ≥6GB
# before each cycle starts. 53H reuses 56B FULL — no re-train needed.

set -u

WS="/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot/04_Research/decision_framework/bearish_forecast_v2_alt_data"
VENV_PY="/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot/.venv_dpl/bin/python3"
LOG_DIR="$WS/outputs/_logs"
mkdir -p "$LOG_DIR"

# Cycles in execution order (53H reuses 56B FULL, skipped here)
CYCLES=(
  "158_53b_v5b_strict.py:53B_v5b"
  "160_53i_v5f_strict.py:53I_v5f"
  "161_54a_v3_strict.py:54A_v3_patch7"
  "162_54a_v4_strict.py:54A_v4_dm32"
)

# Wait for GPU memory ≥ 6 GB free
wait_gpu() {
  local needed_gb=6
  local check_interval=120  # 2 min
  local max_wait=10800       # 3h
  local elapsed=0
  while true; do
    local free_mib=$(nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits | head -1)
    local free_gb=$((free_mib / 1024))
    if [ "$free_gb" -ge "$needed_gb" ]; then
      echo "[wait_gpu] GPU free=${free_gb}GB (≥${needed_gb}GB needed) → proceed"
      return 0
    fi
    echo "[wait_gpu] GPU free=${free_gb}GB < ${needed_gb}GB needed, waiting ${check_interval}s (elapsed ${elapsed}s)"
    if [ "$elapsed" -ge "$max_wait" ]; then
      echo "[wait_gpu] MAX wait exceeded → proceed anyway"
      return 1
    fi
    sleep "$check_interval"
    elapsed=$((elapsed + check_interval))
  done
}

main() {
  local batch_start=$(date -u +%s)
  echo "[batch] Cycle 55A 4-cycle batch start at $(date -u +%FT%TZ)"
  echo "[batch] cycles: ${CYCLES[*]}"

  for entry in "${CYCLES[@]}"; do
    local script="${entry%%:*}"
    local cycle_name="${entry##*:}"
    local log_file="$LOG_DIR/cycle55a_${cycle_name}.log"

    echo ""
    echo "=================================================================="
    echo "[batch] starting cycle: $cycle_name (script=$script)"
    echo "=================================================================="

    wait_gpu

    local cycle_start=$(date -u +%s)
    "$VENV_PY" -u "$WS/scripts/$script" > "$log_file" 2>&1
    local rc=$?
    local cycle_elapsed=$(($(date -u +%s) - cycle_start))

    if [ $rc -eq 0 ]; then
      echo "[batch] cycle $cycle_name DONE rc=$rc elapsed=${cycle_elapsed}s ($((cycle_elapsed/60))min)"
    else
      echo "[batch] cycle $cycle_name FAILED rc=$rc elapsed=${cycle_elapsed}s ($((cycle_elapsed/60))min) — see log $log_file"
    fi
    echo "[batch] log tail:"
    tail -20 "$log_file"
  done

  local batch_elapsed=$(($(date -u +%s) - batch_start))
  echo ""
  echo "=================================================================="
  echo "[batch] All cycles DONE. Total elapsed=${batch_elapsed}s ($((batch_elapsed/60))min)"
  echo "=================================================================="
}

main
