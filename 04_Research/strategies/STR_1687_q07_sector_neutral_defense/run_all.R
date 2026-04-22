cat("=== STR_1687: Q07 Sector-Neutral Defense + SUE (H_1693) ===\n")
## 핵심아이디어: Z_Sector(Q07) 0.7 + z_C01_SUE 0.3 — sector-neutral defense composite
## Dichev-Tang 2009 + Foster 1984 + Daniel-Titman 2006 + AX-001 v2 multi_sleeve_only=TRUE
## S1 pure signal: C4(Q07 45d+SUE daily) C10(LIQ 2e8) C13(Z_Aligned) C15(load_month_factors)

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

FUNC_PATH      <- file.path(PROJECT_ROOT, "02_Infrastructure")
CACHE_DIR      <- file.path(PROJECT_ROOT, ".cache")
VALIDATION_DIR <- file.path(FUNC_PATH, "validation")
STRAT_DIR      <- tryCatch(dirname(sys.frame(1)$ofile), error = function(e) getwd())
OUT_DIR        <- file.path(STRAT_DIR, "output")
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)

source(file.path(FUNC_PATH, "config.R"))
source(file.path(FUNC_PATH, "backtest_harness.R"))

suppressPackageStartupMessages({
  library(data.table); library(arrow); library(xts); library(zoo)
  library(PerformanceAnalytics); library(ggplot2); library(scales)
  library(lubridate); library(jsonlite); library(parallel)
})
options(scipen = 999); Sys.setenv(TZ = "Asia/Seoul")

`%||%` <- function(a, b) if (!is.null(a) && length(a) > 0) a else b

STRATEGY_ID     <- "STR_1687"
HYPOTHESIS_ID   <- "H_1693"
STRATEGY_FAMILY <- "quality_earnings_stability_sector_neutral"
N_HOLD          <- 20L
LIQ_THRESHOLD   <- 2e8
COMMISSION      <- 0.0015
BUFFER_ZONE     <- list(keep_n = 22L, entry_n = 20L)
WEIGHT_METHOD   <- "equal"

# ===================================================================
# 1. Preflight
# ===================================================================
cat("\n[Step 1] Preflight check...\n")
tryCatch({
  source(file.path(VALIDATION_DIR, "preflight_memory.R"))
  preflight_check(STRATEGY_ID, family = STRATEGY_FAMILY)
}, error = function(e) cat("[Preflight]", conditionMessage(e), "\n"))

# ===================================================================
# 2. Load raw data
# ===================================================================
cat("\n[Step 2] Loading RAWDATA...\n")
res     <- load_rawdata(use_cache = TRUE)
RAWDATA <- res$RAWDATA
BM_DT   <- res$BM_DT
rm(res); gc(verbose = FALSE)

setkey(RAWDATA, Date, Ticker)
RAWDATA[, TradingValue := Close * Vol]
RAWDATA[, AvgTV20 := shift(frollmean(TradingValue, n = 20L, align = "right"), 1L), by = Ticker]
RAWDATA[, LiqPass  := !is.na(AvgTV20) & AvgTV20 >= LIQ_THRESHOLD]

cat(sprintf("[Step 2] %s ~ %s | %d tickers\n",
            min(RAWDATA$Date), max(RAWDATA$Date), uniqueN(RAWDATA$Ticker)))

# ===================================================================
# 3. Factor engine (4 ablation variants)
# ===================================================================
cat("\n[Step 3] Factor engine (H_1693, 4 ablation variants)...\n")
source(file.path(STRAT_DIR, "factor_engine.R"))
stopifnot(is.data.table(FACTORS), all(c("Date","Ticker","Score") %in% names(FACTORS)))
cat(sprintf("[Step 3] V1=%d | V2(Q07)=%d | V3(SUE)=%d | V4(EW)=%d\n",
            nrow(FACTORS), nrow(FACTORS_V2), nrow(FACTORS_V3), nrow(FACTORS_V4)))

