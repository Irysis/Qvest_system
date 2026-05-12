#==============================================================================
# PD36 delta_vs_pd30_raw.csv MDD sign bug fix
#
# Issue: maxDrawdown(PerformanceAnalytics) returns positive value (e.g. 0.1923),
#        but PD30_C$MDD stored as -0.2294 (negative). Original delta code used
#        (-m_MULT$MDD - (-PD30_C$MDD))*100 = mixing magnitude/sign convention.
#
# Fix: convert all to MDD magnitude (positive %), then compute delta_MDD_pp.
# Sign convention: MDD as "% loss" (positive number).
#==============================================================================

suppressPackageStartupMessages({library(data.table); library(jsonlite)})
setwd("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")
OUT_DIR <- "qepm/mailbox/worktask/WT-D20260511_001/backtest_result_pd36_overlay_diagnostic"

# Load corrected metrics
cmp <- fread(file.path(OUT_DIR, "comparison_overlay_vs_baselines.csv"))

# Normalize MDD to magnitude (positive %)
cmp[, MDD_pct := abs(MDD)]

# PD30 baseline reference (from metrics_summary.json)
PD30_REF <- list(
  SR = 1.0081, CAGR = 0.1689, MDD_pct = 0.2294,
  CVaR_95 = -0.0879, Sortino = 0.5554, Calmar = 0.7361, TO = 3.33
)
S4_V2_REF <- list(
  SR = 1.7877, CAGR = 0.1970, MDD_pct = 0.1280, CVaR_95 = -0.0501
)

# Compute delta vs PD30 with consistent MDD convention
overlay_rows <- cmp[variant %in% c("MULT_AR_x_M4", "MIN_AR_M4", "LIN_0.5_0.5")]

delta_pd30 <- data.table(
  variant = overlay_rows$variant,
  SR_overlay = overlay_rows$SR,
  SR_baseline_pd30 = PD30_REF$SR,
  delta_SR = overlay_rows$SR - PD30_REF$SR,

  CAGR_overlay = overlay_rows$CAGR,
  CAGR_baseline_pd30 = PD30_REF$CAGR,
  delta_CAGR = overlay_rows$CAGR - PD30_REF$CAGR,
  delta_CAGR_pp = (overlay_rows$CAGR - PD30_REF$CAGR) * 100,

  MDD_pct_overlay = overlay_rows$MDD_pct,
  MDD_pct_baseline_pd30 = PD30_REF$MDD_pct,
  delta_MDD_pp = (overlay_rows$MDD_pct - PD30_REF$MDD_pct) * 100,
  # negative = improvement (less drawdown)

  CVaR_95_overlay = overlay_rows$CVaR_95,
  CVaR_95_baseline_pd30 = PD30_REF$CVaR_95,
  delta_CVaR_pp = (overlay_rows$CVaR_95 - PD30_REF$CVaR_95) * 100,
  # positive = improvement (less negative CVaR)

  Sortino_overlay = overlay_rows$Sortino,
  delta_Sortino = overlay_rows$Sortino - PD30_REF$Sortino,

  Calmar_overlay = overlay_rows$Calmar,
  delta_Calmar = overlay_rows$Calmar - PD30_REF$Calmar,

  TO_overlay = overlay_rows$TO,
  delta_TO = overlay_rows$TO - PD30_REF$TO
)

cat("=== Delta vs PD30 C_softmax raw (corrected) ===\n")
print(delta_pd30)
fwrite(delta_pd30, file.path(OUT_DIR, "delta_vs_pd30_raw_corrected.csv"))

# Delta vs S4 v2 (limited — only SR/CAGR/MDD/CVaR available for S4 v2)
delta_s4v2 <- data.table(
  variant = overlay_rows$variant,
  SR_overlay = overlay_rows$SR,
  SR_S4v2 = S4_V2_REF$SR,
  delta_SR = overlay_rows$SR - S4_V2_REF$SR,
  CAGR_overlay = overlay_rows$CAGR,
  CAGR_S4v2 = S4_V2_REF$CAGR,
  delta_CAGR_pp = (overlay_rows$CAGR - S4_V2_REF$CAGR) * 100,
  MDD_pct_overlay = overlay_rows$MDD_pct,
  MDD_pct_S4v2 = S4_V2_REF$MDD_pct,
  delta_MDD_pp = (overlay_rows$MDD_pct - S4_V2_REF$MDD_pct) * 100,
  CVaR_95_overlay = overlay_rows$CVaR_95,
  CVaR_95_S4v2 = S4_V2_REF$CVaR_95,
  delta_CVaR_pp = (overlay_rows$CVaR_95 - S4_V2_REF$CVaR_95) * 100
)
cat("\n=== Delta vs S4 v2 4-sleeve (255m, full overlay reference) ===\n")
print(delta_s4v2)
fwrite(delta_s4v2, file.path(OUT_DIR, "delta_vs_s4v2_corrected.csv"))

