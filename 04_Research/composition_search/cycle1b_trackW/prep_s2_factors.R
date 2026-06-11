# =============================================================================
# prep_s2_factors.R — Track W S2 substrate: STR_943_oc_eps_chg FACTORS panel
#   regenerated VERBATIM from 04_Research/strategies/STR_943_oc_eps_chg/run_all.R
#   lines 17-99 (signal generation incl. macro skip gates + regime_scale +
#   sector demean — substrate identity as-is). Deviations (documented):
#     1. monthly_dates restricted to >= 2002-01-01 (registered substrate period:
#        registry 2002-03~; current RAWDATA cache extends to 1990 but consensus/
#        investor inputs absent pre-2002 — module identity = registry period)
#     2. NO vol_target / DD / soft-MRS overlay (prereg: weighting axis isolated)
#     3. ADDED ADV(20d, t-1) >= 2e8 KRW liquidity filter at selection
#        (immutable Production Constraint; original used share-volume percentile only)
# =============================================================================
set.seed(42); options(scipen = 999)
suppressPackageStartupMessages({ library(data.table); library(arrow); library(xts) })

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
TRACKW_DIR <- file.path(PROJECT_ROOT, "04_Research/composition_search/cycle1b_trackW")
INT_DIR <- file.path(TRACKW_DIR, "intermediate")
dir.create(INT_DIR, showWarnings = FALSE, recursive = TRUE)

source(file.path(PROJECT_ROOT, "02_Infrastructure/config.R"))
suppressMessages(source(file.path(PROJECT_ROOT, "02_Infrastructure/backtest_harness.R")))

month_end <- function(d) seq(as.Date(format(d, "%Y-%m-01")), by = "1 month", length.out = 2)[2] - 1L

res <- load_rawdata(use_cache = TRUE)
RAWDATA <- res$RAWDATA; BM_DT <- res$BM_DT; rm(res); gc(verbose = FALSE)

# ── VERBATIM signal generation (STR_943 run_all.R L20-99) ────────────────────
inv <- as.data.table(arrow::read_parquet(file.path(CACHE_DIR, "investor_stock", "investor_wide.parquet")))
inv[, Date := as.Date(Date)]; setorder(inv, Ticker, Date)
inv[, oc_40d := frollsum(OtherCorp, n=40L, align="right", na.rm=TRUE), by=Ticker]
inv[, oc_nz := as.numeric(abs(OtherCorp) > 0)]
inv[, oc_active := frollsum(oc_nz, n=40L, align="right", na.rm=TRUE), by=Ticker]; inv[, oc_nz := NULL]

eps1m <- as.data.table(arrow::read_parquet(file.path(CACHE_DIR, "consensus", "eps_chg_1m.parquet")))[, Date := as.Date(Date)]
eps3m <- as.data.table(arrow::read_parquet(file.path(CACHE_DIR, "consensus", "eps_chg_3m.parquet")))[, Date := as.Date(Date)]

MACRO_HARD_THRESH <- 30L; REGIME_SOFT_THRESH <- 15L; REGIME_SCALE_SOFT <- 0.5; BUDDHA_CASH_OUT <- TRUE
macro_regime_dt <- as.data.table(arrow::read_parquet(FRED_REGIME_CACHE))
macro_regime_dt[, YM := substr(Date, 1, 7)]; setkey(macro_regime_dt, YM)

LOOKBACK <- 252L; MIN_OBS <- 200L; VOL_FLOOR_Q <- 0.05
W_IVOL <- 0.35; W_OC <- 0.25; W_EPS1M <- 0.20; W_EPS3M <- 0.20

setorder(RAWDATA, Ticker, Date); RAWDATA[, YM := format(Date, "%Y-%m")]
all_signal_dates <- sort(RAWDATA[, .(Signal_Date = max(Date)), by = YM]$Signal_Date)
all_dates <- sort(unique(RAWDATA$Date))
monthly_dates <- all_signal_dates[all_signal_dates >= all_dates[min(LOOKBACK+1L, length(all_dates))]]
monthly_dates <- monthly_dates[monthly_dates >= as.Date("2002-01-01")]   # deviation 1 (doc'd)
bm_daily <- unique(RAWDATA[, .(Date, BM_Ret)]); setorder(bm_daily, Date)
factor_list <- list(); n_done <- 0L; n_skipped <- 0L

