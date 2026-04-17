## STR_794: Soft MRS + Quality Gate — 검증된 요소 조합
## Base: STR_789 (Soft MRS, Sharpe 1.516, MDD 19.3%) 위에
## Quality Gate: QMJ composite bottom 20% 종목 제거 후 Defense+IndMom 스코어링
## 가설: 저품질 종목 사전 제거 → tail risk 감소 → MDD/Sharpe 추가 개선
## 근거: L-306 (CCC+Accrual gate = Grade A), L-402 (Quality = gate로만 유효)
set.seed(42)

SCRIPT_DIR <- tryCatch({ d <- dirname(sys.frame(1)$ofile); if (d == ".") getwd() else d },
  error = function(e) { args <- commandArgs(trailingOnly = FALSE); file_arg <- grep("--file=", args, value = TRUE)
    if (length(file_arg) > 0) { p <- sub("--file=", "", file_arg[1]); p <- gsub("~+~", " ", p, fixed = TRUE); dirname(p) } else getwd() })
INFRA_DIR <- file.path(dirname(dirname(dirname(SCRIPT_DIR))), "02_Infrastructure")
source(file.path(INFRA_DIR, "config.R")); source(file.path(INFRA_DIR, "backtest_harness.R")); source(file.path(TELEGRAM_DIR, "telegram_notify.R"))
cat("=== STR_794: Soft MRS + Quality Gate ===\n\n")

LIQ_THRESHOLD <- 2e8
DD_BRAKE_FULL <- 0.35; MIN_EXPOSURE <- 0.30; TILT_MAX <- 0.20
QUALITY_GATE_PCT <- 0.20  # bottom 20% QMJ 제거

# ═══ Data ═══
res <- load_rawdata(); RAWDATA <- res$RAWDATA; BM_DT <- res$BM_DT
RAWDATA_ORIG <- copy(RAWDATA); BM_DT_ORIG <- copy(BM_DT)
BASE_DIR <- file.path(dirname(SCRIPT_DIR), "STR_770_phase2_cross")

# ═══ DART for Quality Gate ═══
DART_CACHE <- file.path(CACHE_DIR, "fundamental_dart.parquet")
HAS_DART <- file.exists(DART_CACHE)
FUND_DT <- NULL
if (HAS_DART) {
  FUND_DT <- as.data.table(read_parquet(DART_CACHE))
  setnames(FUND_DT, "bsns_year", "biz_year", skip_absent = TRUE)
  FUND_DT[, Factor_Date := as.Date(Factor_Date)]
  cat(sprintf("  DART: %d rows | dates %s ~ %s\n", nrow(FUND_DT), min(FUND_DT$Factor_Date), max(FUND_DT$Factor_Date)))
} else {
  cat("  [WARN] No DART cache — Quality Gate disabled (pre-2016 period)\n")
}

# ═══ Phase 1: Standard sleeves ═══
cat("[Phase 1a] Defense sleeve...\n")
source(file.path(BASE_DIR, "defense_sleeve.R")); FACTORS_DEF <- copy(FACTORS)
RAWDATA <- copy(RAWDATA_ORIG); BM_DT <- copy(BM_DT_ORIG)
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

# Liquidity
RAWDATA_LIQ <- copy(RAWDATA_ORIG); RAWDATA_LIQ[, TradeVal := Close * Vol]
setorder(RAWDATA_LIQ, Ticker, Date)
RAWDATA_LIQ[, AvgTradeVal_20d := frollmean(TradeVal, n=20L, align="right", na.rm=TRUE), by=Ticker]
RAWDATA_LIQ[, YM := format(Date, "%Y-%m")]
liq_monthly <- RAWDATA_LIQ[, .(AvgTradeVal = tail(AvgTradeVal_20d[!is.na(AvgTradeVal_20d)], 1)), by=.(YM, Ticker)]
setkey(liq_monthly, YM, Ticker); rm(RAWDATA_LIQ); gc()

all_fac_dates <- sort(unique(c(FACTORS_DEF$Date, FACTORS_IND$Date)))

# ═══ Phase 2: FM weights ═══
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

# ═══ Phase 3: Quality Gate + Blended factors ═══
cat("[Phase 3] Building factors with QUALITY GATE...\n")

# Precompute QMJ scores per DART Factor_Date for gating
# Simplified QMJ: Profitability(GPA+ROE+ROA) + Safety(-DebtRatio+AltmanZ) = 5 components
.w <- function(x) { q <- quantile(x, c(0.01, 0.99), na.rm=TRUE); pmin(pmax(x, q[1]), q[2]) }

