## --------------------------------------------------------------------------
## STR_887: Foreign Investor Flow Alpha — factor_engine v7.1 rebuild (C11 FIXED)
## CHANGE: Replace old MRS (FRED_REGIME_CACHE / Macro_Risk_Score) with
##         regime_engine_v7 (build_regime_v7 / exposure).
##         Old MRS is C11-contaminated (FRED monthly -> same-month apply).
##         v7: expanding-window Jump Model + CDaR + LR filter. PIT clean.
## FIX: shift(1L) on fred_monthly — FRED month M signal used in month M+1 only (C11)
## --------------------------------------------------------------------------
cat("[factor_engine_v71_fixed] STR_887: Foreign Flow Alpha (v7.1 regime, C11 fix)...\n")
set.seed(88712)

LOOKBACK <- 252L; MIN_OBS <- 200L; VOL_FLOOR_Q <- 0.05
COOLDOWN_MONTHS <- 2L
KALMAN_PHI <- 0.98
REV_WINDOW <- 42L; REV_EXCLUDE_Q <- 0.05
CVAR_ALPHA <- 0.05

# --- 1. Load Foreign Investor Flow Data (UNCHANGED) -------------------------
cat("  [1] Loading investor flow data...\n")
inv_dir <- file.path(PROJECT_ROOT, ".cache", "investor")
kospi_files <- list.files(inv_dir, pattern = "kospi.*\\.csv$", full.names = TRUE)
kosdaq_files <- list.files(inv_dir, pattern = "kosdaq.*\\.csv$", full.names = TRUE)
cat(sprintf("    KOSPI files: %d | KOSDAQ files: %d\n", length(kospi_files), length(kosdaq_files)))

load_investor <- function(files) {
  dts <- lapply(files, function(f) tryCatch(fread(f, showProgress = FALSE), error = function(e) NULL))
  dts <- dts[!sapply(dts, is.null)]
  rbindlist(dts, fill = TRUE)
}

inv_kospi <- load_investor(kospi_files)
inv_kosdaq <- load_investor(kosdaq_files)
inv_all <- rbind(inv_kospi, inv_kosdaq)
setnames(inv_all, "\uc678\uad6d\uc778", "foreign_net", skip_absent = TRUE)

inv_daily <- inv_all[, .(foreign_net = sum(foreign_net, na.rm = TRUE)), by = Date]
setorder(inv_daily, Date)
inv_daily <- inv_daily[!is.na(Date) & !is.na(foreign_net)]

cat(sprintf("    Investor data: %d days | %s ~ %s\n",
            nrow(inv_daily), as.character(min(inv_daily$Date)), as.character(max(inv_daily$Date))))

# --- 2. Foreign Flow Momentum z-score (UNCHANGED) ---------------------------
cat("  [2] Computing Foreign Flow Momentum z-score...\n")
inv_daily[, flow_20d := frollsum(foreign_net, n = 20L, align = "right", na.rm = TRUE)]
inv_daily[, flow_60d_mean := frollmean(foreign_net, n = 60L, align = "right", na.rm = TRUE)]
inv_daily[, flow_60d_sd := frollapply(foreign_net, n = 60L, FUN = sd, align = "right")]
inv_daily[, flow_z := fifelse(
  !is.na(flow_20d) & !is.na(flow_60d_mean) & !is.na(flow_60d_sd) & flow_60d_sd > 1e-6,
  (flow_20d - flow_60d_mean * 20) / (flow_60d_sd * sqrt(20)),
  NA_real_
)]
inv_daily[, YM := format(Date, "%Y-%m")]
flow_monthly <- inv_daily[!is.na(flow_z), .(flow_z = tail(flow_z, 1)), by = YM]
setkey(flow_monthly, YM)

cat(sprintf("    Flow z-score range: [%.2f, %.2f] | %d months\n",
            min(flow_monthly$flow_z, na.rm = TRUE),
            max(flow_monthly$flow_z, na.rm = TRUE),
            nrow(flow_monthly)))

FLOW_BUY_THRESH  <-  1.0
FLOW_SELL_THRESH <- -1.0