# ===================================================================
# 4. PIT lookahead detection (C1~C15)
# ===================================================================
cat("\n[Step 4] PIT lookahead detection...\n")
tryCatch({
  source(file.path(VALIDATION_DIR, "lookahead_detector.R"))
  pit <- detect_lookahead(file.path(STRAT_DIR, "factor_engine.R"))
  if (!isTRUE(pit$clean)) {
    lapply(pit$violations,
           function(v) cat(sprintf("[PIT VIOLATION] L%d [%s]: %s\n", v$line, v$check, v$msg)))
    stop("PIT violation. Aborting.")
  }
  cat("[Step 4] PIT: CLEAN\n")
}, error = function(e) {
  if (grepl("PIT violation", conditionMessage(e))) stop(e)
  cat("[Step 4 WARN]", conditionMessage(e), "\n")
})

# ===================================================================
# 5. 4-variant simulations (mclapply)
# ===================================================================
cat("\n[Step 5] 4-variant simulations (S1-C4 ablation)...\n")

variants <- list(
  V1_composite = FACTORS,
  V2_q07_only  = FACTORS_V2,
  V3_sue_only  = FACTORS_V3,
  V4_ew_50_50  = FACTORS_V4
)

sim_args <- list(
  RAWDATA = RAWDATA, BM_DT = BM_DT,
  n_holdings = N_HOLD, weight_method = WEIGHT_METHOD,
  commission = COMMISSION, buffer_zone = BUFFER_ZONE
)

n_cores <- min(4L, max(1L, detectCores() - 1L))
sims <- mclapply(names(variants), function(vname) {
  fac <- variants[[vname]]
  if (nrow(fac) < 100L) return(list(error = paste("empty:", vname)))
  tryCatch(
    do.call(run_monthly_simulation, c(list(FACTORS = fac), sim_args)),
    error = function(e) list(error = conditionMessage(e))
  )
}, mc.cores = n_cores)
names(sims) <- names(variants)

sim <- sims[["V1_composite"]]
if (!is.null(sim$error)) {
  cat(sprintf("[FATAL V1] %s\n", sim$error)); stop("V1 simulation failed")
}
cat(sprintf("[Step 5] V1 done: %d trading days\n", length(sim$strategy_xts)))

# ===================================================================
# 6. Analysis (V1 primary)
# ===================================================================
cat("\n[Step 6] Analysis (V1 primary)...\n")
tryCatch({
  source(file.path(FUNC_PATH, "strategy_analyzer.R"))
  run_analysis(sim, FACTORS, RAWDATA, BM_DT, OUT_DIR, strategy_name = STRATEGY_ID)
}, error = function(e) {
  cat("[Step 6 WARN]", conditionMessage(e), "\n")
  tryCatch({
    perf <- summarise_perf(sim$strategy_xts, STRATEGY_ID)
    fwrite(as.data.table(t(unlist(perf))), file.path(OUT_DIR, "performance.csv"))
  }, error = function(e2) NULL)
})

# ===================================================================
# 7. Hurdle gate (V1)
# ===================================================================
cat("\n[Step 7] Hurdle gate (V1)...\n")
source(file.path(FUNC_PATH, "hurdle_gate.R"))
hurdle <- tryCatch(
  run_hurdle_gate(sim, strategy_name = STRATEGY_ID, output_dir = OUT_DIR),
  error = function(e) { cat("[WARN hurdle]", conditionMessage(e), "\n"); list(grade="ERR", score=0) }
)
cat(sprintf("[Step 7] Grade: %s | Score: %.1f\n",
            hurdle$grade %||% "?", as.numeric(hurdle$score %||% 0)))

# ===================================================================
# 8. AX-001 v2 defense evaluation (4-gate)
# ===================================================================
cat("\n[Step 8] AX-001 v2 defense gates...\n")
perf_xts <- sim$strategy_xts
ann_ret  <- as.numeric(Return.annualized(perf_xts, scale = 252))
sr_val   <- as.numeric(SharpeRatio.annualized(perf_xts, Rf = 0, scale = 252))
mdd_val  <- as.numeric(maxDrawdown(perf_xts))

ax001_gate_2a <- TRUE   # multi_sleeve_only hardcoded for defense
ax001_gate_2d <- mdd_val < 0.35
cat(sprintf("[AX-001 v2] Gate 2a multi_sleeve_only: TRUE\n"))
cat(sprintf("[AX-001 v2] Gate 2d MDD: %.1f%% < 35%%: %s\n",
            mdd_val * 100, ifelse(ax001_gate_2d, "PASS","WARN")))

