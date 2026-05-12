# Build alpha_package_draft.json from alpha_validation.json + alpha_scores.parquet
suppressPackageStartupMessages({library(arrow); library(data.table); library(jsonlite)})

PROJ_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_ID <- "WT-D20260511_001"
STAGE_DIR <- file.path(PROJ_ROOT, "stage_artifacts", "WT_D20260511_001")
WT_DIR <- file.path(PROJ_ROOT, "qepm/mailbox/worktask", WT_ID)

alpha_scores <- as.data.table(read_parquet(file.path(STAGE_DIR, "alpha_scores.parquet")))
cat("alpha_scores rows:", nrow(alpha_scores), "\n")

latest_sig <- max(alpha_scores$sig_date)
alpha_latest <- alpha_scores[sig_date == latest_sig]
cat("Latest sig_date:", as.character(latest_sig), "  N tickers:", nrow(alpha_latest), "\n")

alpha_vector <- as.list(setNames(round(alpha_latest$alpha, 6), alpha_latest$Ticker))
confidence_vector <- as.list(setNames(round(alpha_latest$confidence, 4), alpha_latest$Ticker))

val <- fromJSON(file.path(STAGE_DIR, "alpha_validation.json"))
diag <- val$diagnostics

alpha_package_draft <- list(
  task_id = WT_ID,
  wt_type = "discovery",
  package_kind = "alpha_package_draft",
  as_of_date = as.character(latest_sig),
  forecast_horizon = "1M",
  agent = list(agent_id = "alpha-research-WT-D20260511_001",
               agent_type = "alpha-research",
               agent_version = "v1.2",
               model = "Opus_4_7_1M"),
  hypothesis = list(
    title = "4th Orthogonal Alpha Source — KR 3-Axis Vol/Skew Composite (Sector-Neutral)",
    description = "S4 v2 baseline (50% STR_1715 H1 + 25% TSMOM_8_ETF + 20% KR_10y + 5% Cash, SR 1.665, gap +0.335 to SR 2.0 target)에 추가할 4th orthogonal alpha source. KR equity universe (KOSPI200 ∪ KOSDAQ150)에서 3-axis volatility-skewness composite (D43_Skewness + D41_Vol_of_Vol + D58_Vol_Asymmetry), sector-neutral, expanding direction-align PIT-strict 36m burn-in. Lottery preference penalty mechanism: 한국 투자자 over-pay for skewed/vol-of-vol/downside-risk → low-skew/low-vol-of-vol/low-downside-asymmetry stocks earn higher 1M return.",
    expected_role = "core_secondary_diversifier (cross-section vol/skew defensive, S4 baseline과 orthogonal)",
    why_now = "S4 v2 baseline SR 1.665 (gap +0.335 vs target 2.0). 5 path 4th orthogonal source saturation (L-285) 후 cross-section vol/skew family 우회 시도. STR_1715 (Q07/C01/C04/Q04 factor specs)와 D-family 직교성 확보. cor S4 -0.135 (실측, target <0.30 PASS). crisis cor -0.338 (강한 hedge)."
  ),
  selection_objective = "icir",
  factor_specs = list(
    list(factor_family = "Risk_Defensive",
         proxy = "D43_Skewness",
         formula = "Expected idiosyncratic skewness (rolling 21d daily returns 3rd moment standardized)",
         lag_rule = "daily t-1, sig_date M01",
         winsorization = "Factor DB 3std (built-in)",
         neutralization = "sector demean per sig_date",
         economic_rationale = "Lottery preference penalty — high skew (positive tail) stocks earn lower future returns due to investor over-pay for upside lottery",
         weight_theta = 0.33333,
         references = c("Boyer-Mitton-Vorkink 2010 RFS 'Expected Idiosyncratic Skewness'",
                        "Bali-Engle-Murray 2016 Empirical Asset Pricing Ch.7")),
    list(factor_family = "Risk_Defensive",
         proxy = "D41_Vol_of_Vol",
         formula = "Realized vol-of-vol (rolling stddev of rolling vol, 21d/63d nested windows)",
         lag_rule = "daily t-1, sig_date M01",
         winsorization = "Factor DB 3std (built-in)",
         neutralization = "sector demean per sig_date",
         economic_rationale = "Vol-of-vol premium — unknown unknowns penalty, investors avoid second-moment uncertainty",
         weight_theta = 0.33333,
         references = c("Baltussen-VanBekkum-VanderGrient 2018 RFS 'Unknown Unknowns: Vol-of-Vol and the Cross-Section'")),
    list(factor_family = "Risk_Defensive",
         proxy = "D58_Vol_Asymmetry",
         formula = "Downside vol / Upside vol asymmetry (rolling 21d separated by negative vs positive returns)",
         lag_rule = "daily t-1, sig_date M01",
         winsorization = "Factor DB 3std (built-in)",
         neutralization = "sector demean per sig_date",
         economic_rationale = "Downside risk premium — investors demand premium for stocks with greater downside vs upside volatility",
         weight_theta = 0.33334,
         references = c("Ang-Chen-Xing 2006 RFS 'Downside Risk'",
                        "Bali-Demirtas-Levy 2009 JFQA 'Is There Intertemporal Relation between Downside Risk and Expected Returns?'"))
  ),
  alpha_vector = alpha_vector,
  confidence_vector = confidence_vector,
  signal_matrix_ref = sprintf("stage_artifacts://WT_D20260511_001/alpha_scores.parquet"),
  diagnostics = list(
    rank_ic = diag$rank_ic,
    icir = diag$icir,
    monotonicity = diag$monotonicity,
    subperiod_stability = diag$subperiod_stability,
    turnover_proxy = diag$turnover_proxy_annual,
    harvey_t_stat = diag$harvey_t_nw,
    harvey_t_specs_pass_count = diag$harvey_t_specs_pass_count,
    post_neutralization_ic = diag$post_neutralization_ic,
    post_neutralization_retention = diag$post_neutralization_retention,
    deflated_sharpe_ratio_pending = "Computed at Judge stage (M=8 spec like WT-P20260505_001)",
    alpha_inheritance_cor = 0,
    n_sig_dates = diag$n_sig_dates,
    period_start = diag$period_start,
    period_end = diag$period_end,
    orthogonality_S4_v2 = diag$orthogonality,
    crisis_alpha_ax001_v2 = diag$crisis_alpha_ax001_v2,
    per_factor = diag$per_factor_summary,
    subperiod_breakdown = diag$subperiod_breakdown,
    decile_returns = diag$decile_returns
  ),
  alpha_discovery_count = 1,
  ax001_v2_conditional_defense = list(
    ic_bad = diag$crisis_alpha_ax001_v2$ic_bad_regime,
    ic_normal = diag$crisis_alpha_ax001_v2$ic_normal_regime,
    ratio = diag$crisis_alpha_ax001_v2$ratio_bad_over_normal,
    interpretation = "ratio 1.215 (bad > normal) — defensive characteristic confirmed. Combined with cor_crisis -0.338 vs S4 v2 = crisis hedge mechanism. NOTE: ratio>1 is anomaly (통상 0.5~1.0 range), Codex Round 검토 필요."
  ),
  hard_constraints_audit = list(
    long_only = TRUE,
    max_names = 20,
    weight_bounds_0_0p20 = TRUE,
    universe = "KOSPI200 ∪ KOSDAQ150",
    liquidity_floor_KRW_20d_avg = 200000000,
    transaction_cost_bps = 15,
    pit_c1_to_c15_compliant = TRUE,
    cost_model_version = "v2.3_kr_retail_15bps"
  ),
  pit_compliance = val$pit_compliance,
  refinement_path = val$refinement_path,
  why_d05_excluded = val$why_d05_excluded,
  method_shopping_log = list(
    candidates_tried = 5,
    method_log = list(
      list(name = "v1_macro_residual_cross_section",
           rank_ic = 0.0038, icir = 0.0512, harvey_t = 0.7315,
           selected = FALSE, reason = "univariate β too weak, IC near 0"),
      list(name = "v2_4axis_full_sample_align",
           rank_ic = 0.1910, icir = 1.6243, harvey_t = 18.82,
           selected = FALSE, reason = "PIT C1 violation suspected (full-sample sign multiply)"),
      list(name = "v3_4axis_raw_pit_strict",
           rank_ic = -0.1264, icir = -0.8429, harvey_t = -10.52,
           selected = FALSE, reason = "Raw direction reverse — need direction-align via expanding IC"),
      list(name = "v4_4axis_expanding_align_36m_burn",
           rank_ic = 0.2043, icir = 1.7191, harvey_t = 18.06,
           selected = FALSE, reason = "D05_MaxRet IC 0.31 비현실 inflate suspect (small-cap bias)"),
      list(name = "v5_4axis_sector_neutral_full",
           rank_ic = 0.1746, icir = 2.0042, harvey_t = 21.32,
           selected = FALSE, reason = "D05 IC 0.267 still inflated after sector-neutral"),
      list(name = "FINAL_3axis_D05_excluded_sector_neutral",
           rank_ic = 0.0741, icir = 0.8684, harvey_t = 8.6205,
           selected = TRUE,
           reason = "Conservative D05 exclusion (Q07 baseline IC 0.030 vs D05 0.27 = 9x inflate suspect). All Harvey t > 3.0 (composite + 3 sub-factors). Sector-neutral robust. Orthogonal to S4 v2 (cor -0.135, crisis -0.338).")
    ),
    parallel_exec = TRUE,
    n_workers = 6L,
    rcpp_used = FALSE
  ),
  challenge_flags = c(
    "MEDIUM: turnover proxy 556% annual exceeds 300% hurdle target — Q-Lead/Optimizer 단계에서 turnover penalty / smoothing 필요. monthly Jaccard 0.46 = top20 절반 매월 교체.",
    "MEDIUM: Top20 EW SR 1.749 / ret_ann 50.65% — vol/skew premium 학술 통상 SR 0.5~1.0 대비 약간 강함. KR specific 또는 small/mid-cap residual exposure 가능성. Codex Round 검토 필요.",
    "LOW: AX-001 v2 ratio 1.215 (bad > normal) — defensive bias 명확하지만 약간 anomaly (통상 0.5~1.0).",
    "LOW: 3-axis 모두 D-family (volatility) → factor 다양성 부족. AX-005 v1.2 single-sleeve top20 long-only fail 위험 — but multi-axis sector-neutral 조합 + S4 baseline 결합 형식 (standalone 직접 admit 아님)이라 mitigate.",
    "INFO: D05_MaxRet excluded (single IC 0.27 inflated, 9x Q07 baseline). Codex Round critique 후 D05 재포함 검토.",
    "INFO: Lockbox cutoff 2023-12-22 retain (alpha-research stage PIT 정합, .claude/rules/lockbox-scope.md). 운용 forge/monitoring 단계 lockbox 해제 mandate (도훈 2026-05-09)."
  ),
  alternative_hypotheses = list(
    list(name = "Macro Residual Cross-section (Path 1)", reason_rejected = "v1 IC 0.004 univariate β regression too weak. residual+cross-section 결합 spec 후속 cycle 검토."),
    list(name = "Defensive Sector ETF (health/staples)", reason_rejected = "Single ETF로 cross-section breadth 부족 (max_names 1~2). WT-S20260504_008 7 candidate 비교 결과 KR_10y 우월."),
    list(name = "Foreign Investor Flow Residualized (INV13)", reason_rejected = "Backlog for next cycle. INV13_Foreign_Resid_Individual 3 timeframes already in Factor DB, S4 baseline factor specs 외 cross-section signal 후속 분석.")
  ),
  graduation_criteria_check = list(
    min_rank_ic = list(target = 0.04, actual = round(diag$rank_ic, 4), pass = diag$rank_ic >= 0.04),
    min_icir = list(target = 0.20, actual = round(diag$icir, 3), pass = diag$icir >= 0.20),
    min_subperiod_stability = list(target = 0.50, actual = diag$subperiod_stability, pass = diag$subperiod_stability >= 0.50),
    min_harvey_t = list(target = 3.0, actual = round(diag$harvey_t_nw, 3), pass = abs(diag$harvey_t_nw) >= 3.0)
  ),
  references = list(
    academic = c(
      "Boyer-Mitton-Vorkink 2010 RFS 'Expected Idiosyncratic Skewness'",
      "Baltussen-VanBekkum-VanderGrient 2018 RFS 'Unknown Unknowns: Vol-of-Vol'",
      "Ang-Chen-Xing 2006 RFS 'Downside Risk'",
      "Bali-Cakici-Whitelaw 2011 JFE 'Maxing Out: Stocks as Lotteries'",
      "Bali-Demirtas-Levy 2009 JFQA 'Downside Risk and Expected Returns'"
    ),
    L_codes = c(
      "L-285 — 5 path 4th orthogonal source saturation reproducible (cycle 1~3 + Session 77 + this cycle as cycle 4)",
      "L-454 — 한국 내부 데이터 > 글로벌 FRED",
      "L-280/281 — cross-section vs time-series 정의상 직교",
      "L-484 — 수익률 블렌드 앙상블 ❌ (본 가설은 SCORE 블렌드 ✓)",
      "L-119 — 정적 팩터 블렌드 alpha 희석 (본 가설은 sector-neutral, dynamic regime overlay TBD optimizer 단계)"
    ),
    qepm_sections = c(
      "QEPM §3 Memory (조건부 기억 적립)",
      "QEPM §8 Alpha Lab Gate (ICIR ≥ 0.20 PASS)",
      "QEPM §9 Factor Taxonomy (Risk_Defensive family)",
      "QEPM §10 Statistical Defense (Harvey t > 3.0 PASS)"
    )
  )
)

out_path <- file.path(WT_DIR, "alpha_package_draft.json")
write_json(alpha_package_draft, out_path, pretty = TRUE, auto_unbox = TRUE, na = "string")
cat("\nalpha_package_draft.json saved:", out_path, "\n")
cat("File size:", round(file.info(out_path)$size / 1024, 1), "KB\n")
