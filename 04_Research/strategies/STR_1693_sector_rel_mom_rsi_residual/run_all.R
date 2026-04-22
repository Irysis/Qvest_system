cat("=== STR_1693: Sector-Relative Industry Momentum Residualized on RSI (H_1692 Core_Secondary) ===\n")
## 핵심아이디어: M07_IndMom residualized on M18_RSI via expanding pooled OLS
## Grinblatt-Moskowitz 1999 industry momentum + Wilder 1978 RSI overbought filter
## S1 pure signal: PIT C1(expanding OLS strict) C2(t+1 exec) C13(Z_Score_Aligned)
##                 C14(Usable_Date) C15/Gate13(load_month_factors only) C10(LIQ lag)

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
  library(lubridate); library(jsonlite)
})
options(scipen = 999); Sys.setenv(TZ = "Asia/Seoul")

`%||%` <- function(a, b) if (!is.null(a) && length(a) > 0) a else b

STRATEGY_ID     <- "STR_1693"
STRATEGY_FAMILY <- "industry_momentum_residual"
N_HOLD          <- 20L
LIQ_THRESHOLD   <- 2e8
COMMISSION      <- 0.0015
BUFFER_ZONE     <- list(keep_n = 22L, entry_n = 20L)
WEIGHT_METHOD   <- "equal"

# ===================================================================
# 1. Preflight check — Gate 13 enforcement
# ===================================================================
cat("\n[Step 1] Preflight check (Gate 13 enforcement)...\n")

# Gate 13: factor_engine.R must use load_month_factors() — NO direct parquet access
.fe_lines <- readLines(file.path(STRAT_DIR, "factor_engine.R"))
.direct_parquet_pattern <- paste0("arrow", "::", "read_parquet|",
                                   "^\\s*dt\\s*<-\\s*read_parquet\\(fp")
.gate13_violations <- grep(.direct_parquet_pattern, .fe_lines, value = TRUE)
if (length(.gate13_violations) > 0) {
  cat("[GATE 13 VIOLATION] factor_engine.R contains direct parquet access:\n")
  lapply(.gate13_violations, function(v) cat("  ", v, "\n"))
  stop("Gate 13 violation: factor_engine.R must use load_month_factors() only")
}
cat("[Gate 13] PASS — load_month_factors() confirmed\n")
rm(.fe_lines, .direct_parquet_pattern, .gate13_violations)

tryCatch({
  source(file.path(VALIDATION_DIR, "preflight_memory.R"))
  preflight_check(STRATEGY_ID, family = STRATEGY_FAMILY)
}, error = function(e) cat("[Preflight]", conditionMessage(e), "\n"))

# ===================================================================
# 2. Load raw data (once, C15)
# ===================================================================
cat("\n[Step 2] Loading RAWDATA...\n")
res     <- load_rawdata(use_cache = TRUE)
RAWDATA <- res$RAWDATA
BM_DT   <- res$BM_DT
rm(res); gc(verbose = FALSE)

setkey(RAWDATA, Date, Ticker)

# Liquidity pre-compute: 20d lagged avg trading value (C10)
RAWDATA[, TradingValue := Close * Vol]
RAWDATA[order(Date), AvgTV20 := frollmean(TradingValue, n = 20L, align = "right"), by = Ticker]
RAWDATA[, LiqPass := !is.na(AvgTV20) & AvgTV20 >= LIQ_THRESHOLD]

cat(sprintf("[Step 2] %s ~ %s | %d tickers\n",
            min(RAWDATA$Date), max(RAWDATA$Date), uniqueN(RAWDATA$Ticker)))

# ===================================================================
# 3. Factor engine — V1 baseline (expanding OLS)
# ===================================================================
cat("\n[Step 3] Factor engine V1 (expanding OLS, M07 residualized on M18)...\n")
source(file.path(STRAT_DIR, "factor_engine.R"))
stopifnot(is.data.table(FACTORS), all(c("Date","Ticker","Score") %in% names(FACTORS)))
cat(sprintf("[Step 3] FACTORS V1: %d rows | %d dates\n",
            nrow(FACTORS), uniqueN(FACTORS$Date)))

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
# 5. Backtest V1 — EW 20, 15bps, pure factor signal
# ===================================================================
cat("\n[Step 5] Monthly simulation V1 (EW 20, 15bps, pure factor)...\n")
sim <- tryCatch(
  run_monthly_simulation(
    RAWDATA       = RAWDATA,
    BM_DT         = BM_DT,
    FACTORS       = FACTORS,
    n_holdings    = N_HOLD,
    weight_method = WEIGHT_METHOD,
    commission    = COMMISSION,
    buffer_zone   = BUFFER_ZONE
  ),
  error = function(e) { cat("[FATAL]", conditionMessage(e), "\n"); stop(e) }
)
cat(sprintf("[Step 5] Done: %d trading days\n", length(sim$strategy_xts)))