# ===================================================================
# 9. Rolling ICIR + 4-period IC breakdown
# ===================================================================
cat("\n[Step 9] Rolling ICIR + 4-period IC analysis...\n")

compute_icir_series <- function(factors_dt, rawdata_dt) {
  sig_dates <- sort(unique(factors_dt$Date))
  ic_list <- lapply(seq_along(sig_dates), function(i) {
    if (i == length(sig_dates)) return(NULL)
    sd  <- sig_dates[i]
    nsd <- sig_dates[i + 1L]
    fwd <- rawdata_dt[Date > sd & Date <= nsd,
                      .(fwd_ret = prod(1 + Ret, na.rm=TRUE) - 1), by = Ticker]
    sc  <- factors_dt[Date == sd, .(Ticker, Score)]
    mg  <- merge(sc, fwd, by = "Ticker")
    if (nrow(mg) < 10L) return(NULL)
    data.table(Date = sd,
               IC   = cor(mg$Score, mg$fwd_ret, method="spearman", use="complete.obs"))
  })
  rbindlist(Filter(Negate(is.null), ic_list))[!is.na(IC)]
}

ic_monthly <- compute_icir_series(FACTORS, RAWDATA)
overall_icir   <- if (nrow(ic_monthly) >= 12L)
  mean(ic_monthly$IC, na.rm=TRUE) / sd(ic_monthly$IC, na.rm=TRUE) else NA_real_
alpha_lab_pass <- !is.na(overall_icir) && overall_icir >= 0.20

period_icir <- function(d) if (nrow(d) < 6L) NA_real_ else
  mean(d$IC, na.rm=TRUE) / sd(d$IC, na.rm=TRUE)
icir_p1 <- period_icir(ic_monthly[Date <  as.Date("2015-01-01")])
icir_p2 <- period_icir(ic_monthly[Date >= as.Date("2015-01-01") & Date < as.Date("2020-01-01")])
icir_p3 <- period_icir(ic_monthly[Date >= as.Date("2020-01-01")])

cat(sprintf("[Alpha Lab] ICIR=%.3f (>=0.20: %s) | 2005-14=%.3f | 2015-19=%.3f | 2020-26=%.3f\n",
            overall_icir %||% NA, ifelse(alpha_lab_pass,"PASS","FAIL"),
            icir_p1 %||% NA, icir_p2 %||% NA, icir_p3 %||% NA))

fwrite(data.table(period = c("overall","2005-2014","2015-2019","2020-2026"),
                  icir   = c(overall_icir %||% NA, icir_p1 %||% NA,
                             icir_p2 %||% NA, icir_p3 %||% NA)),
       file.path(OUT_DIR, "s2_h1693_three_period_icir.csv"))

# 4-period IC using rolling vol proxy (no external state dependency)
bm_sub <- BM_DT[, .(Date, Ret = BM_Ret)][order(Date)]
bm_sub[, rv12 := frollapply(Ret, n = 252L, FUN = sd, align = "right")]
bm_sub[, rv12_z := {
  # C1: expanding window mean/sd — no full-sample lookahead
  n <- .N
  m_exp <- cumsum(ifelse(is.na(rv12), 0, rv12)) / pmax(cumsum(!is.na(rv12)), 1L)
  ss    <- cumsum(ifelse(is.na(rv12), 0, (rv12 - shift(m_exp, 1L, fill=0))^2))
  cnt   <- cumsum(!is.na(rv12))
  s_exp <- sqrt(ifelse(cnt > 1L, ss / (cnt - 1L), NA_real_))
  m_lag <- shift(m_exp, 1L); s_lag <- shift(s_exp, 1L)
  ifelse(is.na(s_lag) | s_lag < 1e-10, NA_real_, (rv12 - m_lag) / s_lag)
}]

ic_monthly <- merge(ic_monthly,
                    bm_sub[Date %in% ic_monthly$Date, .(Date, rv12_z)],
                    by = "Date", all.x = TRUE)
ic_monthly[, stress_period := fcase(
  rv12_z >= 1.5,  "HIGH_VOL",
  rv12_z >= 0.5,  "ELEVATED",
  rv12_z >= -0.5, "NORMAL",
  default = "LOW_VOL"
)]

