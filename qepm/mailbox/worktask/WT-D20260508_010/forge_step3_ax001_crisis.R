#==============================================================================
# WT-D20260508_010 Forge Step 3 — AX-001 v2 conditional defense + crisis decomposition
#
# AX-001 v2 conditions for Defense classification:
#   1. crisis_alpha (excess return in crisis regimes) > 0
#   2. Core 대비 MDD 완화 (combined MDD < pure Hybrid MDD)
#   3. bad/normal IC ratio > 1.0
#
# R14_DUVOL is classified as Diversifier (NOT Defense) per Optimizer challenge
#==============================================================================

suppressPackageStartupMessages({
  library(data.table); library(jsonlite); library(PerformanceAnalytics); library(xts)
})

setwd("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")

WT_ID <- "WT-D20260508_010"
SA_DIR <- file.path("stage_artifacts", WT_ID)
FORGE_DIR <- file.path(SA_DIR, "forge")

cat("================================================================\n")
cat("[FORGE STEP 3] AX-001 v2 + crisis decomposition + stress periods\n")
cat("================================================================\n")

# Load 4-ratio combined returns
ratios <- c("A", "B", "C", "D")
pcts <- c(0, 10, 20, 30)
rets_list <- list()
for (i in seq_along(ratios)) {
  fp <- file.path(FORGE_DIR, sprintf("%s_%dpct/03_period_returns.csv", ratios[i], pcts[i]))
  pr <- fread(fp)
  pr[, date := as.Date(date)]
  rets_list[[ratios[i]]] <- pr[, .(date, ret_net)]
}

# Load Hybrid baseline (S0 STR_1715_AR alone for crisis ref)
hyb <- fread("qepm/mailbox/worktask/WT-P20260505_001/output/S0_baseline/03_period_returns.csv")
hyb[, date := as.Date(date)]

# Crisis windows (from book_state.json + reference_stress_periods.md)
crisis_windows <- list(
  GFC_2008 = list(start = "2008-09-01", end = "2009-03-01"),
  Euro_2011 = list(start = "2011-08-01", end = "2011-12-01"),
  China_2015 = list(start = "2015-08-01", end = "2016-02-01"),
  COVID_2020 = list(start = "2020-02-01", end = "2020-04-01"),
  Stagflation_2022 = list(start = "2022-01-01", end = "2022-12-01"),
  KR_TradeWar_2025 = list(start = "2025-04-01", end = "2025-09-01")
)

# Pre/During R14_DUVOL window: only Stagflation_2022, KR_TradeWar_2025 covered
# (R14_DUVOL active 2021-06~2026-04)

cat("\n[3a] AX-001 v2 conditional defense audit (R14_DUVOL across 4 ratios)\n")

ax001_results <- list()
for (rname in ratios) {
  pct <- pcts[match(rname, ratios)]
  res_combo <- rets_list[[rname]]

  # Joint window (R14_DUVOL active)
  jw_start <- as.Date("2021-07-01")  # first Hybrid date with R14_DUVOL active
  jw_end <- as.Date("2026-05-01")
  combo_jw <- res_combo[date >= jw_start & date <= jw_end]
  hyb_jw <- hyb[date >= jw_start & date <= jw_end]

  # MDD in joint window
  mdd_combo <- as.numeric(maxDrawdown(xts(combo_jw$ret_net, order.by = combo_jw$date)))
  mdd_hyb_alone <- as.numeric(maxDrawdown(xts(hyb_jw$ret_net, order.by = hyb_jw$date)))
  mdd_relief_pp <- (mdd_hyb_alone - mdd_combo) * 100  # positive = relief

  # Crisis subperiods within joint window
  crisis_alpha_list <- list()
  for (cname in names(crisis_windows)) {
    cs <- as.Date(crisis_windows[[cname]]$start)
    ce <- as.Date(crisis_windows[[cname]]$end)
    if (ce < jw_start || cs > jw_end) next  # skip windows outside R14_DUVOL active range
    cs_eff <- max(cs, jw_start); ce_eff <- min(ce, jw_end)
    combo_c <- combo_jw[date >= cs_eff & date <= ce_eff, ret_net]
    hyb_c <- hyb_jw[date >= cs_eff & date <= ce_eff, ret_net]
    if (length(combo_c) == 0L) next
    crisis_alpha_list[[cname]] <- list(
      start = as.character(cs_eff), end = as.character(ce_eff),
      n_obs = length(combo_c),
      ret_combo_cum = round(prod(1 + combo_c) - 1, 4),
      ret_hybrid_alone_cum = round(prod(1 + hyb_c) - 1, 4),
      crisis_alpha_pp = round((prod(1 + combo_c) - prod(1 + hyb_c)) * 100, 4)
    )
  }

  # Sum crisis alpha
  crisis_alpha_total <- sum(sapply(crisis_alpha_list, function(x) x$crisis_alpha_pp), na.rm = TRUE)

  # AX-001 v2 condition checks (all 3 must PASS for Defense, but R14_DUVOL is Diversifier per Optimizer)
  cond1_crisis_alpha_positive <- crisis_alpha_total > 0
  cond2_mdd_relief <- mdd_relief_pp > 0
  cond3_bad_normal_ic_ratio <- "N/A_only_60m_no_4regime_decomposition"

  # Defense / Diversifier classification
  if (rname == "A") {
    role <- "BASELINE_NO_R14_DUVOL"
  } else {
    role <- if (cond1_crisis_alpha_positive && cond2_mdd_relief) {
      "Diversifier_PARTIAL_PASS_AX001v2"  # 2 of 3 conditions met (no Defense classification)
    } else {
      "Diversifier_FAIL_AX001v2"
    }
  }

  ax001_results[[rname]] <- list(
    ratio = rname,
    r14_duvol_pct = pct,
    crisis_alpha_total_pp = round(crisis_alpha_total, 4),
    crisis_alpha_positive = cond1_crisis_alpha_positive,
    mdd_combo_pct = round(mdd_combo * 100, 4),
    mdd_hybrid_alone_pct = round(mdd_hyb_alone * 100, 4),
    mdd_relief_pp = round(mdd_relief_pp, 4),
    mdd_relief_positive = cond2_mdd_relief,
    bad_normal_ic_ratio = cond3_bad_normal_ic_ratio,
    role_classification = role,
    crisis_decomposition = crisis_alpha_list
  )

  cat(sprintf("  [%s %d%%] crisis_alpha_total=%.4fpp / mdd_relief=%.4fpp / role=%s\n",
              rname, pct, crisis_alpha_total, mdd_relief_pp, role))
}

