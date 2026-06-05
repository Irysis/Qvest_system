#!/usr/bin/env bash
# cycle55a_final_aggregate_trigger.sh
#
# Waits until all 5 cycles (53B, 53H, 53I, 54A_v3, 54A_v4) have at least 1 seed
# of predictions, then triggers final aggregate (163.R).
#
# Use: nohup bash scripts/cycle55a_final_aggregate_trigger.sh > outputs/_logs/cycle55a_aggregate_trigger.log 2>&1 &

set -u

WS="/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot/04_Research/decision_framework/bearish_forecast_v2_alt_data"
OUT_DIR="$WS/outputs/03_models/cycle55a_strict_PIT"
SEEDS=(42 123 456 789 1024)

wait_all_cycles_done() {
  # Wait until 53B / 53I / 54A_v3 / 54A_v4 all have all 5 seeds (53H reused)
  local cycles=("53B_v5b" "53I_v5f" "54A_v3_patch7" "54A_v4_dm32")
  local check_interval=180  # 3 min
  local max_wait=43200       # 12h hard limit
  local elapsed=0
  while true; do
    local all_done=true
    for cn in "${cycles[@]}"; do
      for s in "${SEEDS[@]}"; do
        local fp="$OUT_DIR/predictions_${cn}_seed${s}_y_tail_q126.parquet"
        if [ ! -f "$fp" ]; then
          all_done=false
          break 2
        fi
      done
    done
    if [ "$all_done" = "true" ]; then
      echo "[wait_all_cycles_done] All 4 cycles × 5 seeds complete"
      return 0
    fi
    local done_count=$(ls "$OUT_DIR" 2>/dev/null | grep -E "predictions_(53B|53I|54A)_.*_seed.*_y_tail_q126.parquet" | wc -l)
    echo "[wait_all_cycles_done] $done_count / 20 parquets so far (need all 4 cycles × 5 seeds), waiting ${check_interval}s (elapsed ${elapsed}s)"
    if [ "$elapsed" -ge "$max_wait" ]; then
      echo "[wait_all_cycles_done] MAX wait exceeded ($max_wait s) → proceed with whatever is available"
      return 1
    fi
    sleep "$check_interval"
    elapsed=$((elapsed + check_interval))
  done
}

main() {
  local trigger_start=$(date -u +%s)
  echo "[trigger] Cycle 55A final aggregate trigger start at $(date -u +%FT%TZ)"

  wait_all_cycles_done

  echo ""
  echo "=================================================================="
  echo "[trigger] All cycles done — running 163.R aggregate"
  echo "=================================================================="

  cd "$WS"
  Rscript "$WS/scripts/163_strict_PIT_all_q126_aggregate.R" 2>&1 | tee "$WS/outputs/_logs/cycle55a_final_aggregate.log"
  local rc=$?

  local trigger_elapsed=$(($(date -u +%s) - trigger_start))
  if [ $rc -eq 0 ]; then
    echo "[trigger] aggregate DONE rc=$rc total elapsed=${trigger_elapsed}s ($((trigger_elapsed/60))min)"
  else
    echo "[trigger] aggregate FAILED rc=$rc total elapsed=${trigger_elapsed}s ($((trigger_elapsed/60))min)"
  fi
}

main
