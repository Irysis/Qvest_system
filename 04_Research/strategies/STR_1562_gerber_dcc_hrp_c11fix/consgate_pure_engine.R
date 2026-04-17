#==============================================================================
# STR_1000 Phase 1d: ConsGate Pure Engine
# Based on STR_886 Consensus Momentum GATE, but with IdioVol REMOVED
#
# Change from STR_886:
#   SCORE: 0.65 * rank(low_idiovol) + 0.35 * rank(sue)
#   →  SCORE: 0.0  * rank(low_idiovol) + 1.0  * rank(sue)
#
# Gate conditions PRESERVED:
#   - eps_chg_1m > 0 (positive 1-month revision)
#   - sign(eps_chg_1m) == sign(eps_chg_3m) (direction confirmed)
#   - coverage >= 3
#
# Purpose: Remove Defense (IdioVol) overlap from ConsGate sleeve
#==============================================================================

cat("[factor_engine] STR_1000 ConsGate Pure: Gate + SUE 100% (IdioVol 0%)...\n")
set.seed(42)

LOOKBACK    <- 252L
MIN_OBS     <- 200L
VOL_FLOOR_Q <- 0.05
W_IDIOVOL   <- 0.0   # <<< CHANGED from 0.65 to 0.0 (remove Defense overlap)
W_SUE       <- 1.0   # <<< CHANGED from 0.35 to 1.0 (pure SUE scoring)
MIN_COVERAGE <- 3L

MACRO_HARD_THRESH <- if (exists("MACRO_HARD_THRESH")) MACRO_HARD_THRESH else 30L
REGIME_SOFT_THRESH <- if (exists("REGIME_SOFT_THRESH")) REGIME_SOFT_THRESH else 15L
BUDDHA_CASH_OUT   <- TRUE
REGIME_SCALE_SOFT <- 0.5

# --- Regime data (C11 FIX: accessed via prev_ym = t-1 month, NOT same-month) ---
macro_regime_dt <- as.data.table(read_parquet(FRED_REGIME_CACHE))  # C11_LAG_OK: t-1 month lag applied at access (line 70)
macro_regime_dt[, YM := substr(Date, 1, 7)]
setkey(macro_regime_dt, YM)

# --- Consensus data ---
source(file.path(DATA_DIR, "consensus_parser.R"))
cs <- consensus_load(
  metrics   = c("eps_chg_1m", "eps_chg_3m", "sue", "coverage"),
  date_from = "2001-01-01"
)
cat(sprintf("  Consensus loaded: %s rows\n", format(nrow(cs), big.mark = ",")))

# --- Quarterly rebalance dates ---
setorder(RAWDATA, Ticker, Date)
RAWDATA[, YM := format(Date, "%Y-%m")]
all_signal_dates <- RAWDATA[, .(Signal_Date = max(Date)), by = YM]
all_signal_dates[, Month := as.integer(substr(YM, 6, 7))]
quarterly_dates <- sort(all_signal_dates[Month %in% c(3, 6, 9, 12)]$Signal_Date)

all_dates <- sort(unique(RAWDATA$Date))
min_start <- all_dates[min(LOOKBACK + 1L, length(all_dates))]
quarterly_dates <- quarterly_dates[quarterly_dates >= min_start]

bm_daily <- unique(RAWDATA[, .(Date, BM_Ret)])
setorder(bm_daily, Date)

# --- Main loop ---
factor_list <- list()
n_done <- 0; n_skipped <- 0; n_gate_stats <- c()

