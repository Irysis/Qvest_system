#==============================================================================
# Advanced Derivative Regime Models — Speed, Dynamics, Cross-Signal Divergence
# 4 Models: D1(Velocity), D2(Divergence), D3(OI Regime), D4(FRED+DRV Composite)
# 2026-03-14
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(ggplot2)
  library(patchwork)
})

source("02_Infrastructure/config.R")
source("02_Infrastructure/backtest_harness.R")
source("02_Infrastructure/regime_kpi.R")
tryCatch(source("02_Infrastructure/telegram_notify.R"), error = function(e) {
  cat("[WARN] Telegram not loaded:", e$message, "\n")
  tg_send <<- function(...) invisible(NULL)
})

cat("=== Loading Derivatives Data ===\n")

drv_dir <- file.path(CACHE_DIR, "krx_derivatives")
files <- list.files(drv_dir, pattern = "\\.parquet$", full.names = TRUE)
cat(sprintf("Found %d derivative files\n", length(files)))

all_drv <- rbindlist(lapply(files, function(f) {
  tryCatch(as.data.table(read_parquet(f)), error = function(e) NULL)
}), fill = TRUE)

# Parse Date
all_drv[, Date := as.Date(Date, format = "%Y%m%d")]
all_drv <- all_drv[!is.na(Date)]
setorder(all_drv, Date)
cat(sprintf("Loaded %d days (%s ~ %s)\n", nrow(all_drv), min(all_drv$Date), max(all_drv$Date)))
cat("Columns:", paste(names(all_drv), collapse = ", "), "\n")

# Load FRED regime
fred <- as.data.table(read_parquet(file.path(CACHE_DIR, "macro_regime.parquet")))
fred[, Date := as.Date(Date)]

# Load benchmark
res <- load_rawdata(use_cache = TRUE)
bm <- unique(res$BM_DT[, .(Date, BM_Ret)])
setorder(bm, Date)
bm[, YM := format(Date, "%Y-%m")]
bm_m <- bm[, .(Ret = prod(1 + BM_Ret, na.rm = TRUE) - 1), by = YM]
bm_m[, Date := as.Date(paste0(YM, "-01"))]
setorder(bm_m, Date)
bm_m <- bm_m[, .(Date, Ret)]

cat(sprintf("Benchmark: %d months (%s ~ %s)\n", nrow(bm_m), min(bm_m$Date), max(bm_m$Date)))

#==============================================================================
# STEP 1: Compute Daily Velocities (5-day changes)
#==============================================================================
cat("\n=== Computing Daily Velocities ===\n")

drv <- copy(all_drv)

# Velocity = 5-day change
drv[, VKOSPI_vel := VKOSPI - shift(VKOSPI, 5)]
drv[, PCR_vel    := PCR_Vol - shift(PCR_Vol, 5)]
drv[, Basis_vel  := K200_Basis_Pct - shift(K200_Basis_Pct, 5)]

# Rolling 60d z-score for each velocity
rolling_z <- function(x, window = 60) {
  out <- rep(NA_real_, length(x))
  for (i in seq_along(x)) {
    if (i < window || is.na(x[i])) next
    vals <- x[(i - window + 1):i]
    vals <- vals[!is.na(vals)]
    if (length(vals) < 20) next
    m <- mean(vals)
    s <- sd(vals)
    if (s < 1e-10) next
    out[i] <- (x[i] - m) / s
  }
  out
}

drv[, VKOSPI_vel_z := rolling_z(VKOSPI_vel)]
drv[, PCR_vel_z    := rolling_z(PCR_vel)]
drv[, Basis_vel_z  := rolling_z(Basis_vel)]

# Composite velocity z = mean of available z-scores
drv[, vel_composite_z := rowMeans(cbind(VKOSPI_vel_z, PCR_vel_z, Basis_vel_z), na.rm = TRUE)]

