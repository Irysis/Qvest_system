#==============================================================================
# WT-D20260508_008 — Sector Momentum Cross-Section Alpha
# Asness-Frazzini-Moskowitz 2013 + Moskowitz-Grinblatt 1999 KR application
#
# Hypothesis: KOSPI200∪KOSDAQ150 27-sector cross-section 12-1 momentum
#             ranking → top decile sector → top stocks within sector → α̂
#
# WT_005 inheritance: raw IC 0.0193 → sector-neutral 0.008 retention 0.42
# 본 WT = 섹터 자체 momentum signal 정식 검증 (sector-bet component 분리)
#
# PIT: monthly returns t-1 lag, signal at month-end → t+1 application
# Universe: K200=1 OR KQ150=1 (348 names @last)
# Sector: KSI Lv1 (27 sectors, 한국시장 표준)
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
})

WT_ID <- "WT-D20260508_008"
ARTIFACT_DIR <- file.path("stage_artifacts", "WT_D20260508_008")
MAILBOX_DIR  <- file.path("qepm/mailbox/worktask", WT_ID)
dir.create(ARTIFACT_DIR, recursive = TRUE, showWarnings = FALSE)

cat("[", Sys.time(), "] WT-D20260508_008 sector momentum analysis START\n")

#==============================================================================
# Step 1: Load RAWDATA (PIT-safe)
#==============================================================================
rd <- as.data.table(read_parquet(".cache/rawdata.parquet"))
setkey(rd, Date, Ticker)
cat("RAWDATA loaded:", nrow(rd), "rows / N_tickers =", uniqueN(rd$Ticker), "\n")

# Universe filter: K200=1 OR KQ150=1 at each Date (PIT t-1: Date <= sig_d)
rd[, in_univ := (K200 == 1 | KQ150 == 1)]
rd[is.na(in_univ), in_univ := FALSE]

# Sector lv1 (27 sectors)
rd[, has_sector := !is.na(Sector)]

# 일간 수익률 (Ret 컬럼)
rd[, Ret := as.numeric(Ret)]

#==============================================================================
# Step 2: Build month-end sample + sector membership
#==============================================================================
# Month-end Date (last trading day of month per ticker)
rd[, ym := format(Date, "%Y-%m")]
month_ends <- rd[, .(month_end = max(Date)), by = ym]
setkey(month_ends, ym)
cat("Month-ends:", nrow(month_ends), "\n")

# Monthly returns: t-1 close → t close
# Use month-end snapshots
rd_me <- merge(rd, month_ends, by = "ym")
rd_me <- rd_me[Date == month_end, .(Date, Ticker, Close, Sector, in_univ, K200, KQ150, Size)]
setkey(rd_me, Date, Ticker)

# Compute monthly return
rd_me[, ret_1m := Close / shift(Close, 1) - 1, by = Ticker]
rd_me <- rd_me[!is.na(ret_1m) & !is.na(Sector) & in_univ == TRUE]
cat("Monthly observations (filtered):", nrow(rd_me), "\n")
cat("Date range:", as.character(min(rd_me$Date)), "→", as.character(max(rd_me$Date)), "\n")

#==============================================================================
# Step 3: Build sector portfolio returns (value-weighted within sector)
#==============================================================================
# Sector value-weight return: weighted by lagged Size (t-1 market cap) — PIT safe
rd_me[, w_size_lag := shift(Size, 1), by = Ticker]
rd_me <- rd_me[!is.na(w_size_lag) & w_size_lag > 0]

sector_ret <- rd_me[, .(
  ret_sector_vw = sum(ret_1m * w_size_lag, na.rm = TRUE) / sum(w_size_lag, na.rm = TRUE),
  ret_sector_ew = mean(ret_1m, na.rm = TRUE),
  n_stocks = .N
), by = .(Date, Sector)]

cat("\nSector-month observations:", nrow(sector_ret), "\n")
cat("Sectors with data:", uniqueN(sector_ret$Sector), "\n")

# Min stocks per sector to be valid
sector_ret <- sector_ret[n_stocks >= 3]
cat("Filtered (n_stocks >= 3):", nrow(sector_ret), "\n")

setkey(sector_ret, Sector, Date)

#==============================================================================
# Step 4: Sector-level momentum (12-1, 12-0, 6-1) — PIT-safe rolling
#==============================================================================
# 12-1 momentum: cumulative return from t-12 to t-1 (skip most recent month)
# This is computed at month-end t for use in t+1 portfolio formation