for (sig_d in monthly_dates) {
  sig_d <- as.Date(sig_d); sig_ym <- format(sig_d, "%Y-%m")
  idx <- which(all_dates == sig_d); if (length(idx)==0) next
  macro_row <- macro_regime_dt[YM == sig_ym]
  buddha <- if (nrow(macro_row)>0 && !is.na(macro_row$Buddha_Mode[1])) macro_row$Buddha_Mode[1] else FALSE
  risk_s <- if (nrow(macro_row)>0 && !is.na(macro_row$Macro_Risk_Score[1])) macro_row$Macro_Risk_Score[1] else 0
  vix_r <- if (nrow(macro_row)>0 && !is.na(macro_row$VIX_Regime[1])) macro_row$VIX_Regime[1] else "normal"
  if ((BUDDHA_CASH_OUT && buddha) || risk_s >= MACRO_HARD_THRESH || vix_r %in% c("extreme","crisis")) { n_skipped <- n_skipped+1; next }
  regime_scale <- if (risk_s >= REGIME_SOFT_THRESH) REGIME_SCALE_SOFT else 1.0

  lb_start <- all_dates[max(1, idx-LOOKBACK)]
  window <- RAWDATA[Date >= lb_start & Date <= sig_d]
  stats <- window[!is.na(Ret) & !is.na(Close), {
    n <- .N
    if (n < MIN_OBS) list(idiovol=NA_real_, avg_vol=NA_real_, ret_12m=NA_real_) else {
      bm_w <- bm_daily[Date >= lb_start & Date <= sig_d]
      m <- merge(data.table(Date=Date, Ret=Ret), bm_w, by="Date", all.x=TRUE)
      m <- m[!is.na(Ret) & !is.na(BM_Ret)]
      if (nrow(m) < MIN_OBS) list(idiovol=NA_real_, avg_vol=mean(tail(Vol,20),na.rm=T), ret_12m=prod(1+Ret,na.rm=T)-1)
      else { fit <- .lm.fit(cbind(1, m$BM_Ret), m$Ret)
        list(idiovol=sd(fit$residuals), avg_vol=mean(tail(Vol,20),na.rm=T), ret_12m=prod(1+Ret,na.rm=T)-1) }
    }
  }, by = Ticker]
  stats <- stats[!is.na(idiovol)]
  stats[, vol_rank := frank(avg_vol, ties.method="average") / .N]
  stats <- stats[vol_rank > VOL_FLOOR_Q & ret_12m > -0.40]
  if (nrow(stats) < 30) { n_skipped <- n_skipped+1; next }

  flow_snap <- inv[Date == sig_d, .(Ticker, oc_40d, oc_active)]
  mcap_snap <- RAWDATA[Date == sig_d, .(Ticker, Size)]
  flow_snap <- merge(flow_snap, mcap_snap, by="Ticker", all.x=TRUE)
  flow_snap[, oc_norm := fifelse(oc_active >= 5 & Size > 0, oc_40d / Size, NA_real_)]

  e1 <- eps1m[Date >= (sig_d-7) & Date <= sig_d]; e3 <- eps3m[Date >= (sig_d-7) & Date <= sig_d]
  if (nrow(e1)>0) { el1 <- e1[order(Date)][,.SD[.N],by=Ticker]; stats <- merge(stats, el1[,.(Ticker,eps_chg_1m)], by="Ticker", all.x=T) } else stats[,eps_chg_1m:=NA_real_]
  if (nrow(e3)>0) { el3 <- e3[order(Date)][,.SD[.N],by=Ticker]; stats <- merge(stats, el3[,.(Ticker,eps_chg_3m)], by="Ticker", all.x=T) } else stats[,eps_chg_3m:=NA_real_]
  stats <- merge(stats, flow_snap[, .(Ticker, oc_norm)], by="Ticker", all.x=TRUE)

  stats[, rank_ivol := frank(-idiovol, ties.method="average") / .N]
  has_oc <- sum(!is.na(stats$oc_norm)) >= 15
  if (has_oc) { stats[!is.na(oc_norm), rank_oc := frank(oc_norm, ties.method="average") / sum(!is.na(oc_norm))]; stats[is.na(oc_norm), rank_oc := 0.5] } else stats[, rank_oc := 0.5]
  has_e1 <- sum(!is.na(stats$eps_chg_1m)) >= 15
  if (has_e1) { stats[!is.na(eps_chg_1m), rank_e1 := frank(eps_chg_1m, ties.method="average") / sum(!is.na(eps_chg_1m))]; stats[is.na(eps_chg_1m), rank_e1 := 0.5] } else stats[, rank_e1 := 0.5]
  has_e3 <- sum(!is.na(stats$eps_chg_3m)) >= 15
  if (has_e3) { stats[!is.na(eps_chg_3m), rank_e3 := frank(eps_chg_3m, ties.method="average") / sum(!is.na(eps_chg_3m))]; stats[is.na(eps_chg_3m), rank_e3 := 0.5] } else stats[, rank_e3 := 0.5]

  stats[, Score := (W_IVOL * rank_ivol + W_OC * rank_oc + W_EPS1M * rank_e1 + W_EPS3M * rank_e3) * regime_scale]
  sector_info <- unique(RAWDATA[Date == sig_d, .(Ticker, Sector)])
  stats <- merge(stats, sector_info, by="Ticker", all.x=TRUE)
  stats[!is.na(Sector), Score := Score - mean(Score, na.rm=TRUE), by=Sector]
  stats[, Date := sig_d]
  factor_list[[length(factor_list)+1]] <- stats[!is.na(Score), .(Date, Ticker, Score)]
  n_done <- n_done+1
  if (n_done %% 20 == 0) cat(sprintf("  [%d] %s - %d tickers\n", n_done, as.character(sig_d), nrow(stats)))
}

