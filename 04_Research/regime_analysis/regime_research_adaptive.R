#==============================================================================
# Regime Research: 3 Adaptive Models vs FRED v2 Baseline
#
# Model 1: Z-Score Adaptive Regime (rolling z-scores instead of fixed thresholds)
# Model 2: Regime Transition Detection (rate-of-change, not level)
# Model 3: FRED-Conditional DRV Override (FRED primary + DRV extreme override)
#
# Baseline: FRED v2 (H10/S40) — SIR=1.384, DAS=43.9
# Target: Beat FRED v2 on SIR and/or DAS
#==============================================================================
cat("=== Regime Research: 3 Adaptive Models ===\n")
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
# STEP 1: Load derivative data (4,225 parquet files)
#==============================================================================
cat("\n=== STEP 1: Load derivative data ===\n")

drv_dir <- file.path(CACHE_DIR, "krx_derivatives")
files <- list.files(drv_dir, pattern = "\\.parquet$", full.names = TRUE)
all_drv <- rbindlist(lapply(files, function(f) {
  tryCatch(as.data.table(read_parquet(f)), error = function(e) NULL)
}), fill = TRUE)

# Parse Date
all_drv[, Date := as.Date(Date, format = "%Y%m%d")]
setorder(all_drv, Date)

cat(sprintf("  Loaded: %d rows, Date range: %s ~ %s\n",
            nrow(all_drv), min(all_drv$Date), max(all_drv$Date)))
cat("  Columns:", paste(names(all_drv), collapse = ", "), "\n")

# Column completeness
cat("\n  Column completeness:\n")
for (col in names(all_drv)) {
  n_valid <- sum(!is.na(all_drv[[col]]))
  pct <- round(n_valid / nrow(all_drv) * 100, 1)
  cat(sprintf("    %s: %d/%d (%.1f%%)\n", col, n_valid, nrow(all_drv), pct))
}

#==============================================================================
# STEP 2: Load FRED regime (baseline)
#==============================================================================
cat("\n=== STEP 2: Load FRED regime ===\n")

fred <- as.data.table(read_parquet(FRED_REGIME_CACHE))
fred[, Date := as.Date(Date)]
setorder(fred, Date)
cat(sprintf("  FRED regime: %d months (%s ~ %s)\n",
            nrow(fred), min(fred$Date), max(fred$Date)))

# FRED v2 baseline signal (H10/S40) — what we need to beat
fred_v2_signal <- fred[, .(Date, Score = Macro_Risk_Score)]
fred_v2_signal[, Action := fifelse(Score >= 40, "SKIP",
                                    fifelse(Score >= 10, "HALF", "FULL"))]
cat("  FRED v2 (H10/S40) action distribution:\n")
print(fred_v2_signal[, .N, by = Action])

#==============================================================================
# STEP 3: Load benchmark monthly returns
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
# MODEL 1: Z-Score Adaptive Regime
# Instead of fixed thresholds, use rolling 252d z-scores for each indicator.
# Adapts to structural shifts (e.g., VKOSPI structurally higher after COVID).
#
# z > 1.5 → SKIP, z > 0.5 → HALF, else FULL
#==============================================================================
cat("\n=== MODEL 1: Z-Score Adaptive Regime ===\n")

drv1 <- copy(all_drv)
setorder(drv1, Date)

# Rolling 252-day z-scores for each available indicator
lookback <- 252L

# VKOSPI z-score
if ("VKOSPI" %in% names(drv1)) {
  drv1[, VKOSPI_mean252 := frollmean(VKOSPI, n = lookback, align = "right", na.rm = TRUE)]
  drv1[, VKOSPI_sd252 := frollapply(VKOSPI, N = lookback, FUN = sd, na.rm = TRUE)]
  drv1[, VKOSPI_z := fifelse(
    !is.na(VKOSPI_sd252) & VKOSPI_sd252 > 1e-8,
    (VKOSPI - VKOSPI_mean252) / VKOSPI_sd252,
    NA_real_
  )]
  cat(sprintf("  VKOSPI z-score: %d valid values\n", sum(!is.na(drv1$VKOSPI_z))))
}