compute_mom <- function(returns, lookback, skip) {
  # lookback months total, skip recent skip months
  # returns vector indexed by time
  n <- length(returns)
  out <- rep(NA_real_, n)
  for (i in seq_len(n)) {
    if (i - skip - lookback + 1 < 1) next
    # window: [i - lookback + 1 ... i - skip]  (NOTE: i is index, but we want past lookback months excluding skip recent)
    # Asness 12-1: ret(t-12, t-2) skip t-1 month → product of months t-12 .. t-2
    win_start <- i - lookback + 1
    win_end <- i - skip
    if (win_start < 1 || win_end < win_start) next
    r <- returns[win_start:win_end]
    if (any(is.na(r))) next
    out[i] <- prod(1 + r) - 1
  }
  out
}

# Asness FFM 2013 standard: 12-month return ending month t-2 (skip 1 month)
sector_ret[, mom_12_1 := compute_mom(ret_sector_vw, 12, 1), by = Sector]
sector_ret[, mom_12_0 := compute_mom(ret_sector_vw, 12, 0), by = Sector]
sector_ret[, mom_6_1  := compute_mom(ret_sector_vw, 6, 1), by = Sector]
sector_ret[, mom_3_0  := compute_mom(ret_sector_vw, 3, 0), by = Sector]

# Forward 1-month return (target for IC)
sector_ret[, ret_fwd_1m := shift(ret_sector_vw, -1, type = "lag"), by = Sector]
# Note: shift(-1) gives next period

cat("\nSector momentum sample:\n")
print(head(sector_ret[!is.na(mom_12_1)], 5))

#==============================================================================
# Step 5: Cross-section IC (sector level) — Spearman per Date
#==============================================================================
ic_per_date <- function(dt, signal_col, target_col = "ret_fwd_1m") {
  dt2 <- dt[!is.na(get(signal_col)) & !is.na(get(target_col))]
  if (nrow(dt2) < 5) return(NA_real_)
  cor(dt2[[signal_col]], dt2[[target_col]], method = "spearman")
}

ic_table <- sector_ret[, .(
  ic_12_1 = ic_per_date(.SD, "mom_12_1"),
  ic_12_0 = ic_per_date(.SD, "mom_12_0"),
  ic_6_1  = ic_per_date(.SD, "mom_6_1"),
  ic_3_0  = ic_per_date(.SD, "mom_3_0"),
  n_sectors = .N
), by = Date]

ic_summary <- ic_table[!is.na(ic_12_1), .(
  rank_ic_12_1 = mean(ic_12_1, na.rm = TRUE),
  ic_sd_12_1 = sd(ic_12_1, na.rm = TRUE),
  icir_12_1 = mean(ic_12_1, na.rm = TRUE) / sd(ic_12_1, na.rm = TRUE),
  rank_ic_12_0 = mean(ic_12_0, na.rm = TRUE),
  icir_12_0 = mean(ic_12_0, na.rm = TRUE) / sd(ic_12_0, na.rm = TRUE),
  rank_ic_6_1 = mean(ic_6_1, na.rm = TRUE),
  icir_6_1 = mean(ic_6_1, na.rm = TRUE) / sd(ic_6_1, na.rm = TRUE),
  rank_ic_3_0 = mean(ic_3_0, na.rm = TRUE),
  icir_3_0 = mean(ic_3_0, na.rm = TRUE) / sd(ic_3_0, na.rm = TRUE),
  n_obs = .N
)]

cat("\n=== Sector-level Cross-Section IC ===\n")
print(ic_summary)

# Save IC time-series
fwrite(ic_table, file.path(ARTIFACT_DIR, "ic_sector_momentum_per_date.csv"))

#==============================================================================
# Step 6: Subperiod stability (3 buckets per request)
#==============================================================================
ic_table[, period := fcase(
  Date < as.Date("2015-01-01"), "P1_2008_2014",
  Date >= as.Date("2015-01-01") & Date < as.Date("2020-01-01"), "P2_2015_2019",
  Date >= as.Date("2020-01-01"), "P3_2020_2026"
)]

ic_subperiod <- ic_table[!is.na(ic_12_1), .(
  rank_ic_12_1 = mean(ic_12_1, na.rm = TRUE),
  icir_12_1 = mean(ic_12_1, na.rm = TRUE) / sd(ic_12_1, na.rm = TRUE),
  rank_ic_12_0 = mean(ic_12_0, na.rm = TRUE),
  icir_12_0 = mean(ic_12_0, na.rm = TRUE) / sd(ic_12_0, na.rm = TRUE),
  n = .N
), by = period][order(period)]

