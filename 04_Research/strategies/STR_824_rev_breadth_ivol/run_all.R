set.seed(42); options(scipen=999); Sys.setenv(TZ="Asia/Seoul")
STRATEGY_NAME <- "RevBreadth_IdioVol"; STRATEGY_ID <- "STR_824"
cat(sprintf("\n=== %s: %s ===\n\n", STRATEGY_ID, STRATEGY_NAME))
SCRIPT_DIR <- tryCatch(dirname(sys.frame(1)$ofile), error = function(e) getwd())
INFRA_DIR  <- file.path(SCRIPT_DIR, "..", "..", "..", "02_Infrastructure")
source(file.path(INFRA_DIR, "config.R"))
source(file.path(INFRA_DIR, "backtest_harness.R"))
source(file.path(TELEGRAM_DIR, "telegram_notify.R"))

res <- load_rawdata(use_cache = TRUE); RAWDATA <- res$RAWDATA; BM_DT <- res$BM_DT
source(file.path(SCRIPT_DIR, "factor_engine.R"))
stopifnot(is.data.table(FACTORS), nrow(FACTORS) > 0)

sim <- run_monthly_simulation(RAWDATA, BM_DT, FACTORS,
  n_holdings = 20, commission = 0.0015, weight_method = "equal",
  vol_target = 0.18, vol_lookback = 60L)

output_dir <- file.path(SCRIPT_DIR, "output")
if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)

perf    <- summarise_perf(sim$strategy_xts, STRATEGY_NAME)
bm_perf <- summarise_perf(sim$bm_xts, "KOSPI200")
print(rbind(perf, bm_perf))

generate_charts(sim, output_dir = output_dir,
                strategy_name = sprintf("%s: %s", STRATEGY_ID, STRATEGY_NAME))
source(file.path(INFRA_DIR, "strategy_analyzer.R"))
run_analysis(sim, FACTORS, RAWDATA, BM_DT, output_dir, strategy_name = STRATEGY_ID)

saveRDS(sim, file.path(SCRIPT_DIR, "sim_result.rds"))
fwrite(rbind(perf, bm_perf), file.path(output_dir, "performance.csv"))

hurdle <- tryCatch({
  QEPM_AUTO_COMMIT <- TRUE
  source(file.path(INFRA_DIR, "hurdle_gate.R"))
  run_hurdle_gate(sim_result = sim, strategy_name = STRATEGY_ID, output_dir = output_dir)
}, error = function(e) { cat("Hurdle error:", e$message, "\n"); NULL })

tryCatch({
  if (!is.null(hurdle)) tg_strategy_result_with_chart(STRATEGY_ID, hurdle, output_dir)
}, error = function(e) cat("TG error:", e$message, "\n"))
cat(sprintf("\n[%s] Complete.\n", STRATEGY_ID))