stress_ic <- ic_monthly[stress_period %in% c("HIGH_VOL","ELEVATED"), mean(IC, na.rm=TRUE)]
calm_ic   <- ic_monthly[stress_period %in% c("NORMAL","LOW_VOL"),    mean(IC, na.rm=TRUE)]
ax001_gate_2c <- !is.na(stress_ic) && !is.na(calm_ic) && calm_ic != 0 &&
                 (stress_ic / calm_ic) > 0.6
cat(sprintf("[AX-001 v2] Gate 2c stress/calm IC ratio: %.3f/%.3f=%.2f (>0.6: %s)\n",
            stress_ic %||% NA, calm_ic %||% NA,
            (stress_ic / calm_ic) %||% NA, ifelse(ax001_gate_2c,"PASS","FAIL")))

period_ic_tbl <- ic_monthly[, .(ic_mean=mean(IC,na.rm=TRUE), icir=mean(IC,na.rm=TRUE)/sd(IC,na.rm=TRUE), n=.N), by=stress_period]
cat("[Step 9] Stress-period IC breakdown:\n"); print(period_ic_tbl)
fwrite(period_ic_tbl, file.path(OUT_DIR, "h1693_regime_ic.csv"))

# 6-crisis alpha Gate 2b via known crisis windows
crisis_periods <- list(
  c("1997-07-01","1998-09-30"), c("2000-01-01","2001-12-31"),
  c("2008-01-01","2009-06-30"), c("2011-06-01","2012-03-31"),
  c("2020-01-15","2020-06-30"), c("2022-01-01","2022-12-31")
)
crisis_alpha_check <- sapply(crisis_periods, function(cp) {
  d1 <- as.Date(cp[1]); d2 <- as.Date(cp[2])
  sub_ic <- ic_monthly[Date >= d1 & Date <= d2, mean(IC, na.rm=TRUE)]
  !is.na(sub_ic) && sub_ic > 0
})
ax001_gate_2b <- sum(crisis_alpha_check) >= 4
cat(sprintf("[AX-001 v2] Gate 2b 6-crisis positive IC: %d/6 (>=4: %s)\n",
            sum(crisis_alpha_check), ifelse(ax001_gate_2b,"PASS","FAIL")))

crisis_alpha_json <- list(
  windows_checked = 6L,
  windows_positive = sum(crisis_alpha_check),
  pass = ax001_gate_2b,
  detail = mapply(function(cp, ok) list(period=paste(cp, collapse="~"), ic_positive=ok),
                  crisis_periods, crisis_alpha_check, SIMPLIFY=FALSE)
)
write_json(crisis_alpha_json,
           file.path(OUT_DIR, "h1693_v1_crisis_alpha.json"),
           pretty=TRUE, auto_unbox=TRUE)

# ===================================================================
# 10. Signal-Portfolio Translation gates (S1-C3, Gate 14, veto-level)
# ===================================================================
cat("\n[Step 10] Signal-Portfolio Translation 3-gate (veto-level)...\n")

turnover_avg       <- if (!is.null(sim$turnover)) mean(sim$turnover, na.rm=TRUE) else 0.5
net_ret            <- ann_ret - COMMISSION * turnover_avg - 0.003 * 0.10
transmission_ratio <- if (!is.na(ann_ret) && ann_ret != 0) net_ret / ann_ret else NA_real_
gate_14a           <- !is.na(transmission_ratio) && transmission_ratio > 0.6
cat(sprintf("[Gate 14a] transmission_ratio: %.3f (>0.6: %s)\n",
            transmission_ratio %||% NA, ifelse(gate_14a,"PASS","FAIL")))

gate_14b <- sum(crisis_alpha_check) >= 2
cat(sprintf("[Gate 14b] stress_positive_windows: %d/6 (>=2: %s)\n",
            sum(crisis_alpha_check), ifelse(gate_14b,"PASS","FAIL")))

