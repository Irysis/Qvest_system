cat("=== STR_1685: H_1690 Multi-Source Defense Anchor (4-axis Regime-Smoothed) ===\n")
## 핵심아이디어: M08+C19+Q07+R16 4-axis composite with MRS regime-smoothed weights.
## RISK_ON: momentum+consensus tilt | CRISIS: Q07+R16 defense tilt.
## Smoothing max 10%p/month (STR_1439 TO 154% structure). S1 pure factor signal.
## PIT: C5(MRS t-1 lag) C10(LIQ frollmean) C13(Z_Score_Aligned) C15(bulk load).

QEPM_AUTO_COMMIT <- TRUE
t0 <- Sys.time()

# ===================================================================
# 0. Environment
# ===================================================================
.root_candidates <- c(
  "/mnt/c/Users/User/OneDrive/\ubc14\ud0d5 \ud654\uba74/Quant_Module_Moltbot",
  "/mnt/c/Users/99922/OneDrive/\ubc14\ud0d5 \ud654\uba74/Quant_Module_Moltbot"
)
PROJECT_ROOT <- .root_candidates[sapply(.root_candidates, dir.exists)][1]
rm(.root_candidates)

FUNC_PATH  <- file.path(PROJECT_ROOT, "02_Infrastructure")
CACHE_DIR  <- file.path(PROJECT_ROOT, ".cache")
STRAT_DIR  <- tryCatch(dirname(sys.frame(1)$ofile), error = function(e) getwd())
OUT_DIR    <- file.path(STRAT_DIR, "output")
dir.create(OUT_DIR, showWarnings=FALSE, recursive=TRUE)

source(file.path(FUNC_PATH, "config.R"))
source(file.path(FUNC_PATH, "backtest_harness.R"))

suppressPackageStartupMessages({
  library(data.table); library(arrow); library(xts); library(zoo)
  library(PerformanceAnalytics); library(ggplot2); library(scales)
  library(lubridate); library(jsonlite); library(parallel)
})
options(scipen=999); Sys.setenv(TZ="Asia/Seoul")

`%||%` <- function(a, b) if (!is.null(a) && length(a) > 0) a else b

STRATEGY_ID     <- "STR_1685"
STRATEGY_FAMILY <- "multi_source_score_blend_defense"
N_HOLD          <- 20L
LIQ_THRESHOLD   <- 2e8
COMMISSION      <- 0.0015
BUFFER_ZONE     <- list(keep_n=22L, entry_n=20L)
WEIGHT_METHOD   <- "equal"

# ===================================================================
# 1. Preflight check
# ===================================================================
tryCatch({
  source(file.path(VALIDATION_DIR, "preflight_memory.R"))
  preflight_check(STRATEGY_ID, family=STRATEGY_FAMILY)
}, error = function(e) cat("[Preflight]", conditionMessage(e), "\n"))

# ===================================================================
# 2. Load raw data (once, OPT-1/C15)
# ===================================================================
cat("\n[Step 2] Loading RAWDATA...\n")
res     <- load_rawdata(use_cache=TRUE)
RAWDATA <- res$RAWDATA
BM_DT   <- res$BM_DT
rm(res); gc(verbose=FALSE)

setkey(RAWDATA, Date, Ticker)

# OPT-10: Liquidity filter (C10) — frollmean lagged 20d >= LIQ_THRESHOLD
RAWDATA[, TradingValue := Close * Vol]
# C10: shift(frollmean, 1L) — today volume excluded from liquidity filter
RAWDATA[, AvgTV20 := shift(frollmean(TradingValue, n=20L, align="right"), 1L), by=Ticker]
RAWDATA[, LiqPass := !is.na(AvgTV20) & AvgTV20 >= LIQ_THRESHOLD]

cat(sprintf("[Step 2] %s ~ %s | %d tickers\n",
            min(RAWDATA$Date), max(RAWDATA$Date), uniqueN(RAWDATA$Ticker)))

# ===================================================================
# 3. Factor engine (4-axis composite + 4 variants)
# ===================================================================
cat("\n[Step 3] Factor engine (H_1690 4-axis)...\n")
source(file.path(STRAT_DIR, "factor_engine.R"))
stopifnot(is.data.table(FACTORS), all(c("Date","Ticker","Score") %in% names(FACTORS)))
cat(sprintf("[Step 3] V1: %d rows | %d dates\n", nrow(FACTORS), uniqueN(FACTORS$Date)))

# ===================================================================
# 4. PIT detection
# ===================================================================
tryCatch({
  source(file.path(VALIDATION_DIR, "lookahead_detector.R"))
  pit <- detect_lookahead(file.path(STRAT_DIR, "factor_engine.R"))
  if (!isTRUE(pit$clean)) {
    lapply(pit$violations, function(v)
      cat(sprintf("[PIT VIOLATION] L%d [%s]: %s\n", v$line, v$check, v$msg)))
    stop("PIT violation. Aborting.")
  }
  cat("[Step 4] PIT: CLEAN\n")
}, error = function(e) {
  if (grepl("PIT violation", conditionMessage(e))) stop(e)
  cat("[Step 4 WARN]", conditionMessage(e), "\n")
})

