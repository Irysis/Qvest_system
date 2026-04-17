## STR_798: Adaptive Vol Target (VIX-Regime Dynamic VT)
## Instead of fixed 20% Vol Target, dynamically adjust based on VIX regime:
##   VIX <= 20 ("normal"):   VT = 25% (more aggressive in calm markets)
##   20 < VIX <= 30 ("elevated"): VT = 15% (tighten in uncertain markets)
##   VIX > 30 ("crisis"):   VT = 10% (maximum risk reduction)
## Base: STR_789 architecture (Soft MRS + FM-weighted 2-sleeve)
## No future reference: VIX used is last available value at or before decision date
set.seed(42)

SCRIPT_DIR <- tryCatch({ d <- dirname(sys.frame(1)$ofile); if (d == ".") getwd() else d },
  error = function(e) { args <- commandArgs(trailingOnly = FALSE); file_arg <- grep("--file=", args, value = TRUE)
    if (length(file_arg) > 0) { p <- sub("--file=", "", file_arg[1]); p <- gsub("~+~", " ", p, fixed = TRUE); dirname(p) } else getwd() })
INFRA_DIR <- file.path(dirname(dirname(dirname(SCRIPT_DIR))), "02_Infrastructure")
source(file.path(INFRA_DIR, "config.R")); source(file.path(INFRA_DIR, "backtest_harness.R")); source(file.path(TELEGRAM_DIR, "telegram_notify.R"))
cat("=== STR_798: Adaptive Vol Target (VIX-Regime Dynamic VT) ===\n\n")

LIQ_THRESHOLD <- 2e8
DD_BRAKE_FULL <- 0.35; MIN_EXPOSURE <- 0.30; TILT_MAX <- 0.20

# ═══ Phase 1: Shared sleeves (same as STR_771/789) ═══
BASE_DIR <- file.path(dirname(SCRIPT_DIR), "STR_770_phase2_cross")
res <- load_rawdata(); RAWDATA <- res$RAWDATA; BM_DT <- res$BM_DT
RAWDATA_ORIG <- copy(RAWDATA); BM_DT_ORIG <- copy(BM_DT)

cat("[Phase 1a] Defense sleeve...\n")
source(file.path(BASE_DIR, "defense_sleeve.R")); FACTORS_DEF <- copy(FACTORS)
sim_def <- run_monthly_simulation(RAWDATA, BM_DT, FACTORS_DEF, n_holdings=30, weight_method="equal",
  commission=0.0015, buffer_zone=list(keep_n=50L, entry_n=25L), vol_target=0.25, vol_lookback=60L)

cat("[Phase 1b] IndMom sleeve...\n")
RAWDATA <- copy(RAWDATA_ORIG); BM_DT <- copy(BM_DT_ORIG)
source(file.path(BASE_DIR, "indmom_sleeve.R")); FACTORS_IND <- copy(FACTORS)
sim_ind <- run_monthly_simulation(RAWDATA, BM_DT, FACTORS_IND, n_holdings=30, weight_method="equal",
  commission=0.0015, buffer_zone=list(keep_n=50L, entry_n=25L), vol_target=0.15, vol_lookback=60L)

common_idx <- sort(as.Date(intersect(as.Date(index(sim_def$strategy_xts)), as.Date(index(sim_ind$strategy_xts)))))
ret_def <- as.numeric(sim_def$strategy_xts[common_idx])
ret_ind <- as.numeric(sim_ind$strategy_xts[common_idx])
n <- length(common_idx); daily_ym <- format(common_idx, "%Y-%m")

# Liquidity data
RAWDATA_LIQ <- copy(RAWDATA_ORIG); RAWDATA_LIQ[, TradeVal := Close * Vol]
setorder(RAWDATA_LIQ, Ticker, Date)
RAWDATA_LIQ[, AvgTradeVal_20d := frollmean(TradeVal, n=20L, align="right", na.rm=TRUE), by=Ticker]
RAWDATA_LIQ[, YM := format(Date, "%Y-%m")]
liq_monthly <- RAWDATA_LIQ[, .(AvgTradeVal = tail(AvgTradeVal_20d[!is.na(AvgTradeVal_20d)], 1)), by=.(YM, Ticker)]
setkey(liq_monthly, YM, Ticker); rm(RAWDATA_LIQ); gc()