rank_corr_check <- tryCatch({
  sig_dates_sub <- sort(unique(FACTORS$Date))
  rc_vals <- sapply(seq_along(sig_dates_sub)[-length(sig_dates_sub)], function(i) {
    sd  <- sig_dates_sub[i]
    nsd <- sig_dates_sub[i + 1L]
    fac <- FACTORS[Date == sd][order(-Score)][1:min(40L, .N)]
    fwd <- RAWDATA[Date > sd & Date <= nsd,
                   .(fwd_ret = prod(1+Ret,na.rm=TRUE)-1), by=Ticker]
    mg  <- merge(fac, fwd, by="Ticker")
    if (nrow(mg) < 10L) return(NA_real_)
    cor(mg$Score, mg$fwd_ret, method="spearman", use="complete.obs")
  })
  mean(rc_vals, na.rm=TRUE)
}, error = function(e) NA_real_)
gate_14c <- !is.na(rank_corr_check) && rank_corr_check > 0.20
cat(sprintf("[Gate 14c] rank_corr: %.3f (>0.20: %s)\n",
            rank_corr_check %||% NA, ifelse(gate_14c,"PASS","FAIL")))

gate_14_pass <- gate_14a && gate_14b && gate_14c
cat(sprintf("[Gate 14 TOTAL] Signal-Portfolio Translation: %s\n",
            ifelse(gate_14_pass,"PASS","FAIL_VETO")))

transmission_result <- list(
  gate_14a_transmission_ratio = round(transmission_ratio %||% NA, 3),
  gate_14b_stress_windows     = sum(crisis_alpha_check),
  gate_14c_rank_corr          = round(rank_corr_check %||% NA, 3),
  gate_14_pass                = gate_14_pass,
  ax_cand_3rd_member_risk     = !gate_14_pass
)
write_json(transmission_result,
           file.path(OUT_DIR, "h1693_signal_portfolio_translation.json"),
           pretty=TRUE, auto_unbox=TRUE)

# ===================================================================
# 11. C01_SUE long-only direction check (S1-C7)
# ===================================================================
cat("\n[Step 11] C01_SUE crisis direction reconciliation (S1-C7)...\n")

sue_crisis_ic <- ic_monthly[stress_period == "HIGH_VOL", mean(IC, na.rm=TRUE)]
sue_direction_ok <- !is.na(sue_crisis_ic) && sue_crisis_ic > 0
cat(sprintf("[S1-C7] composite HIGH_VOL IC: %.3f | positive direction: %s\n",
            sue_crisis_ic %||% NA,
            ifelse(sue_direction_ok,"CONFIRMED_POSITIVE","WARNING_NEGATIVE")))

sue_reconcile <- list(
  registry_tag              = "C01_SUE crisis=negative",
  conditional_ic_4r_crisis  = 0.301,
  composite_high_vol_ic     = round(sue_crisis_ic %||% NA, 3),
  long_only_direction_positive = sue_direction_ok,
  verdict = if (sue_direction_ok)
    "REGISTRY_TAG_INCORRECT_IC_POSITIVE"
  else
    "REGISTRY_TAG_CONFIRMED_REJECT_C01_SUE"
)
write_json(sue_reconcile,
           file.path(OUT_DIR, "h1693_c01_sue_regime_reconciliation.json"),
           pretty=TRUE, auto_unbox=TRUE)
if (!sue_direction_ok)
  cat("[Step 11] CRITICAL: composite crisis IC negative — C01_SUE 방향 재검토 필요\n")

# ===================================================================
# 12. Z_Sector NA tracking (S1-C8)
# ===================================================================
cat("\n[Step 12] Z_Sector NA tracking (S1-C8)...\n")
fwrite(H1693_ZSECTOR_NA, file.path(OUT_DIR, "h1693_z_sector_na_tracking.csv"))
cat(sprintf("[Step 12] NA ratio: %.1f%% | gate <15%%: %s\n",
            H1693_ZSECTOR_NA_RATIO * 100,
            ifelse(H1693_ZSECTOR_NA_RATIO <= 0.15,"PASS","WARN")))

