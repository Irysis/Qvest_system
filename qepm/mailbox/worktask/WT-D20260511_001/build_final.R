# Build final alpha_package.json (post-Codex Round)
# Incorporates C5 (challenge_note), C6 (academic page), DSR estimate addition

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(jsonlite); library(future); library(future.apply)
})

PROJ_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_ID <- "WT-D20260511_001"
STAGE_DIR <- file.path(PROJ_ROOT, "stage_artifacts", "WT_D20260511_001")
WT_DIR <- file.path(PROJ_ROOT, "qepm/mailbox/worktask", WT_ID)

# Load alpha_scores + validation
alpha_scores <- as.data.table(read_parquet(file.path(STAGE_DIR, "alpha_scores.parquet")))
val <- fromJSON(file.path(STAGE_DIR, "alpha_validation.json"))
diag <- val$diagnostics

# Compute DSR estimate (Bailey-Lopez de Prado, bootstrap B=1000, M=5 candidates_tried)
# Use cross-sectional IC series for DSR computation
# DSR = (SR - SR_threshold) / sigma(SR), with multi-testing correction
# Simple BLP formula: SR_DSR = SR * sqrt((T-1) / (1 - skew_SR*SR + ((kurt_SR-1)/4)*SR^2))
# Then deflated using max_SR formula

# Use composite IC time series for DSR proxy
panel_eval_path <- file.path(STAGE_DIR, "alpha_scores.parquet")
# Use ic_eval from validation re-compute (sample equivalent)
# Read raw alpha_scores → compute Top20 EW portfolio + DSR
s4_path <- file.path(PROJ_ROOT, "qepm/mailbox/worktask/WT-P20260509_002/output/walk_forward_returns_timeseries.csv")
s4_dt <- fread(s4_path)
s4_b <- s4_dt[method == "BENCH_S4_static_dohoon", .(date = as.Date(date), ret_S4 = ret_net)]

# Top20 EW portfolio returns from alpha_scores
# Need forward returns — load rawdata
rd <- as.data.table(read_parquet(file.path(PROJ_ROOT, ".cache/rawdata.parquet")))
setnames(rd, "Date", "date")
rd_simple <- rd[!is.na(Ret), .(date, Ticker, Ret)]
setkey(rd_simple, Ticker, date)
sig_dates <- sort(unique(alpha_scores$sig_date))
ret_list <- vector("list", length(sig_dates) - 1)
for (i in seq_along(sig_dates)[-length(sig_dates)]) {
  d_s <- sig_dates[i]; d_e <- sig_dates[i + 1]
  rb <- rd_simple[date > d_s & date <= d_e, .(ret_1M = prod(1 + Ret) - 1), by = Ticker]
  rb[, sig_date := d_s]
  ret_list[[i]] <- rb
}
ret_fwd <- rbindlist(ret_list)
alpha_with_ret <- merge(alpha_scores, ret_fwd, by = c("Ticker", "sig_date"))

portfolio_top20 <- alpha_with_ret[, {
  ranked <- order(alpha, decreasing = TRUE)
  if (.N < 20) return(.(top20_ret = NA_real_))
  .(top20_ret = mean(ret_1M[ranked[1:20]], na.rm = TRUE))
}, by = sig_date]
portfolio_top20 <- portfolio_top20[!is.na(top20_ret)]
ret_vec <- portfolio_top20$top20_ret
T_periods <- length(ret_vec)
SR_observed <- mean(ret_vec) * sqrt(12) / sd(ret_vec)
# Bailey-Lopez de Prado DSR:
# DSR = ((SR - E[max SR]) * sqrt(T-1)) / sqrt(1 - skew_r*SR + ((kurt_r-1)/4)*SR^2)
# Skew/kurt of returns (monthly)
sk <- if (sd(ret_vec) > 1e-6) mean(((ret_vec - mean(ret_vec))/sd(ret_vec))^3) else 0
kt <- if (sd(ret_vec) > 1e-6) mean(((ret_vec - mean(ret_vec))/sd(ret_vec))^4) else 3
# SR monthly (not annualized for BLP formula)
sr_m <- mean(ret_vec) / sd(ret_vec)
N_trials <- 5  # candidates_tried in method_shopping_log
E_max_sr <- (1 - 0.5772) * qnorm(1 - 1/N_trials) + 0.5772 * qnorm(1 - 1/(N_trials * exp(1)))  # E[max SR] approx
# Deflated SR (monthly basis)
denom_var <- 1 - sk * sr_m + ((kt - 1)/4) * sr_m^2
if (denom_var > 0) {
  z_dsr <- (sr_m - E_max_sr * sd(ret_vec)) * sqrt(T_periods - 1) / sqrt(denom_var)
  # Probability that DSR > 0
  dsr_pvalue <- 1 - pnorm(z_dsr)
  dsr_estimate <- pnorm(z_dsr)  # P(true SR > 0)
} else {
  z_dsr <- NA; dsr_pvalue <- NA; dsr_estimate <- NA
}

