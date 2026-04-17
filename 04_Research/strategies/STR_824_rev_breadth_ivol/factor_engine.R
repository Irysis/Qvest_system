#==============================================================================
# STR_824: Earnings Revision Breadth Confirmation + IdioVol
#
# Academic: Barber, Lehavy, McNichols & Trueman (2001)
#           "Can Investors Profit from the Prophets?"
#
# Signal:
#   - Revision Breadth = confirmed direction (sign(1m) == sign(3m))
#   - Confirmed strength = eps_chg_1m when direction matches
#   - Composite: 0.55 × rank(low_idiovol) + 0.30 × rank(confirmed_rev) + 0.15 × rank(sue)
#==============================================================================

cat("[factor_engine] STR_824: Revision Breadth + IdioVol...\n")
set.seed(42)

LOOKBACK   <- 252L
MIN_OBS    <- 200L
VOL_FLOOR_Q <- 0.05
W_CONF     <- if(!exists("W_CONF")) 0.30 else W_CONF
W_SUE_824  <- if(!exists("W_SUE_824")) 0.15 else W_SUE_824
W_IDIOVOL_824 <- if(!exists("W_IDIOVOL_824")) 0.55 else W_IDIOVOL_824
MIN_COVERAGE <- 3L

MACRO_HARD_THRESH <- if(exists("MACRO_HARD_THRESH")) MACRO_HARD_THRESH else 40L
BUDDHA_CASH_OUT   <- TRUE
REGIME_SCALE_SOFT <- 0.5

macro_regime_dt <- as.data.table(read_parquet(FRED_REGIME_CACHE))
macro_regime_dt[, YM := substr(Date, 1, 7)]
setkey(macro_regime_dt, YM)

source(file.path(DATA_DIR, "consensus_parser.R"))
cs <- consensus_load(
  metrics   = c("eps_chg_1m", "eps_chg_3m", "sue", "coverage"),
  date_from = "2001-01-01"
)
cat(sprintf("  Consensus (breadth): %s rows\n", format(nrow(cs), big.mark=",")))

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

factor_list <- list()
n_done <- 0; n_skipped <- 0

for (sig_d in quarterly_dates) {
  sig_d <- as.Date(sig_d)
  sig_ym <- format(sig_d, "%Y-%m")
  idx <- which(all_dates == sig_d)

  macro_row <- macro_regime_dt[YM == sig_ym]
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
  regime_scale <- if (risk_s >= (if(exists("REGIME_SOFT_THRESH")) REGIME_SOFT_THRESH else 10L)) REGIME_SCALE_SOFT else 1.0

  lb_start <- all_dates[max(1, idx - LOOKBACK)]
  window <- RAWDATA[Date >= lb_start & Date <= sig_d]

  lv <- window[!is.na(Ret) & !is.na(Close), {
    n <- .N
    if (n < MIN_OBS) {
      list(idiovol=NA_real_, avg_vol=NA_real_, ret_12m=NA_real_)
    } else {
      bm_w <- bm_daily[Date >= lb_start & Date <= sig_d]
      m <- merge(data.table(Date=Date, Ret=Ret), bm_w, by="Date", all.x=TRUE)
      m <- m[!is.na(Ret) & !is.na(BM_Ret)]
      if (nrow(m) < MIN_OBS) {
        list(idiovol=NA_real_, avg_vol=mean(tail(Vol,20),na.rm=T),
             ret_12m=prod(1+Ret,na.rm=T)-1)
      } else {
        fit <- .lm.fit(cbind(1, m$BM_Ret), m$Ret)
        list(idiovol=sd(fit$residuals), avg_vol=mean(tail(Vol,20),na.rm=T),
             ret_12m=prod(1+Ret,na.rm=T)-1)
      }
    }
  }, by = Ticker]
  lv <- lv[!is.na(idiovol)]

  lv[, vol_rank := frank(avg_vol, ties.method="average") / .N]
  lv <- lv[vol_rank > VOL_FLOOR_Q & ret_12m > -0.40]
  if (nrow(lv) < 30) next

  # Merge consensus
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

  # Revision Breadth Confirmation
  # confirmed_rev = eps_chg_1m when sign matches 3m direction, else damped
  lv[!is.na(eps_chg_1m) & !is.na(eps_chg_3m), confirmed_rev := fifelse(
    sign(eps_chg_1m) == sign(eps_chg_3m),
    eps_chg_1m * 1.5,   # amplify confirmed direction
    eps_chg_1m * 0.3    # dampen contradicted direction
  )]
  # Only 1m available: use raw
  lv[!is.na(eps_chg_1m) & is.na(eps_chg_3m), confirmed_rev := eps_chg_1m]

  # Scoring
  lv[, rank_ivol := frank(-idiovol, ties.method = "average") / .N]

  has_conf <- !is.na(lv$confirmed_rev)
  has_sue <- !is.na(lv$sue)

  if (sum(has_conf) >= 15) {
    lv[has_conf, rank_conf := frank(confirmed_rev, ties.method="average") / sum(has_conf)]
    lv[!has_conf, rank_conf := 0.5]
  } else {
    lv[, rank_conf := 0.5]
  }

  if (sum(has_sue) >= 15) {
    lv[has_sue, rank_sue := frank(sue, ties.method="average") / sum(has_sue)]
    lv[!has_sue, rank_sue := 0.5]
  } else {
    lv[, rank_sue := 0.5]
  }

  lv[, Score := (W_IDIOVOL_824 * rank_ivol + W_CONF * rank_conf +
                 W_SUE_824 * rank_sue) * regime_scale]

  sector_info <- unique(RAWDATA[Date == sig_d, .(Ticker, Sector)])
  lv <- merge(lv, sector_info, by = "Ticker", all.x = TRUE)
  lv[, Score := Score - mean(Score, na.rm = TRUE), by = Sector]

  lv[, Date := sig_d]
  factor_list[[length(factor_list) + 1]] <- lv[!is.na(Score), .(Date, Ticker, Score)]
  n_done <- n_done + 1

  if (n_done %% 10 == 0)
    cat(sprintf("  [%d/%d skip] %s — %d tickers (%d confirmed)\n",
                n_done, n_skipped, sig_d, nrow(lv), sum(has_conf)))
}

FACTORS <- rbindlist(factor_list)
setorder(FACTORS, Date, -Score)
if ("YM" %in% names(RAWDATA)) RAWDATA[, YM := NULL]

cat(sprintf("[factor_engine] FACTORS: %d rows | %d dates | %d skipped | %d tickers\n",
            nrow(FACTORS), uniqueN(FACTORS$Date), n_skipped, uniqueN(FACTORS$Ticker)))
