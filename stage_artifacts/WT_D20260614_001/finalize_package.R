# finalize_package.R — alpha_package.json (canonical, post-Codex) for WT-D20260614_001
suppressMessages({library(jsonlite); library(data.table); library(arrow)})
root <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
out_dir <- file.path(root, "stage_artifacts", "WT_D20260614_001")
mb_dir  <- file.path(root, "qepm", "mailbox", "worktask", "WT-D20260614_001")

vec  <- readRDS(file.path(out_dir, "_alpha_vectors.rds"))
diag <- fromJSON(file.path(out_dir, "alpha_validation.json"), simplifyVector = FALSE)
dv_realign <- fromJSON(file.path(out_dir, "diversifier_realign.json"), simplifyVector = FALSE)
rfdiag <- fromJSON(file.path(out_dir, "codex_rebuttal_diags.json"), simplifyVector = FALSE)

as_of <- as.character(vec$as_of)
av <- as.list(vec$alpha_vector); cv <- as.list(vec$confidence_vector)

fspec <- function(family, proxy, formula, rationale, ref, tier, theta) list(
  factor_family = family, proxy = proxy, formula = formula,
  lag_rule = "quarterly 45d / annual May (C4 fundamental lag); Factor_Date <= sig_d",
  winsorization = "factor DB builder 3std (Z_Score)",
  neutralization = "raw at alpha stage (cross-sectional z within KOSPI200∪KQ150). NOTE RF-A4: sector-neutral IC retention 42% — signal is partly a sector tilt; risk-research to treat sector as primary axis.",
  standardization = "cross-sectional z-score (Z_Score_Aligned, C13 direction via PIT IC expanding window)",
  economic_rationale = rationale,
  weight_theta = theta, references = ref, evidence_tier = tier,
  redundancy_cluster_id = "value_cluster", source = "db_existing", factor_db_name = proxy)

# theta reflects RF-A2 standalone strength (informational for downstream; recipe is EW per request)
factor_specs <- list(
  fspec("Value","V01_BM","TotalEquity / MarketCap",
        "Book-to-market risk premium (Fama-French 1993). RF-A2 single: ic=0.0311 ICIR=0.209 t=3.46 (2nd strongest).",
        list("Fama-French 1993","Asness-Frazzini 2013"),"A",0.25),
  fspec("Value","V03_CFP","OperatingCF / MarketCap",
        "Cash-flow yield, accrual-resistant. RF-A2 single: ic=0.0344 ICIR=0.340 t=5.79 — STRONGEST single proxy; dominates the EW composite.",
        list("Lakonishok-Shleifer-Vishny 1994","Hou-Xue-Zhang 2015"),"A",0.25),
  fspec("Value","V10_FCF_Yield","(OperatingCF - CapEx) / MarketCap",
        "Free-cash-flow yield, capital-discipline tilt. RF-A2 single: ic=0.0181 ICIR=0.220 t=3.68 (weaker level, positive ICIR).",
        list("Novy-Marx 2013"),"B",0.25),
  fspec("Value","V11_Shareholder_Yield","Dividends / MarketCap",
        "Shareholder yield, payout-capacity/defensive tilt. RF-A2 single: ic=0.0172 ICIR=0.111 t=1.75 — WEAKEST; drags EW composite below CFP/BM.",
        list("Boudoukh et al. 2007"),"B",0.25))

