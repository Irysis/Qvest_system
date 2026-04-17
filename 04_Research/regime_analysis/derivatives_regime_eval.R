#==============================================================================
# Derivatives Regime KPI Evaluation
# Load 4,225 parquet files (2010-2026), compute regime, evaluate with regime_kpi.R
# Compare with FRED v1/v2 models
#==============================================================================
cat("=== Derivatives Regime KPI Evaluation ===\n")
cat(sprintf("Start: %s\n", Sys.time()))

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(ggplot2)
  library(patchwork)
})

source("02_Infrastructure/config.R")
source("02_Infrastructure/backtest_harness.R")
source("02_Infrastructure/krx_data_collector.R")
source("02_Infrastructure/krx_derivatives_collector.R")
source("02_Infrastructure/regime_derivatives.R")
source("02_Infrastructure/regime_kpi.R")
source("02_Infrastructure/telegram_notify.R")

OUT_DIR <- file.path(PROJECT_ROOT, "research_output", "regime_analysis")
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)

#==============================================================================
# STEP 1: Load and consolidate derivative data from 4,225 parquet files
#==============================================================================
cat("\n=== STEP 1: Load derivative data ===\n")

drv_data <- krx_load_derivatives()
cat(sprintf("  Loaded: %d rows, Date range: %s ~ %s\n",
            nrow(drv_data), min(drv_data$Date), max(drv_data$Date)))
cat("  Columns:", paste(names(drv_data), collapse = ", "), "\n")
cat("\n  Sample (last 3 rows):\n")
print(tail(drv_data, 3))

# Check data completeness per column
cat("\n  Column completeness:\n")
for (col in names(drv_data)) {
  n_valid <- sum(!is.na(drv_data[[col]]))
  pct <- round(n_valid / nrow(drv_data) * 100, 1)
  cat(sprintf("    %s: %d/%d (%.1f%%)\n", col, n_valid, nrow(drv_data), pct))
}

#==============================================================================
# STEP 2: Compute derivatives regime using regime_derivatives.R engine
#==============================================================================
cat("\n=== STEP 2: Compute derivatives regime (ensemble) ===\n")

drv_regime <- drv_ensemble_regime(drv_data)
cat(sprintf("  Regime computed: %d rows\n", nrow(drv_regime)))
cat("  Regime columns:", paste(names(drv_regime), collapse = ", "), "\n")

# Distribution summary
cat("\n  Ensemble regime distribution:\n")
print(drv_regime[, .N, by = Drv_Ensemble_Regime][order(-N)])
cat(sprintf("\n  Ensemble score stats: mean=%.3f, sd=%.3f, min=%.3f, max=%.3f\n",
            mean(drv_regime$Drv_Ensemble_Score, na.rm = TRUE),
            sd(drv_regime$Drv_Ensemble_Score, na.rm = TRUE),
            min(drv_regime$Drv_Ensemble_Score, na.rm = TRUE),
            max(drv_regime$Drv_Ensemble_Score, na.rm = TRUE)))

#==============================================================================
# STEP 3: Load benchmark and prepare monthly returns
#==============================================================================
cat("\n=== STEP 3: Load benchmark ===\n")

res <- load_rawdata(use_cache = TRUE)
bm <- unique(res$BM_DT[, .(Date, BM_Ret)])
setorder(bm, Date)
bm[, YM := format(Date, "%Y-%m")]
bm_m <- bm[, .(Ret = prod(1 + BM_Ret, na.rm = TRUE) - 1), by = YM]
bm_m[, Date := as.Date(cut(as.Date(paste0(YM, "-01")) + 31, "month")) - 1]
setorder(bm_m, Date)
cat(sprintf("  Benchmark monthly: %d months (%s ~ %s)\n",
            nrow(bm_m), min(bm_m$Date), max(bm_m$Date)))

#==============================================================================
# STEP 4: Create monthly regime signals for KPI evaluation
#==============================================================================
cat("\n=== STEP 4: Create monthly regime signals ===\n")

drv_regime[, YM := format(Date, "%Y-%m")]