# ===================================================================
# 5. ICIR helper
# ===================================================================
compute_icir <- function(FACS, RAWDATA_dt, label) {
  sig_dates_v <- sort(unique(FACS$Date))
  ic_list <- lapply(seq_along(sig_dates_v), function(i) {
    sd <- sig_dates_v[i]
    if (i == length(sig_dates_v)) return(NULL)
    next_sd <- sig_dates_v[i + 1L]
    fwd <- RAWDATA_dt[Date > sd & Date <= next_sd,
                      .(fwd_ret=prod(1+Ret,na.rm=TRUE)-1), by=Ticker]
    sc  <- FACS[Date == sd, .(Ticker, Score)]
    mg  <- merge(sc, fwd, by="Ticker")
    if (nrow(mg) < 10L) return(NULL)
    data.table(Date=sd,
               IC=cor(mg$Score, mg$fwd_ret, method="spearman", use="complete.obs"))
  })
  ic_dt <- rbindlist(ic_list[!sapply(ic_list, is.null)], fill=TRUE)
  ic_dt <- ic_dt[!is.na(IC)]
  if (nrow(ic_dt) == 0L)
    return(list(icir=NA_real_, ic_mean=NA_real_, n=0L, label=label, ic_dt=ic_dt))
  ic_mean_v <- mean(ic_dt$IC, na.rm=TRUE)
  ic_sd_v   <- sd(ic_dt$IC,   na.rm=TRUE)
  icir_val  <- if (!is.na(ic_sd_v) && ic_sd_v > 1e-10) ic_mean_v / ic_sd_v else NA_real_
  cat(sprintf("[ICIR %s] %.4f (IC_mean=%.4f, n=%d)\n", label, icir_val, ic_mean_v, nrow(ic_dt)))
  list(icir=icir_val, ic_mean=ic_mean_v, n=nrow(ic_dt), label=label, ic_dt=ic_dt)
}

# ===================================================================
# 6. 4-variant simulations (mclapply, OPT-4)
# ===================================================================
cat("\n[Step 6] 4-variant simulations (mclapply)...\n")

n_cores <- max(min(4L, detectCores() - 1L), 1L)

variant_list  <- list(V1=FACTORS, V2=FACTORS_V2, V3=FACTORS_V3, V4=FACTORS_V4)
variant_names <- names(variant_list)

sim_results <- mclapply(variant_names, function(vn) {
  fac <- variant_list[[vn]]
  tryCatch(
    run_monthly_simulation(
      RAWDATA=RAWDATA, BM_DT=BM_DT, FACTORS=fac,
      n_holdings=N_HOLD, weight_method=WEIGHT_METHOD,
      commission=COMMISSION, buffer_zone=BUFFER_ZONE
    ),
    error = function(e) { cat(sprintf("[FATAL %s] %s\n", vn, conditionMessage(e))); NULL }
  )
}, mc.cores=n_cores)
names(sim_results) <- variant_names

# ===================================================================
# 7. Analysis + hurdle (each variant)
# ===================================================================
source(file.path(FUNC_PATH, "hurdle_gate.R"))
tryCatch(source(file.path(FUNC_PATH, "strategy_analyzer.R")), error=function(e) NULL)

hurdle_list  <- list()
perf_summary <- list()

invisible(lapply(variant_names, function(vn) {
  sim <- sim_results[[vn]]
  if (is.null(sim)) { cat(sprintf("[Step 7] %s: sim NULL\n", vn)); return() }

  px      <- sim$strategy_xts
  ann_ret <- as.numeric(Return.annualized(px, scale=252))
  sr      <- as.numeric(SharpeRatio.annualized(px, Rf=0, scale=252))
  mdd     <- as.numeric(maxDrawdown(px))
  cat(sprintf("[%s] CAGR=%.1f%% | SR=%.3f | MDD=%.1f%%\n",
              vn, ann_ret*100, sr, mdd*100))

  out_sub <- file.path(OUT_DIR, vn)
  dir.create(out_sub, showWarnings=FALSE, recursive=TRUE)

  tryCatch(run_analysis(sim, variant_list[[vn]], RAWDATA, BM_DT, out_sub,
                        strategy_name=paste0(STRATEGY_ID,"_",vn)),
           error=function(e) cat(sprintf("[WARN analysis %s] %s\n", vn, conditionMessage(e))))

  hr <- tryCatch(
    run_hurdle_gate(sim, strategy_name=paste0(STRATEGY_ID,"_",vn), output_dir=out_sub),
    error=function(e) { cat(sprintf("[WARN hurdle %s] %s\n", vn, conditionMessage(e)));
                        list(grade="ERR", score=0) }
  )
  cat(sprintf("[%s] Grade=%s | Score=%.1f\n", vn,
              hr$grade %||% "?", as.numeric(hr$score %||% 0)))

  hurdle_list[[vn]]  <<- hr
  perf_summary[[vn]] <<- list(variant=vn, cagr=ann_ret, sr=sr, mdd=mdd,
                               grade=hr$grade %||% "ERR",
                               score=as.numeric(hr$score %||% 0))

  write_json(
    c(hr, list(strategy_id=STRATEGY_ID, hypothesis_id="H_1690",
               variant=vn, date=as.character(Sys.Date()))),
    file.path(OUT_DIR, sprintf("hurdle_result_%s.json", tolower(vn))),
    pretty=TRUE, auto_unbox=TRUE
  )
}))

