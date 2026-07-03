#==============================================================================
# WT-D20260614_003 — alpha_package.json builder (FINAL, post-Codex REVISE)
# Role: alpha-research. Alpha-hat only. NO covariance / weights / optimization.
# Reflects Codex Critic corrections: defense thesis withdrawn, active-cor 0.42,
# DSR multiplicity, RF-A4 sector-neutral, RF-A2 composite-vs-single, PIT chain.
#==============================================================================
suppressPackageStartupMessages({library(jsonlite); library(data.table)})
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
WT <- "WT-D20260614_003"
AF <- file.path(ROOT, "stage_artifacts", "WT_D20260614_003")
MB <- file.path(ROOT, "qepm", "mailbox", "worktask", WT)
args <- commandArgs(trailingOnly = TRUE); MODE <- if (length(args) >= 1) args[1] else "final"
`%||%` <- function(a,b) if(is.null(a)||length(a)==0||(length(a)==1&&is.na(a))) b else a

d   <- readRDS(file.path(AF, "diag.rds"))
v   <- readRDS(file.path(AF, "vectors.rds"))
uc  <- tryCatch(fromJSON(file.path(AF, "universe_comparison.json")), error=function(e) NULL)
sup <- tryCatch(fromJSON(file.path(AF, "codex_supplements.json")), error=function(e) NULL)

CRISIS_T1_ALPHA <- -0.0044; CRISIS_T1_HIT <- 0.46
COR_ACTIVE_STR1715 <- if(!is.null(sup)) sup$l219_str1715_corr$cor_active else 0.415
DSR_N23  <- if(!is.null(sup)) sup$rf_a6_dsr_multiplicity$dsr_n23_cluster else 0.058
DSR_N409 <- if(!is.null(sup)) sup$rf_a6_dsr_multiplicity$dsr_n409_batch else 0.005
SN_RET   <- if(!is.null(sup)) sup$rf_a4_sector_neutral$retention_pct else 84.2
COMP_VS_SINGLE <- if(!is.null(sup)) sup$rf_a2_single_vs_composite$composite_improve_pct else -10.0

factor_specs <- list(
  list(factor_family="Quality", proxy="GP/Assets", factor_id="Q01_GPA",
       formula="GrossProfit / TotalAssets", lag_rule="quarterly 45d (Factor_Date <= sig_date, C4/C14)",
       winsorization="1%/99%", neutralization="cross-sectional z (raw quality tilt)", direction="higher_better",
       economic_rationale="Gross profitability (Novy-Marx 2013): cleanest pre-accrual profitability; persists OOS, proxies durable advantage.",
       redundancy_cluster_id="quality_profitability", single_icir=0.132, weight_theta=0.25, references=c("Novy-Marx 2013 JFE","AFP QMJ 2019")),
  list(factor_family="Quality", proxy="Piotroski F-Score", factor_id="Q04_Piotroski_F",
       formula="9-point financial-strength score", lag_rule="quarterly 45d (Factor_Date <= sig_date)",
       winsorization="1%/99%", neutralization="cross-sectional z", direction="higher_better",
       economic_rationale="Piotroski (2000): fundamental-momentum composite separating strengthening from deteriorating firms.",
       redundancy_cluster_id="quality_fundamental_strength", single_icir=0.362, weight_theta=0.25,
       note="BEST single component (ICIR 0.362 > composite 0.326).", references=c("Piotroski 2000 JAR")),
  list(factor_family="Quality", proxy="CFO/Assets", factor_id="Q09_CFOA",
       formula="OperatingCashFlow / TotalAssets", lag_rule="quarterly 45d (Factor_Date <= sig_date)",
       winsorization="1%/99%", neutralization="cross-sectional z", direction="higher_better",
       economic_rationale="Cash-based profitability (Sloan 1996 / Bouchaud 2019): avoids accrual manipulation.",
       redundancy_cluster_id="quality_profitability", single_icir=0.262, weight_theta=0.25, references=c("Sloan 1996 AR","Bouchaud-Krueger-Landier-Thesmar 2019 JF")),
  list(factor_family="Quality", proxy="Earnings Stability", factor_id="Q07_Earnings_Stability",
       formula="1 - sd(earnings changes 5y) / mean(|earnings changes|)", lag_rule="quarterly 45d (Factor_Date <= sig_date)",
       winsorization="1%/99%", neutralization="cross-sectional z", direction="higher_better",
       economic_rationale="Earnings stability (Dichev-Tang 2009): low earnings vol predicts lower crash risk.",
       redundancy_cluster_id="quality_low_vol_earnings", single_icir=0.268, weight_theta=0.25, references=c("Dichev-Tang 2009 JAE"))
)

