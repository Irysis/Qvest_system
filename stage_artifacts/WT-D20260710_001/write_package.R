# write_package — assemble alpha_package_draft.json + alpha_validation.json
suppressMessages({library(data.table); library(jsonlite)})
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
SA <- file.path(ROOT,"stage_artifacts","WT-D20260710_001")
WT <- file.path(ROOT,"qepm","mailbox","worktask","WT-D20260710_001")
res <- readRDS(file.path(SA,"screen_result.rds")); stash <- readRDS(file.path(SA,"finalize_stash.rds"))
sup <- readRDS(file.path(SA,"supplement_tab.rds"))
fin <- res$fin; sel <- res$sel; axtab <- res$axtab
ew <- fin$diag_ew_universe; ct <- fin$diag_cap_tier

rnd <- function(x,d=4) if(is.null(x)||length(x)==0||is.na(x)) NA else round(as.numeric(x),d)
selected_axes <- res$selected_axes
isw_norm <- round(res$isw/sum(res$isw),3)

factor_specs <- list(list(
  factor_family = "multi_axis_MID_concentrated_composite",
  proxy = paste0("6-family within-tier-z composite (best-of-family, MID-live): ",
                 paste(sprintf("%s[%s,w=%.2f]", sel$axis, sel$family, isw_norm), collapse=" + ")),
  formula = paste0("comp = (sum_k w_k * z_tier(axis_k)) * tier_mult[MEGA=0.25,MID=1.0,OTHER=0.5]; ",
                   "z_tier = within-tier(MEGA1-10/MID11-30/OTHER31+) cross-sectional z (size-confound removed); ",
                   "w_k = IS(<=2018-12) whole-univ canonical-PORT_t, clipped>=0, normalized; top-25 EW long-only"),
  axes = as.list(sel$axis), axis_families = as.list(sel$family), axis_weights = as.list(isw_norm),
  lag_rule = "factor DB Z_Score_Aligned PIT (Usable_Date<=sig_date expanding IC direction); tier from Size(t); Ret_1m=forward(t+1). lag1 stress IC 0.028 < real 0.053 (PIT graceful)",
  winsorization = "factor-DB standardized (3std in builder) + re-std sd=1 post direction-align",
  neutralization = "within-tier z (MEGA/MID/OTHER) removes cross-tier size confound",
  economic_rationale = paste0("Prior cap-tier localization: alpha lives in MID tier (rank 11-30, LS t~3.0) and MEGA top-10 is signal-dead. ",
    "Hypothesis: a genuinely MULTI-AXIS (6 distinct families: value/revision/momentum/reversal/quality/liquidity) MID-concentrated composite ",
    "might exceed the ~2.4 single-axis mid-cap ceiling. Test result: it does NOT — cap-w PORT_t 2.08 < incumbent score_eff 2.75 < HARD 2.95. ",
    "MID emphasis mechanically raised MID weight 0.086->0.199 and MID gross contrib 0.023->0.043/yr, but cap-w post-2017 active turned NEGATIVE (-0.88): ",
    "adding MID-live orthogonal axes shifts weight toward benchmark-underweight names, increasing tracking divergence vs the mega-cap-dominated cap-w KOSPI200 without net cap-w active gain."),
  weight_theta = 1,
  redundancy_cluster_id = sprintf("distinct from incumbent score_eff (avg cross-sec cor=%.3f — genuinely more orthogonal than prior tier-restriction 0.973), but cap-w outcome worse", res$cor_vs_scoreeff),
  references = list("cap-tier localization diagnostic 2026-07-06 (WT-D20260706_MIDCAP)",
                    "measurement-graduation §6 (long-only cross-sectional selection cannot escape cap-w mega-cap benchmark)",
                    "Harvey-Liu-Zhu 2016 (multiple-testing hurdle)")
))

# full variant table (cap-w) for transparency
variant_table <- lapply(seq_len(nrow(sup)), function(i) as.list(sup[i]))

