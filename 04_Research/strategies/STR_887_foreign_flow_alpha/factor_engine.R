## ──────────────────────────────────────────────────────────────────────────────
## STR_887: Foreign Investor Flow Alpha (STANDALONE, no IdioVol)
## Signal: Foreign flow momentum → regime-conditional stock selection
##   - Foreign buying regime: high-beta + rev_breadth + sue
##   - Foreign selling regime: low-idiovol + rev_breadth + sue
##   - Neutral: balanced mix
## Data: Naver investor data (2020-01+), KOSPI+KOSDAQ market-level flows
## ──────────────────────────────────────────────────────────────────────────────
cat("[factor_engine] STR_887: Foreign Flow Alpha...\n")
set.seed(42)

LOOKBACK <- 252L; MIN_OBS <- 200L; VOL_FLOOR_Q <- 0.05
COOLDOWN_MONTHS <- 2L
KALMAN_PHI <- 0.98
REV_WINDOW <- 42L; REV_EXCLUDE_Q <- 0.05
CVAR_ALPHA <- 0.05

# ─── 1. Load Foreign Investor Flow Data ────────────────────────────────────
cat("  [1] Loading investor flow data...\n")
inv_dir <- file.path(PROJECT_ROOT, ".cache", "investor")

# Load all KOSPI files
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

# Combine KOSPI + KOSDAQ foreign net buying (aggregate market-level signal)
inv_all <- rbind(inv_kospi, inv_kosdaq)
setnames(inv_all, "\uc678\uad6d\uc778", "foreign_net", skip_absent = TRUE)  # 외국인

# Aggregate daily: sum across KOSPI and KOSDAQ
inv_daily <- inv_all[, .(foreign_net = sum(foreign_net, na.rm = TRUE)), by = Date]
setorder(inv_daily, Date)
inv_daily <- inv_daily[!is.na(Date) & !is.na(foreign_net)]

cat(sprintf("    Investor data: %d days | %s ~ %s\n",
            nrow(inv_daily), as.character(min(inv_daily$Date)), as.character(max(inv_daily$Date))))

# ─── 2. Compute Foreign Flow Momentum z-score ─────────────────────────────
cat("  [2] Computing Foreign Flow Momentum z-score...\n")

# Rolling 20d sum of foreign net buying
inv_daily[, flow_20d := frollsum(foreign_net, n = 20L, align = "right", na.rm = TRUE)]
# Rolling 60d mean (baseline)
inv_daily[, flow_60d_mean := frollmean(foreign_net, n = 60L, align = "right", na.rm = TRUE)]
# Rolling 60d sd
inv_daily[, flow_60d_sd := frollapply(foreign_net, n = 60L, FUN = sd, align = "right")]

# z-score = (20d_sum - 60d_mean * 20) / (60d_sd * sqrt(20))
# Scale: 20d_sum has scale of ~20x daily, so normalize properly
inv_daily[, flow_z := fifelse(
  !is.na(flow_20d) & !is.na(flow_60d_mean) & !is.na(flow_60d_sd) & flow_60d_sd > 1e-6,
  (flow_20d - flow_60d_mean * 20) / (flow_60d_sd * sqrt(20)),
  NA_real_
)]

# Monthly: use last trading day of each month
inv_daily[, YM := format(Date, "%Y-%m")]
flow_monthly <- inv_daily[!is.na(flow_z), .(flow_z = tail(flow_z, 1)), by = YM]
setkey(flow_monthly, YM)

cat(sprintf("    Flow z-score range: [%.2f, %.2f] | %d months\n",
            min(flow_monthly$flow_z, na.rm = TRUE),
            max(flow_monthly$flow_z, na.rm = TRUE),
            nrow(flow_monthly)))

# Flow regime thresholds
FLOW_BUY_THRESH  <-  1.0   # Strong foreign buying
FLOW_SELL_THRESH <- -1.0   # Strong foreign selling

# ─── 3. Load Consensus Data ───────────────────────────────────────────────
cat("  [3] Loading consensus data...\n")
CONSENSUS_DIR <- file.path(CACHE_DIR, "consensus")
sue_dt <- as.data.table(read_parquet(file.path(CONSENSUS_DIR, "sue.parquet")))
esbr_dt <- as.data.table(read_parquet(file.path(CONSENSUS_DIR, "esbr.parquet")))
sue_dt[, Date := as.Date(Date)]
esbr_dt[, Date := as.Date(Date)]
setorder(sue_dt, Ticker, Date)
setorder(esbr_dt, Ticker, Date)

# Convert to monthly (last available in each YM)
sue_dt[, YM := format(Date, "%Y-%m")]
esbr_dt[, YM := format(Date, "%Y-%m")]
sue_monthly <- sue_dt[!is.na(sue), .(sue = tail(sue, 1)), by = .(YM, Ticker)]
esbr_monthly <- esbr_dt[!is.na(esbr), .(esbr = tail(esbr, 1)), by = .(YM, Ticker)]
setkey(sue_monthly, YM, Ticker)
setkey(esbr_monthly, YM, Ticker)

cat(sprintf("    SUE: %d rows | ESBR: %d rows\n", nrow(sue_monthly), nrow(esbr_monthly)))

# ─── 4. FRED Macro Regime (same as Defense) ───────────────────────────────
cat("  [4] Loading macro regime...\n")
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

# ─── 5. Build Monthly Factor Scores ──────────────────────────────────────
cat("  [5] Building flow-conditional factor scores...\n")

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

# Also merge flow z
monthly_macro <- merge(monthly_macro, flow_monthly, by = "YM", all.x = TRUE)
monthly_macro[is.na(flow_z), flow_z := 0]  # No investor data available → neutral

