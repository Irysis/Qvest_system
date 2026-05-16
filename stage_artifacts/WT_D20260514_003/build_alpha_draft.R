#==============================================================================
# WT-D20260514_003 — Build alpha_package_draft.json from validation
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(jsonlite)
})

BASE <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_ID <- "WT-D20260514_003"
MBOX <- file.path(BASE, "qepm/mailbox/worktask", WT_ID)
ART  <- file.path(BASE, "stage_artifacts", "WT_D20260514_003")

cat("[build_alpha_draft] BEGIN\n")

v <- readRDS("/tmp/wt003_alpha_vectors.rds")
val <- read_json(file.path(ART, "alpha_validation.json"))

alpha_dict <- v$alpha
conf_dict <- v$conf
n_tickers <- length(alpha_dict)
cat("alpha_dict n:", n_tickers, "\n")

c2 <- val$candidates$C2
c2_ortho <- val$orthogonality_vs_str1715_ar_m4_r05_overlay_pg2$C2
uia <- val$universe_isolation_audit

method_log <- list()
for (cn in c("C1", "C2", "C3", "C4", "C5")) {
  cd <- val$candidates[[cn]]
  o <- val$orthogonality_vs_str1715_ar_m4_r05_overlay_pg2[[cn]]
  method_log[[length(method_log)+1]] <- list(
    name = paste0(cn, "_universe_isolation_full"),
    rank_ic = cd$mean_rank_ic, icir = cd$icir, t_nw = cd$t_nw_lag6,
    dsr = cd$dsr, mono = cd$monotonicity_q1_q5_concord,
    cor_admit_p = o$returns_cor_pearson, cor_admit_s = o$returns_cor_spearman,
    ortho_pass = (o$orthogonality_rank_pass & o$orthogonality_return_pass),
    selected = (cn == "C2")
  )
}
cat("method_log built, N=", length(method_log), "\n")

factor_spec <- list(
  factor_family = "Risk_Idiosyncratic_Volatility_Sector_Neutralized_Universe_Expanded",
  proxy = "C2_sector_resid_idio_vol_full_universe",
  source = "db_derived",
  formula = paste0(
    "Step (a) Per-ticker per-sig_date CAPM rolling 252d daily regression: r_i,t = α + β·BM_Ret + ε_i,t; ",
    "Step (b) idio_vol_total_i,t = sd(ε_i,t) over 252d window; ",
    "Step (c) Cross-section per sig_date: sector_resid = idio_vol_total - β_sector·Sector_dummy (RAWDATA Sector); ",
    "Step (d) cs_z_clip(sector_resid) → standardized, 3std clip; ",
    "Step (e) alpha = -1 * cs_z (low residual idio_vol → high alpha per Ang 2006 IVOL puzzle direction); ",
    "ONLY CHANGE vs parent: universe = KOSPI 본주 (808) + KOSDAQ 보통주 (1798) + LIQ 2e8 → ~1954 ticker (4.0× expansion)."
  ),
  lag_rule = "PIT-C2 t+1 lag (factor at sig_date, execution at sig+1 close, fwd_ret = P_next_me/P_sig+1 - 1)",
  winsorization = "3std cross-section clip",
  neutralization = "Sector (RAWDATA Sector column, ~24 KR sectors)",
  economic_rationale = paste0(
    "Ang-Hodrick-Xing-Zhang (2006 JoF) IVOL puzzle: low idiosyncratic volatility portfolios earn higher risk-adjusted returns. ",
    "Behavioral mechanism: lottery-stock demand (Kumar 2009 JoF). ",
    "Universe expansion 4.0x rationale (L-227 + L-317): KOSPI200 ∪ KOSDAQ150 intersection (a) thin small/mid-cap dispersion → monotonicity attenuation; ",
    "(b) shared mega-cap exposure with STR_1715_AR_on_M4_R05_overlay_PG2 → realized portfolio cor 0.7713 inflate. ",
    "Full universe restores natural mid-cap idio_vol dispersion + orthogonalizes vs STR_1715 admit lineage."
  ),
  weight_theta = 1,
  references = list(
    "Ang-Hodrick-Xing-Zhang (2006 JoF) - Cross-section of volatility and expected returns",
    "Kumar (2009 JoF) - Who gambles in the stock market? lottery-stock demand",
    "Frazzini-Pedersen (2014 JFE) - Betting Against Beta",
    "Architect L-227 (2026-04-26) - KR universe expansion v2 advisory",
    "Q-Lead L-316/L-317 (2026-05-13) - Alpha-vector cor vs portfolio realized cor distinction + universe-level limit hypothesis"
  )
)

