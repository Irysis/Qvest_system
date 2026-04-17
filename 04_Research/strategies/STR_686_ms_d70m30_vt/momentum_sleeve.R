## ──────────────────────────────────────────────────────────────────────────────
## Momentum Sleeve — 12-1M Cross-Sectional Momentum with Golden Formula Risk
## Score = z(ret_12m - ret_1m) sector-neutral
## Risk: CrossAsset z2.0, DaysInv+CVaR+Rev42d gates, MRS regime
## Ref: Jegadeesh & Titman (1993), Asness et al. (2013)
## ──────────────────────────────────────────────────────────────────────────────
cat("[momentum_sleeve] 12-1M Momentum with GF risk infrastructure...\n")
set.seed(42)

LOOKBACK <- 252L; MIN_OBS <- 200L; VOL_FLOOR_Q <- 0.05
REGIME_SCALE_SOFT <- 0.5; MACRO_HARD_THRESH <- if(exists("MACRO_HARD_THRESH")) MACRO_HARD_THRESH else 40L
BUDDHA_CASH_OUT <- TRUE; COOLDOWN_MONTHS <- 2L
REV_WINDOW <- 42L; REV_EXCLUDE_Q <- 0.05
CVAR_ALPHA <- 0.05
MOM_WINDOW_SHORT <- 21L   # 1-month skip

DART_FACTOR_CACHE <- file.path(CACHE_DIR, "fundamental_dart.parquet")
HAS_DART <- file.exists(DART_FACTOR_CACHE)
if (HAS_DART) {
  FUND_DT <- as.data.table(read_parquet(DART_FACTOR_CACHE))
  setnames(FUND_DT, "bsns_year", "biz_year", skip_absent = TRUE)
  FUND_DT[, Factor_Date := as.Date(Factor_Date)]
}

FRED_LONG <- as.data.table(read_parquet(FRED_MACRO_CACHE))
FRED_LONG[, Date := as.Date(Date)]
FRED_LONG <- FRED_LONG[, .(Value = tail(Value, 1)), by = .(Date, Series)]
FRED_WIDE <- dcast(FRED_LONG, Date ~ Series, value.var = "Value")
setorder(FRED_WIDE, Date)

FRED_WIDE[, TS_z := {
  out <- rep(NA_real_, .N)
  for (j in 756:.N) { vals <- Term_Spread[(j-755):j]; vals <- vals[!is.na(vals)]
    if (length(vals) >= 100) out[j] <- (Term_Spread[j] - mean(vals)) / max(sd(vals), 1e-8) }; out }]
FRED_WIDE[, HY_z := {
  out <- rep(NA_real_, .N)
  for (j in 756:.N) { vals <- HY_Spread[(j-755):j]; vals <- vals[!is.na(vals)]
    if (length(vals) >= 100) out[j] <- (HY_Spread[j] - mean(vals)) / max(sd(vals), 1e-8) }; out }]
FRED_WIDE[, VIX_z := {
  out <- rep(NA_real_, .N)
  for (j in 756:.N) { vals <- VIX[(j-755):j]; vals <- vals[!is.na(vals)]
    if (length(vals) >= 100) out[j] <- (VIX[j] - mean(vals)) / max(sd(vals), 1e-8) }; out }]

FRED_WIDE[, sig_TS  := fifelse(!is.na(TS_z) & TS_z < -2.0, 1L, 0L)]
FRED_WIDE[, sig_HY  := fifelse(!is.na(HY_z) & HY_z > 2.0, 1L, 0L)]
FRED_WIDE[, sig_VIX := fifelse(!is.na(VIX_z) & VIX_z > 2.0, 1L, 0L)]
FRED_WIDE[, n_signals := sig_TS + sig_HY + sig_VIX]
FRED_WIDE[, exposure := fifelse(n_signals >= 2, 0.0, fifelse(n_signals == 1, 0.50, 1.0))]

FRED_WIDE[, YM := format(Date, "%Y-%m")]
fred_monthly <- FRED_WIDE[, .(exposure = tail(exposure[!is.na(exposure)], 1),
                               n_sig = tail(n_signals[!is.na(n_signals)], 1)), by = YM]
