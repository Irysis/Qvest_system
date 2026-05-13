# WT-D20260512_003 — Step 2/3: Build candidate factor panel
# 268m × candidates → cross-sectional Z-score panel + STR_1715 alpha cor

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(future)
  library(future.apply)
})

setwd("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")
source("02_Infrastructure/factor_db/factor_db_connector.R")

# Candidate factors (stress-positive empirical) + current sleeve baseline
CAND <- c(
  # V-family stress-positive (KR flight-to-value premium)
  "V01_BM", "V18_AM", "V19_Debt_to_Market", "V20_SP", "V11_Shareholder_Yield",
  # Risk / tail factors
  "MK01_CAPM_Beta", "R05_Tail_Risk", "D17_Cokurtosis",
  # Liquidity-stress
  "L19_Price_Delay", "L20_Trade_Frequency", "L21_Market_Depth", "L44_Vol_Ret_Asymmetry",
  # Consensus stress
  "C19_Composite_Earnings", "C12_Estimate_Dispersion_Proxy",
  # Defense baseline (current STR_1715 sleeve)
  "Q07_Earnings_Stability", "M08_Residual_Mom", "Q25_Ohlson_O",
  # Core baseline (current STR_1715)
  "C01_SUE", "C04_ESBR", "C06_TP_Gap"
)

# Load STR_1715 alpha
ap <- as.data.table(read_parquet("stage_artifacts/WT_D20260426_004/alpha_scores.parquet"))
ap[, Date := as.Date(Date)]
ap[, Ret_1m := as.numeric(Ret_1m)]

sig_dates <- sort(unique(ap$Date))
cat("[panel] Total sig_dates:", length(sig_dates), "\n")
cat("[panel] Range:", as.character(range(sig_dates)), "\n")

# Parallel per-month FDB load + merge
n_workers <- min(8L, parallel::detectCores() - 1L)
cat("[panel] Workers:", n_workers, "\n")
plan(multisession, workers = n_workers)

PROJ_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"

t0 <- Sys.time()
panel_list <- future_lapply(sig_dates, function(sd) {
  setwd(PROJ_ROOT)
  suppressPackageStartupMessages({
    library(data.table); library(arrow)
  })
  source("02_Infrastructure/factor_db/factor_db_connector.R", local = TRUE)
  fm <- as.data.table(load_month_factors(sd))
  fm_sub <- fm[Factor_Name %in% CAND]
  if (nrow(fm_sub) == 0) return(NULL)
  fm_wide <- dcast(fm_sub, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")
  fm_wide[, Date := sd]
  ap_sd <- ap[Date == sd, .(Date, Ticker, score_eff, score_core_z, score_defense_z,
                            Ret_1m, regime_state)]
  merged <- merge(ap_sd, fm_wide, by = c("Date", "Ticker"), all = FALSE)
  merged
}, future.seed = TRUE, future.globals = c("CAND", "ap", "PROJ_ROOT"))
plan(sequential)
cat("[panel] elapsed:", round(as.numeric(difftime(Sys.time(), t0, units="secs")), 1), "s\n")

panel <- rbindlist(panel_list, fill = TRUE)
cat("[panel] panel rows:", nrow(panel), "\n")
cat("[panel] panel cols:", paste(names(panel), collapse=", "), "\n")
cat("[panel] regime breakdown:\n")
print(panel[, .N, by = regime_state])

# Save
dir.create("stage_artifacts/WT_D20260512_003", showWarnings = FALSE, recursive = TRUE)
write_parquet(panel, "stage_artifacts/WT_D20260512_003/candidate_panel.parquet")
cat("[panel] saved candidate_panel.parquet (", nrow(panel), "rows )\n")
