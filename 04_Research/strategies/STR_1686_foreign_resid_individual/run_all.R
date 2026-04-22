cat("=== STR_1686: Foreign Flow Residualized on Individual (H_1685 v2 Diversifier) ===\n")
## 핵심아이디어: INV13 — z_F residualized on z_I via expanding OLS (burn-in 60m)
## Choe-Kho-Stulz 2005 RFS + 고영훈·안일찬 2018. 3 lookback variants: 21d/63d/126d.
## S1 pure signal: PIT C1(expand beta 60m) C2(t+1) C11(T+1 lag) C13(Z_Aligned) C15(load_month_factors)

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

STRATEGY_ID     <- "STR_1686"
STRATEGY_FAMILY <- "investor_flow"
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
# C10: shift(frollmean, 1L) — today volume excluded from liquidity filter
RAWDATA[, AvgTV20 := shift(frollmean(TradingValue, n = 20L, align = "right"), 1L), by = Ticker]
RAWDATA[, LiqPass := !is.na(AvgTV20) & AvgTV20 >= LIQ_THRESHOLD]

cat(sprintf("[Step 2] %s ~ %s | %d tickers\n",
            min(RAWDATA$Date), max(RAWDATA$Date), uniqueN(RAWDATA$Ticker)))

# ===================================================================
# 3. Factor engine
# ===================================================================
cat("\n[Step 3] Factor engine (INV13 3 variants)...\n")
source(file.path(STRAT_DIR, "factor_engine.R"))
stopifnot(is.data.table(FACTORS), all(c("Date","Ticker","Score") %in% names(FACTORS)))
cat(sprintf("[Step 3] V1(21d): %d rows | V2(63d): %d | V3(126d): %d\n",
            nrow(FACTORS), nrow(FACTORS_V2), nrow(FACTORS_V3)))

# ===================================================================
# 4. Lookahead detection
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
# 5. 3-variant simulations (sequential — OOM recovery, Session 69 Day 1)
# ===================================================================
cat("\n[Step 5] 3-variant simulations (sequential)...\n")

variants <- list(
  V1_21d  = FACTORS,
  V2_63d  = FACTORS_V2,
  V3_126d = FACTORS_V3
)

sim_args <- list(
  RAWDATA = RAWDATA, BM_DT = BM_DT,
  n_holdings = N_HOLD, weight_method = WEIGHT_METHOD,
  commission = COMMISSION, buffer_zone = BUFFER_ZONE
)

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

sim <- sims[["V1_21d"]]
if (!is.null(sim$error)) {
  cat(sprintf("[FATAL V1] %s\n", sim$error)); stop("V1 simulation failed")
}
cat(sprintf("[Step 5] V1 done: %d trading days\n", length(sim$strategy_xts)))

# ===================================================================
# 6. Analysis — skipped (strategy_analyzer IC loop too slow on WSL, Session 69 Day 1)
# ===================================================================
cat("\n[Step 6] Analysis skipped (WSL perf). Saving basic performance metrics...\n")
tryCatch({
  x <- sim$strategy_xts
  perf_basic <- data.table(
    strategy  = STRATEGY_ID,
    cagr      = round(as.numeric(Return.annualized(x, scale=252)) * 100, 2),
    sharpe    = round(as.numeric(SharpeRatio.annualized(x, Rf=0, scale=252)), 3),
    mdd       = round(as.numeric(maxDrawdown(x)) * 100, 2),
    ann_vol   = round(as.numeric(StdDev.annualized(x, scale=252)) * 100, 2)
  )
  fwrite(perf_basic, file.path(OUT_DIR, "performance.csv"))
  cat(sprintf("[Step 6] CAGR=%.1f%% SR=%.3f MDD=%.1f%%\n",
              perf_basic$cagr, perf_basic$sharpe, perf_basic$mdd))
}, error = function(e) cat("[Step 6 WARN]", conditionMessage(e), "\n"))

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
# 8. CAPM beta (diversifier: |beta| < 0.30 target)
# ===================================================================
cat("\n[Step 8] CAPM beta (diversifier, |beta|<0.30 target)...\n")
capm_beta <- tryCatch({
  str_xts <- sim$strategy_xts
  bm_sub  <- BM_DT[Date %in% index(str_xts)]
  bm_xts  <- xts(bm_sub$Ret, order.by = bm_sub$Date)
  mg      <- merge(str_xts, bm_xts, join = "inner")
  colnames(mg) <- c("strat", "bench")
  coef(lm(strat ~ bench, data = as.data.frame(mg)))["bench"]
}, error = function(e) { cat("[WARN CAPM]", conditionMessage(e), "\n"); NA_real_ })

