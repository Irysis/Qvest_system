cat("=== STR_1689: Quality Aggregate Defense v3 (H_1689 Q24-excluded) ===\n")
## 핵심아이디어: V1=0.33*Q01+0.33*Q04+0.34*Q25 | V2=0.25*Q01+0.25*Q04+0.25*Q07+0.25*Q25
## Q24 poison pill 제거 (L-163: -0.695*0.25=-0.174, 5× threshold violation)
## AX-001 v2: multi_sleeve_only=TRUE, crisis_alpha + bad/normal IC ratio + core MDD reduction
## Novy-Marx 2013 + Piotroski 2000 + Ohlson 1980 + Asness 2019 QMJ + L-121 Q07

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

STRATEGY_ID     <- "STR_1689"
HYPOTHESIS_ID   <- "H_1689_v3"
STRATEGY_FAMILY <- "quality_composite"
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
RAWDATA[, AvgTV20  := shift(frollmean(TradingValue, n = 20L, align = "right"), 1L), by = Ticker]
RAWDATA[, LiqPass  := !is.na(AvgTV20) & AvgTV20 >= LIQ_THRESHOLD]

cat(sprintf("[Step 2] %s ~ %s | %d tickers\n",
            min(RAWDATA$Date), max(RAWDATA$Date), uniqueN(RAWDATA$Ticker)))

# ===================================================================
# 3. Factor engine (2 variants)
# ===================================================================
cat("\n[Step 3] Factor engine (H_1689 v3, 2 variants)...\n")
source(file.path(STRAT_DIR, "factor_engine.R"))
stopifnot(is.data.table(FACTORS), all(c("Date","Ticker","Score") %in% names(FACTORS)))
cat(sprintf("[Step 3] V1(3-axis)=%d | V2(4-axis Q07)=%d\n", nrow(FACTORS), nrow(FACTORS_V2)))

# ===================================================================
# 4. PIT lookahead detection
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
# 5. 2-variant simulations (mclapply)
# ===================================================================
cat("\n[Step 5] 2-variant simulations...\n")

variants <- list(V1_3axis = FACTORS, V2_4axis_Q07 = FACTORS_V2)
sim_args <- list(
  RAWDATA = RAWDATA, BM_DT = BM_DT,
  n_holdings = N_HOLD, weight_method = WEIGHT_METHOD,
  commission = COMMISSION, buffer_zone = BUFFER_ZONE
)

# OOM recovery: sequential lapply (WSL global_oom, Session 69 Day 1)
sims <- lapply(names(variants), function(vname) {
  fac <- variants[[vname]]
  if (nrow(fac) < 100L) return(list(error = paste("empty:", vname)))
  cat(sprintf("[Step 5] Running variant: %s ...\n", vname))
  tryCatch(
    do.call(run_monthly_simulation, c(list(FACTORS = fac), sim_args)),
    error = function(e) list(error = conditionMessage(e))
  )
})
names(sims) <- names(variants)

sim <- sims[["V1_3axis"]]
if (!is.null(sim$error)) {
  cat(sprintf("[FATAL V1] %s\n", sim$error)); stop("V1 simulation failed")
}
cat(sprintf("[Step 5] V1 done: %d trading days\n", length(sim$strategy_xts)))

# ===================================================================
# 6. Analysis (V1 primary) — timeout guard: 90s limit
# ===================================================================
cat("\n[Step 6] Analysis (V1 primary)...\n")
tryCatch({
  source(file.path(FUNC_PATH, "strategy_analyzer.R"))
  setTimeLimit(elapsed = 90, transient = TRUE)
  run_analysis(sim, FACTORS, RAWDATA, BM_DT, OUT_DIR, strategy_name = STRATEGY_ID)
  setTimeLimit(elapsed = Inf)
}, error = function(e) {
  setTimeLimit(elapsed = Inf)
  cat("[Step 6 WARN]", conditionMessage(e), "\n")
  tryCatch({
    perf <- summarise_perf(sim$strategy_xts, STRATEGY_ID)
    fwrite(as.data.table(t(unlist(perf))), file.path(OUT_DIR, "performance.csv"))
  }, error = function(e2) NULL)
})

