# build_package.R — assemble alpha_package_draft.json for WT-D20260614_001
suppressMessages({library(jsonlite); library(data.table); library(arrow)})
root <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
out_dir <- file.path(root, "stage_artifacts", "WT_D20260614_001")
mb_dir  <- file.path(root, "qepm", "mailbox", "worktask", "WT-D20260614_001")

vec  <- readRDS(file.path(out_dir, "_alpha_vectors.rds"))
diag <- fromJSON(file.path(out_dir, "alpha_validation.json"), simplifyVector = FALSE)
dv   <- fromJSON(file.path(out_dir, "diversifier_diag.json"), simplifyVector = FALSE)

as_of <- as.character(vec$as_of)
av <- as.list(vec$alpha_vector); cv <- as.list(vec$confidence_vector)

# factor specs (4 value factors) — registry-grounded definitions
fspec <- function(family, proxy, formula, rationale, ref, tier) list(
  factor_family = family, proxy = proxy, formula = formula,
  lag_rule = "quarterly 45d / annual May (C4 fundamental lag); Factor_Date <= sig_d",
  winsorization = "factor DB builder 3std (Z_Score)",
  neutralization = "raw (cross-sectional z within KOSPI200∪KQ150 universe)",
  standardization = "cross-sectional z-score (Z_Score_Aligned, C13 direction via PIT IC expanding window)",
  economic_rationale = rationale,
  weight_theta = 0.25, references = ref, evidence_tier = tier,
  redundancy_cluster_id = "value_cluster", source = "db_existing",
  factor_db_name = proxy)

factor_specs <- list(
  fspec("Value","V01_BM","TotalEquity / MarketCap",
        "Book-to-market risk premium (Fama-French 1993). KR: value risk premium persists; cheap book provides margin-of-safety in elevated/crisis regimes (registry regime_profile: elevated/crisis positive).",
        list("Fama-French 1993","Asness-Frazzini 2013"),"A"),
  fspec("Value","V03_CFP","OperatingCF / MarketCap",
        "Cash-flow yield. Harder to manipulate than earnings; captures operating cash generation relative to price. KR value composites benefit from CF-based metrics that resist accrual distortion.",
        list("Lakonishok-Shleifer-Vishny 1994","Hou-Xue-Zhang 2015"),"A"),
  fspec("Value","V10_FCF_Yield","(OperatingCF - CapEx) / MarketCap",
        "Free-cash-flow yield. Net cash after reinvestment relative to price; rewards capital discipline. Complements CFP by penalizing high-capex cash burners.",
        list("Novy-Marx 2013"),"B"),
  fspec("Value","V11_Shareholder_Yield","Dividends / MarketCap",
        "Shareholder yield (dividend payout / market cap). Cash actually returned to owners; quality-of-value tilt favoring firms with payout capacity. KR dividend tilt has defensive character.",
        list("Boudoukh et al. 2007"),"B"))