diagnostics <- list(
  metric_type="canonical_screen",
  metric_type_note="rank-IC = monthly Spearman(score, fwd 1M ret). portfolio_alpha_t = canonical_screen_bt top30 EW long-only net-15bps (contract build_benchmark_compare NW lag-3). NOT forge-authoritative.",
  rank_ic=round(d$rank_ic,4), icir=round(d$icir,3), ic_std=round(d$ic_sd,4), n_ic_months=d$n_ic,
  harvey_t_stat=round(d$harvey_t_nw3,3),
  harvey_t_basis="rank-IC NW lag-3 t-stat (cross-sectional rank power). DISTINCT from portfolio_alpha_t (0.577).",
  monotonicity=round(d$monotonicity,3), subperiod_stability=round(d$subperiod_stability,3),
  subperiod_ic=list(p1_2005_2013=round(as.numeric(d$subperiod_ic$p1_2005_2013),4),
                    p2_2014_2019=round(as.numeric(d$subperiod_ic$p2_2014_2019),4),
                    p3_2020_2026=round(as.numeric(d$subperiod_ic$p3_2020_2026),4)),
  ic_decay_note="rank-IC magnitude DECAYS monotonically (0.052->0.027->0.0165). Sign stable. Cohort-wide quality decay, NOT recency overfit (RF-A3 recent/full ratio 0.92).",
  composite_vs_best_single_icir_pct=COMP_VS_SINGLE,
  composite_note=sprintf("RF-A2: composite ICIR 0.326 is %.1f%% vs best single Q04_Piotroski_F (0.362). Composite does NOT beat best component; justification is breadth/robustness only.", COMP_VS_SINGLE),
  sector_neutral_ic=0.0294, sector_neutral_retention_pct=SN_RET,
  sector_neutral_note=sprintf("RF-A4: sector-neutral IC retains %.1f%% of raw (0.0294 vs 0.0349). NOT a sector bet.", SN_RET),
  turnover_proxy_annual_2sided=round(d$turnover_annual,2),
  turnover_one_way_per_rebalance=0.163, turnover_one_way_annual=1.96, name_retention_m_to_m=0.84,
  turnover_note="LOW turnover: 84% m/m name retention (16% churn). One-way ~1.96x/yr — within TO<=11/yr (P6). Confirmed strength.",
  post_neutralization_ic=round(d$rank_ic,4)
)

portfolio_alpha <- list(
  metric_type="canonical_screen",
  portfolio_alpha_t_nw_lag3=round(d$portfolio_alpha_t_nw_lag3,3),
  portfolio_alpha_t_pvalue=round(d$portfolio_alpha_t_pvalue,3),
  information_ratio_active=round(d$information_ratio,3), net_active_sr=round(d$net_sr,3),
  alpha_annualized=round(d$alpha_annualized,4), n_months=d$T_obs, cost_bps_oneway=15, top_n_diagnostic=30,
  max_names_deployment=25,
  warning="portfolio_alpha_t = 0.577 (p=0.564) INSIGNIFICANT standalone. IR_active ~0.08. FAILS graduation HARD (PORT_t>=2.95). top30 is DIAGNOSTIC-only; any deployment max_names=25 hard.",
  authoritative_note="forge build_bt_result remains binding for admission. This is a screening proxy."
)

