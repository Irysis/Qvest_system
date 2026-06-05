#==============================================================================
# WT-D20260528_003 v3.7 — Step 6: Alpha Package Draft Emission
#
# Honest verdict:
#   - ICIR_neut = 0.453, IC t-stat = 6.81 (Spec A + D PASS)
#   - Subperiod stability = 0.733 (P1/P2/P3 all positive t > 3.3)
#   - DSR z = 5.13 (PASS very strong)
#   - Sector retention: D43 138%, D22 151%, M22 139% (RF-A4 PASS)
#   - RF-A2 PASS: composite (0.453) > best single (0.380)
#   - 5y recent ICIR_neut: D43=0.555, D22=0.448 (very strong)
#
# But graduation FAIL 3 critical:
#   - Harvey 5-spec n_pass = 2/5 (gate 3 fail)
#   - Monotonicity = -0.261 (gate 0.7 fail, non-monotonic decile)
#   - AX-001 v2 bad/normal IC ratio = -0.211 (crisis IC negative)
#
# Top 20 active alpha: +0.22%/m (annualized 2.63%/y), active SR=0.30
# Best single (D22 only) raw IC has higher t-stat than composite Spec B
#
# DRAFT recommendation: graduation FAIL → TERMINATE (honest)
# Alternative: deployment as defensive sleeve only (long-only top 20)
#==============================================================================

suppressPackageStartupMessages({
  library(arrow)
  library(data.table)
  library(jsonlite)
})

BASE <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(BASE)
OUT_DIR <- file.path(BASE, "qepm/mailbox/worktask/WT-D20260528_003/outputs/v3_7")
MAIL_DIR <- file.path(BASE, "qepm/mailbox/worktask/WT-D20260528_003")

cat("[Step 6: alpha_package_draft emission] === START ===\n")

# ---- 1. Load validation ----
val <- fromJSON(file.path(OUT_DIR, "alpha_full_validation.json"), simplifyVector = FALSE)
construct <- fromJSON(file.path(OUT_DIR, "alpha_construct_summary.json"), simplifyVector = FALSE)
sector_neut <- fromJSON(file.path(OUT_DIR, "top12_sector_neut_retention.json"), simplifyVector = FALSE)
single_vs_comp <- fromJSON(file.path(OUT_DIR, "single_vs_composite_diagnostic.json"), simplifyVector = FALSE)

# ---- 2. Load latest alpha_scores ----
alpha <- as.data.table(read_parquet(file.path(OUT_DIR, "alpha_scores.parquet")))
alpha[, Date := as.Date(Date)]
latest_d <- max(alpha$Date)
latest <- alpha[Date == latest_d]
setorder(latest, -alpha_score)

# alpha_vector (latest sig_date, all tickers)
alpha_vector <- setNames(latest$alpha_score, latest$Ticker)

# confidence_vector — z-score absolute -> [0, 1] via tanh transformation
# higher absolute alpha + lower extreme rank stability variance = higher confidence
# Simple: 0.5 + 0.4 * tanh(|alpha_score| / 2) but anchor base 0.5
confidence_vector <- sapply(latest$alpha_score, function(a) {
  c <- 0.4 + 0.4 * tanh(abs(a) / 2)
  pmin(0.95, pmax(0.05, c))
})
names(confidence_vector) <- latest$Ticker

# ---- 3. Factor specs ----
factor_specs <- list(
  list(
    factor_family = "Risk",
    proxy = "D22_Tracking_Error",
    formula = "rolling 252d std(stock_ret - bench_ret) — active risk tracking error",
    lag_rule = "monthly (factor_db Usable_Date <= sig_date)",
    winsorization = "factor_db default (3std)",
    neutralization = "sector (Asness-Frazzini 2013 dummy-mean residualization)",
    economic_rationale = "Active risk premium / idiosyncratic exposure compensation. High-TE stocks demand premium for benchmark-deviation risk.",
    weight_theta = 0.3762,
    icir_raw = 0.252,
    icir_neut = 0.380,
    icir_neut_5y = 0.448,
    references = c("Roll 1992 mean-tracking error", "Grinold-Kahn 1999 active management")
  ),
  list(
    factor_family = "Risk_Higher_Moment",
    proxy = "D43_Skewness",
    formula = "rolling 252d cross-sectional skewness of daily returns",
    lag_rule = "monthly (factor_db)",
    winsorization = "factor_db default",
    neutralization = "sector",
    economic_rationale = "Boyer-Mitton-Vorkink 2010 idiosyncratic skewness preference — investors over-pay for lottery-like skewness, generating ex-post underperformance in high-skew stocks (sign-aligned to negative). High Z_aligned = low expected skew (post-flip)",
    weight_theta = 0.3575,
    icir_raw = 0.261,
    icir_neut = 0.361,
    icir_neut_5y = 0.555,
    references = c("Boyer-Mitton-Vorkink 2010 RFS", "Conrad-Dittmar-Ghysels 2013 JFE")
  ),
  list(
    factor_family = "Lottery",
    proxy = "M22_Max_Return",
    formula = "max daily return in past 21d (MAX anomaly proxy)",
    lag_rule = "monthly (factor_db)",
    winsorization = "factor_db default",
    neutralization = "sector",
    economic_rationale = "Bali-Cakici-Whitelaw 2011 MAX anomaly — extreme positive returns attract retail demand bid up prices, generating ex-post underperformance. Sign-aligned to negative MAX.",
    weight_theta = 0.2663,
    icir_raw = 0.193,
    icir_neut = 0.269,
    icir_neut_5y = 0.240,
    references = c("Bali-Cakici-Whitelaw 2011 JFE", "Asness-Moskowitz-Pedersen 2013")
  )
)

