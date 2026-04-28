#==============================================================================
# Finalize alpha_package.json post-PIT-clean v2 (WT-D20260428_003 Iter 10 B)
#
# v2 metrics dramatically improved vs v1 (manual sign flip):
#   rank_ic 0.0188 → 0.0382 / ICIR 0.656 → 1.121 / NW-t 1.78 → 3.596 (PASS!)
#   D10-D1 -0.001 → +0.0033 (POSITIVE) / mono 0.346 → 0.673
#   Subperiod 100% pos / Single-axis ICIR Z_A4 = 1.218 (best, > composite)
#==============================================================================
suppressPackageStartupMessages({
  library(arrow); library(data.table); library(jsonlite)
})

WT_DIR <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot/qepm/mailbox/worktask/WT-D20260428_003"
ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"

panel <- readRDS(file.path(WT_DIR, "alpha_panel_v2_pit_clean.rds"))
panel[, sig_date := as.Date(sig_date)]
asof <- panel[sig_date == as.Date("2023-10-31")][order(-alpha)]
top50 <- head(asof, 50)
av <- as.list(setNames(round(top50$alpha, 4), top50$Ticker))
cv <- as.list(setNames(round(1/(1+exp(-1.5*top50$alpha)), 4), top50$Ticker))

pkg <- list(
  task_id = "WT-D20260428_003",
  wt_type = "discovery",
  iter = 10L,
  iter_track = "B",
  iter_name = "MAQGC_Multi_Axis_Growth_Quality_Composite",
  agent = "alpha_research_v1.2",
  agent_model = "Opus 4.7 (1M context)",
  pg1_eligibility = "certificate_required",
  discovery_of = setNames(list(), character(0)),
  parent_iters_archived = list(
    STR_1631_SYN_05 = "WT-D20260425_010 (Iter 5 multi-sleeve composite)",
    STR_1701 = "WT-D20260426_004 (Iter 11 Linear Tilt)",
    STR_1715 = "WT-D20260427_016 (Iter 31 grid sweep — current PG2 100%)"
  ),
  baseline_pg2 = "STR_1715 100% (User OVERRIDE_006 mandate)",
  signal_as_of = "2023-10-31",
  signal_as_of_note = "Originally requested 2023-11-30; pipeline month-end fallback to 2023-10-31 (data-availability). Forward 1M return ends 2023-11-30 — PIT-safe.",
  forecast_horizon = "1M",
  rebalance_frequency = "monthly",
  selection_objective = "icir",
  hypothesis_title = "KR Multi-Axis Growth Quality Composite (MAQGC) — AFP 2019 QMJ KR-adapted [PIT-clean v2]",
  hypothesis_summary = paste(
    "Iter 10 B-track parallel discovery — family-orthogonal to FIAPAS",
    "(investor_flow / liquidity_diffusion / accrual). MAQGC family = quality_multi_axis × growth.",
    "AX-004 named EXCLUSION (multi-axis quality composite + multi-sleeve permitted) honored via",
    "4-axis composite. Ex-ante 4 axes pre-registered with sign +1 each in Z_Score_Aligned space:",
    "(A1) Profitability = z(GPA + ROIC + NetMargin), (A2) Growth = z(RevenueG + EarningsG + SustainableG),",
    "(A3) Safety = z(D/E_Aligned + EarningsStability), (A4) CashFlowQuality = z(CFOA_Aligned + Accrual_Aligned).",
    "Composite = mean(A1..A4) equal-weight, no tuning. n_candidates_tried=3 (S1 ALL, S2 Prof+Safe, S3 Prof+Grow as alternative spec sweeps).",
    "v2 PIT-clean re-evaluation: load_month_factors() + Z_Score_Aligned exclusively (Codex C2/C3/C13/C15 fix)."
  ),
  primary_variant = "S1_ALL_4axes_PIT_CLEAN_V2",
  primary_variant_v1_comparison = "v1 (manual sign flip) → v2 (Z_Score_Aligned): rank_ic 0.0188→0.0382 / NW-t 1.78→3.60 / D10-D1 NEG→+0.0033 / monotonicity 0.346→0.673. PIT-clean methodology resurrected the alpha.",
  alternative_variants_documented = list(
    S1_ALL_4axes = list(
      sign_axis = "all +1 ex-ante in Z_Score_Aligned space",
      mechanism_citation = paste(
        "Asness-Frazzini-Pedersen (2019 RAS) Quality Minus Junk multi-axis composite /",
        "Lakonishok-Shleifer-Vishny (1994 JF) growth quality contrarian /",
        "Sloan (1996 AR) accrual reliability inverse / Dechow-Dichev (2002 AR) earnings quality"
      ),
      diagnostics = list(
        rank_ic = 0.03816,
        ic_sd = 0.118,
        icir = 1.121,
        nw_t_lag3 = 3.596,
        harvey_t_stat_pooled = 3.596,
        monotonicity_rank_cor = 0.6727,
        d10_d1_spread = 0.00328,
        decile_max_at = 9L,
        decile_returns_d1_to_d10 = c(0.00681, 0.01022, 0.00319, 0.00912, 0.00854, 0.01048, 0.01294, 0.01401, 0.01577, 0.01010),
        subperiod_stability = 1.0,
        subperiod_ics = list(
          p1_2008_2014 = list(rank_ic = 0.0638, icir = 1.646, n_months = 53L, pos_pct = 0.679),
          p2_2015_2019 = list(rank_ic = 0.0107, icir = 0.319, n_months = 39L, pos_pct = 0.590),
          p3_2020_2023 = list(rank_ic = 0.0286, icir = 1.297, n_months = 30L, pos_pct = 0.667)
        ),
        single_axis_icir = list(
          A1_Profitability = list(rank_ic = 0.0249, icir = 0.695, nw_t = 2.390),
          A2_Growth = list(rank_ic = 0.0224, icir = 0.855, nw_t = 2.506),
          A3_Safety = list(rank_ic = 0.0289, icir = 0.977, nw_t = 3.434),
          A4_CashFlowQuality = list(rank_ic = 0.0353, icir = 1.218, nw_t = 3.875)
        ),
        composite_vs_best_single = list(
          best_single_axis = "A4_CashFlowQuality",
          best_single_icir = 1.218,
          composite_icir = 1.121,
          composite_beats_best = FALSE,
          rf_a2_concern = TRUE,
          interpretation = "Composite ICIR (1.121) below best single axis A4 (1.218). RF-A2 partially flagged: composite does NOT beat best individual factor on ICIR. However composite Harvey-t (3.596) and stability profile may be more robust under multi-testing penalty."
        ),
        alpha_inheritance_cor_vs_Q08_proxy = 0.7228,
        n_months_evaluated = 122L,
        turnover_proxy_monthly = NA,
        dsr_pre = 1.121,
        dsr_post = 1.0035,
        n_candidates_tried = 3L
      ),
      result = "rank_ic=0.0382 / icir=1.121 / Harvey_t=3.596 PASS / D10-D1 +0.0033 / cert_4cond=3/4 PASS",
      verdict = paste(
        "GRADUATION BORDERLINE: rank_ic 0.0382 just below 0.04 (4.5% short),",
        "monotonicity 0.673 below 0.80, but Harvey-t 3.596 PASSES, ICIR 1.121 PASSES, subperiod 100% PASSES,",
        "DSR_post 1.00 PASSES, D10-D1 POSITIVE. Cert cond4 (3-of-3 specs pass Harvey-t 3.0):",
        "S1 PASS / S2 NW-t 2.63 < 3.0 FAIL / S3 NW-t 2.58 < 3.0 FAIL → 1/3 PASS, cond4 FAIL.",
        "AX-007 long-only top20 path: D10-D1 positive but small (+0.0033 monthly = +3.93% annual gross before cost),",
        "after 15bps cost × turnover may be negligible. Honest stance: alpha exists at PIT-clean level but",
        "graduation BORDERLINE FAIL. cert NOT ISSUED on cond4. Iter 11 mandate: extend cond4 satisfaction via",
        "axis residualization, or accept S1 alone as primary spec with cond4 reformulation."
      )
    ),
    S2_Prof_Safety = list(
      mechanism = "Drop Growth + CFQ axes; pure Profitability + Safety (AFP 2019 narrowed)",
      diagnostics = list(rank_ic = 0.0297, icir = 0.791, nw_t = 2.632),
      result = "MARGINAL FAIL — IC weak, NW-t 2.63 < 3.0"
    ),
    S3_Prof_Growth = list(
      mechanism = "Profitability + Growth only (omit Safety + CFQ)",
      diagnostics = list(rank_ic = 0.0266, icir = 0.789, nw_t = 2.575),
      result = "MARGINAL FAIL — Harvey-t 2.58 < 3.0"
    )
  ),
  alpha_vector = av,
  confidence_vector = cv,
  signal_matrix_ref = "stage_artifacts://WT_D20260428_003/alpha_scores.parquet",
  signal_matrix_ref_note = "alpha_scores.parquet is sig_date × Ticker × score full panel (39879 rows × 122 sig_dates × 717 unique tickers). RF-A7 compliant.",
  factor_specs = list(
    list(
      name = "S1_MAQGC_4axes_ALL_PIT_CLEAN",
      family = "quality_multi_axis × growth",
      axis_definitions = list(
        A1_Profitability = list(formula = "mean(z_aligned(GPA), z_aligned(ROIC), z_aligned(NetMargin))", sign = "+1", citation = "AFP 2019 QMJ profitability axis"),
        A2_Growth = list(formula = "mean(z_aligned(RevenueG), z_aligned(EarningsG), z_aligned(SustainableG))", sign = "+1", citation = "Lakonishok-Shleifer-Vishny 1994 contrarian growth quality"),
        A3_Safety = list(formula = "mean(z_aligned(D/E), z_aligned(EarningsStab))", sign = "+1", citation = "AFP 2019 safety axis (Aligned auto-flips D/E sign for IC < 0)"),
        A4_CashFlowQuality = list(formula = "mean(z_aligned(CFOA), z_aligned(Accrual))", sign = "+1", citation = "Sloan 1996 inverse + Dechow-Dichev 2002 (Aligned auto-flips Accrual for Sloan effect)")
      ),
      composite = "mean(A1, A2, A3, A4) equal-weight ex-ante in Aligned space",
      rank_ic = 0.0382,
      icir = 1.121,
      harvey_t = 3.596,
      pit_compliance = "PIT-C13/C14/C15 PASS via load_month_factors() + Z_Score_Aligned",
      selected = TRUE
    ),
    list(
      name = "S2_Prof_Safety",
      family = "quality_multi_axis (narrow QMJ)",
      composite = "mean(A1, A3)",
      rank_ic = 0.0297,
      icir = 0.791,
      harvey_t = 2.632,
      selected = FALSE,
      source = "axis_pruning_alternative"
    ),
    list(
      name = "S3_Prof_Growth",
      family = "quality × growth (LSV1994)",
      composite = "mean(A1, A2)",
      rank_ic = 0.0266,
      icir = 0.789,
      harvey_t = 2.575,
      selected = FALSE,
      source = "axis_pruning_alternative"
    )
  ),
  candidates_tried = list(
    list(name = "S1_MAQGC_4axes_ALL", rank_ic = 0.0382, t = 3.596, selected = TRUE, source = "ex_ante_pre_registered"),
    list(name = "S2_Prof_Safety", rank_ic = 0.0297, t = 2.632, selected = FALSE, source = "axis_pruning"),
    list(name = "S3_Prof_Growth", rank_ic = 0.0266, t = 2.575, selected = FALSE, source = "axis_pruning")
  ),
  pit_compliance = list(
    C1 = "PASS — walk-forward only via load_month_factors(sig_date)",
    C2 = "PASS — monthly forward return = close(month_end+1) / close(month_end) - 1",
    C3 = "PASS — per-month cross-sectional Z (no full-sample aggregate)",
    C4 = "PASS — quarterly 45d / annual May enforced upstream by FactorDB; load_month_factors uses validated FactorDB",
    C5 = "N/A — no overlay used at alpha layer",
    C9 = "PASS — sig_date d → applied (d, d+1m] via month-end Close lead",
    C10 = "PASS — 20d AvgTV PIT t-30..t-1 one-sided + LIQ 5e7 floor (mandate). LIQ 2e8 sensitivity = Iter 11 mandate (Codex C6)",
    C11 = "PASS — fundamental data lag enforced by FactorDB",
    C13 = "PASS — Z_Score_Aligned via FactorDB align_factor_direction (PIT-safe expanding window IC, no manual flip)",
    C14 = "PASS — Usable_Date <= sig_date (FactorDB align_factor_direction enforced via sig_date param, line 220-230 of factor_db_connector.R)",
    C15 = "PASS — load_month_factors() exclusively (v2 script)",
    note = "v1 script (DEPRECATED) used direct parquet read + manual `-Q15` `-Q05`. Codex C2/C3/C13/C14/C15 ACCEPT → v2 fix applied. v2 results dramatically improved: rank_ic 0.0188→0.0382, NW-t 1.78→3.60, D10-D1 negative→positive."
  ),
  signal_processing_summary = list(
    sig_dates_processed_unique = 122L,
    sig_dates_processed_target = 191L,
    universe_label = "KOSPI200_KOSDAQ150_intersection (K200 OR KQ150 == TRUE)",
    liquidity_floor_krw = 50000000L,
    coverage_min = 0.05,
    final_alpha_top_n = 50L,
    n_panel_rows_unique = 39879L,
    n_unique_tickers = 717L,
    asof_alpha_names = 50L,
    asof_alpha_universe_size_at_2023_10_31 = 344L
  ),
  optimizer_handoff_notes = list(
    "Alpha agent 산출물은 alpha_vector + confidence_vector + alpha_scores.parquet (Date × Ticker × score panel) 까지.",
    "Optimizer는 max_names=20 (user hard mandate), weight_bounds=[0, 1] enforce 해야 함.",
    "Risk Agent는 alpha_scores.parquet의 Ticker × score 신호로부터 covariance Σ + tail risk를 자체 추정 (alpha agent는 Σ 추정 금지).",
    "**ATTENTION (post-PIT-clean v2)**: alpha statistics PASS Harvey-t 3.0 + Subperiod 100% + DSR_post 1.00. D10-D1 +0.0033/month (≈+4% annual gross). rank_ic 0.0382 just below 0.04 graduation min. cert 4-cond cond4 (3-of-3 specs pass Harvey-t) FAIL because S2 (2.63) and S3 (2.58) both fall short by <0.5. S1 alone PASSES.",
    "AX-007 long-only top20 path: D10-D1 positive but modest. After 15bps cost × turnover (estimated 6-8x annual based on monthly rebalance and quality factor stability), net alpha may be 1-2% annual. Caution recommended. If used, sleeve allocation 10-15% paired with FIAPAS V2 or STR_1715 incumbent.",
    "Inheritance vs Q08_Composite_Quality: 0.723 (still high). Iter 11 mandate: residualize MAQGC against Q08 to extract orthogonal alpha contribution.",
    "Single-axis A4 (CashFlowQuality) ICIR 1.218 > composite 1.121 → composite does NOT beat best single (RF-A2 partial). A4 alone might be the cleanest signal — Iter 11 mandate: standalone A4 (CFOA + Accrual_Aligned) evaluation."
  ),
  family_orthogonality = list(
    fiapas_family_avoided = c("investor_flow", "liquidity_diffusion", "accrual"),
    maqgc_family = c("quality_multi_axis", "growth"),
    cross_family_overlap = "minimal vs FIAPAS (A4 uses Q05_Accrual fundamental quality — orthogonal to FIAPAS V2_F3 retail-accrual-MTC).",
    ax004_exclusion = "MULTI-AXIS COMPOSITE permitted by AX-004 EXCLUSION clause. 4-axis ex-ante pre-registered. Empirical PIT-clean ICIR 1.121 + Harvey-t 3.60 — alpha contribution validated.",
    inheritance_vs_Q08_concern = "0.723 spearman cor with FactorDB Q08_Composite_Quality. Iter 11: residualization against Q08 mandatory."
  ),
  graduation_check = list(
    rank_ic_target = 0.04,
    rank_ic_actual = 0.0382,
    rank_ic_pass = FALSE,
    rank_ic_short_pct = 4.5,
    icir_target = 0.20,
    icir_actual = 1.121,
    icir_pass = TRUE,
    subperiod_target = 0.50,
    subperiod_actual = 1.00,
    subperiod_pass = TRUE,
    harvey_t_target = 3.0,
    harvey_t_actual = 3.596,
    harvey_t_pass = TRUE,
    dsr_post_target = 0.50,
    dsr_post_actual = 1.0035,
    dsr_post_pass = TRUE,
    monotonicity_target = 0.80,
    monotonicity_actual = 0.6727,
    monotonicity_pass = FALSE,
    monotonicity_note = "rank-cor 0.673 < 0.80 — decile 9 = max (0.0158), decile 10 reverts to 0.0101 (still > decile 1).",
    overall = "BORDERLINE — 4/6 PASS (ICIR/subperiod/Harvey-t/DSR), 2/6 FAIL (rank_ic by 4.5%, monotonicity by 13%). Significant improvement vs v1 (3/6 → 4/6 PASS). Honest stance: graduation BORDERLINE — does NOT meet hard PG1 admission graduation criteria but alpha is clearly present."
  ),
  cert_4cond_check = list(
    cond1_inheritance_cor_lt_095 = list(actual = 0.7228, target = 0.95, pass = TRUE, note = "vs Q08_Composite_Quality parent proxy. < 0.95 PASS but high — Iter 11 mandate residualization."),
    cond2_factor_specs_ge_1 = list(actual = 3L, target = 1L, pass = TRUE),
    cond3_mechanism_ge_50chars = list(actual_chars = 280L, target = 50L, pass = TRUE),
    cond4_harvey_pass_ge_3 = list(actual_count = 1L, target = 3L, pass = FALSE, breakdown = list(S1 = 3.596, S2 = 2.632, S3 = 2.575), note = "S1 (primary) PASSES Harvey-t 3.596. S2 (2.63) and S3 (2.58) marginally below 3.0. cond4 requires 3-of-3 specs PASS Harvey-t which is a strict bar — S1 alone is empirically PIT-clean valid."),
    all_4cond_technical_pass = FALSE,
    cond4_caveat = "If cond4 reformulated as 'at least 1 spec PASS Harvey-t 3.0' (looser), MAQGC S1 alone would PASS. But strict 3-of-3 reading is what prior FIAPAS V2 also failed. Cert NOT ISSUED to maintain consistency with FIAPAS V2 standards."
  ),
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
  pipeline_version = "alpha_research_v1.2_v6.31_charter_post_codex_pit_clean_v2",
  post_codex_finalized = TRUE,
  codex_critic_audit = list(
    performed_at = "2026-04-28T15:27:14+09:00",
    stance = "REJECT",
    veto_flag = FALSE,
    n_critical_concerns = 8L,
    n_high = 5L,
    n_medium = 3L,
    q_lead_escalate_triggered = TRUE,
    q_lead_escalate_reason = "HIGH severity concerns ≥ 5",
    agent_response_protocol = "Charter §8 No Silent Override + Charter §10 Role Card",
    n_accept = 5L,
    n_partial = 2L,
    n_rebuttal = 1L,
    concern_breakdown = list(
      C1_RF_A7 = list(severity = "HIGH", classification = "ACCEPT", action = "alpha_scores.parquet rewritten as time-series panel (39879 rows × 122 sig_dates after v2 rebuild)"),
      C2_PIT_C13_manual_sign_flip = list(severity = "HIGH", classification = "ACCEPT", action = "v2 PIT-clean script uses Z_Score_Aligned exclusively. **CRITICAL FINDING**: This fix dramatically improved metrics (rank_ic 0.0188→0.0382, NW-t 1.78→3.60). v1 manual flip was actually WRONG sign in some sub-periods. Codex was correct."),
      C3_PIT_C15_load_month_factors = list(severity = "HIGH", classification = "ACCEPT", action = "v2 uses load_month_factors() with internal Usable_Date enforcement"),
      C4_graduation_silent_override = list(severity = "HIGH", classification = "ACCEPT", action = "optimizer_handoff_notes wording revised to remove 'deployable quality tilt' framing"),
      C5_AX007_long_only_top20 = list(severity = "HIGH", classification = "PARTIAL", action = "post-v2 D10-D1 POSITIVE (+0.0033) — long-only top20 NOT broken anymore. AX-007 path may be feasible. Codex's C5 was based on v1 NEGATIVE D10-D1 which was an artifact of manual sign flip error."),
      C6_LIQ_5e7_vs_2e8 = list(severity = "MEDIUM", classification = "PARTIAL", action = "WT mandate is 5e7. LIQ 2e8 sensitivity Iter 11 mandate."),
      C7_RF_A2_A4 = list(severity = "MEDIUM", classification = "ACCEPT", action = "v2 reports single-axis ICIR for all 4 axes. RF-A2 finding: composite (1.121) does NOT beat best single (A4=1.218)."),
      C8_AX008_artifact_completeness = list(severity = "MEDIUM", classification = "PARTIAL_REBUTTAL", action = "challenge_note + artifact_lineage CREATED. risk/optimizer artifacts are downstream — outside alpha scope per Charter §10.")
    ),
    weakest_assumption_response = "ACCEPTED + FIXED. alpha_scores.parquet rewritten with sig_date column.",
    pit_audit_response = "ALL FIXED in v2. v1 results superseded.",
    rationalization_red_flags_response = "1 wording revision applied; others factual statements retained.",
    additional_finding = "Codex C2 ACCEPT led to material improvement (not just process compliance): manual `-Z` was actively harming the signal because Z_Score_Aligned IC-based direction was already correct. Method-shopping concern is INVERTED — manual override was *worse* than canonical. Lesson L-224 captures this."
  )
)

write_json(pkg, file.path(WT_DIR, "alpha_package.json"),
           pretty = TRUE, auto_unbox = TRUE, dataframe = "rows", null = "null")
cat("alpha_package.json finalized (v2 PIT-clean)\n")
cat(sprintf("File size: %s bytes\n", file.info(file.path(WT_DIR, "alpha_package.json"))$size))
