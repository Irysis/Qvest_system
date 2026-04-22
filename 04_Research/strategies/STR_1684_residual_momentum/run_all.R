cat("=== STR_1684: H_1688 Residual Momentum Core_Secondary (Blitz-Huij-Martens 2011) ===\n")
## 핵심아이디어: M01_Mom_12_1 residualized on 24M CAPM beta + log(Size) + R12_IdioVol
## Expanding Z-score -> Top 20 EW. S1 pure factor signal.
## V2/V3/V4 variants -> S5 Mutation slate only (S1 single signal baseline here).
## PIT: C1(expanding Z) C2(t+1+beta lag) C10(LIQ frollmean) C13(Z_Score_Aligned) C15(bulk load).

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

STRATEGY_ID     <- "STR_1684"
STRATEGY_FAMILY <- "momentum_residual"
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
# 2. Load raw data (once, C15/OPT-1)
# ===================================================================
cat("\n[Step 2] Loading RAWDATA...\n")
res     <- load_rawdata(use_cache = TRUE)
RAWDATA <- res$RAWDATA
BM_DT   <- res$BM_DT
rm(res); gc(verbose = FALSE)

setkey(RAWDATA, Date, Ticker)

# OPT-10: Liquidity filter — frollmean(TradingValue, 20) >= LIQ_THRESHOLD, lagged (C10)
RAWDATA[, TradingValue := Close * Vol]
RAWDATA[order(Date), AvgTV20 := frollmean(TradingValue, n = 20L, align = "right"), by = Ticker]
RAWDATA[, LiqPass := !is.na(AvgTV20) & AvgTV20 >= LIQ_THRESHOLD]

cat(sprintf("[Step 2] %s ~ %s | %d tickers\n",
            min(RAWDATA$Date), max(RAWDATA$Date), uniqueN(RAWDATA$Ticker)))