bm_daily <- unique(RAWDATA[, .(Date, BM_Ret)]); setorder(bm_daily, Date)
factor_list <- list()
n_done <- 0L; n_skipped <- 0L; n_buy <- 0L; n_sell <- 0L; n_neutral <- 0L

for (i in seq_len(nrow(monthly_macro))) {
  gc(verbose = FALSE)
  row <- monthly_macro[i]; sig_d <- as.Date(row$Signal_Date)
  if (row$effective_cashout) { n_skipped <- n_skipped + 1L; next }
  idx <- which(all_dates == sig_d); if (length(idx) == 0) next
  exp_factor <- row$exposure
  if (exp_factor == 0) { n_skipped <- n_skipped + 1L; next }

  # Get flow regime
  fz <- row$flow_z

  lb_start <- all_dates[max(1, idx - LOOKBACK)]
  window <- RAWDATA[Date >= lb_start & Date <= sig_d]

  # Compute stock-level stats: IdioVol, Beta, volume
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

  # Sector + Kalman beta
  si_all <- unique(RAWDATA[Date == sig_d, .(Ticker, Sector)])
  stats <- merge(stats, si_all, by = "Ticker", all.x = TRUE)
  stats[!is.na(Sector), sector_beta := mean(beta_raw, na.rm = TRUE), by = Sector]
  stats[is.na(sector_beta), sector_beta := mean(stats$beta_raw, na.rm = TRUE)]
  stats[, beta_raw := KALMAN_PHI * beta_raw + (1 - KALMAN_PHI) * sector_beta]
  stats[, beta_s := 0.6 * beta_raw + 0.4 * 1.0]

  # Reversal gate (same as Defense)
  if (sum(!is.na(stats$ret_rev)) > 50) {
    rev_thr <- quantile(stats$ret_rev[!is.na(stats$ret_rev)], REV_EXCLUDE_Q)
    stats <- stats[is.na(ret_rev) | ret_rev >= rev_thr]
  }
  if (nrow(stats) < 30) next

  # Merge consensus
  ym_i <- format(sig_d, "%Y-%m")
  sue_m <- sue_monthly[YM == ym_i]
  esbr_m <- esbr_monthly[YM == ym_i]
  stats <- merge(stats, sue_m[, .(Ticker, sue)], by = "Ticker", all.x = TRUE)
  stats <- merge(stats, esbr_m[, .(Ticker, esbr)], by = "Ticker", all.x = TRUE)

  # Winsorize and z-score
  .w <- function(x) { q <- quantile(x, c(0.01, 0.99), na.rm = TRUE); pmin(pmax(x, q[1]), q[2]) }

  # z-scores: low IdioVol = good (negative sign), high Beta = good for buying regime
  stats[, z_iv := { x <- .w(idiovol); -(x - mean(x, na.rm=TRUE)) / max(sd(x, na.rm=TRUE), 1e-8) }]
  stats[, z_beta := { x <- .w(beta_s); (x - mean(x, na.rm=TRUE)) / max(sd(x, na.rm=TRUE), 1e-8) }]  # high = good
  stats[, z_sue := fifelse(!is.na(sue), { x <- .w(sue[!is.na(sue)]); (sue - mean(x)) / max(sd(x), 1e-8) }, 0)]
  stats[, z_esbr := fifelse(!is.na(esbr), { x <- .w(esbr[!is.na(esbr)]); (esbr - mean(x)) / max(sd(x), 1e-8) }, 0)]

  # ─── Flow-Conditional Scoring ───────────────────────────────────────────
  if (fz > FLOW_BUY_THRESH) {
    # Foreign buying → favor high-beta, momentum-aligned stocks
    # Scoring: 0.40*high_beta + 0.30*rev_breadth + 0.30*sue
    stats[, sr := 0.40 * z_beta + 0.30 * z_esbr + 0.30 * z_sue]
    n_buy <- n_buy + 1L
    regime_label <- "FOREIGN_BUY"
  } else if (fz < FLOW_SELL_THRESH) {
    # Foreign selling → favor low-vol defensive stocks
    # Scoring: 0.70*low_idiovol + 0.15*rev_breadth + 0.15*sue
    stats[, sr := 0.70 * z_iv + 0.15 * z_esbr + 0.15 * z_sue]
    n_sell <- n_sell + 1L
    regime_label <- "FOREIGN_SELL"
  } else {
    # Neutral: balanced
    # Scoring: 0.55*low_idiovol + 0.25*rev_breadth + 0.20*sue
    stats[, sr := 0.55 * z_iv + 0.25 * z_esbr + 0.20 * z_sue]
    n_neutral <- n_neutral + 1L
    regime_label <- "NEUTRAL"
  }

  # Sector-neutral scoring with macro exposure scaling
  stats[, Score := as.double((sr - mean(sr, na.rm = TRUE)) * exp_factor), by = Sector]
  stats[, Date := sig_d]
  factor_list[[length(factor_list) + 1]] <- stats[!is.na(Score), .(Date, Ticker, Score)]
  n_done <- n_done + 1L
}

if (length(factor_list) == 0) stop("No factor data generated")
FACTORS <- rbindlist(factor_list); setorder(FACTORS, Date, -Score)
if ("YM" %in% names(RAWDATA)) RAWDATA[, YM := NULL]
cat(sprintf("[STR_887] Flow Alpha | %d rows | %d dates | skip=%d | BUY=%d | SELL=%d | NEUTRAL=%d\n",
            nrow(FACTORS), uniqueN(FACTORS$Date), n_skipped, n_buy, n_sell, n_neutral))