ax001_v2 <- list(
  alpha_type_claimed="defense_factor", alpha_type_final="screening_tier_quality_lead",
  axiom="AX-001_v2", evaluation_axes=3, defense_thesis="WITHDRAWN (post-Codex)",
  axis_1_crisis_alpha=list(
    crisis_months_n=d$crisis_n,
    concurrent_label=list(crisis_alpha_mean=round(d$crisis_alpha_mean,4), hit=round(d$crisis_hit,3),
      note="concurrent same-month regime label = DIAGNOSTIC ATTRIBUTION only, not tradeable (Codex C9)."),
    t1_lagged_label=list(crisis_alpha_mean=CRISIS_T1_ALPHA, hit=CRISIS_T1_HIT,
      note="t-1 lagged (PIT-correct, decision-time) crisis_alpha = -0.44%/mo, hit 46%."),
    verdict="FAIL (PIT-correct). Positive concurrent crisis_alpha was a same-month-labeling artifact; t-1 lagged is NEGATIVE."),
  axis_2_mdd_complement=list(
    sleeve_net_mdd=round(d$sleeve_net_mdd,3), benchmark_mdd=round(d$bm_mdd,3), cor_vs_benchmark=-0.027,
    cor_active_vs_incumbent_STR1715=round(COR_ACTIVE_STR1715,3),
    note="CORRECTED (Codex C6/L-219): draft claimed low-cor diversifier on BENCHMARK basis (-0.027). Correct basis = ACTIVE cor vs incumbent STR_1715 = 0.42 (> 0.30 Seq-Admission). Shares ~42% active variance with incumbent.",
    verdict="FAIL — standalone MDD worse than BM AND active cor 0.42 (not a diversifier)."),
  axis_3_bad_normal_ic_ratio=list(ic_bad=round(d$ic_bad,4), ic_normal=round(d$ic_normal,4),
    ratio=round(d$bad_normal_ic_ratio,3), threshold=1.5,
    verdict="FAIL (0.58 < 1.5) — ranking power weakens in crisis."),
  ax001_v2_summary="DEFENSE THESIS WITHDRAWN. All 3 axes FAIL under PIT-correct measurement. NOT a defense_factor, NOT a cross-family diversifier (active cor 0.42). Screening-tier quality lead only. Recommend NO defense-sleeve admission on current evidence."
)

dsr_block <- list(
  deflated_sharpe_ratio_n1=round(d$dsr,3), dsr_n23_cluster=round(DSR_N23,3), dsr_n409_batch=round(DSR_N409,3),
  selection_type="sweep_selected (cluster23 rep from 409-batch)",
  severity="HARD-relevant (selection operator, Codex C7)",
  note="CORRECTED (Codex RF-A6): n_trials=1 understated multiplicity. Alpha was SELECTED as cluster23 rep from 409-batch. Under cluster multiplicity DSR=0.058 (<0.5); under batch DSR=0.005. After selection-path correction DSR does NOT survive. Reinforces screening-tier verdict."
)

universe_comparison <- if(!is.null(uc)) uc else list(status="unavailable")
universe_comparison$interpretation <- "L-227 mandate (weak IR trigger): broader FREEFLOAT IMPROVES rank-IC (0.034->0.054) and ICIR (0.32->0.59) — top342 IC was universe-restricted. BUT portfolio_alpha_t gets WORSE (0.58->-0.07) and IR negative. Cross-sectional rank gains do NOT translate to long-only top-30 portfolio alpha (Cycle 2 lesson: rank-IC t != portfolio-alpha t)."