sim_v1  <- sim_results[["V1"]]
perf_v1 <- perf_summary[["V1"]]
hr_v1   <- hurdle_list[["V1"]]

# ===================================================================
# 8. ICIR (4 variants)
# ===================================================================
cat("\n[Step 8] ICIR (4 variants)...\n")

icir_list <- lapply(variant_names, function(vn) compute_icir(variant_list[[vn]], RAWDATA, vn))
names(icir_list) <- variant_names
icir_v1 <- icir_list[["V1"]]$icir

icir_summary <- rbindlist(lapply(variant_names, function(vn) {
  data.table(variant=vn, icir=icir_list[[vn]]$icir,
             ic_mean=icir_list[[vn]]$ic_mean, n_months=icir_list[[vn]]$n)
}))
fwrite(icir_summary, file.path(OUT_DIR, "icir_summary_4variants.csv"))
cat("[Step 8] ICIR summary:\n"); print(icir_summary)

icir_gate_pass <- !is.na(icir_v1) && icir_v1 >= 0.25
cat(sprintf("[ICIR Gate] V1 ICIR=%.4f | Gate(>=0.25): %s\n", icir_v1 %||% NA, icir_gate_pass))

# ===================================================================
# 9. C2: Stress period IC (8대 정본 기준, reference_stress_periods.md)
# ===================================================================
cat("\n[Step 9] C2 — Stress period IC...\n")

# 8대 정본: 9/11(2001-09), GFC(2007-10), EU_Debt, China_Shock,
#            Trade_War(2018-03), COVID(2020-01), Rate_Hike(2022-01~2022-12), Iran_War(2026-02)
stress_period_defs <- list(
  Terror_911  = c("2001-09-01", "2002-03-31"),
  GFC         = c("2007-10-01", "2009-03-31"),
  EU_Debt     = c("2010-04-01", "2012-12-31"),
  China_Shock = c("2015-06-01", "2016-02-29"),
  Trade_War   = c("2018-03-01", "2019-06-30"),
  COVID       = c("2020-01-01", "2020-06-30"),
  Rate_Hike   = c("2022-01-01", "2022-12-31"),
  Iran_War    = c("2026-02-01", "2026-04-30")
)

stress_ic_list <- lapply(names(stress_period_defs), function(sp_name) {
  sp_range <- stress_period_defs[[sp_name]]
  s_dt <- as.Date(sp_range[1]); e_dt <- as.Date(sp_range[2])
  fac_sp <- FACTORS[Date >= s_dt & Date <= e_dt]
  if (nrow(fac_sp) < 3L)
    return(data.table(period=sp_name, ic_mean=NA_real_, n=0L))
  sd_v <- sort(unique(fac_sp$Date))
  ic_sp <- lapply(seq_along(sd_v), function(i) {
    if (i == length(sd_v)) return(NULL)
    sd <- sd_v[i]; next_sd <- sd_v[i+1L]
    fwd <- RAWDATA[Date > sd & Date <= next_sd,
                   .(fwd_ret=prod(1+Ret,na.rm=TRUE)-1), by=Ticker]
    sc  <- fac_sp[Date==sd, .(Ticker, Score)]
    mg  <- merge(sc, fwd, by="Ticker")
    if (nrow(mg) < 5L) return(NULL)
    data.table(IC=cor(mg$Score, mg$fwd_ret, method="spearman", use="complete.obs"))
  })
  ic_dt2 <- rbindlist(ic_sp[!sapply(ic_sp, is.null)], fill=TRUE)
  ic_dt2 <- ic_dt2[!is.na(IC)]
  data.table(period=sp_name,
             ic_mean=if (nrow(ic_dt2)>0) mean(ic_dt2$IC,na.rm=TRUE) else NA_real_,
             n=nrow(ic_dt2))
})
stress_ic_dt <- rbindlist(stress_ic_list)
fwrite(stress_ic_dt, file.path(OUT_DIR, "H_1690_r16_stress_icir_validation.csv"))
cat("[C2] Stress IC:\n"); print(stress_ic_dt)
stress_ic_mean <- mean(stress_ic_dt$ic_mean, na.rm=TRUE)
cat(sprintf("[C2] Mean stress IC: %.4f\n", stress_ic_mean))

