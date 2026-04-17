## ──────────────────────────────────────────────────────────────────────────────
## Multi-Sleeve Portfolio Analysis
## Combines top Grade A strategies to test portfolio-level diversification
## ──────────────────────────────────────────────────────────────────────────────
cat("=== Multi-Sleeve Portfolio Analysis ===\n")

SCRIPT_DIR <- tryCatch({ d <- dirname(sys.frame(1)$ofile); if (d == ".") getwd() else d },
  error = function(e) { args <- commandArgs(trailingOnly = FALSE); file_arg <- grep("--file=", args, value = TRUE)
    if (length(file_arg) > 0) { p <- sub("--file=", "", file_arg[1]); p <- gsub("~+~", " ", p, fixed = TRUE); dirname(p) } else getwd() })
INFRA_DIR <- file.path(dirname(dirname(SCRIPT_DIR)), "02_Infrastructure")
source(file.path(INFRA_DIR, "config.R"))
source(file.path(INFRA_DIR, "backtest_harness.R"))
source(file.path(PORTFOLIO_DIR, "multi_sleeve_builder.R"))
source(file.path(TELEGRAM_DIR, "telegram_notify.R"))

output_dir <- file.path(SCRIPT_DIR, "output")
if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)

# ── Top strategies for multi-sleeve combination ──
# Selected for diversity: different gate families, different base templates
top_strategies <- c(
  "STR_517_cross_all_z2",           # Score 83.0 — CrossAsset best, DaysInv+CVaR gates
  "STR_490_ra_daysinv_cvar_rev42d", # Score 80.0 — RA DaysInv+CVaR triple gate
  "STR_486_ra_cvar_rev42d",         # Score 78.2 — RA CVaR+Rev42d (no DART gate)
  "STR_397_ag_ccc_45_55",           # Score 77.7 — AG+CCC dual, quarterly, different regime
  "STR_316_ccc_gate",               # Score 77.0 — CCC gate, quarterly, simple baseline
  "STR_445_ra_at_rev42",            # Score 70.6 — RA AT+Rev42d (different DART gate)
  "STR_401_ra_days_inv"             # Score 66.3 — RA DaysInv (simple RA)
)

cat(sprintf("\n[multi_sleeve] Analyzing %d strategies...\n", length(top_strategies)))

# ── Step 1: Correlation analysis ──
cat("\n══ Step 1: Correlation Analysis ══\n")
corr <- analyze_sleeve_correlations(top_strategies, freq = "daily")

if (!is.null(corr)) {
  # Save correlation heatmap
  plot_sleeve_correlation(corr, output_dir = output_dir)

  # Save correlation matrix
  corr_dt <- as.data.table(corr$matrix, keep.rownames = "Strategy")
  fwrite(corr_dt, file.path(output_dir, "correlation_matrix.csv"))
  cat(sprintf("\n[multi_sleeve] Avg pairwise corr: %.3f\n", mean(abs(corr$matrix[lower.tri(corr$matrix)]))))
}

# ── Step 2: Compare all combination methods ──
cat("\n══ Step 2: Method Comparison ══\n")
comparison <- compare_combination_methods(top_strategies, rebalance = "monthly")

if (!is.null(comparison)) {
  fwrite(comparison$comparison, file.path(output_dir, "method_comparison.csv"))

  # ── Step 3: Best method equity curve ──
  best_method <- comparison$comparison$Label[which.max(comparison$comparison$Sharpe)]
  best_method_name <- sub("MultiSleeve_", "", best_method)
  cat(sprintf("\n[multi_sleeve] Best method: %s\n", best_method_name))

  if (best_method_name %in% names(comparison$results)) {
    best_result <- comparison$results[[best_method_name]]
    plot_sleeve_equity(best_result, output_dir = output_dir)
    plot_sleeve_weights(best_result, output_dir = output_dir)
    summary <- summarise_multi_sleeve(best_result)
    if (!is.null(summary)) {
      fwrite(summary$combined, file.path(output_dir, "best_combined_perf.csv"))
      fwrite(summary$sleeves, file.path(output_dir, "individual_sleeve_perf.csv"))
    }
  }
}

# ── Step 4: Subset analysis (top 3 only) ──
cat("\n══ Step 3: Top-3 Subset ══\n")
top3 <- top_strategies[1:3]
sub3 <- tryCatch(
  build_multi_sleeve(top3, method = "risk_parity", rebalance = "monthly"),
  error = function(e) { cat(sprintf("[subset] Error: %s\n", e$message)); NULL }
)
if (!is.null(sub3)) {
  sub3_perf <- summarise_multi_sleeve(sub3)
  if (!is.null(sub3_perf)) {
    fwrite(sub3_perf$combined, file.path(output_dir, "top3_riskparity_perf.csv"))
  }
}

# ── Telegram notification ──
if (!is.null(comparison)) {
  best_row <- comparison$comparison[which.max(comparison$comparison$Sharpe)]
  msg <- sprintf(
    "<b>[Multi-Sleeve 분석 완료]</b>\n%d개 전략 조합 테스트\n─────────────\nBest: %s\nCAGR: %.1f%% | Sharpe: %.3f | MDD: %.1f%%\nAvg Corr: %.3f\n─────────────\n%s",
    length(top_strategies),
    best_row$Label,
    best_row$CAGR, best_row$Sharpe, best_row$MDD,
    if (!is.null(corr)) mean(abs(corr$matrix[lower.tri(corr$matrix)])) else NA,
    paste(sprintf("%s: SR=%.3f MDD=%.1f%%",
                  comparison$comparison$Label,
                  comparison$comparison$Sharpe,
                  comparison$comparison$MDD), collapse = "\n")
  )
  tg_send(msg)

  # Send equity curve chart
  eq_path <- file.path(output_dir, "sleeve_equity_curve.png")
  if (file.exists(eq_path)) {
    tg_send_photo(eq_path, caption = "Multi-Sleeve Equity Curve")
  }
  corr_path <- file.path(output_dir, "sleeve_correlation_heatmap.png")
  if (file.exists(corr_path)) {
    tg_send_photo(corr_path, caption = "Sleeve Correlation Heatmap")
  }
}

cat("\n[multi_sleeve] Analysis complete.\n")