# challenge_flags — honest provenance + structural findings (Charter §8, AX-000)
challenge_flags <- list(
  list(id="CF-PROVENANCE-1", severity="HIGH",
       text="Carried 409-batch baseline (CAGR 15.86% / Sharpe 0.676 / corr_core 0.713) does NOT measure this value-4 recipe. Direct audit of batch_434 runner FACTOR_NAMES shows NO runner ran the pure V01_BM+V03_CFP+V10_FCF_Yield+V11_Shareholder_Yield combo; every runner containing these 4 also contains >=4 non-value factors (D01_IdioVol,D02_Beta,M07_IndMom,Q04_Piotroski_F). Per [[project-batch434-codegen-contamination]], the carried stats belong to an 8-factor mixed combo, NOT the value-4 sleeve. Treat carried baseline as SUSPECT/advisory only. This package reports a first-principles clean measurement instead.",
       evidence="stage_artifacts/batch_434/20260612_codegen_409/runners/*.R FACTOR_NAMES grep"),
  list(id="CF-PORTALPHA-LOW", severity="HIGH",
       text="Standalone value-4 long-only does NOT clear graduation. canonical_screen_bt PORT_alpha_t_NW3 = 0.212 (n=30) / 0.453 (n=25), p>0.66 — far below 2.95 HARD. net active SR 0.047(n30)/0.100(n25). This is the EXPECTED Cycle-2 lesson (rank-IC 0.0269 / Harvey-t 3.10 decent, but realized long-only portfolio-alpha t near zero) and confirms carried weakness #2 (standalone SR 0.68 << 2.5). Value enters as a DIVERSIFIER FEATURE, not a standalone graduate. Judge/forge portfolio-alpha t is authoritative.",
       evidence="alpha_validation.json::canonical_screen_n30/n25"),
  list(id="CF-IC-DECAY", severity="MEDIUM",
       text="Subperiod IC decay: p1(2005-14) 0.0325 / p2(2015-19) 0.0321 / p3(2020-26) 0.0139 — recent IC roughly halved. Consistent with value crowding (carried weakness #3; all 4 factors share registry correlation_group='value_cluster'). subperiod_stability=1.0 only in sign (all positive), not magnitude. Recent ICIR 0.092 monthly is weak.",
       evidence="alpha_validation.json::subperiod"),
  list(id="CF-CROWDING", severity="MEDIUM",
       text="Single-axis crowding: all 4 factors are economic_family=value, correlation_group=value_cluster (registry). EW composite of 4 highly-collinear value proxies provides limited independent breadth vs a single value proxy. Risk-research should diagnose intra-value collinearity (likely V01_BM~V03_CFP~V10 high pairwise) and value-crowding exposure.",
       evidence="factor_registry.json labels.correlation_group"),
  list(id="CF-DIVERSIFIER-ALIGN", severity="MEDIUM",
       text="Diversifier diagnostic (alpha-role, return-cor only — NO cov/weight): return_cor(total) = -0.030, active_cor(vs BM) = +0.109 vs incumbent STR_1715 (219m overlap). This is FAVORABLE (near-orthogonal) and BETTER than carried corr_core 0.713 AND the 'KR VALUE corr~0.76 established truth'. CAVEAT: incumbent series is month-START dated, my sleeve month-END dated; ~half-month misalignment may artificially deflate correlation. Risk-research must recompute with proper date alignment before book-marginal ΔIR. Magnitude UNCERTAIN; direction (low cor) robust.",
       evidence="diversifier_diag.json + _diversifier_cor.R"),
  list(id="CF-MDD-CARRY", severity="MEDIUM",
       text="Carried weakness #1: MDD 64.3% structural (deep value drawdown). NOT re-measured here (alpha role = signal, not portfolio MDD). Optimizer/risk to address via CVaR/risk-budget. Note structural-drawdown screening tier (measurement-graduation §3 2026-06-13): MDD alone is not auto-hard-fail; BM 2005+ MDD itself 54.5%.")
)