for (sig_d in quarterly_dates) {
  sig_d <- as.Date(sig_d)
  sig_ym <- format(sig_d, "%Y-%m")
  idx <- which(all_dates == sig_d)

  # Regime check — C11 FIX: use t-1 month FRED data (previous month)
  # FRED monthly data published at month-end → same-month access is lookahead
  prev_ym <- format(as.Date(paste0(sig_ym, "-01")) - 32, "%Y-%m")
  macro_row <- macro_regime_dt[YM == prev_ym]
  buddha <- if (nrow(macro_row) > 0 && !is.na(macro_row$Buddha_Mode[1]))
    macro_row$Buddha_Mode[1] else FALSE
  risk_s <- if (nrow(macro_row) > 0 && !is.na(macro_row$Macro_Risk_Score[1]))
    macro_row$Macro_Risk_Score[1] else 0
  vix_r <- if (nrow(macro_row) > 0 && !is.na(macro_row$VIX_Regime[1]))
    macro_row$VIX_Regime[1] else "normal"

  if ((BUDDHA_CASH_OUT && buddha) || risk_s >= MACRO_HARD_THRESH ||
      vix_r %in% c("extreme", "crisis")) {
    n_skipped <- n_skipped + 1; next
  }

  # Soft regime scaling (linear ramp from REGIME_SOFT_THRESH to MACRO_HARD_THRESH)
  regime_scale <- if (risk_s >= REGIME_SOFT_THRESH) {
    1.0 - (risk_s - REGIME_SOFT_THRESH) / (MACRO_HARD_THRESH - REGIME_SOFT_THRESH) * (1.0 - REGIME_SCALE_SOFT)
  } else 1.0
  regime_scale <- max(regime_scale, REGIME_SCALE_SOFT)

  # --- IdioVol calculation (still needed for universe filtering, NOT scoring) ---
  lb_start <- all_dates[max(1, idx - LOOKBACK)]
  window <- RAWDATA[Date >= lb_start & Date <= sig_d]

  lv <- window[!is.na(Ret) & !is.na(Close), {
    n <- .N
    if (n < MIN_OBS) {
      list(idiovol = NA_real_, avg_vol = NA_real_, ret_12m = NA_real_)
    } else {
      bm_w <- bm_daily[Date >= lb_start & Date <= sig_d]
      m <- merge(data.table(Date = Date, Ret = Ret), bm_w, by = "Date", all.x = TRUE)
      m <- m[!is.na(Ret) & !is.na(BM_Ret)]
      if (nrow(m) < MIN_OBS) {
        list(idiovol = NA_real_, avg_vol = mean(tail(Vol, 20), na.rm = TRUE),
             ret_12m = prod(1 + Ret, na.rm = TRUE) - 1)
      } else {
        fit <- .lm.fit(cbind(1, m$BM_Ret), m$Ret)
        list(idiovol = sd(fit$residuals), avg_vol = mean(tail(Vol, 20), na.rm = TRUE),
             ret_12m = prod(1 + Ret, na.rm = TRUE) - 1)
      }
    }
  }, by = Ticker]
  lv <- lv[!is.na(idiovol)]

  # Liquidity & crash filter
  lv[, vol_rank := frank(avg_vol, ties.method = "average") / .N]
  lv <- lv[vol_rank > VOL_FLOOR_Q & ret_12m > -0.40]
  if (nrow(lv) < 30) next

  # --- Merge consensus ---
  cs_snap <- cs[Date >= (sig_d - 7) & Date <= sig_d]
  if (nrow(cs_snap) > 0) {
    cs_l <- cs_snap[order(Date)][, .SD[.N], by = Ticker]
    cs_l <- cs_l[!is.na(coverage) & coverage >= MIN_COVERAGE]
    lv <- merge(lv, cs_l[, .(Ticker, eps_chg_1m, eps_chg_3m, sue, coverage)],
                by = "Ticker", all.x = TRUE)
  } else {
    lv[, c("eps_chg_1m", "eps_chg_3m", "sue", "coverage") :=
         .(NA_real_, NA_real_, NA_real_, NA_real_)]
  }

  # ===== CONSENSUS MOMENTUM GATE (preserved from STR_886) =====
  lv_gated <- lv[!is.na(eps_chg_1m) & !is.na(eps_chg_3m) &
                  eps_chg_1m > 0 &
                  sign(eps_chg_1m) == sign(eps_chg_3m)]

  n_gate_stats <- c(n_gate_stats, nrow(lv_gated))

  if (nrow(lv_gated) < 10) {
    cat(sprintf("  [SKIP] %s — only %d stocks pass gate\n", sig_d, nrow(lv_gated)))
    n_skipped <- n_skipped + 1
    next
  }

  # ===== SCORING: SUE Pure (100%) — IdioVol removed =====
  # rank_ivol still computed but W_IDIOVOL=0 so it has zero contribution
  lv_gated[, rank_ivol := frank(-idiovol, ties.method = "average") / .N]

  if (sum(!is.na(lv_gated$sue)) >= 10) {
    has_sue <- !is.na(lv_gated$sue)
    lv_gated[has_sue,  rank_sue := frank(sue, ties.method = "average") / sum(has_sue)]
    lv_gated[!has_sue, rank_sue := 0.5]
  } else {
    lv_gated[, rank_sue := 0.5]
  }

  # W_IDIOVOL=0.0, W_SUE=1.0 → Score = rank_sue * regime_scale
  lv_gated[, Score := (W_IDIOVOL * rank_ivol + W_SUE * rank_sue) * regime_scale]

  # Sector neutralization
  sector_info <- unique(RAWDATA[Date == sig_d, .(Ticker, Sector)])
  lv_gated <- merge(lv_gated, sector_info, by = "Ticker", all.x = TRUE)
  lv_gated[, Score := Score - mean(Score, na.rm = TRUE), by = Sector]

  lv_gated[, Date := sig_d]
  factor_list[[length(factor_list) + 1]] <- lv_gated[!is.na(Score), .(Date, Ticker, Score)]
  n_done <- n_done + 1

  if (n_done %% 10 == 0)
    cat(sprintf("  [%d/%d skip] %s — %d gated (of %d universe)\n",
                n_done, n_skipped, sig_d, nrow(lv_gated), nrow(lv)))
}

FACTORS <- rbindlist(factor_list)
setorder(FACTORS, Date, -Score)
if ("YM" %in% names(RAWDATA)) RAWDATA[, YM := NULL]

cat(sprintf("[factor_engine] FACTORS: %d rows | %d dates | %d skipped | %d tickers\n",
            nrow(FACTORS), uniqueN(FACTORS$Date), n_skipped, uniqueN(FACTORS$Ticker)))
cat(sprintf("[factor_engine] Gate stats: median %d stocks pass gate per period (range: %d-%d)\n",
            as.integer(median(n_gate_stats, na.rm = TRUE)),
            min(n_gate_stats, na.rm = TRUE), max(n_gate_stats, na.rm = TRUE)))
cat("[factor_engine] W_IDIOVOL=0.0, W_SUE=1.0 — ConsGate Pure (Defense overlap removed)\n")
