## RC Shared Factor Engine — 5F Composite (Defense/Consensus/Momentum/Quality/Value)
## Sourced by all RC_* strategies. Requires:
##   - RAWDATA, BM_DT loaded
##   - INFRA_DIR, FUNC_PATH, CACHE_DIR, LIQ_THRESHOLD defined
##   - get_regime_weights(sig_d) function defined by calling strategy
##     returns list(weights = named_vector, cash = numeric)
## Produces: FACTORS, regime_log_dt

cat("[Shared 5F Engine] Starting...\n")

setorder(RAWDATA, Ticker, Date)
RAWDATA[, YM := format(Date, "%Y-%m")]
all_signal_dates <- RAWDATA[, .(Signal_Date = max(Date)), by = YM]$Signal_Date
all_signal_dates <- sort(all_signal_dates)
all_dates <- sort(unique(RAWDATA$Date))
LOOKBACK <- 252L
MIN_OBS  <- 200L
min_start <- all_dates[min(LOOKBACK + 1L, length(all_dates))]
monthly_dates <- all_signal_dates[all_signal_dates >= min_start]

bm_daily <- unique(RAWDATA[, .(Date, BM_Ret)]); setorder(bm_daily, Date)

RAWDATA[, TradingValue := Close * Vol]
RAWDATA[, AvgTV20 := shift(frollmean(TradingValue, n = 20L, align = "right"),
                            n = 1L, type = "lag"), by = Ticker]

# Load DART
DART_FACTOR_CACHE <- file.path(CACHE_DIR, "fundamental_dart.parquet")
HAS_DART <- file.exists(DART_FACTOR_CACHE)
if (HAS_DART) {
  FUND_DT <- as.data.table(read_parquet(DART_FACTOR_CACHE))
  setnames(FUND_DT, "bsns_year", "biz_year", skip_absent = TRUE)
  FUND_DT[, Factor_Date := as.Date(Factor_Date)]
}

# Load consensus
source(file.path(DATA_DIR, "consensus_parser.R"))
cs <- consensus_load(metrics = c("sue", "eps_chg_1m", "coverage"),
                     date_from = "2001-01-01")

# Rank-based z-score
z_safe <- function(x) {
  valid <- !is.na(x)
  if (sum(valid) < 10) return(rep(0.5, length(x)))
  out <- rep(0.5, length(x))
  out[valid] <- frank(x[valid], ties.method = "average") / sum(valid)
  out
}

factor_list <- list()
regime_log  <- list()
n_done <- 0L; n_skipped <- 0L

