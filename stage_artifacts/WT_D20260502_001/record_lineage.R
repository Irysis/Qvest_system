# Record lineage for alpha_package.json
suppressMessages({
  library(jsonlite)
  library(digest)
})

PROJ <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(PROJ)
source("02_Infrastructure/worktask/lineage_utils.R")

input_files <- c(
  ".cache/factor_db/factor_registry.json",
  ".cache/unified_regime_signal.parquet",
  ".cache/rawdata.parquet",
  "qepm/mailbox/governor/str_1715_full_reassessment/str_1715_monthly_returns_full.csv",
  "stage_artifacts/WT_D20260502_001/alpha_pipeline_v5_walkforward.R",
  "stage_artifacts/WT_D20260502_001/alpha_pipeline_v6_live.R",
  "stage_artifacts/WT_D20260502_001/build_alpha_package_v2.R",
  "stage_artifacts/WT_D20260502_001/alpha_scores.parquet",
  "stage_artifacts/WT_D20260502_001/alpha_validation.json"
)

record_package_lineage(
  task_id = "WT-D20260502_001",
  package_type = "alpha_package",
  method_selected = "walk_forward_36m_train_1m_oos_with_ICIR_weighted_top4_NW_t_threshold_2_5",
  input_file_paths = input_files,
  windows = list(
    train_window_months = 36L,
    oos_horizon_months = 1L,
    window_start = "2008-01-31",
    window_end = "2026-04-30",
    n_oos_months = 184L
  ),
  random_seed = NULL,
  extra = list(
    pipeline_version = "v6_walkforward_post_codex_revise",
    codex_round = 1L,
    codex_stance = "REJECT",
    agent_response = "5_ACCEPT_2_PARTIAL_1_REBUTTAL",
    selection_objective = "icir",
    n_factor_candidates = 7L,
    n_factor_selected = 3L,
    selected_factors = "D43_Skewness, R13_NCSKEW, Q07_Earnings_Stability"
  )
)

cat("\nLineage recorded for alpha_package.json (WT-D20260502_001)\n")

# Verify
lineage_path <- "qepm/mailbox/worktask/WT-D20260502_001/artifact_lineage.json"
if (file.exists(lineage_path)) {
  lin <- fromJSON(lineage_path, simplifyVector = FALSE)
  cat(sprintf("artifact_lineage.json: %d entries\n", length(lin$entries)))
  if (length(lin$entries) > 0) {
    last <- lin$entries[[length(lin$entries)]]
    cat(sprintf("  last entry: package_type=%s task_id=%s\n",
                last$package_type, last$task_id))
    cat(sprintf("  method_selected: %s\n", last$method_selected))
  }
}
