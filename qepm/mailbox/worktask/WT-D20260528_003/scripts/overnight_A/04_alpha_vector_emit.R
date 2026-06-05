#==============================================================================
# WT-D20260528_003 Hypothesis A — Step 4
# - Emit alpha_vector (전 universe, snapshot 2023-11-30, D43_neut+D44_neut composite ICIR-weighted)
# - Emit confidence_vector
# - Write alpha_scores.parquet (panel-wise scores)
# - alpha_validation.json (Comprehensive)
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
})

t0 <- Sys.time()

PROJ <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(PROJ)

WT_ID <- "WT-D20260528_003"
OUT_DIR <- "stage_artifacts/WT_D20260528_003_overnight_A"

panel_dt <- as.data.table(readRDS(file.path(OUT_DIR, "panel_neut.rds")))
ic_wf    <- as.data.table(readRDS(file.path(OUT_DIR, "ic_wf.rds")))

# ---- Snapshot sig_date for alpha_vector ----
snap_sd <- as.Date("2023-11-30")
cat("[Step 4] alpha_vector snapshot sig_date =", as.character(snap_sd), "\n")

snap <- panel_dt[sig_date == snap_sd]
cat("  snap N =", nrow(snap), "\n")

# Latest walk-forward weights
last_w <- ic_wf[sig_date == max(sig_date)]
w43 <- last_w$w_43_wf
w44 <- last_w$w_44_wf
cat(sprintf("  WF weights (latest pre-snap): w43=%+.3f w44=%+.3f\n", w43, w44))

# Composite alpha score per ticker = w43*Z43_neut + w44*Z44_neut
snap[, alpha_score := w43 * Z43_neut + w44 * Z44_neut]

# z-normalize alpha_score to ~ [-3, +3] range
snap[, alpha_score_z := (alpha_score - mean(alpha_score, na.rm=TRUE)) /
                         sd(alpha_score, na.rm=TRUE)]

# Multi-sleeve top 20 (top10 D43 + top10 D44 not in A)
ord43 <- snap[order(-Z43_neut), Ticker]
ord44 <- snap[order(-Z44_neut), Ticker]
sleeve_A <- head(ord43, 10)
sleeve_B <- head(setdiff(ord44, sleeve_A), 10)
multi_top20 <- c(sleeve_A, sleeve_B)

cat("  Multi-sleeve top 20:\n")
cat("    Sleeve A (D43 top 10):", paste(sleeve_A, collapse=", "), "\n")
cat("    Sleeve B (D44 top 10):", paste(sleeve_B, collapse=", "), "\n")

# ---- alpha_vector (전수 score, composite Z) ----
alpha_vector <- setNames(round(snap$alpha_score_z, 4), snap$Ticker)
alpha_vector <- alpha_vector[order(-alpha_vector)]

# ---- confidence_vector ----
# 기본: 0.50, 신호 절대값 기반 [0.45, 0.75]
snap[, conf := pmin(0.75, pmax(0.45, 0.55 + 0.05 * abs(alpha_score_z)))]
confidence_vector <- setNames(round(snap$conf, 3), snap$Ticker)
confidence_vector <- confidence_vector[order(-confidence_vector)]

cat("  alpha_vector N=", length(alpha_vector), " range=[",
    round(min(alpha_vector),3), ",", round(max(alpha_vector),3), "]\n")
cat("  confidence_vector N=", length(confidence_vector), "\n")

# ---- alpha_scores.parquet (panel-wide composite) ----
panel_dt[, alpha_score := NA_real_]
ic_panel <- ic_wf[, .(sig_date, w_43_wf, w_44_wf)]
panel_wf <- merge(panel_dt, ic_panel, by = "sig_date", all.x = TRUE)
panel_wf[!is.na(w_43_wf), alpha_score := w_43_wf * Z43_neut + w_44_wf * Z44_neut]
panel_wf <- panel_wf[!is.na(alpha_score)]