# ---- 4. Diagnostics ----
diagnostics <- list(
  rank_ic = val$ic_diagnostics$rank_ic_mean,
  icir = val$ic_diagnostics$icir,
  rank_ic_t_stat = val$ic_diagnostics$rank_ic_t,
  n_dates = val$ic_diagnostics$n_dates,
  monotonicity = val$monotonicity$spearman_decile_rank,
  subperiod_stability = 0.733,
  turnover_proxy = val$turnover$turnover_proxy,
  post_neutralization_ic = val$ic_diagnostics$rank_ic_mean,  # already neutralized
  harvey_t_stat = val$harvey_5spec$spec_A_spearman,
  harvey_5spec_pass_3 = val$harvey_5spec$n_pass_3,
  harvey_5spec_pass_25 = val$harvey_5spec$n_pass_25,
  harvey_5spec_detail = val$harvey_5spec,
  dsr_z = val$dsr$dsr_z,
  dsr_prob = val$dsr$dsr_prob,
  decile_d10_minus_d1 = val$monotonicity$d10_minus_d1,
  decile_means = val$monotonicity$decile_means,
  bad_normal_ic_ratio = val$ax_001_v2$bad_normal_ratio,
  bad_normal_n_crisis = val$ax_001_v2$crisis_n_dates,
  bad_normal_n_normal = val$ax_001_v2$normal_n_dates,
  top20_active_alpha_monthly = "0.2188%",
  top20_active_alpha_annualized = "2.63%",
  top20_active_sr_annualized = 0.303,
  top20_subperiod_P1 = "+2.37%/y (t=0.86)",
  top20_subperiod_P2 = "+2.84%/y (t=0.94)",
  top20_subperiod_P3 = "+3.04%/y (t=0.55)"
)

# ---- 5. Challenge flags ----
challenge_flags <- list(
  list(id = "RF-A2", severity = "RESOLVED",
       description = "Composite (ICIR 0.453) > best single (D22 0.380). v1/v3.5/v3.6 3 cycles FAIL 후 첫 PASS.",
       resolution = "Top 3 selective composite + ICIR-proportional weights + sector neutralized"),
  list(id = "RF-A4", severity = "RESOLVED",
       description = "Sector retention D22=151%, D43=138%, M22=139% — sector tilt 제거 후 알파 강화 (v3.6 lesson 정합)",
       resolution = "Asness-Frazzini 2013 dummy-mean residualization 사전 적용 (Step 2)"),
  list(id = "RF-A6_HARVEY", severity = "HIGH",
       description = "Harvey 5-spec n_pass = 2/5 (gate 3). Spec A (rank IC t=6.81) + Spec D (NW t=6.92) PASS. Spec B/C/E FAIL (linear correlation + decile spread + quintile spread 약함).",
       implication = "Cross-section rank IC는 강하나 decile-extreme spread가 약함 — non-monotonic alpha"),
  list(id = "RF-A8_MONOTONICITY", severity = "HIGH",
       description = "Decile monotonicity Spearman = -0.261 (gate 0.7 fail). D10-D1 spread = 0.03%/m (t=0.54). Top decile 대비 mid decile (D3) outperformance가 더 큼.",
       implication = "Top 20 long-only selection은 alpha potential의 일부만 capture (active SR 0.30)"),
  list(id = "RF-AX001_v2_CRISIS", severity = "HIGH",
       description = "AX-001 v2 bad/normal IC ratio = -0.211. Crisis 9 dates (2008/2011/2020/2022) 평균 IC = -0.010 (정상 +0.046 대비).",
       implication = "방어형 알파 아님 — risk_premium 알파 family (active risk + lottery aversion + skewness preference)는 crisis 시 mean reversion 실패"),
  list(id = "AX-007_SLEEVE_DESIGN", severity = "MEDIUM",
       description = "Single-sleeve long-only top 20 = AX-007 hard FAIL (mechanism break)",
       resolution = "alpha_score 자체는 score-based universe alpha vector (350 ticker). Optimizer 단계에서 multi-sleeve 분리 가능 (skewness sleeve 10 + lottery sleeve 10) — 그러나 본 alpha의 D22+D43+M22가 mechanism-distinct 하므로 multi-sleeve 의미 있음"),
  list(id = "GRADUATION_FAIL", severity = "BLOCKER",
       description = "3 critical gates FAIL: Harvey 2/5, Monotonicity -0.26, Bad/Normal -0.21",
       recommendation = "alpha_discovery_certificate 발급 부적격. STR_1722 family TERMINATE 권고 (honest)")
)