# Monthly aggregation: use end-of-month values (last available date per month)
drv_monthly <- drv_regime[, {
  idx <- .N  # last row = end of month
  list(
    Ensemble_Score_EoM = Drv_Ensemble_Score[idx],
    Ensemble_Regime_EoM = Drv_Ensemble_Regime[idx],
    N_Votes_EoM = Drv_N_Votes[idx],
    VKOSPI_EoM = VKOSPI_raw[idx],
    VKOSPI_regime_EoM = VKOSPI_regime[idx],
    PCR_EoM = PCR_raw[idx],
    Basis_EoM = Basis_Pct_raw[idx],
    # Monthly averages for robustness
    Ensemble_Score_Avg = mean(Drv_Ensemble_Score, na.rm = TRUE),
    VKOSPI_Avg = mean(VKOSPI_raw, na.rm = TRUE),
    # Fraction of days in risk-off
    RiskOff_Frac = mean(Drv_Ensemble_Regime == "risk_off", na.rm = TRUE),
    N_Days = .N
  )
}, by = YM]
setorder(drv_monthly, YM)
cat(sprintf("  Monthly derivative signals: %d months\n", nrow(drv_monthly)))

# Create KPI-compatible signal:
# Map ensemble score to Action: risk_off -> SKIP, euphoria_warning -> HALF, normal -> FULL
# Use end-of-month regime for next month's action (lag-1 to avoid look-ahead)
drv_monthly[, Action := fifelse(
  Ensemble_Regime_EoM == "risk_off", "SKIP",
  fifelse(Ensemble_Regime_EoM == "euphoria_warning", "HALF", "FULL")
)]

# Also create score on 0-100 scale (higher = riskier, same direction as FRED)
drv_monthly[, Score := fifelse(
  is.na(Ensemble_Score_EoM), 0,
  pmin(100, pmax(0, (-Ensemble_Score_EoM + 1) * 50))
)]

# Lag the signal by 1 month (use this month's regime for next month's action)
drv_monthly[, Action_Lagged := shift(Action, 1, type = "lag")]
drv_monthly[, Score_Lagged := shift(Score, 1, type = "lag")]
drv_monthly[is.na(Action_Lagged), Action_Lagged := "FULL"]
drv_monthly[is.na(Score_Lagged), Score_Lagged := 0]

# Create Date column matching bm_m format
drv_monthly[, Date := as.Date(cut(as.Date(paste0(YM, "-01")) + 31, "month")) - 1]

# DRV signal (lagged, no look-ahead)
drv_signal <- drv_monthly[, .(Date, Score = Score_Lagged, Action = Action_Lagged)]

# DRV signal (same-month, for comparison — has look-ahead)
drv_signal_contemp <- drv_monthly[, .(Date, Score, Action)]

cat("  DRV signal distribution (lagged):\n")
print(drv_signal[, .N, by = Action])

#==============================================================================
# STEP 4b: Alternative DRV signals — VKOSPI-only + composite score
#==============================================================================

# VKOSPI-only regime (use VKOSPI > 25 as alert)
drv_monthly[, VKOSPI_Action := fifelse(
  VKOSPI_EoM > 30, "SKIP",
  fifelse(VKOSPI_EoM > 20, "HALF", "FULL")
)]
drv_monthly[, VKOSPI_Action_Lag := shift(VKOSPI_Action, 1, type = "lag")]
drv_monthly[is.na(VKOSPI_Action_Lag), VKOSPI_Action_Lag := "FULL"]
drv_monthly[, VKOSPI_Score := fifelse(is.na(VKOSPI_EoM), 0,
  pmin(100, pmax(0, (VKOSPI_EoM - 10) * 100 / 30)))]
drv_monthly[, VKOSPI_Score_Lag := shift(VKOSPI_Score, 1, type = "lag")]
drv_monthly[is.na(VKOSPI_Score_Lag), VKOSPI_Score_Lag := 0]

vkospi_signal <- drv_monthly[, .(Date, Score = VKOSPI_Score_Lag, Action = VKOSPI_Action_Lag)]

# Risk-off fraction > 50% of days in month
drv_monthly[, Frac_Action := fifelse(
  RiskOff_Frac > 0.5, "SKIP",
  fifelse(RiskOff_Frac > 0.2, "HALF", "FULL")
)]
drv_monthly[, Frac_Action_Lag := shift(Frac_Action, 1, type = "lag")]
drv_monthly[is.na(Frac_Action_Lag), Frac_Action_Lag := "FULL"]
drv_monthly[, Frac_Score := pmin(100, RiskOff_Frac * 100)]
drv_monthly[, Frac_Score_Lag := shift(Frac_Score, 1, type = "lag")]
drv_monthly[is.na(Frac_Score_Lag), Frac_Score_Lag := 0]

frac_signal <- drv_monthly[, .(Date, Score = Frac_Score_Lag, Action = Frac_Action_Lag)]

