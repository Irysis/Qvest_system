#==============================================================================
# record_lineage.R — Risk Package lineage record for WT-D20260514_013
# Run AFTER risk_package_draft.json is written.
#==============================================================================
suppressPackageStartupMessages({
  library(jsonlite)
})

WT_ID <- "WT-D20260514_013"

source("02_Infrastructure/worktask/lineage_utils.R")

# Note: we record draft lineage; final lineage will be recorded after Codex Round.
record_package_lineage(
  task_id = WT_ID,
  package_type = "risk_package_draft",
  method_selected = "sample_factor_cov+specific_var_grand_mean_shrink_rho_0_30+psd_floor_1e-8",
  input_file_paths = c(
    "qepm/mailbox/worktask/WT-D20260514_013/alpha_package.json",
    "stage_artifacts/WT_D20260514_013/alpha_lockbox_pit_clean_mandate.parquet",
    ".cache/rawdata.parquet"
  ),
  windows = list(
    list(name = "train_window",
         start = "2021-01-30", end = "2026-01-30", months = 60L),
    list(name = "lockbox_inheritance",
         start = "2024-02-29", end = "2026-01-30", months = 24L)
  ),
  random_seed = 20260515L,
  extra = list(
    sig_date_risk = "2026-01-30",
    n_tickers_cov = 414L,
    K_PCA = 6L,
    cn_sigma = 397.71,
    cov_estimator_log_count = 3L,
    crowding_factors = 2L,
    challenge_flags = 0L
  )
)
cat("Lineage recorded.\n")
