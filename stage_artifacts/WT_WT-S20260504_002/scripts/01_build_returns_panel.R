#==============================================================================
# WT-S20260504_002 — DCC GARCH Vol Target Risk Research
# Step 1: Build returns panels (daily for DCC stocks + monthly for σ_p)
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(jsonlite)
})

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_ID <- "WT-S20260504_002"
SA <- file.path(PROJECT_ROOT, "stage_artifacts", paste0("WT_", WT_ID))
DIR_DBG <- file.path(SA, "_debug")
dir.create(DIR_DBG, recursive = TRUE, showWarnings = FALSE)

cat("[Step 1] Build returns panels — START\n")

# ─── 18 active stocks (from 2026-05-01 weights; weight > 0) ──────────────
ACTIVE_18 <- c(
  "A010950","A050890","A009420","A058470","A005930","A071970","A095340",
  "A084370","A403870","A218410","A039030","A240810","A002380","A000660",
  "A064760","A053030","A290650","A026960"
)
stopifnot(length(ACTIVE_18) == 18L)

# ─── Daily RAWDATA ─────────────────────────────────────────────────────────
raw <- as.data.table(read_parquet(file.path(PROJECT_ROOT, ".cache", "rawdata.parquet")))
sub <- raw[Ticker %in% ACTIVE_18, .(Date, Ticker, Close, Ret)]
setkey(sub, Ticker, Date)

# Common-date intersection (all 18 must have data on same Date)
n_per_date <- sub[, .N, by = Date][N == 18L]
common_dates <- n_per_date$Date
sub_common <- sub[Date %in% common_dates]
cat(sprintf("[Step 1] Common-date daily intersection: %d days (%s -> %s)\n",
            length(common_dates),
            as.character(min(common_dates)),
            as.character(max(common_dates))))

# Wide daily returns
ret_wide_daily <- dcast(sub_common, Date ~ Ticker, value.var = "Ret")
# Drop rows with any NA in stock-return columns
stk_cols <- setdiff(names(ret_wide_daily), "Date")
ret_wide_daily <- ret_wide_daily[complete.cases(ret_wide_daily[, ..stk_cols]), ]
cat(sprintf("[Step 1] Daily returns matrix: T=%d, K=%d\n",
            nrow(ret_wide_daily), ncol(ret_wide_daily) - 1L))

# ─── Monthly aggregation (compounded) for monthly DCC if needed ──────────
sub_common[, ym := format(Date, "%Y-%m")]
# Compound monthly per ticker
agg_monthly_fn <- function(r) prod(1 + r) - 1
monthly_long <- sub_common[, .(MonthlyRet = agg_monthly_fn(Ret)), by = .(Ticker, ym)]
ret_wide_monthly <- dcast(monthly_long, ym ~ Ticker, value.var = "MonthlyRet")
ret_wide_monthly <- ret_wide_monthly[order(ym)]
cat(sprintf("[Step 1] Monthly returns matrix: T=%d, K=%d\n",
            nrow(ret_wide_monthly), ncol(ret_wide_monthly) - 1L))

# ─── STR_1715 strategy monthly returns (268m) ──────────────────────────────
pr <- fread(file.path(PROJECT_ROOT,
  "04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/output/03_period_returns.csv"))
str_returns <- pr[, .(date = as.Date(date), ret_net, ret_gross)]
setorder(str_returns, date)
stopifnot(nrow(str_returns) >= 268L)
cat(sprintf("[Step 1] STR_1715 monthly returns: T=%d (%s -> %s)\n",
            nrow(str_returns),
            as.character(min(str_returns$date)),
            as.character(max(str_returns$date))))

# ─── Save ─────────────────────────────────────────────────────────────────
write_parquet(ret_wide_daily, file.path(SA, "returns_daily_18.parquet"))
write_parquet(ret_wide_monthly, file.path(SA, "returns_monthly_18.parquet"))
write_parquet(str_returns, file.path(SA, "str1715_monthly_returns.parquet"))

# ─── Diagnostics ───────────────────────────────────────────────────────────
diag <- list(
  step = "01_build_returns_panel",
  status = if (nrow(ret_wide_daily) >= 252L && nrow(ret_wide_daily) > 0L &&
               nrow(str_returns) >= 268L) "PASS" else "WARN",
  active_18 = ACTIVE_18,
  daily_T = nrow(ret_wide_daily),
  daily_K = ncol(ret_wide_daily) - 1L,
  daily_first = as.character(min(ret_wide_daily$Date)),
  daily_last  = as.character(max(ret_wide_daily$Date)),
  monthly_T = nrow(ret_wide_monthly),
  monthly_K = ncol(ret_wide_monthly) - 1L,
  monthly_first = ret_wide_monthly$ym[1L],
  monthly_last  = ret_wide_monthly$ym[nrow(ret_wide_monthly)],
  str1715_monthly_T = nrow(str_returns),
  str1715_monthly_first = as.character(min(str_returns$date)),
  str1715_monthly_last  = as.character(max(str_returns$date)),
  newest_stock = "A403870 (HPSP, listed 2022-07-18 — drives common-date floor)",
  pit_note = "Daily Ret = Close[t]/Close[t-1]-1; t-1 close PIT-safe; no future leakage"
)
write_json(diag, file.path(DIR_DBG, "step01_build_returns.json"),
           pretty = TRUE, auto_unbox = TRUE)

cat("[Step 1] DONE\n")