# PCR z-score (use PCR_Vol or PCR_OI)
pcr_col <- intersect(c("PCR_Vol", "PCR_OI"), names(drv1))[1]
if (!is.na(pcr_col)) {
  drv1[, PCR_val := get(pcr_col)]
  drv1[, PCR_mean252 := frollmean(PCR_val, n = lookback, align = "right", na.rm = TRUE)]
  drv1[, PCR_sd252 := frollapply(PCR_val, N = lookback, FUN = sd, na.rm = TRUE)]
  drv1[, PCR_z := fifelse(
    !is.na(PCR_sd252) & PCR_sd252 > 1e-8,
    (PCR_val - PCR_mean252) / PCR_sd252,
    NA_real_
  )]
  cat(sprintf("  PCR z-score (%s): %d valid values\n", pcr_col, sum(!is.na(drv1$PCR_z))))
}

# Basis z-score
if ("K200_Basis_Pct" %in% names(drv1)) {
  # Invert: negative basis = stress, so we negate for z (positive z = more stress)
  drv1[, Basis_neg := -K200_Basis_Pct]
  drv1[, Basis_mean252 := frollmean(Basis_neg, n = lookback, align = "right", na.rm = TRUE)]
  drv1[, Basis_sd252 := frollapply(Basis_neg, N = lookback, FUN = sd, na.rm = TRUE)]
  drv1[, Basis_z := fifelse(
    !is.na(Basis_sd252) & Basis_sd252 > 1e-8,
    (Basis_neg - Basis_mean252) / Basis_sd252,
    NA_real_
  )]
  cat(sprintf("  Basis z-score: %d valid values\n", sum(!is.na(drv1$Basis_z))))
}

# Skew z-score
if ("IV_Skew" %in% names(drv1)) {
  drv1[, Skew_mean252 := frollmean(IV_Skew, n = lookback, align = "right", na.rm = TRUE)]
  drv1[, Skew_sd252 := frollapply(IV_Skew, N = lookback, FUN = sd, na.rm = TRUE)]
  drv1[, Skew_z := fifelse(
    !is.na(Skew_sd252) & Skew_sd252 > 1e-8,
    (IV_Skew - Skew_mean252) / Skew_sd252,
    NA_real_
  )]
  cat(sprintf("  Skew z-score: %d valid values\n", sum(!is.na(drv1$Skew_z))))
}

# Ensemble z-score = mean of available z-scores
z_cols <- intersect(c("VKOSPI_z", "PCR_z", "Basis_z", "Skew_z"), names(drv1))
cat(sprintf("  Z-score columns available: %s\n", paste(z_cols, collapse = ", ")))

drv1[, Ensemble_z := {
  row_z <- numeric(.N)
  for (i in seq_len(.N)) {
    vals <- sapply(z_cols, function(cc) .SD[[cc]][i])
    valid <- vals[!is.na(vals)]
    row_z[i] <- if (length(valid) > 0) mean(valid) else NA_real_
  }
  row_z
}, .SDcols = z_cols]

drv1[, N_z := rowSums(!is.na(.SD)), .SDcols = z_cols]

cat(sprintf("  Ensemble z: %d valid, mean=%.3f, sd=%.3f\n",
            sum(!is.na(drv1$Ensemble_z)),
            mean(drv1$Ensemble_z, na.rm = TRUE),
            sd(drv1$Ensemble_z, na.rm = TRUE)))