strengths_weaknesses <- list(
  strengths=list(
    low_turnover="84% m/m name retention, ~1.96x one-way/yr — genuinely slow quality sleeve (CONFIRMED)",
    sector_robust=sprintf("sector-neutral IC retains %.1f%% — not a sector bet (RF-A4 PASS)", SN_RET),
    rank_ic_sign_stable="rank-IC positive in all 3 subperiods; Harvey-t NW3 = 5.12 full sample",
    ic_in_broad_universe="ICIR rises to 0.59 in FREEFLOAT — real cross-sectional signal exists"),
  weaknesses=list(
    weak_ir="portfolio_alpha_t 0.577 (insignificant), IR_active ~0.08 — core weakness CONFIRMED",
    defense_withdrawn="t-1 crisis_alpha NEGATIVE (-0.44%/mo); AX-001 v2 all 3 axes FAIL",
    active_cor_incumbent="active cor vs STR_1715 = 0.42 (> 0.30) — NOT a diversifier on active basis",
    composite_no_edge="composite ICIR -10% vs best single Piotroski-F",
    dsr_selection="DSR collapses to 0.058 (cluster) / 0.005 (batch) under selection multiplicity",
    ic_decay="rank-IC magnitude decaying to ~1/3 of early-period power",
    standalone_mdd="MDD -52.2% (worse than BM -48.5%)")
)

alpha_vector <- as.list(v$alpha_vector); confidence_vector <- as.list(v$conf_vector)

method_log <- list(candidates_tried=1L, selection_objective="rank_ic", parallel_exec=FALSE,
  selection_path_note="Alpha is cluster23 rep SELECTED from 409-batch — effective selection multiplicity n~23 (cluster) to 409 (batch). DSR reported accordingly.",
  method_log=list(list(name="Q01_GPA+Q04_Piotroski_F+Q09_CFOA+Q07_Earnings_Stability EW z-composite",
    rank_ic=round(d$rank_ic,4), icir=round(d$icir,3), selected=TRUE,
    note="Decontaminated cluster23 recipe (ML_12_svm label = codegen contamination).")))

challenge_flags <- list(
  list(id="CF-1", severity="HIGH", flag="Standalone portfolio_alpha_t = 0.577 (p=0.564) INSIGNIFICANT; IR_active ~0.08. FAILS graduation HARD (PORT_t>=2.95). Screening-tier only.", codex="C1 ACCEPT"),
  list(id="CF-2", severity="HIGH", flag="DEFENSE THESIS WITHDRAWN: t-1 lagged crisis_alpha NEGATIVE (-0.44%/mo). Concurrent +1.93% was same-month labeling artifact. AX-001 v2 all 3 axes FAIL.", codex="C2/C9 ACCEPT"),
  list(id="CF-3", severity="HIGH", flag="Active cor vs incumbent STR_1715 = 0.42 (> 0.30 Seq-Admission). Draft 'low-cor diversifier' claim CORRECTED — diversification was measured on wrong (benchmark) basis.", codex="C6/L-219 ACCEPT"),
  list(id="CF-4", severity="MEDIUM", flag="DSR collapses under selection multiplicity: n1=0.651 -> n23=0.058 -> n409=0.005. Alpha was selected from 409-batch; n_trials=1 understated.", codex="C7/RF-A6 ACCEPT"),
  list(id="CF-5", severity="MEDIUM", flag="Composite ICIR -10% vs best single Q04_Piotroski_F (0.326 vs 0.362). 4-factor EW does NOT beat best component (Charter §5 composite-overfit caution).", codex="RF-A2 self-flag"),
  list(id="CF-6", severity="MEDIUM", flag="AX-007: single-sleeve long-only top-N quality = mechanism-break pattern. Exception (multi-sleeve) only holds CONDITIONALLY via optimizer book-integration, not standalone.", codex="C3 PARTIAL"),
  list(id="CF-7", severity="LOW", flag="rank-IC magnitude decay 0.052->0.0165 across subperiods (sign stable). Cohort-wide quality decay.", codex="RF-A1 caveat"),
  list(id="CF-8", severity="LOW", flag="PIT C4/C14: lag enforced UPSTREAM (Factor_Date in fundamental_dart_quarterly + registry Factor_Date<=sig_date + compute_quality Date<=sig_d + load_month_factors C15 boundary). NOT carried into alpha_scores — document, persist Factor_Date in future runs.", codex="C5 PARTIAL"),
  list(id="CF-9", severity="LOW", flag="request liquidity 5e7 < constitutional 2e8; applied 2e8 (conservative). cost v2.4_15bps consistent with KR_top342. If optimizer uses FREEFLOAT, bump to 20bps (mandate_compliance).", codex="-")
)