cat(sprintf("[CAPM beta] beta=%.4f | |beta|<0.30: %s\n",
            capm_beta %||% NA,
            ifelse(!is.na(capm_beta) && abs(capm_beta) < 0.30, "PASS", "WARN")))

# ===================================================================
# 9. Rolling ICIR + 3-period breakdown
# ===================================================================
cat("\n[Step 9] Rolling ICIR + 3-period breakdown...\n")
setTimeLimit(elapsed = 120, transient = TRUE)
icir_result <- tryCatch({
  sig_dates <- sort(unique(FACTORS$Date))
  ic_monthly <- rbindlist(lapply(seq_along(sig_dates), function(i) {
    sd <- sig_dates[i]
    if (i == length(sig_dates)) return(NULL)
    next_sd <- sig_dates[i + 1L]
    fwd <- RAWDATA[Date > sd & Date <= next_sd,
                   .(fwd_ret = prod(1 + Ret, na.rm=TRUE) - 1), by = Ticker]
    sc  <- FACTORS[Date == sd, .(Ticker, Score)]
    mg  <- merge(sc, fwd, by = "Ticker")
    if (nrow(mg) < 10L) return(NULL)
    data.table(Date = sd,
               IC   = cor(mg$Score, mg$fwd_ret, method="spearman", use="complete.obs"))
  }))
  ic_monthly <- ic_monthly[!is.na(IC)]
  if (nrow(ic_monthly) < 12L) return(list(overall_icir=NA, ic_monthly=ic_monthly))
  overall_icir <- mean(ic_monthly$IC, na.rm=TRUE) / sd(ic_monthly$IC, na.rm=TRUE)

  # 3-period breakdown (S6 condition C6)
  p1 <- ic_monthly[Date <  as.Date("2015-01-01")]
  p2 <- ic_monthly[Date >= as.Date("2015-01-01") & Date < as.Date("2020-01-01")]
  p3 <- ic_monthly[Date >= as.Date("2020-01-01")]
  icir_p <- function(d) if (nrow(d) < 6) NA_real_ else
    mean(d$IC, na.rm=TRUE) / sd(d$IC, na.rm=TRUE)

  list(
    overall_icir = overall_icir,
    ic_monthly   = ic_monthly,
    icir_2005_2014 = icir_p(p1),
    icir_2015_2019 = icir_p(p2),
    icir_2020_2026 = icir_p(p3)
  )
}, error = function(e) {
  cat("[WARN ICIR]", conditionMessage(e), "\n")
  list(overall_icir = NA, ic_monthly = data.table())
})
setTimeLimit(elapsed = Inf)

alpha_lab_pass <- !is.na(icir_result$overall_icir) && icir_result$overall_icir >= 0.20
cat(sprintf("[Alpha Lab] ICIR=%.3f | 2005-14=%.3f | 2015-19=%.3f | 2020-26=%.3f | >=0.20: %s\n",
            icir_result$overall_icir %||% NA,
            icir_result$icir_2005_2014 %||% NA,
            icir_result$icir_2015_2019 %||% NA,
            icir_result$icir_2020_2026 %||% NA,
            ifelse(alpha_lab_pass, "PASS", "FAIL")))