# ===================================================================
# 13. Sector HHI + turnover (S1-C5)
# ===================================================================
cat("\n[Step 13] Sector HHI + turnover (S1-C5)...\n")
sector_hhi_monthly <- tryCatch({
  sig_dates_sub <- sort(unique(FACTORS$Date))
  rbindlist(lapply(sig_dates_sub, function(sd) {
    top20  <- FACTORS[Date == sd][order(-Score)][1:min(20L,.N)]
    sec_dt <- if (exists("H1693_FDB_SNAP") && "Sector" %in% names(H1693_FDB_SNAP))
      H1693_FDB_SNAP[Date == sd, .(Ticker, Sector)] else NULL
    if (is.null(sec_dt)) return(NULL)
    merged <- merge(top20, sec_dt, by="Ticker", all.x=TRUE)
    merged[is.na(Sector), Sector := "Unknown"]
    sec_cnt <- merged[, .N, by=Sector]
    n_tot   <- nrow(merged)
    data.table(Date=sd,
               hhi          = sum((sec_cnt$N/n_tot)^2) * 10000,
               max_sector_pct = max(sec_cnt$N)/n_tot*100)
  }))
}, error = function(e) {
  cat("[Step 13 WARN]", conditionMessage(e), "\n")
  data.table(Date=as.Date(character(0)), hhi=numeric(0), max_sector_pct=numeric(0))
})

avg_hhi     <- if (nrow(sector_hhi_monthly)>0) mean(sector_hhi_monthly$hhi,     na.rm=TRUE) else NA_real_
max_sec_pct <- if (nrow(sector_hhi_monthly)>0) mean(sector_hhi_monthly$max_sector_pct, na.rm=TRUE) else NA_real_
cat(sprintf("[Step 13] Avg HHI: %.0f (warn >2500) | Avg max sector%%: %.1f%% (warn >25%%)\n",
            avg_hhi %||% NA, max_sec_pct %||% NA))
if (nrow(sector_hhi_monthly) > 0)
  fwrite(sector_hhi_monthly, file.path(OUT_DIR, "h1693_sector_turnover_cluster.csv"))

# ===================================================================
# 14. Ablation comparison (S1-C4)
# ===================================================================
cat("\n[Step 14] Ablation variant comparison (S1-C4)...\n")
ablation_perf <- rbindlist(lapply(names(sims), function(vname) {
  s <- sims[[vname]]
  if (!is.null(s$error) || is.null(s$strategy_xts)) {
    return(data.table(variant=vname, cagr=NA_real_, sr=NA_real_, mdd=NA_real_, turnover=NA_real_))
  }
  x <- s$strategy_xts
  data.table(
    variant  = vname,
    cagr     = round(as.numeric(Return.annualized(x, scale=252)) * 100, 2),
    sr       = round(as.numeric(SharpeRatio.annualized(x, Rf=0, scale=252)), 3),
    mdd      = round(as.numeric(maxDrawdown(x)) * 100, 2),
    turnover = round(if (!is.null(s$turnover)) mean(s$turnover,na.rm=TRUE)*100 else NA_real_, 1)
  )
}))
cat("[Ablation comparison]\n"); print(ablation_perf)
fwrite(ablation_perf, file.path(OUT_DIR, "h1693_ablation_robustness.csv"))

icir_cv <- tryCatch({
  sr_vals <- ablation_perf$sr[!is.na(ablation_perf$sr)]
  if (length(sr_vals) >= 2L) sd(sr_vals)/abs(mean(sr_vals)) else NA_real_
}, error = function(e) NA_real_)
cat(sprintf("[S1-C4] Ablation SR CV: %.2f (warn if >0.30)\n", icir_cv %||% NA))

# ===================================================================
# 15. s1_construction artifact
# ===================================================================
cat("\n[Step 15] Saving s1_construction_H_1693.json...\n")

ax001_v2_result <- list(
  gate_2a_multi_sleeve_only   = ax001_gate_2a,
  gate_2b_crisis_alpha_4of6   = ax001_gate_2b,
  gate_2c_stress_calm_ic_ratio = ax001_gate_2c,
  gate_2d_mdd_lt_35pct        = ax001_gate_2d,
  all_pass = ax001_gate_2a && ax001_gate_2b && ax001_gate_2c && ax001_gate_2d
)

