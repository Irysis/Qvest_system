#==============================================================================
# MSM-based Regime Model KPI Evaluation
# Compare 5 MSM models against FRED v2 baseline (SIR 1.384, DAS 43.9)
#==============================================================================
source("02_Infrastructure/config.R")
source("02_Infrastructure/backtest_harness.R")
source("02_Infrastructure/regime_signal.R")
source("02_Infrastructure/regime_combined.R")
source("02_Infrastructure/regime_kpi.R")
source("02_Infrastructure/telegram_notify.R")
library(data.table); library(arrow)

cat("=== MSM Regime KPI Evaluation ===\n\n")

# ── Load benchmark monthly returns ──────────────────────────────────────────
res <- load_rawdata(use_cache = TRUE)
bm <- unique(res$BM_DT[, .(Date, BM_Ret)])
setorder(bm, Date)
bm[, YM := format(Date, "%Y-%m")]
bm_m <- bm[, .(Ret = prod(1 + BM_Ret, na.rm = TRUE) - 1), by = YM]
bm_m[, Date := as.Date(cut(as.Date(paste0(YM, "-01")) + 31, "month")) - 1]
setorder(bm_m, Date)
cat(sprintf("[BM] %d months: %s ~ %s\n\n", nrow(bm_m), min(bm_m$Date), max(bm_m$Date)))

# ── Load raw signals ────────────────────────────────────────────────────────
msm_dt  <- load_msm_signal()
fred_dt <- load_fred_signal()

cat(sprintf("[MSM] %d months | [FRED] %d months\n\n", nrow(msm_dt), nrow(fred_dt)))

# ── FRED v2 Baseline ────────────────────────────────────────────────────────
fred_signal <- copy(fred_dt)
fred_signal[, Date := as.Date(paste0(YM, "-01"))]
fred_signal[, Date := as.Date(cut(Date + 31, "month")) - 1]
fred_signal[, Score := FRED_MRS]
fred_signal[, Action := fifelse(Score >= 40, "SKIP",
                                fifelse(Score >= 10, "HALF", "FULL"))]
fred_signal <- fred_signal[, .(Date, Score, Action)]

# ── Model A: MSM Standalone ─────────────────────────────────────────────────
cat("--- Model A: MSM Standalone ---\n")
msm_sig_a <- copy(msm_dt)
msm_sig_a[, Date := as.Date(paste0(YM, "-01"))]
msm_sig_a[, Date := as.Date(cut(Date + 31, "month")) - 1]
msm_sig_a[, Score := MSM_Crisis_Prob * 100]
msm_sig_a[, Action := fifelse(MSM_Crisis_Prob > 0.5, "SKIP",
                               fifelse(MSM_Crisis_Prob > 0.3, "HALF", "FULL"))]
msm_sig_a <- msm_sig_a[, .(Date, Score, Action)]

# ── Merge MSM + FRED on YM for combined models ─────────────────────────────
merged <- merge(
  fred_dt[, .(YM, FRED_MRS)],
  msm_dt[, .(YM, MSM_Crisis_Prob)],
  by = "YM", all = TRUE
)
merged[is.na(FRED_MRS), FRED_MRS := 0]
merged[is.na(MSM_Crisis_Prob), MSM_Crisis_Prob := 0]
merged[, Date := as.Date(paste0(YM, "-01"))]
merged[, Date := as.Date(cut(Date + 31, "month")) - 1]
setorder(merged, Date)

# ── Model B: FRED + MSM AND-gate ────────────────────────────────────────────
cat("--- Model B: FRED + MSM AND-gate ---\n")
msm_sig_b <- copy(merged)
msm_sig_b[, FRED_Alert := (FRED_MRS >= 30)]
msm_sig_b[, MSM_Alert  := (MSM_Crisis_Prob >= 0.5)]
# SKIP only when BOTH agree
msm_sig_b[, Action := fifelse(FRED_Alert & MSM_Alert, "SKIP",
                               fifelse(FRED_Alert | MSM_Alert, "HALF", "FULL"))]