# Final comparison summary table (unified MDD = % magnitude)
final_cmp <- data.table(
  variant = c(overlay_rows$variant, "PD30_C_softmax (baseline)", "S4_v2 (reference, full overlay)"),
  SR = c(overlay_rows$SR, PD30_REF$SR, S4_V2_REF$SR),
  CAGR_pct = c(overlay_rows$CAGR * 100, PD30_REF$CAGR * 100, S4_V2_REF$CAGR * 100),
  MDD_pct_magnitude = c(overlay_rows$MDD_pct * 100, PD30_REF$MDD_pct * 100, S4_V2_REF$MDD_pct * 100),
  CVaR_95_pct = c(overlay_rows$CVaR_95 * 100, PD30_REF$CVaR_95 * 100, S4_V2_REF$CVaR_95 * 100),
  Sortino = c(overlay_rows$Sortino, PD30_REF$Sortino, NA),
  Calmar = c(overlay_rows$Calmar, PD30_REF$Calmar, NA),
  Hit_pct = c(overlay_rows$Hit * 100, NA, NA),
  TO_annualized = c(overlay_rows$TO, PD30_REF$TO, NA),
  n_months = c(overlay_rows$n_months, 296, 255)
)
cat("\n=== Unified comparison (MDD as positive % magnitude) ===\n")
print(final_cmp)
fwrite(final_cmp, file.path(OUT_DIR, "comparison_unified.csv"))

# Update audit summary with corrected metrics
audit_path <- file.path(OUT_DIR, "audit.json")
au <- fromJSON(audit_path, simplifyVector = FALSE)
au$corrected_delta_path <- "delta_vs_pd30_raw_corrected.csv (MDD magnitude convention)"
au$mdd_convention_note <- "All MDD values stored as positive % magnitude. Delta sign: negative = improvement."
write_json(au, audit_path, pretty = TRUE, auto_unbox = TRUE)

cat("\n=== FIX COMPLETE ===\n")
cat(sprintf("\nPD36 MULT_AR_x_M4 vs PD30 C_softmax raw:\n"))
cat(sprintf("  SR     : %.4f -> %.4f (delta %+.4f)\n", PD30_REF$SR, overlay_rows[variant=="MULT_AR_x_M4", SR],
            overlay_rows[variant=="MULT_AR_x_M4", SR] - PD30_REF$SR))
cat(sprintf("  CAGR   : %.2f%% -> %.2f%% (delta %+.2fpp)\n", PD30_REF$CAGR*100, overlay_rows[variant=="MULT_AR_x_M4", CAGR]*100,
            (overlay_rows[variant=="MULT_AR_x_M4", CAGR] - PD30_REF$CAGR)*100))
cat(sprintf("  MDD    : %.2f%% -> %.2f%% (delta %+.2fpp = %s)\n", PD30_REF$MDD_pct*100, overlay_rows[variant=="MULT_AR_x_M4", MDD_pct]*100,
            (overlay_rows[variant=="MULT_AR_x_M4", MDD_pct] - PD30_REF$MDD_pct)*100,
            ifelse(overlay_rows[variant=="MULT_AR_x_M4", MDD_pct] < PD30_REF$MDD_pct, "IMPROVEMENT", "WORSE")))
cat(sprintf("  CVaR95 : %.2f%% -> %.2f%% (delta %+.2fpp = %s)\n", PD30_REF$CVaR_95*100, overlay_rows[variant=="MULT_AR_x_M4", CVaR_95]*100,
            (overlay_rows[variant=="MULT_AR_x_M4", CVaR_95] - PD30_REF$CVaR_95)*100,
            ifelse(overlay_rows[variant=="MULT_AR_x_M4", CVaR_95] > PD30_REF$CVaR_95, "IMPROVEMENT", "WORSE")))
cat(sprintf("  TO     : %.2f -> %.2f (delta %+.2f)\n", PD30_REF$TO, overlay_rows[variant=="MULT_AR_x_M4", TO],
            overlay_rows[variant=="MULT_AR_x_M4", TO] - PD30_REF$TO))