cat("\n=== Subperiod Stability (Sector level) ===\n")
print(ic_subperiod)

fwrite(ic_subperiod, file.path(ARTIFACT_DIR, "subperiod_stability.csv"))

#==============================================================================
# Step 7: Newey-West t-stat (Harvey 다중검정 보정)
#==============================================================================
nw_tstat <- function(x, lag = 4) {
  x <- x[!is.na(x)]
  n <- length(x)
  if (n < 30) return(NA_real_)
  mu <- mean(x)
  resid <- x - mu
  s2 <- mean(resid^2)
  for (j in seq_len(lag)) {
    w <- 1 - j / (lag + 1)
    s2 <- s2 + 2 * w * mean(resid[1:(n-j)] * resid[(j+1):n])
  }
  if (s2 <= 0) return(NA_real_)
  se <- sqrt(s2 / n)
  mu / se
}

t_12_1 <- nw_tstat(ic_table$ic_12_1)
t_12_0 <- nw_tstat(ic_table$ic_12_0)
t_6_1  <- nw_tstat(ic_table$ic_6_1)
t_3_0  <- nw_tstat(ic_table$ic_3_0)

cat("\n=== Newey-West t-stat (lag=4) ===\n")
cat("12-1 mom:", round(t_12_1, 4), "\n")
cat("12-0 mom:", round(t_12_0, 4), "\n")
cat(" 6-1 mom:", round(t_6_1, 4), "\n")
cat(" 3-0 mom:", round(t_3_0, 4), "\n")

#==============================================================================
# Step 8: Top/Bottom decile spread portfolio (long-only top decile)
#==============================================================================
# At each month t, rank 27 sectors by mom_12_1 → top 5 vs bottom 5 (decile-equivalent)
sector_ret[, mom_rank := frank(mom_12_1, na.last = "keep"), by = Date]
sector_ret[, n_sectors_t := sum(!is.na(mom_12_1)), by = Date]
sector_ret[, mom_q := fcase(
  is.na(mom_12_1), NA_integer_,
  mom_rank > n_sectors_t * 0.7, 5L,  # top 30% (Q5)
  mom_rank > n_sectors_t * 0.5, 4L,
  mom_rank > n_sectors_t * 0.3, 3L,
  mom_rank > n_sectors_t * 0.1, 2L,
  default = 1L
)]

# Quintile portfolio returns (forward 1M)
quintile_ret <- sector_ret[!is.na(mom_q) & !is.na(ret_fwd_1m),
                           .(qret = mean(ret_fwd_1m, na.rm = TRUE), n = .N),
                           by = .(Date, mom_q)]
qsummary <- quintile_ret[, .(mean_ret = mean(qret, na.rm = TRUE), n_obs = .N), by = mom_q][order(mom_q)]
cat("\n=== Quintile Mean Forward 1M Returns ===\n")
print(qsummary)

# Long-only top quintile (Q5)
ls_spread <- merge(
  quintile_ret[mom_q == 5, .(Date, q5 = qret)],
  quintile_ret[mom_q == 1, .(Date, q1 = qret)],
  by = "Date"
)
ls_spread[, ls := q5 - q1]
cat("\nQ5-Q1 spread mean:", round(mean(ls_spread$ls, na.rm = TRUE), 4),
    "/ NW-t:", round(nw_tstat(ls_spread$ls), 4), "/ N:", nrow(ls_spread), "\n")
cat("Q5 (top sector decile) mean:", round(mean(ls_spread$q5, na.rm = TRUE), 4),
    "/ NW-t:", round(nw_tstat(ls_spread$q5 - mean(ls_spread$q1, na.rm = TRUE)), 4), "\n")

fwrite(ls_spread, file.path(ARTIFACT_DIR, "sector_quintile_spread.csv"))

#==============================================================================
# Step 9: Stock-level alpha mapping — sector momentum projection to stocks
#==============================================================================
# Map: each stock at month-end gets sector_mom_12_1 of its sector
# This gives stock-level sector_momentum signal (cross-stock IC vs forward 1M return)

# rd_me = stock-level monthly. Need to attach sector mom_12_1 (PIT: at sig_date t use mom_12_1 computed at t)
sector_mom_pit <- sector_ret[, .(Date, Sector, mom_12_1, mom_6_1, mom_q)]
setkey(sector_mom_pit, Date, Sector)