qmj_gate_tickers <- list()  # YM → set of tickers to EXCLUDE (bottom 20% QMJ)
if (HAS_DART) {
  qmj_cols <- c("GPA", "ROE", "ROA", "DebtRatio", "AltmanZ")
  avail_qmj <- qmj_cols[qmj_cols %in% names(FUND_DT)]
  cat(sprintf("  QMJ gate cols: %s\n", paste(avail_qmj, collapse=", ")))

  for (fd in sort(unique(FUND_DT$Factor_Date))) {
    fd <- as.Date(fd)
    dart_snap <- FUND_DT[Factor_Date == fd]
    if (nrow(dart_snap) < 50) next
    ym <- format(fd, "%Y-%m")

    # Simple QMJ: mean of available z-scores
    safe_z <- function(x) { x_ok <- x[!is.na(x)]; if (length(x_ok) < 10) return(rep(NA_real_, length(x)))
      (x - mean(x_ok)) / max(sd(x_ok), 1e-8) }

    dart_snap[, qmj := 0]
    n_comp <- 0
    for (col in c("GPA", "ROE", "ROA")) {
      if (col %in% names(dart_snap)) {
        vals <- dart_snap[[col]]
        if (sum(!is.na(vals)) >= 20) { dart_snap[, qmj := qmj + safe_z(get(col))]; n_comp <- n_comp + 1 }
      }
    }
    for (col in c("DebtRatio")) {
      if (col %in% names(dart_snap)) {
        vals <- dart_snap[[col]]
        if (sum(!is.na(vals)) >= 20) { dart_snap[, qmj := qmj + safe_z(-get(col))]; n_comp <- n_comp + 1 }
      }
    }
    if ("AltmanZ" %in% names(dart_snap)) {
      vals <- dart_snap[["AltmanZ"]]
      if (sum(!is.na(vals)) >= 20) { dart_snap[, qmj := qmj + safe_z(get("AltmanZ"))]; n_comp <- n_comp + 1 }
    }

    if (n_comp >= 2) {
      dart_snap[, qmj := qmj / n_comp]
      cutoff <- quantile(dart_snap$qmj, QUALITY_GATE_PCT, na.rm = TRUE)
      exclude <- dart_snap[qmj <= cutoff, Ticker]
      qmj_gate_tickers[[ym]] <- exclude
    }
  }
  cat(sprintf("  Quality gate: %d months with exclusion lists\n", length(qmj_gate_tickers)))
}

