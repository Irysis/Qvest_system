## WT-D20260424_001: Regime-Adaptive PEAD-Accrual Composite (RAPC)
## Alpha Research Pipeline — v6.1
## Train window: 2012-01-21 ~ 2022-01-21
## Lockbox: SEALED (2024-01-23 ~) — train + validation only

cat("=== WT-D20260424_001: RAPC Alpha Pipeline ===\n")

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
})

# ---- Paths ----
ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
CACHE_DIR <- file.path(ROOT, ".cache")
FUNC_PATH <- file.path(ROOT, "02_Infrastructure")
WT_DIR <- file.path(ROOT, "qepm/mailbox/worktask/WT-D20260424_001")
ARTIFACT_DIR <- file.path(ROOT, "stage_artifacts/WT_D20260424_001")

if (!dir.exists(ARTIFACT_DIR)) dir.create(ARTIFACT_DIR, recursive=TRUE)

# ---- PIT-safe evaluation windows (R2 P2: train + validation only) ----
TRAIN_START <- as.Date("2012-01-21")
TRAIN_END   <- as.Date("2022-01-21")
VAL_START   <- as.Date("2022-01-22")
VAL_END     <- as.Date("2024-01-22")
# LOCKBOX: 2024-01-23 ~ SEALED — never access
ANALYSIS_END <- VAL_END  # maximum date we can use

cat("[Step 1] Loading Factor DB via load_month_factors() ...\n")

# Load connector
source(file.path(FUNC_PATH, "factor_db/factor_db_connector.R"))

# Target factors: C04_ESBR, C01_SUE, AC21_CF_to_Accrual_Ratio
TARGET_FACTORS <- c("C04_ESBR", "C01_SUE", "AC21_CF_to_Accrual_Ratio")

# Load all monthly parquet files covering train+validation window
FACTOR_DB_PATH <- file.path(CACHE_DIR, "factor_db")

# Get file list for train+validation period only (C2 P2: no lockbox)
# Monthly files named factor_db_YYYYMM.parquet
files <- list.files(FACTOR_DB_PATH, pattern="factor_db_\\d{6}\\.parquet", full.names=TRUE)

# Filter: 201201 <= YYYYMM <= 202401 (validation end)
file_months <- as.integer(gsub(".*factor_db_(\\d{6})\\.parquet", "\\1", basename(files)))
files_use <- files[file_months >= 201201 & file_months <= 202401]
cat(sprintf("[Step 1] Using %d monthly parquet files (201201~202401)\n", length(files_use)))

# Load and rbind — once only (L-534 pattern)
dt_list <- lapply(files_use, function(f) {
  dt <- as.data.table(read_parquet(f))
  dt
})
dt_raw <- rbindlist(dt_list, fill=TRUE)

# Check available columns
cat("[Step 1] Available columns (sample):", paste(head(names(dt_raw), 20), collapse=", "), "\n")

# Identify factor columns present
target_present <- TARGET_FACTORS[TARGET_FACTORS %in% names(dt_raw)]
cat("[Step 1] Target factors present:", paste(target_present, collapse=", "), "\n")

if (length(target_present) == 0) {
  cat("[WARN] No target factors found by name. Checking Z_Score columns...\n")
  # Try Z_Score_Aligned variants
  z_cols <- names(dt_raw)[grepl("Z_Score_Aligned|ESBR|SUE|Accrual", names(dt_raw), ignore.case=TRUE)]
  cat("[Step 1] Z_Score candidates:", paste(z_cols, collapse=", "), "\n")
}

# Identify date column
date_col <- if ("Date" %in% names(dt_raw)) "Date" else if ("date" %in% names(dt_raw)) "date" else names(dt_raw)[1]
ticker_col <- if ("Ticker" %in% names(dt_raw)) "Ticker" else if ("ticker" %in% names(dt_raw)) "ticker" else "Ticker"
ret_col <- if ("Ret_1M" %in% names(dt_raw)) "Ret_1M" else if ("Ret" %in% names(dt_raw)) "Ret" else NULL

cat(sprintf("[Step 1] date_col=%s ticker_col=%s ret_col=%s\n", date_col, ticker_col, ifelse(is.null(ret_col), "NOT FOUND", ret_col)))
cat("[Step 1] Rows:", nrow(dt_raw), "| Unique tickers:", uniqueN(dt_raw[[ticker_col]]), "\n")
cat("[Step 1] Date range:", as.character(min(dt_raw[[date_col]], na.rm=TRUE)), "~", as.character(max(dt_raw[[date_col]], na.rm=TRUE)), "\n")