cf <- function(id, sev, text, ev="") list(id=id, severity=sev, text=text, evidence=ev)
challenge_flags <- list(
  cf("CF-PROVENANCE-1","HIGH",
     "Carried 409-batch baseline (CAGR 15.86%/Sharpe 0.676/corr_core 0.713) does NOT measure this value-4 recipe. Audit of batch_434 runner FACTOR_NAMES: NO runner ran the pure value-4 combo; all contain >=4 non-value factors (D01/D02/M07/Q04). Carried stats belong to an 8-factor mixed combo ([[project-batch434-codegen-contamination]]). Carried baseline = SUSPECT/advisory only; this package = first-principles clean measurement.",
     "stage_artifacts/batch_434/.../runners/*.R FACTOR_NAMES grep"),
  cf("CF-PORTALPHA-LOW","HIGH",
     "Standalone value-4 long-only does NOT graduate. canonical PORT_alpha_t_NW3 = 0.453 (n25, PRIMARY) / 0.212 (n30) << 2.95 HARD; net active SR 0.100(n25). rank-IC 0.0269 / Harvey-t 3.10 decent but realized long-only portfolio-alpha near zero (Cycle-2 lesson). Value = DIVERSIFIER FEATURE, not standalone graduate. Forge portfolio-alpha t authoritative.",
     "alpha_validation.json::canonical_screen_n25/n30"),
  cf("CF-COMPOSITE-SUBOPTIMAL","HIGH",
     "RF-A2 (Codex C3): EW-4 composite (ic 0.0269/ICIR 0.178/t 3.10) UNDERPERFORMS its strongest singles V03_CFP (ic 0.0344/ICIR 0.340/t 5.79) and V01_BM (ic 0.0311/ICIR 0.209/t 3.46). Equal-weighting drags strong CFP/BM down with weak V10/V11 (ICIR 0.220/0.111). The requested value-4 EW recipe is suboptimal; a CFP/BM-led weighting would be stronger. Optimizer/risk: re-weighting opportunity (alpha honors requested EW as measured object).",
     "codex_rebuttal_diags.json::rf_a2_single_vs_composite"),
  cf("CF-SECTOR-TILT","HIGH",
     "RF-A4 (Codex C4): sector-neutral IC retention = 42% (< 50% threshold — RF-A4 fires). size-neutral 65%, sector+size 68%. A large part of raw value IC is a SECTOR bet (KR value loads cyclicals/financials). Risk-research MUST treat sector exposure as a primary risk axis; 'value alpha' is partly sector tilt.",
     "codex_rebuttal_diags.json::rf_a4_retention_pct"),
  cf("CF-IC-DECAY","MEDIUM",
     "Recent magnitude decay (Codex C5): p1(05-14) 0.0325 / p2(15-19) 0.0321 / p3(20-26) 0.0139; recent ICIR 0.092. subperiod sign-stability=1.0 is SIGN-only and overstates stability (magnitude halved). recent_ic_attenuation_ratio (p3/p1)=0.43. Consistent with value crowding.",
     "alpha_validation.json::subperiod"),
  cf("CF-DIVERSIFIER-CORRECTED","MEDIUM",
     "Diversifier diagnostic CORRECTED for date alignment (Codex C2). Realization-month aligned (219m): return_cor total 0.488, active_cor vs BM 0.269 (rolling 36m median 0.242, range [-0.34,0.74]). My draft's misaligned figure (active_cor +0.109) OVERSTATED diversification by a half-month lag. Value-4 = MODERATE partial diversifier (active_cor 0.27), weaker than carried '0.713 unique' claim. Risk-research authoritative for book-marginal ΔIR (proper covariance).",
     "diversifier_realign.json"),
  cf("CF-MULTITEST","MEDIUM",
     "Upstream multiple-testing (Codex unresolved-dispute): recipe is single at alpha stage (candidates_tried=1) BUT was SELECTED as 'unique diversifier' from a 409-candidate batch — effective meta-level multiple-testing exposure. Selection signal (corr_core 0.713) was itself contaminated (CF-PROVENANCE-1). DSR/Harvey hurdle should be read with 409-wide breadth in mind. Strengthens feature-not-graduate framing.",
     ""),
  cf("CF-AX007","MEDIUM",
     "AX-007 (Codex C6): single-sleeve long-only value top-N standalone fails (confirmed). Package does NOT claim standalone graduation — explicit DIVERSIFIER FEATURE for multi-sleeve book (STR_1715 + value tilt) and/or DPL feature (research_philosophy 4). AX-007 'multi-sleeve' exception applies at BOOK level (risk/governor), not alpha-feature level. n25 production-compliant primary; n30 diagnostic only.",
     ""),
  cf("CF-MDD-CARRY","MEDIUM",
     "Carried weakness #1: MDD 64.3% structural — NOT re-measured (alpha role = signal). Optimizer/risk to address via CVaR/risk-budget. measurement-graduation §3 (2026-06-13): MDD alone not auto-hard-fail (BM 2005+ MDD itself 54.5%); structural-drawdown criteria apply at portfolio tier.",
     "")
)

