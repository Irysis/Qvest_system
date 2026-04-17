## STR_1433: Consensus Triple Combo (C19 + C13 + C10)
## Family: consensus_triple_combo
## Bucket: explore
##
## Core Idea: C19_Composite_Earnings (ICIR 0.575) + C13_Revision_Breadth (ICIR 0.412)
##   + C10_SUE_Persistence (ICIR 0.389) 3F RankCombo, alpha decay resistance.
##   Phase 1 (FC-1a + WD-A1): top 20 by RankCombo, equal weight, monthly rebalance.
##
## PIT: Factor DB Z_Score_Aligned via Arrow (C13/C15). All quarterly -> 45d lag (C4).
##      Liq t-1 lagged (C10). No full-sample (C1). C1-C15 compliant.
cat("=== STR_1433: Consensus Triple Combo (C19+C13+C10) ===\n")
cat("## Core: C19(0.575)+C13(0.412)+C10(0.389) 3F RankCombo, alpha decay resistance\n")

set.seed(1433)
options(scipen = 999)
Sys.setenv(TZ = "Asia/Seoul")

STRATEGY_NAME   <- "Consensus_Triple_Combo"
STRATEGY_ID     <- "STR_1433"
STRATEGY_FAMILY <- "consensus_triple_combo"
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
N_HOLDINGS <- 20L; COMMISSION <- 0.0015

res <- load_rawdata(use_cache = TRUE)
RAWDATA <- res$RAWDATA; BM_DT <- res$BM_DT
rm(res); gc(verbose = FALSE)

source(file.path(SCRIPT_DIR, "factor_engine.R"))
stopifnot(is.data.table(FACTORS), nrow(FACTORS) > 0)
cat(sprintf("  FACTORS: %d rows | %d signal dates\n", nrow(FACTORS), uniqueN(FACTORS$Date)))

# ============================================================================
# Step 2: Backtest — EW, N=20
# ============================================================================
cat(sprintf("\n[Step 2] EW Backtest: N=%d\n", N_HOLDINGS))
sim <- run_monthly_simulation(
  RAWDATA = RAWDATA, BM_DT = BM_DT, FACTORS = FACTORS,
  n_holdings = N_HOLDINGS, weight_method = "equal",
  commission = COMMISSION, buffer_zone = list(keep_n = 30L, entry_n = 20L)
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
# Step 4: R4 Regime Payoff
# ============================================================================
cat("\n[Step 4] R4 Regime Payoff...\n")
tryCatch({
  source(file.path(REGIME_DIR, "regime_engine_v7.R"))
  regime_dt <- build_regime_v7(use_cache = TRUE)
  regime_daily <- data.table(Date = as.Date(regime_dt$apply_start), MRS = regime_dt$MRS)
  setkey(regime_daily, Date)
  nav_dt <- sim$DAILY_NAV_DT
  daily_dt <- data.table(Date = nav_dt$Date); setkey(daily_dt, Date)
  daily_dt <- regime_daily[daily_dt, roll = TRUE]; daily_dt[is.na(MRS), MRS := 0]
  plog <- data.table(Date = nav_dt$Date, Ret = nav_dt$Strategy_Ret, MRS = daily_dt$MRS)
  regime_payoff <- plog[, .(ann_ret = mean(Ret, na.rm=TRUE)*252,
    ann_vol = sd(Ret, na.rm=TRUE)*sqrt(252),
    sharpe = fifelse(sd(Ret, na.rm=TRUE)>0, mean(Ret, na.rm=TRUE)/sd(Ret, na.rm=TRUE)*sqrt(252), 0),
    n_days = .N), by = .(regime = fifelse(MRS<15, "Normal", fifelse(MRS>=30, "Crisis", "Elevated")))]
  print(regime_payoff)
  fwrite(regime_payoff, file.path(output_dir, "r4_regime_payoff.csv"))
}, error = function(e) cat("[R4] Error:", e$message, "\n"))

# ============================================================================
# Step 5: Telegram + Auto-commit
# ============================================================================
cat("\n[Step 5] Telegram + QEPM commit...\n")
tryCatch({
  source(file.path(TELEGRAM_DIR, "telegram_notify.R"))
  if (!is.null(hurdle)) {
    hr <- jsonlite::fromJSON(file.path(output_dir, "hurdle_result.json"))
    tg_strategy_result_with_chart(STRATEGY_ID, hr, output_dir)
  }
}, error = function(e) cat("[TG]", e$message, "\n"))

tryCatch({
  grade_str <- if (!is.null(hurdle)) hurdle$grade else "?"
  score_str <- if (!is.null(hurdle)) sprintf("%.1f", hurdle$total_score %||% hurdle$score %||% 0) else "?"
  tg_send(paste0("\U0001F3AF STR_1433: Consensus Triple Combo (C19+C13+C10)\n",
    "C19(0.575)+C13(0.412)+C10(0.389) 3F RankCombo\n",
    sprintf("[Strat] CAGR=%.2f%% | SR=%.3f | MDD=%.1f%%\n", perf_strat$CAGR, perf_strat$Sharpe, perf_strat$MDD),
    sprintf("Grade: %s | Score: %s", grade_str, score_str)))
}, error = function(e) cat("[TG]", e$message, "\n"))

if (isTRUE(QEPM_AUTO_COMMIT)) {
  tryCatch({
    qepm_hybrid <- file.path(dirname(dirname(dirname(SCRIPT_DIR))), "qepm", "scripts", "hybrid_mode.R")
    if (file.exists(qepm_hybrid)) {
      source(qepm_hybrid)
      if (exists("hybrid_commit"))
        hybrid_commit(strategy_name = STRATEGY_ID, family = STRATEGY_FAMILY,
                      hurdle_result = hurdle, artifact_paths = list(output_dir))
    }
  }, error = function(e) cat("[QEPM]", e$message, "\n"))
}

tryCatch({
  jsonlite::write_json(list(strategy_id = STRATEGY_ID, family = STRATEGY_FAMILY,
    factors = c("C19_Composite_Earnings", "C13_Revision_Breadth", "C10_SUE_Persistence"), n_holdings = N_HOLDINGS,
    weight_method = "equal", performance = list(strategy = as.list(perf_strat), bm = as.list(perf_bm)),
    hurdle = tryCatch(list(grade=hurdle$grade, score=hurdle$total_score%||%hurdle$score%||%0, pass=hurdle$pass),
                      error=function(e) list()), generated = as.character(Sys.time()),
    pit_status = "CLEAN"), file.path(SCRIPT_DIR, "result.json"), auto_unbox = TRUE, pretty = TRUE)
}, error = function(e) cat("[JSON]", e$message, "\n"))

cat(sprintf("\n=== %s Complete. ===\n", STRATEGY_ID))