alpha_package <- list(
  task_id = "WT-D20260614_001",
  wt_type = "discovery",
  as_of_date = as_of,
  forecast_horizon = "1M",
  selection_objective = "icir",
  selection_objective_note = "predictive-power metric only (R4 P3). rank_ic/icir/monotonicity/subperiod used for factor selection; sharpe/ir/cagr NOT used for selection.",
  alpha_definition = list(
    recipe = "equal-weight cross-sectional z-score composite of 4 value factors",
    factors = c("V01_BM","V03_CFP","V10_FCF_Yield","V11_Shareholder_Yield"),
    canonical_top_n = 30L, rebalance = "monthly",
    universe = "KOSPI200_KOSDAQ150_intersection", liquidity_min_won_20d = 2e8,
    period = c("2005-01-31", as_of), n_signal_months = 258L,
    provenance_note = "de-contaminated recipe per request (label-suspect codegen); first-principles measured via load_month_factors (C15). NOT the batch_434 carried 8-factor combo."),
  alpha_vector = av,
  confidence_vector = cv,
  signal_matrix_ref = "stage_artifacts/WT_D20260614_001/alpha_scores.parquet",
  factor_specs = factor_specs,
  diagnostics = list(
    rank_ic = diag$rank_ic,
    icir_monthly = diag$icir_monthly,
    icir_annualized = diag$icir_annualized,
    monotonicity = diag$monotonicity_quintile,
    subperiod_stability = diag$subperiod_stability,
    turnover_proxy_annual = diag$canonical_screen_n30$turnover_annual,
    harvey_t_stat_rankic_nw3 = diag$harvey_t_rankic_nw3,
    ic_t_plain = diag$ic_t_plain,
    post_neutralization_ic = diag$rank_ic,
    post_neutralization_ic_note = "factors are raw cross-sectional z (no sector/size neutralization applied at alpha stage); reported rank_ic IS the screening IC.",
    n_months_ic = diag$n_months_ic,
    subperiod_detail = diag$subperiod,
    decile_returns = diag$decile_returns,
    metric_type = "canonical_screen"),
  portfolio_alpha = list(
    metric_type = "canonical_screen",
    authoritative_note = "NOT forge-authoritative. forge build_bt_result(optimizer weights) is the binding portfolio-alpha t. This is canonical top-N EW long-only screening (contract build_benchmark_compare, NW lag-3).",
    n30 = diag$canonical_screen_n30, n25 = diag$canonical_screen_n25),
  cost_aware = list(
    cost_model_version = "v2.4_kr_retail_15bps", cost_bps_oneway = 15,
    turnover_annual_n30 = diag$canonical_screen_n30$turnover_annual,
    net_basis = TRUE,
    net_alpha_annualized_n30 = diag$canonical_screen_n30$alpha_annualized,
    net_sr_active_n30 = diag$canonical_screen_n30$net_sr,
    note = "All IR/alpha/SR reported NET of 15bps one-way (research_philosophy #2). Turnover ~4.8x/yr (low — value low-turnover, well under 11.0/yr mandate)."),
  uncertainty_aware = list(
    method = "IC-shrinkage scaled alpha-hat (Liao 2025 spirit)",
    alpha_hat_construction = "alpha_hat_i = rank_ic * realized_active_sd_monthly * z_i (cross-sectional z); rank_ic acts as global shrinkage toward 0 given weak IC.",
    realized_active_sd_monthly = diag$realized_active_sd_monthly,
    confidence_basis = "per-name |z| rank-extremity * global ICIR reliability scaler; bounded [0.3,0.9].",
    icir_reliability_note = "monthly ICIR 0.178 is modest; recent-window ICIR 0.092 weaker — point alpha should be read as lower-confidence."),
  diversifier_diagnostic = dv,
  redundancy_cluster_id = "value_cluster",
  alpha_inheritance_cor = NULL,
  alpha_inheritance_cor_note = "discovery WT; this is a measured sleeve not inherited from a parent alpha. return_cor vs incumbent (diagnostic) = -0.030 total / +0.109 active.",
  cor_vs_admitted = dv$active_cor_vs_bm,
  deflated_sharpe_ratio = NA,
  dsr_note = "selection_type=chain/single (1 recipe, not a sweep). Per measurement-graduation §3 (2026-06-10), DSR HARD applies to sweep-selection only; this single de-contam recipe = advisory. DSR not the binding gate; oos_retention + portfolio_alpha_t are.",
  ax001_v2_note = "value is not a defense factor; AX-001 v2 conditional-defense evaluation N/A. Standard SR evaluation applies but standalone fails (see CF-PORTALPHA-LOW).",
  challenge_flags = challenge_flags,
  method_shopping_log = list(
    candidates_tried = 1L,
    method_log = list(list(name = "value4_EW_zcomposite", rank_ic = diag$rank_ic, selected = TRUE)),
    note = "single de-contaminated recipe per request; no factor fishing. candidates_tried=1."),
  red_flags_self = list(
    RF_A3_inverse = "recent IC LOWER than overall (decay), not higher — no overfitting-to-recent flag.",
    RF_A2 = "composite vs single-value baseline improvement not separately measured (single recipe mandate)."),
  status = "ALPHA_DRAFT_PENDING_CODEX",
  generated_by = "alpha-research agent", generated_at = as.character(Sys.time())
)

draft_path <- file.path(mb_dir, "alpha_package_draft.json")
write_json(alpha_package, draft_path, pretty = TRUE, auto_unbox = TRUE, digits = 8, null = "null")
cat("draft written:", draft_path, "\n")
cat("n_names:", length(av), "| as_of:", as_of, "\n")
cat("alpha_hat range:", round(min(unlist(av)),5), round(max(unlist(av)),5), "\n")
