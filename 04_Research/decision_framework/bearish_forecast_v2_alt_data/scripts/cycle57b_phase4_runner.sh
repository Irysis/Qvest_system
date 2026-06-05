#!/bin/bash
# cycle57b_phase4_runner.sh — Run 5 q15 cycles sequentially on FIXED2 panels.
# Each cycle: 5 seeds, ~15-20 min on RTX 4080 16GB, gpu_fraction=0.15.
# Total: ~75-100 min expected.

set -u  # do NOT set -e (allow continue-on-error per cycle)

cd "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot/04_Research/decision_framework/bearish_forecast_v2_alt_data" || exit 1

OUT_DIR="outputs/03_models/cycle57b_q15_BBVA_fixed"
mkdir -p "$OUT_DIR"
LOG="$OUT_DIR/_runner_stdout.log"

echo "[cycle57b phase4] START $(date -Iseconds)" | tee -a "$LOG"

VENV_PY="/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot/.venv_dpl/bin/python3"

run_one() {
  local script="$1"
  local label="$2"
  echo "[cycle57b phase4] >>> $label START $(date -Iseconds)" | tee -a "$LOG"
  start=$(date +%s)
  "$VENV_PY" -u "scripts/$script" >> "$LOG" 2>&1
  rc=$?
  end=$(date +%s)
  echo "[cycle57b phase4] <<< $label END $(date -Iseconds) rc=$rc elapsed=$((end-start))s" | tee -a "$LOG"
  return $rc
}

# Run 5 cycles sequentially
run_one "182_53B_v5b_q15_FIXED2.py"        "53B_v5b_FIXED2"
run_one "183_54A_v3_patch7_q15_FIXED2.py"  "54A_v3_patch7_FIXED2"
run_one "184_54A_v4_dm32_q15_FIXED2.py"    "54A_v4_dm32_FIXED2"
run_one "182b_53H_v5e_q15_FIXED2.py"       "53H_v5e_FIXED2"
run_one "182c_53I_v5f_q15_FIXED2.py"       "53I_v5f_FIXED2"

echo "[cycle57b phase4] DONE $(date -Iseconds)" | tee -a "$LOG"