# Monthly aggregation: end-of-month ensemble z
drv1[, YM := format(Date, "%Y-%m")]
m1 <- drv1[!is.na(Ensemble_z), {
  idx <- .N  # last day of month
  list(
    Ensemble_z_EoM = Ensemble_z[idx],
    N_z_EoM = N_z[idx],
    # Also monthly average for robustness
    Ensemble_z_Avg = mean(Ensemble_z, na.rm = TRUE)
  )
}, by = YM]
setorder(m1, YM)

# Action: z > 1.5 → SKIP, z > 0.5 → HALF, else FULL
m1[, Action := fifelse(Ensemble_z_EoM > 1.5, "SKIP",
                        fifelse(Ensemble_z_EoM > 0.5, "HALF", "FULL"))]
m1[, Score := round(pmin(100, pmax(0, Ensemble_z_EoM * 25 + 50)), 1)]  # map z to 0-100

# Lag by 1 month (no look-ahead)
m1[, Action_Lag := shift(Action, 1, type = "lag")]
m1[, Score_Lag := shift(Score, 1, type = "lag")]
m1[is.na(Action_Lag), Action_Lag := "FULL"]
m1[is.na(Score_Lag), Score_Lag := 0]

m1[, Date := as.Date(cut(as.Date(paste0(YM, "-01")) + 31, "month")) - 1]
signal_m1 <- m1[, .(Date, Score = Score_Lag, Action = Action_Lag)]

cat("  Model 1 signal distribution:\n")
print(signal_m1[, .N, by = Action])


#==============================================================================
# MODEL 2: Regime Transition Detection
# Instead of level, detect CHANGES (delta-5d) in each indicator.
# Rapid simultaneous deterioration = regime transition signal.
#
# 3+ indicators worsening → SKIP, 2 → HALF, 0-1 → FULL
#==============================================================================
cat("\n=== MODEL 2: Regime Transition Detection ===\n")

drv2 <- copy(all_drv)
setorder(drv2, Date)

delta_lag <- 5L

# VKOSPI delta (rising = deterioration)
if ("VKOSPI" %in% names(drv2)) {
  drv2[, VKOSPI_delta := VKOSPI - shift(VKOSPI, delta_lag)]
  drv2[, VKOSPI_worsening := fifelse(!is.na(VKOSPI_delta) & VKOSPI_delta > 2.0, 1L, 0L)]
  cat(sprintf("  VKOSPI delta: %d worsening signals (>2.0 in 5d)\n",
              sum(drv2$VKOSPI_worsening, na.rm = TRUE)))
}

# PCR delta (rising = more fear/stress)
if (!is.na(pcr_col) && pcr_col %in% names(drv2)) {
  drv2[, PCR_delta := get(pcr_col) - shift(get(pcr_col), delta_lag)]
  # Use rolling sd to normalize — adaptive threshold
  drv2[, PCR_delta_sd := frollapply(PCR_delta, N = 60, FUN = sd, na.rm = TRUE)]
  drv2[, PCR_worsening := fifelse(
    !is.na(PCR_delta) & !is.na(PCR_delta_sd) & PCR_delta_sd > 1e-8 &
      PCR_delta / PCR_delta_sd > 1.5, 1L, 0L)]
  cat(sprintf("  PCR delta: %d worsening signals (z>1.5 in 5d)\n",
              sum(drv2$PCR_worsening, na.rm = TRUE)))
}

# Basis delta (falling = deterioration, so negate)
if ("K200_Basis_Pct" %in% names(drv2)) {
  drv2[, Basis_delta := -(K200_Basis_Pct - shift(K200_Basis_Pct, delta_lag))]
  drv2[, Basis_delta_sd := frollapply(Basis_delta, N = 60, FUN = sd, na.rm = TRUE)]
  drv2[, Basis_worsening := fifelse(
    !is.na(Basis_delta) & !is.na(Basis_delta_sd) & Basis_delta_sd > 1e-8 &
      Basis_delta / Basis_delta_sd > 1.5, 1L, 0L)]
  cat(sprintf("  Basis delta: %d worsening signals (z>1.5 in 5d)\n",
              sum(drv2$Basis_worsening, na.rm = TRUE)))
}

