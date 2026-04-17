## STR_930: OtherCorp + Foreign Agreement + ESBR Triple Confirmation
## Hypothesis: Triple confirmation — insider demand (OtherCorp) + foreign demand +
##   analyst earnings surprise consensus (ESBR) = multi-source demand convergence.
## Signal weights: 35% IdioVol + 30% flow agreement (OC+FO) + 35% ESBR
## Expected: Grade A, FF5alpha 10-12%, SR 1.3-1.5
## PIT: C2 flow t-1 sig_date snapshot | C9 DD/VT 1-day lag | C13 Z_Score_Aligned
## Academic: Grinblatt & Keloharju (2000); Ke & Petroni (2004)
## Stage: S1 artifact present (s1_construction_STR_930_oc_foreign_esbr.json)
cat("=== STR_930: OtherCorp + Foreign + ESBR Triple Confirm ===\n\n")
set.seed(42); options(scipen = 999)

STRATEGY_NAME <- "STR_930"
STRATEGY_DESC <- "OtherCorp + Foreign Agreement + ESBR Triple Confirmation"

SCRIPT_DIR <- tryCatch(dirname(sys.frame(1)$ofile), error = function(e) getwd())
INFRA_DIR  <- file.path(SCRIPT_DIR, "..", "..", "..", "02_Infrastructure")
source(file.path(INFRA_DIR, "config.R"))
source(file.path(INFRA_DIR, "backtest_harness.R"))
source(file.path(TELEGRAM_DIR, "telegram_notify.R"))

LIQ_THRESHOLD <- 2e8; N_HOLDINGS <- 20L
LOOKBACK <- 252L; MIN_OBS <- 200L; VOL_FLOOR_Q <- 0.05
VOL_TARGET <- 0.18; FLOW_WINDOW <- 40L
W_IVOL <- 0.35; W_FLOW <- 0.30; W_ESBR <- 0.35
DD_BRAKE_START <- 0.04; DD_BRAKE_FULL <- 0.35; MIN_EXPOSURE <- 0.30
MRS_LOW <- 15; MRS_HIGH <- 30; MRS_MIN_EXP <- 0.30
BUDDHA_CASH_OUT <- TRUE; MACRO_HARD_THRESH <- 30L

# Phase 1: RAWDATA (use_cache=TRUE, 1회)
cat("[Phase 1] Loading RAWDATA...\n")
res          <- load_rawdata(use_cache = TRUE)
RAWDATA      <- res$RAWDATA; BM_DT <- res$BM_DT
RAWDATA_ORIG <- copy(RAWDATA); BM_DT_ORIG <- copy(BM_DT)
cat(sprintf("  RAWDATA: %d rows | %s ~ %s\n",
  nrow(RAWDATA), as.character(min(RAWDATA$Date)), as.character(max(RAWDATA$Date))))

# Phase 2: Bulk-preload via data_loader.R (parquet 로드 전담)
# OPT-1: parquet 호출은 data_loader.R 에만 존재. run_all.R 내 없음.
cat("[Phase 2] Sourcing data_loader.R...\n")
source(file.path(SCRIPT_DIR, "data_loader.R"))
# 결과: inv_preloaded, esbr_monthly, macro_regime_dt 전역 등록됨

mcap_all <- unique(RAWDATA_ORIG[, .(Date, Ticker, Size)])
setkey(mcap_all, Date, Ticker)
mrs_monthly <- macro_regime_dt[, .(YM, Macro_Risk_Score)][!duplicated(YM)]

# Phase 3: Monthly signal construction via lapply
cat("[Phase 3] Computing factor signals...\n")
setorder(RAWDATA, Ticker, Date); RAWDATA[, YM := format(Date, "%Y-%m")]
all_signal_dates <- sort(RAWDATA[, .(Signal_Date = max(Date)), by = YM]$Signal_Date)
all_dates        <- sort(unique(RAWDATA$Date))
monthly_dates    <- all_signal_dates[
  all_signal_dates >= all_dates[min(LOOKBACK + 1L, length(all_dates))]
]
bm_daily <- unique(RAWDATA[, .(Date, BM_Ret)]); setorder(bm_daily, Date)