write_json(ax001_results, file.path(FORGE_DIR, "ax001_v2_conditional_defense.json"),
           pretty = TRUE, auto_unbox = TRUE)
cat("[saved] forge/ax001_v2_conditional_defense.json\n")

# ----------------------------------------------------------------------
# [3b] Stress periods coverage table
# ----------------------------------------------------------------------
cat("\n[3b] Stress periods coverage (8 reference + R14_DUVOL active subset)\n")

stress_8 <- list(
  IMF_1997 = list(start = "1997-07-01", end = "1998-12-01"),
  DotCom_2000 = list(start = "2000-03-01", end = "2002-09-01"),
  GFC_2008 = list(start = "2008-09-01", end = "2009-03-01"),
  Euro_2011 = list(start = "2011-08-01", end = "2011-12-01"),
  China_2015 = list(start = "2015-08-01", end = "2016-02-01"),
  COVID_2020 = list(start = "2020-02-01", end = "2020-04-01"),
  Stagflation_2022 = list(start = "2022-01-01", end = "2022-12-01"),
  KR_TradeWar_2025 = list(start = "2025-04-01", end = "2025-09-01")
)

stress_table <- list()
for (sname in names(stress_8)) {
  cs <- as.Date(stress_8[[sname]]$start); ce <- as.Date(stress_8[[sname]]$end)
  hyb_period_start <- as.Date("2005-02-01")
  r14_period_start <- as.Date("2021-07-01")
  hyb_observable <- ce >= hyb_period_start
  r14_observable <- ce >= r14_period_start && cs <= as.Date("2026-04-30")
  stress_table[[sname]] <- list(
    start = as.character(cs), end = as.character(ce),
    hybrid_observable = hyb_observable,
    r14_duvol_observable = r14_observable,
    in_optimizer_stress_6_8_window = hyb_observable
  )
}
write_json(stress_table, file.path(FORGE_DIR, "stress_periods_coverage.json"),
           pretty = TRUE, auto_unbox = TRUE)
cat("[saved] forge/stress_periods_coverage.json\n")
cat(sprintf("  Hybrid observable: %d/8\n",
            sum(sapply(stress_table, function(x) x$hybrid_observable))))
cat(sprintf("  R14_DUVOL observable: %d/8\n",
            sum(sapply(stress_table, function(x) x$r14_duvol_observable))))

# ----------------------------------------------------------------------
# [3c] Cost-adjusted SR final table (rebalance turnover impact)
# ----------------------------------------------------------------------
cat("\n[3c] Cost-adjusted SR final (already net of 15bps in component returns)\n")
cat("  - Hybrid S3 already includes 15bps cost (per period_returns ret_net column)\n")
cat("  - R14_DUVOL sleeve already includes 15bps × 2 × turnover (round-trip)\n")
cat("  - Combined ret_net = w_h*ret_h + w_r*ret_r14 = naturally cost-adjusted\n")

cat("\n[FORGE STEP 3] DONE\n")
