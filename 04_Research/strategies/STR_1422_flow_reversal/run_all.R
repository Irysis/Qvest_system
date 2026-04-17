cat("=== STR_1422: S5 M2 — D01 IdioVol 0.7 + Flow Reversal 0.3 Blend ===\n")
## S5 Mutation: D01(검증 alpha) * 0.7 + FlowRev(독립 신호) * 0.3
## Original: Foreign net buying contrarian standalone → S5: D01 blend

set.seed(1422)
options(scipen = 999)
Sys.setenv(TZ = "Asia/Seoul")

STRATEGY_NAME   <- "D01_FlowRev_Blend"
STRATEGY_ID     <- "STR_1422"
STRATEGY_FAMILY <- "flow_reversal"
QEPM_AUTO_COMMIT <- TRUE

SCRIPT_DIR <- tryCatch(dirname(sys.frame(1)$ofile), error = function(e) getwd())
INFRA_DIR  <- file.path(SCRIPT_DIR, "..", "..", "..", "02_Infrastructure")
if (!file.exists(file.path(INFRA_DIR, "config.R"))) {
  INFRA_DIR <- file.path(
    "/mnt/c/Users/User/OneDrive/\ubc14\ud0d5 \ud654\uba74/Quant_Module_Moltbot",
    "02_Infrastructure")
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

cat(sprintf("\n=== %s: %s ===\n\n", STRATEGY_ID, STRATEGY_NAME))
LIQ_THRESHOLD <- 2e8

# ============================================================================
# Phase 1: Load data + Factor Engine (D01 + FlowRev blend)
# ============================================================================
cat("\n[Phase 1] Loading data + factor engine...\n")
res <- load_rawdata(use_cache = TRUE)
RAWDATA <- res$RAWDATA; BM_DT <- res$BM_DT
RAWDATA_ORIG <- copy(RAWDATA)
rm(res); gc(verbose = FALSE)

source(file.path(SCRIPT_DIR, "factor_engine.R"))

stopifnot(is.data.table(FACTORS),
          all(c("Date", "Ticker", "Score") %in% names(FACTORS)),
          nrow(FACTORS) > 0)
cat(sprintf("  FACTORS: %d rows | %d signal dates\n",
            nrow(FACTORS), uniqueN(FACTORS$Date)))

# ============================================================================
# Phase 2: Base backtest — N=30, EW, BZ 50/25
# ============================================================================
cat("\n[Phase 2] Running base backtest (N=30, EW, BZ 50/25)...\n")
RAWDATA <- copy(RAWDATA_ORIG)

sim_base <- run_monthly_simulation(
  RAWDATA       = RAWDATA,
  BM_DT         = BM_DT,
  FACTORS       = FACTORS,
  n_holdings    = 30L,
  weight_method = "equal",
  commission    = 0.0015,
  buffer_zone   = list(keep_n = 50L, entry_n = 25L)
)

# ============================================================================
# Phase 3: DD Brake overlay (S5: DD 8/22/30, t-1 lagged)
# ============================================================================
cat("\n[Phase 3] DD Brake overlay (t-1, start=8%, full=22%, min_exp=30%)...\n")
raw_ret   <- as.numeric(sim_base$strategy_xts)
raw_dates <- as.Date(index(sim_base$strategy_xts))
n_f       <- length(raw_ret)

nav_dd  <- cumprod(1 + raw_ret)
dd_pct  <- 1 - nav_dd / cummax(nav_dd)

DD_START <- 0.08; DD_FULL <- 0.22; DD_MIN_EXP <- 0.30

dd_pct_lagged <- c(0, dd_pct[-n_f])
dd_exp_lagged <- fifelse(dd_pct_lagged <= DD_START, 1.0,
                fifelse(dd_pct_lagged >= DD_FULL, DD_MIN_EXP,
                        pmax(DD_MIN_EXP,
                             1.0 - (dd_pct_lagged - DD_START) /
                                   (DD_FULL - DD_START) * (1 - DD_MIN_EXP))))

final_ret <- raw_ret * dd_exp_lagged

cat(sprintf("  DD Brake active: %.1f%% of days (mean exposure=%.3f)\n",
            mean(dd_exp_lagged < 1.0) * 100, mean(dd_exp_lagged)))

# ============================================================================
# Phase 4: Final assembly
# ============================================================================
cat("\n[Phase 4] Final assembly...\n")
combined_xts <- xts(final_ret, order.by = raw_dates)
names(combined_xts) <- "Strategy"

sim <- sim_base
sim$strategy_xts <- combined_xts
sim$bm_xts <- sim_base$bm_xts[raw_dates]
sim$DAILY_NAV_DT <- data.table(
  Date         = raw_dates,
  NAV          = cumprod(1 + final_ret) * 10000,
  Strategy_Ret = final_ret
)

# ============================================================================
# Phase 5: Analysis + Hurdle Gate
# ============================================================================
cat("\n[Phase 5] Analysis + Hurdle Gate...\n")
output_dir <- file.path(SCRIPT_DIR, "output")
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

perf_strat <- summarise_perf(sim$strategy_xts, STRATEGY_NAME)
perf_bm    <- summarise_perf(sim$bm_xts, "Benchmark_K200")
cat(sprintf("\n  %s Results:\n", STRATEGY_ID))
cat(sprintf("  CAGR=%.2f%% | Sharpe=%.3f | MDD=%.1f%%\n",
            perf_strat$CAGR, perf_strat$Sharpe, perf_strat$MDD))
print(rbind(perf_strat, perf_bm))

generate_charts(sim, output_dir = output_dir, strategy_name = STRATEGY_NAME)
fwrite(rbind(perf_strat, perf_bm), file.path(output_dir, "performance.csv"))
saveRDS(sim, file.path(output_dir, "sim_result.rds"))
saveRDS(sim, file.path(SCRIPT_DIR, "sim_result.rds"))

RAWDATA <- copy(RAWDATA_ORIG)
tryCatch({
  source(file.path(INFRA_DIR, "strategy_analyzer.R"))
  run_analysis(sim, FACTORS, RAWDATA, BM_DT, output_dir,
               strategy_name = STRATEGY_ID)
}, error = function(e) cat("[WARN] strategy_analyzer:", e$message, "\n"))

source(file.path(INFRA_DIR, "hurdle_gate.R"))
hurdle <- run_hurdle_gate(
  sim_result    = sim,
  FACTORS       = FACTORS,
  strategy_name = STRATEGY_NAME,
  strategy_file = file.path(SCRIPT_DIR, "factor_engine.R"),
  output_dir    = output_dir
)

cat(sprintf("\n  Grade: %s | Score: %.1f | Verdict: %s\n",
            hurdle$grade,
            hurdle$total_score %||% hurdle$score %||% 0,
            if (isTRUE(hurdle$pass)) "PASS" else "FAIL"))

jsonlite::write_json(hurdle, file.path(output_dir, "hurdle_result.json"),
                     auto_unbox = TRUE, pretty = TRUE)

# ============================================================================
# Phase 6: Telegram + QEPM
# ============================================================================
cat("\n[Phase 6] Telegram + QEPM commit...\n")
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
      if (exists("hybrid_commit")) {
        hybrid_commit(strategy_name = STRATEGY_ID, family = STRATEGY_FAMILY,
                      hurdle_result = hurdle, artifact_paths = list(output_dir))
        cat("[QEPM] hybrid_commit() complete\n")
      }
    }
  }, error = function(e) cat("[QEPM] auto-commit:", e$message, "\n"))
}

cat(sprintf("\n=== %s Complete. Grade=%s Score=%.1f ===\n",
            STRATEGY_ID, hurdle$grade,
            hurdle$total_score %||% hurdle$score %||% 0))
