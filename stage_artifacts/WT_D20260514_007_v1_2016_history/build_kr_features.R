#!/usr/bin/env Rscript
# WT-D20260514_007 KR Internal Data + Academic Novel Method Feature Engineering
# Mandate (도훈 정정 2026-05-14): MCP/API = paper search only; KR internal data + 학술 새 method
#
# 5 ex-ante candidates (AX-002 strict grid N=5):
# F1: Realized Skewness Dispersion (Babiak-Barunik-Kurka arXiv:2604.07870 2026)
# F2: Idiosyncratic Vol Decomposition (Kalnina-Tewou arXiv:2408.13437 2024)
# F3: Macro β Sensitivity (KR equity × FRED rolling 36m monthly)
# F4: KR Sector × US Term Spread Conditional Momentum
# F5: DART Disclosure Velocity (Cohen-Malloy-Nguyen 2020 adapted, numeric metadata only)
#
# PIT C1-C15 strict:
# - C1 rolling/expanding only
# - C2 t-1 lag (monthly sig_dates use up to month-end close)
# - C4 fundamental quarterly 45d lag (DART rcept_dt + 45d)
# - C9 vol/skew lag (use t-1 month data)
# - C11 FRED macro 1d/1m lag
# - C14 IC Usable_Date <= sig_date

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(future); library(future.apply)
})

WT_ID <- "WT-D20260514_007"
STAGE <- file.path("stage_artifacts", "WT_D20260514_007")
dir.create(STAGE, showWarnings=FALSE, recursive=TRUE)

cat("====================================\n")
cat("[WT-D20260514_007] KR Internal Data + Academic Novel Method\n")
cat("====================================\n\n")

# ===== Step 1: Load infrastructure =====
cat("[1/8] Loading infrastructure...\n")
rawdata <- as.data.table(read_parquet(".cache/rawdata.parquet"))
setkey(rawdata, Date, Ticker)

macro_fred <- as.data.table(read_parquet(".cache/macro_fred.parquet"))

dart_q <- as.data.table(read_parquet(".cache/dart/dart_raw_quarterly.parquet"))
dart_q[, disclosure_date := as.Date(substr(rcept_no, 1, 8), format="%Y%m%d")]

cat("  RAWDATA:", nrow(rawdata), "rows,", uniqueN(rawdata$Ticker), "tickers\n")
cat("  FRED:", uniqueN(macro_fred$Series), "series\n")
cat("  DART quarterly:", uniqueN(dart_q$rcept_no), "unique disclosures\n")

# ===== Step 2: Universe panel build (vectorized) =====
cat("\n[2/8] Universe panel build (vectorized)...\n")
sig_dates_all <- rawdata[, .(d_max = max(Date)), by = .(YM = format(Date, "%Y-%m"))][order(d_max)]$d_max
sig_dates <- sig_dates_all[sig_dates_all >= as.Date("2010-01-01") & sig_dates_all <= as.Date("2026-04-30")]
cat("  sig_dates:", length(sig_dates), "monthly observations\n")

rawdata[, ADV_won := Close * Vol]
adv_d <- rawdata[Market %in% c("KOSPI", "KOSDAQ") & !is.na(ADV_won) & !is.na(Sector_Lv2),
                  .(Date, Ticker, ADV_won, Sector_Lv2)]
setkey(adv_d, Ticker, Date)
adv_d[, ADV_20d := frollmean(ADV_won, 20L, align="right", fill=NA), by=Ticker]

universe_panel <- list()
for (sd in sig_dates) {
  snap <- adv_d[Date == sd & ADV_20d >= 2e8 & !is.na(Sector_Lv2),
                 .(Ticker, ADV_20d, Sector_Lv2)]
  universe_panel[[as.character(sd)]] <- snap
}
n_univ <- sapply(universe_panel, nrow)
cat("  Universe: mean", round(mean(n_univ)), "median", median(n_univ),
    "range", min(n_univ), "->", max(n_univ), "\n")