msm_sig_b[, Score := pmax(FRED_MRS, MSM_Crisis_Prob * 100)]
msm_sig_b <- msm_sig_b[, .(Date, Score, Action)]

# ── Model C: FRED + MSM OR-gate ─────────────────────────────────────────────
cat("--- Model C: FRED + MSM OR-gate ---\n")
msm_sig_c <- copy(merged)
msm_sig_c[, FRED_Alert := (FRED_MRS >= 30)]
msm_sig_c[, MSM_Alert  := (MSM_Crisis_Prob >= 0.5)]
# SKIP when EITHER signals danger
msm_sig_c[, Action := fifelse(FRED_Alert | MSM_Alert, "SKIP",
                               fifelse(FRED_MRS >= 10 | MSM_Crisis_Prob >= 0.3, "HALF", "FULL"))]
msm_sig_c[, Score := pmax(FRED_MRS, MSM_Crisis_Prob * 100)]
msm_sig_c <- msm_sig_c[, .(Date, Score, Action)]

# ── Model D: FRED + MSM Weighted (60/40) ────────────────────────────────────
cat("--- Model D: FRED + MSM Weighted 60/40 ---\n")
msm_sig_d <- copy(merged)
msm_sig_d[, Score := 0.6 * FRED_MRS + 0.4 * MSM_Crisis_Prob * 100]
msm_sig_d[, Action := fifelse(Score >= 40, "SKIP",
                               fifelse(Score >= 10, "HALF", "FULL"))]
msm_sig_d <- msm_sig_d[, .(Date, Score, Action)]

# ── Model E: MSM as FRED Booster ────────────────────────────────────────────
cat("--- Model E: MSM as FRED Booster ---\n")
msm_sig_e <- copy(merged)
msm_sig_e[, Score := FRED_MRS]
# Add MSM boost to FRED score
msm_sig_e[MSM_Crisis_Prob > 0.7, Score := Score + 25]
msm_sig_e[MSM_Crisis_Prob > 0.5 & MSM_Crisis_Prob <= 0.7, Score := Score + 15]
msm_sig_e[, Action := fifelse(Score >= 40, "SKIP",
                               fifelse(Score >= 10, "HALF", "FULL"))]
msm_sig_e <- msm_sig_e[, .(Date, Score, Action)]

# ── Evaluate all models ─────────────────────────────────────────────────────
cat("\n========== EVALUATION ==========\n\n")

models_list <- list(
  "FRED_v2_Baseline"    = fred_signal,
  "A_MSM_Standalone"    = msm_sig_a,
  "B_FRED_MSM_AND"      = msm_sig_b,
  "C_FRED_MSM_OR"       = msm_sig_c,
  "D_FRED_MSM_Wt60_40"  = msm_sig_d,
  "E_MSM_FRED_Booster"  = msm_sig_e
)

comp <- regime_compare(models_list, bm_m)

# ── Print final comparison ──────────────────────────────────────────────────
cat("\n\n========== FINAL COMPARISON ==========\n")
print(comp$comparison_dt[, .(Model, SR_Benchmark, SR_Regime, SIR, DAS,
                              N_Crisis, N_Skipped, N_Halved, N_Full,
                              CAGR_BM, CAGR_Regime)])

# ── Save comparison CSV ─────────────────────────────────────────────────────
out_dir <- file.path(RESEARCH_OUTPUT, "regime_analysis")
fwrite(comp$comparison_dt, file.path(out_dir, "msm_regime_kpi_comparison.csv"))

# ── Generate charts for each model ──────────────────────────────────────────
cat("\n[Charts] Generating...\n")
for (nm in names(comp$eval_list)) {
  tryCatch(
    regime_kpi_chart(comp$eval_list[[nm]], output_dir = out_dir),
    error = function(e) cat(sprintf("[Chart SKIP] %s: %s\n", nm, e$message))
  )
}