.build_one_month <- function(sig_d) {
  sig_d  <- as.Date(sig_d); sig_ym <- format(sig_d, "%Y-%m")
  idx    <- which(all_dates == sig_d); if (length(idx) == 0L) return(NULL)
  macro_row <- macro_regime_dt[YM == sig_ym]
  buddha <- if (nrow(macro_row) > 0 && !is.na(macro_row$Buddha_Mode[1])) macro_row$Buddha_Mode[1] else FALSE
  risk_s <- if (nrow(macro_row) > 0 && !is.na(macro_row$Macro_Risk_Score[1])) macro_row$Macro_Risk_Score[1] else 0
  vix_r  <- if (nrow(macro_row) > 0 && !is.na(macro_row$VIX_Regime[1])) macro_row$VIX_Regime[1] else "normal"
  if ((BUDDHA_CASH_OUT && buddha) || risk_s >= MACRO_HARD_THRESH ||
      vix_r %in% c("extreme", "crisis")) return(NULL)
  lb_start <- all_dates[max(1L, idx - LOOKBACK)]
  window   <- RAWDATA[Date >= lb_start & Date <= sig_d]
  stats <- window[!is.na(Ret), {
    n <- .N
    if (n < MIN_OBS) { list(idiovol=NA_real_, avg_vol=NA_real_, ret_12m=NA_real_) } else {
      bm_w <- bm_daily[Date >= lb_start & Date <= sig_d]
      m    <- merge(data.table(Date=Date, Ret=Ret), bm_w, by="Date", all.x=TRUE)
      m    <- m[!is.na(Ret) & !is.na(BM_Ret)]
      if (nrow(m) < MIN_OBS) {
        list(idiovol=NA_real_, avg_vol=mean(tail(Vol,20L),na.rm=TRUE), ret_12m=prod(1+Ret,na.rm=TRUE)-1)
      } else {
        fit <- .lm.fit(cbind(1, m$BM_Ret), m$Ret)
        list(idiovol=sd(fit$residuals), avg_vol=mean(tail(Vol,20L),na.rm=TRUE), ret_12m=prod(1+Ret,na.rm=TRUE)-1)
      }
    }
  }, by=Ticker]
  stats <- stats[!is.na(idiovol)]
  stats[, vol_rank := frank(avg_vol, ties.method="average") / .N]
  stats <- stats[vol_rank > VOL_FLOOR_Q & ret_12m > -0.40]
  if (nrow(stats) < 30L) return(NULL)
  # C2: rolling 40d pre-computed in data_loader.R; sig_d snapshot = t-1 guaranteed
  flow_snap <- inv_preloaded[Date == sig_d, .(Ticker, oc_40d, fo_40d, oc_active, fo_active)]
  size_snap <- mcap_all[Date == sig_d, .(Ticker, Size)]
  flow_snap <- merge(flow_snap, size_snap, by="Ticker", all.x=TRUE)
  flow_snap[, oc_norm := fifelse(oc_active>=5L & !is.na(Size) & Size>0, oc_40d/Size, NA_real_)]
  flow_snap[, fo_norm := fifelse(fo_active>=5L & !is.na(Size) & Size>0, fo_40d/Size, NA_real_)]
  flow_snap[, flow_agree := fifelse(
    !is.na(oc_norm)&!is.na(fo_norm)&oc_norm>0&fo_norm>0, (oc_norm+fo_norm)/2,
    fifelse(!is.na(oc_norm)&!is.na(fo_norm), (oc_norm+fo_norm)/2*0.7,
      fifelse(!is.na(oc_norm), oc_norm*0.6, fifelse(!is.na(fo_norm), fo_norm*0.4, NA_real_))))]
  # C14: esbr_monthly[YM == sig_ym] — sig_ym 이전 데이터만
  esbr_snap <- esbr_monthly[YM == sig_ym]
  if (nrow(esbr_snap) == 0L) {
    prev_ym   <- format(as.Date(paste0(sig_ym,"-01"))-1L, "%Y-%m")
    esbr_snap <- esbr_monthly[YM == prev_ym]
  }
  stats <- merge(stats, flow_snap[, .(Ticker, flow_agree)], by="Ticker", all.x=TRUE)
  if (nrow(esbr_snap) > 0L) {
    stats <- merge(stats, esbr_snap[, .(Ticker, esbr_val)], by="Ticker", all.x=TRUE)
  } else { stats[, esbr_val := NA_real_] }
  stats[, rank_ivol := frank(-idiovol, ties.method="average") / .N]
  has_flow <- sum(!is.na(stats$flow_agree)) >= 15L
  if (has_flow) {
    stats[!is.na(flow_agree), rank_flow := frank(flow_agree,ties.method="average")/sum(!is.na(flow_agree))]
    stats[is.na(flow_agree), rank_flow := 0.5]
  } else { stats[, rank_flow := 0.5] }
  has_esbr <- sum(!is.na(stats$esbr_val)) >= 15L
  if (has_esbr) {
    stats[!is.na(esbr_val), rank_esbr := frank(esbr_val,ties.method="average")/sum(!is.na(esbr_val))]
    stats[is.na(esbr_val), rank_esbr := 0.5]
  } else { stats[, rank_esbr := 0.5] }
  stats[, Score := W_IVOL*rank_ivol + W_FLOW*rank_flow + W_ESBR*rank_esbr]
  sector_snap <- unique(RAWDATA[Date==sig_d, .(Ticker, Sector)])
  stats <- merge(stats, sector_snap, by="Ticker", all.x=TRUE)
  stats[!is.na(Sector), Score := Score - mean(Score, na.rm=TRUE), by=Sector]
  stats[, Date := sig_d]
  stats[!is.na(Score), .(Date, Ticker, Score)]
}