diagnostics <- list(
  canonical_port_t_nw_lag3 = rnd(fin$portfolio_alpha_t_nw_lag3),
  canonical_port_t_pvalue = rnd(stash$capw_pval),
  canonical_n_months = fin$n_months,
  canonical_ir = rnd(fin$information_ratio),
  canonical_net_sr = rnd(fin$net_sr),
  canonical_turnover_annual = rnd(fin$turnover_annual,2),
  canonical_post2017_capw_t = rnd(res$post2017_capw_t),
  rank_ic = rnd(res$rank_ic), icir = rnd(res$icir,3), harvey_t_stat_rank_ic = rnd(res$harvey_t,3),
  subperiod_ic = list(sp_2004_2015=rnd(stash$sp1), sp_2015_2020=rnd(stash$sp2),
                      sp_2020_2026=rnd(stash$sp3), post2017=rnd(stash$sp17)),
  subperiod_stability = rnd(stash$subperiod_stability,3),
  post_neutralization_ic = rnd(res$rank_ic),
  turnover_proxy_annual = rnd(fin$turnover_annual,2),
  orthogonality_cor_vs_score_eff = rnd(res$cor_vs_scoreeff,3),
  dual_basis = list(
    note = "v8.3 dual-basis: cap-w(bench) is HARD-gate authoritative; EW-universe & cap_tier are non-binding diagnostics.",
    capw_benchmark = list(basis="cap-w KOSPI200 (forward-shifted, anchor-verified vs prior 2.40)",
      port_t = rnd(fin$portfolio_alpha_t_nw_lag3), post2017_t = rnd(res$post2017_capw_t),
      verdict = "FAIL vs 2.95 HARD and vs incumbent score_eff 2.75"),
    ew_universe = list(basis="EW-universe (pre-liquidity-filter panel, equal-weight) — fair peer benchmark",
      port_t = rnd(ew$portfolio_alpha_t_nw_lag3), post2017_t = rnd(ew$post2017_t_nw_lag3),
      oos_retention_approx = rnd(ew$oos_retention_approx), net_sr = rnd(ew$net_sr),
      note = "selection signal IS real vs EW peers (port_t 4.10) but does NOT transfer to cap-w — IC->PORT_t transfer wall"),
    cap_tier_composition = list(
      note = "avg holding weight share + annualized gross contribution by size tier (MEGA1-10/MID11-30/OTHER31+)",
      weight_share = list(MEGA=rnd(ct$weight_share_avg$MEGA,3), MID=rnd(ct$weight_share_avg$MID,3),
                          OTHER=rnd(ct$weight_share_avg$OTHER,3)),
      contrib_gross_annualized = list(MEGA=rnd(ct$contrib_gross_annualized$MEGA), MID=rnd(ct$contrib_gross_annualized$MID),
                                      OTHER=rnd(ct$contrib_gross_annualized$OTHER)),
      incumbent_score_eff_weight_share = list(MEGA=0.058, MID=0.086, OTHER=0.856),
      interpretation = "MID emphasis worked mechanically (MID weight 0.086->0.199, MID gross contrib 0.023->0.043/yr) but did not lift cap-w PORT_t; OTHER(small-cap) still dominates gross and cap-w benchmark penalizes benchmark-underweight tilt.")
  ),
  full_period_variant_table_capw = variant_table,
  axis_screen_IS = lapply(seq_len(nrow(axtab)), function(i) as.list(axtab[i])),
  self_adversarial = list(
    lag1_pit_stress = sprintf("real rank-IC %.4f > lag1(t-1) rank-IC %.4f — PIT graceful, no same-month leakage", res$rank_ic, stash$lag1_ic),
    placebo = sprintf("within-date shuffled score rank-IC %.4f (~0) — null OK, no spurious structure", stash$plac_ic),
    ic_vs_portt_distinct = sprintf("rank-IC %.4f (strong, > incumbent 0.044) but cap-w PORT_t %.2f — NOT conflated; IC->PORT_t transfer wall explicit", res$rank_ic, fin$portfolio_alpha_t_nw_lag3)
  )
)