alpha_package <- list(
  task_id = "WT-D20260614_001", wt_type = "discovery", as_of_date = as_of,
  forecast_horizon = "1M",
  selection_objective = "icir",
  selection_objective_note = "predictive-power metric only (R4 P3). sharpe/ir/cagr NOT used for factor selection.",
  status = "ALPHA_FINAL_NON_GRADUATING_DIVERSIFIER_FEATURE",
  status_note = "Standalone value-4 fails graduation (PORT_t 0.45 << 2.95). Delivered as DIVERSIFIER FEATURE / DPL feed (research_philosophy 4-6), not a capital-graduating alpha. Post-Codex REVISE: 4 concerns accepted with new measurement, diversifier corrected, n25 primary.",
  codex_round = list(stance = "REVISE", veto_flag = FALSE, ax_008_at_alpha_stage = "FAIL_expected_completes_at_judge",
    resolution = "challenge_note.md", concerns_total = 7, accepted = 4, partial = 3, rebuttal_pure = 0,
    response_file = "codex_critic_response_alpha.json"),
  alpha_definition = list(
    recipe = "equal-weight cross-sectional z-score composite of 4 value factors (as requested)",
    factors = c("V01_BM","V03_CFP","V10_FCF_Yield","V11_Shareholder_Yield"),
    primary_screen_top_n = 25L, diagnostic_top_n = 30L, rebalance = "monthly",
    universe = "KOSPI200_KOSDAQ150_intersection", liquidity_min_won_20d = 2e8,
    period = c("2005-01-31", as_of), n_signal_months = 258L,
    provenance_note = "de-contaminated recipe per request (label-suspect codegen); first-principles via load_month_factors (C15). NOT the batch_434 8-factor combo.",
    recipe_caveat = "RF-A2: this EW recipe is suboptimal vs CFP/BM-led weighting (CF-COMPOSITE-SUBOPTIMAL). Measured as-requested; downstream may re-weight."),
  alpha_vector = av, confidence_vector = cv,
  signal_matrix_ref = "stage_artifacts/WT_D20260614_001/alpha_scores.parquet",
  factor_specs = factor_specs,
  diagnostics = list(
    rank_ic = diag$rank_ic, icir_monthly = diag$icir_monthly, icir_annualized = diag$icir_annualized,
    monotonicity = diag$monotonicity_quintile,
    subperiod_sign_stability = diag$subperiod_stability,
    subperiod_sign_stability_note = "SIGN-only (all 3 periods positive IC). Does NOT capture magnitude decay — see recent_ic_attenuation_ratio.",
    recent_ic_attenuation_ratio = 0.43,
    turnover_proxy_annual = diag$canonical_screen_n25$turnover_annual,
    harvey_t_stat_rankic_nw3 = diag$harvey_t_rankic_nw3, ic_t_plain = diag$ic_t_plain,
    n_months_ic = diag$n_months_ic, subperiod_detail = diag$subperiod, decile_returns = diag$decile_returns,
    metric_type = "canonical_screen"),
  rf_a2_single_vs_composite = rfdiag$rf_a2_single_vs_composite,
  rf_a4_neutralized_ic = rfdiag$rf_a4_neutralized_ic,
  rf_a4_retention_pct = rfdiag$rf_a4_retention_pct,
  portfolio_alpha = list(
    metric_type = "canonical_screen",
    authoritative_note = "NOT forge-authoritative. forge build_bt_result(optimizer weights) is binding. canonical top-N EW long-only screen (build_benchmark_compare, NW lag-3).",
    primary_n25 = diag$canonical_screen_n25, diagnostic_n30 = diag$canonical_screen_n30),
  cost_aware = list(cost_model_version = "v2.4_kr_retail_15bps", cost_bps_oneway = 15,
    turnover_annual_n25 = diag$canonical_screen_n25$turnover_annual, net_basis = TRUE,
    net_alpha_annualized_n30 = diag$canonical_screen_n30$alpha_annualized,
    net_sr_active_n25 = diag$canonical_screen_n25$net_sr,
    note = "IR/alpha/SR NET of 15bps one-way (research_philosophy 2). TO ~5.0x/yr (low value, << 11.0/yr mandate)."),
  uncertainty_aware = list(method = "IC-shrinkage scaled alpha-hat (Liao 2025 spirit)",
    alpha_hat_construction = "alpha_hat_i = rank_ic * realized_active_sd_monthly * z_i; rank_ic = global shrinkage given weak IC.",
    realized_active_sd_monthly = diag$realized_active_sd_monthly,
    confidence_basis = "per-name |z| rank-extremity * global ICIR reliability scaler; bounded [0.3,0.9].",
    reliability_note = "monthly ICIR 0.178 modest; recent 0.092 weaker — point alpha = lower-confidence."),
  diversifier_diagnostic = list(
    method = "alpha-role Pearson cor of realized return series ONLY; no cov/weight/opt.",
    incumbent = "STR_1715_AR_on_M4_R05_overlay_PG2 (book IR 1.5754)",
    realization_month_aligned = TRUE, overlap_months = dv_realign$realigned_overlap_months,
    return_cor_total = dv_realign$return_cor_total_realigned,
    active_cor_vs_bm = dv_realign$active_cor_vs_bm_realigned,
    rolling36m_active_cor = dv_realign$rolling36m_active_cor,
    interpretation = "MODERATE partial diversifier (active_cor 0.27). Weaker than carried 0.713. risk/governor authoritative for book-marginal delta-IR.",
    correction_note = "Draft misaligned figure (active_cor +0.109) corrected to 0.269 (Codex C2)."),
  redundancy_cluster_id = "value_cluster",
  cor_vs_admitted_active = dv_realign$active_cor_vs_bm_realigned,
  deflated_sharpe_ratio = NA,
  dsr_note = "selection_type=chain/single at alpha stage. DSR HARD = sweep-only (measurement-graduation §3). Caveat: upstream 409-cluster selection = meta multiple-testing (CF-MULTITEST). DSR not binding gate; portfolio_alpha_t (forge) + oos_retention are.",
  ax001_v2_note = "value not a defense factor; AX-001 v2 N/A. Standard eval applies; standalone fails (CF-PORTALPHA-LOW).",
  challenge_flags = challenge_flags,
  method_shopping_log = list(candidates_tried = 1L,
    method_log = list(list(name = "value4_EW_zcomposite", rank_ic = diag$rank_ic, selected = TRUE)),
    upstream_selection_note = "candidates_tried=1 at ALPHA stage, but recipe SELECTED from 409-batch cluster (meta multiple-testing — CF-MULTITEST). Judge should weigh 409-wide breadth.",
    rf_a2_baselines_logged = TRUE),
  generated_by = "alpha-research agent (post-Codex REVISE)", generated_at = as.character(Sys.time())
)

final_path <- file.path(mb_dir, "alpha_package.json")
write_json(alpha_package, final_path, pretty = TRUE, auto_unbox = TRUE, digits = 8, null = "null")
cat("FINAL written:", final_path, "\n")

# lineage (after file write — L-194 order)
src <- file.path(root, "02_Infrastructure", "worktask", "lineage_utils.R")
if (file.exists(src)) {
  source(src)
  tryCatch(record_package_lineage(task_id = "WT-D20260614_001", package_type = "alpha_package",
      method_selected = "value-4 EW z-composite (V01_BM+V03_CFP+V10_FCF_Yield+V11_Shareholder_Yield), n25 primary, post-Codex",
      input_file_paths = c(file.path(out_dir,"alpha_scores.parquet"),
                           file.path(out_dir,"alpha_validation.json"),
                           file.path(out_dir,"codex_rebuttal_diags.json"),
                           file.path(root,".cache","factor_db","factor_registry.json"))),
    error = function(e) cat("[lineage] WARN:", conditionMessage(e), "\n"))
} else cat("[lineage] lineage_utils.R not found — skipped\n")
cat("DONE\n")