#==============================================================================
# STEP 5: Load FRED regime and create v1/v2 signals (from existing eval)
#==============================================================================
cat("\n=== STEP 5: Load FRED regime (v1/v2) ===\n")

regime <- as.data.table(read_parquet(FRED_REGIME_CACHE))
regime[, Date := as.Date(Date)]
setorder(regime, Date)

# Reconstruct v1 scores (4-axis)
regime[, v1_score := 0L]
if ("VIX_Regime" %in% names(regime))
  regime[, v1_score := v1_score + fifelse(!is.na(VIX_Regime) & VIX_Regime == "crisis", 30L,
    fifelse(!is.na(VIX_Regime) & VIX_Regime == "elevated", 15L, 0L))]
if ("YC_Inversion" %in% names(regime))
  regime[, v1_score := v1_score + fifelse(!is.na(YC_Inversion) & YC_Inversion, 25L, 0L)]
if ("Credit_Stress" %in% names(regime))
  regime[, v1_score := v1_score + fifelse(!is.na(Credit_Stress) & Credit_Stress, 25L, 0L)]
if ("KRW_Stress" %in% names(regime))
  regime[, v1_score := v1_score + fifelse(!is.na(KRW_Stress) & KRW_Stress, 20L, 0L)]

# v1 signal (H15/S30)
v1_signal <- regime[, .(Date, Score = v1_score)]
v1_signal[, Action := fifelse(Score >= 30, "SKIP", fifelse(Score >= 15, "HALF", "FULL"))]

# v2 signal (9-axis, H10/S40) — current production
v2_signal <- regime[, .(Date, Score = Macro_Risk_Score)]
v2_signal[, Action := fifelse(Score >= 40, "SKIP", fifelse(Score >= 10, "HALF", "FULL"))]

# v2 with v1 thresholds (H15/S30) for fair comparison
v2_v1thresh <- regime[, .(Date, Score = Macro_Risk_Score)]
v2_v1thresh[, Action := fifelse(Score >= 30, "SKIP", fifelse(Score >= 15, "HALF", "FULL"))]

cat(sprintf("  FRED regime: %d months (%s ~ %s)\n",
            nrow(regime), min(regime$Date), max(regime$Date)))

#==============================================================================
# STEP 6: Evaluate ALL models with regime_kpi.R
#==============================================================================
cat("\n=== STEP 6: KPI Evaluation (SIR + DAS) ===\n")

# Build models list
models <- list(
  FRED_v1_H15S30     = v1_signal,
  FRED_v2_H10S40     = v2_signal,
  FRED_v2_H15S30     = v2_v1thresh,
  DRV_Ensemble       = drv_signal,
  DRV_VKOSPI_Only    = vkospi_signal,
  DRV_RiskOff_Frac   = frac_signal
)

# Run comparison
compare <- regime_compare(models, bm_m)
comp_dt <- compare$comparison_dt

cat("\n\n╔══════════════════════════════════════════════════════════════╗\n")
cat("║        REGIME MODEL COMPARISON — SIR & DAS                  ║\n")
cat("╠══════════════════════════════════════════════════════════════╣\n")
print(comp_dt[, .(Model, SR_Benchmark, SR_Regime, SIR, DAS,
                  N_Crisis, N_Skipped, CAGR_BM, CAGR_Regime)])
cat("╚══════════════════════════════════════════════════════════════╝\n")

# Save comparison table
write.csv(comp_dt, file.path(OUT_DIR, "drv_regime_kpi_comparison.csv"), row.names = FALSE)

#==============================================================================
# STEP 7: Generate charts for each model
#==============================================================================
cat("\n=== STEP 7: Generate charts ===\n")

for (nm in names(compare$eval_list)) {
  ev <- compare$eval_list[[nm]]
  tryCatch({
    regime_kpi_chart(ev, OUT_DIR)
    cat(sprintf("  Chart saved: %s\n", nm))
  }, error = function(e) cat(sprintf("  Chart error (%s): %s\n", nm, e$message)))
}

#==============================================================================
# STEP 7b: Combined comparison chart
#==============================================================================
cat("\n=== STEP 7b: Combined comparison chart ===\n")