# z-normalize per sig_date
panel_wf[, alpha_score_z := (alpha_score - mean(alpha_score, na.rm=TRUE)) /
                             sd(alpha_score, na.rm=TRUE), by = sig_date]

out_panel <- panel_wf[, .(sig_date, Ticker, Sector_Lv2,
                          Z43_neut, Z44_neut,
                          alpha_score, alpha_score_z,
                          fwd_1m)]
out_panel[, alpha_score := round(alpha_score, 6)]
out_panel[, alpha_score_z := round(alpha_score_z, 6)]
write_parquet(out_panel, file.path(OUT_DIR, "alpha_scores.parquet"))
cat("  alpha_scores.parquet saved:", file.path(OUT_DIR, "alpha_scores.parquet"),
    " rows=", nrow(out_panel), "\n")

# ---- alpha_validation.json ----
step1 <- fromJSON(file.path(OUT_DIR, "step1_summary.json"), simplifyVector = FALSE)
step2 <- fromJSON(file.path(OUT_DIR, "step2_summary.json"), simplifyVector = FALSE)
step3 <- fromJSON(file.path(OUT_DIR, "step3_summary.json"), simplifyVector = FALSE)

# Graduation criteria check (from request.json)
graduation_check <- list(
  min_rank_ic = list(
    threshold = 0.04,
    actual_d43_neut = step1$ic_summary$D43_neut$ic_mean,
    actual_d44_neut = step1$ic_summary$D44_neut$ic_mean,
    actual_composite_wf = step2$walk_forward_metrics$Composite_WF$ic_mean,
    PASS = (step2$walk_forward_metrics$Composite_WF$ic_mean >= 0.04)
  ),
  min_icir = list(
    threshold = 0.20,
    actual_d43_neut_wf = step2$walk_forward_metrics$D43_neut_WF$icir,
    actual_d44_neut_wf = step2$walk_forward_metrics$D44_neut_WF$icir,
    actual_composite_wf = step2$walk_forward_metrics$Composite_WF$icir,
    PASS = (step2$walk_forward_metrics$Composite_WF$icir >= 0.20)
  ),
  min_subperiod_stability = list(
    threshold = 0.5,
    actual_d43 = step2$subperiod$stability_score_D43,
    actual_d44 = step2$subperiod$stability_score_D44,
    PASS = (step2$subperiod$stability_score_D43 >= 0.5)
  ),
  min_harvey_t_stat = list(
    threshold = 3.0,
    pass_count = step2$harvey_check$pass_count,
    max_t = max(c(step2$harvey_check$D43_neut_WF$t,
                  step2$harvey_check$D44_neut_WF$t,
                  step2$harvey_check$Composite_WF$t)),
    PASS = (max(c(step2$harvey_check$D43_neut_WF$t,
                  step2$harvey_check$D44_neut_WF$t,
                  step2$harvey_check$Composite_WF$t)) >= 3.0)
  ),
  min_deflated_sharpe_ratio = list(
    threshold = 0.5,
    actual = step2$dsr_pvalue,
    PASS = (step2$dsr_pvalue >= 0.5)
  ),
  monotonicity = list(
    threshold = 0.7,
    actual_d43 = step3$monotonicity$D43_neut,
    actual_d44 = step3$monotonicity$D44_neut,
    PASS = (step3$monotonicity$D43_neut >= 0.7)
  )
)

# Overall verdict
n_pass <- sum(sapply(graduation_check, function(g) isTRUE(g$PASS)))
n_total <- length(graduation_check)

overall_verdict <- if (n_pass == n_total) "PASS" else if (n_pass >= n_total - 1) "MARGINAL_FAIL" else "FAIL"

cat("\n[Graduation Criteria]\n")
for (nm in names(graduation_check)) {
  g <- graduation_check[[nm]]
  cat(sprintf("  %-30s PASS=%s\n", nm, isTRUE(g$PASS)))
}
cat(sprintf("\n  Overall verdict: %s (%d / %d PASS)\n", overall_verdict, n_pass, n_total))