# Skew delta (rising = more tail fear)
if ("IV_Skew" %in% names(drv2)) {
  drv2[, Skew_delta := IV_Skew - shift(IV_Skew, delta_lag)]
  drv2[, Skew_delta_sd := frollapply(Skew_delta, N = 60, FUN = sd, na.rm = TRUE)]
  drv2[, Skew_worsening := fifelse(
    !is.na(Skew_delta) & !is.na(Skew_delta_sd) & Skew_delta_sd > 1e-8 &
      Skew_delta / Skew_delta_sd > 1.5, 1L, 0L)]
  cat(sprintf("  Skew delta: %d worsening signals (z>1.5 in 5d)\n",
              sum(drv2$Skew_worsening, na.rm = TRUE)))
}

# Count simultaneous deteriorations
w_cols <- intersect(c("VKOSPI_worsening", "PCR_worsening", "Basis_worsening", "Skew_worsening"),
                     names(drv2))
drv2[, N_worsening := rowSums(.SD, na.rm = TRUE), .SDcols = w_cols]

cat(sprintf("  N_worsening distribution:\n"))
print(drv2[, .N, by = N_worsening][order(N_worsening)])

# Monthly aggregation: max N_worsening within month
drv2[, YM := format(Date, "%Y-%m")]
m2 <- drv2[, {
  list(
    Max_Worsening = max(N_worsening, na.rm = TRUE),
    Mean_Worsening = mean(N_worsening, na.rm = TRUE),
    Days_Alert = sum(N_worsening >= 2, na.rm = TRUE),
    N_Days = .N
  )
}, by = YM]
setorder(m2, YM)

# Use max worsening count for action
# 3+ → SKIP, 2 → HALF, 0-1 → FULL
m2[, Action := fifelse(Max_Worsening >= 3, "SKIP",
                        fifelse(Max_Worsening >= 2, "HALF", "FULL"))]
m2[, Score := round(pmin(100, Max_Worsening * 25), 1)]

# Lag by 1 month
m2[, Action_Lag := shift(Action, 1, type = "lag")]
m2[, Score_Lag := shift(Score, 1, type = "lag")]
m2[is.na(Action_Lag), Action_Lag := "FULL"]
m2[is.na(Score_Lag), Score_Lag := 0]

m2[, Date := as.Date(cut(as.Date(paste0(YM, "-01")) + 31, "month")) - 1]
signal_m2 <- m2[, .(Date, Score = Score_Lag, Action = Action_Lag)]

cat("  Model 2 signal distribution:\n")
print(signal_m2[, .N, by = Action])


#==============================================================================
# MODEL 3: FRED-Conditional DRV Override
# FRED v2 as primary. DRV z-score overrides ONLY when extreme and FRED disagrees.
#
# - FRED=FULL but DRV z > 2.0 (extreme stress) → upgrade to HALF
# - FRED=HALF but DRV z < -1.0 (all clear) → downgrade to FULL
# - Otherwise keep FRED decision
#
# This preserves FRED's strength (high SIR) while using DRV as safety net.
#==============================================================================
cat("\n=== MODEL 3: FRED-Conditional DRV Override ===\n")

# Get DRV z-score monthly (from Model 1 computation)
# Already have m1 with Ensemble_z_EoM
drv_z_monthly <- m1[, .(YM, DRV_z = Ensemble_z_EoM)]

# Get FRED v2 signal
fred_m3 <- copy(fred_v2_signal)
fred_m3[, YM := format(Date, "%Y-%m")]

# Merge FRED + DRV z
m3 <- merge(fred_m3, drv_z_monthly, by = "YM", all.x = TRUE)
setorder(m3, Date)

# Lag DRV z by 1 month (avoid look-ahead on DRV side)
# FRED is already monthly, but DRV z uses daily data within the month
m3[, DRV_z_Lag := shift(DRV_z, 1, type = "lag")]