tryCatch({
  # Panel 1: SIR comparison bar chart
  sir_dt <- comp_dt[, .(Model, SIR)]
  sir_dt[, Model_short := gsub("_", "\n", Model)]
  sir_dt[, Color := fifelse(grepl("DRV", Model), "Derivatives", "FRED")]

  p_sir <- ggplot(sir_dt, aes(x = reorder(Model_short, -SIR), y = SIR, fill = Color)) +
    geom_col(alpha = 0.8) +
    geom_hline(yintercept = 1.0, linetype = "dashed", color = "red", linewidth = 0.5) +
    geom_text(aes(label = sprintf("%.3f", SIR)), vjust = -0.5, size = 3.5) +
    scale_fill_manual(values = c("FRED" = "#2171B5", "Derivatives" = "#D6604D")) +
    labs(title = "KPI-A: Sharpe Improvement Ratio (SIR)",
         subtitle = "SIR > 1 = regime model improves Sharpe vs buy-and-hold",
         x = NULL, y = "SIR", fill = "Source") +
    theme_minimal(base_size = 11) +
    theme(axis.text.x = element_text(size = 8))

  # Panel 2: DAS comparison
  das_dt <- comp_dt[, .(Model, DAS)]
  das_dt[, Model_short := gsub("_", "\n", Model)]
  das_dt[, Color := fifelse(grepl("DRV", Model), "Derivatives", "FRED")]

  p_das <- ggplot(das_dt, aes(x = reorder(Model_short, -DAS), y = DAS, fill = Color)) +
    geom_col(alpha = 0.8) +
    geom_text(aes(label = sprintf("%.1f", DAS)), vjust = -0.5, size = 3.5) +
    scale_fill_manual(values = c("FRED" = "#2171B5", "Derivatives" = "#D6604D")) +
    labs(title = "KPI-B: Drawdown Avoidance Score (DAS)",
         subtitle = "0-100 scale: fraction of crisis severity avoided",
         x = NULL, y = "DAS", fill = "Source") +
    theme_minimal(base_size = 11) +
    theme(axis.text.x = element_text(size = 8))

  # Panel 3: Cumulative returns overlay (top 3 models + benchmark)
  # Prepare data
  top_models <- comp_dt$Model[1:min(4, nrow(comp_dt))]
  cum_list <- list()
  for (nm in top_models) {
    ev <- compare$eval_list[[nm]]
    dt <- copy(ev$monthly_dt)
    dt[, CumReg := cumprod(1 + Ret_regime)]
    cum_list[[nm]] <- dt[, .(Date, Growth = CumReg, Series = nm)]
  }
  # Add benchmark
  bm_cum <- compare$eval_list[[1]]$monthly_dt
  bm_cum[, CumBM := cumprod(1 + Ret)]
  cum_list[["Benchmark"]] <- bm_cum[, .(Date, Growth = CumBM, Series = "Benchmark")]

  cum_all <- rbindlist(cum_list)
  cum_all[, Series := factor(Series, levels = c("Benchmark", top_models))]

  p_cum <- ggplot(cum_all, aes(x = Date, y = Growth, color = Series)) +
    geom_line(linewidth = 0.7) +
    scale_color_manual(values = c("Benchmark" = "grey50",
                                   setNames(scales::hue_pal()(length(top_models)), top_models))) +
    labs(title = "Cumulative Growth: Top Models vs Benchmark",
         x = NULL, y = "Growth of 1") +
    theme_minimal(base_size = 11) +
    theme(legend.position = "bottom", legend.title = element_blank(),
          legend.text = element_text(size = 7))

  # Panel 4: CAGR comparison
  cagr_dt <- comp_dt[, .(Model, CAGR_BM, CAGR_Regime)]
  cagr_long <- melt(cagr_dt, id.vars = "Model",
                     variable.name = "Type", value.name = "CAGR")
  cagr_long[, Model_short := gsub("_", "\n", Model)]

  p_cagr <- ggplot(cagr_long, aes(x = Model_short, y = CAGR, fill = Type)) +
    geom_col(position = "dodge", alpha = 0.8) +
    scale_fill_manual(values = c("CAGR_BM" = "grey60", "CAGR_Regime" = "#41AB5D"),
                      labels = c("Buy & Hold", "Regime-Adjusted")) +
    labs(title = "CAGR: Regime-Adjusted vs Buy-and-Hold",
         x = NULL, y = "CAGR (%)", fill = NULL) +
    theme_minimal(base_size = 11) +
    theme(axis.text.x = element_text(size = 8), legend.position = "bottom")

  # Combine all panels
  combined <- (p_sir | p_das) / (p_cum | p_cagr) +
    plot_annotation(
      title = "Derivatives vs FRED Regime Model Comparison",
      subtitle = sprintf("Period: %s ~ %s | %d models compared",
                          comp_dt$Period_Start[1], comp_dt$Period_End[1], nrow(comp_dt)),
      theme = theme(plot.title = element_text(face = "bold", size = 14))
    )

  chart_path <- file.path(OUT_DIR, "drv_vs_fred_comparison.png")
  ggsave(chart_path, combined, width = 16, height = 11, dpi = 150, bg = "white")
  cat(sprintf("  Combined chart saved: %s\n", chart_path))
}, error = function(e) cat(sprintf("  Combined chart error: %s\n", e$message)))