# OI changes (20-day pct change)
drv[, Put_OI_chg20  := (Put_OI - shift(Put_OI, 20)) / shift(Put_OI, 20)]
drv[, Call_OI_chg20 := (Call_OI - shift(Call_OI, 20)) / shift(Call_OI, 20)]
drv[, OI_regime     := Put_OI_chg20 - Call_OI_chg20]
drv[, OI_regime_z   := rolling_z(OI_regime)]

# Cross-signal divergence: VKOSPI rising but PCR falling = unhedged fear
drv[, divergence := VKOSPI_vel_z - PCR_vel_z]

# Add YM
drv[, YM := format(Date, "%Y-%m")]

cat(sprintf("Velocities computed. Non-NA composite z: %d / %d\n",
            sum(!is.na(drv$vel_composite_z)), nrow(drv)))

#==============================================================================
# MODEL D1: Velocity Regime (max velocity z per month)
#==============================================================================
cat("\n=== Model D1: Velocity Regime ===\n")

d1_monthly <- drv[!is.na(vel_composite_z), .(
  max_vel_z = max(vel_composite_z, na.rm = TRUE),
  mean_vel_z = mean(vel_composite_z, na.rm = TRUE)
), by = YM]

d1_monthly[, Date := as.Date(paste0(YM, "-01"))]
d1_monthly[, Score := round(pmax(0, max_vel_z) * 20, 1)]  # scale for readability
d1_monthly[, Action := fifelse(max_vel_z > 2.0, "SKIP",
                        fifelse(max_vel_z > 1.0, "HALF", "FULL"))]

cat(sprintf("D1 signal: %d months | FULL: %d, HALF: %d, SKIP: %d\n",
            nrow(d1_monthly),
            sum(d1_monthly$Action == "FULL"),
            sum(d1_monthly$Action == "HALF"),
            sum(d1_monthly$Action == "SKIP")))

#==============================================================================
# MODEL D2: Cross-Signal Divergence
#==============================================================================
cat("\n=== Model D2: Cross-Signal Divergence ===\n")

d2_monthly <- drv[!is.na(divergence), .(
  max_div = max(divergence, na.rm = TRUE),
  mean_div = mean(divergence, na.rm = TRUE),
  # Also check basis narrowing + VKOSPI rising double confirm
  basis_vkospi_confirm = sum(Basis_vel_z < -1 & VKOSPI_vel_z > 1, na.rm = TRUE)
), by = YM]

d2_monthly[, Date := as.Date(paste0(YM, "-01"))]
d2_monthly[, Score := round(pmax(0, max_div) * 15, 1)]
d2_monthly[, Action := fifelse(max_div > 2.0, "SKIP",
                        fifelse(max_div > 1.0, "HALF", "FULL"))]

cat(sprintf("D2 signal: %d months | FULL: %d, HALF: %d, SKIP: %d\n",
            nrow(d2_monthly),
            sum(d2_monthly$Action == "FULL"),
            sum(d2_monthly$Action == "HALF"),
            sum(d2_monthly$Action == "SKIP")))

#==============================================================================
# MODEL D3: Open Interest Regime Change
#==============================================================================
cat("\n=== Model D3: OI Regime Change ===\n")

d3_monthly <- drv[!is.na(OI_regime_z), .(
  mean_oi_z = mean(OI_regime_z, na.rm = TRUE),
  max_oi_z = max(OI_regime_z, na.rm = TRUE)
), by = YM]

d3_monthly[, Date := as.Date(paste0(YM, "-01"))]
d3_monthly[, Score := round(pmax(0, mean_oi_z) * 25, 1)]
d3_monthly[, Action := fifelse(mean_oi_z > 1.5, "SKIP",
                        fifelse(mean_oi_z > 0.5, "HALF", "FULL"))]