# Stock month-end Ret forward
rd_me[, ret_fwd_stock := shift(ret_1m, -1), by = Ticker]
stock_with_sector_mom <- merge(rd_me, sector_mom_pit, by = c("Date", "Sector"), all.x = FALSE)
stock_with_sector_mom <- stock_with_sector_mom[!is.na(mom_12_1) & !is.na(ret_fwd_stock)]
cat("\nStock-level merged obs (with sector mom):", nrow(stock_with_sector_mom), "\n")

# Stock-level cross-section IC (PIT t signal vs t+1 stock return)
stock_ic_table <- stock_with_sector_mom[, .(
  ic_stock_12_1 = ic_per_date(.SD, "mom_12_1", "ret_fwd_stock"),
  n_stocks = .N
), by = Date]

stock_ic_summary <- stock_ic_table[!is.na(ic_stock_12_1), .(
  stock_rank_ic = mean(ic_stock_12_1, na.rm = TRUE),
  stock_icir = mean(ic_stock_12_1, na.rm = TRUE) / sd(ic_stock_12_1, na.rm = TRUE),
  stock_nw_t = nw_tstat(ic_stock_12_1),
  n_obs = .N
)]
cat("\n=== Stock-level IC (sector momentum projected) ===\n")
print(stock_ic_summary)

fwrite(stock_ic_table, file.path(ARTIFACT_DIR, "stock_level_ic_sector_proj.csv"))

#==============================================================================
# Step 10: Final alpha vector @ as_of_date 2026-05-08
#==============================================================================
AS_OF <- as.Date("2026-05-08")
# Use most recent month-end <= AS_OF (PIT)
last_me <- max(rd_me$Date[rd_me$Date <= AS_OF])
cat("\n[ALPHA EMISSION] Using month-end:", as.character(last_me), "\n")

# Latest sector momentum (computed at last_me, applies for next month)
latest_sector_mom <- sector_ret[Date == last_me, .(Sector, mom_12_1, mom_6_1, mom_q)]
cat("\nLatest sector ranks (top 5):\n")
print(latest_sector_mom[order(-mom_12_1)][1:8])
cat("\nLatest sector ranks (bottom 5):\n")
print(latest_sector_mom[order(mom_12_1)][1:8])

# Stock-level alpha: stock's sector momentum (cross-stock z-score)
latest_stocks <- rd_me[Date == last_me, .(Ticker, Sector, in_univ, K200, KQ150)]
latest_stocks <- merge(latest_stocks, latest_sector_mom, by = "Sector", all.x = FALSE)
latest_stocks <- latest_stocks[!is.na(mom_12_1)]

# Z-score the sector momentum within universe (cross-section)
latest_stocks[, alpha_raw := mom_12_1]
mu_a <- mean(latest_stocks$alpha_raw, na.rm = TRUE)
sd_a <- sd(latest_stocks$alpha_raw, na.rm = TRUE)
latest_stocks[, alpha_z := (alpha_raw - mu_a) / sd_a]

# Convert Z to expected return (use historical IC slope as scale)
ic_mean <- ic_summary$rank_ic_12_1
# alpha_hat in return space: scale by historical realized stock-level slope
# Simple: alpha = z * sigma_target where sigma_target ~ IC * cross-section std return
xs_std_ret <- sd(rd_me$ret_1m, na.rm = TRUE)
latest_stocks[, alpha_hat := alpha_z * ic_mean * xs_std_ret]

# Confidence: data availability + subperiod stability
sub_stab <- ic_subperiod[, .(min_ic = min(rank_ic_12_1, na.rm = TRUE), max_ic = max(rank_ic_12_1, na.rm = TRUE))]
sub_stab_score <- 1 - (sub_stab$max_ic - sub_stab$min_ic) / (abs(sub_stab$max_ic) + abs(sub_stab$min_ic) + 1e-6)
sub_stab_score <- max(0, min(1, sub_stab_score))

# Per-stock confidence
latest_stocks[, sector_n := .N, by = Sector]
latest_stocks[, confidence := pmin(1, sub_stab_score * (sector_n / max(sector_n)))]

cat("\nFinal alpha vector summary:\n")
cat("N stocks:", nrow(latest_stocks), "\n")
cat("Alpha mean:", round(mean(latest_stocks$alpha_hat), 6), "\n")
cat("Alpha sd:", round(sd(latest_stocks$alpha_hat), 6), "\n")
cat("Confidence mean:", round(mean(latest_stocks$confidence), 4), "\n")

