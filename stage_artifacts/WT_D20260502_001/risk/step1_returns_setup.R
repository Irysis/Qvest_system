#==============================================================================
# WT-D20260502_001 Risk Research — Step 1: Returns matrix + Universe setup
#
# Purpose:
#  - Load 322 alpha vector tickers + STR_1715 (for diversifier validation)
#  - Build daily returns matrix (last 252 trading days, monthly anchor 2026-04-30)
#  - Build monthly returns matrix (60 months for stability)
#  - Build sector / size mapping
#
# Output: stage_artifacts/WT_D20260502_001/risk/returns_state.rds
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
})

PROJ <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_ID <- "WT-D20260502_001"
WT_DIR <- file.path(PROJ, "stage_artifacts", "WT_D20260502_001", "risk")
dir.create(WT_DIR, showWarnings = FALSE, recursive = TRUE)

# ---- Load alpha_package -----------------------------------------------------
alpha_pkg_path <- file.path(PROJ, "qepm/mailbox/worktask", WT_ID, "alpha_package.json")
alpha_pkg <- fromJSON(alpha_pkg_path, simplifyVector = FALSE)
alpha_vector <- unlist(alpha_pkg$alpha_vector)
confidence_vector <- unlist(alpha_pkg$confidence_vector)
n_alpha <- length(alpha_vector)
cat(sprintf("[Step1] alpha_vector: %d tickers\n", n_alpha))

# ---- RAWDATA cache load -----------------------------------------------------
RAWDATA_CACHE <- file.path(PROJ, ".cache/rawdata.parquet")
RAWDATA <- as.data.table(read_parquet(RAWDATA_CACHE))
cat(sprintf("[Step1] RAWDATA: %d rows | %s ~ %s\n",
            nrow(RAWDATA), min(RAWDATA$Date), max(RAWDATA$Date)))
cat(sprintf("[Step1] RAWDATA columns: %s\n", paste(names(RAWDATA), collapse=",")))
cat(sprintf("[Step1] Unique tickers: %d\n", uniqueN(RAWDATA$Ticker)))

# ---- as_of_date ---
as_of_date <- as.Date(alpha_pkg$as_of_date)  # 2026-04-30
cat(sprintf("[Step1] as_of_date: %s\n", as_of_date))

# ---- Daily returns (last 252 trading days for daily-based stress + tail) -----
# t-1 lag: anchor at as_of_date - 1
end_date <- as_of_date  # already PIT (alpha generated for 2026-04-30)
# 252 trading days back ~ 1 calendar year
start_252_calendar <- end_date - 365L
returns_252 <- RAWDATA[Date >= start_252_calendar & Date <= end_date,
                       .(Date, Ticker, Ret)]

# Filter to alpha tickers + STR_1715 will be loaded separately
alpha_tickers <- names(alpha_vector)
returns_filtered <- returns_252[Ticker %in% alpha_tickers]

# Pivot wide
returns_wide_252 <- dcast(returns_filtered, Date ~ Ticker, value.var = "Ret")
cat(sprintf("[Step1] Daily returns last 252 — wide: %d days x %d tickers\n",
            nrow(returns_wide_252), ncol(returns_wide_252) - 1))

# ---- Monthly returns (last 60 months for cov stability + crisis sample) -----
RAWDATA[, YM := format(Date, "%Y-%m")]
# Compute monthly compounded returns per ticker
monthly_returns <- RAWDATA[Date <= end_date,
                           .(Ret_M = prod(1 + Ret, na.rm = TRUE) - 1, n_days = .N),
                           by = .(Ticker, YM)]
# Keep only month-ends with sufficient n_days
monthly_returns <- monthly_returns[n_days >= 12]
# Last 60 months
all_ym <- sort(unique(monthly_returns$YM))
last_60_ym <- tail(all_ym, 60L)
monthly_returns_60 <- monthly_returns[YM %in% last_60_ym & Ticker %in% alpha_tickers]
monthly_wide_60 <- dcast(monthly_returns_60, YM ~ Ticker, value.var = "Ret_M")
cat(sprintf("[Step1] Monthly returns last 60 — wide: %d months x %d tickers\n",
            nrow(monthly_wide_60), ncol(monthly_wide_60) - 1))

# ---- Long-history monthly returns (full 2008+ for stress + AX-001 axis 1) ----
ym_2008 <- all_ym[all_ym >= "2008-01"]
monthly_returns_full <- monthly_returns[YM %in% ym_2008 & Ticker %in% alpha_tickers]
monthly_wide_full <- dcast(monthly_returns_full, YM ~ Ticker, value.var = "Ret_M")
cat(sprintf("[Step1] Monthly returns 2008-now — wide: %d months x %d tickers\n",
            nrow(monthly_wide_full), ncol(monthly_wide_full) - 1))

# ---- Universe alignment ---
# Tickers that have at least 60% coverage in last 60M
non_na_count_60M <- colSums(!is.na(monthly_wide_60[, -1, with=FALSE]))
n_months <- nrow(monthly_wide_60)
covered_60M <- names(non_na_count_60M)[non_na_count_60M >= round(n_months * 0.6)]
cat(sprintf("[Step1] Tickers with >=60%% coverage 60M: %d / %d alpha\n",
            length(covered_60M), n_alpha))

# ---- Save state -------------------------------------------------------------
state <- list(
  task_id = WT_ID,
  as_of_date = as_of_date,
  alpha_vector = alpha_vector,
  confidence_vector = confidence_vector,
  alpha_tickers = alpha_tickers,
  covered_tickers_60M = covered_60M,
  returns_wide_252_daily = returns_wide_252,
  monthly_wide_60 = monthly_wide_60,
  monthly_wide_full = monthly_wide_full,
  diagnostics = list(
    n_alpha_tickers = n_alpha,
    n_covered_60M = length(covered_60M),
    daily_252_days = nrow(returns_wide_252),
    monthly_60M_months = nrow(monthly_wide_60),
    monthly_full_months = nrow(monthly_wide_full)
  )
)
saveRDS(state, file.path(WT_DIR, "step1_state.rds"))
cat(sprintf("[Step1] Saved state to %s\n", file.path(WT_DIR, "step1_state.rds")))
cat("[Step1] DONE.\n")