cat(sprintf("D3 signal: %d months | FULL: %d, HALF: %d, SKIP: %d\n",
            nrow(d3_monthly),
            sum(d3_monthly$Action == "FULL"),
            sum(d3_monthly$Action == "HALF"),
            sum(d3_monthly$Action == "SKIP")))

#==============================================================================
# MODEL D4: FRED + Best DRV Composite (derivatives as boosters)
#==============================================================================
cat("\n=== Model D4: FRED + DRV Composite ===\n")

# FRED baseline
fred_sig <- fred[, .(YM, Macro_Risk_Score)]
fred_sig[, Date := as.Date(paste0(YM, "-01"))]

# Merge with D1, D2, D3 monthly signals
d4 <- merge(fred_sig, d1_monthly[, .(YM, max_vel_z)], by = "YM", all.x = TRUE)
d4 <- merge(d4, d2_monthly[, .(YM, max_div)], by = "YM", all.x = TRUE)
d4 <- merge(d4, d3_monthly[, .(YM, mean_oi_z)], by = "YM", all.x = TRUE)

# Derivative booster to FRED score
d4[, drv_boost := 0]
d4[!is.na(max_vel_z) & max_vel_z > 1.5, drv_boost := drv_boost + 10]
d4[!is.na(max_div) & max_div > 1.5, drv_boost := drv_boost + 8]
d4[!is.na(mean_oi_z) & mean_oi_z > 1.0, drv_boost := drv_boost + 5]

d4[, Score := Macro_Risk_Score + drv_boost]
d4[, Action := fifelse(Score >= 40, "SKIP",
                fifelse(Score >= 10, "HALF", "FULL"))]

cat(sprintf("D4 signal: %d months | FULL: %d, HALF: %d, SKIP: %d\n",
            nrow(d4),
            sum(d4$Action == "FULL"),
            sum(d4$Action == "HALF"),
            sum(d4$Action == "SKIP")))
cat(sprintf("  Months with DRV boost > 0: %d (%.1f%%)\n",
            sum(d4$drv_boost > 0, na.rm = TRUE),
            mean(d4$drv_boost > 0, na.rm = TRUE) * 100))

#==============================================================================
# FRED v2 Baseline (for comparison)
#==============================================================================
cat("\n=== FRED v2 Baseline ===\n")

fred_baseline <- fred[, .(YM, Macro_Risk_Score)]
fred_baseline[, Date := as.Date(paste0(YM, "-01"))]
fred_baseline[, Score := Macro_Risk_Score]
fred_baseline[, Action := fifelse(Score >= 40, "SKIP",
                           fifelse(Score >= 10, "HALF", "FULL"))]

cat(sprintf("FRED v2: %d months | FULL: %d, HALF: %d, SKIP: %d\n",
            nrow(fred_baseline),
            sum(fred_baseline$Action == "FULL"),
            sum(fred_baseline$Action == "HALF"),
            sum(fred_baseline$Action == "SKIP")))

#==============================================================================
# EVALUATE ALL MODELS
#==============================================================================
cat("\n=== Evaluating All Models ===\n")

models <- list(
  "D1_Velocity"     = d1_monthly[, .(Date, Score, Action)],
  "D2_Divergence"   = d2_monthly[, .(Date, Score, Action)],
  "D3_OI_Regime"    = d3_monthly[, .(Date, Score, Action)],
  "D4_FRED_DRV"     = d4[, .(Date, Score, Action)],
  "FRED_v2_Baseline" = fred_baseline[, .(Date, Score, Action)]
)

comp <- regime_compare(models, bm_m)

# Print comparison
cat("\n╔══════════════════════════════════════════════════════════════════════╗\n")
cat("║        ADVANCED DERIVATIVES REGIME MODEL COMPARISON                ║\n")
cat("╠══════════════════════════════════════════════════════════════════════╣\n")