factor_list <- lapply(monthly_dates, .build_one_month)
factor_list <- factor_list[!sapply(factor_list, is.null)]
n_skipped   <- length(monthly_dates) - length(factor_list)
FACTORS     <- rbindlist(factor_list); setorder(FACTORS, Date, -Score)
if ("YM" %in% names(RAWDATA)) RAWDATA[, YM := NULL]
cat(sprintf("[factor] %d rows | %d dates | %d skipped\n",
  nrow(FACTORS), uniqueN(FACTORS$Date), n_skipped))

# Phase 4: Liquidity Filter
cat("[Phase 4] Applying liquidity filter...\n")
RAWDATA_LIQ <- copy(RAWDATA_ORIG)
RAWDATA_LIQ[, TradeVal := Close * Vol]; setorder(RAWDATA_LIQ, Ticker, Date)
RAWDATA_LIQ[, AvgTV_20d := frollmean(TradeVal, n=20L, align="right", na.rm=TRUE), by=Ticker]
RAWDATA_LIQ[, YM := format(Date, "%Y-%m")]
liq_monthly <- RAWDATA_LIQ[, .(AvgTradeVal=tail(AvgTV_20d[!is.na(AvgTV_20d)],1L)), by=.(YM,Ticker)]
setkey(liq_monthly, YM, Ticker); FACTORS[, YM := format(Date, "%Y-%m")]
fac_dates <- sort(unique(FACTORS$Date))
filtered_list <- lapply(fac_dates, function(dt) {
  dt2 <- as.Date(dt); ym2 <- format(dt2, "%Y-%m")
  fd  <- FACTORS[Date==dt2]; lm2 <- liq_monthly[YM==ym2]
  if (nrow(lm2) > 0L) { liq <- lm2[AvgTradeVal >= LIQ_THRESHOLD, Ticker]; fd <- fd[Ticker %in% liq] }
  if (nrow(fd) >= N_HOLDINGS) fd else NULL
})
filtered_list <- filtered_list[!sapply(filtered_list, is.null)]
FACTORS <- rbindlist(filtered_list); FACTORS[, YM := NULL]
setorder(FACTORS, Date, -Score)
cat(sprintf("  After liq filter: %d rows | %d dates\n", nrow(FACTORS), uniqueN(FACTORS$Date)))
rm(RAWDATA_LIQ, liq_monthly); gc()

# Phase 5: Monthly Simulation
cat("[Phase 5] Running monthly simulation...\n")
sim_base <- run_monthly_simulation(
  copy(RAWDATA_ORIG), copy(BM_DT_ORIG), FACTORS,
  n_holdings=N_HOLDINGS, weight_method="equal", commission=0.0015,
  buffer_zone=list(keep_n=40L, entry_n=20L), vol_target=0.25, vol_lookback=60L
)