# Save 3-period ICIR for Scout S2 (condition C6)
fwrite(data.table(
  period   = c("2005-2014","2015-2019","2020-2026","overall"),
  icir     = c(icir_result$icir_2005_2014 %||% NA,
               icir_result$icir_2015_2019 %||% NA,
               icir_result$icir_2020_2026 %||% NA,
               icir_result$overall_icir   %||% NA)
), file.path(OUT_DIR, "s2_h1685v2_three_period_icir.csv"))

# ===================================================================
# 10. Variant comparison (turnover + ICIR, condition C4)
# ===================================================================
cat("\n[Step 10] Variant comparison (21d/63d/126d)...\n")
variant_perf <- rbindlist(lapply(names(sims), function(vname) {
  s <- sims[[vname]]
  if (!is.null(s$error) || is.null(s$strategy_xts)) {
    return(data.table(variant=vname, cagr=NA, sr=NA, mdd=NA, turnover=NA))
  }
  xts_ <- s$strategy_xts
  data.table(
    variant  = vname,
    cagr     = round(as.numeric(Return.annualized(xts_, scale=252)) * 100, 2),
    sr       = round(as.numeric(SharpeRatio.annualized(xts_, Rf=0, scale=252)), 3),
    mdd      = round(as.numeric(maxDrawdown(xts_)) * 100, 2),
    turnover = round(if (!is.null(s$turnover)) mean(s$turnover, na.rm=TRUE) * 100 else NA, 1)
  )
}))
cat("[Variant comparison]\n"); print(variant_perf)
fwrite(variant_perf, file.path(OUT_DIR, "variant_comparison.csv"))

# ===================================================================
# 11. s1_construction_H_1685_v2 artifact
# ===================================================================
cat("\n[Step 11] Saving s1_construction_H_1685_v2.json...\n")
perf_xts <- sim$strategy_xts
ann_ret  <- as.numeric(Return.annualized(perf_xts, scale = 252))
sr       <- as.numeric(SharpeRatio.annualized(perf_xts, Rf = 0, scale = 252))
mdd      <- as.numeric(maxDrawdown(perf_xts))