all_fac_dates <- sort(unique(c(FACTORS_DEF$Date, FACTORS_IND$Date)))

# ═══ Phase 2: FM weights (same as STR_771/789) ═══
cat("\n[Phase 2] FM weights...\n")
scale_ind <- numeric(n)
for (i in seq_len(n)) { if (i < 60) scale_ind[i] <- 1.0
  else { vd <- sd(ret_def[1:i])*sqrt(252); vi <- sd(ret_ind[1:i])*sqrt(252)
    scale_ind[i] <- if (vi > 0.01) vd/vi else 1.0 }}
cum_def <- zoo::rollapply(ret_def, width=63, FUN=function(x) prod(1+x)-1, fill=NA, align="right")
cum_ind_adj <- rep(NA_real_, n)
for (i in 63:n) { si <- i-62L; cum_ind_adj[i] <- prod(1+ret_ind[si:i]*scale_ind[si:i])-1 }
w_def_daily <- numeric(n)
for (i in seq_len(n)) {
  if (is.na(cum_def[max(1L, i-1L)])||is.na(cum_ind_adj[max(1L, i-1L)])) w_def_daily[i] <- 0.50
  else { diff <- cum_def[max(1L, i-1L)]-cum_ind_adj[max(1L, i-1L)]; w_def_daily[i] <- 0.50+max(-TILT_MAX,min(TILT_MAX,diff*2)) }
}
monthly_fm <- data.table(YM=daily_ym, w_def=w_def_daily)[, .(w_def=tail(w_def,1)), by=YM]; setkey(monthly_fm, YM)

# ═══ Phase 3: Build blended factors (SOFT MRS — same as STR_789) ═══
cat("[Phase 3] Building factors (SOFT MRS)...\n")
macro_regime_dt <- as.data.table(read_parquet(FRED_REGIME_CACHE))
macro_regime_dt[, YM := substr(Date, 1, 7)]; setkey(macro_regime_dt, YM)

blended_list <- list()
for (dt in all_fac_dates) {
  dt <- as.Date(dt); ym <- format(dt, "%Y-%m")
  w_fm <- monthly_fm[YM == ym, w_def]; if (length(w_fm) == 0) w_fm <- 0.50
  w_d <- max(0.10, min(0.90, 0.50 + (w_fm - 0.50)))
  N_def <- max(2L, min(18L, as.integer(round(20 * w_d)))); N_ind <- 20L - N_def
  def_r <- FACTORS_DEF[Date == dt][order(-Score)]; ind_r <- FACTORS_IND[Date == dt][order(-Score)]
  liq_m <- liq_monthly[YM == ym]
  if (nrow(liq_m) > 0) { liquid <- liq_m[AvgTradeVal >= LIQ_THRESHOLD, Ticker]
    def_r <- def_r[Ticker %in% liquid]; ind_r <- ind_r[Ticker %in% liquid] }
  if (nrow(def_r) < N_def || nrow(ind_r) < N_ind) next
  def_picks <- head(def_r$Ticker, N_def)
  ind_rem <- ind_r[!Ticker %in% def_picks]; if (nrow(ind_rem) < N_ind) next
  ind_picks <- head(ind_rem$Ticker, N_ind); selected <- c(def_picks, ind_picks)
  buf <- unique(c(head(def_r[!Ticker %in% selected]$Ticker, 30), head(ind_rem[!Ticker %in% selected]$Ticker, 30)))
  buf <- buf[!buf %in% selected]; ns <- length(selected); nb <- length(buf)
  merged <- data.table(Ticker=c(selected,buf), Score=c(seq(100,100-ns+1), seq(100-ns,100-ns-nb+1)), Date=dt)
  blended_list[[length(blended_list)+1]] <- merged[!duplicated(Ticker)]
}
FACTORS_B <- rbindlist(blended_list) |> setorder(Date, -Score)
cat(sprintf("  %d rows | %d dates\n", nrow(FACTORS_B), uniqueN(FACTORS_B$Date)))