setkey(fred_monthly, YM)

macro_regime_dt <- as.data.table(read_parquet(FRED_REGIME_CACHE))
macro_regime_dt[, YM := substr(Date, 1, 7)]; setkey(macro_regime_dt, YM)
setorder(RAWDATA, Ticker, Date)
RAWDATA[, YM := format(Date, "%Y-%m")]
all_signal_dates <- RAWDATA[, .(Signal_Date = max(Date)), by = YM]$Signal_Date
all_signal_dates <- sort(all_signal_dates)
all_dates <- sort(unique(RAWDATA$Date))
min_start <- all_dates[min(LOOKBACK + 1L, length(all_dates))]
monthly_dates <- all_signal_dates[all_signal_dates >= min_start]

monthly_macro <- data.table(Signal_Date = monthly_dates)
monthly_macro[, YM := format(Signal_Date, "%Y-%m")]
monthly_macro <- merge(monthly_macro, macro_regime_dt[, .(YM, Macro_Risk_Score, VIX_Regime, Buddha_Mode)],
                       by = "YM", all.x = TRUE)
monthly_macro[is.na(Macro_Risk_Score), Macro_Risk_Score := 0]
monthly_macro[is.na(VIX_Regime), VIX_Regime := "normal"]
monthly_macro[is.na(Buddha_Mode), Buddha_Mode := FALSE]
monthly_macro[, hard_cashout := (BUDDHA_CASH_OUT & Buddha_Mode) | (Macro_Risk_Score >= MACRO_HARD_THRESH) |
                                (VIX_Regime %in% c("extreme", "crisis"))]
monthly_macro[, months_since_crisis := {
  out <- rep(Inf, .N); lc <- -Inf
  for (i in seq_len(.N)) { if (hard_cashout[i]) lc <- i; out[i] <- i - lc }; out }]
monthly_macro[, effective_cashout := hard_cashout | (months_since_crisis < COOLDOWN_MONTHS)]
monthly_macro <- merge(monthly_macro, fred_monthly, by = "YM", all.x = TRUE)
monthly_macro[is.na(exposure), exposure := 1.0]
monthly_macro[is.na(n_sig), n_sig := 0L]

bm_daily <- unique(RAWDATA[, .(Date, BM_Ret)]); setorder(bm_daily, Date)
factor_list <- list(); n_done <- 0L; n_skipped <- 0L; n_excluded <- 0L