# ===================================================================
# 7. Hurdle gate
# ===================================================================
cat("\n[Step 7] Hurdle gate...\n")
source(file.path(FUNC_PATH, "hurdle_gate.R"))
hurdle <- tryCatch(
  run_hurdle_gate(sim, strategy_name = STRATEGY_ID, output_dir = OUT_DIR),
  error = function(e) { cat("[WARN hurdle]", conditionMessage(e), "\n"); list(grade="ERR", score=0) }
)
cat(sprintf("[Step 7] Grade: %s | Score: %.1f\n",
            hurdle$grade %||% "?", as.numeric(hurdle$score %||% 0)))

# ===================================================================
# 8. AX-001 v2 defense evaluation
# ===================================================================
cat("\n[Step 8] AX-001 v2 defense gates...\n")
perf_xts <- sim$strategy_xts
ann_ret  <- as.numeric(Return.annualized(perf_xts, scale = 252))
sr_val   <- as.numeric(SharpeRatio.annualized(perf_xts, Rf = 0, scale = 252))
mdd_val  <- as.numeric(maxDrawdown(perf_xts))

ax001_gate_2a <- TRUE   # multi_sleeve_only hardcoded for defense
ax001_gate_2d <- mdd_val < 0.35
cat(sprintf("[AX-001 v2] Gate 2a multi_sleeve_only: TRUE\n"))
cat(sprintf("[AX-001 v2] Gate 2d MDD=%.1f%% < 35%%: %s\n",
            mdd_val * 100, ifelse(ax001_gate_2d, "PASS", "WARN")))

# ===================================================================
# 9. Rolling ICIR + stress-period IC (GATE 4 bad/normal ratio)
# ===================================================================
cat("\n[Step 9] Rolling ICIR + 4-period IC + bad/normal ratio (GATE 4)...\n")

compute_icir_series <- function(factors_dt, rawdata_dt) {
  sig_dates <- sort(unique(factors_dt$Date))
  ic_list <- lapply(seq_along(sig_dates), function(i) {
    if (i == length(sig_dates)) return(NULL)
    sd  <- sig_dates[i]
    nsd <- sig_dates[i + 1L]
    fwd <- rawdata_dt[Date > sd & Date <= nsd,
                      .(fwd_ret = prod(1 + Ret, na.rm = TRUE) - 1), by = Ticker]
    sc  <- factors_dt[Date == sd, .(Ticker, Score)]
    mg  <- merge(sc, fwd, by = "Ticker")
    if (nrow(mg) < 10L) return(NULL)
    data.table(Date = sd,
               IC   = cor(mg$Score, mg$fwd_ret, method = "spearman", use = "complete.obs"))
  })
  rbindlist(Filter(Negate(is.null), ic_list))[!is.na(IC)]
}

ic_monthly <- compute_icir_series(FACTORS, RAWDATA)
overall_icir   <- if (nrow(ic_monthly) >= 12L)
  mean(ic_monthly$IC, na.rm = TRUE) / sd(ic_monthly$IC, na.rm = TRUE) else NA_real_
alpha_lab_pass <- !is.na(overall_icir) && overall_icir >= 0.20

period_icir <- function(d) if (nrow(d) < 6L) NA_real_ else
  mean(d$IC, na.rm = TRUE) / sd(d$IC, na.rm = TRUE)
icir_p1 <- period_icir(ic_monthly[Date <  as.Date("2015-01-01")])
icir_p2 <- period_icir(ic_monthly[Date >= as.Date("2015-01-01") & Date < as.Date("2020-01-01")])
icir_p3 <- period_icir(ic_monthly[Date >= as.Date("2020-01-01")])

cat(sprintf("[Alpha Lab] ICIR=%.3f (>=0.20: %s) | 2005-14=%.3f | 2015-19=%.3f | 2020-26=%.3f\n",
            overall_icir %||% NA, ifelse(alpha_lab_pass, "PASS", "FAIL"),
            icir_p1 %||% NA, icir_p2 %||% NA, icir_p3 %||% NA))

fwrite(data.table(period = c("overall","2005-2014","2015-2019","2020-2026"),
                  icir   = c(overall_icir %||% NA, icir_p1 %||% NA,
                             icir_p2 %||% NA, icir_p3 %||% NA)),
       file.path(OUT_DIR, "h1689_v3_three_period_icir.csv"))