# ═══ Phase 4: Simulation ═══
cat("[Phase 4] Simulation...\n")
RAWDATA_tmp <- copy(RAWDATA_ORIG); BM_tmp <- copy(BM_DT_ORIG)
sim_c <- run_monthly_simulation(RAWDATA_tmp, BM_tmp, FACTORS_B, n_holdings=20L, weight_method="equal",
  commission=0.0015, buffer_zone=list(keep_n=40L, entry_n=20L), vol_target=0.30, vol_lookback=60L)

# ═══ Phase 5: ADAPTIVE Vol Target (KEY CHANGE) + DD Brake ═══
cat("[Phase 5] Adaptive VT (VIX-regime) + DD Brake...\n")
raw_ret <- as.numeric(sim_c$strategy_xts); raw_dates <- as.Date(index(sim_c$strategy_xts)); n_f <- length(raw_ret)

## Load VIX data from FRED_MACRO_CACHE
FRED_VIX <- as.data.table(read_parquet(FRED_MACRO_CACHE))
FRED_VIX <- FRED_VIX[Series == "VIX" & !is.na(Value)]
FRED_VIX[, Date := as.Date(Date)]
setorder(FRED_VIX, Date)

## Build monthly VIX: last available VIX value for each YM (no future reference)
FRED_VIX[, YM := format(Date, "%Y-%m")]
vix_monthly <- FRED_VIX[, .(VIX_level = tail(Value, 1)), by = YM]
setkey(vix_monthly, YM)
cat(sprintf("  VIX monthly data: %d months | range: %.1f to %.1f\n",
    nrow(vix_monthly), min(vix_monthly$VIX_level), max(vix_monthly$VIX_level)))

## Map daily dates to monthly VIX (last available month's VIX)
daily_ym_f <- format(raw_dates, "%Y-%m")

## Determine adaptive VT for each day based on VIX regime
vt_target_daily <- numeric(n_f)
vix_regime_daily <- character(n_f)
for (i in seq_len(n_f)) {
  vix_val <- vix_monthly[YM == daily_ym_f[i], VIX_level]
  if (length(vix_val) == 0) {
    ## Fallback: use last available month before current
    prev_months <- vix_monthly[YM < daily_ym_f[i]]
    if (nrow(prev_months) > 0) {
      vix_val <- tail(prev_months$VIX_level, 1)
    } else {
      vix_val <- 20  # neutral default
    }
  }

  if (vix_val <= 20) {
    vt_target_daily[i] <- 0.25
    vix_regime_daily[i] <- "normal"
  } else if (vix_val <= 30) {
    vt_target_daily[i] <- 0.15
    vix_regime_daily[i] <- "elevated"
  } else {
    vt_target_daily[i] <- 0.10
    vix_regime_daily[i] <- "crisis"
  }
}

## Report VIX regime distribution
regime_tbl <- table(vix_regime_daily)
cat(sprintf("  VIX regimes: normal=%d (%.1f%%) | elevated=%d (%.1f%%) | crisis=%d (%.1f%%)\n",
    regime_tbl["normal"], 100*regime_tbl["normal"]/n_f,
    ifelse("elevated" %in% names(regime_tbl), regime_tbl["elevated"], 0),
    ifelse("elevated" %in% names(regime_tbl), 100*regime_tbl["elevated"]/n_f, 0),
    ifelse("crisis" %in% names(regime_tbl), regime_tbl["crisis"], 0),
    ifelse("crisis" %in% names(regime_tbl), 100*regime_tbl["crisis"]/n_f, 0)))

## Apply adaptive VT: vt_scale = min(1.0, vt_target / port_vol_60)
port_vol <- zoo::rollapply(raw_ret, width=60, FUN=sd, fill=NA, align="right") * sqrt(252)
vt_scale <- ifelse(is.na(port_vol) | port_vol < 0.01, 1.0, pmin(1.0, vt_target_daily / port_vol))
vt_scale_lagged <- c(1.0, head(vt_scale, -1))  # 1-day lag (C2/C5 fix)
after_vt <- raw_ret * vt_scale_lagged