# Override logic:
# Start with FRED Action, then conditionally modify
m3[, Override_Action := Action]

# Override 1: FRED says FULL but DRV extreme stress → HALF
m3[Action == "FULL" & !is.na(DRV_z_Lag) & DRV_z_Lag > 2.0,
   Override_Action := "HALF"]

# Override 2: FRED says HALF but DRV all-clear → FULL
m3[Action == "HALF" & !is.na(DRV_z_Lag) & DRV_z_Lag < -1.0,
   Override_Action := "FULL"]

# Count overrides
n_up <- m3[Action == "FULL" & Override_Action == "HALF", .N]
n_down <- m3[Action == "HALF" & Override_Action == "FULL", .N]
cat(sprintf("  Overrides: FULL→HALF (DRV stress): %d, HALF→FULL (DRV clear): %d\n",
            n_up, n_down))

m3[, Override_Score := Score]  # keep FRED score for display

signal_m3 <- m3[, .(Date, Score = Override_Score, Action = Override_Action)]

cat("  Model 3 signal distribution:\n")
print(signal_m3[, .N, by = Action])

# Also show original FRED for comparison
cat("  Original FRED v2 distribution:\n")
print(fred_v2_signal[, .N, by = Action])


#==============================================================================
# STEP 6: Evaluate ALL models with regime_kpi.R
#==============================================================================
cat("\n=== STEP 6: KPI Evaluation ===\n")

models <- list(
  FRED_v2_H10S40       = fred_v2_signal,
  M1_ZScore_Adaptive   = signal_m1,
  M2_Transition_Detect = signal_m2,
  M3_FRED_DRV_Override = signal_m3
)

# Run comparison
compare <- regime_compare(models, bm_m)
comp_dt <- compare$comparison_dt

cat("\n\n")
cat("================================================================\n")
cat("      REGIME MODEL COMPARISON — 3 New Models vs FRED v2        \n")
cat("================================================================\n")
print(comp_dt[, .(Model, SR_Benchmark, SR_Regime, SIR, DAS,
                  N_Crisis, N_Skipped, N_Halved, CAGR_BM, CAGR_Regime)])
cat("================================================================\n")

# Highlight winners
best_sir <- comp_dt[which.max(SIR)]
best_das <- comp_dt[which.max(DAS)]
fred_sir <- comp_dt[Model == "FRED_v2_H10S40", SIR]
fred_das <- comp_dt[Model == "FRED_v2_H10S40", DAS]

cat(sprintf("\nBest SIR:  %s (%.3f) — FRED v2: %.3f — %s\n",
            best_sir$Model, best_sir$SIR, fred_sir,
            if (best_sir$SIR > fred_sir) "BEATS FRED!" else "FRED wins"))
cat(sprintf("Best DAS:  %s (%.1f) — FRED v2: %.1f — %s\n",
            best_das$Model, best_das$DAS, fred_das,
            if (best_das$DAS > fred_das) "BEATS FRED!" else "FRED wins"))

# Per-model delta vs FRED
cat("\nDelta vs FRED v2:\n")
for (i in seq_len(nrow(comp_dt))) {
  r <- comp_dt[i]
  if (r$Model == "FRED_v2_H10S40") next
  sir_d <- r$SIR - fred_sir
  das_d <- r$DAS - fred_das
  cat(sprintf("  %s: SIR %+.3f, DAS %+.1f\n", r$Model, sir_d, das_d))
}

# Save comparison table
write.csv(comp_dt,
  file.path(OUT_DIR, "regime_adaptive_comparison.csv"), row.names = FALSE)


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
# STEP 8: Combined comparison chart
#==============================================================================
cat("\n=== STEP 8: Combined comparison chart ===\n")