# Red Flags
red_flags <- list()
if (step2$subperiod$D43_neut$p3_2020_2023$icir > step2$walk_forward_metrics$D43_neut_WF$icir * 1.5) {
  red_flags <- c(red_flags, list(list(
    id = "RF-A3",
    severity = "HIGH",
    detail = sprintf("D43_neut recent p3 ICIR=%.3f vs overall ICIR=%.3f (>1.5x)",
                     step2$subperiod$D43_neut$p3_2020_2023$icir,
                     step2$walk_forward_metrics$D43_neut_WF$icir)
  )))
}
if (step3$single_vs_multi$rf_a2_trigger) {
  red_flags <- c(red_flags, list(list(
    id = "RF-A2",
    severity = "MEDIUM",
    detail = sprintf("Multi-sleeve %+.1f%% improvement vs best single (negative — composite WORSE)",
                     step3$single_vs_multi$improvement_pct)
  )))
}
if (step3$monotonicity$D43_neut < 0.5 || step3$monotonicity$D44_neut < 0.5) {
  red_flags <- c(red_flags, list(list(
    id = "MONO_COLLAPSE",
    severity = "HIGH",
    detail = sprintf("Decile monotonicity collapse: D43_neut=%.3f, D44_neut=%.3f (negative or near-zero)",
                     step3$monotonicity$D43_neut, step3$monotonicity$D44_neut)
  )))
}
if (step3$turnover$annualized_2way > 6.0) {
  red_flags <- c(red_flags, list(list(
    id = "TO_DISCIPLINE",
    severity = "MEDIUM",
    detail = sprintf("Annualized 2-way turnover %.2f > 6.0/yr (Trend P6 Implementation Discipline)",
                     step3$turnover$annualized_2way)
  )))
}
if (step3$sector_diagnostics$max_sector_share$mean > 0.30) {
  red_flags <- c(red_flags, list(list(
    id = "RF-A5_SECTOR",
    severity = "MEDIUM",
    detail = sprintf("Max sector share mean=%.2f median=%.2f (concentration risk)",
                     step3$sector_diagnostics$max_sector_share$mean,
                     step3$sector_diagnostics$max_sector_share$median)
  )))
}

cat(sprintf("\n[Red Flags] %d total\n", length(red_flags)))
for (rf in red_flags) cat(sprintf("  [%s] %s — %s\n", rf$severity, rf$id, rf$detail))