#==============================================================================
# STEP 8: Detailed crisis-by-crisis breakdown
#==============================================================================
cat("\n=== STEP 8: Crisis-by-crisis breakdown ===\n")

for (nm in names(compare$eval_list)) {
  ev <- compare$eval_list[[nm]]
  cb <- ev$crisis_by_name
  if (nrow(cb) > 0) {
    cat(sprintf("\n  --- %s ---\n", nm))
    print(cb[, .(Crisis, N_months, Total_Drop = round(Total_Drop * 100, 1),
                 Avoidance_Pct = round(Avoidance_Pct, 1))])
  }
}

#==============================================================================
# STEP 9: Telegram summary
#==============================================================================
cat("\n=== STEP 9: Telegram summary ===\n")

# Build telegram message
best_sir <- comp_dt[which.max(SIR)]
best_das <- comp_dt[which.max(DAS)]

tg_lines <- c(
  "<b>[Regime KPI] Derivatives vs FRED Comparison</b>",
  sprintf("Period: %s ~ %s", comp_dt$Period_Start[1], comp_dt$Period_End[1]),
  "",
  "<b>Model Rankings (SIR):</b>"
)
for (i in seq_len(nrow(comp_dt))) {
  r <- comp_dt[i]
  marker <- ""
  if (r$SIR == best_sir$SIR) marker <- " [BEST SIR]"
  if (r$DAS == best_das$DAS) marker <- paste0(marker, " [BEST DAS]")
  tg_lines <- c(tg_lines, sprintf("  %d. %s: SIR=%.3f, DAS=%.1f, CAGR=%.1f%%%s",
                                    i, r$Model, r$SIR, r$DAS, r$CAGR_Regime, marker))
}
tg_lines <- c(tg_lines, "",
  sprintf("<b>Best SIR:</b> %s (%.3f)", best_sir$Model, best_sir$SIR),
  sprintf("<b>Best DAS:</b> %s (%.1f)", best_das$Model, best_das$DAS),
  "",
  "Charts saved to regime_analysis/"
)

tg_msg <- paste(tg_lines, collapse = "\n")
cat(tg_msg, "\n")

# Send via telegram
tryCatch({
  tg_send(tg_msg, parse_mode = "HTML")
  cat("  Telegram sent.\n")
}, error = function(e) cat(sprintf("  Telegram error: %s\n", e$message)))

# Send chart
tryCatch({
  chart_path <- file.path(OUT_DIR, "drv_vs_fred_comparison.png")
  if (file.exists(chart_path)) {
    tg_send_photo(chart_path, caption = "Derivatives vs FRED Regime Comparison")
    cat("  Chart sent via telegram.\n")
  }
}, error = function(e) cat(sprintf("  Chart telegram error: %s\n", e$message)))

#==============================================================================
# FINAL: Print summary
#==============================================================================
cat("\n\n")
cat("╔══════════════════════════════════════════════════════════════╗\n")
cat("║              FINAL RESULTS SUMMARY                          ║\n")
cat("╠══════════════════════════════════════════════════════════════╣\n")
cat(sprintf("║ Derivative data: %d days (%s ~ %s)\n",
            nrow(drv_data), min(drv_data$Date), max(drv_data$Date)))
cat(sprintf("║ Models compared: %d\n", nrow(comp_dt)))
cat("║\n")
for (i in seq_len(nrow(comp_dt))) {
  r <- comp_dt[i]
  cat(sprintf("║ %-20s  SIR=%.3f  DAS=%5.1f  CAGR=%5.1f%%  SR=%.3f\n",
              r$Model, r$SIR, r$DAS, r$CAGR_Regime, r$SR_Regime))
}
cat("║\n")
cat(sprintf("║ Best SIR:  %s (%.3f)\n", best_sir$Model, best_sir$SIR))
cat(sprintf("║ Best DAS:  %s (%.1f)\n", best_das$Model, best_das$DAS))
cat("╚══════════════════════════════════════════════════════════════╝\n")

cat(sprintf("\nEnd: %s\n", Sys.time()))
cat("=== Derivatives Regime KPI Evaluation Complete ===\n")