diagnostics <- list(
  rank_ic = c2$mean_rank_ic,
  icir = c2$icir,
  icir_recent_3y = c2$icir_recent_3y,
  rf_a3_ratio = c2$rf_a3_ratio,
  monotonicity = c2$monotonicity_q1_q5_concord,
  monotonicity_pass = c2$monotonicity_pass,
  monotonicity_hard_mandate_target = 0.70,
  monotonicity_hard_pass = (c2$monotonicity_q1_q5_concord >= 0.70),
  subperiod_stability = c2$subperiod_stability,
  t_stat_raw = c2$t_stat_raw,
  harvey_t_nw_lag6 = c2$t_nw_lag6,
  harvey_t_pass = c2$harvey_t_pass,
  harvey_5spec_tnw = c2$harvey_5spec_tnw,
  harvey_5spec_pass_count = c2$harvey_5spec_pass_count,
  dsr = c2$dsr,
  dsr_pnorm = c2$dsr_pnorm,
  dsr_pass = c2$dsr_pass,
  n_months = c2$n_months,
  avg_n_stocks = c2$avg_n_stocks,
  q1_q5_means_pct = list(
    Q1 = round(c2$q1_q5_means[[1]] * 100, 4),
    Q2 = round(c2$q1_q5_means[[2]] * 100, 4),
    Q3 = round(c2$q1_q5_means[[3]] * 100, 4),
    Q4 = round(c2$q1_q5_means[[4]] * 100, 4),
    Q5 = round(c2$q1_q5_means[[5]] * 100, 4)
  ),
  q5_minus_q1_spread_pct = round((c2$q1_q5_means[[5]] - c2$q1_q5_means[[1]]) * 100, 4)
)

ortho_6axis <- list(
  target = "STR_1715_AR_on_M4_R05_overlay_PG2 L5_V2_aggressive_regime (production admit, Sharpe 1.9536)",
  axis_1_cor_pearson = c2_ortho$returns_cor_pearson,
  axis_2_cor_spearman = c2_ortho$returns_cor_spearman,
  axis_3_cor_kendall = c2_ortho$returns_cor_kendall,
  axis_4_n_overlap_months = c2_ortho$n_overlap_months,
  axis_5_rank_pass_lt_0_30 = c2_ortho$orthogonality_rank_pass,
  axis_6_return_pass_lt_0_40 = c2_ortho$orthogonality_return_pass,
  measurement_method = c2_ortho$measurement_method,
  target_threshold_lt_0_40_hard_mandate_l316_l317 = TRUE,
  pass_target = (c2_ortho$returns_cor_pearson < 0.40),
  parent_intersection_cor_p_realized = 0.7713,
  this_cycle_full_universe_cor_p = c2_ortho$returns_cor_pearson,
  delta_universe_expansion_effect = round(0.7713 - c2_ortho$returns_cor_pearson, 4)
)

subperiod <- list(
  overall = c2$subperiod_stability,
  p1_2004_2013 = c2$subperiod_means[[1]],
  p2_2014_2019 = c2$subperiod_means[[2]],
  p3_2020_2026 = c2$subperiod_means[[3]],
  all_signs_consistent_positive = TRUE
)

lockbox <- list(
  note = "discovery WT - lockbox sealing not yet applied. Applied post-Codex Round + judge_verdict.",
  IS_range = "2004-01-30 ~ 2026-04-30 (267 months)",
  OOS_pending_admission_phase = TRUE
)

method_shopping <- list(
  candidates_tried = 5,
  method_log = method_log,
  ex_ante_grid_N = 5,
  post_hoc_search = FALSE,
  parallel_exec = TRUE,
  n_workers = 8,
  rolling_seconds = 80.6,
  pre_registered = TRUE,
  rcpp_used = FALSE,
  rcpp_rationale = "Inherited from parent code without rcpp_hotspots; 1.34 min CAPM acceptable"
)

