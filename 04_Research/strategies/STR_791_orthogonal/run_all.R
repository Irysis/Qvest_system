## STR_791: Orthogonal Residual Scoring
## Cross-sectional regression: Momentum = α + β×Defense + ε
## Use ε (residual) as independent alpha → by construction uncorrelated with Defense
## Hypothesis: 12-1 momentum residual (after removing Defense overlap) is pure alpha
## Combined as 2-sleeve: Defense + Orthogonal-Momentum
set.seed(42)

SCRIPT_DIR <- tryCatch({ d <- dirname(sys.frame(1)$ofile); if (d == ".") getwd() else d },
  error = function(e) { args <- commandArgs(trailingOnly = FALSE); file_arg <- grep("--file=", args, value = TRUE)
    if (length(file_arg) > 0) { p <- sub("--file=", "", file_arg[1]); p <- gsub("~+~", " ", p, fixed = TRUE); dirname(p) } else getwd() })
INFRA_DIR <- file.path(dirname(dirname(dirname(SCRIPT_DIR))), "02_Infrastructure")
source(file.path(INFRA_DIR, "config.R")); source(file.path(INFRA_DIR, "backtest_harness.R")); source(file.path(TELEGRAM_DIR, "telegram_notify.R"))
cat("=== STR_791: Orthogonal Residual Scoring ===\n\n")

LIQ_THRESHOLD <- 2e8
DD_BRAKE_FULL <- 0.35; MIN_EXPOSURE <- 0.30; TILT_MAX <- 0.20

res <- load_rawdata(); RAWDATA <- res$RAWDATA; BM_DT <- res$BM_DT
RAWDATA_ORIG <- copy(RAWDATA); BM_DT_ORIG <- copy(BM_DT)

# ═══ Phase 1: Defense sleeve (standard) ═══
cat("[Phase 1] Defense sleeve + factors...\n")
BASE_DIR <- file.path(dirname(SCRIPT_DIR), "STR_770_phase2_cross")
source(file.path(BASE_DIR, "defense_sleeve.R")); FACTORS_DEF <- copy(FACTORS)
RAWDATA <- copy(RAWDATA_ORIG); BM_DT <- copy(BM_DT_ORIG)
sim_def <- run_monthly_simulation(RAWDATA, BM_DT, FACTORS_DEF, n_holdings=30, weight_method="equal",
  commission=0.0015, buffer_zone=list(keep_n=50L, entry_n=25L), vol_target=0.25, vol_lookback=60L)

# ═══ Phase 2: Compute raw momentum + orthogonalize ═══
cat("[Phase 2] Orthogonal momentum factor...\n")
RAWDATA_m <- copy(RAWDATA_ORIG); setorder(RAWDATA_m, Ticker, Date)
RAWDATA_m[, TradeVal := Close * Vol]
RAWDATA_m[, AvgTradeVal_20d := frollmean(TradeVal, n=20L, align="right", na.rm=TRUE), by=Ticker]

all_dates <- sort(unique(RAWDATA_m$Date))
fac_dates <- sort(unique(FACTORS_DEF$Date))

# FRED regime (for cashout)
macro_regime_dt <- as.data.table(read_parquet(FRED_REGIME_CACHE))
macro_regime_dt[, YM := substr(Date, 1, 7)]; setkey(macro_regime_dt, YM)
FRED_LONG <- as.data.table(read_parquet(FRED_MACRO_CACHE)); FRED_LONG[, Date := as.Date(Date)]
FRED_LONG <- FRED_LONG[, .(Value = tail(Value, 1)), by = .(Date, Series)]
FRED_WIDE <- dcast(FRED_LONG, Date ~ Series, value.var = "Value"); setorder(FRED_WIDE, Date)
for (cn in c("Term_Spread", "HY_Spread", "VIX")) {
  FRED_WIDE[, paste0(cn, "_z") := { out <- rep(NA_real_, .N)
    for (j in 756:.N) { vals <- get(cn)[(j-755):j]; vals <- vals[!is.na(vals)]
      if (length(vals)>=100) out[j] <- (get(cn)[j]-mean(vals))/max(sd(vals),1e-8) }; out }]
}
FRED_WIDE[, n_sig := (fifelse(!is.na(Term_Spread_z) & Term_Spread_z < -2.0, 1L, 0L) +
                       fifelse(!is.na(HY_Spread_z) & HY_Spread_z > 2.0, 1L, 0L) +
                       fifelse(!is.na(VIX_z) & VIX_z > 2.0, 1L, 0L))]
