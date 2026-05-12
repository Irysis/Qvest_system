#==============================================================================
# WT-D20260508_013 Forge — build forge_package_draft.json
#==============================================================================

suppressPackageStartupMessages({
  library(data.table); library(jsonlite); library(digest)
})

setwd("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")

WT_ID <- "WT-D20260508_013"
SA_DIR <- file.path("stage_artifacts", WT_ID)
FORGE_DIR <- file.path(SA_DIR, "forge")
WT_DIR <- file.path("qepm/mailbox/worktask", WT_ID)

cat("[Forge] Building forge_package_draft.json\n")

# Hash input packages
alpha_sha <- digest(file = file.path(WT_DIR, "alpha_package.json"), algo = "sha256")
risk_sha  <- digest(file = file.path(WT_DIR, "risk_package.json"), algo = "sha256")
opt_sha   <- digest(file = file.path(WT_DIR, "optimization_package_draft.json"), algo = "sha256")

# Load five_ratio_metrics + ax001_v2 + cov_eigen + opt_vs_forge
five_ratio <- read_json(file.path(FORGE_DIR, "five_ratio_metrics.json"), simplifyVector = FALSE)
ax001 <- read_json(file.path(FORGE_DIR, "ax001_v2_realized_audit.json"), simplifyVector = FALSE)
cov_eigen <- read_json(file.path(FORGE_DIR, "cov_eigen_recompute.json"), simplifyVector = FALSE)
opt_vs_forge <- read_json(file.path(FORGE_DIR, "optimizer_estimate_vs_forge_realized.json"),
                           simplifyVector = FALSE)

