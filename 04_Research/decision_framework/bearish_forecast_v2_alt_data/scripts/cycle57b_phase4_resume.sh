#!/bin/bash
# cycle57b_phase4_resume.sh — Resume runner that completes remaining cycles.
#
# Status at restart:
#   - 53B_v5b_FIXED2 (5/5 seeds + mean5) — DONE
#   - 54A_v3_patch7_FIXED2 (5/5 seeds + mean5) — DONE
#   - 54A_v4_dm32_FIXED2 (2/5 seeds: 42, 123) — RESUME
#   - 53H_v5e_FIXED2 — PENDING
#   - 53I_v5f_FIXED2 — PENDING
#
# Note: The 167b template runs all 5 seeds atomically in one invocation, so we
# can't truly "resume" mid-cycle. Instead, re-run 54A_v4_dm32 entirely (it will
# overwrite existing seed42/seed123 predictions with identical results since
# strict-PIT determinism + identical seeds + identical inputs guarantee bit-exact
# reproduction). Then proceed to 53H and 53I.

set -u  # do NOT set -e (allow continue-on-error per cycle)

cd "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot/04_Research/decision_framework/bearish_forecast_v2_alt_data" || exit 1

OUT_DIR="outputs/03_models/cycle57b_q15_BBVA_fixed"
mkdir -p "$OUT_DIR"
LOG="$OUT_DIR/_runner_stdout.log"

echo "[cycle57b phase4 RESUME] START $(date -Iseconds)" | tee -a "$LOG"

VENV_PY="/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot/.venv_dpl/bin/python3"

run_one() {
  local script="$1"
  local label="$2"
  echo "[cycle57b phase4 RESUME] >>> $label START $(date -Iseconds)" | tee -a "$LOG"
  start=$(date +%s)
  "$VENV_PY" -u "scripts/$script" >> "$LOG" 2>&1
  rc=$?
  end=$(date +%s)
  echo "[cycle57b phase4 RESUME] <<< $label END $(date -Iseconds) rc=$rc elapsed=$((end-start))s" | tee -a "$LOG"
  return $rc
}

# Resume from 54A_v4_dm32 (re-run entirely for determinism, then 53H + 53I)
run_one "184_54A_v4_dm32_q15_FIXED2.py"    "54A_v4_dm32_FIXED2"
run_one "182b_53H_v5e_q15_FIXED2.py"       "53H_v5e_FIXED2"
run_one "182c_53I_v5f_q15_FIXED2.py"       "53I_v5f_FIXED2"

echo "[cycle57b phase4 RESUME] DONE $(date -Iseconds)" | tee -a "$LOG"