# Stress-period IC via BM rolling vol (GATE 4)
bm_sub <- BM_DT[, .(Date, Ret = BM_Ret)][order(Date)]
bm_sub[, rv12 := frollapply(Ret, n = 252L, FUN = sd, align = "right")]
bm_sub[, rv12_z := {
  m <- mean(rv12, na.rm = TRUE); s <- sd(rv12, na.rm = TRUE)
  if (is.na(s) || s < 1e-10) rep(NA_real_, .N) else (rv12 - m) / s
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

stress_ic <- ic_monthly[stress_period %in% c("HIGH_VOL","ELEVATED"), mean(IC, na.rm = TRUE)]
calm_ic   <- ic_monthly[stress_period %in% c("NORMAL","LOW_VOL"),    mean(IC, na.rm = TRUE)]
# GATE 4: bad/normal IC ratio > 0.6
ax001_gate_2c <- !is.na(stress_ic) && !is.na(calm_ic) && calm_ic != 0 &&
                 (stress_ic / calm_ic) > 0.6
cat(sprintf("[GATE 4] bad/normal IC ratio=%.3f/%.3f=%.2f (>0.6: %s)\n",
            stress_ic %||% NA, calm_ic %||% NA,
            (stress_ic / calm_ic) %||% NA, ifelse(ax001_gate_2c, "PASS", "FAIL")))

period_ic_tbl <- ic_monthly[, .(ic_mean = mean(IC, na.rm = TRUE),
                                 icir    = mean(IC, na.rm = TRUE) / sd(IC, na.rm = TRUE),
                                 n       = .N), by = stress_period]
cat("[Step 9] Stress IC breakdown:\n"); print(period_ic_tbl)
fwrite(period_ic_tbl, file.path(OUT_DIR, "h1689_v3_variant_1_regime_ic.csv"))

# ===================================================================
# 10. GATE 5: 6-crisis alpha
# ===================================================================
cat("\n[Step 10] GATE 5: 6-crisis alpha (AX-001 v2 Gate 2b)...\n")

crisis_periods <- list(
  c("1997-07-01","1998-09-30"), c("2000-01-01","2001-12-31"),
  c("2008-01-01","2009-06-30"), c("2011-06-01","2012-03-31"),
  c("2020-01-15","2020-06-30"), c("2022-01-01","2022-12-31")
)
crisis_alpha_check <- sapply(crisis_periods, function(cp) {
  d1 <- as.Date(cp[1]); d2 <- as.Date(cp[2])
  sub_ic <- ic_monthly[Date >= d1 & Date <= d2, mean(IC, na.rm = TRUE)]
  !is.na(sub_ic) && sub_ic > 0
})
ax001_gate_2b <- sum(crisis_alpha_check) >= 4
cat(sprintf("[GATE 5] 6-crisis positive IC: %d/6 (>=4: %s)\n",
            sum(crisis_alpha_check), ifelse(ax001_gate_2b, "PASS", "FAIL")))

crisis_alpha_json <- list(
  windows_checked  = 6L,
  windows_positive = sum(crisis_alpha_check),
  pass             = ax001_gate_2b,
  detail = mapply(function(cp, ok) list(period = paste(cp, collapse = "~"), ic_positive = ok),
                  crisis_periods, crisis_alpha_check, SIMPLIFY = FALSE)
)
write_json(crisis_alpha_json,
           file.path(OUT_DIR, "h1689_v3_variant_1_crisis_alpha.json"),
           pretty = TRUE, auto_unbox = TRUE)

# ===================================================================
# 11. GATE 6: V2 ICIR + stress_icir comparison
# ===================================================================
cat("\n[Step 11] GATE 6: V1 vs V2 stress_icir comparison...\n")

sim_v2 <- sims[["V2_4axis_Q07"]]
ic_v2  <- if (!is.null(sim_v2$error)) NULL else
  compute_icir_series(FACTORS_V2, RAWDATA)

stress_icir_v1 <- if (nrow(ic_monthly) >= 6L) {
  sub <- ic_monthly[stress_period %in% c("HIGH_VOL","ELEVATED")]
  if (nrow(sub) >= 3L) mean(sub$IC) / sd(sub$IC) else NA_real_
} else NA_real_

stress_icir_v2 <- NA_real_
if (!is.null(ic_v2) && nrow(ic_v2) > 0L) {
  ic_v2 <- merge(ic_v2, bm_sub[Date %in% ic_v2$Date, .(Date, rv12_z)],
                 by = "Date", all.x = TRUE)
  ic_v2[, stress_period := fcase(
    rv12_z >= 1.5, "HIGH_VOL", rv12_z >= 0.5, "ELEVATED",
    rv12_z >= -0.5, "NORMAL", default = "LOW_VOL"
  )]
  sub2 <- ic_v2[stress_period %in% c("HIGH_VOL","ELEVATED")]
  if (nrow(sub2) >= 3L) stress_icir_v2 <- mean(sub2$IC) / sd(sub2$IC)
}

cat(sprintf("[GATE 6] stress_icir: V1=%.3f | V2=%.3f\n",
            stress_icir_v1 %||% NA, stress_icir_v2 %||% NA))

# Ablation comparison table (V1 + V2)
ablation_perf <- rbindlist(lapply(names(sims), function(vname) {
  s <- sims[[vname]]
  if (!is.null(s$error) || is.null(s$strategy_xts))
    return(data.table(variant = vname, cagr = NA_real_, sr = NA_real_,
                      mdd = NA_real_, turnover = NA_real_))
  x <- s$strategy_xts
  data.table(
    variant  = vname,
    cagr     = round(as.numeric(Return.annualized(x, scale = 252)) * 100, 2),
    sr       = round(as.numeric(SharpeRatio.annualized(x, Rf = 0, scale = 252)), 3),
    mdd      = round(as.numeric(maxDrawdown(x)) * 100, 2),
    turnover = round(if (!is.null(s$turnover)) mean(s$turnover, na.rm = TRUE) * 100 else NA_real_, 1)
  )
}))
cat("[Ablation comparison]\n"); print(ablation_perf)
fwrite(ablation_perf, file.path(OUT_DIR, "h1689_v3_variant_comparison.csv"))

# ===================================================================
# 12. s1_construction artifact
# ===================================================================
cat("\n[Step 12] Saving s1_construction_H_1689_v3.json...\n")

ax001_v2_result <- list(
  gate_2a_multi_sleeve_only    = ax001_gate_2a,
  gate_2b_crisis_alpha_4of6    = ax001_gate_2b,
  gate_2c_bad_normal_ic_ratio  = ax001_gate_2c,
  gate_2d_mdd_lt_35pct         = ax001_gate_2d,
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
  pit_evidence  = H1689V3_PIT_EVIDENCE,
  alpha_lab_gate = list(
    icir_threshold = 0.20,
    overall_icir   = round(overall_icir %||% NA, 3),
    pass           = alpha_lab_pass
  ),
  three_period_icir = list(
    p1_2005_2014 = round(icir_p1 %||% NA, 3),
    p2_2015_2019 = round(icir_p2 %||% NA, 3),
    p3_2020_2026 = round(icir_p3 %||% NA, 3)
  ),
  ax001_v2_defense_gates = ax001_v2_result,
  gate_4_bad_normal_ic   = list(
    stress_ic = round(stress_ic %||% NA, 3),
    calm_ic   = round(calm_ic %||% NA, 3),
    ratio     = round((stress_ic / calm_ic) %||% NA, 3),
    pass      = ax001_gate_2c
  ),
  gate_5_crisis_alpha = crisis_alpha_json,
  gate_6_stress_icir  = list(
    v1_stress_icir = round(stress_icir_v1 %||% NA, 3),
    v2_stress_icir = round(stress_icir_v2 %||% NA, 3)
  ),
  ablation_variants = ablation_perf
)

art_path <- file.path(PROJECT_ROOT, "stage_artifacts", "s1_construction_H_1689_v3.json")
write_json(s1_art, art_path, pretty = TRUE, auto_unbox = TRUE)
cat(sprintf("[Step 12] Saved: %s\n", art_path))

# ===================================================================
# 13. Charts
# ===================================================================
tryCatch({
  generate_charts(sim, output_dir = OUT_DIR)
  cat("[Step 13] Charts saved.\n")
}, error = function(e) cat("[Step 13 WARN]", conditionMessage(e), "\n"))

# ===================================================================
# 13b. daily_returns.csv (Scout S3 TDC 측정용)
# ===================================================================
tryCatch({
  dr <- data.table(Date = index(sim$strategy_xts),
                   ret  = as.numeric(sim$strategy_xts))
  fwrite(dr, file.path(OUT_DIR, "daily_returns.csv"))
  cat("[Step 13b] daily_returns.csv saved.\n")
}, error = function(e) cat("[Step 13b WARN]", conditionMessage(e), "\n"))

# ===================================================================
# 14. Tail risk (risk_gate.sh 필수)
# ===================================================================
cat("\n[Step 14] Tail risk...\n")
tail_risk_res <- tryCatch({
  source(file.path(FUNC_PATH, "risk_engine.R"))
  compute_tail_risk_suite(sim$strategy_xts, output_dir = OUT_DIR,
                          strategy_id = STRATEGY_ID)
}, error = function(e) {
  cat("[WARN tail_risk]", conditionMessage(e), "\n")
  rets  <- as.numeric(sim$strategy_xts)
  es_99 <- quantile(rets, 0.01, na.rm = TRUE)
  res   <- list(
    evt_xi        = NA_real_,
    cdar_95       = as.numeric(maxDrawdown(sim$strategy_xts)),
    es_99_monthly = round(es_99, 4),
    overall_pass  = FALSE
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
# 15. Summary
# ===================================================================
elapsed <- round(difftime(Sys.time(), t0, units = "mins"), 1)
cat(sprintf("\n=== STR_1689 S1 COMPLETE ===\n"))
cat(sprintf("  Grade: %s | Score: %.1f\n", hurdle$grade %||% "?", as.numeric(hurdle$score %||% 0)))
cat(sprintf("  CAGR: %.1f%% | SR: %.3f | MDD: %.1f%%\n", ann_ret*100, sr_val, mdd_val*100))
cat(sprintf("  Alpha Lab ICIR: %.3f (>=0.20: %s)\n",
            overall_icir %||% NA, ifelse(alpha_lab_pass, "PASS", "FAIL")))
cat(sprintf("  AX-001 v2: 2a=%s 2b=%s 2c=%s 2d=%s\n",
            ifelse(ax001_gate_2a,"P","F"), ifelse(ax001_gate_2b,"P","F"),
            ifelse(ax001_gate_2c,"P","F"), ifelse(ax001_gate_2d,"P","F")))
cat(sprintf("  GATE 6: V1 stress_icir=%.3f | V2=%.3f\n",
            stress_icir_v1 %||% NA, stress_icir_v2 %||% NA))
cat(sprintf("  Elapsed: %s min\n", elapsed))

# ===================================================================
# 16. Telegram
# ===================================================================
tryCatch({
  source(file.path(FUNC_PATH, "telegram", "telegram_notify.R"))
  tg_send(paste0(
    "[Forge] STR_1689 S1 완료 (H_1689 v3 Quality Aggregate Defense Q24-excluded)\n",
    sprintf("Grade: %s | Score: %.1f\n", hurdle$grade %||% "?", as.numeric(hurdle$score %||% 0)),
    sprintf("CAGR: %.1f%% | SR: %.3f | MDD: %.1f%%\n", ann_ret*100, sr_val, mdd_val*100),
    sprintf("ICIR: %.3f (>=0.20: %s)\n", overall_icir %||% NA, ifelse(alpha_lab_pass,"PASS","FAIL")),
    sprintf("AX-001 v2: 2a=%s 2b=%s 2c=%s 2d=%s\n",
            ifelse(ax001_gate_2a,"P","F"), ifelse(ax001_gate_2b,"P","F"),
            ifelse(ax001_gate_2c,"P","F"), ifelse(ax001_gate_2d,"P","F")),
    sprintf("GATE 6: V1 stress_icir=%.3f | V2=%.3f\n",
            stress_icir_v1 %||% NA, stress_icir_v2 %||% NA),
    "RoleBias: RoleBias_Defense | Family: quality_composite"
  ))
  chart_path <- file.path(OUT_DIR, "equity_curve.png")
  if (file.exists(chart_path)) tg_send_photo(chart_path, caption = "STR_1689 Equity Curve")
}, error = function(e) cat("[Telegram WARN]", conditionMessage(e), "\n"))

# ===================================================================
# 17. QEPM auto-commit
# ===================================================================
if (isTRUE(QEPM_AUTO_COMMIT)) {
  tryCatch({
    source(file.path(PROJECT_ROOT, "qepm", "scripts", "hybrid_mode.R"))
    hybrid_commit(
      strategy      = STRATEGY_ID,
      family        = STRATEGY_FAMILY,
      hurdle_result = hurdle,
      role_bias     = "RoleBias_Defense",
      tags          = c("H_1689_v3", "Q24_excluded", "quality_composite",
                        "defense", "AX001_v2", "S1", "L163_poison_pill")
    )
    cat("[QEPM] hybrid_commit done.\n")
  }, error = function(e) cat("[QEPM WARN]", conditionMessage(e), "\n"))
}

cat("[DONE]\n")