saveRDS(universe_panel, file.path(STAGE, "universe_panel.rds"))
universe_all <- unique(unlist(lapply(universe_panel, function(x) x$Ticker)))
cat("  Universe (all sig_dates):", length(universe_all), "unique tickers\n")

# ===== Step 3: Monthly returns panel =====
cat("\n[3/8] Monthly returns panel...\n")
ret_d <- rawdata[!is.na(Close) & Market %in% c("KOSPI", "KOSDAQ"),
                 .(Date, Ticker, Close, Ret, Sector_Lv2, BM_Ret)]
ret_d[, YM := format(Date, "%Y-%m")]
ret_m <- ret_d[, .(Date = max(Date), Close = last(Close),
                    Sector_Lv2 = last(Sector_Lv2)), by=.(Ticker, YM)]
setorder(ret_m, Ticker, Date)
ret_m[, Ret_1m := Close / shift(Close, 1L, type="lag") - 1, by=Ticker]
ret_m <- ret_m[Date %in% sig_dates & Ticker %in% universe_all, ]
ret_m[, Ret_1m_fwd := shift(Ret_1m, 1L, type="lead"), by=Ticker]
cat("  ret_m rows:", nrow(ret_m), "\n")
write_parquet(ret_m, file.path(STAGE, "returns_monthly_panel.parquet"))

# ===== Step 4: F1 — Realized Skewness Dispersion (Babiak-Barunik-Kurka 2026) =====
# Method: For each ticker and each month, compute realized skewness over 21 trading days
# of daily returns. Cross-section monthly Z-score → dispersion signal.
# Hypothesis: Higher firm-level realized skewness → lower future returns
# (Babiak-Barunik-Kurka 2026: monetary policy announcements drive this)
cat("\n[4/8] F1: Realized Skewness Dispersion (arXiv:2604.07870)...\n")
ret_daily <- rawdata[!is.na(Ret) & Market %in% c("KOSPI", "KOSDAQ") & Ticker %in% universe_all,
                      .(Date, Ticker, Ret)]
ret_daily[, YM := format(Date, "%Y-%m")]
setorder(ret_daily, Ticker, Date)

# Monthly realized skewness per ticker
realized_moments <- ret_daily[, .(
  n_obs = .N,
  rv_skew = if (.N >= 15) {
    (sum((Ret - mean(Ret, na.rm=TRUE))^3, na.rm=TRUE) / .N) /
      (sum((Ret - mean(Ret, na.rm=TRUE))^2, na.rm=TRUE) / .N)^(3/2)
  } else NA_real_,
  rv_var = if (.N >= 15) var(Ret, na.rm=TRUE) else NA_real_,
  rv_kurt = if (.N >= 15) {
    (sum((Ret - mean(Ret, na.rm=TRUE))^4, na.rm=TRUE) / .N) /
      (sum((Ret - mean(Ret, na.rm=TRUE))^2, na.rm=TRUE) / .N)^2
  } else NA_real_,
  Date = max(Date)
), by=.(Ticker, YM)]
realized_moments <- realized_moments[Date %in% sig_dates & !is.na(rv_skew), ]
cat("  realized_moments rows:", nrow(realized_moments), "\n")

# PIT C9 lag: use t-1 month signal at sig_date t
setorder(realized_moments, Ticker, Date)
realized_moments[, rv_skew_lag := shift(rv_skew, 1L, type="lag"), by=Ticker]
realized_moments[, rv_var_lag := shift(rv_var, 1L, type="lag"), by=Ticker]
realized_moments[, rv_kurt_lag := shift(rv_kurt, 1L, type="lag"), by=Ticker]