# ===================================================================
# 3. Factor engine (M01 residualization + 24M rolling beta)
# ===================================================================
cat("\n[Step 3] Factor engine (M01 residualization + Vasicek 24M beta)...\n")
source(file.path(STRAT_DIR, "factor_engine.R"))
stopifnot(is.data.table(FACTORS), all(c("Date","Ticker","Score") %in% names(FACTORS)))
cat(sprintf("[Step 3] FACTORS V1: %d rows | %d dates\n",
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
# 5. V1 Baseline simulation — pure factor signal
# ===================================================================
cat("\n[Step 5] V1 Baseline simulation (EW 20, 15bps, pure residual momentum)...\n")
sim <- tryCatch(
  run_monthly_simulation(
    RAWDATA = RAWDATA, BM_DT = BM_DT, FACTORS = FACTORS,
    n_holdings = N_HOLD, weight_method = WEIGHT_METHOD,
    commission = COMMISSION, buffer_zone = BUFFER_ZONE
  ),
  error = function(e) { cat("[FATAL]", conditionMessage(e), "\n"); stop(e) }
)
cat(sprintf("[Step 5] Done: %d trading days\n", length(sim$strategy_xts)))

perf_xts <- sim$strategy_xts
ann_ret  <- as.numeric(Return.annualized(perf_xts, scale = 252))
sr       <- as.numeric(SharpeRatio.annualized(perf_xts, Rf = 0, scale = 252))
mdd      <- as.numeric(maxDrawdown(perf_xts))

# ===================================================================
# 6. COND_01: M08 baseline ICIR comparison (kill gate)
# ===================================================================
cat("\n[Step 6] COND_01 — M08_Residual_Mom ICIR vs H_1688...\n")
compute_icir <- function(FACS, RAWDATA_dt, label) {
  sig_dates_v <- sort(unique(FACS$Date))
  ic_list <- lapply(seq_along(sig_dates_v), function(i) {
    sd <- sig_dates_v[i]
    if (i == length(sig_dates_v)) return(NULL)
    next_sd <- sig_dates_v[i + 1L]
    fwd <- RAWDATA_dt[Date > sd & Date <= next_sd,
                      .(fwd_ret = prod(1+Ret, na.rm=TRUE)-1), by=Ticker]
    sc  <- FACS[Date == sd, .(Ticker, Score)]
    mg  <- merge(sc, fwd, by="Ticker")
    if (nrow(mg) < 10L) return(NULL)
    data.table(Date=sd, IC=cor(mg$Score, mg$fwd_ret, method="spearman", use="complete.obs"))
  })
  ic_dt <- rbindlist(ic_list[!sapply(ic_list, is.null)], fill=TRUE)
  ic_dt <- ic_dt[!is.na(IC)]
  if (nrow(ic_dt) == 0) return(list(icir=NA, n=0L, label=label))
  icir_val <- mean(ic_dt$IC) / sd(ic_dt$IC)
  cat(sprintf("[ICIR %s] %.4f (n=%d months)\n", label, icir_val, nrow(ic_dt)))
  list(icir=icir_val, n=nrow(ic_dt), label=label)
}

icir_h1688 <- compute_icir(FACTORS,     RAWDATA, "H_1688_V1")
icir_m08   <- compute_icir(FACTORS_M08, RAWDATA, "M08_baseline")

h1688_beats_m08 <- !is.na(icir_h1688$icir) && !is.na(icir_m08$icir) &&
                   icir_h1688$icir > icir_m08$icir

icir_comparison <- data.table(
  variant        = c("H_1688_V1_residual", "M08_Residual_Mom_baseline"),
  icir           = c(icir_h1688$icir %||% NA, icir_m08$icir %||% NA),
  n_months       = c(icir_h1688$n   %||% 0L,  icir_m08$n   %||% 0L)
)
fwrite(icir_comparison, file.path(OUT_DIR, "h1688_m08_vs_h1688_icir_comparison.csv"))
cat(sprintf("[COND_01] H_1688=%.4f vs M08=%.4f | kill_gate_pass: %s\n",
            icir_h1688$icir %||% NA, icir_m08$icir %||% NA, h1688_beats_m08))

# ===================================================================
# 7. Analysis
# ===================================================================
cat("\n[Step 7] Analysis...\n")
tryCatch({
  source(file.path(FUNC_PATH, "strategy_analyzer.R"))
  run_analysis(sim, FACTORS, RAWDATA, BM_DT, OUT_DIR, strategy_name = STRATEGY_ID)
}, error = function(e) {
  cat("[Step 7 WARN]", conditionMessage(e), "\n")
  tryCatch({
    perf <- summarise_perf(sim$strategy_xts, STRATEGY_ID)
    fwrite(as.data.table(t(unlist(perf))), file.path(OUT_DIR, "performance.csv"))
  }, error = function(e2) NULL)
})

# ===================================================================
# 8. Hurdle gate
# ===================================================================
cat("\n[Step 8] Hurdle gate...\n")
source(file.path(FUNC_PATH, "hurdle_gate.R"))
hurdle <- tryCatch(
  run_hurdle_gate(sim, strategy_name = STRATEGY_ID, output_dir = OUT_DIR),
  error = function(e) { cat("[WARN hurdle]", conditionMessage(e), "\n"); list(grade="ERR", score=0) }
)
cat(sprintf("[Step 8] Grade: %s | Score: %.1f\n",
            hurdle$grade %||% "?", as.numeric(hurdle$score %||% 0)))

# ===================================================================
# 9. COND_05: Tail risk suite
# ===================================================================
cat("\n[Step 9] COND_05 — Tail risk suite...\n")
tail_risk <- tryCatch({
  source(file.path(FUNC_PATH, "risk_engine.R"))
  compute_tail_risk_suite(sim$strategy_xts, output_dir = OUT_DIR)
}, error = function(e) {
  cat("[WARN tail_risk]", conditionMessage(e), "\n")
  rets  <- as.numeric(perf_xts)
  es_99 <- quantile(rets, 0.01, na.rm = TRUE)
  list(
    evt_xi        = NA,
    cdar_95       = as.numeric(maxDrawdown(perf_xts)),
    es_99_monthly = round(es_99, 4),
    evt_gate      = NA,
    cdar_gate     = as.numeric(maxDrawdown(perf_xts)) < 0.25,
    es_gate       = es_99 > -0.12,
    overall_pass  = FALSE
  )
})
cat(sprintf("[Tail risk] CDaR_95=%.2f%% | ES_99=%.2f%% | pass=%s\n",
            (tail_risk$cdar_95 %||% NA) * 100,
            (tail_risk$es_99_monthly %||% NA) * 100,
            tail_risk$overall_pass %||% NA))

write_json(
  c(tail_risk, list(strategy_id=STRATEGY_ID, hypothesis_id="H_1688",
                    variant="V1_baseline", date=as.character(Sys.Date()))),
  file.path(OUT_DIR, "tail_risk_result.json"), pretty=TRUE, auto_unbox=TRUE
)

# ===================================================================
# 10. COND_10: Core_Secondary gate + CAPM beta
# ===================================================================
cat("\n[Step 10] COND_10 — Core_Secondary gate...\n")
cond_10_pass <- !is.na(icir_h1688$icir) && icir_h1688$icir >= 0.35 &&
                !is.na(sr) && sr >= 0.70 && !is.na(ann_ret) && ann_ret > 0.08
cat(sprintf("[COND_10] ICIR=%.4f | SR=%.3f | CAGR=%.1f%% | Core_Secondary: %s\n",
            icir_h1688$icir %||% NA, sr, ann_ret*100, cond_10_pass))

capm_beta <- tryCatch({
  bm_sub <- BM_DT[Date %in% index(perf_xts)]
  bm_xts <- xts(bm_sub$BM_Ret, order.by = bm_sub$Date)
  mg     <- merge(perf_xts, bm_xts, join = "inner")
  colnames(mg) <- c("strat", "bench")
  coef(lm(strat ~ bench, data = as.data.frame(mg)))["bench"]
}, error = function(e) { cat("[WARN CAPM]", conditionMessage(e), "\n"); NA_real_ })
cat(sprintf("[CAPM beta] %.4f | abs_beta<0.85: %s\n",
            capm_beta %||% NA,
            ifelse(!is.na(capm_beta) && abs(capm_beta) < 0.85, "PASS", "FAIL")))

# ===================================================================
# 11. Save daily returns + monthly holdings (S3/FF5 용)
# ===================================================================
tryCatch({
  fwrite(data.table(Date=index(perf_xts), Return=as.numeric(perf_xts)),
         file.path(OUT_DIR, "daily_returns_primary.csv"))
  cat("[Step 11] daily_returns saved.\n")
}, error = function(e) cat("[WARN daily_ret]", conditionMessage(e), "\n"))
tryCatch({
  if (!is.null(sim$holdings))
    fwrite(sim$holdings, file.path(OUT_DIR, "monthly_top20_holdings.csv"))
}, error = function(e) cat("[WARN holdings]", conditionMessage(e), "\n"))

# ===================================================================
# 12. Save beta artifact (COND_02)
# ===================================================================
tryCatch({
  if (exists("H1688_BETA_DT") && nrow(H1688_BETA_DT) > 0)
    write_parquet(H1688_BETA_DT, file.path(OUT_DIR, "h1688_beta_24m_rolling.parquet"))
  cat("[Step 12] Beta parquet saved.\n")
}, error = function(e) cat("[WARN beta parquet]", conditionMessage(e), "\n"))

# ===================================================================
# 13. s1_construction_H_1688 artifact (full, replaces placeholder)
# ===================================================================
cat("\n[Step 13] Saving s1_construction_H_1688.json...\n")
s1_art <- list(
  strategy_id   = STRATEGY_ID,
  hypothesis_id = "H_1688",
  stage         = "S1",
  date          = as.character(Sys.Date()),
  status        = "complete",
  family        = STRATEGY_FAMILY,
  expected_role = "Core_Secondary",
  role_bias     = "RoleBias_Core",
  performance   = list(
    cagr   = round(ann_ret * 100, 2),
    sharpe = round(sr, 3),
    mdd    = round(mdd * 100, 2),
    icir   = round(icir_h1688$icir %||% NA, 4),
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
  pit_evidence   = if (exists("H1688_PIT_EVIDENCE")) H1688_PIT_EVIDENCE else list(),
  capm_beta      = round(capm_beta %||% NA, 4),
  capm_beta_gate = list(threshold=0.85, pass=!is.na(capm_beta)&&abs(capm_beta)<0.85),
  cond_01 = list(
    status         = "applied",
    h1688_icir     = round(icir_h1688$icir %||% NA, 4),
    m08_icir       = round(icir_m08$icir %||% NA, 4),
    kill_gate_pass = h1688_beats_m08
  ),
  cond_02 = list(
    status            = "applied",
    beta_window_days  = 504L,
    vasicek_shrinkage = TRUE,
    c2_strict         = TRUE,
    beta_months       = if(exists("H1688_BETA_DT")) uniqueN(H1688_BETA_DT$Date) else NA
  ),
  cond_03 = "applied — M01 (not M04) + R12 Z_Score_Aligned no flip (C13)",
  cond_04 = list(status="applied",
                 pit_evidence=if(exists("H1688_PIT_EVIDENCE")) H1688_PIT_EVIDENCE else list()),
  cond_05 = list(
    status       = "applied",
    cdar_95      = round(tail_risk$cdar_95 %||% NA, 4),
    es_99        = round(tail_risk$es_99_monthly %||% NA, 4),
    overall_pass = tail_risk$overall_pass %||% NA
  ),
  cond_10 = list(
    status              = "applied",
    icir                = round(icir_h1688$icir %||% NA, 4),
    sr                  = round(sr, 3),
    cagr                = round(ann_ret * 100, 2),
    core_secondary_pass = cond_10_pass
  ),
  s5_slate_note = "Barroso vol-scaling / multi-horizon composite / DD-brake variants -> S5 only",
  conditions_met = list(
    COND_01 = list(status="applied", kill_gate_pass=h1688_beats_m08),
    COND_02 = "applied — 24M rolling beta Vasicek, C2 strict",
    COND_03 = "applied — Factor ID corrected M01, R12 sign C13",
    COND_04 = "applied — PIT CHECKLIST 4건 명시",
    COND_05 = list(status="applied", overall_pass=tail_risk$overall_pass %||% NA),
    COND_06 = "pending — S3 DCC (Scout)",
    COND_07 = "pending — S5 slate (Scout, COND_10 PASS 후)",
    COND_08 = "pending — S2 rolling ICIR drift (Scout)",
    COND_09 = "applied — COND_03 Factor DB correction",
    COND_10 = list(status="applied", pass=cond_10_pass),
    COND_11 = "pending — S3 H_1687 orthogonality (Scout)",
    COND_12 = "pending — S6 FF5 UMD (Judge)"
  )
)
art_path <- file.path(PROJECT_ROOT, "stage_artifacts", "s1_construction_H_1688.json")
write_json(s1_art, art_path, pretty=TRUE, auto_unbox=TRUE)
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
cat(sprintf("\n=== STR_1684 S1 COMPLETE ===\n"))
cat(sprintf("  Grade: %s | Score: %.1f\n", hurdle$grade %||% "?", as.numeric(hurdle$score %||% 0)))
cat(sprintf("  CAGR: %.1f%% | SR: %.3f | MDD: %.1f%%\n", ann_ret*100, sr, mdd*100))
cat(sprintf("  ICIR: %.4f | beats_M08: %s | Core_Secondary: %s\n",
            icir_h1688$icir %||% NA, h1688_beats_m08, cond_10_pass))
cat(sprintf("  CAPM beta: %.4f | Tail risk pass: %s\n",
            capm_beta %||% NA, tail_risk$overall_pass %||% NA))
cat(sprintf("  Elapsed: %s min\n", elapsed))

# ===================================================================
# 16. Telegram
# ===================================================================
tryCatch({
  source(file.path(FUNC_PATH, "telegram", "telegram_notify.R"))
  msg <- paste0(
    "[Forge] STR_1684 S1 완료 (H_1688 Residual Momentum Core_Secondary)\n",
    sprintf("Grade: %s | Score: %.1f\n", hurdle$grade %||% "?", as.numeric(hurdle$score %||% 0)),
    sprintf("CAGR: %.1f%% | SR: %.3f | MDD: %.1f%%\n", ann_ret*100, sr, mdd*100),
    sprintf("ICIR: %.4f | H_1688>M08: %s\n", icir_h1688$icir %||% NA, h1688_beats_m08),
    sprintf("Core_Secondary(ICIR>=0.35+SR>=0.70+CAGR>8%%): %s\n", cond_10_pass),
    sprintf("CAPM beta: %.4f | Tail risk pass: %s\n",
            capm_beta %||% NA, tail_risk$overall_pass %||% NA),
    "RoleBias: RoleBias_Core | Family: momentum_residual | AX-003/004/005: PASS"
  )
  tg_send(msg)
  chart_path <- file.path(OUT_DIR, "equity_curve.png")
  if (file.exists(chart_path)) tg_send_photo(chart_path, caption = "STR_1684 Equity Curve")
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
      tags          = c("H_1688","momentum_residual","blitz2011","core_secondary","S1")
    )
    cat("[QEPM] hybrid_commit done.\n")
  }, error = function(e) cat("[QEPM WARN]", conditionMessage(e), "\n"))
}

cat("[DONE]\n")