gate_excluded_total <- 0
blended_list <- list()
for (dt in all_fac_dates) {
  dt <- as.Date(dt); ym <- format(dt, "%Y-%m")
  w_fm <- monthly_fm[YM == ym, w_def]; if (length(w_fm) == 0) w_fm <- 0.50
  w_d <- max(0.10, min(0.90, 0.50 + (w_fm - 0.50)))
  N_def <- max(2L, min(18L, as.integer(round(20 * w_d)))); N_ind <- 20L - N_def
  def_r <- FACTORS_DEF[Date == dt][order(-Score)]; ind_r <- FACTORS_IND[Date == dt][order(-Score)]

  # Liquidity filter
  liq_m <- liq_monthly[YM == ym]
  if (nrow(liq_m) > 0) { liquid <- liq_m[AvgTradeVal >= LIQ_THRESHOLD, Ticker]
    def_r <- def_r[Ticker %in% liquid]; ind_r <- ind_r[Ticker %in% liquid] }

  # ★ QUALITY GATE: remove bottom 20% QMJ tickers ★
  # Use most recent available gate (DART dates don't align exactly with factor dates)
  gate_ym <- ym
  if (!gate_ym %in% names(qmj_gate_tickers)) {
    # Find closest earlier gate
    all_gate_yms <- sort(names(qmj_gate_tickers))
    earlier <- all_gate_yms[all_gate_yms <= gate_ym]
    if (length(earlier) > 0) gate_ym <- tail(earlier, 1)
  }
  if (gate_ym %in% names(qmj_gate_tickers)) {
    exclude_tickers <- qmj_gate_tickers[[gate_ym]]
    n_before_d <- nrow(def_r); n_before_i <- nrow(ind_r)
    def_r <- def_r[!Ticker %in% exclude_tickers]
    ind_r <- ind_r[!Ticker %in% exclude_tickers]
    gate_excluded_total <- gate_excluded_total + (n_before_d - nrow(def_r)) + (n_before_i - nrow(ind_r))
  }

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
cat(sprintf("  %d rows | %d dates | Quality gate excluded: %d total ticker-dates\n",
  nrow(FACTORS_B), uniqueN(FACTORS_B$Date), gate_excluded_total))

# ═══ Phase 4: Simulation ═══
cat("[Phase 4] Simulation...\n")
RAWDATA_tmp <- copy(RAWDATA_ORIG); BM_tmp <- copy(BM_DT_ORIG)
sim_c <- run_monthly_simulation(RAWDATA_tmp, BM_tmp, FACTORS_B, n_holdings=20L, weight_method="equal",
  commission=0.0015, buffer_zone=list(keep_n=40L, entry_n=20L), vol_target=0.30, vol_lookback=60L)

# ═══ Phase 5: VT + DD Brake ═══
raw_ret <- as.numeric(sim_c$strategy_xts); raw_dates <- as.Date(index(sim_c$strategy_xts)); n_f <- length(raw_ret)
port_vol <- zoo::rollapply(raw_ret, width=60, FUN=sd, fill=NA, align="right") * sqrt(252)
vt_scale <- ifelse(is.na(port_vol) | port_vol < 0.01, 1.0, pmin(1.0, 0.20 / port_vol))
vt_scale_lagged <- c(1.0, head(vt_scale, -1))  # 1-day lag (C2/C5 fix)
after_vt <- raw_ret * vt_scale_lagged
nav <- cumprod(1 + after_vt); dd <- 1 - nav / cummax(nav)
dd_exp <- ifelse(dd <= 0.04, 1.0, ifelse(dd >= 0.35, 0.30, pmax(0.30, 1.0 - (dd - 0.04) / 0.31 * 0.70)))
dd_exp_lagged <- c(1.0, head(dd_exp, -1))  # 1-day lag (C2/C5 fix)
after_dd <- after_vt * dd_exp_lagged

# ═══ Phase 6: SOFT MRS Overlay (from STR_789) ═══
cat("[Phase 6] Soft MRS overlay...\n")
MRS_LOW <- 15; MRS_HIGH <- 30; MRS_MIN_EXP <- 0.30
macro_regime_dt <- as.data.table(read_parquet(FRED_REGIME_CACHE))
macro_regime_dt[, YM := substr(Date, 1, 7)]; setkey(macro_regime_dt, YM)
mrs_monthly <- macro_regime_dt[, .(YM, Macro_Risk_Score)]; mrs_monthly <- mrs_monthly[!duplicated(YM)]
daily_ym_f <- format(raw_dates, "%Y-%m")

soft_mrs_exp <- numeric(n_f)
for (i in seq_len(n_f)) {
  mrs_val <- mrs_monthly[YM == daily_ym_f[i], Macro_Risk_Score]
  if (length(mrs_val) == 0) mrs_val <- 0
  if (mrs_val < MRS_LOW) soft_mrs_exp[i] <- 1.0
  else if (mrs_val >= MRS_HIGH) soft_mrs_exp[i] <- MRS_MIN_EXP
  else soft_mrs_exp[i] <- 1.0 - (mrs_val - MRS_LOW) / (MRS_HIGH - MRS_LOW) * (1.0 - MRS_MIN_EXP)
}
combined_ret <- after_dd * soft_mrs_exp
cat(sprintf("  Mean MRS exp: %.3f | Days reduced: %d/%d\n", mean(soft_mrs_exp), sum(soft_mrs_exp < 1.0), n_f))

combined_xts <- xts(combined_ret, order.by=raw_dates); names(combined_xts) <- "Strategy"
sim <- sim_c; sim$strategy_xts <- combined_xts; sim$bm_xts <- sim_c$bm_xts[raw_dates]
sim$DAILY_NAV_DT <- data.table(Date=raw_dates, NAV=cumprod(1+combined_ret)*10000, Strategy_Ret=combined_ret)
perf <- summarise_perf(combined_xts, "STR_794")
cat(sprintf("\n  CAGR=%.2f%% | Sharpe=%.3f | MDD=%.1f%%\n", perf$CAGR, perf$Sharpe, perf$MDD))

# ═══ Phase 7: Output + Hurdle ═══
out_dir <- file.path(SCRIPT_DIR, "output", "STR_794")
dir.create(out_dir, showWarnings=FALSE, recursive=TRUE)
generate_charts(sim, output_dir=out_dir, strategy_name="STR_794: Soft MRS + Quality Gate")
RAWDATA_tmp2 <- copy(RAWDATA_ORIG); FACTORS_tmp <- copy(FACTORS_B)
source(file.path(INFRA_DIR, "strategy_analyzer.R"))
run_analysis(sim, FACTORS_tmp, RAWDATA_tmp2, BM_DT_ORIG, out_dir, strategy_name="STR_794")
source(file.path(INFRA_DIR, "hurdle_gate.R"))
hurdle <- run_hurdle_gate(sim_result=sim, strategy_name="STR_794", output_dir=out_dir)

tryCatch({
  hr <- jsonlite::fromJSON(file.path(out_dir, "hurdle_result.json"))
  tg_strategy_result_with_chart("STR_794", hr, out_dir)
}, error = function(e) cat("[TG]", e$message, "\n"))

cat("\n[STR_794] Complete.\n")