cat("DSR estimate (Bailey-Lopez de Prado, M=5, T=", T_periods, "):\n")
cat(sprintf("  SR observed (annualized): %.4f\n", SR_observed))
cat(sprintf("  SR monthly: %.4f, skew: %.3f, kurt: %.3f\n", sr_m, sk, kt))
cat(sprintf("  E[max SR | N=5] estimate: %.4f\n", E_max_sr))
cat(sprintf("  z_DSR: %.4f, p-value: %.4f, DSR (P[true SR>0]): %.4f\n", z_dsr, dsr_pvalue, dsr_estimate))

# Final alpha_package
latest_sig <- max(alpha_scores$sig_date)
alpha_latest <- alpha_scores[sig_date == latest_sig]
alpha_vector <- as.list(setNames(round(alpha_latest$alpha, 6), alpha_latest$Ticker))
confidence_vector <- as.list(setNames(round(alpha_latest$confidence, 4), alpha_latest$Ticker))

alpha_package <- list(
  task_id = WT_ID,
  wt_type = "discovery",
  package_kind = "alpha_package",
  as_of_date = as.character(latest_sig),
  forecast_horizon = "1M",
  agent = list(agent_id = "alpha-research-WT-D20260511_001",
               agent_type = "alpha-research",
               agent_version = "v1.2",
               model = "Opus_4_7_1M"),
  codex_round = list(
    round_1_response_file = "codex_critic_response_alpha.json",
    stance = "REJECT",
    veto_flag = FALSE,
    n_critical_concerns = 6,
    n_high_severity = 5,
    challenge_note_file = "challenge_note.md",
    disposition_summary = list(
      C1_PIT_C13_dir_multiplier = "ACCEPT_TIMELINE — Z_Score_Aligned only 재계산 next cycle (factor_ic_monthly.parquet build 후)",
      C2_RF_A6_multi_testing = "PARTIAL — DSR 추정 본 stage 추가 (아래 dsr_estimate) + 5-spec regression risk-research stage",
      C3_AX_007_single_sleeve = "REBUTTAL — Exception 1 multi-sleeve integration (S4 v2 4-sleeve + new sleeve = 5-sleeve, standalone admit X)",
      C4_turnover_hurdle = "ACCEPT — Optimizer turnover smoothing ≤ 300% 정합화 mandate",
      C5_charter_8_no_silent = "ACCEPT — challenge_note.md 본 문서 + weights/cov risk/optimizer agent",
      C6_academic_page_KR_specific = "PARTIAL — page numbers 추가 (아래 references) + KR specific architect 후속",
      PIT_C13_FAIL = "ACCEPT_TIMELINE (C1과 동일)",
      PIT_C14_FAIL = "ACCEPT_TIMELINE — compute_rolling_ic_all() 활용 next cycle"
    ),
    q_lead_escalation_trigger = "HIT (HIGH severity 5건 ≥ 5)",
    rationalization_detection_acknowledged = TRUE
  ),
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
         economic_rationale = "Lottery preference penalty — high skew stocks earn lower future returns due to investor over-pay for upside lottery",
         weight_theta = 0.33333,
         references = c("Boyer-Mitton-Vorkink 2010 RFS 23(1): 169-202 'Expected Idiosyncratic Skewness'",
                        "Bali-Engle-Murray 2016 Empirical Asset Pricing Ch.7")),
    list(factor_family = "Risk_Defensive",
         proxy = "D41_Vol_of_Vol",
         formula = "Realized vol-of-vol (rolling stddev of rolling vol, 21d/63d nested windows)",
         lag_rule = "daily t-1, sig_date M01",
         winsorization = "Factor DB 3std (built-in)",
         neutralization = "sector demean per sig_date",
         economic_rationale = "Vol-of-vol premium — unknown unknowns penalty, investors avoid second-moment uncertainty",
         weight_theta = 0.33333,
         references = c("Baltussen-VanBekkum-VanderGrient 2018 RFS 31(7): 2664-2706 'Unknown Unknowns: Vol-of-Vol and the Cross-Section'")),
    list(factor_family = "Risk_Defensive",
         proxy = "D58_Vol_Asymmetry",
         formula = "Downside vol / Upside vol asymmetry (rolling 21d separated by negative vs positive returns)",
         lag_rule = "daily t-1, sig_date M01",
         winsorization = "Factor DB 3std (built-in)",
         neutralization = "sector demean per sig_date",
         economic_rationale = "Downside risk premium — investors demand premium for stocks with greater downside vs upside volatility",
         weight_theta = 0.33334,
         references = c("Ang-Chen-Xing 2006 RFS 19(4): 1191-1239 'Downside Risk'",
                        "Bali-Demirtas-Levy 2009 JFQA 44(4): 883-909 'Is There Intertemporal Relation between Downside Risk and Expected Returns?'"))
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
    deflated_sharpe_ratio = list(
      method = "Bailey-Lopez de Prado, T=155 monthly, M=5 candidates_tried, no bootstrap",
      sr_observed_annualized = SR_observed,
      sr_monthly = sr_m,
      skew_returns = sk,
      kurt_returns = kt,
      e_max_sr_estimate_N5 = E_max_sr,
      z_dsr = z_dsr,
      p_value = dsr_pvalue,
      dsr_probability_true_sr_positive = dsr_estimate,
      threshold_passed_0p5 = dsr_estimate >= 0.5,
      note = "Codex C2 PARTIAL response. Bootstrap version + 5-spec regression risk-research / judge stage 위임."
    ),
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
  ax007_exception_claim = list(
    exception_type = "Exception 1: multi-sleeve integration",
    rationale = "본 alpha는 standalone single-sleeve admit 후보 아님. S4 v2 baseline (4-sleeve: STR_1715 50 + TSMOM_8 25 + KR_10y 20 + Cash 5)에 추가할 4th orthogonal source. Risk-research agent가 sleeve role audit + covariance + style overlap 후 sleeve 구성 권고. Optimizer agent가 weights 결정. 최종 5-sleeve allocation. AX-007 4-exception 중 Exception 1 (multi-sleeve) 적용.",
    L_code_references = c("L-281 — Cross-Asset TSMOM 4-asset class diversification 입증",
                          "L-280 — direct orthogonal source 결합 Pareto improvement")
  ),
  ax001_v2_conditional_defense = list(
    ic_bad = diag$crisis_alpha_ax001_v2$ic_bad_regime,
    ic_normal = diag$crisis_alpha_ax001_v2$ic_normal_regime,
    ratio = diag$crisis_alpha_ax001_v2$ratio_bad_over_normal,
    interpretation = "ratio 1.215 (bad > normal) — defensive characteristic 강함. Combined with cor_crisis -0.338 vs S4 v2 = crisis hedge confirmed. NOTE: ratio>1 은 통상 0.5~1.0 범위를 넘는 anomaly로 risk-research에 명시 audit 의무."
  ),
  hard_constraints_audit = list(
    long_only = TRUE,
    max_names = 20,
    weight_bounds_0_0p20 = TRUE,
    universe = "KOSPI200 ∪ KOSDAQ150",
    liquidity_floor_KRW_20d_avg = 200000000,
    transaction_cost_bps = 15,
    pit_c1_to_c15_compliant_full = list(C1_PASS = TRUE, C2_PASS = TRUE, C9_PASS = TRUE,
                                         C13_FAIL_TIMELINE_ACCEPT = TRUE,
                                         C14_FAIL_TIMELINE_ACCEPT = TRUE,
                                         C15_PASS = TRUE),
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
           reason = "D05 IC 0.27 inflate vs KR Q07 baseline 0.030 9x → excluded. Harvey t-pass 4/4. Sector-neutral robust. Orthogonal S4 v2 (cor -0.135, crisis -0.338).")
    ),
    parallel_exec = TRUE,
    n_workers = 6L,
    rcpp_used = FALSE
  ),
  challenge_flags = c(
    "MEDIUM: Turnover proxy 556% annual one-way (round-trip ~1112%) > 600% hurdle — Optimizer turnover smoothing ≤ 300% 정합화 의무 (Codex C4 ACCEPT).",
    "MEDIUM: Top20 EW SR 1.749 / ret_ann 50.65% — vol/skew premium 학술 baseline 대비 강함. KR specific 또는 small/mid-cap residual exposure 가능. Risk-research style overlap audit 의무.",
    "LOW: AX-001 v2 ratio 1.215 (bad > normal) — defensive 명확하지만 통상 0.5~1.0 범위 초과 anomaly. Risk-research 명시 audit.",
    "LOW: 3-axis 모두 D-family — multi-sleeve integration claim으로 mitigate (Codex C3 REBUTTAL).",
    "INFO: D05_MaxRet excluded (IC 0.27 9x Q07 inflate). Codex critique 검토 후 D05 재포함 검토.",
    "INFO: Lockbox cutoff 2023-12-22 retain (.claude/rules/lockbox-scope.md). 운용 단계 해제.",
    "MEDIUM (Codex C1): PIT-C13 strict 해석 시 dir_* multiplier 위반 — Factor DB factor_ic_monthly.parquet build 후 재계산 의무.",
    "INFO (Codex C5): challenge_note.md 본 cycle 작성 (Charter §8 No Silent Override 충족)."
  ),
  alternative_hypotheses = list(
    list(name = "Macro Residual Cross-section (Path 1)", reason_rejected = "v1 IC 0.004 univariate β too weak. Residual + cross-section 결합 spec 후속 cycle 검토."),
    list(name = "Defensive Sector ETF (health/staples)", reason_rejected = "Single ETF cross-section breadth 부족. WT-S20260504_008 7 candidate audit에서 KR_10y 우월 입증."),
    list(name = "Foreign Investor Flow Residualized (INV13)", reason_rejected = "Backlog next cycle. INV13_Foreign_Resid_Individual 3 timeframes Factor DB 활용 후속 검토.")
  ),
  graduation_criteria_check = list(
    min_rank_ic = list(target = 0.04, actual = round(diag$rank_ic, 4), pass = diag$rank_ic >= 0.04),
    min_icir = list(target = 0.20, actual = round(diag$icir, 3), pass = diag$icir >= 0.20),
    min_subperiod_stability = list(target = 0.50, actual = diag$subperiod_stability, pass = diag$subperiod_stability >= 0.50),
    min_harvey_t = list(target = 3.0, actual = round(diag$harvey_t_nw, 3), pass = abs(diag$harvey_t_nw) >= 3.0),
    min_deflated_sharpe_ratio = list(target = 0.5, actual = round(dsr_estimate, 4),
                                       pass = !is.na(dsr_estimate) && dsr_estimate >= 0.5)
  ),
  references = list(
    academic = c(
      "Boyer-Mitton-Vorkink 2010 RFS 23(1): 169-202 'Expected Idiosyncratic Skewness'",
      "Baltussen-VanBekkum-VanderGrient 2018 RFS 31(7): 2664-2706 'Unknown Unknowns: Vol-of-Vol and the Cross-Section'",
      "Ang-Chen-Xing 2006 RFS 19(4): 1191-1239 'Downside Risk'",
      "Bali-Cakici-Whitelaw 2011 JFE 99(2): 427-446 'Maxing Out: Stocks as Lotteries and the Cross-Section of Expected Returns'",
      "Bali-Demirtas-Levy 2009 JFQA 44(4): 883-909 'Is There Intertemporal Relation between Downside Risk and Expected Returns?'"
    ),
    L_codes = c(
      "L-285 — 5 path 4th orthogonal source saturation reproducible (cycle 1~3 + Session 77 + this cycle as cycle 4)",
      "L-454 — 한국 내부 데이터 > 글로벌 FRED (정합 본 cycle은 KR equity universe)",
      "L-280/281 — cross-section vs time-series 정의상 직교 (vol/skew는 cross-section family)",
      "L-484 — 수익률 블렌드 앙상블 ❌ (본 가설은 SCORE 블렌드 ✓)",
      "L-119 — 정적 팩터 블렌드 alpha 희석 (본 가설은 sector-neutral + Optimizer dynamic overlay TBD)",
      "L-121 — Q07_Earnings_Stability 양쪽 위기 최강 (본 가설은 Q07과 직교 사실 입증)"
    ),
    qepm_sections = c(
      "QEPM §3 Memory (조건부 기억 적립)",
      "QEPM §8 Alpha Lab Gate (ICIR ≥ 0.20 PASS, 0.868 = 4.34x)",
      "QEPM §9 Factor Taxonomy (Risk_Defensive family)",
      "QEPM §10 Statistical Defense (Harvey t > 3.0 PASS, 8.62 = 2.87x)"
    )
  ),
  next_agent_mandate = list(
    risk_research_agent = c(
      "Σ = BΩB' + D + tail risk + stress 진단 산출",
      "Style overlap audit (D-family β vs STR_1715 Q07/C01/C04 β)",
      "AX-001 v2 ratio 1.215 anomaly 정량 진단 (Codex C3 mitigate)",
      "5-spec regression (CAPM, Carhart-3/4, FF5/6) — Codex C2 partial response",
      "Sleeve role audit — multi-sleeve integration AX-007 Exception 1 검증"
    ),
    optimizer_research_agent = c(
      "Turnover smoothing ≤ 300% 정합화 (Codex C4 ACCEPT)",
      "5-sleeve weight allocation (S4 v2 4-sleeve + new D-family sleeve)",
      "Long-only + max 20 names + weight bounds [0, 0.20] + Σw=1 enforce"
    ),
    architect_agent_advisory_request = c(
      "KR-specific Vol/Skew academic validation (Codex C6 partial)",
      "AX-007 Exception 1 multi-sleeve integration 학술 reference 확장"
    )
  )
)