# Build forge_package
forge_package <- list(
  task_id = WT_ID,
  package_kind = "forge_package_draft",
  wt_type = "discovery",
  as_of_date = "2026-05-08",
  agent = "forge",
  draft_revision = "v1.0_pre_codex",

  # Pure Function R12 inheritance hashes
  alpha_inheritance = list(
    alpha_package_path = paste0(WT_DIR, "/alpha_package.json"),
    alpha_package_sha = alpha_sha,
    no_alpha_modification = TRUE
  ),
  risk_inheritance = list(
    risk_package_path = paste0(WT_DIR, "/risk_package.json"),
    risk_package_sha = risk_sha,
    no_risk_modification = TRUE
  ),
  optimization_inheritance = list(
    optimization_package_draft_path = paste0(WT_DIR, "/optimization_package_draft.json"),
    optimization_package_draft_sha = opt_sha,
    no_optimization_modification = TRUE
  ),

  # SR Provenance Mandate (Charter v1.7 §10 / v6.3 HARD)
  sr_provenance = list(
    sr_realized_share_based = list(
      "0pct" = 1.8110,
      "5pct" = 1.8176,
      "10pct" = 1.8129,
      "15pct" = 1.7949,
      "20pct" = 1.7617,
      method = "PerformanceAnalytics::SharpeRatio.annualized(scale=12) on Hybrid 4-sleeve combine monthly returns",
      window = "joint_window_252m_2005_06_to_2026_05",
      cost_basis = "alpha sleeve 15bps round-trip (PIT-honest walk-forward); Hybrid baseline pre-cost integrated"
    ),
    sr_factor_engine_continuous = NULL,
    sr_lockbox_daily_harness = NULL,
    measurement_basis_primary = "forge_realized_share_based",
    divergence_factor_engine_vs_realized_pp = NULL,
    vs_factor_engine = list(
      diagnosis = "NEGLIGIBLE",
      basis = "No factor_engine claim made by Forge. Optimizer estimate compared separately."
    )
  ),

  # 5 비중 실측 결과
  five_ratio_results = five_ratio,

  # Cov eigen recompute (Risk verify pass-through)
  cov_eigen_recompute = cov_eigen,

  # AX-001 v2 strict realized audit
  ax001_v2_realized = ax001,

  # Optimizer estimate vs Forge realized
  optimizer_vs_forge_realized = opt_vs_forge,

  # Schedule fidelity
  schedule_fidelity = list(
    weights_csv_density = 1.0,
    weights_csv_n_dates = 252,
    sleeve_returns_n_periods = 252,
    sleeve_realized_range = "2005-05-31 ~ 2026-04-30",
    hybrid_baseline_density = 1.0,
    joint_window = "250m (Hybrid ∩ Sleeve, 4 hybrid-only months early + 2 sleeve-only month late)",
    no_holdings_re_selection = TRUE,
    no_alpha_scores_top_n_re_pick = TRUE,
    note = "Sleeve weights derived AT each sig_date from c4_rcomp via AlphaWeighted top20 with [0,0.20] bound. No re-selection of Optimizer's target_weights. Pure Function R12."
  ),

  # PIT compliance
  pit_compliance = list(
    C1 = "PASS — walk-forward 252 sig_dates, no full-sample stats",
    C2 = "PASS — sig_date t selects from data <= t (alpha_z PIT-aligned by alpha_package)",
    C9 = "N/A — no DD/VT overlay in Forge layer",
    C13 = "N/A — Z_Score_Aligned consumed from alpha_package (c4_rcomp)",
    C14 = "PASS — alpha_scores Usable_Date already enforced by alpha_package C14",
    C15 = "PASS — alpha_scores.parquet via stage_artifacts (no factor_db direct load)"
  ),

  # AX axiom audit
  ax_axiom_audit = list(
    AX_001_v2 = list(
      verdict = "INHERITED_DIVERSIFIER_HONEST_DOWNGRADE_CONFIRMED_BY_FORGE_REALIZED_AUDIT",
      forge_realized_findings = list(
        cor_sleeve_hybrid_full_250m = 0.1450,
        cor_sleeve_hybrid_60m = 0.0546,
        gate_3_low_cor_full_pass = TRUE,
        gate_3_low_cor_60m_pass = TRUE,
        crisis_alpha_vs_AR_core_total_pp = -132.62,
        crisis_periods_n_positive = 1,
        crisis_periods_n_feasible = 6,
        bad_normal_ratio_realized = -0.1059,
        regime_diagnosis = "PRO_CYCLIC_bad_neg_normal_pos_INVERSE_DEFENSIVE",
        notable_positive_period = "COVID_2020 +13.61pp vs AR core",
        notable_negative_periods = c("China_Shock_2015 -48.83pp", "VolShock_2018 -27.27pp",
                                       "GFC_2008 -32.20pp", "EuDebt_2011 -23.07pp",
                                       "Inflation_2022 -14.86pp")
      ),
      diagnosis = paste0(
        "Risk agent classified Diversifier honest (NOT defense). Forge realized audit ",
        "confirms AX-001 v2 strict gate 4 crisis_alpha vs AR core SUM = -132.62pp across 6 ",
        "feasible crisis periods (only 1/6 positive: COVID 2020). Sleeve standalone ",
        "is PRO_CYCLIC (bad/normal ratio = -0.1059, inverse defensive). However, ",
        "diversification by mean-variance partial: Hybrid 5% incremental SR +0.0065 / ",
        "MDD -0.62pp improvement. Conclusion: WEAK DIVERSIFIER (low cor not enough; ",
        "PRO_CYCLIC behavior negates defense claim). NOT defense, not even strong diversifier."
      )
    ),
    AX_002 = list(
      status = "PASS",
      basis = paste0(
        "Forge backtest uses walk-forward harness on alpha_scores.parquet (PIT-honest). ",
        "weights at each sig_date computed from c4_rcomp top20 + AlphaWeighted positive-shift. ",
        "No fabrication of holdings or sig_dates. schedule_density = 1.0 (252 unique sig_dates). ",
        "All 10 + audit components saved per Backtest Result Contract v1.0 sketch."
      )
    ),
    AX_007 = list(
      verdict = "PASS_VIA_MULTI_SLEEVE_EXCEPTION",
      structure_at_forge_layer = "multi_sleeve_4_PG2_hybrid_plus_WT_013",
      basis = paste0(
        "Hybrid 70/15/15 = 3-sleeve multi-source EXCEPTION already operative. ",
        "WT_013 admit at 5-20% extends multi-sleeve to 4 sleeves. ",
        "Single-sleeve top20 long-only break PREVENTED."
      )
    ),
    AX_008 = list(
      triangulation_progress = "Forge + Codex critic = 2/3. Architect 3rd-source mandate REMAINS.",
      forge_2nd_source = "PASS_with_caveats (cov_eigen verified PSD; 5 ratio realized; AX-001 v2 strict realized confirms Risk Diversifier downgrade)",
      architect_mandate = paste0(
        "Independent VaR + Mom factor reproduction (alpha-side) + ",
        "factor model Σ verification (risk-side) + ",
        "Hybrid 4-sleeve combine 5 비중 ΔSharpe verification (Forge)."
      )
    )
  ),

  # 5 sleeve combination — primary recommendation
  primary_recommendation = list(
    pct = 5,
    basis_realized = paste0(
      "Forge 256m realized 5 비중 비교: 5% provides best ΔSR=+0.0065 + ΔMDD=-0.62pp ",
      "+ TE=1.32% + low turnover impact (0.018). 10% gives larger MDD improvement (-1.22pp) ",
      "but ΔSR ~ 0 (+0.002). 15% ΔSR negative (-0.016). 20% ΔSR strongly negative (-0.049) ",
      "and MDD WORSE (+2.15pp)."
    ),
    optimizer_diff = paste0(
      "Optimizer recommended C_90_10 (10%). Forge realized: 10% MDD better but SR ~ flat. ",
      "5% provides best risk-adjusted improvement. Conservative Diversifier (Risk recommendation) ",
      "is better realized at 5% weight (lower turnover + lower TE)."
    ),
    governor_decision = "Q-Lead/Governor decides: A (skip 0%), B (5% Forge primary), C (10% Optimizer primary), D (15%), E (20%). Forge primary = B (5%)."
  ),

  # Hard constraint audit
  hard_constraints_audit = list(
    max_names_n = 20,
    max_names_pass = TRUE,
    long_only_pass = TRUE,
    weight_bounds_ok = TRUE,
    sum_w_minus_1_max = 0,
    sum_w_pass = TRUE,
    cost_15bps_one_way = TRUE,
    note = paste0(
      "Sleeve walk-forward maintains 20 holdings each period (252/252). Σw=1 (alpha-weighted ",
      "positive-shift normalize, cap at 0.20 with re-normalize). long-only all weights >= 0."
    )
  ),

  # Red flags
  rf_red_flags = list(
    "RF-F1" = list(severity = "MEDIUM",
                    finding = "Sleeve standalone PerfA SR = 0.3658 vs Optimizer cost-adj SR 0.6550 → 44% deflate. Consistent with WT_009/010 PIT/cost gap."),
    "RF-F2" = list(severity = "HIGH",
                    finding = "AX-001 v2 strict realized: bad/normal ratio -0.106 (PRO_CYCLIC, inverse defensive). 5/6 crisis periods crisis_alpha vs AR core NEGATIVE. Diversifier classification supported only by low cor; defensive claim fully INVALIDATED."),
    "RF-F3" = list(severity = "LOW",
                    finding = "Optimizer SR estimate vs Forge realized: realized > estimate by +0.02~+0.16. Optimizer was CONSERVATIVE on SR (atypical relative to WT_009/010 inflate pattern). MDD: Optimizer estimate -19~-17% vs Forge realized -18~-22%. Both directions of mis-estimation observed; gap moderate (~0.4pp)."),
    "RF-F4" = list(severity = "INFO",
                    finding = "Forge primary recommendation (5%) differs from Optimizer primary (10%). Both within Risk band [5%, 15%]. Final admit decision deferred to Q-Lead/Governor."),
    "RF-F5" = list(severity = "LOW",
                    finding = "Joint window 250m (vs target 256m). 4 Hybrid-only early months (2005-02 ~ 2005-05 + occasional gaps) + 2 sleeve-only late months (2026-05). Schedule density = 1.0 within joint scope.")
  ),

  # Artifact lineage
  artifact_lineage = list(
    request = paste0(WT_DIR, "/request.json"),
    alpha_package = paste0(WT_DIR, "/alpha_package.json"),
    risk_package = paste0(WT_DIR, "/risk_package.json"),
    optimization_package_draft = paste0(WT_DIR, "/optimization_package_draft.json"),
    sleeve_returns = paste0(SA_DIR, "/forge/sleeve_returns_256m.csv"),
    five_ratio_metrics = paste0(SA_DIR, "/forge/five_ratio_metrics.json"),
    five_ratio_comparison = paste0(SA_DIR, "/forge/five_ratio_comparison.csv"),
    cov_eigen_recompute = paste0(SA_DIR, "/forge/cov_eigen_recompute.json"),
    ax001_v2_realized_audit = paste0(SA_DIR, "/forge/ax001_v2_realized_audit.json"),
    optimizer_estimate_vs_forge_realized = paste0(SA_DIR, "/forge/optimizer_estimate_vs_forge_realized.json"),
    output_charts = list(
      equity_curve = paste0(SA_DIR, "/forge/output/equity_curve.png"),
      annual_returns = paste0(SA_DIR, "/forge/output/annual_returns.png"),
      oos_zoom_chart = paste0(SA_DIR, "/forge/output/oos_zoom_chart.png"),
      regime_decomposition = paste0(SA_DIR, "/forge/output/regime_decomposition.png"),
      drawdown_comparison = paste0(SA_DIR, "/forge/output/drawdown_comparison.png")
    ),
    per_ratio_period_returns = list(
      "0pct" = paste0(SA_DIR, "/forge/0pct/03_period_returns.csv"),
      "5pct" = paste0(SA_DIR, "/forge/5pct/03_period_returns.csv"),
      "10pct" = paste0(SA_DIR, "/forge/10pct/03_period_returns.csv"),
      "15pct" = paste0(SA_DIR, "/forge/15pct/03_period_returns.csv"),
      "20pct" = paste0(SA_DIR, "/forge/20pct/03_period_returns.csv")
    )
  ),

  agent_id = "forge",
  artifact_version = "v1.0_forge_package_draft_pre_codex"
)

write_json(forge_package, file.path(WT_DIR, "forge_package_draft.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "null")
cat("[saved]", file.path(WT_DIR, "forge_package_draft.json"), "\n")

# Final verification
final_size <- file.size(file.path(WT_DIR, "forge_package_draft.json"))
cat("Draft size:", final_size, "bytes\n")
cat("\n[Forge] forge_package_draft.json built\n")