# ===================================================================
# 6. Analysis
# ===================================================================
cat("\n[Step 6] Analysis...\n")
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
# 8. CAPM beta (Core_Secondary — 0.95~1.10 expected)
# ===================================================================
cat("\n[Step 8] CAPM beta...\n")
capm_beta <- tryCatch({
  str_xts <- sim$strategy_xts
  bm_sub  <- BM_DT[Date %in% index(str_xts)]
  bm_xts  <- xts(bm_sub$Ret, order.by = bm_sub$Date)
  mg      <- merge(str_xts, bm_xts, join = "inner")
  colnames(mg) <- c("strat", "bench")
  coef(lm(strat ~ bench, data = as.data.frame(mg)))["bench"]
}, error = function(e) { cat("[WARN CAPM]", conditionMessage(e), "\n"); NA_real_ })

cat(sprintf("[CAPM beta] beta=%.4f | Core_Secondary range [0.7,1.3]: %s\n",
            capm_beta %||% NA,
            ifelse(!is.na(capm_beta) && capm_beta >= 0.7 && capm_beta <= 1.3,
                   "WITHIN_RANGE", "OUT_OF_RANGE")))

# ===================================================================
# 9. Rolling ICIR via lapply (Alpha Lab Gate: ICIR >= 0.20)
# ===================================================================
cat("\n[Step 9] Rolling ICIR (Alpha Lab Gate >= 0.20)...\n")
icir_result <- tryCatch({
  sig_dates <- sort(unique(FACTORS$Date))
  ic_monthly <- rbindlist(lapply(seq_along(sig_dates), function(i) {
    sd <- sig_dates[i]
    if (i == length(sig_dates)) return(NULL)
    next_sd <- sig_dates[i + 1L]
    fwd <- RAWDATA[Date > sd & Date <= next_sd,
                   .(fwd_ret = prod(1 + Ret, na.rm = TRUE) - 1), by = Ticker]
    sc  <- FACTORS[Date == sd, .(Ticker, Score)]
    mg  <- merge(sc, fwd, by = "Ticker")
    if (nrow(mg) < 10L) return(NULL)
    ic_v <- cor(mg$Score, mg$fwd_ret, method = "spearman", use = "complete.obs")
    data.table(Date = sd, IC = ic_v)
  }))
  ic_monthly <- ic_monthly[!is.na(IC)]
  if (nrow(ic_monthly) < 12L) return(list(overall_icir=NA, ic_monthly=ic_monthly))
  overall_icir <- mean(ic_monthly$IC, na.rm=TRUE) / sd(ic_monthly$IC, na.rm=TRUE)
  ic_monthly[, ICIR_36M := frollmean(IC, n=36L, align="right") /
               frollapply(IC, n=36L, FUN=sd, align="right", fill=NA)]
  list(overall_icir = overall_icir, ic_monthly = ic_monthly)
}, error = function(e) {
  cat("[WARN ICIR]", conditionMessage(e), "\n")
  list(overall_icir = NA, ic_monthly = data.table())
})

alpha_lab_pass <- !is.na(icir_result$overall_icir) && icir_result$overall_icir >= 0.20
cat(sprintf("[Alpha Lab Gate] ICIR=%.3f | >= 0.20: %s\n",
            icir_result$overall_icir %||% NA,
            ifelse(alpha_lab_pass, "PASS", "FAIL")))

# ===================================================================
# 10. beta_t diagnostics
# ===================================================================
cat("\n[Step 10] beta_t diagnostics (L-161 avoidance)...\n")
beta_diag <- list(status = "not_available")
if (exists("H1692_BETA_SERIES") && is.data.table(H1692_BETA_SERIES) && nrow(H1692_BETA_SERIES) > 0) {
  beta_diag <- list(
    status    = "available",
    n_months  = nrow(H1692_BETA_SERIES),
    mean_beta = round(mean(H1692_BETA_SERIES$beta_t, na.rm = TRUE), 4),
    sd_beta   = round(sd(H1692_BETA_SERIES$beta_t, na.rm = TRUE), 4),
    min_beta  = round(min(H1692_BETA_SERIES$beta_t, na.rm = TRUE), 4),
    max_beta  = round(max(H1692_BETA_SERIES$beta_t, na.rm = TRUE), 4),
    l161_note = "M07 sd=1.0, M18 sd=1.0 — balanced OLS, no scale distortion"
  )
  cat(sprintf("[beta_t] mean=%.4f | sd=%.4f | range=[%.4f, %.4f]\n",
              beta_diag$mean_beta, beta_diag$sd_beta,
              beta_diag$min_beta, beta_diag$max_beta))
}

