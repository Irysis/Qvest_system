#!/bin/bash
## WT-T20260508_003 — Phase 2 ~ 4 sequential runner
## Pre-condition: Phase 1 (factor_db_rebuild) 완료
## Usage: bash run_all_phases.sh
##
## Sequential dependency:
##   Phase 2a (alpha_scores regen) — ~10-30 min
##   Phase 2b (STR_1715 base rerun) — ~10-20 min
##   Phase 2c (Layer A regen)      — ~3-5 min
##   Phase 3 (5family backtest)    — ~5-10 min
##   Phase 4 (pre/post 비교)        — ~1 min

set -e

PROJECT_ROOT="/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_DIR="${PROJECT_ROOT}/qepm/mailbox/worktask/WT-T20260508_003"

cd "${PROJECT_ROOT}"

echo "=========================================="
echo "  WT-T20260508_003 Phase 2~4 sequential"
echo "  Started: $(date '+%Y-%m-%d %H:%M:%S')"
echo "=========================================="

# Phase 2a — alpha_scores regen
echo ""
echo "[Phase 2a] alpha_scores.parquet regen..."
Rscript "${WT_DIR}/phase2a_alpha_scores_regen.R" 2>&1 | tee "${WT_DIR}/phase2a.log"
PHASE2A_STATUS=${PIPESTATUS[0]}
if [[ ${PHASE2A_STATUS} -ne 0 ]]; then
    echo "[FAIL] Phase 2a exit code ${PHASE2A_STATUS}"; exit 1
fi
echo "[PASS] Phase 2a done"

# Phase 2b — STR_1715 base rerun
echo ""
echo "[Phase 2b] STR_1715 base run_all.R rerun..."
Rscript "${WT_DIR}/phase2b_str_1715_rerun.R" 2>&1 | tee "${WT_DIR}/phase2b.log"
PHASE2B_STATUS=${PIPESTATUS[0]}
if [[ ${PHASE2B_STATUS} -ne 0 ]]; then
    echo "[FAIL] Phase 2b exit code ${PHASE2B_STATUS}"; exit 1
fi
echo "[PASS] Phase 2b done"

# Phase 2c — Layer A regen
echo ""
echo "[Phase 2c] Layer A (ret_AR_on_M4) regen..."
Rscript "${WT_DIR}/phase2c_layer_a_regen.R" 2>&1 | tee "${WT_DIR}/phase2c.log"
PHASE2C_STATUS=${PIPESTATUS[0]}
if [[ ${PHASE2C_STATUS} -ne 0 ]]; then
    echo "[FAIL] Phase 2c exit code ${PHASE2C_STATUS}"; exit 1
fi
echo "[PASS] Phase 2c done"

# Phase 3 — 5family backtest
echo ""
echo "[Phase 3] 5family re-backtest..."
Rscript "${WT_DIR}/phase3_run_5family_post_rebuild.R" 2>&1 | tee "${WT_DIR}/phase3.log"
PHASE3_STATUS=${PIPESTATUS[0]}
if [[ ${PHASE3_STATUS} -ne 0 ]]; then
    echo "[FAIL] Phase 3 exit code ${PHASE3_STATUS}"; exit 1
fi
echo "[PASS] Phase 3 done"

# Phase 4 — comparison pre/post
echo ""
echo "[Phase 4] 직전 vs 신규 비교..."
Rscript "${WT_DIR}/phase4_comparison_pre_post.R" 2>&1 | tee "${WT_DIR}/phase4.log"
PHASE4_STATUS=${PIPESTATUS[0]}
if [[ ${PHASE4_STATUS} -ne 0 ]]; then
    echo "[FAIL] Phase 4 exit code ${PHASE4_STATUS}"; exit 1
fi
echo "[PASS] Phase 4 done"

echo ""
echo "=========================================="
echo "  All Phase 2~4 complete"
echo "  Finished: $(date '+%Y-%m-%d %H:%M:%S')"
echo "=========================================="