FRED_WIDE[, exposure := fifelse(n_sig >= 2, 0.0, fifelse(n_sig == 1, 0.50, 1.0))]
FRED_WIDE[, YM := format(Date, "%Y-%m")]
fred_m <- FRED_WIDE[, .(exposure = tail(exposure[!is.na(exposure)], 1)), by = YM]; setkey(fred_m, YM)

factor_list <- list()
for (dd in fac_dates) {
  dd <- as.Date(dd); ym <- format(dd, "%Y-%m")
  # MRS cashout
  mrs_val <- macro_regime_dt[YM == ym, Macro_Risk_Score]; if (length(mrs_val)==0) mrs_val <- 0
  if (mrs_val[1] >= 30) next
  exp_f <- fred_m[YM == ym, exposure]; if (length(exp_f)==0) exp_f <- 1.0; if (exp_f == 0) next
  rsc <- if (mrs_val[1] >= 15) 0.5 else 1.0

  idx <- which(all_dates == dd); if (length(idx) == 0 || idx < 252) next
  lb_start <- all_dates[max(1, idx - 252)]
  # Skip most recent 21 days (12-1 month momentum = skip last month)
  mom_end <- all_dates[max(1, idx - 21)]

  # 12-1 month momentum per stock
  stats_mom <- RAWDATA_m[Date >= lb_start & Date <= mom_end & !is.na(Ret), {
    if (.N >= 200) list(mom_12_1 = as.double(prod(1+Ret)-1)) else list(mom_12_1=NA_real_)
  }, by=Ticker]
  stats_mom <- stats_mom[!is.na(mom_12_1)]

  # Get Defense scores for same date
  def_scores <- FACTORS_DEF[Date == dd, .(Ticker, DefScore = Score)]
  merged <- merge(stats_mom, def_scores, by="Ticker")

  # Liquidity
  liq_snap <- RAWDATA_m[Date == dd & !is.na(AvgTradeVal_20d), .(Ticker, AvgTradeVal_20d)]
  merged <- merge(merged, liq_snap, by="Ticker"); merged <- merged[AvgTradeVal_20d >= LIQ_THRESHOLD]
  if (nrow(merged) < 30) next

  # Cross-sectional regression: mom = α + β*Defense + ε
  fit <- tryCatch(.lm.fit(cbind(1, merged$DefScore), merged$mom_12_1), error = function(e) NULL)
  if (is.null(fit)) next
  merged[, ortho_mom := as.double(fit$residuals)]

  # Sector info
  si <- unique(RAWDATA_m[Date == dd, .(Ticker, Sector)])
  merged <- merge(merged, si, by="Ticker", all.x=TRUE)

  # Sector-neutral z-scoring of orthogonal residual
  .w <- function(x) { q <- quantile(x, c(0.01, 0.99), na.rm=TRUE); pmin(pmax(x, q[1]), q[2]) }
  merged[!is.na(Sector), z_ortho := { if (.N>=5) {v<-.w(ortho_mom); (v-mean(v))/max(sd(v),1e-8)} else rep(NA_real_,.N)}, by=Sector]
  merged <- merged[!is.na(z_ortho)]
  if (nrow(merged) < 30) next

  merged[, Score := as.double(z_ortho * rsc * exp_f)]
  merged[, Date := dd]
  factor_list[[length(factor_list)+1]] <- merged[, .(Date, Ticker, Score)]
}
FACTORS_ORTHO <- rbindlist(factor_list); setorder(FACTORS_ORTHO, Date, -Score)
cat(sprintf("  ORTHO FACTORS: %d rows | %d dates\n", nrow(FACTORS_ORTHO), uniqueN(FACTORS_ORTHO$Date)))

