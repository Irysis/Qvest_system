## STR_1393: Bayes Quality Trend (GR02+Q17+Q23)
## Family: esbr_sue_adaptive
## MF_09: FC_2c BayesShrinkage + Quality trending 3F
## Explore priority. Novy-Marx(2013) profitability.
cat("=== STR_1393: Bayes Quality Trend (GR02+Q17+Q23) ===\n")
## 핵심아이디어: 이익성장(GR02)+자본효율(Q17)+지속가능성장(Q23) BayesShrinkage 결합

set.seed(1393)
options(scipen = 999)
Sys.setenv(TZ = "Asia/Seoul")

STRATEGY_NAME   <- "ESBRSUEAdaptive"
STRATEGY_ID     <- "STR_1393"
STRATEGY_FAMILY <- "esbr_sue_adaptive"
QEPM_AUTO_COMMIT <- TRUE

# ── Infrastructure ──
SCRIPT_DIR <- tryCatch(dirname(sys.frame(1)$ofile), error = function(e) getwd())
INFRA_DIR  <- file.path(SCRIPT_DIR, "..", "..", "..", "02_Infrastructure")
if (!file.exists(file.path(INFRA_DIR, "config.R"))) {
  INFRA_DIR <- file.path(
    Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot")),
    "02_Infrastructure"
  )
}
source(file.path(INFRA_DIR, "config.R"))
source(file.path(INFRA_DIR, "backtest_harness.R"))
library(data.table); library(xts); library(arrow)

tryCatch({
  source(file.path(VALIDATION_DIR, "preflight_memory.R"))
  preflight_check(STRATEGY_ID, family = STRATEGY_FAMILY)
}, error = function(e) cat("[Preflight]", e$message, "\n"))

tryCatch({
  source(file.path(VALIDATION_DIR, "lookahead_detector.R"))
  la1 <- detect_lookahead(file.path(SCRIPT_DIR, "run_all.R"))
  la2 <- detect_lookahead(file.path(SCRIPT_DIR, "factor_engine.R"))
  if (!la1$clean || !la2$clean) {
    for (v in c(la1$violations, la2$violations))
      cat(sprintf("  %s: L%d -- %s\n", v$check, v$line, v$msg))
    stop("Lookahead violations -- aborting.")
  }
  cat("[PIT] Lookahead scan: CLEAN\n")
}, error = function(e) {
  if (grepl("Lookahead violations", e$message)) stop(e$message)
  cat("[PIT] Scanner warning:", e$message, "\n")
})

# ============================================================================
# Phase 0: Load data
# ============================================================================
cat("\n[Phase 0] Loading data...\n")
res <- load_rawdata(use_cache = TRUE)
RAWDATA <- res$RAWDATA; BM_DT <- res$BM_DT
RAWDATA_ORIG <- copy(RAWDATA)
rm(res); gc(verbose = FALSE)

# ============================================================================
# Phase 1: Factor Engine (BayesShrinkage)
# ============================================================================
cat("\n[Phase 1] Factor engine (C04+C01 Adaptive IC Weight)...\n")
source(file.path(SCRIPT_DIR, "factor_engine.R"))

stopifnot(is.data.table(FACTORS),
          all(c("Date", "Ticker", "Score") %in% names(FACTORS)),
          nrow(FACTORS) > 0)
cat(sprintf("  FACTORS: %d rows | %d signal dates\n",
            nrow(FACTORS), uniqueN(FACTORS$Date)))

# ============================================================================
# Phase 2: Base backtest (N=30, EW, VT20%)
# ============================================================================
cat("\n[Phase 2] Backtest (N=30, EW, VT20%)...\n")
RAWDATA <- copy(RAWDATA_ORIG)

sim_base <- run_monthly_simulation(
  RAWDATA       = RAWDATA,
  BM_DT         = BM_DT,
  FACTORS       = FACTORS,
  n_holdings    = 30L,
  weight_method = "equal",
  commission    = 0.0015,
  buffer_zone   = list(keep_n = 50L, entry_n = 25L),
  vol_target    = 0.20,
  vol_lookback  = 60L
)

if (nrow(sim_base$HOLDINGS_LOG) > 0) {
  max_h <- sim_base$HOLDINGS_LOG[, .N, by = Exec_Date][, max(N)]
  cat(sprintf("  Max holdings: %d (limit 30)\n", max_h))
}

# ============================================================================
# Phase 3: DD Brake (t-1 lagged, 15%/35%)
# ============================================================================
cat("\n[Phase 3] DD Brake (t-1, 15%/35%)...\n")
raw_ret   <- as.numeric(sim_base$strategy_xts)
raw_dates <- as.Date(index(sim_base$strategy_xts))
n_f       <- length(raw_ret)