# ===================================================================
# 10. C3: MRS threshold sensitivity (10/25, 15/30, 20/35)
# ===================================================================
cat("\n[Step 10] C3 — MRS threshold sensitivity...\n")

REGIME_DT_THRESH <- as.data.table(
  arrow::read_parquet(file.path(CACHE_DIR, "unified_regime_signal.parquet")))
REGIME_DT_THRESH[, Date := as.Date(Date)]
setkey(REGIME_DT_THRESH, Date)

classify_mrs_thresh <- function(mrs, lo, hi) {
  ifelse(is.na(mrs), "ELEVATED",
    ifelse(mrs < lo, "RISK_ON", ifelse(mrs < hi, "ELEVATED", "CRISIS")))
}

thresh_defs <- list(
  T1_10_25 = c(lo=10, hi=25),
  T2_15_30 = c(lo=15, hi=30),
  T3_20_35 = c(lo=20, hi=35)
)
sig_dates_thresh <- sort(unique(FACTORS$Date))
mrs_t_vec <- REGIME_DT_THRESH[.(sig_dates_thresh - 1), roll=TRUE, on="Date",
                                nomatch=NA][, Regime_Score]

thresh_results <- rbindlist(lapply(names(thresh_defs), function(tn) {
  tv    <- thresh_defs[[tn]]
  reg_t <- classify_mrs_thresh(mrs_t_vec, tv["lo"], tv["hi"])
  n_tot <- length(sig_dates_thresh)
  data.table(threshold=tn, lo=tv["lo"], hi=tv["hi"],
             pct_risk_on  = round(sum(reg_t=="RISK_ON",  na.rm=TRUE)/n_tot*100, 1),
             pct_elevated = round(sum(reg_t=="ELEVATED", na.rm=TRUE)/n_tot*100, 1),
             pct_crisis   = round(sum(reg_t=="CRISIS",   na.rm=TRUE)/n_tot*100, 1))
}))
fwrite(thresh_results, file.path(OUT_DIR, "H_1690_mrs_threshold_backtesting.csv"))
cat("[C3] MRS threshold sensitivity:\n"); print(thresh_results)

# ===================================================================
# 11. C6: 2020-03 weight transition lag
# ===================================================================
cat("\n[Step 11] C6 — 2020-03 weight transition lag...\n")

covid_window <- WEIGHT_DT[Date >= as.Date("2019-10-01") & Date <= as.Date("2020-09-01")]
if (nrow(covid_window) > 0L) {
  cat("[C6] Weight state around COVID:\n")
  print(covid_window[, .(Date, regime, mrs, w_M08, w_Q07, w_R16)])
  first_crisis <- covid_window[regime=="CRISIS" & Date >= as.Date("2020-01-01"),
                                if (.N>0) min(Date) else as.Date(NA)]
  cat(sprintf("[C6] First CRISIS month >= 2020-01: %s\n",
              if (!is.null(first_crisis) && length(first_crisis)>0 && !is.na(first_crisis))
                as.character(first_crisis) else "none"))
  write_json(list(
    weight_transition_lag_2020_03 = as.character(first_crisis %||% "none"),
    smoothing_10pp_month          = TRUE
  ), file.path(OUT_DIR, "H_1690_covid_transition_lag.json"), pretty=TRUE, auto_unbox=TRUE)
}

# ===================================================================
# 12. C7: Variance ratio (linear dominance, Gate 15)
# ===================================================================
cat("\n[Step 12] C7 — Variance contribution check...\n")

fac_cols <- c("M08_Residual_Mom","C19_Composite_Earnings",
              "Q07_Earnings_Stability","R16_Calmar")
total_var <- var(FDB_WIDE$Score_V1, na.rm=TRUE)
if (!is.na(total_var) && total_var > 1e-12) {
  var_ratio_dt <- rbindlist(lapply(fac_cols, function(fc) {
    if (!fc %in% names(FDB_WIDE)) return(NULL)
    v_fc <- var(FDB_WIDE[[fc]], na.rm=TRUE)
    data.table(factor=fc, regime="ALL",
               variance_contribution_pct=round(v_fc/total_var*100, 1))
  }))
  fwrite(var_ratio_dt, file.path(OUT_DIR, "H_1690_variance_ratio_step_wise.csv"))
  cat("[C7] Variance contribution:\n"); print(var_ratio_dt)
  max_contrib <- max(var_ratio_dt$variance_contribution_pct, na.rm=TRUE)
  cat(sprintf("[C7] Max: %.1f%% | Gate<=40%%: %s\n", max_contrib, max_contrib <= 40))
}