comp_dt <- comp$comparison_dt
for (i in seq_len(nrow(comp_dt))) {
  r <- comp_dt[i]
  flag <- ""
  if (r$SIR > 1.353) flag <- " *** BEATS BEST MSM HYBRID ***"
  cat(sprintf("║  %-20s  SIR=%.3f  DAS=%.1f  CAGR_BM=%.1f%%  CAGR_REG=%.1f%%%s\n",
              r$Model, r$SIR, r$DAS, r$CAGR_BM, r$CAGR_Regime, flag))
}
cat("╠══════════════════════════════════════════════════════════════════════╣\n")
cat("║  Reference: FRED+MSM 60/40 hybrid  SIR=1.353  DAS=61.9           ║\n")
cat("╚══════════════════════════════════════════════════════════════════════╝\n")

# Save comparison CSV
out_dir <- file.path(RESEARCH_OUTPUT, "regime_analysis")
fwrite(comp_dt, file.path(out_dir, "drv_advanced_comparison.csv"))

#==============================================================================
# CHARTS
#==============================================================================
cat("\n=== Generating Charts ===\n")

# Individual KPI charts
for (nm in names(comp$eval_list)) {
  tryCatch(
    regime_kpi_chart(comp$eval_list[[nm]], output_dir = out_dir),
    error = function(e) cat(sprintf("[WARN] Chart for %s failed: %s\n", nm, e$message))
  )
}

# Comparison bar chart
bar_dt <- comp_dt[, .(Model, SIR, DAS)]
bar_dt[, Model := factor(Model, levels = Model)]

p_sir <- ggplot(bar_dt, aes(x = Model, y = SIR, fill = SIR > 1)) +
  geom_col(alpha = 0.85) +
  geom_hline(yintercept = 1.0, linetype = "dashed", color = "red") +
  geom_hline(yintercept = 1.353, linetype = "dotted", color = "blue") +
  annotate("text", x = 0.5, y = 1.353, label = "MSM Hybrid (1.353)",
           hjust = 0, vjust = -0.5, size = 3, color = "blue") +
  scale_fill_manual(values = c("FALSE" = "#CB181D", "TRUE" = "#2171B5"), guide = "none") +
  labs(title = "SIR (Sharpe Improvement Ratio)", y = "SIR", x = NULL) +
  theme_minimal(base_size = 11) +
  theme(axis.text.x = element_text(angle = 30, hjust = 1))

p_das <- ggplot(bar_dt, aes(x = Model, y = DAS, fill = DAS > 50)) +
  geom_col(alpha = 0.85) +
  geom_hline(yintercept = 61.9, linetype = "dotted", color = "blue") +
  annotate("text", x = 0.5, y = 61.9, label = "MSM Hybrid (61.9)",
           hjust = 0, vjust = -0.5, size = 3, color = "blue") +
  scale_fill_manual(values = c("FALSE" = "#FD8D3C", "TRUE" = "#41AB5D"), guide = "none") +
  labs(title = "DAS (Drawdown Avoidance Score, 0-100)", y = "DAS", x = NULL) +
  theme_minimal(base_size = 11) +
  theme(axis.text.x = element_text(angle = 30, hjust = 1))

combined <- (p_sir | p_das) +
  plot_annotation(
    title = "Advanced Derivatives Regime Models vs Baselines",
    subtitle = sprintf("Period: %s ~ %s | Reference: FRED+MSM 60/40 SIR=1.353, DAS=61.9",
                        min(bm_m$Date), max(bm_m$Date)),
    theme = theme(plot.title = element_text(face = "bold", size = 14))
  )

chart_path <- file.path(out_dir, "drv_advanced_comparison.png")
ggsave(chart_path, combined, width = 14, height = 7, dpi = 150, bg = "white")
cat(sprintf("Comparison chart saved: %s\n", chart_path))

#==============================================================================
# DETAILED CRISIS ANALYSIS — Best model
#==============================================================================
cat("\n=== Crisis Analysis (Best Model) ===\n")

