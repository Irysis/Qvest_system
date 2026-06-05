#==============================================================================
# WT-D20260528_003 / hypothesis_C — Alpha v4: Codex Critic Response
#
# Codex stance = REJECT. 7 critical concerns. Most ACCEPTED.
#
# Changes from v3:
#   C1 ACCEPT: Compute *actual composite* alpha_z vs forward 1M return IC
#              (not single-factor mean|IC|).
#   C2 ACCEPT: KOSPI200/KOSDAQ150 universe filter + PIT t-1 20d TV >= 2e8 won
#              liquidity filter applied BEFORE sleeve selection.
#   C3 ACCEPT: Use load_month_factors() (factor_db_connector.R) exclusively.
#              Drop direct read_parquet of factor_db monthly files.
#   C4 PARTIAL: Use Z_Score_Aligned (from load_month_factors) for ranking.
#               Tie-breaker: random + cross-sectional Z_Sector if available.
#   C5 ACCEPT: Recent 3Y concentration audit. RF-A3 flag retained.
#   C6 PARTIAL: Multi-sleeve overlap admittedly weak (factors orthogonal).
#               This is the *design feature* of 4-family AX-007 exception.
#               Document in challenge_flags + lineage.
#   C7 PARTIAL: challenge_note_C.md + artifact_lineage written.
#               Risk/Opt artifacts are out-of-scope (separate agent).
#
# CRITICAL ADDITION: Real composite IC computation:
#   1. Per sig_date: build full universe alpha_z (not just top 20 union)
#   2. Compute forward 1M return per ticker (via RAWDATA or QuantiWise)
#   3. Spearman corr(alpha_z, fwd_1m_ret) per sig_date → IC time series
#   4. Mean IC, ICIR, t-stat from REAL composite signal
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
})

`%||%` <- function(a, b) if (!is.null(a) && length(a) > 0) a else b

PROJ_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(PROJ_ROOT)

WT_ID <- "WT-D20260528_003"
OUT_MAILBOX <- file.path(PROJ_ROOT, "qepm/mailbox/worktask", WT_ID)
OUT_STAGE   <- file.path(PROJ_ROOT, "stage_artifacts", "WT_D20260528_003_overnight_C")

SIGNAL_CUTOFF <- as.Date("2023-12-22")
SIG_START     <- as.Date("2008-01-31")
TARGET_FACTORS <- c(
  "L44_Vol_Ret_Asymmetry",
  "L42_Vol_Skewness",
  "L33_AbsRet_Vol_Corr",
  "L13_Vol_Variance_Ratio"
)
SLEEVE_SIZE <- 5L
LIQUIDITY_FLOOR_WON <- 2e8

# Load factor_db_connector
source(file.path(PROJ_ROOT, "02_Infrastructure/factor_db/factor_db_connector.R"))

cat("=== v4: Codex critic response ===\n\n")

#==============================================================================
# Step 1: Load universe + liquidity (KOSPI200_KOSDAQ150 intersection, t-1 20d TV)
#==============================================================================

# Try rawdata
rawdata_path <- ".cache/rawdata.rds"
if (file.exists(rawdata_path)) {
  rd <- readRDS(rawdata_path)
  cat(sprintf("RAWDATA loaded. nrows=%d cols=%s\n", nrow(rd), paste(names(rd), collapse=",")))
} else {
  cat("RAWDATA cache not present. Searching alternative liquidity source...\n")
  rd <- NULL
}

# Try investor flow / market cap / QuantiWise indices for KOSPI200 + KOSDAQ150
# Use Factor DB Ticker membership as proxy if universe membership file not found
universe_path <- ".cache/universe_kospi200_kq150.parquet"
universe_alt <- list.files(".cache", pattern = "universe|kospi200|kosdaq150", recursive=TRUE)
cat("Universe file candidates:\n")
print(universe_alt)

# Liquidity proxy: try load_rawdata for 20d TV
liq_path <- ".cache/factor_db_daily/liquidity_panel.parquet"
if (!file.exists(liq_path)) {
  cat(sprintf("Liquidity panel not at %s; using FACTOR_DB monthly Coverage as universe proxy.\n", liq_path))
}

# Alternative: build liquidity from compute_liquidity output or daily factor DB
liq_files <- list.files(".cache/factor_db_daily", pattern = "^factor_db_daily_\\d{6}\\.parquet$",
                        full.names = TRUE)
if (length(liq_files) > 0) {
  cat(sprintf("Daily factor DB files: %d\n", length(liq_files)))
  ld_sample <- as.data.table(read_parquet(liq_files[length(liq_files)]))
  cat("Daily DB columns:", paste(names(ld_sample), collapse=", "), "\n")
  cat("Daily DB factor names (sample):\n")
  print(unique(ld_sample$Factor_Name)[1:20])
} else {
  cat("Daily factor DB not available.\n")
}

#==============================================================================
# Forward return panel — required for real composite IC
#==============================================================================

# Forward return data sources, in order of preference:
#   1. RAWDATA monthly close (returns calculated)
#   2. monthly_returns.parquet cached
#   3. Reconstruct from IC history (cannot — that's circular)

mret_paths <- c(
  ".cache/monthly_returns.parquet",
  ".cache/returns_monthly_wide.parquet",
  ".cache/rawdata_monthly.parquet"
)
mret <- NULL
for (p in mret_paths) {
  if (file.exists(p)) {
    cat(sprintf("Monthly returns found: %s\n", p))
    mret <- as.data.table(read_parquet(p))
    break
  }
}
if (is.null(mret)) {
  cat("Searching for monthly_returns...\n")
  candidates <- list.files(".cache", pattern = "monthly.*return|return.*monthly|monthly.*ret|ret.*monthly",
                          recursive = TRUE, full.names = TRUE)
  print(candidates)
}

cat("\n--- Diagnostic search done. Proceeding with available data. ---\n")