nav_dd  <- cumprod(1 + raw_ret)
dd_pct  <- 1 - nav_dd / cummax(nav_dd)
dd_pct_lagged <- c(0, dd_pct[-n_f])
dd_exp_lagged <- fifelse(dd_pct_lagged <= 0.15, 1.0,
                fifelse(dd_pct_lagged >= 0.35, 0.30,
                        pmax(0.30, 1.0 - (dd_pct_lagged - 0.15) / 0.20 * 0.70)))
final_ret <- raw_ret * dd_exp_lagged

cat(sprintf("  DD active: %.1f%% days (mean exp=%.3f)\n",
            mean(dd_exp_lagged < 1) * 100, mean(dd_exp_lagged)))

# ============================================================================
# Phase 4: Final assembly
# ============================================================================
cat("\n[Phase 4] Assembly...\n")
combined_xts <- xts(final_ret, order.by = raw_dates)
names(combined_xts) <- "Strategy"
sim <- sim_base
sim$strategy_xts <- combined_xts
sim$bm_xts <- sim_base$bm_xts[raw_dates]
sim$DAILY_NAV_DT <- data.table(Date = raw_dates, NAV = cumprod(1 + final_ret) * 10000,
                                Strategy_Ret = final_ret)

# ============================================================================
# Phase 5: Analysis + Hurdle
# ============================================================================
cat("\n[Phase 5] Analysis + Hurdle...\n")
output_dir <- file.path(SCRIPT_DIR, "output")
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

perf_strat <- summarise_perf(sim$strategy_xts, STRATEGY_NAME)
perf_bm    <- summarise_perf(sim$bm_xts, "Benchmark_K200")
cat(sprintf("\n  %s: CAGR=%.2f%% | SR=%.3f | MDD=%.1f%%\n",
            STRATEGY_ID, perf_strat$CAGR, perf_strat$Sharpe, perf_strat$MDD))
print(rbind(perf_strat, perf_bm))

generate_charts(sim, output_dir = output_dir, strategy_name = STRATEGY_NAME)
fwrite(rbind(perf_strat, perf_bm), file.path(output_dir, "performance.csv"))
saveRDS(sim, file.path(output_dir, "sim_result.rds"))
saveRDS(sim, file.path(SCRIPT_DIR, "sim_result.rds"))

RAWDATA <- copy(RAWDATA_ORIG)
tryCatch({
  source(file.path(INFRA_DIR, "strategy_analyzer.R"))
  run_analysis(sim, FACTORS, RAWDATA, BM_DT, output_dir, strategy_name = STRATEGY_ID)
}, error = function(e) cat("[WARN] analyzer:", e$message, "\n"))

source(file.path(INFRA_DIR, "hurdle_gate.R"))
hurdle <- run_hurdle_gate(sim_result = sim, FACTORS = FACTORS,
                          strategy_name = STRATEGY_NAME,
                          strategy_file = file.path(SCRIPT_DIR, "factor_engine.R"),
                          output_dir = output_dir)

cat(sprintf("\n  Grade: %s | Score: %.1f | Verdict: %s\n",
            hurdle$grade, hurdle$total_score %||% hurdle$score %||% 0,
            if (isTRUE(hurdle$pass)) "PASS" else "FAIL"))

jsonlite::write_json(hurdle, file.path(output_dir, "hurdle_result.json"),
                     auto_unbox = TRUE, pretty = TRUE)

# ============================================================================
# Phase 6: Telegram + QEPM
# ============================================================================
cat("\n[Phase 6] Telegram + QEPM...\n")
tryCatch({
  source(file.path(TELEGRAM_DIR, "telegram_notify.R"))
  hr <- jsonlite::fromJSON(file.path(output_dir, "hurdle_result.json"))
  tg_strategy_result_with_chart(STRATEGY_ID, hr, output_dir)
}, error = function(e) cat("[TG]", e$message, "\n"))

if (isTRUE(QEPM_AUTO_COMMIT)) {
  tryCatch({
    qepm_hybrid <- file.path(dirname(dirname(dirname(SCRIPT_DIR))),
                             "qepm", "scripts", "hybrid_mode.R")
    if (file.exists(qepm_hybrid)) {
      source(qepm_hybrid)
      if (exists("hybrid_commit"))
        hybrid_commit(strategy_name = STRATEGY_ID, family = STRATEGY_FAMILY,
                      hurdle_result = hurdle, artifact_paths = list(output_dir))
    }
  }, error = function(e) cat("[QEPM]", e$message, "\n"))
}

cat(sprintf("\n=== %s Complete. Grade=%s Score=%.1f ===\n",
            STRATEGY_ID, hurdle$grade, hurdle$total_score %||% hurdle$score %||% 0))
