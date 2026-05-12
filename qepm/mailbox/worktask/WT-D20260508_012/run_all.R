#==============================================================================
# WT-D20260508_012 — Lineage Reproduction Wrapper
# Sequential execution: regime indicator build → alpha_package_draft.json
#
# Use case:
#   cd /mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot
#   Rscript qepm/mailbox/worktask/WT-D20260508_012/run_all.R
#==============================================================================

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_DIR <- file.path(PROJECT_ROOT, "qepm/mailbox/worktask/WT-D20260508_012")

cat("[run_all] WT-D20260508_012 — Option-Implied Tail Risk Regime Indicator\n")
cat("[run_all] Step 1: build regime indicator (build_option_tail_regime.R)\n")
source(file.path(WT_DIR, "build_option_tail_regime.R"), chdir = FALSE)

cat("\n[run_all] Step 2: regime-conditional diagnostic (build_regime_conditional_diag.R)\n")
source(file.path(WT_DIR, "build_regime_conditional_diag.R"), chdir = FALSE)

cat("\n[run_all] Step 3: build alpha_package_draft.json\n")
source(file.path(WT_DIR, "build_alpha_package_draft.R"), chdir = FALSE)

cat("\n[run_all] DONE\n")
