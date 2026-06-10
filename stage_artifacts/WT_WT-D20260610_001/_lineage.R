root <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
Sys.setenv(CLAUDE_PROJECT_DIR = root)
setwd(root)
source(file.path(root, "02_Infrastructure/worktask/lineage_utils.R"))
record_package_lineage(
  task_id = "WT-D20260610_001",
  package_type = "alpha_package_draft",
  method_selected = "value6_eqw_plus_0.5xR05_top25EW_canonical_screen (chain, n_trials=1)",
  input_file_paths = c(
    ".cache/rawdata.parquet",
    ".cache/factor_db/factor_db_*.parquet (2005-01..2026-05)",
    "05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/04_backtest_results/period_returns_layer5.csv"
  ),
  extra = list(
    metric_type = "canonical_screen",
    codex_round = "BLOCKED_token_expired",
    finalized = FALSE,
    note = "draft only — finalize alpha_package.json after Codex Round re-run"
  )
)
cat("[lineage] recorded for alpha_package_draft\n")