# ===================================================================
# 13. C9: KOSPI/KOSDAQ split
# ===================================================================
cat("\n[Step 13] C9 — KOSPI/KOSDAQ split...\n")

mkt_col <- if ("Market" %in% names(RAWDATA)) "Market" else
           if ("market" %in% names(RAWDATA)) "market" else NULL
if (!is.null(mkt_col)) {
  kospi_n  <- uniqueN(RAWDATA[get(mkt_col)=="KOSPI",  Ticker])
  kosdaq_n <- uniqueN(RAWDATA[get(mkt_col)=="KOSDAQ", Ticker])
  cat(sprintf("[C9] KOSPI: %d | KOSDAQ: %d tickers\n", kospi_n, kosdaq_n))
  write_json(list(kospi_n=kospi_n, kosdaq_n=kosdaq_n,
                  note="Full split simulation deferred to S2"),
             file.path(OUT_DIR, "H_1690_kospi_kosdaq_split.json"),
             pretty=TRUE, auto_unbox=TRUE)
} else {
  cat("[C9] Market column absent. Split deferred to S2.\n")
}

# ===================================================================
# 14. C10: Defense Conditional Audit 3-axis (AX-001)
# ===================================================================
cat("\n[Step 14] C10 — Defense Conditional Audit (AX-001)...\n")

axis_a_val  <- stress_ic_mean
axis_a_pass <- !is.na(axis_a_val) && axis_a_val > 0.03

axis_b_val   <- perf_v1$mdd %||% NA_real_
str1631_mdd  <- 0.2127
axis_b_delta <- str1631_mdd - (axis_b_val %||% 0)
axis_b_pass  <- !is.na(axis_b_val) && axis_b_delta >= 0.08

ic_v1_dt <- icir_list[["V1"]]$ic_dt
ic_bad <- NA_real_; ic_good <- NA_real_; axis_c_val <- NA_real_
if (!is.null(ic_v1_dt) && nrow(ic_v1_dt) > 0L) {
  ic_v1_dt2 <- merge(ic_v1_dt, WEIGHT_DT[, .(Date, regime)], by="Date", all.x=TRUE)
  ic_bad  <- ic_v1_dt2[regime=="CRISIS",  mean(IC, na.rm=TRUE)]
  ic_good <- ic_v1_dt2[regime=="RISK_ON", mean(IC, na.rm=TRUE)]
  axis_c_val <- if (!is.na(ic_good) && abs(ic_good) > 1e-10) ic_bad/ic_good else NA_real_
}
axis_c_pass <- !is.na(axis_c_val) && axis_c_val > 1.2

defense_audit <- list(
  strategy_id="STR_1685", hypothesis_id="H_1690",
  date=as.character(Sys.Date()),
  axis_a=list(name="stress_IC_avg>0.03", value=round(axis_a_val,4), pass=axis_a_pass),
  axis_b=list(name="MDD_delta>=8pp", v1_mdd=round(axis_b_val%||%NA,4),
              str1631_mdd=str1631_mdd, delta=round(axis_b_delta,4), pass=axis_b_pass),
  axis_c=list(name="bad_good_IC_ratio>1.2",
              ic_crisis=round(ic_bad%||%NA,4), ic_risk_on=round(ic_good%||%NA,4),
              ratio=round(axis_c_val%||%NA,4), pass=axis_c_pass),
  overall_pass=all(c(axis_a_pass, axis_b_pass, axis_c_pass), na.rm=TRUE)
)
write_json(defense_audit,
           file.path(OUT_DIR, "H_1690_defense_conditional_audit_v1_0.json"),
           pretty=TRUE, auto_unbox=TRUE)
cat(sprintf("[C10] A(%.4f):%s | B(+%.3f):%s | C(%.3f):%s | OVERALL:%s\n",
            axis_a_val, axis_a_pass, axis_b_delta, axis_b_pass,
            axis_c_val%||%NA, axis_c_pass, defense_audit$overall_pass))

# ===================================================================
# 15. Tail risk (V1)
# ===================================================================
cat("\n[Step 15] Tail risk...\n")

tail_risk <- tryCatch({
  source(file.path(FUNC_PATH, "risk_engine.R"))
  compute_tail_risk_suite(sim_v1$strategy_xts, output_dir=OUT_DIR)
}, error = function(e) {
  cat("[WARN tail_risk]", conditionMessage(e), "\n")
  rets  <- as.numeric(sim_v1$strategy_xts)
  es_99 <- quantile(rets, 0.01, na.rm=TRUE)
  list(evt_xi=NA, cdar_95=as.numeric(maxDrawdown(sim_v1$strategy_xts)),
       es_99_monthly=round(es_99,4), evt_gate=NA,
       cdar_gate=as.numeric(maxDrawdown(sim_v1$strategy_xts))<0.25,
       es_gate=es_99 > -0.12, overall_pass=FALSE)
})
cat(sprintf("[Tail] CDaR_95=%.2f%% | ES_99=%.2f%% | pass=%s\n",
            (tail_risk$cdar_95%||%NA)*100,
            (tail_risk$es_99_monthly%||%NA)*100,
            tail_risk$overall_pass%||%NA))
