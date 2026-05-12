#!/bin/bash
# WT-T20260508_004 — Phase 2/3/4 Chain Runner
# Pre-condition: Phase 1 (incremental_update_audit.json) complete with status PASS
# Sequential: 2a (alpha_scores) → 2b (STR_1715) → 2c (Layer A) → 3 (5family) → 4 (compare)

set -e

PROJECT_ROOT="/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_DIR="${PROJECT_ROOT}/qepm/mailbox/worktask/WT-T20260508_004"

cd "${PROJECT_ROOT}"

echo "========================================================"
echo "  WT-T20260508_004 Phase 2~4 Chain Runner"
echo "  Started: $(date '+%Y-%m-%d %H:%M:%S')"
echo "========================================================"

# Phase 1 prerequisite check
if [ ! -f "${WT_DIR}/incremental_update_audit.json" ]; then
  echo "[FAIL] Phase 1 audit not found — aborting"
  exit 1
fi

PHASE1_STATUS=$(python3 -c "import json; d=json.load(open('${WT_DIR}/incremental_update_audit.json')); print(d.get('status','MISSING'))")
echo "[PRE-CHECK] Phase 1 status: ${PHASE1_STATUS}"

if [ "${PHASE1_STATUS}" != "PASS" ] && [ "${PHASE1_STATUS}" != "REVIEW" ]; then
  echo "[FAIL] Phase 1 status not PASS/REVIEW — aborting"
  exit 1
fi

# Phase 2a
echo ""
echo "=== PHASE 2a: alpha_scores regen ==="
Rscript "${WT_DIR}/phase2a_alpha_scores_regen.R" 2>&1 | tee "${WT_DIR}/phase2a.log"

# Phase 2b
echo ""
echo "=== PHASE 2b: STR_1715 base rerun ==="
Rscript "${WT_DIR}/phase2b_str_1715_rerun.R" 2>&1 | tee "${WT_DIR}/phase2b.log"

# Phase 2c
echo ""
echo "=== PHASE 2c: Layer A regen ==="
Rscript "${WT_DIR}/phase2c_layer_a_regen.R" 2>&1 | tee "${WT_DIR}/phase2c.log"

# Phase 3
echo ""
echo "=== PHASE 3: 5-family backtest ==="
Rscript "${WT_DIR}/phase3_run_5family.R" 2>&1 | tee "${WT_DIR}/phase3.log"

# Phase 4
echo ""
echo "=== PHASE 4: pre vs post comparison ==="
Rscript "${WT_DIR}/phase4_comparison_pre_post.R" 2>&1 | tee "${WT_DIR}/phase4.log"

echo ""
echo "========================================================"
echo "  All Phases Complete: $(date '+%Y-%m-%d %H:%M:%S')"
echo "========================================================"