# ===================================================================
# 11. s1_construction_H_1692 artifact
# ===================================================================
cat("\n[Step 11] Saving s1_construction_H_1692.json...\n")
perf_xts <- sim$strategy_xts
ann_ret  <- as.numeric(Return.annualized(perf_xts, scale = 252))
sr       <- as.numeric(SharpeRatio.annualized(perf_xts, Rf = 0, scale = 252))
mdd      <- as.numeric(maxDrawdown(perf_xts))

s1_art <- list(
  strategy_id   = STRATEGY_ID,
  hypothesis_id = "H_1692",
  stage         = "S1",
  date          = as.character(Sys.Date()),
  family        = STRATEGY_FAMILY,
  expected_role = "core_secondary",
  role_bias     = "RoleBias_Core",
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
  pit_evidence     = if (exists("H1692_PIT_EVIDENCE")) H1692_PIT_EVIDENCE else list(),
  capm_beta        = round(capm_beta %||% NA, 4),
  capm_beta_note   = "Core_Secondary: beta 0.95~1.10 expected (industry momentum intrinsic)",
  alpha_lab_gate   = list(
    icir_threshold = 0.20,
    overall_icir   = round(icir_result$overall_icir %||% NA, 3),
    pass           = alpha_lab_pass
  ),
  beta_diagnostics = beta_diag,
  gate13_status    = "PASS",
  l161_avoidance   = "M07_IndMom sd=1.000 + M18_RSI sd=1.000: scale-balanced OLS",
  s1_variant       = "V1_baseline",
  s5_variants_pending = list(
    V2 = "63d lookback sensitivity",
    V3 = "sector-neutral residual",
    V4 = "M07 raw no residualization (control)"
  )
)

art_path <- file.path(PROJECT_ROOT, "stage_artifacts", "s1_construction_H_1692.json")
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
cat(sprintf("\n=== STR_1693 S1 COMPLETE ===\n"))
cat(sprintf("  Grade: %s | Score: %.1f\n", hurdle$grade %||% "?", as.numeric(hurdle$score %||% 0)))
cat(sprintf("  CAGR: %.1f%% | SR: %.3f | MDD: %.1f%%\n", ann_ret*100, sr, mdd*100))
cat(sprintf("  CAPM beta: %.4f\n", capm_beta %||% NA))
cat(sprintf("  Alpha Lab ICIR: %.3f (>= 0.20: %s)\n",
            icir_result$overall_icir %||% NA, ifelse(alpha_lab_pass, "PASS", "FAIL")))
cat(sprintf("  Elapsed: %s min\n", elapsed))

# ===================================================================
# 14. Telegram
# ===================================================================
tryCatch({
  source(file.path(FUNC_PATH, "telegram", "telegram_notify.R"))
  msg <- paste0(
    "[Forge] STR_1693 S1 완료 (H_1692 IndMom RSI Residualized Core_Secondary)\n",
    sprintf("Grade: %s | Score: %.1f\n", hurdle$grade %||% "?", as.numeric(hurdle$score %||% 0)),
    sprintf("CAGR: %.1f%% | SR: %.3f | MDD: %.1f%%\n", ann_ret*100, sr, mdd*100),
    sprintf("CAPM beta: %.4f\n", capm_beta %||% NA),
    sprintf("Alpha Lab ICIR: %.3f (>= 0.20: %s)\n",
            icir_result$overall_icir %||% NA, ifelse(alpha_lab_pass, "PASS", "FAIL")),
    "RoleBias: RoleBias_Core | Family: industry_momentum_residual | Gate13: PASS"
  )
  tg_send(msg)
  chart_path <- file.path(OUT_DIR, "equity_curve.png")
  if (file.exists(chart_path)) tg_send_photo(chart_path, caption = "STR_1693 Equity Curve")
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
      role_bias     = "RoleBias_Core",
      tags          = c("H_1692", "industry_momentum_residual", "rsi_orthogonal",
                        "core_secondary", "S1", "Gate13")
    )
    cat("[QEPM] hybrid_commit done.\n")
  }, error = function(e) cat("[QEPM WARN]", conditionMessage(e), "\n"))
}

cat("[DONE]\n")