# --- 3. Load Consensus Data (UNCHANGED) -------------------------------------
cat("  [3] Loading consensus data...\n")
CONSENSUS_DIR <- file.path(CACHE_DIR, "consensus")
sue_dt <- as.data.table(read_parquet(file.path(CONSENSUS_DIR, "sue.parquet")))
esbr_dt <- as.data.table(read_parquet(file.path(CONSENSUS_DIR, "esbr.parquet")))
sue_dt[, Date := as.Date(Date)]
esbr_dt[, Date := as.Date(Date)]
setorder(sue_dt, Ticker, Date)
setorder(esbr_dt, Ticker, Date)
sue_dt[, YM := format(Date, "%Y-%m")]
esbr_dt[, YM := format(Date, "%Y-%m")]
sue_monthly <- sue_dt[!is.na(sue), .(sue = tail(sue, 1)), by = .(YM, Ticker)]
esbr_monthly <- esbr_dt[!is.na(esbr), .(esbr = tail(esbr, 1)), by = .(YM, Ticker)]
setkey(sue_monthly, YM, Ticker)
setkey(esbr_monthly, YM, Ticker)
cat(sprintf("    SUE: %d rows | ESBR: %d rows\n", nrow(sue_monthly), nrow(esbr_monthly)))

# --- 4. REGIME ENGINE v7.1 (REPLACING old MRS) ------------------------------
cat("  [4] Loading regime_engine_v7 (replacing old MRS)...\n")
source(file.path(REGIME_DIR, "regime_engine_v7.R"))
regime_v7 <- build_regime_v7(use_cache = TRUE)

# regime_v7 columns: apply_month (YM), exposure, regime_state, p_crisis, MRS
# For gating: use exposure < threshold as cashout equivalent
# Old MRS used: Macro_Risk_Score >= MACRO_HARD_THRESH (40) -> skip month
# Old MRS also had: VIX_Regime extreme/crisis + Buddha_Mode -> cashout
# v7 equivalent: exposure == 0.3 (Crisis state) or p_crisis >= 0.7

# Build monthly macro from v7
regime_v7_monthly <- regime_v7[, .(
  apply_month,
  exposure_v7 = exposure,
  regime_state_v7 = regime_state,
  p_crisis_v7 = p_crisis,
  MRS_v7 = MRS
)]
setkey(regime_v7_monthly, apply_month)

cat(sprintf("    v7 regime: %d months | exposure mean=%.3f | crisis months=%d\n",
            nrow(regime_v7_monthly),
            mean(regime_v7_monthly$exposure_v7, na.rm = TRUE),
            sum(regime_v7_monthly$regime_state_v7 == "Crisis", na.rm = TRUE)))

# Also load FRED data for the cross-asset exposure signal
# (this was separate from the old MRS contaminated piece)
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
FRED_WIDE[, fred_exposure := fifelse(n_signals >= 2, 0.0, fifelse(n_signals == 1, 0.50, 1.0))]
FRED_WIDE[, YM := format(Date, "%Y-%m")]
fred_monthly <- FRED_WIDE[, .(fred_exposure = tail(fred_exposure[!is.na(fred_exposure)], 1),
                               n_sig = tail(n_signals[!is.na(n_signals)], 1)), by = YM]
setorder(fred_monthly, YM)
# C11 FIX: shift FRED exposure by 1 month — month M signal available only in month M+1
fred_monthly[, fred_exposure := shift(fred_exposure, n = 1L, type = "lag")]
fred_monthly[, n_sig := shift(n_sig, n = 1L, type = "lag")]
fred_monthly[is.na(fred_exposure), fred_exposure := 1.0]  # first month = full exposure
fred_monthly[is.na(n_sig), n_sig := 0L]
setkey(fred_monthly, YM)

# --- 5. Build Monthly Factor Scores -----------------------------------------
cat("  [5] Building flow-conditional factor scores (v7.1 regime)...\n")

setorder(RAWDATA, Ticker, Date)
RAWDATA[, YM := format(Date, "%Y-%m")]
all_signal_dates <- RAWDATA[, .(Signal_Date = max(Date)), by = YM]$Signal_Date
all_signal_dates <- sort(all_signal_dates)
all_dates <- sort(unique(RAWDATA$Date))
min_start <- all_dates[min(LOOKBACK + 1L, length(all_dates))]
monthly_dates <- all_signal_dates[all_signal_dates >= min_start]

monthly_macro <- data.table(Signal_Date = monthly_dates)
monthly_macro[, YM := format(Signal_Date, "%Y-%m")]

