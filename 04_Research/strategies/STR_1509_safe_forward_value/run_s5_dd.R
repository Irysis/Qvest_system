cat("=== STR_1509 S5: DD Brake Overlay — 3 Variants (A/B/C) ===\n")
## 핵심아이디어: MDD 58.1% 개선을 위한 DD brake overlay mutation
## Base: STR_1509 Safe_Forward_Value (V04_fPER + Q13_Fin_Leverage)
## DD brake uses t-1 lag (C9 compliance): dd_lag <- c(0, dd_pct[-n_f])
options(scipen = 999); Sys.setenv(TZ = "Asia/Seoul")

SCRIPT_DIR <- tryCatch({
  d <- dirname(sys.frame(1)$ofile)
  if (d == ".") getwd() else d
}, error = function(e) getwd())
INFRA_DIR <- file.path(SCRIPT_DIR, "..", "..", "..", "02_Infrastructure")
if (!file.exists(file.path(INFRA_DIR, "config.R")))
  INFRA_DIR <- file.path(Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot")), "02_Infrastructure")

source(file.path(INFRA_DIR, "config.R"))
source(file.path(INFRA_DIR, "backtest_harness.R"))
library(data.table); library(xts)

## Load parent sim (pure factor baseline)
sim_parent <- readRDS(file.path(SCRIPT_DIR, "sim_result.rds"))
raw_ret <- as.numeric(sim_parent$strategy_xts)
raw_ret[is.na(raw_ret)] <- 0
raw_dates <- as.Date(index(sim_parent$strategy_xts))
n_f <- length(raw_ret)

## DD brake parameters: 3 variants
variants <- list(
  A = list(seed = 15091L, DD_START = 0.07, DD_FULL = 0.22, DD_MIN_EXP = 0.30,
           label = "S5_ddA", dir_name = "output_s5_ddA"),
  B = list(seed = 15092L, DD_START = 0.10, DD_FULL = 0.25, DD_MIN_EXP = 0.30,
           label = "S5_ddB", dir_name = "output_s5_ddB"),
  C = list(seed = 15093L, DD_START = 0.15, DD_FULL = 0.35, DD_MIN_EXP = 0.30,
           label = "S5_ddC", dir_name = "output_s5_ddC")
)

## Compute DD brake once (same raw returns, same dd_pct/dd_lag for all)
nav_dd <- cumprod(1 + raw_ret)
dd_pct <- 1 - nav_dd / cummax(nav_dd)
## C9: t-1 lag — today's exposure uses YESTERDAY's drawdown
dd_lag <- c(0, dd_pct[-n_f])

results <- list()
for (v_name in names(variants)) {
  v <- variants[[v_name]]
  set.seed(v$seed)
  cat(sprintf("\n--- Variant %s: DD %.0f/%.0f (min_exp=%.0f%%) ---\n",
              v_name, v$DD_START * 100, v$DD_FULL * 100, v$DD_MIN_EXP * 100))

  ## Compute exposure scaling: 100% if dd_lag <= DD_START, MIN_EXP if dd_lag >= DD_FULL, linear in between

  dd_exp <- fifelse(
    dd_lag <= v$DD_START, 1.0,
    fifelse(dd_lag >= v$DD_FULL, v$DD_MIN_EXP,
            pmax(v$DD_MIN_EXP, 1.0 - (dd_lag - v$DD_START) / (v$DD_FULL - v$DD_START) * (1 - v$DD_MIN_EXP)))
  )

  final_ret <- raw_ret * dd_exp
  combined_xts <- xts(final_ret, order.by = raw_dates)
  names(combined_xts) <- "Strategy"

  sim <- sim_parent
  sim$strategy_xts <- combined_xts
  sim$bm_xts <- sim_parent$bm_xts[raw_dates]
  sim$DAILY_NAV_DT <- data.table(
    Date = raw_dates,
    NAV = cumprod(1 + final_ret) * 10000,
    Strategy_Ret = final_ret
  )

  output_dir <- file.path(SCRIPT_DIR, v$dir_name)
  dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

  perf <- summarise_perf(sim$strategy_xts, v$label)
  perf_bm <- summarise_perf(sim$bm_xts, "BM")
  cat(sprintf("  %s: SR=%.3f CAGR=%.2f%% MDD=%.1f%%\n", v$label, perf$Sharpe, perf$CAGR, perf$MDD))

  generate_charts(sim, output_dir = output_dir, strategy_name = v$label)
  fwrite(rbind(perf, perf_bm), file.path(output_dir, "performance.csv"))
  saveRDS(sim, file.path(output_dir, "sim_result.rds"))

  ## Hurdle gate
  source(file.path(INFRA_DIR, "hurdle_gate.R"))
  hurdle <- run_hurdle_gate(
    sim_result = sim,
    strategy_name = v$label,
    output_dir = output_dir
  )
  jsonlite::write_json(hurdle, file.path(output_dir, "hurdle_result.json"),
                       auto_unbox = TRUE, pretty = TRUE)
  cat(sprintf("  Grade: %s | Score: %.1f\n",
              hurdle$grade, hurdle$total_score %||% hurdle$score %||% 0))

  results[[v_name]] <- list(perf = perf, hurdle = hurdle)

  ## Telegram notification
  tryCatch({
    source(file.path(TELEGRAM_DIR, "telegram_notify.R"))
    hr <- jsonlite::fromJSON(file.path(output_dir, "hurdle_result.json"))
    tg_strategy_result_with_chart(
      paste0("STR_1509_", v$label), hr, output_dir
    )
  }, error = function(e) cat("[TG]", e$message, "\n"))
}

## Summary comparison
cat("\n\n========== STR_1509 S5 DD Overlay — Summary ==========\n")
cat(sprintf("%-10s %-7s %-7s %-8s %-8s %-6s\n", "Variant", "Grade", "Score", "SR", "CAGR%", "MDD%"))
for (v_name in names(results)) {
  r <- results[[v_name]]
  cat(sprintf("%-10s %-7s %-7.1f %-8.3f %-8.2f %-6.1f\n",
              v_name, r$hurdle$grade,
              r$hurdle$total_score %||% r$hurdle$score %||% 0,
              r$perf$Sharpe, r$perf$CAGR, r$perf$MDD))
}
cat("======================================================\n")
cat("=== STR_1509 S5 DD Overlay Complete ===\n")