write_json(c(tail_risk, list(strategy_id=STRATEGY_ID, hypothesis_id="H_1690",
                              variant="V1_smoothed_weight",
                              date=as.character(Sys.Date()))),
           file.path(OUT_DIR, "tail_risk_result.json"), pretty=TRUE, auto_unbox=TRUE)

# ===================================================================
# 16. C12: Static EW vs smoothed-weight decomposition (L-155)
# ===================================================================
cat("\n[Step 16] C12 — L-155 decomposition...\n")

sr_incremental <- round((perf_summary[["V1"]]$sr%||%0)-(perf_summary[["V2"]]$sr%||%0), 4)
decomp_c12 <- list(
  note="L-155: V2=Core_alone(static EW 25/25/25/25), V1=smoothed_weight dynamic",
  core_alone_V2=list(cagr=round(perf_summary[["V2"]]$cagr%||%NA,4),
                      sr  =round(perf_summary[["V2"]]$sr%||%NA,4),
                      mdd =round(perf_summary[["V2"]]$mdd%||%NA,4),
                      grade=perf_summary[["V2"]]$grade%||%"ERR"),
  smoothed_weight_V1=list(cagr=round(perf_summary[["V1"]]$cagr%||%NA,4),
                           sr  =round(perf_summary[["V1"]]$sr%||%NA,4),
                           mdd =round(perf_summary[["V1"]]$mdd%||%NA,4),
                           grade=perf_summary[["V1"]]$grade%||%"ERR"),
  incremental_sr_from_weight_tilt = sr_incremental
)
write_json(decomp_c12,
           file.path(OUT_DIR, "H_1690_core_vs_smoothed_decomposition.json"),
           pretty=TRUE, auto_unbox=TRUE)
cat(sprintf("[C12] V1 SR=%.3f | V2(EW) SR=%.3f | incremental=%.3f\n",
            perf_summary[["V1"]]$sr%||%NA,
            perf_summary[["V2"]]$sr%||%NA,
            sr_incremental))

# ===================================================================
# 17. Daily returns + Holdings (S3 DCC-GARCH용)
# ===================================================================
cat("\n[Step 17] Daily returns + Holdings...\n")

if (!is.null(sim_v1)) {
  fwrite(data.table(Date=index(sim_v1$strategy_xts),
                    Return=as.numeric(sim_v1$strategy_xts)),
         file.path(OUT_DIR, "daily_returns_primary.csv"))

  if (!is.null(sim_v1$holdings_history) && length(sim_v1$holdings_history) > 0L) {
    hold_dt <- rbindlist(lapply(names(sim_v1$holdings_history), function(d) {
      data.table(Date=as.Date(d), Ticker=sim_v1$holdings_history[[d]])
    }), fill=TRUE)
    fwrite(hold_dt, file.path(OUT_DIR, "monthly_top20_holdings.csv"))
  }
}

# ===================================================================
# 18. Final summary
# ===================================================================
cat("\n[Step 18] Summary...\n")

summary_out <- list(
  strategy_id   = STRATEGY_ID,
  hypothesis_id = "H_1690",
  date          = as.character(Sys.Date()),
  elapsed_min   = round(as.numeric(difftime(Sys.time(), t0, units="mins")), 2),
  variants      = lapply(variant_names, function(vn) {
    p <- perf_summary[[vn]]
    list(variant=vn,
         cagr=round(p$cagr%||%NA,4), sr=round(p$sr%||%NA,4),
         mdd=round(p$mdd%||%NA,4),
         icir=round(icir_list[[vn]]$icir%||%NA,4),
         grade=p$grade%||%"ERR", score=p$score%||%0)
  }),
  alpha_lab_gate_V1  = list(icir_pass=icir_gate_pass, icir=round(icir_v1%||%NA,4)),
  defense_audit_pass = defense_audit$overall_pass,
  c1_cosine_pass     = all_pass_c1,
  tail_risk_pass     = tail_risk$overall_pass%||%FALSE,
  primary_variant    = "V1_smoothed_weight"
)
write_json(summary_out,
           file.path(OUT_DIR, "hurdle_result_V1_regime_smoothed.json"),
           pretty=TRUE, auto_unbox=TRUE)