s1_art <- list(
  strategy_id   = STRATEGY_ID,
  hypothesis_id = "H_1685_v2",
  stage         = "S1",
  date          = as.character(Sys.Date()),
  family        = STRATEGY_FAMILY,
  expected_role = "diversifier",
  role_bias     = "RoleBias_Diversifier",
  performance   = list(
    cagr   = round(ann_ret * 100, 2),
    sharpe = round(sr, 3),
    mdd    = round(mdd * 100, 2),
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
  pit_evidence   = if (exists("H1685V2_PIT_EVIDENCE")) H1685V2_PIT_EVIDENCE else list(),
  capm_beta      = round(capm_beta %||% NA, 4),
  capm_beta_gate = list(threshold=0.30, pass=!is.na(capm_beta)&&abs(capm_beta)<0.30),
  alpha_lab_gate = list(
    icir_threshold = 0.20,
    overall_icir   = round(icir_result$overall_icir %||% NA, 3),
    pass           = alpha_lab_pass
  ),
  three_period_icir = list(
    p1_2005_2014 = round(icir_result$icir_2005_2014 %||% NA, 3),
    p2_2015_2019 = round(icir_result$icir_2015_2019 %||% NA, 3),
    p3_2020_2026 = round(icir_result$icir_2020_2026 %||% NA, 3),
    post2020_pass = !is.na(icir_result$icir_2020_2026) && icir_result$icir_2020_2026 >= 0.15
  ),
  variant_comparison = variant_perf,
  primary_variant = "V1_21d (baseline)"
)

art_path <- file.path(PROJECT_ROOT, "stage_artifacts", "s1_construction_H_1685_v2.json")
write_json(s1_art, art_path, pretty = TRUE, auto_unbox = TRUE)
cat(sprintf("[Step 11] Saved: %s\n", art_path))

# ===================================================================
# 12. Charts
# ===================================================================
tryCatch({
  generate_charts(sim, output_dir = OUT_DIR)
  cat("[Step 12] Charts saved.\n")
}, error = function(e) cat("[Step 12 WARN]", conditionMessage(e), "\n"))

# ===================================================================
# 13. Summary
# ===================================================================
elapsed <- round(difftime(Sys.time(), t0, units = "mins"), 1)
cat(sprintf("\n=== STR_1686 S1 COMPLETE ===\n"))
cat(sprintf("  Grade: %s | Score: %.1f\n", hurdle$grade %||% "?", as.numeric(hurdle$score %||% 0)))
cat(sprintf("  CAGR: %.1f%% | SR: %.3f | MDD: %.1f%%\n", ann_ret*100, sr, mdd*100))
cat(sprintf("  CAPM beta: %.4f | |beta|<0.30: %s\n",
            capm_beta %||% NA,
            ifelse(!is.na(capm_beta) && abs(capm_beta) < 0.30, "PASS", "WARN")))
cat(sprintf("  Alpha Lab ICIR: %.3f (>=0.20: %s)\n",
            icir_result$overall_icir %||% NA, ifelse(alpha_lab_pass, "PASS", "FAIL")))
cat(sprintf("  Elapsed: %s min\n", elapsed))

# ===================================================================
# 14. Telegram
# ===================================================================
tryCatch({
  source(file.path(FUNC_PATH, "telegram", "telegram_notify.R"))
  msg <- paste0(
    "[Forge] STR_1686 S1 완료 (H_1685 v2 Foreign Resid Individual Diversifier)\n",
    sprintf("Grade: %s | Score: %.1f\n", hurdle$grade %||% "?", as.numeric(hurdle$score %||% 0)),
    sprintf("CAGR: %.1f%% | SR: %.3f | MDD: %.1f%%\n", ann_ret*100, sr, mdd*100),
    sprintf("CAPM beta: %.4f | |beta|<0.30: %s\n",
            capm_beta %||% NA,
            ifelse(!is.na(capm_beta)&&abs(capm_beta)<0.30,"PASS","WARN")),
    sprintf("ICIR: %.3f (>=0.20: %s) | post-2020: %.3f (>=0.15: %s)\n",
            icir_result$overall_icir %||% NA, ifelse(alpha_lab_pass,"PASS","FAIL"),
            icir_result$icir_2020_2026 %||% NA,
            ifelse(!is.na(icir_result$icir_2020_2026)&&icir_result$icir_2020_2026>=0.15,"PASS","FAIL")),
    "RoleBias: RoleBias_Diversifier | Family: investor_flow"
  )
  tg_send(msg)
  chart_path <- file.path(OUT_DIR, "equity_curve.png")
  if (file.exists(chart_path)) tg_send_photo(chart_path, caption = "STR_1686 Equity Curve")
}, error = function(e) cat("[Telegram WARN]", conditionMessage(e), "\n"))

# ===================================================================
# 15. QEPM auto-commit
# ===================================================================
if (isTRUE(QEPM_AUTO_COMMIT)) {
  tryCatch({
    source(file.path(PROJECT_ROOT, "qepm", "scripts", "hybrid_mode.R"))
    hybrid_commit(
      strategy      = STRATEGY_ID,
      family        = STRATEGY_FAMILY,
      hurdle_result = hurdle,
      role_bias     = "RoleBias_Diversifier",
      tags          = c("H_1685_v2", "investor_flow", "foreign_resid_individual",
                        "INV13", "diversifier", "S1")
    )
    cat("[QEPM] hybrid_commit done.\n")
  }, error = function(e) cat("[QEPM WARN]", conditionMessage(e), "\n"))
}

cat("[DONE]\n")