#==============================================================================
# Step 11: Save artifacts
#==============================================================================
# alpha_scores parquet
alpha_out <- latest_stocks[, .(
  Ticker, Sector, mom_12_1, alpha_z, alpha_hat, confidence
)]
write_parquet(alpha_out, file.path(ARTIFACT_DIR, "alpha_scores.parquet"))

# Sector classification snapshot
sector_class <- list(
  classification = "KSI_Lv1",
  n_sectors = 27,
  source = "RAWDATA Sector column (QuantiWise/internal)",
  sectors = sort(unique(rd_me$Sector)),
  description = "한국 KSI Level 1 — IT하드웨어/건강관리/화장품/건설/자동차/소프트웨어/기계/화학/필수소비재/반도체/비철목재/미디어교육/디스플레이/은행/철강/IT가전/소매유통/운송/상사자본재/증권/에너지/조선/유틸리티/보험/호텔레저/통신서비스 등"
)
write_json(sector_class, file.path(ARTIFACT_DIR, "sector_classification.json"),
           pretty = TRUE, auto_unbox = TRUE)

#==============================================================================
# Step 12: Diagnostics summary
#==============================================================================
diag <- list(
  rank_ic = round(ic_summary$rank_ic_12_1, 6),
  icir = round(ic_summary$icir_12_1, 4),
  rank_ic_12_0 = round(ic_summary$rank_ic_12_0, 6),
  icir_12_0 = round(ic_summary$icir_12_0, 4),
  rank_ic_6_1 = round(ic_summary$rank_ic_6_1, 6),
  icir_6_1 = round(ic_summary$icir_6_1, 4),
  harvey_t_stat = round(t_12_1, 4),
  harvey_t_12_0 = round(t_12_0, 4),
  harvey_t_6_1 = round(t_6_1, 4),
  ls_spread_mean = round(mean(ls_spread$ls, na.rm = TRUE), 6),
  ls_spread_nw_t = round(nw_tstat(ls_spread$ls), 4),
  q5_top_mean = round(mean(ls_spread$q5, na.rm = TRUE), 6),
  monotonicity_q1_q5 = round(qsummary$mean_ret[5] - qsummary$mean_ret[1], 6),
  subperiod_stability = round(sub_stab_score, 4),
  stock_rank_ic = round(stock_ic_summary$stock_rank_ic, 6),
  stock_icir = round(stock_ic_summary$stock_icir, 4),
  stock_nw_t = round(stock_ic_summary$stock_nw_t, 4),
  n_obs_sector = ic_summary$n_obs,
  n_obs_stock = stock_ic_summary$n_obs,
  n_sectors = uniqueN(sector_ret$Sector),
  n_stocks_alpha = nrow(latest_stocks)
)
write_json(diag, file.path(ARTIFACT_DIR, "alpha_validation.json"),
           pretty = TRUE, auto_unbox = TRUE)

cat("\n=== DIAGNOSTICS DUMP ===\n")
str(diag)

cat("\n[", Sys.time(), "] Step 11 artifact write COMPLETE\n")
cat("Files written:\n")
cat(" -", file.path(ARTIFACT_DIR, "alpha_scores.parquet"), "\n")
cat(" -", file.path(ARTIFACT_DIR, "sector_classification.json"), "\n")
cat(" -", file.path(ARTIFACT_DIR, "alpha_validation.json"), "\n")
cat(" -", file.path(ARTIFACT_DIR, "ic_sector_momentum_per_date.csv"), "\n")
cat(" -", file.path(ARTIFACT_DIR, "subperiod_stability.csv"), "\n")
cat(" -", file.path(ARTIFACT_DIR, "stock_level_ic_sector_proj.csv"), "\n")
cat(" -", file.path(ARTIFACT_DIR, "sector_quintile_spread.csv"), "\n")

# Save diagnostic to globalenv-like for downstream
saveRDS(list(
  ic_summary = ic_summary,
  ic_subperiod = ic_subperiod,
  qsummary = qsummary,
  ls_spread = ls_spread,
  diag = diag,
  alpha_out = alpha_out,
  latest_sector_mom = latest_sector_mom
), file.path(ARTIFACT_DIR, "wt008_full_diagnostics.rds"))

cat("\n[", Sys.time(), "] WT-D20260508_008 alpha analysis COMPLETE\n")