f1_panel <- realized_moments[!is.na(rv_skew_lag), .(Date, Ticker, rv_skew_lag, rv_var_lag, rv_kurt_lag)]
# Cross-section z-score within Date
f1_panel[, rv_skew_z := scale(rv_skew_lag), by=Date]
f1_panel[, rv_var_z := scale(rv_var_lag), by=Date]
cat("  F1 panel:", nrow(f1_panel), "obs\n")
write_parquet(f1_panel, file.path(STAGE, "f1_realized_skewness_panel.parquet"))

# ===== Step 5: F2 — Idiosyncratic Vol Decomposition (Kalnina-Tewou 2024) =====
# Method: Decompose idio_vol into (a) systematic factor (market vol)-related component
# and (b) residual (non-systematic) component.
# Steps:
#   1. Per ticker, monthly idio_vol = std(Ret - α_i - β_i * BM_Ret) over 252d window (PIT-safe)
#   2. Regress idio_vol (time series) on KOSPI BM_vol (market vol) over 36m window
#   3. Component A = β * BM_vol (systematic)
#   4. Component B = idio_vol - Component A (residual, non-systematic)
#   5. Cross-section z-score of Component B → alpha signal
# Hypothesis: Residual (non-systematic) idio_vol = cleaner anomaly signal
# (after stripping market vol-driven component)
cat("\n[5/8] F2: Idiosyncratic Vol Decomposition (arXiv:2408.13437)...\n")

# Step 5a: Get daily ticker returns + BM_Ret
ret_with_bm <- rawdata[!is.na(Ret) & !is.na(BM_Ret) &
                        Market %in% c("KOSPI", "KOSDAQ") & Ticker %in% universe_all,
                        .(Date, Ticker, Ret, BM_Ret)]
setorder(ret_with_bm, Ticker, Date)

# Step 5b: Per-ticker rolling 252d β + idio residual std
n_workers <- min(6L, parallel::detectCores() - 1L)
plan(multisession, workers = n_workers)
cat("  F2 workers:", n_workers, "\n")

compute_idio_vol <- function(tk_data) {
  # 252d rolling β and idio vol (std of residuals)
  n <- nrow(tk_data)
  if (n < 252) return(data.table())
  out <- data.table()
  # Process each month-end
  month_end_idx <- which(format(tk_data$Date, "%Y-%m") != shift(format(tk_data$Date, "%Y-%m"), -1L))
  for (i in month_end_idx) {
    if (i < 252) next
    w <- tk_data[(i-251):i, ]
    if (nrow(w) < 100) next
    fit <- tryCatch(lm(Ret ~ BM_Ret, data = w), error = function(e) NULL)
    if (is.null(fit)) next
    resid_std <- sd(residuals(fit), na.rm=TRUE)
    bm_vol <- sd(w$BM_Ret, na.rm=TRUE)
    beta_mkt <- coef(fit)["BM_Ret"]
    out <- rbind(out, data.table(Date = tk_data$Date[i],
                                  idio_vol_raw = resid_std * sqrt(252),  # annualized
                                  bm_vol_local = bm_vol * sqrt(252),
                                  beta_mkt = beta_mkt))
  }
  return(out)
}

# Parallelize per ticker
tickers_f2 <- universe_all
f2_results <- future_lapply(tickers_f2, function(tk) {
  tk_data <- ret_with_bm[Ticker == tk, ]
  res <- compute_idio_vol(tk_data)
  if (nrow(res) > 0) res[, Ticker := tk]
  return(res)
}, future.seed = TRUE)
plan(sequential)

f2_idio_panel <- rbindlist(f2_results)
cat("  f2_idio_panel rows:", nrow(f2_idio_panel), "\n")

# Step 5c: For each ticker, regress idio_vol_raw on bm_vol_local over 36m rolling window
# Residual = Component B (non-systematic idio vol)
# F2 fix: month-level YM match (exact Date %in% sig_dates 0 obs issue)
f2_idio_panel[, YM := format(Date, "%Y-%m")]
sig_ym <- format(sig_dates, "%Y-%m")
f2_idio_panel <- f2_idio_panel[YM %in% sig_ym, ]
# Keep last day per (Ticker, YM) — monthly aggregate
setorder(f2_idio_panel, Ticker, Date)
f2_idio_panel <- f2_idio_panel[, .SD[.N], by = .(Ticker, YM)]
setorder(f2_idio_panel, Ticker, Date)