best_idx <- which.max(comp_dt$SIR)
best_name <- comp_dt$Model[best_idx]
best_eval <- comp$eval_list[[best_name]]

cat(sprintf("\nBest model: %s (SIR=%.3f, DAS=%.1f)\n", best_name,
            comp_dt$SIR[best_idx], comp_dt$DAS[best_idx]))
cat("\nCrisis breakdown:\n")
print(best_eval$crisis_by_name)

#==============================================================================
# VELOCITY DYNAMICS — Additional analysis
#==============================================================================
cat("\n=== Velocity Signal Analysis ===\n")

# Show which months triggered velocity alerts
vel_alerts <- d1_monthly[Action != "FULL"][order(-max_vel_z)]
cat(sprintf("\nD1 Velocity alerts (%d months):\n", nrow(vel_alerts)))
if (nrow(vel_alerts) > 0) {
  print(head(vel_alerts[, .(YM, max_vel_z, Action)], 20))
}

# Divergence alerts
div_alerts <- d2_monthly[Action != "FULL"][order(-max_div)]
cat(sprintf("\nD2 Divergence alerts (%d months):\n", nrow(div_alerts)))
if (nrow(div_alerts) > 0) {
  print(head(div_alerts[, .(YM, max_div, basis_vkospi_confirm, Action)], 20))
}

# OI regime alerts
oi_alerts <- d3_monthly[Action != "FULL"][order(-mean_oi_z)]
cat(sprintf("\nD3 OI Regime alerts (%d months):\n", nrow(oi_alerts)))
if (nrow(oi_alerts) > 0) {
  print(head(oi_alerts[, .(YM, mean_oi_z, Action)], 20))
}

# D4 boost analysis
d4_boosted <- d4[drv_boost > 0][order(-drv_boost)]
cat(sprintf("\nD4 FRED+DRV boosted months (%d):\n", nrow(d4_boosted)))
if (nrow(d4_boosted) > 0) {
  print(head(d4_boosted[, .(YM, Macro_Risk_Score, drv_boost, Score, Action)], 20))
}

#==============================================================================
# TELEGRAM REPORT
#==============================================================================
cat("\n=== Sending Telegram Report ===\n")

msg_lines <- c(
  "<b>[Regime] Advanced Derivatives Models</b>",
  "",
  "<b>4 Models — Speed, Dynamics, Cross-Signal</b>",
  ""
)

for (i in seq_len(nrow(comp_dt))) {
  r <- comp_dt[i]
  emoji <- if (r$SIR > 1.353) ">>>" else if (r$SIR > 1.0) ">" else "X"
  msg_lines <- c(msg_lines, sprintf("%s <b>%s</b>: SIR=%.3f, DAS=%.1f",
                                     emoji, r$Model, r$SIR, r$DAS))
}

msg_lines <- c(msg_lines, "",
  sprintf("Reference: FRED+MSM SIR=1.353, DAS=61.9"),
  "",
  sprintf("Best: <b>%s</b> (SIR=%.3f, DAS=%.1f)",
          best_name, comp_dt$SIR[best_idx], comp_dt$DAS[best_idx]),
  "",
  "<b>Model Logic:</b>",
  "D1: Velocity (5d change z-score, max/month)",
  "D2: VKOSPI-PCR divergence (unhedged fear)",
  "D3: Put/Call OI change regime",
  "D4: FRED + derivative boosters"
)

msg <- paste(msg_lines, collapse = "\n")
tryCatch(tg_send(msg, parse_mode = "HTML"), error = function(e) {
  cat("[WARN] Telegram failed:", e$message, "\n")
})

# Send chart
tryCatch(tg_send_image(chart_path, caption = "Advanced DRV Regime Comparison"),
         error = function(e) cat("[WARN] Chart send failed:", e$message, "\n"))

cat("\n=== COMPLETE ===\n")
cat(sprintf("Results saved to: %s\n", out_dir))