cat(sprintf("  Adaptive VT: mean target=%.3f | mean scale=%.3f\n", mean(vt_target_daily), mean(vt_scale, na.rm=TRUE)))

## DD Brake (same as STR_789: 4% start, 35% full, 30% min)
nav <- cumprod(1 + after_vt); dd <- 1 - nav / cummax(nav)
dd_exp <- ifelse(dd <= 0.04, 1.0, ifelse(dd >= 0.35, 0.30, pmax(0.30, 1.0 - (dd - 0.04) / 0.31 * 0.70)))
dd_exp_lagged <- c(1.0, head(dd_exp, -1))  # 1-day lag (C2/C5 fix)
after_dd <- after_vt * dd_exp_lagged

# ═══ Phase 6: SOFT MRS Overlay (same as STR_789) ═══
cat("[Phase 6] Soft MRS overlay...\n")
MRS_LOW <- 15; MRS_HIGH <- 30; MRS_MIN_EXP <- 0.30

mrs_monthly <- macro_regime_dt[, .(YM, Macro_Risk_Score)]
mrs_monthly <- mrs_monthly[!duplicated(YM)]

soft_mrs_exp <- numeric(n_f)
for (i in seq_len(n_f)) {
  mrs_val <- mrs_monthly[YM == daily_ym_f[i], Macro_Risk_Score]
  if (length(mrs_val) == 0) mrs_val <- 0
  if (mrs_val < MRS_LOW) { soft_mrs_exp[i] <- 1.0 }
  else if (mrs_val >= MRS_HIGH) { soft_mrs_exp[i] <- MRS_MIN_EXP }
  else { soft_mrs_exp[i] <- 1.0 - (mrs_val - MRS_LOW) / (MRS_HIGH - MRS_LOW) * (1.0 - MRS_MIN_EXP) }
}

combined_ret <- after_dd * soft_mrs_exp
cat(sprintf("  Mean MRS exp: %.3f | Days reduced: %d/%d\n", mean(soft_mrs_exp), sum(soft_mrs_exp < 1.0), n_f))

combined_xts <- xts(combined_ret, order.by=raw_dates); names(combined_xts) <- "Strategy"
sim <- sim_c; sim$strategy_xts <- combined_xts; sim$bm_xts <- sim_c$bm_xts[raw_dates]
sim$DAILY_NAV_DT <- data.table(Date=raw_dates, NAV=cumprod(1+combined_ret)*10000, Strategy_Ret=combined_ret)

perf <- summarise_perf(combined_xts, "STR_798")
cat(sprintf("\n  CAGR=%.2f%% | Sharpe=%.3f | MDD=%.1f%%\n", perf$CAGR, perf$Sharpe, perf$MDD))

# ═══ Phase 7: Output + Hurdle ═══
out_dir <- file.path(SCRIPT_DIR, "output", "STR_798")
dir.create(out_dir, showWarnings=FALSE, recursive=TRUE)
generate_charts(sim, output_dir=out_dir, strategy_name="STR_798: Adaptive VT")
RAWDATA_tmp2 <- copy(RAWDATA_ORIG); FACTORS_tmp <- copy(FACTORS_B)
source(file.path(INFRA_DIR, "strategy_analyzer.R"))
run_analysis(sim, FACTORS_tmp, RAWDATA_tmp2, BM_DT_ORIG, out_dir, strategy_name="STR_798")
source(file.path(INFRA_DIR, "hurdle_gate.R"))
hurdle <- run_hurdle_gate(sim_result=sim, strategy_name="STR_798", output_dir=out_dir)

# ═══ Telegram Briefing (MANDATORY) ═══
tryCatch({
  hr <- jsonlite::fromJSON(file.path(out_dir, "hurdle_result.json"))
  tg_strategy_result_with_chart("STR_798", hr, out_dir)
}, error = function(e) cat("[TG]", e$message, "\n"))

cat("\n[STR_798] Complete.\n")