# ---- Compose alpha_validation.json ----
alpha_validation <- list(
  task_id = WT_ID,
  hypothesis = "A (Distribution Moments Pure: D43_Skewness + D44_Kurtosis multi-sleeve)",
  snapshot_sig_date = as.character(snap_sd),
  signal_cutoff_lockbox = "2023-12-22",
  universe = "KOSPI200 union KOSDAQ150",
  liquidity_floor_won_20d_avg = 2e8,
  factors_used = c("D43_Skewness", "D44_Kurtosis"),
  factor_db_build_hash_tag = "factor_db_v2_pit_safe",

  pit_assertions = list(
    factor_load = "load_month_factors() — align_factor_direction PIT-safe (Usable_Date <= sig_date)",
    sig_date_cutoff = "Date <= 2023-12-22 (alpha-research lockbox per lockbox-scope.md)",
    walk_forward = "Expanding ICIR weights: w(t) = ICIR computed on IC ≤ t-1 only (36m burn-in)",
    sector_neutralize = "OLS residual per sig_date (cross-section, no time leak)",
    forward_return = "Next-month-end close / current-month-end close - 1",
    pit_clean = TRUE,
    c1_c15_assertion = "C1 expanding rolling / C13 Z_Score_Aligned / C14 IC Usable_Date / C15 load_month_factors()"
  ),

  step1_summary = step1,
  step2_summary = step2,
  step3_summary = step3,
  graduation_criteria_check = graduation_check,
  overall_verdict = overall_verdict,
  red_flags = red_flags,

  multi_sleeve_design = list(
    rationale = "AX-007 회피 의도 — single sleeve top20 long-only KR mechanism break 우회",
    sleeve_A_skewness = list(factor = "D43_Skewness", top_k = 10, snapshot = sleeve_A),
    sleeve_B_kurtosis = list(factor = "D44_Kurtosis", top_k = 10, snapshot = sleeve_B),
    cross_corr_neut_mean = step1$cor_neut$mean,
    cross_corr_neut_median = step1$cor_neut$median
  ),

  ax_007_check = list(
    structure = "multi_sleeve",
    sleeve_count = 2,
    per_sleeve_size = 10,
    note = "multi_sleeve 적용 but performance shows worse than best single — RF-A2 mechanism collapse"
  ),

  ax_001_v2_check = step2$ax_001_v2_regime,

  honest_assessment = list(
    one_sentence_verdict = "Distribution moments pure multi-sleeve fails graduation: monotonicity collapse + Harvey-t 0/5 + DSR p=0.376 + decile spread sign reversal + composite WORSE than best single.",
    primary_failure_modes = c(
      "Monotonicity collapse: D43 -0.20 / D44 -0.46 (bottom decile outperforms top)",
      "Harvey-Liu-Zhu 0/5 PASS (max t=2.18 vs threshold 2.58 Bonferroni n_trials=5)",
      "Multi-sleeve RF-A2: -33% SR vs best single (mechanism failure)",
      "Cost-adjusted SR_ann = +0.20 (near-zero net alpha)",
      "Annualized 2-way turnover 6.98 > 6.0/yr (Implementation Discipline)"
    ),
    salvage_signals = c(
      "AX-001 v2 strong PASS: bad/normal IC ratio D43=+3.61, D44=+7.41 (defense alpha 가능성)",
      "Subperiod p3 (2020-23) ICIR D43=0.46, recent regime strong (RF-A3 trigger)",
      "D43_neut WF Bootstrap CI95 [+0.0042, +0.0253] excludes 0",
      "Cross-corr D43-D44 neut mean 0.34 (orthogonal-ish, design valid in concept)"
    ),
    interpretation = paste(
      "Boyer-Mitton-Vorkink 2010 idiosyncratic skewness anomaly 가설은 KR에서 정반대 작동.",
      "Decile 1 (low skewness = stable / 비-lottery 종목) > Decile 10 (high skewness = lottery 종목).",
      "Bali-Murray 2013 kurtosis tail risk premium도 동일 — KR retail-driven 시장은 lottery preference 강함.",
      "Cross-section IC가 양수임에도 portfolio top20 decile 단조성 negative — 신호는 약하게 cross-sectional 정보 보유하나",
      "top-decile 집중이 alpha 발현 메커니즘 아님. Multi-sleeve 회피도 effectivity 입증 X."
    ),
    recommendation = "TERMINATE this hypothesis — graduation FAIL, mechanism not validated, no path to Deployment WT."
  )
)

write_json(alpha_validation, file.path(OUT_DIR, "alpha_validation.json"),
           pretty = TRUE, auto_unbox = TRUE)

cat("\n[Step 4] alpha_validation.json saved\n")

# Save snap for emit step
saveRDS(snap, file.path(OUT_DIR, "snap_2023_11_30.rds"))
saveRDS(list(alpha_vector = alpha_vector,
             confidence_vector = confidence_vector,
             multi_top20 = multi_top20,
             sleeve_A = sleeve_A,
             sleeve_B = sleeve_B,
             w43 = w43, w44 = w44),
        file.path(OUT_DIR, "emit_payload.rds"))

cat("\n[Step 4 DONE] elapsed:", round(as.numeric(Sys.time() - t0, units = "secs"), 1), "s\n")