# ── Comparison bar chart ────────────────────────────────────────────────────
library(ggplot2)

comp_dt <- comp$comparison_dt
comp_dt[, Model_short := gsub("_", " ", Model)]

# SIR + DAS dual-axis bar chart
p_sir <- ggplot(comp_dt, aes(x = reorder(Model_short, SIR), y = SIR)) +
  geom_col(fill = "#2171B5", alpha = 0.85, width = 0.6) +
  geom_hline(yintercept = 1.0, linetype = "dashed", color = "red") +
  geom_text(aes(label = sprintf("%.3f", SIR)), hjust = -0.1, size = 3.5) +
  coord_flip() +
  labs(title = "Sharpe Improvement Ratio (SIR)", x = NULL, y = "SIR") +
  theme_minimal(base_size = 11) +
  expand_limits(y = max(comp_dt$SIR) * 1.15)

p_das <- ggplot(comp_dt, aes(x = reorder(Model_short, DAS), y = DAS)) +
  geom_col(fill = "#41AB5D", alpha = 0.85, width = 0.6) +
  geom_text(aes(label = sprintf("%.1f", DAS)), hjust = -0.1, size = 3.5) +
  coord_flip() +
  labs(title = "Drawdown Avoidance Score (DAS)", x = NULL, y = "DAS (0-100)") +
  theme_minimal(base_size = 11) +
  expand_limits(y = max(comp_dt$DAS) * 1.15)

library(patchwork)
p_combined <- p_sir / p_das +
  plot_annotation(
    title = "MSM Regime Models vs FRED v2 Baseline",
    subtitle = sprintf("Period: %s ~ %s | %d models compared",
                        min(comp_dt$Period_Start), max(comp_dt$Period_End),
                        nrow(comp_dt)),
    theme = theme(plot.title = element_text(face = "bold", size = 14))
  )

chart_path <- file.path(out_dir, "msm_vs_fred_comparison.png")
ggsave(chart_path, p_combined, width = 12, height = 8, dpi = 150, bg = "white")
cat(sprintf("[Chart] Saved: %s\n", chart_path))

# ── Telegram report ─────────────────────────────────────────────────────────
best_model <- comp_dt[which.max(SIR)]
msg_lines <- c(
  "<b>[Regime KPI] MSM vs FRED v2 Comparison</b>",
  "",
  "<b>Model Ranking (by SIR):</b>"
)
for (i in seq_len(nrow(comp_dt))) {
  r <- comp_dt[i]
  marker <- fifelse(r$Model == "FRED_v2_Baseline", " [BASELINE]", "")
  msg_lines <- c(msg_lines,
    sprintf("  %d. %s: SIR=%.3f, DAS=%.1f, CAGR=%.2f%%%s",
            i, r$Model, r$SIR, r$DAS, r$CAGR_Regime, marker))
}
msg_lines <- c(msg_lines, "",
  sprintf("<b>Best: %s (SIR=%.3f, DAS=%.1f)</b>", best_model$Model,
          best_model$SIR, best_model$DAS),
  sprintf("FRED v2 Baseline: SIR=%.3f, DAS=%.1f",
          comp_dt[Model == "FRED_v2_Baseline"]$SIR,
          comp_dt[Model == "FRED_v2_Baseline"]$DAS)
)
msg <- paste(msg_lines, collapse = "\n")

tryCatch({
  tg_send(msg, parse_mode = "HTML")
  if (file.exists(chart_path)) tg_send_photo(chart_path, "MSM vs FRED v2 Comparison")
  cat("[Telegram] Sent.\n")
}, error = function(e) cat(sprintf("[Telegram] Failed: %s\n", e$message)))

cat("\n=== MSM Regime KPI Evaluation Complete ===\n")
