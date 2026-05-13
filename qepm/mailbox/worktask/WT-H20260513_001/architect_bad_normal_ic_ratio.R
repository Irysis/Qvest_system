# ===========================================================
# Architect bad_normal_IC_ratio computation — R05 source signal
# WT-H20260513_001 — Codex C6 PARTIAL escalation deliverable
# AX-001 v2 axis 3 evidence — R05_Tail_Risk_Z forward IC
# ============================================================
# Method:
#   1. Load R05 alpha_scores_new.parquet (ticker × date × R05_Tail_Risk_Z + Ret_1m)
#   2. Compute monthly IC: Spearman corr(R05_z, fwd_ret) per (regime_state, ym)
#   3. ICIR by regime
#   4. Bad / Normal ratio
#
# Bad regimes:    CAUTION + CRISIS
# Normal regimes: BULL + NORMAL
# ===========================================================

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
})

base_dir <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(base_dir)

cat("============================================================\n")
cat("ARCHITECT BAD/NORMAL IC_RATIO — R05_Tail_Risk_Z\n")
cat("============================================================\n\n")

r05 <- as.data.table(read_parquet("stage_artifacts/WT_D20260512_003/alpha_scores_new.parquet"))
r05[, Date := as.Date(Date)]
setorder(r05, Date, Ticker)
cat("R05 panel: rows=", nrow(r05),
    " | dates=", length(unique(r05$Date)),
    " | tickers=", length(unique(r05$Ticker)), "\n")

# Per-date Ret_1m is sig_date convention (forward 1-month return)
# So IC = cor(R05_Tail_Risk_Z at date t, Ret_1m at date t) = predictive IC

# Filter complete cases
ic_panel <- r05[!is.na(R05_Tail_Risk_Z) & !is.na(Ret_1m) & is.finite(Ret_1m)]
cat("Valid (R05, fwd_ret) pairs:", nrow(ic_panel), "\n")

# Monthly IC by Spearman rank corr
ic_monthly <- ic_panel[, .(
  ic = cor(R05_Tail_Risk_Z, Ret_1m, method = "spearman", use = "pairwise.complete.obs"),
  n_obs = .N,
  regime = first(regime_state)
), by = Date]

ic_monthly <- ic_monthly[!is.na(ic)]
cat("\nMonthly IC summary by regime:\n")
print(ic_monthly[, .(n_months = .N,
                     ic_mean = mean(ic),
                     ic_sd = sd(ic),
                     icir = mean(ic) / sd(ic),
                     hit_rate_pos = mean(ic > 0)), by = regime])

# Aggregate to bad / normal
ic_monthly[, regime_class := ifelse(regime %in% c("CAUTION", "CRISIS"), "BAD",
                                     ifelse(regime %in% c("BULL", "NORMAL"), "NORMAL", "OTHER"))]

agg <- ic_monthly[regime_class %in% c("BAD","NORMAL"),
                  .(n_months = .N,
                    ic_mean = mean(ic),
                    ic_sd = sd(ic),
                    icir = mean(ic) / sd(ic),
                    hit_rate_pos = mean(ic > 0)),
                  by = regime_class]
cat("\nBAD vs NORMAL aggregate:\n")
print(agg)

bad <- agg[regime_class == "BAD"]
nor <- agg[regime_class == "NORMAL"]
ic_mean_ratio <- bad$ic_mean / nor$ic_mean
icir_ratio    <- bad$icir / nor$icir
abs_icir_ratio <- abs(bad$icir) / abs(nor$icir)
cat(sprintf("\nIC mean ratio  (bad / normal): %.4f\n", ic_mean_ratio))
cat(sprintf("ICIR ratio      (bad / normal): %.4f\n", icir_ratio))
cat(sprintf("|ICIR| ratio    (bad / normal): %.4f\n", abs_icir_ratio))

# AX-001 v2 axis 3 threshold: bad/normal ic_ratio >= 1.5 (defense factor evidence)
# But R05 layer 5 is PURE OVERLAY scalar (Judge ruling AX-001 v2 N/A pure overlay)
# So this is supplementary signal-level evidence only.
ax001_axis3_assessment <- if (!is.na(abs_icir_ratio) && abs_icir_ratio >= 1.5) {
  "BAD_REGIME_STRONGER_AXIS3_PASS"
} else if (!is.na(abs_icir_ratio) && abs_icir_ratio >= 1.0) {
  "BAD_REGIME_COMPARABLE_AXIS3_NEUTRAL"
} else {
  "BAD_REGIME_WEAKER_AXIS3_FAIL_BUT_PURE_OVERLAY_NA"
}

cat(sprintf("\nAX-001 v2 axis 3 (signal level) assessment: %s\n", ax001_axis3_assessment))
cat("Judge ruling: AX-001 v2 N/A (R05 = pure overlay scalar, not defense factor)\n")
cat("This metric is supplementary signal-level evidence per Codex C6 escalation.\n")

# CRISIS bootstrap mean (Forge claim: 6.34)
crisis_panel <- ic_panel[regime_state == "CRISIS"]
cat(sprintf("\nCRISIS regime panel: n=%d rows, %d unique dates\n",
            nrow(crisis_panel), length(unique(crisis_panel$Date))))
if (nrow(crisis_panel) > 0) {
  crisis_r05_mean <- mean(crisis_panel$R05_Tail_Risk_Z, na.rm=TRUE)
  cat(sprintf("CRISIS regime R05_z mean: %.4f (Forge claim: 6.34)\n",
              crisis_r05_mean))
  # Forge claim: bootstrap mean of R05 score in CRISIS subgroup
  # Recompute as score average per (Date, ticker) in CRISIS regime
  crisis_score_per_date <- crisis_panel[, .(score_mean = mean(R05_Tail_Risk_Z, na.rm=TRUE)),
                                          by = Date]
  cat("CRISIS dates (per-date R05_z portfolio average):\n")
  print(crisis_score_per_date)
}

# Save JSON
out <- list(
  task_id = "WT-H20260513_001",
  agent = "architect",
  prereq = "bad_normal_IC_ratio_R05_source",
  signal = "R05_Tail_Risk_Z",
  method = "Spearman rank IC vs Ret_1m per (Date, regime)",
  monthly_ic_by_regime = as.list(ic_monthly[, .(n_months = .N,
                                                 ic_mean = mean(ic),
                                                 ic_sd = sd(ic),
                                                 icir = mean(ic) / sd(ic),
                                                 hit_rate_pos = mean(ic > 0)),
                                              by = regime]),
  bad_vs_normal_aggregate = as.list(agg),
  bad_normal_ic_ratio = ic_mean_ratio,
  bad_normal_icir_ratio = icir_ratio,
  bad_normal_abs_icir_ratio = abs_icir_ratio,
  ax001_v2_axis3_assessment = ax001_axis3_assessment,
  ax001_v2_judge_ruling = "N/A_PURE_OVERLAY (Judge phase2 adjudication WT-H20260513_001)",
  supplementary_use_only = TRUE,
  created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S+09:00")
)
write_json(out, "qepm/mailbox/worktask/WT-H20260513_001/architect_bad_normal_ic_ratio.json",
           pretty = TRUE, auto_unbox = TRUE)
cat("\n[saved] architect_bad_normal_ic_ratio.json\n")