pit_chain <- list(
  c4_c14_chain=c("fundamental_dart_quarterly.parquet carries Factor_Date (publication-lagged usable date)",
                 "factor_registry lag_rule (all 4) = 'Factor_Date <= sig_date'",
                 "compute_quality.R snapshots Date <= sig_d only",
                 "load_month_factors() = C15-safe connector boundary (no direct parquet load)",
                 "align_factor_direction uses Usable_Date <= sig_date for IC direction"),
  c9_note="Selection (score) is strictly t-1/PIT. Concurrent regime labeling was DIAGNOSTIC attribution only; t-1 lagged regime reported for tradeable verdict. No look-ahead in the alpha signal itself.",
  c13_c15="PASS (Codex agrees). No NEGATE/FLIP; Z_Score_Aligned only; connector-routed.",
  audit_gap="Factor_Date lineage not persisted into alpha_scores.parquet — upstream-verified, not output-auditable."
)

alpha_package <- list(
  task_id=WT, wt_type="discovery", alpha_type="screening_tier_quality_lead",
  as_of_date=d$as_of, forecast_horizon="1M", rebalance_frequency="monthly",
  universe=list(label="KOSPI200_KOSDAQ150_intersection (KR_top342)", liquidity_min_won_20d_avg=2e8,
    liquidity_note="request 5e7 < 2e8; applied 2e8 hard floor (conservative).",
    cost_model_version="v2.4_kr_retail_15bps", n_names_latest=d$n_names_latest,
    n_months_panel=d$n_months_panel, period="2005-01 .. 2026-06"),
  selection_objective="rank_ic",
  alpha_vector=alpha_vector, confidence_vector=confidence_vector,
  signal_matrix_ref="stage_artifacts/WT_D20260614_003/alpha_scores.parquet",
  alpha_latest_ref="stage_artifacts/WT_D20260614_003/alpha_latest.parquet",
  sleeve_monthly_ref="stage_artifacts/WT_D20260614_003/sleeve_monthly.parquet",
  factor_specs=factor_specs, diagnostics=diagnostics, portfolio_alpha=portfolio_alpha,
  ax001_v2=ax001_v2, dsr=dsr_block, universe_comparison=universe_comparison,
  strengths_weaknesses=strengths_weaknesses, method_shopping_log=method_log,
  pit_chain=pit_chain, challenge_flags=challenge_flags,
  codex_round=list(stance="REVISE", veto_flag=FALSE, disposition="accepted with material spec downgrades",
    challenge_note="qepm/mailbox/worktask/WT-D20260614_003/challenge_note.md",
    response="qepm/mailbox/worktask/WT-D20260614_003/codex_critic_response_alpha.json",
    accept=c("C1","C2","C7","C9","RF-A2"), partial=c("C3","C5"), rebuttal=c("C4(scope)","RF-A4")),
  alpha_inheritance=list(
    note="Decontaminated from 409-batch cluster23 ML_12_svm (label=codegen contamination). Actual recipe = 4 quality factor EW. SELECTED from 409-batch (selection multiplicity).",
    alpha_inheritance_cor=NA,
    baseline_409batch=list(CAGR=0.122,Sharpe=0.61,IR=0.105,MDD=0.467,turnover=1.089,severe45=1,corr_core=0.87)),
  baseline_reconciliation=list(
    note="QEPM canonical-screen (2e8 liq + strict K200uKQ150 + canonical month-end + proper monthly BM) vs 409-batch baseline.",
    sharpe_total_mine=0.535, sharpe_baseline=0.61, cagr_mine=0.101, cagr_baseline=0.122,
    mdd_mine=-0.522, mdd_baseline=-0.467, ir_active_mine=round(d$information_ratio,3), ir_baseline=0.105,
    turnover_oneway_annual_mine=1.96,
    bug_disclosure="Initial run produced inflated IR 0.70 / port_t 5.9 from TWO measurement bugs: (1) per-ticker (not market-wide) month-end dates scrambling sig_date alignment, (2) daily BM_Ret used as monthly benchmark (C11 time-axis). BOTH FIXED before any reported figure (governance_log). Final figures consistent with baseline.",
    reconciliation_verdict="Consistent within universe/liq-floor differences. IR weakness + low-TO confirmed."),
  final_verdict="SCREENING-TIER quality research-lead. FAILS graduation HARD (portfolio_alpha_t 0.577) standalone; defense thesis WITHDRAWN (t-1 crisis_alpha negative, all AX-001 v2 axes FAIL); active cor vs incumbent 0.42 (not a diversifier); DSR fails under selection multiplicity. RECOMMENDATION: NO standalone graduation, NO defense-sleeve admission on current evidence. Optional downstream: (a) DPL input feature (research_philosophy §5), (b) Piotroski-F single-factor re-test (dominates composite ICIR).",
  emitted_by="alpha-research", emitted_at=format(Sys.time(),"%Y-%m-%dT%H:%M:%S%z"),
  status=if(MODE=="final") "ALPHA_DONE" else "DRAFT"
)