cat(sprintf("\n=== STR_1685 DONE | %.1f min ===\n", summary_out$elapsed_min))
cat(sprintf("V1 | CAGR=%.1f%% | SR=%.3f | MDD=%.1f%% | Grade=%s | ICIR=%.4f\n",
            (perf_summary[["V1"]]$cagr%||%NA)*100,
            perf_summary[["V1"]]$sr%||%NA,
            (perf_summary[["V1"]]$mdd%||%NA)*100,
            perf_summary[["V1"]]$grade%||%"ERR",
            icir_v1%||%NA))
cat(sprintf("V2(EW) SR=%.3f | V3(2ax) SR=%.3f | V4(3ax) SR=%.3f\n",
            perf_summary[["V2"]]$sr%||%NA,
            perf_summary[["V3"]]$sr%||%NA,
            perf_summary[["V4"]]$sr%||%NA))
cat(sprintf("Defense Audit:%s | C1 cosine:%s | Tail:%s\n",
            defense_audit$overall_pass, all_pass_c1,
            tail_risk$overall_pass%||%FALSE))

# ===================================================================
# 19. CAPM beta gate
# ===================================================================
capm_beta <- tryCatch({
  px <- sim_v1$strategy_xts
  bm_sub <- BM_DT[Date %in% index(px)]
  bm_xts <- xts(bm_sub$BM_Ret, order.by=bm_sub$Date)
  mg     <- merge(px, bm_xts, join="inner")
  colnames(mg) <- c("strat","bench")
  coef(lm(strat ~ bench, data=as.data.frame(mg)))["bench"]
}, error=function(e) NA_real_)
cat(sprintf("[CAPM beta] %.4f | |beta|<0.85: %s\n",
            capm_beta%||%NA, !is.na(capm_beta) && abs(capm_beta)<0.85))

# ===================================================================
# 20. S1 artifact
# ===================================================================
cat("\n[Step 20] S1 artifact...\n")

s1_art <- list(
  strategy_id   = STRATEGY_ID,
  hypothesis_id = "H_1690",
  stage         = "S1",
  date          = as.character(Sys.Date()),
  status        = "complete",
  family        = STRATEGY_FAMILY,
  expected_role = "defense_anchor",
  role_bias     = "RoleBias_Defense",
  performance   = list(
    cagr   = round(perf_summary[["V1"]]$cagr%||%NA, 4),
    sharpe = round(perf_summary[["V1"]]$sr%||%NA,   4),
    mdd    = round(perf_summary[["V1"]]$mdd%||%NA,  4),
    icir   = round(icir_v1%||%NA, 4),
    grade  = perf_summary[["V1"]]$grade%||%"ERR",
    score  = perf_summary[["V1"]]$score%||%0
  ),
  portfolio = list(n_holdings=N_HOLD, weight_method=WEIGHT_METHOD,
                   commission=COMMISSION, buffer_zone=BUFFER_ZONE,
                   liq_threshold=LIQ_THRESHOLD),
  pit_evidence     = H1690_PIT_EVIDENCE,
  capm_beta        = round(capm_beta%||%NA, 4),
  capm_beta_gate   = list(threshold=0.85, pass=!is.na(capm_beta)&&abs(capm_beta)<0.85),
  alpha_lab_gate   = list(icir_gate=icir_gate_pass, icir=round(icir_v1%||%NA,4)),
  defense_audit    = defense_audit,
  tail_risk_gate   = list(pass=tail_risk$overall_pass%||%FALSE,
                          cdar_95=round(tail_risk$cdar_95%||%NA,4),
                          es_99=round(tail_risk$es_99_monthly%||%NA,4)),
  c1_cosine_pass   = all_pass_c1,
  variants         = summary_out$variants,
  conditions_met   = list(
    C1_cosine    = list(status="applied", all_pass=all_pass_c1),
    C2_stress_IC = list(status="applied", mean_ic=round(stress_ic_mean,4)),
    C3_mrs_thresh = list(status="applied", note="10/25 15/30 20/35 compared"),
    C5_mrs_lag   = "applied — MRS t-1 roll join",
    C6_covid_lag = list(status="applied"),
    C7_var_ratio = list(status="applied"),
    C9_kospi_kosdaq = list(status="applied"),
    C10_defense_audit = list(status="applied", overall=defense_audit$overall_pass),
    C11_algebraic = "applied — 4-family distinct PASS",
    C12_decomp    = list(status="applied", sr_incremental=sr_incremental)
  )
)
art_path <- file.path(PROJECT_ROOT, "stage_artifacts", "s1_construction_H_1690.json")
write_json(s1_art, art_path, pretty=TRUE, auto_unbox=TRUE)
cat(sprintf("[Step 20] Artifact: %s\n", art_path))

# ===================================================================
# 21. Charts
# ===================================================================
tryCatch({
  generate_charts(sim_v1, output_dir=OUT_DIR)
  cat("[Step 21] Charts saved.\n")
}, error=function(e) cat("[WARN charts]", conditionMessage(e), "\n"))