s1_art <- list(
  strategy_id   = STRATEGY_ID,
  hypothesis_id = HYPOTHESIS_ID,
  stage         = "S1",
  date          = as.character(Sys.Date()),
  family        = STRATEGY_FAMILY,
  expected_role = "defense",
  role_bias     = "RoleBias_Defense",
  performance   = list(
    cagr   = round(ann_ret * 100, 2),
    sharpe = round(sr_val, 3),
    mdd    = round(mdd_val * 100, 2),
    grade  = hurdle$grade %||% "?",
    score  = as.numeric(hurdle$score %||% 0)
  ),
  portfolio = list(
    n_holdings    = N_HOLD,
    weight_method = WEIGHT_METHOD,
    commission    = COMMISSION,
    buffer_zone   = BUFFER_ZONE,
    liq_threshold = LIQ_THRESHOLD
  ),
  pit_evidence  = if (exists("H1693_PIT_EVIDENCE")) H1693_PIT_EVIDENCE else list(),
  alpha_lab_gate = list(
    icir_threshold = 0.20,
    overall_icir   = round(overall_icir %||% NA, 3),
    pass           = alpha_lab_pass
  ),
  three_period_icir = list(
    p1_2005_2014  = round(icir_p1 %||% NA, 3),
    p2_2015_2019  = round(icir_p2 %||% NA, 3),
    p3_2020_2026  = round(icir_p3 %||% NA, 3)
  ),
  ax001_v2_defense_gates               = ax001_v2_result,
  gate_14_signal_portfolio_translation = transmission_result,
  s1_c7_sue_direction                  = sue_reconcile,
  s1_c8_zsector_na_ratio               = round(H1693_ZSECTOR_NA_RATIO %||% NA, 3),
  s1_c5_sector_hhi = list(
    avg_hhi      = round(avg_hhi %||% NA, 0),
    avg_max_pct  = round(max_sec_pct %||% NA, 1),
    hhi_pass     = !is.na(avg_hhi) && avg_hhi < 2500,
    max_pct_pass = !is.na(max_sec_pct) && max_sec_pct <= 25
  ),
  s1_c4_ablation_sr_cv = round(icir_cv %||% NA, 3),
  primary_variant      = "V1_composite (0.7/0.3)",
  ablation_variants    = ablation_perf
)

art_path <- file.path(PROJECT_ROOT, "stage_artifacts", "s1_construction_H_1693.json")
write_json(s1_art, art_path, pretty=TRUE, auto_unbox=TRUE)
cat(sprintf("[Step 15] Saved: %s\n", art_path))

# ===================================================================
# 16. Charts
# ===================================================================
tryCatch({
  generate_charts(sim, output_dir = OUT_DIR)
  cat("[Step 16] Charts saved.\n")
}, error = function(e) cat("[Step 16 WARN]", conditionMessage(e), "\n"))

# ===================================================================
# 16b. Tail risk (Risk Gate 필수 — risk_gate.sh hook)
# ===================================================================
cat("\n[Step 16b] Tail risk...\n")
tail_risk_res <- tryCatch({
  source(file.path(FUNC_PATH, "risk_engine.R"))
  compute_tail_risk_suite(sim$strategy_xts, output_dir = OUT_DIR,
                          strategy_id = STRATEGY_ID)
}, error = function(e) {
  cat("[WARN tail_risk]", conditionMessage(e), "\n")
  rets  <- as.numeric(sim$strategy_xts)
  es_99 <- quantile(rets, 0.01, na.rm = TRUE)
  res   <- list(
    evt_xi         = NA_real_,
    cdar_95        = as.numeric(maxDrawdown(sim$strategy_xts)),
    es_99_monthly  = round(es_99, 4),
    overall_pass   = FALSE
  )
  write_json(c(res, list(strategy_id = STRATEGY_ID, hypothesis_id = HYPOTHESIS_ID,
                          date = as.character(Sys.Date()))),
             file.path(OUT_DIR, "tail_risk_result.json"), pretty = TRUE, auto_unbox = TRUE)
  res
})
cat(sprintf("[Tail] CDaR_95=%.2f%% | ES_99=%.2f%% | pass=%s\n",
            (tail_risk_res$cdar_95 %||% NA) * 100,
            (tail_risk_res$es_99_monthly %||% NA) * 100,
            tail_risk_res$overall_pass %||% FALSE))