tryCatch({
  # Panel 1: SIR bar chart
  sir_dt <- comp_dt[, .(Model, SIR)]
  sir_dt[, Model_short := gsub("_", "\n", Model)]
  sir_dt[, Color := fifelse(Model == "FRED_v2_H10S40", "FRED (Baseline)", "New Model")]

  p_sir <- ggplot(sir_dt, aes(x = reorder(Model_short, -SIR), y = SIR, fill = Color)) +
    geom_col(alpha = 0.85, width = 0.7) +
    geom_hline(yintercept = 1.0, linetype = "dashed", color = "red", linewidth = 0.5) +
    geom_text(aes(label = sprintf("%.3f", SIR)), vjust = -0.3, size = 4, fontface = "bold") +
    scale_fill_manual(values = c("FRED (Baseline)" = "#2171B5", "New Model" = "#D6604D")) +
    labs(title = "KPI-A: Sharpe Improvement Ratio (SIR)",
         subtitle = "SIR > 1.0 = improves Sharpe vs buy-and-hold",
         x = NULL, y = "SIR") +
    theme_minimal(base_size = 11) +
    theme(legend.position = "bottom", legend.title = element_blank(),
          axis.text.x = element_text(size = 8))

  # Panel 2: DAS bar chart
  das_dt <- comp_dt[, .(Model, DAS)]
  das_dt[, Model_short := gsub("_", "\n", Model)]
  das_dt[, Color := fifelse(Model == "FRED_v2_H10S40", "FRED (Baseline)", "New Model")]

  p_das <- ggplot(das_dt, aes(x = reorder(Model_short, -DAS), y = DAS, fill = Color)) +
    geom_col(alpha = 0.85, width = 0.7) +
    geom_text(aes(label = sprintf("%.1f", DAS)), vjust = -0.3, size = 4, fontface = "bold") +
    scale_fill_manual(values = c("FRED (Baseline)" = "#2171B5", "New Model" = "#D6604D")) +
    labs(title = "KPI-B: Drawdown Avoidance Score (DAS)",
         subtitle = "0-100 scale: higher = better crisis avoidance",
         x = NULL, y = "DAS") +
    theme_minimal(base_size = 11) +
    theme(legend.position = "bottom", legend.title = element_blank(),
          axis.text.x = element_text(size = 8))

  # Panel 3: Cumulative returns
  cum_list <- list()
  for (nm in names(compare$eval_list)) {
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
  model_names <- c("Benchmark", names(compare$eval_list))
  cum_all[, Series := factor(Series, levels = model_names)]

  n_models <- length(model_names)
  pal <- c("Benchmark" = "grey50",
           setNames(c("#2171B5", "#D6604D", "#FC8D62", "#66C2A5"),
                    names(compare$eval_list)))

  p_cum <- ggplot(cum_all, aes(x = Date, y = Growth, color = Series)) +
    geom_line(linewidth = 0.7) +
    scale_color_manual(values = pal) +
    labs(title = "Cumulative Growth: All Models vs Benchmark",
         x = NULL, y = "Growth of 1") +
    theme_minimal(base_size = 11) +
    theme(legend.position = "bottom", legend.title = element_blank(),
          legend.text = element_text(size = 7))

  # Panel 4: CAGR grouped bar
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

  # Combine
  combined <- (p_sir | p_das) / (p_cum | p_cagr) +
    plot_annotation(
      title = "Regime Research: 3 Adaptive Models vs FRED v2 Baseline",
      subtitle = sprintf("Period: %s ~ %s | FRED v2 baseline: SIR=%.3f, DAS=%.1f",
                          comp_dt$Period_Start[1], comp_dt$Period_End[1],
                          fred_sir, fred_das),
      theme = theme(plot.title = element_text(face = "bold", size = 14))
    )

  chart_path <- file.path(OUT_DIR, "regime_adaptive_comparison.png")
  ggsave(chart_path, combined, width = 16, height = 11, dpi = 150, bg = "white")
  cat(sprintf("  Combined chart saved: %s\n", chart_path))

}, error = function(e) cat(sprintf("  Combined chart error: %s\n", e$message)))


#==============================================================================
# STEP 9: Crisis-by-crisis breakdown
#==============================================================================
cat("\n=== STEP 9: Crisis-by-crisis breakdown ===\n")

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
# STEP 10: Telegram summary
#==============================================================================
cat("\n=== STEP 10: Telegram summary ===\n")

tg_lines <- c(
  "<b>[Regime Research] 3 Adaptive Models vs FRED v2</b>",
  sprintf("Period: %s ~ %s", comp_dt$Period_Start[1], comp_dt$Period_End[1]),
  ""
)

for (i in seq_len(nrow(comp_dt))) {
  r <- comp_dt[i]
  marker <- ""
  if (r$Model == "FRED_v2_H10S40") marker <- " [BASELINE]"
  else {
    sir_d <- r$SIR - fred_sir
    das_d <- r$DAS - fred_das
    if (sir_d > 0 && das_d > 0) marker <- " [BEATS BOTH!]"
    else if (sir_d > 0) marker <- " [SIR+]"
    else if (das_d > 0) marker <- " [DAS+]"
  }
  tg_lines <- c(tg_lines, sprintf("%d. <b>%s</b>: SIR=%.3f DAS=%.1f CAGR=%.1f%%%s",
                                    i, r$Model, r$SIR, r$DAS, r$CAGR_Regime, marker))
}

tg_lines <- c(tg_lines, "",
  "<b>Model descriptions:</b>",
  "M1: Rolling 252d z-score (adaptive thresholds)",
  "M2: 5d delta transition detection (simultaneous deterioration)",
  "M3: FRED primary + DRV extreme override (z>2 or z<-1)",
  "",
  sprintf("Best SIR: %s (%.3f)", best_sir$Model, best_sir$SIR),
  sprintf("Best DAS: %s (%.1f)", best_das$Model, best_das$DAS)
)

tg_msg <- paste(tg_lines, collapse = "\n")
cat(tg_msg, "\n")

tryCatch({
  tg_send(tg_msg, parse_mode = "HTML")
  cat("  Telegram sent.\n")
}, error = function(e) cat(sprintf("  Telegram error: %s\n", e$message)))

tryCatch({
  chart_path <- file.path(OUT_DIR, "regime_adaptive_comparison.png")
  if (file.exists(chart_path)) {
    tg_send_photo(chart_path, caption = "Regime Research: 3 Adaptive Models vs FRED v2")
    cat("  Chart sent via telegram.\n")
  }
}, error = function(e) cat(sprintf("  Chart telegram error: %s\n", e$message)))


#==============================================================================
# FINAL SUMMARY
#==============================================================================
cat("\n\n")
cat("================================================================\n")
cat("      FINAL RESULTS — 3 Adaptive Models vs FRED v2             \n")
cat("================================================================\n")
for (i in seq_len(nrow(comp_dt))) {
  r <- comp_dt[i]
  tag <- if (r$Model == "FRED_v2_H10S40") "(BASELINE)" else ""
  delta_sir <- if (r$Model != "FRED_v2_H10S40") sprintf(" (dSIR=%+.3f)", r$SIR - fred_sir) else ""
  delta_das <- if (r$Model != "FRED_v2_H10S40") sprintf(" (dDAS=%+.1f)", r$DAS - fred_das) else ""
  cat(sprintf("  %-25s SIR=%.3f%s  DAS=%5.1f%s  CAGR=%5.1f%%  SR=%.3f %s\n",
              r$Model, r$SIR, delta_sir, r$DAS, delta_das,
              r$CAGR_Regime, r$SR_Regime, tag))
}
cat("================================================================\n")

cat(sprintf("\nEnd: %s\n", Sys.time()))
cat("=== Regime Research Complete ===\n")