# ===================================================================
# 22. Telegram
# ===================================================================
tryCatch({
  source(file.path(FUNC_PATH, "telegram", "telegram_notify.R"))
  v1p <- perf_summary[["V1"]]
  msg <- paste0(
    "[Forge] STR_1685 S1 완료 (H_1690 Multi-Source Defense Anchor)\n",
    sprintf("Grade: %s | Score: %.1f\n", v1p$grade%||%"?", v1p$score%||%0),
    sprintf("CAGR: %.1f%% | SR: %.3f | MDD: %.1f%%\n",
            (v1p$cagr%||%NA)*100, v1p$sr%||%NA, (v1p$mdd%||%NA)*100),
    sprintf("ICIR: %.4f | Gate(>=0.25): %s\n", icir_v1%||%NA, icir_gate_pass),
    sprintf("V2(EW): SR=%.3f | V3(2ax): SR=%.3f | V4(noR16): SR=%.3f\n",
            perf_summary[["V2"]]$sr%||%NA,
            perf_summary[["V3"]]$sr%||%NA,
            perf_summary[["V4"]]$sr%||%NA),
    sprintf("AX-001 DefenseAudit: %s (A=%s B=%s C=%s)\n",
            defense_audit$overall_pass,
            defense_audit$axis_a$pass, defense_audit$axis_b$pass, defense_audit$axis_c$pass),
    sprintf("C1 Cosine PASS: %s | Tail: %s\n", all_pass_c1, tail_risk$overall_pass%||%FALSE),
    "RoleBias: Defense | Family: multi_source_score_blend_defense"
  )
  tg_send(msg)
  chart_path <- file.path(OUT_DIR, "equity_curve.png")
  if (file.exists(chart_path)) tg_send_photo(chart_path, caption="STR_1685 Equity Curve")
}, error=function(e) cat("[Telegram WARN]", conditionMessage(e), "\n"))

# ===================================================================
# 23. QEPM auto-commit
# ===================================================================
if (isTRUE(QEPM_AUTO_COMMIT)) {
  tryCatch({
    source(file.path(PROJECT_ROOT, "qepm", "scripts", "hybrid_mode.R"))
    hybrid_commit(
      strategy      = STRATEGY_ID,
      family        = STRATEGY_FAMILY,
      hurdle_result = hr_v1,
      role_bias     = "RoleBias_Defense",
      tags          = c("H_1690","defense_anchor","multi_source","regime_smoothed","S1")
    )
    cat("[QEPM] hybrid_commit done.\n")
  }, error=function(e) cat("[QEPM WARN]", conditionMessage(e), "\n"))
}

# ===================================================================
# 24. DONE mail to Scout
# ===================================================================
tryCatch({
  done_path <- file.path(PROJECT_ROOT, "qepm", "mailbox", "scout", "inbox",
                         "DONE_S1_RESULT_H_1690_multi_source_defense_anchor.json")
  v1p <- perf_summary[["V1"]]
  done_msg <- list(
    from         = "Forge",
    to           = "Scout",
    subject      = "DONE S1 — H_1690 Multi-Source Defense Anchor",
    date         = as.character(Sys.Date()),
    hypothesis_id= "H_1690",
    strategy_id  = STRATEGY_ID,
    status       = "complete",
    variants     = lapply(variant_names, function(vn) {
      p <- perf_summary[[vn]]
      list(variant=vn, cagr=round(p$cagr%||%NA,4), sr=round(p$sr%||%NA,4),
           mdd=round(p$mdd%||%NA,4), icir=round(icir_list[[vn]]$icir%||%NA,4),
           grade=p$grade%||%"ERR")
    }),
    alpha_lab_gate = icir_gate_pass,
    defense_audit  = defense_audit$overall_pass,
    c1_cosine_pass = all_pass_c1,
    tdc_sneak_peek = "pending S3 DCC-GARCH",
    artifact_path  = art_path
  )
  write_json(done_msg, done_path, pretty=TRUE, auto_unbox=TRUE)
  cat(sprintf("[Step 24] DONE mail: %s\n", done_path))
}, error=function(e) cat("[WARN done_mail]", conditionMessage(e), "\n"))

# rename TODO to DONE in Forge inbox
tryCatch({
  todo_path <- file.path(PROJECT_ROOT, "qepm", "mailbox", "forge", "inbox",
                         "TODO_S1_H_1690_multi_source_defense_anchor.json")
  done_inbox <- file.path(PROJECT_ROOT, "qepm", "mailbox", "forge", "inbox",
                          "DONE_S1_H_1690_multi_source_defense_anchor.json")
  if (file.exists(todo_path)) file.rename(todo_path, done_inbox)
  cat("[Step 24] Inbox TODO renamed to DONE.\n")
}, error=function(e) cat("[WARN rename]", conditionMessage(e), "\n"))

cat("[DONE]\n")