outfile <- if(MODE=="final") file.path(MB,"alpha_package.json") else file.path(MB,"alpha_package_draft.json")
write_json(alpha_package, outfile, pretty=TRUE, auto_unbox=TRUE, na="null", digits=8)
cat("WROTE:", outfile, " mode=", MODE, "\n")

validation <- list(task_id=WT,
  graduation_check=list(
    rank_ic=list(value=round(d$rank_ic,4),threshold=0.04,severity="advisory",pass=d$rank_ic>=0.04),
    icir=list(value=round(d$icir,3),threshold=0.20,severity="advisory",pass=d$icir>=0.20),
    subperiod_stability=list(value=d$subperiod_stability,threshold=0.50,severity="advisory",pass=d$subperiod_stability>=0.50),
    harvey_t_rank_ic=list(value=round(d$harvey_t_nw3,3),threshold=3.0,severity="advisory",pass=d$harvey_t_nw3>=3.0),
    portfolio_alpha_t_nw=list(value=round(d$portfolio_alpha_t_nw_lag3,3),threshold=2.95,severity="hard",pass=FALSE,note="canonical-screen proxy; FAILS standalone."),
    dsr_selection_corrected=list(value_n1=round(d$dsr,3),value_n23=round(DSR_N23,3),value_n409=round(DSR_N409,3),threshold=0.50,severity="hard_sweep",pass=DSR_N23>=0.5,note="selection multiplicity (cluster23/409-batch) — fails.")),
  defense_check_ax001_v2=ax001_v2, pit_chain=pit_chain, universe_comparison=universe_comparison,
  codex_supplements=sup,
  verdict="SCREENING-TIER. FAILS graduation HARD (portfolio_alpha_t 0.577 + DSR-selection). Defense WITHDRAWN. NO standalone graduation / NO defense-sleeve admission on current evidence. AX-001 v2: not applicable (all axes FAIL).")
write_json(validation, file.path(AF,"alpha_validation.json"), pretty=TRUE, auto_unbox=TRUE, na="null", digits=8)
cat("WROTE: alpha_validation.json\n")