for (sig_d in monthly_dates) {
  sig_d <- as.Date(sig_d)
  gc(verbose = FALSE)

  idx <- which(all_dates == sig_d)
  if (length(idx) == 0) { n_skipped <- n_skipped + 1L; next }

  # --- Get regime-dependent weights from calling strategy ---
  rw <- get_regime_weights(sig_d)
  w_vec <- rw$weights
  cash   <- rw$cash
  regime_log[[length(regime_log) + 1L]] <- c(list(Date = sig_d, cash = cash), rw$meta)

  lb_start <- all_dates[max(1, idx - LOOKBACK)]
  snap <- RAWDATA[Date == sig_d, .(Ticker, Close, AvgTV20, Sector, Size)]
  snap <- snap[!is.na(Close) & Close > 0]
  snap <- snap[!is.na(AvgTV20) & AvgTV20 >= LIQ_THRESHOLD]
  if (nrow(snap) < 50) { n_skipped <- n_skipped + 1L; next }

  window <- RAWDATA[Ticker %in% snap$Ticker & Date >= lb_start & Date <= sig_d]

  # ── Factor 1: Defense ──
  stats <- window[!is.na(Ret) & !is.na(Close), {
    n <- .N
    if (n < MIN_OBS) list(idiovol = NA_real_, beta_raw = NA_real_,
                          ret_12m = NA_real_, ret_1m = NA_real_)
    else {
      bm_w <- bm_daily[Date >= lb_start & Date <= sig_d]
      mg <- merge(data.table(Date = Date, Ret = Ret), bm_w, by = "Date", all.x = TRUE)
      mg <- mg[!is.na(Ret) & !is.na(BM_Ret)]
      if (nrow(mg) < MIN_OBS) list(idiovol = NA_real_, beta_raw = NA_real_,
                                   ret_12m = NA_real_, ret_1m = NA_real_)
      else {
        fit <- .lm.fit(cbind(1, mg$BM_Ret), mg$Ret)
        rv <- fit$residuals
        ret_1m_val <- as.double(prod(1 + tail(Ret[!is.na(Ret)], 21), na.rm = TRUE) - 1)
        list(idiovol = as.double(sd(rv)),
             beta_raw = as.double(fit$coefficients[2]),
             ret_12m = as.double(prod(1 + Ret, na.rm = TRUE) - 1),
             ret_1m = ret_1m_val)
      }
    }
  }, by = Ticker]
  stats <- stats[!is.na(idiovol) & !is.na(beta_raw)]
  stats <- merge(stats, snap[, .(Ticker, Sector, Close, Size)], by = "Ticker", all.x = TRUE)
  if (nrow(stats) < 50) { n_skipped <- n_skipped + 1L; next }

  stats[, z_defense := z_safe(-idiovol) + z_safe(-beta_raw)]

  # ── Factor 2: Consensus ──
  cs_now <- cs[Date >= (sig_d - 7) & Date <= sig_d]
  if (nrow(cs_now) > 0) {
    cs_now <- cs_now[order(Date)][, .SD[.N], by = Ticker]
    cs_now <- cs_now[!is.na(coverage) & coverage >= 3L]
    stats <- merge(stats,
                   cs_now[, .(Ticker, sue_val = sue, eps_chg = eps_chg_1m)],
                   by = "Ticker", all.x = TRUE)
  } else {
    stats[, c("sue_val", "eps_chg") := NA_real_]
  }
  stats[, z_consensus := fifelse(!is.na(sue_val) & !is.na(eps_chg),
                                  z_safe(sue_val) + z_safe(eps_chg), 0)]

  # ── Factor 3: Momentum ──
  high_52 <- window[!is.na(High), .(high_52w = max(High, na.rm = TRUE)), by = Ticker]
  stats <- merge(stats, high_52, by = "Ticker", all.x = TRUE)
  stats[!is.na(high_52w) & high_52w > 0, ratio_52w := Close / high_52w]
  stats[, z_momentum := z_safe(ret_12m - ret_1m)]
  stats[!is.na(ratio_52w), z_momentum := z_momentum + z_safe(ratio_52w)]

  # ── Factor 4: Quality ──
  stats[, z_quality := 0]
  if (HAS_DART) {
    avd <- sort(unique(FUND_DT$Factor_Date))
    vd <- avd[avd <= sig_d]
    if (length(vd) > 0) {
      lfd <- max(vd)
      fund_now <- FUND_DT[Factor_Date == lfd,
                           .(Ticker, GPA, PiotroskiF = as.numeric(PiotroskiF), Accrual)]
      fund_now <- fund_now[!is.na(GPA) | !is.na(PiotroskiF) | !is.na(Accrual)]
      if (nrow(fund_now) > 0) {
        stats <- merge(stats, fund_now, by = "Ticker", all.x = TRUE)
        stats[, z_q_gpa := fifelse(!is.na(GPA), z_safe(GPA), 0)]
        stats[, z_q_pio := fifelse(!is.na(PiotroskiF), z_safe(PiotroskiF), 0)]
        stats[, z_q_acc := fifelse(!is.na(Accrual), z_safe(-Accrual), 0)]
        stats[, z_quality := z_q_gpa + z_q_pio + z_q_acc]
        for (cc in c("GPA", "PiotroskiF", "Accrual", "z_q_gpa", "z_q_pio", "z_q_acc"))
          if (cc %in% names(stats)) stats[, (cc) := NULL]
      }
    }
  }

  # ── Factor 5: Value ──
  stats[, z_value := 0]
  if (HAS_DART) {
    avd <- sort(unique(FUND_DT$Factor_Date))
    vd <- avd[avd <= sig_d]
    if (length(vd) > 0) {
      lfd <- max(vd)
      val_now <- FUND_DT[Factor_Date == lfd & !is.na(OperatingCF),
                          .(Ticker, OCF = OperatingCF)]
      if (nrow(val_now) > 0) {
        stats <- merge(stats, val_now, by = "Ticker", all.x = TRUE)
        stats[!is.na(OCF) & !is.na(Close) & Close > 0,
              z_value := z_safe(OCF / Close)]
        if ("OCF" %in% names(stats)) stats[, OCF := NULL]
      }
    }
  }

  # ── Composite Score ──
  stats[, Score := w_vec["defense"]   * z_defense +
                   w_vec["consensus"] * z_consensus +
                   w_vec["momentum"]  * z_momentum +
                   w_vec["quality"]   * z_quality +
                   w_vec["value"]     * z_value]

  stats[!is.na(Sector), Score := Score - mean(Score, na.rm = TRUE), by = Sector]
  stats[, Date := sig_d]
  factor_list[[length(factor_list) + 1L]] <- stats[!is.na(Score), .(Date, Ticker, Score)]
  n_done <- n_done + 1L
}

FACTORS <- rbindlist(factor_list)
setorder(FACTORS, Date, -Score)
regime_log_dt <- rbindlist(regime_log, fill = TRUE)

for (col in c("TradingValue", "AvgTV20", "YM"))
  if (col %in% names(RAWDATA)) RAWDATA[, (col) := NULL]

cat(sprintf("[5F Engine] %d dates, %d skipped | %s scores\n",
            n_done, n_skipped, format(nrow(FACTORS), big.mark = ",")))
