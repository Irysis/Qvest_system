## STR_943: OtherCorp + EPS Change (1M + 3M)
## Hypothesis: Short-term EPS revision (eps_chg_1m, eps_chg_3m) captures
## analyst sentiment change. When combined with insider buying = dual signal.
## Data: investor_wide (OtherCorp) + consensus (eps_chg_1m, eps_chg_3m) + RAWDATA
set.seed(42); options(scipen=999)

STRATEGY_NAME <- "STR_943"
STRATEGY_DESC <- "OtherCorp + EPS Change Momentum"

SCRIPT_DIR <- tryCatch(dirname(sys.frame(1)$ofile), error = function(e) getwd())
INFRA_DIR  <- file.path(SCRIPT_DIR, "..", "..", "..", "02_Infrastructure")
source(file.path(INFRA_DIR, "config.R"))
source(file.path(INFRA_DIR, "backtest_harness.R"))
source(file.path(TELEGRAM_DIR, "telegram_notify.R"))
cat(sprintf("=== %s: %s ===\n\n", STRATEGY_NAME, STRATEGY_DESC))

res <- load_rawdata(use_cache = TRUE)
RAWDATA <- res$RAWDATA; BM_DT <- res$BM_DT

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
  if (nrow(stats) < 30) next

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
  if (n_done %% 20 == 0) cat(sprintf("  [%d] %s — %d tickers\n", n_done, sig_d, nrow(stats)))
}

FACTORS <- rbindlist(factor_list); setorder(FACTORS, Date, -Score)
if ("YM" %in% names(RAWDATA)) RAWDATA[, YM := NULL]
cat(sprintf("[factor] %d rows | %d dates | %d skipped\n", nrow(FACTORS), uniqueN(FACTORS$Date), n_skipped))
sim_base <- run_monthly_simulation(RAWDATA, BM_DT, FACTORS, n_holdings=20L, commission=0.0015, weight_method="equal", vol_target=0.18, vol_lookback=60L)
raw_ret <- as.numeric(sim_base$strategy_xts); raw_dates <- as.Date(index(sim_base$strategy_xts)); n_f <- length(raw_ret)
nav_dd <- cumprod(1+raw_ret); dd_pct <- 1-nav_dd/cummax(nav_dd)
dd_exp <- ifelse(dd_pct<=0.04,1.0,ifelse(dd_pct>=0.35,0.30,pmax(0.30,1.0-(dd_pct-0.04)/0.31*0.70)))
after_dd <- raw_ret * dd_exp
mrs_monthly <- macro_regime_dt[, .(YM, Macro_Risk_Score)][!duplicated(YM)]; daily_ym <- format(raw_dates, "%Y-%m"); soft_mrs <- numeric(n_f)
for (i in seq_len(n_f)) { mrs_val <- mrs_monthly[YM==daily_ym[i], Macro_Risk_Score]; if (length(mrs_val)==0) mrs_val <- 0; soft_mrs[i] <- if (mrs_val < 15) 1.0 else if (mrs_val >= 30) 0.30 else 1.0-(mrs_val-15)/15*0.70 }
combined_ret <- after_dd * soft_mrs; combined_xts <- xts(combined_ret, order.by=raw_dates); names(combined_xts) <- "Strategy"
sim <- sim_base; sim$strategy_xts <- combined_xts; sim$bm_xts <- sim_base$bm_xts[raw_dates]
sim$DAILY_NAV_DT <- data.table(Date=raw_dates, NAV=cumprod(1+combined_ret)*1e8, Strategy_Ret=combined_ret)
perf <- summarise_perf(combined_xts, STRATEGY_NAME)
cat(sprintf("\n  === %s ===\n  CAGR=%.2f%% | Sharpe=%.3f | MDD=%.1f%%\n", STRATEGY_NAME, perf$CAGR, perf$Sharpe, perf$MDD))
out_dir <- file.path(SCRIPT_DIR, "output"); dir.create(out_dir, showWarnings=FALSE, recursive=TRUE)
saveRDS(sim, file.path(SCRIPT_DIR, "sim_result.rds"))
generate_charts(sim, output_dir=out_dir, strategy_name=sprintf("%s: %s", STRATEGY_NAME, STRATEGY_DESC))
source(file.path(INFRA_DIR, "strategy_analyzer.R")); run_analysis(sim, FACTORS, RAWDATA, BM_DT, out_dir, strategy_name=STRATEGY_NAME)
QEPM_AUTO_COMMIT <- TRUE; source(file.path(INFRA_DIR, "hurdle_gate.R"))
hurdle <- run_hurdle_gate(sim_result=sim, strategy_name=STRATEGY_NAME, output_dir=out_dir)
tryCatch({ hr <- jsonlite::fromJSON(file.path(out_dir,"hurdle_result.json")); tg_strategy_result_with_chart(STRATEGY_NAME, hr, out_dir) }, error=function(e) cat("[TG]",e$message,"\n"))
cat(sprintf("\n[%s] Complete.\n", STRATEGY_NAME))