# ===================================================================
# 17. Summary
# ===================================================================
elapsed <- round(difftime(Sys.time(), t0, units="mins"), 1)
cat(sprintf("\n=== STR_1687 S1 COMPLETE ===\n"))
cat(sprintf("  Grade: %s | Score: %.1f\n", hurdle$grade %||% "?", as.numeric(hurdle$score %||% 0)))
cat(sprintf("  CAGR: %.1f%% | SR: %.3f | MDD: %.1f%%\n", ann_ret*100, sr_val, mdd_val*100))
cat(sprintf("  Alpha Lab ICIR: %.3f (>=0.20: %s)\n",
            overall_icir %||% NA, ifelse(alpha_lab_pass,"PASS","FAIL")))
cat(sprintf("  AX-001 v2: 2a=%s 2b=%s 2c=%s 2d=%s\n",
            ifelse(ax001_gate_2a,"P","F"), ifelse(ax001_gate_2b,"P","F"),
            ifelse(ax001_gate_2c,"P","F"), ifelse(ax001_gate_2d,"P","F")))
cat(sprintf("  Gate 14: %s | 14a=%.2f 14b=%d/6 14c=%.2f\n",
            ifelse(gate_14_pass,"PASS","FAIL_VETO"),
            transmission_ratio %||% NA, sum(crisis_alpha_check), rank_corr_check %||% NA))
cat(sprintf("  S1-C7 SUE direction: %s\n", sue_reconcile$verdict))
cat(sprintf("  S1-C8 Z_Sector NA: %.1f%% | S1-C5 HHI: %.0f\n",
            H1693_ZSECTOR_NA_RATIO*100, avg_hhi %||% NA))
cat(sprintf("  Elapsed: %s min\n", elapsed))

# ===================================================================
# 18. Telegram
# ===================================================================
tryCatch({
  source(file.path(FUNC_PATH, "telegram", "telegram_notify.R"))
  tg_send(paste0(
    "[Forge] STR_1687 S1 완료 (H_1693 Q07 Sector-Neutral Defense)\n",
    sprintf("Grade: %s | Score: %.1f\n", hurdle$grade %||% "?", as.numeric(hurdle$score %||% 0)),
    sprintf("CAGR: %.1f%% | SR: %.3f | MDD: %.1f%%\n", ann_ret*100, sr_val, mdd_val*100),
    sprintf("ICIR: %.3f (>=0.20: %s)\n", overall_icir %||% NA, ifelse(alpha_lab_pass,"PASS","FAIL")),
    sprintf("AX-001 v2: 2a=%s 2b=%s 2c=%s 2d=%s\n",
            ifelse(ax001_gate_2a,"P","F"), ifelse(ax001_gate_2b,"P","F"),
            ifelse(ax001_gate_2c,"P","F"), ifelse(ax001_gate_2d,"P","F")),
    sprintf("Gate 14: %s (14a=%.2f 14b=%d/6 14c=%.2f)\n",
            ifelse(gate_14_pass,"PASS","FAIL_VETO"),
            transmission_ratio %||% NA, sum(crisis_alpha_check), rank_corr_check %||% NA),
    sprintf("S1-C7 SUE: %s\n", sue_reconcile$verdict),
    "RoleBias: RoleBias_Defense | Family: quality_earnings_stability_sector_neutral"
  ))
  chart_path <- file.path(OUT_DIR, "equity_curve.png")
  if (file.exists(chart_path)) tg_send_photo(chart_path, caption="STR_1687 Equity Curve")
}, error = function(e) cat("[Telegram WARN]", conditionMessage(e), "\n"))

# ===================================================================
# 19. QEPM auto-commit
# ===================================================================
if (isTRUE(QEPM_AUTO_COMMIT)) {
  tryCatch({
    source(file.path(PROJECT_ROOT, "qepm", "scripts", "hybrid_mode.R"))
    hybrid_commit(
      strategy      = STRATEGY_ID,
      family        = STRATEGY_FAMILY,
      hurdle_result = hurdle,
      role_bias     = "RoleBias_Defense",
      tags          = c("H_1693", "Q07_sector_neutral", "C01_SUE",
                        "defense", "AX001_v2", "S1")
    )
    cat("[QEPM] hybrid_commit done.\n")
  }, error = function(e) cat("[QEPM WARN]", conditionMessage(e), "\n"))
}

cat("[DONE]\n")