# --- v7.1 REGIME MERGE (replaces old macro_regime_dt merge) ---
monthly_macro <- merge(monthly_macro, regime_v7_monthly,
                       by.x = "YM", by.y = "apply_month",
                       all.x = TRUE)
# Fill: no v7 data = normal (full exposure)
monthly_macro[is.na(exposure_v7), exposure_v7 := 1.0]
monthly_macro[is.na(p_crisis_v7), p_crisis_v7 := 0.0]
monthly_macro[is.na(regime_state_v7), regime_state_v7 := "Normal"]

# Hard cashout: v7 Crisis state (replaces old Macro_Risk_Score >= 40 + Buddha_Mode)
monthly_macro[, hard_cashout := (regime_state_v7 == "Crisis")]

# Cooldown
monthly_macro[, months_since_crisis := {
  out <- rep(Inf, .N); lc <- -Inf
  for (i in seq_len(.N)) { if (hard_cashout[i]) lc <- i; out[i] <- i - lc }; out }]
monthly_macro[, effective_cashout := hard_cashout | (months_since_crisis < COOLDOWN_MONTHS)]

# Merge FRED cross-asset exposure (this uses expanding z-scores, not old MRS)
monthly_macro <- merge(monthly_macro, fred_monthly, by = "YM", all.x = TRUE)
monthly_macro[is.na(fred_exposure), fred_exposure := 1.0]
monthly_macro[is.na(n_sig), n_sig := 0L]

# Combined exposure: min of v7 exposure and FRED cross-asset
monthly_macro[, combined_exposure := pmin(exposure_v7, fred_exposure)]

# Also merge flow z
monthly_macro <- merge(monthly_macro, flow_monthly, by = "YM", all.x = TRUE)
monthly_macro[is.na(flow_z), flow_z := 0]

bm_daily <- unique(RAWDATA[, .(Date, BM_Ret)]); setorder(bm_daily, Date)
factor_list <- list()
n_done <- 0L; n_skipped <- 0L; n_buy <- 0L; n_sell <- 0L; n_neutral <- 0L

