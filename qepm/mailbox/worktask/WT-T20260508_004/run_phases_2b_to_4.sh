#!/bin/bash
# WT-T20260508_004 — Phase 2b/2c/3/4 Chain Rerun (Phase 1 + 2a already complete)

set -e

PROJECT_ROOT="/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_DIR="${PROJECT_ROOT}/qepm/mailbox/worktask/WT-T20260508_004"

cd "${PROJECT_ROOT}"

echo "========================================================"
echo "  WT-T20260508_004 Phase 2b~4 Chain Rerun"
echo "  Started: $(date '+%Y-%m-%d %H:%M:%S')"
echo "========================================================"

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
echo "  Chain Rerun Complete: $(date '+%Y-%m-%d %H:%M:%S')"
echo "========================================================"
