## STR_1549: Defense Core Alpha (D01_IdioVol + D02_Beta + Q07_EarningsStability)
## Family: defense_core_alpha
## Bucket: explore
##
## Core Idea: Weighted RankCombo (IVol 50% + Beta 30% + Q07 20%).
##   Harvest structural low-vol premium (Frazzini & Pedersen 2014 BAB) with
##   earnings stability quality filter (Dichev & Tang 2009).
##   Phase 1 (S1): top 30 by weighted RankCombo, equal weight, monthly rebalance.
##   Sector-neutral required (B1). Size-neutral OFF (B1: harmful for defense).
##
## PIT: Factor DB Z_Score_Aligned via Arrow (C13/C15). Liq t-1 lagged (C10).
##      No full-sample stats (C1). No same-day circular (C2). C1-C15 compliant.
## Overlay: NONE (S0/S1 rule — pure factor signal measurement only).
cat("=== STR_1549: Defense Core Alpha (D01+D02+Q07) ===\n")
cat("## Core: IVol(0.50)+Beta(0.30)+Q07(0.20) Weighted RankCombo, sector-neutral\n")

set.seed(1549)
options(scipen = 999)
Sys.setenv(TZ = "Asia/Seoul")

STRATEGY_NAME   <- "Defense_Core_Alpha"
STRATEGY_ID     <- "STR_1549"
STRATEGY_FAMILY <- "defense_core_alpha"
QEPM_AUTO_COMMIT <- TRUE

# ============================================================================
# Step 0: Infrastructure
# ============================================================================
SCRIPT_DIR <- tryCatch({
  d <- dirname(sys.frame(1)$ofile)
  if (d == ".") getwd() else d
}, error = function(e) {
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("--file=", args, value = TRUE)
  if (length(file_arg) > 0) {
    p <- sub("--file=", "", file_arg[1])
    p <- gsub("~+~", " ", p, fixed = TRUE)
    dirname(p)
  } else getwd()
})