for (i in seq_len(nrow(monthly_macro))) {
  gc(verbose = FALSE)
  row <- monthly_macro[i]; sig_d <- as.Date(row$Signal_Date)
  if (row$effective_cashout) { n_skipped <- n_skipped + 1L; next }
  idx <- which(all_dates == sig_d); if (length(idx) == 0) next
  exp_factor <- row$combined_exposure
  if (exp_factor == 0) { n_skipped <- n_skipped + 1L; next }

  fz <- row$flow_z

  lb_start <- all_dates[max(1, idx - LOOKBACK)]
  window <- RAWDATA[Date >= lb_start & Date <= sig_d]

  stats <- window[!is.na(Ret) & !is.na(Close), {
    n <- .N
    if (n < MIN_OBS) list(idiovol = NA_real_, beta_raw = NA_real_, avg_vol = NA_real_,
                          ret_12m = NA_real_, ret_rev = NA_real_, cvar5 = NA_real_)
    else {
      bm_w <- bm_daily[Date >= lb_start & Date <= sig_d]
      mg <- merge(data.table(Date = Date, Ret = Ret), bm_w, by = "Date", all.x = TRUE)
      mg <- mg[!is.na(Ret) & !is.na(BM_Ret)]
      if (nrow(mg) < MIN_OBS) list(idiovol = NA_real_, beta_raw = NA_real_, avg_vol = NA_real_,
                                   ret_12m = NA_real_, ret_rev = NA_real_, cvar5 = NA_real_)
      else {
        fit <- .lm.fit(cbind(1, mg$BM_Ret), mg$Ret)
        rv <- fit$residuals
        r_rev <- as.double(prod(1 + tail(Ret[!is.na(Ret)], REV_WINDOW), na.rm = TRUE) - 1)
        rv_sorted <- sort(rv)
        n_tail <- max(1L, floor(length(rv_sorted) * CVAR_ALPHA))
        cvar5 <- as.double(mean(rv_sorted[seq_len(n_tail)]))
        list(idiovol = as.double(sd(rv)), beta_raw = as.double(fit$coefficients[2]),
             avg_vol = as.double(mean(tail(Vol, 20), na.rm = TRUE)),
             ret_12m = as.double(prod(1 + Ret, na.rm = TRUE) - 1),
             ret_rev = r_rev, cvar5 = cvar5)
      }
    }
  }, by = Ticker]

  stats <- stats[!is.na(idiovol) & !is.na(beta_raw)]
  stats[, vol_rank := frank(avg_vol, ties.method = "average") / .N]
  stats <- stats[vol_rank > VOL_FLOOR_Q & ret_12m > -0.40]
  if (nrow(stats) < 30) next

  si_all <- unique(RAWDATA[Date == sig_d, .(Ticker, Sector)])
  stats <- merge(stats, si_all, by = "Ticker", all.x = TRUE)
  stats[!is.na(Sector), sector_beta := mean(beta_raw, na.rm = TRUE), by = Sector]
  stats[is.na(sector_beta), sector_beta := mean(stats$beta_raw, na.rm = TRUE)]
  stats[, beta_raw := KALMAN_PHI * beta_raw + (1 - KALMAN_PHI) * sector_beta]
  stats[, beta_s := 0.6 * beta_raw + 0.4 * 1.0]

  if (sum(!is.na(stats$ret_rev)) > 50) {
    rev_thr <- quantile(stats$ret_rev[!is.na(stats$ret_rev)], REV_EXCLUDE_Q)
    stats <- stats[is.na(ret_rev) | ret_rev >= rev_thr]
  }
  if (nrow(stats) < 30) next

  ym_i <- format(sig_d, "%Y-%m")
  sue_m <- sue_monthly[YM == ym_i]
  esbr_m <- esbr_monthly[YM == ym_i]
  stats <- merge(stats, sue_m[, .(Ticker, sue)], by = "Ticker", all.x = TRUE)
  stats <- merge(stats, esbr_m[, .(Ticker, esbr)], by = "Ticker", all.x = TRUE)

  .w <- function(x) { q <- quantile(x, c(0.01, 0.99), na.rm = TRUE); pmin(pmax(x, q[1]), q[2]) }

  stats[, z_iv := { x <- .w(idiovol); -(x - mean(x, na.rm=TRUE)) / max(sd(x, na.rm=TRUE), 1e-8) }]
  stats[, z_beta := { x <- .w(beta_s); (x - mean(x, na.rm=TRUE)) / max(sd(x, na.rm=TRUE), 1e-8) }]
  stats[, z_sue := fifelse(!is.na(sue), { x <- .w(sue[!is.na(sue)]); (sue - mean(x)) / max(sd(x), 1e-8) }, 0)]
  stats[, z_esbr := fifelse(!is.na(esbr), { x <- .w(esbr[!is.na(esbr)]); (esbr - mean(x)) / max(sd(x), 1e-8) }, 0)]

  if (fz > FLOW_BUY_THRESH) {
    stats[, sr := 0.40 * z_beta + 0.30 * z_esbr + 0.30 * z_sue]
    n_buy <- n_buy + 1L
    regime_label <- "FOREIGN_BUY"
  } else if (fz < FLOW_SELL_THRESH) {
    stats[, sr := 0.70 * z_iv + 0.15 * z_esbr + 0.15 * z_sue]
    n_sell <- n_sell + 1L
    regime_label <- "FOREIGN_SELL"
  } else {
    stats[, sr := 0.55 * z_iv + 0.25 * z_esbr + 0.20 * z_sue]
    n_neutral <- n_neutral + 1L
    regime_label <- "NEUTRAL"
  }

  stats[, Score := as.double((sr - mean(sr, na.rm = TRUE)) * exp_factor), by = Sector]
  stats[, Date := sig_d]
  factor_list[[length(factor_list) + 1]] <- stats[!is.na(Score), .(Date, Ticker, Score)]
  n_done <- n_done + 1L
}

if (length(factor_list) == 0) stop("No factor data generated")
FACTORS <- rbindlist(factor_list); setorder(FACTORS, Date, -Score)
if ("YM" %in% names(RAWDATA)) RAWDATA[, YM := NULL]
cat(sprintf("[STR_887 v7.1 C11-fixed] Flow Alpha | %d rows | %d dates | skip=%d | BUY=%d | SELL=%d | NEUTRAL=%d\n",
            nrow(FACTORS), uniqueN(FACTORS$Date), n_skipped, n_buy, n_sell, n_neutral))