for (i in seq_len(nrow(monthly_macro))) {
  row <- monthly_macro[i]; sig_d <- as.Date(row$Signal_Date)
  if (row$effective_cashout) { n_skipped <- n_skipped + 1L; next }
  idx <- which(all_dates == sig_d); if (length(idx) == 0) next
  rs <- row$Macro_Risk_Score
  exp_factor <- row$exposure
  if (exp_factor == 0) { n_skipped <- n_skipped + 1L; next }

  rsc <- if (rs >= 15) REGIME_SCALE_SOFT else 1.0

  lb_start <- all_dates[max(1, idx - LOOKBACK)]
  window <- RAWDATA[Date >= lb_start & Date <= sig_d]

  stats <- window[!is.na(Ret) & !is.na(Close), {
    n <- .N
    if (n < MIN_OBS) list(idiovol = NA_real_, ret_12m = NA_real_, ret_1m = NA_real_,
                          ret_rev = NA_real_, cvar5 = NA_real_, avg_vol = NA_real_)
    else {
      bm_w <- bm_daily[Date >= lb_start & Date <= sig_d]
      mg <- merge(data.table(Date = Date, Ret = Ret), bm_w, by = "Date", all.x = TRUE)
      mg <- mg[!is.na(Ret) & !is.na(BM_Ret)]
      if (nrow(mg) < MIN_OBS) list(idiovol = NA_real_, ret_12m = NA_real_, ret_1m = NA_real_,
                                   ret_rev = NA_real_, cvar5 = NA_real_, avg_vol = NA_real_)
      else {
        fit <- .lm.fit(cbind(1, mg$BM_Ret), mg$Ret)
        rv <- fit$residuals
        r_rev <- as.double(prod(1 + tail(Ret[!is.na(Ret)], REV_WINDOW), na.rm = TRUE) - 1)
        rv_sorted <- sort(rv)
        n_tail <- max(1L, floor(length(rv_sorted) * CVAR_ALPHA))
        cvar5 <- as.double(mean(rv_sorted[seq_len(n_tail)]))
        r_1m <- as.double(prod(1 + tail(Ret[!is.na(Ret)], MOM_WINDOW_SHORT), na.rm = TRUE) - 1)
        list(idiovol = as.double(sd(rv)),
             ret_12m = as.double(prod(1 + Ret, na.rm = TRUE) - 1),
             ret_1m = r_1m,
             ret_rev = r_rev, cvar5 = cvar5,
             avg_vol = as.double(mean(tail(Vol, 20), na.rm = TRUE)))
      }
    }
  }, by = Ticker]

  stats <- stats[!is.na(idiovol) & !is.na(ret_12m) & !is.na(ret_1m)]
  stats[, vol_rank := frank(avg_vol, ties.method = "average") / .N]
  stats <- stats[vol_rank > VOL_FLOOR_Q & ret_12m > -0.40]
  if (nrow(stats) < 30) next
  si_all <- unique(RAWDATA[Date == sig_d, .(Ticker, Sector)])
  stats <- merge(stats, si_all, by = "Ticker", all.x = TRUE)

  ## ── Gates: DaysInventory + CVaR + Rev42d ──
  if (HAS_DART) {
    avd <- sort(unique(FUND_DT$Factor_Date)); vd <- avd[avd <= sig_d]
    if (length(vd) > 0) {
      lfd <- max(vd)
      fs <- FUND_DT[Factor_Date == lfd & !is.na(DaysInventory), .(Ticker, gv = DaysInventory)]
      stats <- merge(stats, fs, by = "Ticker", all.x = TRUE)
      if (sum(!is.na(stats$gv)) > 50) {
        thr <- quantile(stats$gv[!is.na(stats$gv)], 0.90)
        n_b <- nrow(stats); stats <- stats[is.na(gv) | gv <= thr]
        n_excluded <- n_excluded + (n_b - nrow(stats))
      }
      stats[, gv := NULL]
    }
  }
  if (sum(!is.na(stats$cvar5)) > 50) {
    cvar_thr <- quantile(stats$cvar5[!is.na(stats$cvar5)], 0.10)
    n_b <- nrow(stats); stats <- stats[is.na(cvar5) | cvar5 >= cvar_thr]
    n_excluded <- n_excluded + (n_b - nrow(stats))
  }
  if (sum(!is.na(stats$ret_rev)) > 50) {
    rev_thr <- quantile(stats$ret_rev[!is.na(stats$ret_rev)], REV_EXCLUDE_Q)
    n_b <- nrow(stats); stats <- stats[is.na(ret_rev) | ret_rev >= rev_thr]
    n_excluded <- n_excluded + (n_b - nrow(stats))
  }

  if (nrow(stats) < 30) next

  ## ── Momentum Scoring: z(ret_12m - ret_1m) ──
  stats[, mom_raw := ret_12m - ret_1m]
  .w <- function(x) { q <- quantile(x, c(0.01, 0.99), na.rm = TRUE); pmin(pmax(x, q[1]), q[2]) }
  stats[, mom_w := .w(mom_raw)]
  stats[, z_mom := (mom_w - mean(mom_w)) / sd(mom_w)]

  ## Sector-neutral + regime scale + CrossAsset exposure
  stats[, Score := as.double((z_mom - mean(z_mom, na.rm = TRUE)) * rsc * exp_factor), by = Sector]
  stats[, Date := sig_d]
  factor_list[[length(factor_list) + 1]] <- stats[!is.na(Score), .(Date, Ticker, Score)]
  n_done <- n_done + 1L
}

if (length(factor_list) == 0) stop("No momentum data")
FACTORS <- rbindlist(factor_list); setorder(FACTORS, Date, -Score)
if ("YM" %in% names(RAWDATA)) RAWDATA[, YM := NULL]
cat(sprintf("[momentum_sleeve] %d rows | %d dates | excluded=%d\n", nrow(FACTORS), uniqueN(FACTORS$Date), n_excluded))