# ═══ Phase 3: Orthogonal sleeve sim ═══
cat("[Phase 3] Orthogonal sleeve sim...\n")
RAWDATA <- copy(RAWDATA_ORIG); BM_DT <- copy(BM_DT_ORIG)
sim_ort <- run_monthly_simulation(RAWDATA, BM_DT, FACTORS_ORTHO, n_holdings=30, weight_method="equal",
  commission=0.0015, buffer_zone=list(keep_n=50L, entry_n=25L), vol_target=0.15, vol_lookback=60L)

# ═══ Phase 4: FM-weighted 2-sleeve (Defense + Orthogonal) ═══
cat("[Phase 4] FM blend...\n")
common_idx <- sort(as.Date(intersect(as.Date(index(sim_def$strategy_xts)), as.Date(index(sim_ort$strategy_xts)))))
ret_d <- as.numeric(sim_def$strategy_xts[common_idx])
ret_o <- as.numeric(sim_ort$strategy_xts[common_idx])
nn <- length(common_idx); daily_ym <- format(common_idx, "%Y-%m")

sc_ort <- numeric(nn)
for (i in seq_len(nn)) { if (i<60) sc_ort[i] <- 1.0
  else { vd <- sd(ret_d[1:i])*sqrt(252); vo <- sd(ret_o[1:i])*sqrt(252); sc_ort[i] <- if(vo>0.01) vd/vo else 1.0 }}
cum_d <- zoo::rollapply(ret_d, width=63, FUN=function(x)prod(1+x)-1, fill=NA, align="right")
cum_o <- rep(NA_real_, nn)
for (i in 63:nn) { si <- i-62L; cum_o[i] <- prod(1+ret_o[si:i]*sc_ort[si:i])-1 }
w_def <- numeric(nn)
for (i in seq_len(nn)) {
  if (is.na(cum_d[i])||is.na(cum_o[i])) w_def[i] <- 0.50
  else { diff <- cum_d[i]-cum_o[i]; w_def[i] <- 0.50+max(-TILT_MAX,min(TILT_MAX,diff*2)) }
}
fm_m <- data.table(YM=daily_ym, w_def=w_def)[, .(w_def=tail(w_def,1)), by=YM]; setkey(fm_m, YM)
all_fd <- sort(unique(c(FACTORS_DEF$Date, FACTORS_ORTHO$Date)))

RAWDATA_LIQ <- copy(RAWDATA_ORIG); RAWDATA_LIQ[, TradeVal := Close * Vol]
setorder(RAWDATA_LIQ, Ticker, Date)
RAWDATA_LIQ[, AvgTradeVal_20d := frollmean(TradeVal, n=20L, align="right", na.rm=TRUE), by=Ticker]
RAWDATA_LIQ[, YM := format(Date, "%Y-%m")]
liq_monthly <- RAWDATA_LIQ[, .(AvgTradeVal=tail(AvgTradeVal_20d[!is.na(AvgTradeVal_20d)],1)), by=.(YM,Ticker)]
setkey(liq_monthly, YM, Ticker); rm(RAWDATA_LIQ); gc()