FACTORS <- rbindlist(factor_list); setorder(FACTORS, Date, -Score)
cat(sprintf("[S2 factors] %d rows | %d dates | %d skipped (cash months)\n",
            nrow(FACTORS), uniqueN(FACTORS$Date), n_skipped))
write_parquet(FACTORS, file.path(INT_DIR, "s2_factors.parquet"))

# ── deviation 3: ADV(20d Close*Vol, t-1 lag) >= 2e8 then top-20 ──────────────
RAWDATA[, TradingValue := Close * Vol]
RAWDATA[, AvgTV20 := shift(frollmean(TradingValue, n = 20L, align = "right"), n = 1L, type = "lag"),
        by = Ticker]
liq <- RAWDATA[Date %in% unique(FACTORS$Date), .(Date, Ticker, AvgTV20)]
F2 <- merge(FACTORS, liq, by = c("Date","Ticker"), all.x = TRUE)
F2 <- F2[!is.na(AvgTV20) & AvgTV20 >= 2e8]
s2_sel <- F2[, .SD[order(-Score)][1:min(20, .N)], by = Date]
s2_sel[, w_idx := as.Date(vapply(Date, function(d) as.character(month_end(d)), character(1)))]
s2_sel[, r_idx := as.Date(vapply(Date, function(d)
        as.character(month_end(seq(as.Date(format(d, "%Y-%m-01")), by = "1 month", length.out = 2)[2])), character(1)))]

# forward 1m return (calendar month m+1 compound, asset-level prep)
RET <- RAWDATA[, .(Date, Ticker, Ret)]
RET[, ym := format(Date, "%Y-%m")]
mret <- RET[!is.na(Ret), .(Ret_1m = prod(1 + Ret) - 1), by = .(Ticker, ym)]
s2_sel[, ym_fwd := format(r_idx, "%Y-%m")]
s2_sel <- merge(s2_sel, mret, by.x = c("Ticker","ym_fwd"), by.y = c("Ticker","ym"), all.x = TRUE)
n_na2 <- s2_sel[is.na(Ret_1m), .N]
s2_sel[is.na(Ret_1m), Ret_1m := 0]
s2_out <- s2_sel[, .(Date, w_idx, r_idx, Ticker, Score, Ret_1m)]
setorder(s2_out, Date, -Score)
write_parquet(s2_out, file.path(INT_DIR, "s2_sel.parquet"))

# month grid INCLUDING macro-skip cash months (substrate identity: cash-out)
first_m <- format(min(s2_out$Date), "%Y-%m"); last_m <- format(max(s2_out$Date), "%Y-%m")
mseq <- seq(as.Date(paste0(first_m, "-01")), as.Date(paste0(last_m, "-01")), by = "1 month")
s2_grid <- data.table(w_idx = as.Date(vapply(mseq, function(d) as.character(month_end(d)), character(1))),
                      r_idx = as.Date(vapply(mseq, function(d)
                        as.character(month_end(seq(d, by = "1 month", length.out = 2)[2])), character(1))))
fwrite(s2_grid, file.path(INT_DIR, "s2_grid.csv"))
n_cash <- nrow(s2_grid) - uniqueN(s2_out$w_idx)
cat(sprintf("[prep] S2: %d rows | invested months %d | grid months %d (cash %d) | NA Ret_1m->0: %d | %s ~ %s\n",
            nrow(s2_out), uniqueN(s2_out$w_idx), nrow(s2_grid), n_cash, n_na2,
            as.character(min(s2_out$Date)), as.character(max(s2_out$Date))))

tk_s2 <- sort(unique(s2_out$Ticker))
ret_s2 <- RET[Ticker %in% tk_s2 & Date >= as.Date("1999-01-01"), .(Date, Ticker, Ret)]
write_parquet(ret_s2, file.path(INT_DIR, "ret_s2.parquet"))
cat(sprintf("[prep] ret slice s2: %d rows (%d tickers)\n", nrow(ret_s2), length(tk_s2)))
cat("PREP_S2_OK\n")