# F2 fix v3: per-ticker simple cross-section decomposition (no rolling regression)
# Decomp via per-Date cross-section: idio_vol_residual = idio_vol_raw - β_xs * bm_vol_local
# (cross-section reg per sig_date, then residual = non-systematic component)
cat("  pre-decomp f2_idio_panel rows:", nrow(f2_idio_panel),
    "| unique tickers:", uniqueN(f2_idio_panel$Ticker),
    "| tickers with 12+ months:", uniqueN(f2_idio_panel[, .N, by=Ticker][N >= 12]$Ticker), "\n")

f2_idio_panel[, idio_vol_residual := {
  if (.N < 5L) {
    rep(NA_real_, .N)
  } else {
    fit <- tryCatch(lm(idio_vol_raw ~ bm_vol_local), error = function(e) NULL)
    if (is.null(fit)) rep(NA_real_, .N) else as.numeric(residuals(fit))
  }
}, by=Date]

cat("  decomp residuals non-NA count:", sum(!is.na(f2_idio_panel$idio_vol_residual)), "\n")

f2_panel <- f2_idio_panel[!is.na(idio_vol_residual), .(Date, Ticker, idio_vol_raw, idio_vol_residual, bm_vol_local, beta_mkt)]
# Lag 1 month (PIT C9)
setorder(f2_panel, Ticker, Date)
f2_panel[, idio_vol_residual_lag := shift(idio_vol_residual, 1L, type="lag"), by=Ticker]
f2_panel[, idio_vol_raw_lag := shift(idio_vol_raw, 1L, type="lag"), by=Ticker]
f2_panel <- f2_panel[!is.na(idio_vol_residual_lag), ]
# Cross-section z-score
f2_panel[, idio_vol_residual_z := as.numeric(scale(idio_vol_residual_lag)), by=Date]
f2_panel[, idio_vol_raw_z := as.numeric(scale(idio_vol_raw_lag)), by=Date]
cat("  F2 panel:", nrow(f2_panel), "obs\n")
write_parquet(f2_panel, file.path(STAGE, "f2_idio_vol_decomp_panel.parquet"))

# ===== Step 6: F3 — Macro β Sensitivity (FRED × KR equity monthly 36m) =====
cat("\n[6/8] F3: Macro β Sensitivity (FRED rolling 36m)...\n")

# Monthly FRED panel
fred_keep <- c("VIX", "US_10Y_Yield", "Term_Spread", "Breakeven_Infl", "KRW_USD")
fred_d <- macro_fred[Series %in% fred_keep, ]
fred_d[, YM := format(Date, "%Y-%m")]
fred_m <- fred_d[, .(Value = last(Value)), by=.(YM, Series)]
fred_m_wide <- dcast(fred_m, YM ~ Series, value.var = "Value")
ym_to_date <- data.table(YM = format(sig_dates, "%Y-%m"), sig_date = sig_dates)
fred_m_wide <- merge(fred_m_wide, ym_to_date, by="YM", all.y=TRUE)
setorder(fred_m_wide, sig_date)
fred_m_wide[, dVIX := VIX - shift(VIX, 1L)]
fred_m_wide[, dUS10Y := US_10Y_Yield - shift(US_10Y_Yield, 1L)]
fred_m_wide[, dTS := Term_Spread - shift(Term_Spread, 1L)]
fred_m_wide[, dKRW := log(KRW_USD) - log(shift(KRW_USD, 1L))]