blended_list <- list()
for (dt in all_fd) {
  dt <- as.Date(dt); ym <- format(dt, "%Y-%m")
  wfm <- fm_m[YM==ym, w_def]; if (length(wfm)==0) wfm <- 0.50
  wd <- max(0.10, min(0.90, 0.50+(wfm-0.50)))
  Nd <- max(2L, min(18L, as.integer(round(20*wd)))); No <- 20L-Nd
  dr <- FACTORS_DEF[Date==dt][order(-Score)]; ort <- FACTORS_ORTHO[Date==dt][order(-Score)]
  lq <- liq_monthly[YM==ym]
  if (nrow(lq)>0) { lt <- lq[AvgTradeVal>=LIQ_THRESHOLD, Ticker]; dr <- dr[Ticker %in% lt]; ort <- ort[Ticker %in% lt] }
  if (nrow(dr)<Nd || nrow(ort)<No) next
  dp <- head(dr$Ticker, Nd); orem <- ort[!Ticker %in% dp]; if (nrow(orem)<No) next
  op <- head(orem$Ticker, No); sel <- c(dp, op)
  buf <- unique(c(head(dr[!Ticker %in% sel]$Ticker,30), head(orem[!Ticker %in% sel]$Ticker,30)))
  buf <- buf[!buf %in% sel]; ns <- length(sel); nb <- length(buf)
  blended_list[[length(blended_list)+1]] <- data.table(
    Ticker=c(sel,buf), Score=c(seq(100,100-ns+1), seq(100-ns,100-ns-nb+1)), Date=dt)[!duplicated(Ticker)]
}
FACTORS_BLEND <- rbindlist(blended_list) |> setorder(Date, -Score)

RAWDATA <- copy(RAWDATA_ORIG); BM_DT <- copy(BM_DT_ORIG)
sim_c <- run_monthly_simulation(RAWDATA, BM_DT, FACTORS_BLEND, n_holdings=20L, weight_method="equal",
  commission=0.0015, buffer_zone=list(keep_n=40L, entry_n=20L), vol_target=0.30, vol_lookback=60L)

# VT + DD
raw_ret <- as.numeric(sim_c$strategy_xts); raw_dates <- as.Date(index(sim_c$strategy_xts)); nf <- length(raw_ret)
pv <- zoo::rollapply(raw_ret, width=60, FUN=sd, fill=NA, align="right")*sqrt(252)
vts <- ifelse(is.na(pv)|pv<0.01, 1.0, pmin(1.0, 0.20/pv)); avt <- raw_ret*vts
nav <- cumprod(1+avt); dd <- 1-nav/cummax(nav)
dde <- ifelse(dd<=0.04, 1.0, ifelse(dd>=0.35, 0.30, pmax(0.30, 1.0-(dd-0.04)/0.31*0.70)))
combined_ret <- avt * dde

combined_xts <- xts(combined_ret, order.by=raw_dates); names(combined_xts) <- "Strategy"
sim <- sim_c; sim$strategy_xts <- combined_xts; sim$bm_xts <- sim_c$bm_xts[raw_dates]
sim$DAILY_NAV_DT <- data.table(Date=raw_dates, NAV=cumprod(1+combined_ret)*10000, Strategy_Ret=combined_ret)
perf <- summarise_perf(combined_xts, "STR_791")
cat(sprintf("\n  STR_791: CAGR=%.2f%% | Sharpe=%.3f | MDD=%.1f%%\n", perf$CAGR, perf$Sharpe, perf$MDD))

out_dir <- file.path(SCRIPT_DIR, "output", "STR_791")
dir.create(out_dir, showWarnings=FALSE, recursive=TRUE)
generate_charts(sim, output_dir=out_dir, strategy_name="STR_791: Orthogonal Mom")
RAWDATA_tmp <- copy(RAWDATA_ORIG); source(file.path(INFRA_DIR, "strategy_analyzer.R"))
run_analysis(sim, copy(FACTORS_BLEND), RAWDATA_tmp, BM_DT_ORIG, out_dir, strategy_name="STR_791")
source(file.path(INFRA_DIR, "hurdle_gate.R"))
hurdle <- run_hurdle_gate(sim_result=sim, strategy_name="STR_791", output_dir=out_dir)

tryCatch({
  hr <- jsonlite::fromJSON(file.path(out_dir, "hurdle_result.json"))
  tg_strategy_result_with_chart("STR_791", hr, out_dir)
}, error = function(e) cat("[TG]", e$message, "\n"))

cat("\n[STR_791] Complete.\n")
