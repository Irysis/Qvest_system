cat("=== STR_1692: Industry Momentum RSI Residualized (H_1692 v2 Core_Secondary) ===\n")
## 핵심아이디어: M07_IndMom residualized on M18_RSI — expanding OLS beta, burn-in 36m
## Grinblatt-Moskowitz 1999 + Wilder 1978 + Lee-Swaminathan 2000 + Hanauer-Huber 2019
## S1 pure signal: C1(expand beta 36m) C2(t+1) C10(LIQ 2e8) C13(Z_Aligned) C15(load_month_factors)

QEPM_AUTO_COMMIT <- TRUE
t0 <- Sys.time()

# ===================================================================
# 0. Environment
# ===================================================================
.root_candidates <- c(
  Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot")),
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

STRATEGY_ID     <- "STR_1692"
HYPOTHESIS_ID   <- "H_1692_v2"
STRATEGY_FAMILY <- "industry_momentum_residual"
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
RAWDATA[, LiqPass := !is.na(AvgTV20) & AvgTV20 >= LIQ_THRESHOLD]

cat(sprintf("[Step 2] %s ~ %s | %d tickers\n",
            min(RAWDATA$Date), max(RAWDATA$Date), uniqueN(RAWDATA$Ticker)))

# ===================================================================
# 3. Factor engine
# ===================================================================
cat("\n[Step 3] Factor engine (H_1692 v2 Industry Mom RSI Residual)...\n")
source(file.path(STRAT_DIR, "factor_engine.R"))
stopifnot(is.data.table(FACTORS), all(c("Date","Ticker","Score") %in% names(FACTORS)))
cat(sprintf("[Step 3] V1: %d rows | V2: %d | V3: %d\n",
            nrow(FACTORS), nrow(FACTORS_V2), nrow(FACTORS_V3)))

# ===================================================================
# 4. PIT detection
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
# 5. 3-variant simulations (mclapply)
# ===================================================================
cat("\n[Step 5] 3-variant simulations (mclapply)...\n")

variants <- list(V1_residual = FACTORS, V2_M07only = FACTORS_V2, V3_M18neg = FACTORS_V3)
sim_args <- list(
  RAWDATA = RAWDATA, BM_DT = BM_DT,
  n_holdings = N_HOLD, weight_method = WEIGHT_METHOD,
  commission = COMMISSION, buffer_zone = BUFFER_ZONE
)
n_cores <- min(3L, max(1L, detectCores() - 1L))
sims <- mclapply(names(variants), function(vn) {
  fac <- variants[[vn]]
  if (nrow(fac) < 50L) return(list(error = paste("empty:", vn)))
  tryCatch(do.call(run_monthly_simulation, c(list(FACTORS = fac), sim_args)),
           error = function(e) list(error = conditionMessage(e)))
}, mc.cores = n_cores)
names(sims) <- names(variants)

sim <- sims[["V1_residual"]]
if (!is.null(sim$error)) { cat(sprintf("[FATAL V1] %s\n", sim$error)); stop("V1 failed") }
cat(sprintf("[Step 5] V1 done: %d trading days\n", length(sim$strategy_xts)))

# ===================================================================
# 6. Analysis (V1 primary)
# ===================================================================
cat("\n[Step 6] Analysis (V1 primary)...\n")
tryCatch({
  source(file.path(FUNC_PATH, "strategy_analyzer.R"))
  run_analysis(sim, FACTORS, RAWDATA, BM_DT, OUT_DIR, strategy_name = STRATEGY_ID)
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

perf_xts <- sim$strategy_xts
ann_ret  <- as.numeric(Return.annualized(perf_xts, scale = 252))
sr_val   <- as.numeric(SharpeRatio.annualized(perf_xts, Rf = 0, scale = 252))
mdd_val  <- as.numeric(maxDrawdown(perf_xts))

# ===================================================================
# 8. ICIR + 3-period + net IC gain vs M07-only (S1 action_2)
# ===================================================================
cat("\n[Step 8] ICIR + M07 standalone comparison...\n")

compute_icir_dt <- function(FAC, RD) {
  sd_v <- sort(unique(FAC$Date))
  ic_list <- lapply(seq_along(sd_v), function(i) {
    if (i == length(sd_v)) return(NULL)
    sd <- sd_v[i]; next_sd <- sd_v[i + 1L]
    fwd <- RD[Date > sd & Date <= next_sd, .(fwd_ret = prod(1+Ret,na.rm=TRUE)-1), by=Ticker]
    sc  <- FAC[Date == sd, .(Ticker, Score)]
    mg  <- merge(sc, fwd, by = "Ticker")
    if (nrow(mg) < 10L) return(NULL)
    data.table(Date = sd, IC = cor(mg$Score, mg$fwd_ret, method="spearman", use="complete.obs"))
  })
  rbindlist(ic_list[!sapply(ic_list, is.null)])[!is.na(IC)]
}

ic_v1 <- compute_icir_dt(FACTORS,    RAWDATA)
ic_v2 <- compute_icir_dt(FACTORS_V2, RAWDATA)

icir_v1 <- if (nrow(ic_v1) > 1) mean(ic_v1$IC)/sd(ic_v1$IC) else NA_real_
icir_v2 <- if (nrow(ic_v2) > 1) mean(ic_v2$IC)/sd(ic_v2$IC) else NA_real_

alpha_lab_pass <- !is.na(icir_v1) && icir_v1 >= 0.20

# 3-period breakdown
icir_period <- function(d) if (nrow(d) < 6) NA_real_ else mean(d$IC)/sd(d$IC)
icir_2004_2014 <- icir_period(ic_v1[Date <  as.Date("2015-01-01")])
icir_2015_2019 <- icir_period(ic_v1[Date >= as.Date("2015-01-01") & Date < as.Date("2020-01-01")])
icir_2020_2026 <- icir_period(ic_v1[Date >= as.Date("2020-01-01")])

net_ic_gain <- if (!is.na(icir_v1) && !is.na(icir_v2)) icir_v1 - icir_v2 else NA_real_

cat(sprintf("[ICIR] V1(residual)=%.3f | V2(M07)=%.3f | net_gain=%.3f\n",
            icir_v1 %||% NA, icir_v2 %||% NA, net_ic_gain %||% NA))
cat(sprintf("[3-period] 2004-14=%.3f | 2015-19=%.3f | 2020-26=%.3f\n",
            icir_2004_2014 %||% NA, icir_2015_2019 %||% NA, icir_2020_2026 %||% NA))

fwrite(data.table(
  metric = c("icir_V1_residual","icir_V2_M07only","net_ic_gain",
             "icir_2004_2014","icir_2015_2019","icir_2020_2026"),
  value  = c(icir_v1, icir_v2, net_ic_gain, icir_2004_2014, icir_2015_2019, icir_2020_2026)
), file.path(OUT_DIR, "h1692v2_icir_net_gain.csv"))

# ===================================================================
# 9. IC-to-return transmission (S1 action_4 net of costs >0.6)
# ===================================================================
cat("\n[Step 9] IC-to-return transmission net of costs...\n")

gross_icir <- icir_v1 %||% 0
cost_drag  <- 0.0015 + 0.003  # 15bps commission + 30bps slippage
transmission_ratio <- if (!is.na(sr_val) && !is.na(ann_ret) && abs(ann_ret) > 0.001)
  max(0, (ann_ret - cost_drag) / ann_ret) else NA_real_
cat(sprintf("[Step 9] transmission_ratio=%.3f | gate>0.6: %s\n",
            transmission_ratio %||% NA,
            ifelse(!is.na(transmission_ratio) && transmission_ratio > 0.6, "PASS", "WARN")))

# ===================================================================
# 9b. GATE 1: beta_t timeseries CSV (GATE 1 산출물)
# ===================================================================
if (!is.null(H1692V2_BETA_DT) && nrow(H1692V2_BETA_DT) > 0L) {
  beta_ts <- merge(H1692V2_BETA_DT,
                   monthly_agg[, .(Date, cum_num, cum_den, beta_raw)],
                   by = "Date", all.x = TRUE)
  fwrite(beta_ts, file.path(OUT_DIR, "h1692_v2_beta_t_timeseries.csv"))
  cat(sprintf("[GATE 1] beta_t_timeseries.csv saved: %d months | first valid=%s\n",
              nrow(beta_ts), as.character(H1692V2_BETA_DT[!is.na(beta), min(Date)])))
}

# ===================================================================
# 10. Beta structural break audit (S1 action_3)
# ===================================================================
cat("\n[Step 10] Beta structural break audit...\n")
if (!is.null(H1692V2_BETA_BY_PERIOD) && nrow(H1692V2_BETA_BY_PERIOD) > 0L) {
  cat("[Beta by period]\n"); print(H1692V2_BETA_BY_PERIOD)
  betas <- H1692V2_BETA_BY_PERIOD$mean_beta
  max_delta <- if (length(betas) >= 2) max(abs(diff(betas)), na.rm = TRUE) else NA_real_
  rolling_beta_std <- sd(H1692V2_BETA_DT[!is.na(beta), beta], na.rm = TRUE)
  gate3_pass <- !is.na(rolling_beta_std) && rolling_beta_std >= 0.02 &&
                !is.na(max_delta) && max_delta >= 0.05
  cat(sprintf("[Step 10] Max beta delta: %.4f (>=0.05: %s) | rolling_std: %.4f (>=0.02: %s)\n",
              max_delta %||% NA,
              ifelse(!is.na(max_delta) && max_delta >= 0.05, "BREAK_DETECTED", "STABLE"),
              rolling_beta_std %||% NA,
              ifelse(!is.na(rolling_beta_std) && rolling_beta_std >= 0.02, "PASS", "FAIL")))
  fwrite(H1692V2_BETA_BY_PERIOD, file.path(OUT_DIR, "h1692_v2_beta_structural_break_audit.csv"))
}

# ===================================================================
# 11. Variant comparison
# ===================================================================
cat("\n[Step 11] Variant comparison...\n")
variant_perf <- rbindlist(lapply(names(sims), function(vn) {
  s <- sims[[vn]]
  if (!is.null(s$error) || is.null(s$strategy_xts))
    return(data.table(variant=vn, cagr=NA, sr=NA, mdd=NA))
  x <- s$strategy_xts
  data.table(
    variant  = vn,
    cagr     = round(as.numeric(Return.annualized(x, scale=252)) * 100, 2),
    sr       = round(as.numeric(SharpeRatio.annualized(x, Rf=0, scale=252)), 3),
    mdd      = round(as.numeric(maxDrawdown(x)) * 100, 2)
  )
}))
cat("[Variants]\n"); print(variant_perf)
fwrite(variant_perf, file.path(OUT_DIR, "variant_comparison.csv"))

# ===================================================================
# 12. Tail risk
# ===================================================================
cat("\n[Step 12] Tail risk...\n")
tail_risk_res <- tryCatch({
  source(file.path(FUNC_PATH, "risk_engine.R"))
  compute_tail_risk_suite(sim$strategy_xts, output_dir = OUT_DIR, strategy_id = STRATEGY_ID)
}, error = function(e) {
  cat("[WARN tail_risk]", conditionMessage(e), "\n")
  rets  <- as.numeric(sim$strategy_xts)
  es_99 <- quantile(rets, 0.01, na.rm = TRUE)
  res   <- list(evt_xi=NA_real_, cdar_95=as.numeric(maxDrawdown(sim$strategy_xts)),
                es_99_monthly=round(es_99, 4), overall_pass=FALSE)
  write_json(c(res, list(strategy_id=STRATEGY_ID, hypothesis_id=HYPOTHESIS_ID,
                          date=as.character(Sys.Date()))),
             file.path(OUT_DIR, "tail_risk_result.json"), pretty=TRUE, auto_unbox=TRUE)
  res
})
cat(sprintf("[Tail] CDaR_95=%.2f%% | pass=%s\n",
            (tail_risk_res$cdar_95 %||% NA)*100, tail_risk_res$overall_pass %||% FALSE))

# ===================================================================
# 13. S1 artifact
# ===================================================================
cat("\n[Step 13] Saving s1_construction_H_1692_v2.json...\n")

s1_art <- list(
  strategy_id   = STRATEGY_ID,
  hypothesis_id = HYPOTHESIS_ID,
  stage         = "S1",
  date          = as.character(Sys.Date()),
  family        = STRATEGY_FAMILY,
  expected_role = "core_secondary",
  role_bias     = "RoleBias_Core",
  trail         = "standard",
  gap_targeting_axes = c("SR", "KR_structural"),
  performance   = list(
    cagr   = round(ann_ret * 100, 2),
    sharpe = round(sr_val, 3),
    mdd    = round(mdd_val * 100, 2),
    grade  = hurdle$grade %||% "?",
    score  = as.numeric(hurdle$score %||% 0)
  ),
  portfolio     = list(n_holdings=N_HOLD, weight_method=WEIGHT_METHOD,
                       commission=COMMISSION, buffer_zone=BUFFER_ZONE,
                       liq_threshold=LIQ_THRESHOLD),
  pit_evidence  = H1692V2_PIT_EVIDENCE,
  alpha_lab_gate = list(icir_threshold=0.20, icir=round(icir_v1%||%NA,3), pass=alpha_lab_pass),
  three_period_icir = list(
    p1_2004_2014 = round(icir_2004_2014%||%NA, 3),
    p2_2015_2019 = round(icir_2015_2019%||%NA, 3),
    p3_2020_2026 = round(icir_2020_2026%||%NA, 3)
  ),
  net_ic_gain_vs_M07   = round(net_ic_gain%||%NA, 4),
  transmission_ratio   = round(transmission_ratio%||%NA, 4),
  beta_structural_break = H1692V2_BETA_BY_PERIOD,
  variant_comparison   = variant_perf,
  tail_risk_gate       = list(pass=tail_risk_res$overall_pass%||%FALSE,
                               cdar_95=round(tail_risk_res$cdar_95%||%NA, 4))
)
art_path <- file.path(PROJECT_ROOT, "stage_artifacts", "s1_construction_H_1692_v2.json")
write_json(s1_art, art_path, pretty = TRUE, auto_unbox = TRUE)
cat(sprintf("[Step 13] Saved: %s\n", art_path))

# ===================================================================
# 14. Charts
# ===================================================================
tryCatch({
  generate_charts(sim, output_dir = OUT_DIR)
  cat("[Step 14] Charts saved.\n")
}, error = function(e) cat("[Step 14 WARN]", conditionMessage(e), "\n"))

# ===================================================================
# 15. Summary
# ===================================================================
elapsed <- round(difftime(Sys.time(), t0, units = "mins"), 1)
cat(sprintf("\n=== STR_1692 S1 COMPLETE ===\n"))
cat(sprintf("  Grade: %s | Score: %.1f\n", hurdle$grade %||% "?", as.numeric(hurdle$score %||% 0)))
cat(sprintf("  CAGR: %.1f%% | SR: %.3f | MDD: %.1f%%\n", ann_ret*100, sr_val, mdd_val*100))
cat(sprintf("  ICIR(V1): %.3f (>=0.20: %s) | M07 ICIR: %.3f | net_gain: %.3f\n",
            icir_v1%||%NA, ifelse(alpha_lab_pass,"PASS","FAIL"),
            icir_v2%||%NA, net_ic_gain%||%NA))
cat(sprintf("  Transmission: %.3f | Elapsed: %s min\n", transmission_ratio%||%NA, elapsed))

# ===================================================================
# 16. Telegram
# ===================================================================
tryCatch({
  source(file.path(FUNC_PATH, "telegram", "telegram_notify.R"))
  tg_send(paste0(
    "[Forge] STR_1692 S1 완료 (H_1692 v2 Industry Momentum RSI Residual)\n",
    sprintf("Grade: %s | Score: %.1f\n", hurdle$grade%||%"?", as.numeric(hurdle$score%||%0)),
    sprintf("CAGR: %.1f%% | SR: %.3f | MDD: %.1f%%\n", ann_ret*100, sr_val, mdd_val*100),
    sprintf("ICIR: %.3f (>=0.20: %s) | M07 ICIR: %.3f | net_gain: %.3f\n",
            icir_v1%||%NA, ifelse(alpha_lab_pass,"PASS","FAIL"),
            icir_v2%||%NA, net_ic_gain%||%NA),
    "RoleBias: RoleBias_Core | Family: industry_momentum_residual"
  ))
  chart_path <- file.path(OUT_DIR, "equity_curve.png")
  if (file.exists(chart_path)) tg_send_photo(chart_path, caption = "STR_1692 Equity Curve")
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
      role_bias     = "RoleBias_Core",
      tags          = c("H_1692_v2", "industry_momentum", "RSI_residual",
                        "core_secondary", "expanding_OLS", "S1")
    )
    cat("[QEPM] hybrid_commit done.\n")
  }, error = function(e) cat("[QEPM WARN]", conditionMessage(e), "\n"))
}

# ===================================================================
# 18. DONE mail to Scout + Forge inbox rename
# ===================================================================
tryCatch({
  done_path <- file.path(PROJECT_ROOT, "qepm", "mailbox", "scout", "inbox",
                         "DONE_S1_RESULT_H_1692_v2_industry_mom_rsi_residual.json")
  write_json(list(
    from=         "Forge", to="Scout",
    subject=      "DONE S1 — H_1692 v2 Industry Momentum RSI Residual",
    date=         as.character(Sys.Date()),
    hypothesis_id= HYPOTHESIS_ID, strategy_id=STRATEGY_ID, status="complete",
    grade=        hurdle$grade%||%"ERR",
    cagr=         round(ann_ret*100,2), sr=round(sr_val,3), mdd=round(mdd_val*100,2),
    icir_V1=      round(icir_v1%||%NA,3), icir_V2_M07=round(icir_v2%||%NA,3),
    net_ic_gain=  round(net_ic_gain%||%NA,4),
    alpha_lab_gate= alpha_lab_pass,
    artifact_path= art_path
  ), done_path, pretty=TRUE, auto_unbox=TRUE)
  cat(sprintf("[Step 18] DONE mail: %s\n", done_path))
}, error = function(e) cat("[WARN done_mail]", conditionMessage(e), "\n"))

tryCatch({
  todo_p <- file.path(PROJECT_ROOT, "qepm", "mailbox", "forge", "inbox",
                      "TODO_S1_H_1692_v2_core_secondary.json")
  done_p <- file.path(PROJECT_ROOT, "qepm", "mailbox", "forge", "inbox",
                      "DONE_S1_H_1692_v2_core_secondary.json")
  if (file.exists(todo_p)) file.rename(todo_p, done_p)
  cat("[Step 18] Inbox TODO renamed to DONE.\n")
}, error = function(e) cat("[WARN rename]", conditionMessage(e), "\n"))

cat("[DONE]\n")