# PIT C11: lag 1 month
fred_m_lag <- fred_m_wide[, .(sig_date, dVIX_lag1 = shift(dVIX, 1L, type="lag"),
                                dUS10Y_lag1 = shift(dUS10Y, 1L, type="lag"),
                                dTS_lag1 = shift(dTS, 1L, type="lag"),
                                dKRW_lag1 = shift(dKRW, 1L, type="lag"))]

ret_macro <- merge(ret_m[, .(Date, Ticker, Ret_1m)],
                    fred_m_lag, by.x="Date", by.y="sig_date", all.x=TRUE)
ret_macro <- ret_macro[!is.na(Ret_1m) & !is.na(dVIX_lag1), ]
setorder(ret_macro, Ticker, Date)

n_workers <- min(6L, parallel::detectCores() - 1L)
plan(multisession, workers = n_workers)
cat("  F3 workers:", n_workers, "\n")

# Per-ticker × per-sig_date 36m rolling OLS β
compute_f3 <- function(tk) {
  td <- ret_macro[Ticker == tk, ]
  n <- nrow(td)
  if (n < 24) return(data.table())
  out <- data.table()
  setorder(td, Date)
  for (i in 24:n) {
    w <- td[max(1, i-35):i, ]
    fit <- tryCatch(lm(Ret_1m ~ dVIX_lag1 + dTS_lag1 + dKRW_lag1, data = w),
                    error = function(e) NULL)
    if (is.null(fit)) next
    cc <- coef(fit)
    out <- rbind(out, data.table(Date = td$Date[i],
                                  beta_VIX = unname(cc["dVIX_lag1"]),
                                  beta_TS = unname(cc["dTS_lag1"]),
                                  beta_USD = unname(cc["dKRW_lag1"])))
  }
  if (nrow(out) > 0) out[, Ticker := tk]
  return(out)
}

f3_results <- future_lapply(universe_all, compute_f3, future.seed = TRUE)
plan(sequential)
f3_panel <- rbindlist(f3_results)
f3_panel <- f3_panel[Date %in% sig_dates & !is.na(beta_VIX), ]
# Lag 1m
setorder(f3_panel, Ticker, Date)
f3_panel[, beta_VIX_lag := shift(beta_VIX, 1L, type="lag"), by=Ticker]
f3_panel[, beta_TS_lag := shift(beta_TS, 1L, type="lag"), by=Ticker]
f3_panel[, beta_USD_lag := shift(beta_USD, 1L, type="lag"), by=Ticker]
f3_panel <- f3_panel[!is.na(beta_VIX_lag), ]
f3_panel[, beta_VIX_z := scale(beta_VIX_lag), by=Date]
f3_panel[, beta_TS_z := scale(beta_TS_lag), by=Date]
f3_panel[, beta_USD_z := scale(beta_USD_lag), by=Date]
cat("  F3 panel:", nrow(f3_panel), "obs\n")
write_parquet(f3_panel, file.path(STAGE, "f3_macro_beta_panel.parquet"))

# ===== Step 7: F4 — KR Sector × US Term Spread Conditional Momentum =====
cat("\n[7/8] F4: Sector × US Term Spread Conditional...\n")
sector_m <- ret_m[!is.na(Ret_1m) & !is.na(Sector_Lv2) & Ticker %in% universe_all,
                   .(SectorRet = mean(Ret_1m, na.rm=TRUE), n_tk = .N),
                   by=.(Date, Sector_Lv2)]
sector_m <- sector_m[n_tk >= 5, ]
setorder(sector_m, Sector_Lv2, Date)
sector_m[, SectorMom_12m := {
  r <- log(1 + SectorRet)
  cum_r <- frollsum(r, 12L, na.rm=FALSE)
  exp(shift(cum_r, 1L, type="lag")) - 1
}, by=Sector_Lv2]
sector_m[, SectorMom_z := as.numeric(scale(SectorMom_12m)), by=Date]

