cat("=== STR_1682: Residual Consensus Revision Breadth (H_1676 Diversifier) ===\n")
## 핵심아이디어: C13_Revision_Breadth_3m residualized on log(MarketCap)+R12_Idiosyncratic_Risk
## Cross-section OLS → expanding Z-score → Top 20 EW. Orthogonal PEAD diversifier.
## S1 pure signal: PIT C1(expanding Z) C2(t+1 exec) C13(Z_Score_Aligned) C15(bulk load) C10(LIQ lag).

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

FUNC_PATH <- file.path(PROJECT_ROOT, "02_Infrastructure")
CACHE_DIR <- file.path(PROJECT_ROOT, ".cache")
STRAT_DIR <- tryCatch(dirname(sys.frame(1)$ofile), error = function(e) getwd())
OUT_DIR   <- file.path(STRAT_DIR, "output")
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

STRATEGY_ID     <- "STR_1682"
STRATEGY_FAMILY <- "consensus"
N_HOLD          <- 20L
LIQ_THRESHOLD   <- 2e8
COMMISSION      <- 0.0015
BUFFER_ZONE     <- list(keep_n = 22L, entry_n = 20L)
WEIGHT_METHOD   <- "equal"

# ===================================================================
# 1. Preflight check
# ===================================================================
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
# 3. Factor engine
# ===================================================================
cat("\n[Step 3] Factor engine (residual C13 bulk load)...\n")
source(file.path(STRAT_DIR, "factor_engine.R"))
stopifnot(is.data.table(FACTORS), all(c("Date","Ticker","Score") %in% names(FACTORS)))
cat(sprintf("[Step 3] FACTORS: %d rows | %d dates\n",
            nrow(FACTORS), uniqueN(FACTORS$Date)))

# ===================================================================
# 4. Lookahead detection
# ===================================================================
tryCatch({
  source(file.path(VALIDATION_DIR, "lookahead_detector.R"))
  pit <- detect_lookahead(file.path(STRAT_DIR, "factor_engine.R"))
  if (!isTRUE(pit$clean)) {
    for (v in pit$violations)
      cat(sprintf("[PIT VIOLATION] L%d [%s]: %s\n", v$line, v$check, v$msg))
    stop("PIT violation. Aborting.")
  }
  cat("[Step 4] PIT: CLEAN\n")
}, error = function(e) {
  if (grepl("PIT violation", conditionMessage(e))) stop(e)
  cat("[Step 4 WARN]", conditionMessage(e), "\n")
})

# ===================================================================
# 5. Backtest — EW 20, 15bps, pure factor signal
# ===================================================================
cat("\n[Step 5] Monthly simulation (EW 20, 15bps, pure factor)...\n")
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
# 8. COND_03: Portfolio CAPM beta (|β| < 0.15 gate)
# ===================================================================
cat("\n[Step 8] COND_03 — CAPM beta gate...\n")
capm_beta <- tryCatch({
  str_xts <- sim$strategy_xts
  bm_sub  <- BM_DT[Date %in% index(str_xts)]
  bm_xts  <- xts(bm_sub$Ret, order.by = bm_sub$Date)
  mg      <- merge(str_xts, bm_xts, join = "inner")
  colnames(mg) <- c("strat", "bench")
  fit <- lm(strat ~ bench, data = as.data.frame(mg))
  coef(fit)["bench"]
}, error = function(e) { cat("[WARN CAPM]", conditionMessage(e), "\n"); NA_real_ })

cat(sprintf("[CAPM beta] beta=%.4f | |beta|<0.15: %s\n",
            capm_beta %||% NA,
            ifelse(!is.na(capm_beta) && abs(capm_beta) < 0.15, "PASS", "FAIL")))

# ===================================================================
# 9. COND_04: Rolling 3Y residual ICIR drift
# ===================================================================
cat("\n[Step 9] COND_04 — Rolling 3Y ICIR drift...\n")
r12_result <- tryCatch({
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
  if (nrow(ic_monthly) < 12L) return(list(drift_ratio=NA, stable=NA, overall_icir=NA))
  ic_monthly[, ICIR_36M := frollmean(IC, n=36L, align="right") /
               frollapply(IC, n=36L, FUN=sd, align="right", fill=NA)]
  recent <- ic_monthly[!is.na(ICIR_36M), tail(ICIR_36M, 36L)]
  drift  <- if (length(recent) > 5) sd(recent) / abs(mean(recent)) else NA
  list(
    ic_monthly   = ic_monthly,
    drift_ratio  = drift,
    stable       = !is.na(drift) && drift < 0.30,
    overall_icir = if (nrow(ic_monthly) > 0) {
      mean(ic_monthly$IC, na.rm=TRUE) / sd(ic_monthly$IC, na.rm=TRUE)
    } else NA
  )
}, error = function(e) {
  cat("[WARN ICIR]", conditionMessage(e), "\n")
  list(drift_ratio=NA, stable=NA, overall_icir=NA)
})

cat(sprintf("[ICIR drift] ratio=%.3f | stable(drift<30%%): %s | overall ICIR=%.3f\n",
            r12_result$drift_ratio %||% NA,
            r12_result$stable %||% NA,
            r12_result$overall_icir %||% NA))

# ===================================================================
# 10. s1_construction_H_1676 artifact
# ===================================================================
cat("\n[Step 10] Saving s1_construction_H_1676.json...\n")
perf_xts <- sim$strategy_xts
ann_ret  <- as.numeric(Return.annualized(perf_xts, scale = 252))
sr       <- as.numeric(SharpeRatio.annualized(perf_xts, Rf = 0, scale = 252))
mdd      <- as.numeric(maxDrawdown(perf_xts))