INFRA_DIR <- file.path(dirname(dirname(dirname(SCRIPT_DIR))), "02_Infrastructure")
if (!file.exists(file.path(INFRA_DIR, "config.R"))) {
  INFRA_DIR <- file.path(
    "/mnt/c/Users/User/OneDrive/\ubc14\ud0d5 \ud654\uba74/Quant_Module_Moltbot",
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
# Step 1: Load data + Factor Engine
# ============================================================================
cat("[Step 1] Loading data + factor engine...\n")
N_HOLDINGS <- 30L; COMMISSION <- 0.0015

res <- load_rawdata(use_cache = TRUE)
RAWDATA <- res$RAWDATA; BM_DT <- res$BM_DT
rm(res); gc(verbose = FALSE)

source(file.path(SCRIPT_DIR, "factor_engine.R"))
stopifnot(is.data.table(FACTORS), nrow(FACTORS) > 0)
cat(sprintf("  FACTORS: %d rows | %d signal dates\n", nrow(FACTORS), uniqueN(FACTORS$Date)))

# ============================================================================
# Step 2: Backtest — EW, N=30
# ============================================================================
cat(sprintf("\n[Step 2] EW Backtest: N=%d\n", N_HOLDINGS))
sim <- run_monthly_simulation(
  RAWDATA = RAWDATA, BM_DT = BM_DT, FACTORS = FACTORS,
  n_holdings = N_HOLDINGS, weight_method = "equal",
  commission = COMMISSION, buffer_zone = list(keep_n = 40L, entry_n = 30L)
)

# ============================================================================
# Step 3: Performance + Hurdle Gate
# ============================================================================
cat("\n[Step 3] Performance + Hurdle Gate...\n")
output_dir <- file.path(SCRIPT_DIR, "output")
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

perf_strat <- summarise_perf(sim$strategy_xts, STRATEGY_NAME)
perf_bm    <- summarise_perf(sim$bm_xts, "Benchmark_K200")
cat(sprintf("  [Strategy] CAGR=%.2f%% | SR=%.3f | MDD=%.1f%%\n",
            perf_strat$CAGR, perf_strat$Sharpe, perf_strat$MDD))
cat(sprintf("  [BM]       CAGR=%.2f%% | SR=%.3f | MDD=%.1f%%\n",
            perf_bm$CAGR, perf_bm$Sharpe, perf_bm$MDD))

generate_charts(sim, output_dir = output_dir, strategy_name = STRATEGY_NAME)
fwrite(rbind(perf_strat, perf_bm), file.path(output_dir, "performance.csv"))
saveRDS(sim, file.path(output_dir, "sim_result.rds"))
saveRDS(sim, file.path(SCRIPT_DIR, "sim_result.rds"))

tryCatch({
  source(file.path(INFRA_DIR, "strategy_analyzer.R"))
  run_analysis(sim, FACTORS, RAWDATA, BM_DT, output_dir, strategy_name = STRATEGY_ID)
}, error = function(e) cat("[WARN] strategy_analyzer:", e$message, "\n"))

hurdle <- tryCatch({
  source(file.path(INFRA_DIR, "hurdle_gate.R"))
  run_hurdle_gate(sim_result = sim, FACTORS = FACTORS, strategy_name = STRATEGY_NAME,
                  strategy_file = file.path(SCRIPT_DIR, "run_all.R"), output_dir = output_dir)
}, error = function(e) { cat("Hurdle error:", e$message, "\n"); NULL })

if (!is.null(hurdle)) {
  cat(sprintf("\n  Grade: %s | Score: %.1f | Verdict: %s\n",
              hurdle$grade, hurdle$total_score %||% hurdle$score %||% 0,
              if (isTRUE(hurdle$pass)) "PASS" else "FAIL"))
  jsonlite::write_json(hurdle, file.path(output_dir, "hurdle_result.json"),
                       auto_unbox = TRUE, pretty = TRUE)
}

# ============================================================================
# Step 4: Telegram notification
# ============================================================================
tryCatch({
  source(file.path(TELEGRAM_DIR, "telegram_notify.R"))
  msg <- sprintf(paste0(
    "[Scout] STR_1549 Defense Core Alpha S1 \xec\x99\x84\xeb\xa3\x8c\n",
    "\xf0\x9f\x9b\xa1\xef\xb8\x8f D01(IVol 50%%) + D02(Beta 30%%) + Q07(EarnStab 20%%)\n\n",
    "\xf0\x9f\x93\x8a \xea\xb2\xb0\xea\xb3\xbc:\n",
    "  CAGR: %.2f%% | SR: %.3f | MDD: %.1f%%\n",
    "  Grade: %s | Score: %.1f\n\n",
    "\xf0\x9f\x94\xac \xed\x95\x99\xec\x88\xa0\xea\xb7\xbc\xea\xb1\xb0: BAB(FP2014) + IdioVol(AHXZ2006)\n",
    "\xf0\x9f\x8e\xaf \xec\x97\xad\xed\x95\xa0: Core Alpha (PG0 \xec\xb2\xab \xec\xa0\x84\xeb\x9e\xb5)"
  ),
  perf_strat$CAGR, perf_strat$Sharpe, perf_strat$MDD,
  if (!is.null(hurdle)) hurdle$grade else "N/A",
  if (!is.null(hurdle)) (hurdle$total_score %||% hurdle$score %||% 0) else 0)
  tg_send(msg)

  # Send charts
  eq_chart <- file.path(output_dir, "equity_curve.png")
  ar_chart <- file.path(output_dir, "annual_returns.png")
  if (file.exists(eq_chart)) tg_send_photo(eq_chart)
  if (file.exists(ar_chart)) tg_send_photo(ar_chart)
}, error = function(e) cat("[TG]", e$message, "\n"))

cat("\n=== STR_1549: Defense Core Alpha COMPLETE ===\n")