# US Term Spread regime (PIT)
ts_d <- fred_m_wide[, .(sig_date, Term_Spread)]
setorder(ts_d, sig_date)
ts_d[, TS_mean_expand := frollmean(Term_Spread, 36L, na.rm=TRUE, align="right")]
ts_d[, TS_regime := fifelse(Term_Spread > shift(TS_mean_expand, 1L, type="lag"), 1, -1)]
ts_d <- ts_d[, .(Date = sig_date, TS_regime)]

sector_m <- merge(sector_m, ts_d, by="Date", all.x=TRUE)
sector_m[, f4_signal := SectorMom_z * TS_regime]

ticker_sector_map <- ret_m[!is.na(Sector_Lv2), .(Date, Ticker, Sector_Lv2)]
f4_panel <- merge(ticker_sector_map, sector_m[, .(Date, Sector_Lv2, f4_signal)],
                   by=c("Date", "Sector_Lv2"), all.x=TRUE)
f4_panel <- f4_panel[!is.na(f4_signal), ]
cat("  F4 panel:", nrow(f4_panel), "obs\n")
write_parquet(f4_panel, file.path(STAGE, "f4_sector_macro_panel.parquet"))

# ===== Step 8: F5 — DART Disclosure Velocity (numeric metadata only) =====
cat("\n[8/8] F5: DART Disclosure Velocity...\n")
dart_events <- unique(dart_q[!is.na(disclosure_date) & !is.na(Ticker),
                              .(rcept_no, Ticker, disclosure_date)])
dart_events <- dart_events[Ticker %in% universe_all, ]

compute_disclosure_velocity <- function(sd, dart_dt) {
  cutoff <- sd - 45  # PIT C4: 45d lag
  trail_3m_start <- cutoff - 90
  events_3m <- dart_dt[disclosure_date >= trail_3m_start & disclosure_date <= cutoff, ]
  cnt_3m <- events_3m[, .(disc_count_3m = .N), by=Ticker]
  trail_12m_start <- cutoff - 365
  events_12m <- dart_dt[disclosure_date >= trail_12m_start & disclosure_date <= cutoff, ]
  cnt_12m <- events_12m[, .(disc_count_12m = .N), by=Ticker]
  out <- merge(cnt_3m, cnt_12m, by="Ticker", all=TRUE)
  out[is.na(disc_count_3m), disc_count_3m := 0]
  out[is.na(disc_count_12m), disc_count_12m := 0]
  out[, Date := sd]
  return(out)
}

f5_list <- lapply(sig_dates, compute_disclosure_velocity, dart_dt = dart_events)
f5_panel <- rbindlist(f5_list)
# F5 fix: universe_panel names are numeric chars (days since 1970), use sig_dates[i] directly
univ_dt <- rbindlist(lapply(seq_along(universe_panel), function(i)
                     universe_panel[[i]][, .(Date = sig_dates[i], Ticker)]))
f5_panel <- merge(f5_panel, univ_dt, by=c("Date", "Ticker"), all.y=TRUE)
f5_panel[is.na(disc_count_3m), disc_count_3m := 0]
f5_panel[is.na(disc_count_12m), disc_count_12m := 0]

f5_panel[, disc_3m_z := as.numeric(scale(disc_count_3m)), by=Date]
f5_panel[, disc_12m_z := as.numeric(scale(disc_count_12m)), by=Date]
f5_panel[, disc_velocity := ifelse(disc_count_12m > 0,
                                    (disc_count_3m * 4) / pmax(disc_count_12m, 1),
                                    NA_real_)]
f5_panel[, disc_velocity_z := as.numeric(scale(disc_velocity)), by=Date]
cat("  F5 panel:", nrow(f5_panel), "obs\n")
write_parquet(f5_panel, file.path(STAGE, "f5_disclosure_velocity_panel.parquet"))

cat("\n====================================\n")
cat("All 5 KR internal feature panels built.\n")
cat("====================================\n")