# Save final alpha_package.json
out_path <- file.path(WT_DIR, "alpha_package.json")
write_json(alpha_package, out_path, pretty = TRUE, auto_unbox = TRUE, na = "string")
cat("\nalpha_package.json saved:", out_path, "\n")
cat("File size:", round(file.info(out_path)$size / 1024, 1), "KB\n")

# Lineage append
source(file.path(PROJ_ROOT, "02_Infrastructure/worktask/lineage_utils.R"))
tryCatch({
  record_package_lineage(
    task_id = WT_ID,
    package_type = "alpha_package",
    method_selected = "3-axis vol/skew composite (D43+D41+D58) sector-neutral PIT-strict 36m burn-in, post-Codex Round REJECT challenge_note disposition",
    input_file_paths = c(
      ".cache/rawdata.parquet",
      ".cache/factor_db/factor_db_YYYYMM.parquet (load_month_factors)",
      "qepm/mailbox/worktask/WT-P20260509_002/output/walk_forward_returns_timeseries.csv",
      "qepm/mailbox/worktask/WT-D20260511_001/alpha_package_draft.json",
      "qepm/mailbox/worktask/WT-D20260511_001/codex_critic_response_alpha.json",
      "qepm/mailbox/worktask/WT-D20260511_001/challenge_note.md"
    )
  )
  cat("Lineage recorded for alpha_package\n")
}, error = function(e) cat("Lineage error:", conditionMessage(e), "\n"))