# ---- 6. Method shopping log ----
method_log <- list(
  list(name = "Top12 single factor IC", rank_ic = 0.025, icir = 0.275, selected = FALSE,
       comment = "Phase 1+3 inherited orthogonal selection"),
  list(name = "Sector neutralize per factor", retention_avg = 0.86, selected = TRUE,
       comment = "Step 2 — sector retention 100%+ for D22/D43/M22"),
  list(name = "ALL12 equal-weight composite", icir = 0.432, selected = FALSE),
  list(name = "TOP6 composite", icir = 0.409, selected = FALSE),
  list(name = "TOP5 composite", icir = 0.439, selected = FALSE),
  list(name = "TOP4_DIST_LOTTERY composite", icir = 0.413, selected = FALSE),
  list(name = "TOP3 D22+D43+M22 ICIR-proportional composite", icir = 0.453, selected = TRUE,
       comment = "Best composite — RF-A2 PASS, t=6.81, subperiod stability 0.73"),
  list(name = "HIGH_RETENTION_9 composite", icir = 0.441, selected = FALSE)
)

# ---- 7. Compile draft package ----
draft <- list(
  task_id = "WT-D20260528_003",
  wt_type = "discovery",
  schema_version = "alpha_package_v1",
  as_of_date = "2026-05-28",
  signal_cutoff = "2023-12-22",
  forecast_horizon = "1M",
  universe = "KOSPI200 ∪ KOSDAQ150 intersection (n_ticker ~ 350 at sig_date)",
  benchmark = "KOSPI200_total_return",
  hypothesis_title = "STR_1722 Factor DB Untapped Top 12 + Sector-Neutralized Top 3 Composite",
  hypothesis_description = paste(
    "Two-axis alpha source discovery — Phase 1+3 lineage (factor_db_untapped 269 factor scan → 12 orthogonal Top-K).",
    "v3.7 alpha-research applied: (1) Top 12 single factor IC re-verification under K200∪KQ150 + Spearman vs fwd_ret;",
    "(2) Sector neutralization sector tilt mitigation (Asness-Frazzini 2013); (3) Single vs Composite RF-A2 sentinel.",
    "Selected: TOP3 composite (D22_Tracking_Error + D43_Skewness + M22_Max_Return) ICIR-proportional weights.",
    "Result: ICIR_neut=0.453, IC t=6.81, subperiod stability 0.73, sector retention 138~151%.",
    "But 3 critical FAIL: Harvey 2/5, monotonicity -0.26, bad/normal -0.21.",
    "Verdict: alpha exists but graduation FAIL — honest TERMINATE recommendation."
  ),
  alpha_vector = as.list(round(alpha_vector, 4)),
  confidence_vector = as.list(round(confidence_vector, 3)),
  signal_matrix_ref = "qepm/mailbox/worktask/WT-D20260528_003/outputs/v3_7/alpha_scores.parquet",
  selection_objective = "icir",  # R4 P3 mandate
  factor_specs = factor_specs,
  diagnostics = diagnostics,
  graduation_evaluation = list(
    rank_ic = list(value = val$ic_diagnostics$rank_ic_mean, gate = 0.04, pass = TRUE),
    icir = list(value = val$ic_diagnostics$icir, gate = 0.20, pass = TRUE),
    subperiod_stability = list(value = 0.733, gate = 0.5, pass = TRUE),
    harvey_t_pass_3 = list(value = val$harvey_5spec$n_pass_3, gate = 3, pass = FALSE,
                            critical_blocker = TRUE),
    monotonicity = list(value = val$monotonicity$spearman_decile_rank, gate = 0.7, pass = FALSE,
                         critical_blocker = TRUE),
    bad_normal_ic_ratio = list(value = val$ax_001_v2$bad_normal_ratio, gate = 0.5, pass = FALSE,
                                critical_blocker_axiom = "AX-001 v2"),
    dsr = list(value = val$dsr$dsr_z, gate = 0.5, pass = TRUE),
    sector_retention_gte_50pct = list(value = "138%/150%/139% (D22/D43/M22)", gate = "50%", pass = TRUE),
    rf_a2_composite_gte_single = list(value = TRUE, gate = TRUE, pass = TRUE),
    overall_graduation = list(pass = FALSE,
                               critical_fail_count = 3,
                               recommendation = "TERMINATE — graduation gate insufficient")
  ),
  method_shopping_log = list(
    candidates_tried = length(method_log),
    method_log = method_log,
    parallel_exec = FALSE,
    rcpp_used = FALSE
  ),
  challenge_flags = challenge_flags,
  ax_axiom_compliance = list(
    AX_001_v2 = "FAIL — bad/normal ratio -0.211 (crisis IC negative)",
    AX_002 = "PASS — no PIT bypass / no rationalization labels detected",
    AX_003 = "N/A — no Value family used",
    AX_004 = "N/A — Quality (Q07/Q11/Q32) excluded due to low sector retention",
    AX_005 = "PARTIAL — defense family (low_vol) not used; this is risk_premium family",
    AX_007 = "DESIGN_INTENT — alpha_score = universe score; multi-sleeve handed to Optimizer",
    AX_008 = "PENDING — triangulation requires Risk + Optimizer downstream + Codex Round"
  ),
  pit_c1_c15_compliance = list(
    C1 = "PASS — full PIT walk-forward, no full-sample stats",
    C13 = "PASS — Z_Score_Aligned via load_month_factors() (no NEGATE_FACTORS)",
    C14 = "PASS — Usable_Date <= sig_date auto via connector",
    C15 = "PASS — load_month_factors() connector used (no direct parquet read)",
    sector_data_source = ".cache/rawdata.parquet Sector column (contemporaneous categorical, PIT-OK)"
  ),
  lineage = list(
    phase_1 = "factor_db_untapped_icir_ranking.parquet (269 factor scan)",
    phase_3 = "phase3_orthogonal_top_k.parquet (12 factor selection)",
    phase_4 = "v3.7 alpha-research (Top 12 → TOP3 selective composite)",
    inherited_from = "Factor DB infrastructure (288 factor monthly + 309 daily)",
    refs = c("Phase 1 ICIR_5y D43=0.842 / D44=0.804 / L44=-0.786 (univ-restricted measurement)",
              "v3.7 K200∪KQ150 IC: D43_neut ICIR=0.361 / D22_neut ICIR=0.380 / M22_neut ICIR=0.269")
  ),
  honest_verdict = list(
    summary = "Alpha exists but weak — composite ICIR 0.453 with t=6.81 strong, but decile non-monotonic + crisis IC negative + Harvey 5-spec 2/5",
    top20_active_alpha_annualized_pct = 2.63,
    top20_active_sharpe_ratio = 0.303,
    deployment_readiness = "NOT_READY — graduation gates 3 critical FAIL",
    recommendation_primary = "TERMINATE STR_1722 family v3.7 — honest with v1/v3.5/v3.6 lesson",
    recommendation_alternative = "Deploy as defensive sleeve only (long-only top 20 with active SR 0.30) — but does NOT meet PG1 admission",
    decision_authority = "Q-Lead (도훈 confirm required) per Charter §5 Data Mining 방지"
  )
)

# ---- 8. Save draft ----
write_json(draft, file.path(MAIL_DIR, "alpha_package_draft.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "null")
cat("  saved: alpha_package_draft.json (", file.size(file.path(MAIL_DIR, "alpha_package_draft.json")), "bytes)\n")

# Lineage record
source(file.path(BASE, "02_Infrastructure/worktask/lineage_utils.R"))
record_package_lineage(
  task_id = "WT-D20260528_003",
  package_type = "alpha_package",
  method_selected = "TOP3 selective composite (D22+D43+M22) sector-neutralized, ICIR-proportional weights",
  input_file_paths = c(
    file.path(BASE, ".cache/rawdata.parquet"),
    file.path(BASE, ".cache/universe_support/us_k200.parquet"),
    file.path(BASE, ".cache/universe_support/us_kq150.parquet"),
    file.path(BASE, "02_Infrastructure/factor_db/factor_registry.json"),
    file.path(BASE, "04_Research/decision_framework/factor_untapped/outputs/phase3_orthogonal_top_k.parquet")
  )
)
cat("  lineage recorded\n")

cat("\n[Step 6] === DRAFT EMITTED — Codex Round 5-step engaged === \n")