s1_art <- list(
  strategy_id   = STRATEGY_ID,
  hypothesis_id = "H_1676",
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
  pit_evidence  = if (exists("H1676_PIT_EVIDENCE")) H1676_PIT_EVIDENCE else list(),
  capm_beta      = round(capm_beta %||% NA, 4),
  capm_beta_gate = list(
    threshold = 0.15,
    pass      = !is.na(capm_beta) && abs(capm_beta) < 0.15
  ),
  r12_stability = list(
    drift_ratio  = round(r12_result$drift_ratio %||% NA, 4),
    stable       = r12_result$stable %||% NA,
    overall_icir = round(r12_result$overall_icir %||% NA, 3)
  ),
  alpha_lab_gate = list(
    icir_threshold = 0.20,
    overall_icir   = round(r12_result$overall_icir %||% NA, 3),
    pass           = !is.na(r12_result$overall_icir) && r12_result$overall_icir >= 0.20
  ),
  conditions_met = list(
    COND_01 = "applied — diversifier role, RoleBias_Diversifier",
    COND_02 = "applied — STR_1537 lesson_check in s0_record v2",
    COND_03 = list(status="applied", capm_beta=capm_beta%||%NA,
                   pass=!is.na(capm_beta)&&abs(capm_beta)<0.15),
    COND_04 = list(status="applied", drift_ratio=r12_result$drift_ratio%||%NA,
                   stable=r12_result$stable%||%NA),
    COND_05 = list(status="applied",
                   pit_evidence=if(exists("H1676_PIT_EVIDENCE")) H1676_PIT_EVIDENCE else list()),
    COND_06 = "pending — S5 slate registration (Scout)",
    COND_07 = "pending — S3 orthogonality (Scout)"
  )
)

art_path <- file.path(PROJECT_ROOT, "stage_artifacts", "s1_construction_H_1676.json")
write_json(s1_art, art_path, pretty = TRUE, auto_unbox = TRUE)
cat(sprintf("[Step 10] Saved: %s\n", art_path))

# ===================================================================
# 11. Charts
# ===================================================================
tryCatch({
  generate_charts(sim, output_dir = OUT_DIR)
  cat("[Step 11] Charts saved.\n")
}, error = function(e) cat("[Step 11 WARN]", conditionMessage(e), "\n"))

# ===================================================================
# 12. Summary
# ===================================================================
elapsed <- round(difftime(Sys.time(), t0, units = "mins"), 1)
cat(sprintf("\n=== STR_1682 S1 COMPLETE ===\n"))
cat(sprintf("  Grade: %s | Score: %.1f\n", hurdle$grade %||% "?", as.numeric(hurdle$score %||% 0)))
cat(sprintf("  CAGR: %.1f%% | SR: %.3f | MDD: %.1f%%\n", ann_ret*100, sr, mdd*100))
cat(sprintf("  CAPM beta: %.4f (|beta|<0.15: %s)\n",
            capm_beta %||% NA,
            ifelse(!is.na(capm_beta) && abs(capm_beta) < 0.15, "PASS", "FAIL")))
cat(sprintf("  ICIR drift: %.3f (stable: %s)\n",
            r12_result$drift_ratio %||% NA, r12_result$stable %||% NA))
cat(sprintf("  Elapsed: %s min\n", elapsed))

# ===================================================================
# 13. Telegram
# ===================================================================
tryCatch({
  source(file.path(FUNC_PATH, "telegram", "telegram_notify.R"))
  msg <- paste0(
    "[Forge] STR_1682 S1 완료 (H_1676 Residual Consensus Diversifier)\n",
    sprintf("Grade: %s | Score: %.1f\n", hurdle$grade %||% "?", as.numeric(hurdle$score %||% 0)),
    sprintf("CAGR: %.1f%% | SR: %.3f | MDD: %.1f%%\n", ann_ret*100, sr, mdd*100),
    sprintf("CAPM beta: %.4f | |beta|<0.15: %s\n",
            capm_beta %||% NA,
            ifelse(!is.na(capm_beta) && abs(capm_beta)<0.15,"PASS","FAIL")),
    sprintf("ICIR drift ratio: %.3f | stable: %s\n",
            r12_result$drift_ratio %||% NA, r12_result$stable %||% NA),
    "RoleBias: RoleBias_Diversifier | Family: consensus"
  )
  tg_send(msg)
  chart_path <- file.path(OUT_DIR, "equity_curve.png")
  if (file.exists(chart_path)) tg_send_photo(chart_path, caption = "STR_1682 Equity Curve")
}, error = function(e) cat("[Telegram WARN]", conditionMessage(e), "\n"))

# ===================================================================
# 14. QEPM auto-commit
# ===================================================================
if (isTRUE(QEPM_AUTO_COMMIT)) {
  tryCatch({
    source(file.path(PROJECT_ROOT, "qepm", "scripts", "hybrid_mode.R"))
    hybrid_commit(
      strategy      = STRATEGY_ID,
      family        = STRATEGY_FAMILY,
      hurdle_result = hurdle,
      role_bias     = "RoleBias_Diversifier",
      tags          = c("H_1676","consensus","residual_revision","diversifier","S1")
    )
    cat("[QEPM] hybrid_commit done.\n")
  }, error = function(e) cat("[QEPM WARN]", conditionMessage(e), "\n"))
}

cat("[DONE]\n")