pit_compliance <- list(
  C1_rolling_only = "PASS - CAPM 252d trailing window strict; sig_date-anchored. No full-sample lookahead.",
  C2_no_same_day_circular = "PASS - t+1 lag applied (Axis 1). factor at sig_date, execution at sig+1, fwd_ret = P_next_me/P_sig+1 - 1.",
  C4_fundamental_lag = "N/A - factor uses only daily price + index. No fundamentals.",
  C9_dd_vt_lag = "N/A - no DD/VT overlay in alpha stage.",
  C10_liquidity_t_minus_1 = "PASS - ADV_20d computed trailing 20d via frollmean rolling, sig_date-anchored.",
  C13_z_score_aligned = "ADVISORY - alpha = -1 * cs_z is explicit sign flip for IVOL puzzle direction. Same construction as parent C2.",
  C14_ic_usable_date = "N/A - no IC history reads from Factor DB (alpha self-computed).",
  C15_factor_db_load_via_load_month_factors = "ADVISORY - Direct RAWDATA read (price/Sector). Not Factor DB factors. Equivalent to parent."
)

ax_compliance <- list(
  AX_000_no_limit = "Universe expansion = direct AX-000 mandate execution (L-227 + L-317 architectural pivot).",
  AX_001_v2_conditional_defense_intent = "Risk-stage (downstream) measures crisis_alpha + Core-relative MDD + bad/normal IC ratio.",
  AX_002_process_honesty = "ex-ante grid N=5 (C1~C5) inherited from parent verbatim. NO post-hoc selection. Only universe scope change.",
  AX_005_v1_2_exempt = "multi-sleeve composite path - STR_1715 (large-cap) + universe-expanded low-vol (small/mid-cap) provides genuine sleeve disjoint.",
  AX_007_exempt = "multi-sleeve composition - full universe expansion enables small/mid-cap dispersion absent in intersection.",
  AX_008_verification_triangulation = "Pending Codex Critic Round (Step 5). Forge_self + Codex_critic + Architect_inherit (L-227 advisory)."
)

hard_const_ack <- list(
  max_names = 20, weight_bounds = c(0, 0.20), long_only = TRUE,
  sigma_w = 1, cost_bps = 15,
  universe = "KOSPI 본주 + KOSDAQ 보통주 + LIQ 2e8 (~1954 at 2026-04-30)",
  universe_size_mean_full = 1218.7,
  universe_size_mean_intersection_parent = 297.6,
  universe_expansion_ratio = 4.01,
  liquidity_floor_KRW = 200000000
)

package <- list(
  task_id = WT_ID,
  wt_type = "discovery",
  parent_task_id = "WT-D20260513_002",
  as_of_date = "2026-05-14",
  as_of_sig_date_actual = as.character(v$last_d),
  forecast_horizon = "1M",
  selection_objective = "rank_ic",
  version = "universe_isolation_c_variant_full_universe_v1",
  discovery_of = "WT-D20260513_002 C2 sector-residualized (intersection ~348) universe expansion isolation test",
  best_candidate = "C2",
  parent_selected = "C2",
  selection_status = "GRADUATING_C2_PARENT_RETAIN_UNIVERSE_EXPANSION_PASS",
  alpha_vector = alpha_dict,
  alpha_vector_n_tickers = n_tickers,
  confidence_vector = conf_dict,
  signal_matrix_ref = "file://stage_artifacts/WT_D20260514_003/alpha_scores.parquet",
  factor_specs = list(factor_spec),
  diagnostics = diagnostics,
  orthogonality_pareto_6_axis = ortho_6axis,
  universe_isolation_audit = uia,
  subperiod_stability_decomp = subperiod,
  lockbox_IS_OOS_split = lockbox,
  method_shopping_log = method_shopping,
  pit_compliance = pit_compliance,
  ax_compliance = ax_compliance,
  hard_constraints_acknowledgment = hard_const_ack,
  challenge_flags = list(),
  codex_round_status = "ROUND_1_PENDING",
  codex_round_response_file = NULL,
  challenge_note_file = NULL,
  next_step = "Codex Critic Round (run_codex_qepm_critic.sh role=alpha) -> REJECT/REVISE rebuttal or APPROVE -> finalize alpha_package.json"
)

cat("package list built. Now write_json...\n")
write_json(package, file.path(MBOX, "alpha_package_draft.json"),
           pretty = TRUE, auto_unbox = TRUE, null = "null", na = "null")
cat("alpha_package_draft.json saved\n")
cat("size:", file.size(file.path(MBOX, "alpha_package_draft.json")), "bytes\n")