alpha_package <- list(
  task_id="WT-D20260710_001", wt_type="discovery", as_of_date="2026-07-10",
  signal_as_of_date=stash$last_d, forecast_horizon="1M",
  hypothesis="MID tier(11-30) concentrated MULTI-AXIS composite (AX-007 single-sleeve exception) — does it exceed cap-w PORT_t 2.95, or is the mid-cap ~2.4 ceiling structural?",
  selection_objective="canonical_port_t",
  alpha_vector=stash$alpha_vector, confidence_vector=stash$confidence_vector,
  signal_matrix_ref="stage_artifacts/WT-D20260710_001/alpha_scores.parquet",
  factor_specs=factor_specs, diagnostics=diagnostics, metric_type="canonical_screen",
  method_shopping_log=list(
    candidates_tried=4,
    selection_window="IS <= 2018-12 (whole-univ top-25 canonical PORT_t); OOS never queried for selection (chain req 2)",
    method_log=lapply(seq_len(nrow(res$cand_IS)), function(i) as.list(res$cand_IS[i])),
    selected=res$cstar,
    note="C0_score_eff is incumbent reference (not a new-discovery candidate). Selected multi-axis = C3_multiISw_midemph (IS whole-univ PORT_t 4.52 = best multi-axis; C0 incumbent 4.87 still higher)."),
  challenge_flags=list(
    list(id="CF-1", severity="HIGH", note=sprintf("HARD-GATE FAIL: cap-w canonical PORT_t=%.2f < 2.95. ALL multi-axis variants 1.76-2.08 < incumbent score_eff 2.75 < prior single-axis tier-emphasis 2.40-2.52. Multi-axis breadth does NOT break the mid-cap ceiling.", fin$portfolio_alpha_t_nw_lag3)),
    list(id="CF-2", severity="HIGH", note=sprintf("CAP-TIER TRAP RECONFIRMED: cap-w post-2017 active t=%.2f (NEGATIVE). MID emphasis (weight 0.086->0.199) worsens cap-w post-2017 active. Long-only cross-sectional MID tilt increases divergence vs mega-cap benchmark without net cap-w gain.", res$post2017_capw_t)),
    list(id="CF-3", severity="MEDIUM", note=sprintf("IC->PORT_t transfer wall: rank-IC %.4f (strong, > incumbent 0.044) and EW-universe port_t 4.10, but cap-w port_t only %.2f. Signal is real among peers, not vs cap-w mandate benchmark.", res$rank_ic, fin$portfolio_alpha_t_nw_lag3)),
    list(id="CF-4", severity="MEDIUM", note=sprintf("VALUE-DECAY leakage in IS selection: V02_EP had strongest IS port_t (4.24) so ISw weighting tilts to value, but subperiod IC decays 2004-15=0.071 -> 2015-20=0.024 (stability %.2f<0.5). IS-optimal axis weights do not generalize.", stash$subperiod_stability)),
    list(id="CF-5", severity="LOW", note="canonical top-25 EW is screening-grade (metric_type=canonical_screen), NOT forge-authoritative. Full pipeline (risk->optimizer->forge) is authoritative; screening already predicts FAIL. alpha stage does NOT declare graduation.")
  ),
  guarded_prior_engagement="request prior=guarded (cap-tier trap both-sided proven, measurement-graduation §6). This WT tests the specific open question 'multi-axis vs single-axis at MID' with a genuinely orthogonal 6-family composite (cor 0.567 vs prior tier-restriction 0.973) and value/momentum/reversal/liquidity axes the prior did not test. Result CONFIRMS structural ceiling: multi-axis breadth does not exceed 2.95; it is slightly worse than single-axis because orthogonal MID-live axes deepen the benchmark-underweight tilt. AX-000: honest completed measurement, decisive negative, not premature-limit.",
  next_step="Risk Agent spawn (Q-Lead orchestration). Expected pipeline verdict: FAIL (cap-w PORT_t 2.08<2.95, post2017 negative). Informational value: mid-cap ceiling ~2.4-2.75 is STRUCTURAL and NOT liftable by multi-axis breadth."
)

write_json(alpha_package, file.path(WT,"alpha_package_draft.json"), auto_unbox=TRUE, pretty=TRUE, na="null", digits=6)
cat("[written] alpha_package_draft.json\n")

# alpha_validation.json
av <- list(task_id="WT-D20260710_001", metric_type="canonical_screen",
  selection_objective="canonical_port_t", selected_composite=res$cstar,
  canonical_port_t_nw_lag3=rnd(fin$portfolio_alpha_t_nw_lag3), canonical_port_t_pvalue=rnd(stash$capw_pval),
  hard_gate_2p95_pass=FALSE, n_months=fin$n_months,
  universe_comparison=list(
    capw=list(port_t=rnd(fin$portfolio_alpha_t_nw_lag3), post2017_t=rnd(res$post2017_capw_t)),
    ew_universe=list(port_t=rnd(ew$portfolio_alpha_t_nw_lag3), post2017_t=rnd(ew$post2017_t_nw_lag3), oos_retention_approx=rnd(ew$oos_retention_approx))),
  rank_ic=rnd(res$rank_ic), icir=rnd(res$icir,3), harvey_t=rnd(res$harvey_t,3),
  cor_vs_score_eff=rnd(res$cor_vs_scoreeff,3),
  verdict="SCREEN_FAIL_STRUCTURAL_MIDCAP_CEILING",
  note="multi-axis MID composite cap-w 2.08 < incumbent 2.75 < HARD 2.95; post2017 cap-w negative. Ceiling structural.")
write_json(av, file.path(SA,"alpha_validation.json"), auto_unbox=TRUE, pretty=TRUE, na="null", digits=6)
cat("[written] alpha_validation.json\n")