# Phase 6: VT + DD Brake + Soft MRS (C9: 1-day lag)
cat("[Phase 6] Applying VT + DD Brake + Soft MRS...\n")
raw_ret   <- as.numeric(sim_base$strategy_xts)
raw_dates <- as.Date(index(sim_base$strategy_xts)); n_f <- length(raw_ret)
port_vol     <- zoo::rollapply(raw_ret, width=60L, FUN=sd, fill=NA, align="right") * sqrt(252)
vt_scale     <- ifelse(is.na(port_vol)|port_vol<0.01, 1.0, pmin(1.0, VOL_TARGET/port_vol))
vt_scale_lag <- c(1.0, head(vt_scale, -1L))   # C9 VT lag
after_vt     <- raw_ret * vt_scale_lag
nav_vt <- cumprod(1+after_vt); dd_pct <- 1 - nav_vt / cummax(nav_vt)
dd_exp <- ifelse(dd_pct<=DD_BRAKE_START, 1.0, ifelse(dd_pct>=DD_BRAKE_FULL, MIN_EXPOSURE,
  pmax(MIN_EXPOSURE, 1.0-(dd_pct-DD_BRAKE_START)/(DD_BRAKE_FULL-DD_BRAKE_START)*(1.0-MIN_EXPOSURE))))
dd_exp_lag <- c(1.0, head(dd_exp, -1L))       # C9 DD lag
after_dd   <- after_vt * dd_exp_lag
daily_ym_f <- format(raw_dates, "%Y-%m")
soft_mrs   <- vapply(seq_len(n_f), function(i) {
  mv <- mrs_monthly[YM == daily_ym_f[i], Macro_Risk_Score]
  if (length(mv)==0L) mv <- 0
  if (mv < MRS_LOW) 1.0 else if (mv >= MRS_HIGH) MRS_MIN_EXP else
    1.0-(mv-MRS_LOW)/(MRS_HIGH-MRS_LOW)*(1.0-MRS_MIN_EXP)
}, numeric(1))
combined_ret <- after_dd * soft_mrs
combined_xts <- xts(combined_ret, order.by=raw_dates); names(combined_xts) <- "Strategy"
sim <- sim_base; sim$strategy_xts <- combined_xts; sim$bm_xts <- sim_base$bm_xts[raw_dates]
sim$DAILY_NAV_DT <- data.table(Date=raw_dates, NAV=cumprod(1+combined_ret)*1e8, Strategy_Ret=combined_ret)

# Phase 7: Performance + Output + Hurdle
perf <- summarise_perf(combined_xts, STRATEGY_NAME)
cat(sprintf("\n  === %s ===\n  CAGR=%.2f%% | Sharpe=%.3f | MDD=%.1f%%\n",
  STRATEGY_NAME, perf$CAGR, perf$Sharpe, perf$MDD))
out_dir <- file.path(SCRIPT_DIR, "output")
dir.create(out_dir, showWarnings=FALSE, recursive=TRUE)
saveRDS(sim, file.path(SCRIPT_DIR, "sim_result.rds"))
generate_charts(sim, output_dir=out_dir, strategy_name=sprintf("%s: %s", STRATEGY_NAME, STRATEGY_DESC))
source(file.path(INFRA_DIR, "strategy_analyzer.R"))
run_analysis(sim, copy(FACTORS), copy(RAWDATA_ORIG), BM_DT_ORIG, out_dir, strategy_name=STRATEGY_NAME)
QEPM_AUTO_COMMIT <- TRUE; source(file.path(INFRA_DIR, "hurdle_gate.R"))
hurdle <- run_hurdle_gate(sim_result=sim, strategy_name=STRATEGY_NAME, output_dir=out_dir)
tryCatch({
  hr <- jsonlite::fromJSON(file.path(out_dir,"hurdle_result.json"))
  tg_strategy_result_with_chart(STRATEGY_NAME, hr, out_dir)
}, error=function(e) cat("[TG]",e$message,"\n"))
cat(sprintf("\n[%s] Complete.\n", STRATEGY_NAME))
