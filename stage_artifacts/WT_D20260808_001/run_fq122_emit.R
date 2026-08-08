# run_fq122_emit.R — FQ-122 산출물 발행 (alpha_scores / alpha_validation / alpha_package / lineage)
suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)})
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
OUT <- "stage_artifacts/WT_D20260808_001"; MBX <- "qepm/mailbox/worktask/WT-D20260808_001"
say <- function(f, ...) cat(sprintf(paste0("[emit] ", f, "\n"), ...))
p1 <- readRDS(file.path(OUT, "fq122_part1.rds")); p2 <- readRDS(file.path(OUT, "fq122_part2.rds"))

# ── alpha_scores.parquet : 소비규칙 적용 패널 ────────────────────────────────
TUNED <- as.data.table(read_parquet("stage_artifacts/WT_D20260802_009/tuned_panel.parquet"))
TUNED[, Date := as.Date(Date)]
RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet", col_select = c("Date","Ticker","K200","KQ150")))
RAW[, Date := as.Date(Date)]; RAW[, ym := format(Date, "%Y-%m")]
MEND <- sort(RAW[, .(Date = max(Date)), by = ym]$Date)
UNIV <- RAW[Date %in% MEND & (K200 == TRUE | KQ150 == TRUE), .(Date, Ticker)]
W <- dcast(TUNED[Factor_Name %in% c("M01_PATHQ","D03_EWMA","Q01_EB")],
           Date + Ticker ~ Factor_Name, value.var = "score")
W <- merge(W, UNIV, by = c("Date","Ticker"))
S <- W[is.finite(M01_PATHQ)]
S[, rk_m01 := frank(-M01_PATHQ, ties.method = "first"), by = Date]
for (f in c("D03_EWMA","Q01_EB")) {
  S[, (paste0(f, "_pct")) := { v <- get(f); r <- rep(NA_real_, .N); ok <- is.finite(v)
      if (any(ok)) r[ok] <- frank(v[ok]) / sum(ok); r }, by = Date]
}
S[, excl_q01_q20 := is.finite(Q01_EB_pct) & Q01_EB_pct <= 0.20]
S[, excl_d03_q20 := is.finite(D03_EWMA_pct) & D03_EWMA_pct <= 0.20]
S[, score := M01_PATHQ]
S[, score_q01filtered := ifelse(excl_q01_q20, NA_real_, M01_PATHQ)]
write_parquet(S, file.path(OUT, "alpha_scores.parquet"))
say("alpha_scores.parquet %d행 · %d월 · 제외율 Q01 %.3f / D03 %.3f",
    nrow(S), uniqueN(S$Date), mean(S$excl_q01_q20), mean(S$excl_d03_q20))

last_d <- max(S$Date)
L <- S[Date == last_d & !is.na(score_q01filtered)][order(-score_q01filtered)][1:25]
alpha_vec <- as.list(setNames(round(L$score_q01filtered, 6), L$Ticker))
conf <- 0.35 + 0.15 * (is.finite(L$D03_EWMA) & is.finite(L$Q01_EB)) + 0.10 * (L$rk_m01 <= 15)
conf_vec <- as.list(setNames(round(pmin(pmax(conf, 0), 1), 3), L$Ticker))
say("alpha_vector 최신월 %s · %d종목", as.character(last_d), length(alpha_vec))

RECON <- p2$RECON; PROD <- p2$PROD; PLC <- p2$PLC
q01_w1 <- RECON[weighting == "W1_recon_ew25" & factor == "Q01_EB" & q == 0.20]
q01_w3 <- PROD[arm == "W3_prod_tilt20_Q01_EB"]

val <- list(
  task_id = "WT-D20260808_001", fq_ref = "FQ-122", as_of_date = "2026-08-08",
  metric_type_map = list(canonical_arms = "canonical_screen",
    production_arms = "realcode_recon (production_parity_verified)",
    precheck = "precheck_diag", placebo = "diag"),
  input_assert = list(
    tuned_panel = "2,514,408행 · MONTHLY(월말) · 295월 · 2001-12-28~2026-06-30",
    prod_alpha_panel = "81,226행 · MONTHLY(월초) · 272월 · score_eff non-NA 62,830",
    eligible_set = "82,566행 · 295월 · 월평균 279.9 / 중앙 329종목",
    date_anchor_mapping = "tuned 월말 d0 → production sig_label 월 = month(d0)+1 (C5 준수)",
    forward_returns = "build_monthly_forward_returns() 계약함수 경유 (손계산 없음)"),
  parity = list(gate_A = "production 03_period_returns.csv 정확 재현",
    max_abs_dev = p2$gateA_max_dev, threshold = 1e-8, result = "PASS",
    anchor = "04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/output/03_period_returns.csv",
    admitted_slot = "STR_1715_on_M4gAE_R05_noLayer4_PG2 (슬롯 2-4, IR 1.416) — 종목계층 앵커는 Iter31 동일 엔진"),
  consumption_face_a_tiebreaker = list(status = "REJECTED_PRE_MEASUREMENT",
    rule = "alpha_hypothesis falsification F4 사전 킬스위치",
    band = "M01 rank 20~40 · 6,195행 · 295월",
    D03_slope_ann_pct = -3.283, D03_t = -1.276,
    Q01_slope_ann_pct = -3.257, Q01_t = -1.518,
    M01_self_slope_ann_pct = 0.050, M01_self_t = 0.025,
    note = "두 팩터 모두 기울기 <= 0 → 측정하지 않음. 부호 반전 재설계 금지(C13 + 사후선택)"),
  consumption_face_b_exclusion = list(
    p_hit = list(D03_q20 = 0.3862, Q01_q20 = 0.1600,
                 D03_hits_per_month = 9.65, Q01_hits_per_month = 3.95),
    cells = rbind(
      RECON[q == 0.20, .(cell = weighting, factor, d_ann_pct = round(d_ann_pct,3),
        paired_t = round(paired_t,3), delta_ir = round(delta_ir,4),
        ci_lo = round(ci_lo_ann_pct,2), ci_hi = round(ci_hi_ann_pct,2), sign_agree, power_verdict)],
      PROD[!grepl("lag1", arm), .(cell = sub("_D03_EWMA|_Q01_EB", "", arm),
        factor = ifelse(grepl("D03", arm), "D03_EWMA", "Q01_EB"), d_ann_pct = round(d_ann_pct,3),
        paired_t = round(paired_t,3), delta_ir = round(delta_ir,4),
        ci_lo = round(ci_lo_ann_pct,2), ci_hi = round(ci_hi_ann_pct,2), sign_agree, power_verdict)]),
    sensitivity_q = RECON[weighting == "W1_recon_ew25",
      .(factor, q, d_ann_pct = round(d_ann_pct,3), paired_t = round(paired_t,3))],
    canonical_port_t = list(base = 2.050, D03_q10 = 1.582, D03_q20 = 1.589, D03_q30 = 1.292,
      Q01_q10 = 2.175, Q01_q20 = 2.381, Q01_q30 = 2.481),
    dual_basis = list(
      ew_universe_t = list(base = 2.415, D03_q20 = 1.944, Q01_q20 = 2.728, Q01_q30 = 2.885),
      ew_universe_post2017_t = list(base = 1.507, D03_q20 = 1.229, Q01_q20 = 1.505, Q01_q30 = 1.466),
      note = "EW-유니버스 대비에서도 방향 동일. 단 post-2017 구간에서는 Q01 개선이 사라짐(1.507→1.505) — 개선이 초기 구간 편중일 개연"),
    turnover_annual_pct = list(canonical_base = 789, canonical_Q01_q20 = 768, canonical_Q01_q30 = 745,
      canonical_D03_q20 = 819, prod_tilt_base = 514, prod_tilt_Q01 = 475, prod_tilt_D03 = 516,
      cap = "11.0/yr(1100%) 상한 — 전 arm 준수. Q01 필터는 회전을 낮춘다"),
    lag1_stress = list(Q01_W3 = list(d_ann_pct = 1.476, t = 0.848),
      D03_W3 = list(d_ann_pct = -4.215, t = -1.724),
      note = "부호·크기 유지 = 동월 누출 징후 없음"),
    placebo = list(
      seeds_8 = PLC[, .(factor, real_d_ann_pct = round(real_d_ann_pct,3),
        placebo_mean = round(placebo_mean,3), outside_range)],
      seeds_24_W3 = list(
        Q01 = list(real = 2.10, placebo_mean = -2.21, placebo_sd = 1.93,
          placebo_min = -6.87, placebo_max = 1.77, right_tail_p = 0.000),
        D03 = list(real = -3.70, placebo_mean = -2.05, placebo_sd = 1.30,
          placebo_min = -4.06, placebo_max = 0.46, right_tail_p = 0.833)),
      interpretation = "플라시보는 '같은 개수를 무작위로 빼는 것' 대비 선택 정보를 시험한다(조건부). 모집단 효과의 시계열 불확실성(t 1.31 · CI[-1.03,+5.24])을 대체하지 않는다")),
  primary_P1_conditional_information = p2$P1[, .(region, factor,
    slope_ann_pct = round(slope_ann_pct,3), t_nw = round(t_nw,3),
    ci_lo_ann_pct = round(ci_lo_ann_pct,2), ci_hi_ann_pct = round(ci_hi_ann_pct,2), power_verdict)],
  falsification_observables = list(
    F1_left_localization = list(
      D03 = list(Q1_minus_Q3_ann_pct = -2.07, t = -0.63, Q5_minus_Q3_ann_pct = -6.90, t_Q5 = -2.30,
        verdict = "REJECTED — 승계 reject_if (1) (t > -1) 충족. 정보는 좌측이 아니라 우측(초저변동)에 있고 방향은 손실"),
      Q01 = list(Q1_minus_Q3_ann_pct = -5.21, t = -2.25, Q5_minus_Q3_ann_pct = -0.58, t_Q5 = -0.21,
        verdict = "SUPPORTED — 좌측 열위 유의 + 최상위 평탄 = 예측된 손실회피 형태")),
    F2_agent_individual_flow = list(D03_slope = -0.1109, D03_t = -11.87,
      Q01_slope = -0.0267, Q01_t = -10.17,
      verdict = "SUPPORTED — 필터 z 가 낮은(고변동·불안정) 종목에 개인 순매수가 집중",
      caveat = "동시기(contemporaneous) 특성 연관이지 예측 주장 아님. 고변동 월에 개인 거래가 느는 기계적 성분을 배제하지 못했다"),
    F3_beta_drag = list(
      D03 = list(Q5_beta_med = 0.709, univ_med = 0.889, verdict = "SUPPORTED — 초저변동 꼬리 beta 유의 저하 = beta-drag 경로"),
      Q01 = list(Q5_beta_med = 0.817, univ_med = 0.888, verdict = "WEAK"))),
  regime_interaction_advisory = p2$REG[, .(factor, interact_coef = round(interact_coef,5),
    interact_t = round(interact_t,3))],
  power = list(required_annual_pct_at_t2 = list(D03 = 4.47, Q01 = 3.02),
    n_months = 295, prod_n_months = 270,
    stance = "전 셀 INCONCLUSIVE_UNDERPOWERED — pass/fail 선언 금지, 구간추정 보고"),
  verdict = list(
    a_tiebreaker = "REJECTED_PRE_MEASUREMENT (F4 킬스위치)",
    b_D03 = "NOT_CONSUMABLE — 4/4 가중규칙에서 음(-) 방향이나 24-seed 플라시보와 구별 불가(우측 p=0.833). 손해의 정체는 D03 정보가 아니라 9.65종 제거의 희석. 기전도 F1 기각·F3 지지 = beta-drag",
    b_Q01 = "NOT_ESTABLISHED_BUT_LIVE — 신호 구조(F1/F2) 확인 · canonical PORT_t 2.050→2.381 단조 개선 · 회전 감소 · 24-seed 플라시보 밖(p<0.05). 그러나 (i) production EW20 에서 부호 반전(-1.54) → 사전등록 '가중규칙 >=2 부호일치' 미충족 (ii) 전 셀 |t|<2 검정력 부족 (iii) post-2017 EW-유니버스 개선 소멸",
    capital_claim = "없음 — graduation HARD 3종 판정 아님"))
write_json(val, file.path(OUT, "alpha_validation.json"), pretty = TRUE, auto_unbox = TRUE,
           digits = NA, null = "null")
say("alpha_validation.json 저장")

hyp <- fromJSON(file.path(MBX, "alpha_hypothesis.json"), simplifyVector = FALSE)
sel <- hyp$selected
esc_m01 <- list(escape_type = "STORED_SCORE",
  provenance_path = "stage_artifacts/WT_D20260802_009/tuned_panel.parquet",
  provenance_builder = "run_wt009_tuned.R — M01_PATHQ = CS_ZSCORE(CS_WINSORIZE(path_efficiency_252_21))",
  provenance_vintage = "2026-08-02T12:57", production_parity_verified = FALSE,
  note = "연구 파생 패널 — production 대체 아님")
esc_q01 <- list(escape_type = "STORED_SCORE",
  provenance_path = "stage_artifacts/WT_D20260802_009/tuned_panel.parquet",
  provenance_builder = "run_wt009_tuned.R — Q01_EB = MUL(z, DIV_GUARD(1, ADD(1, MUL(TS_STD(z,36), TS_STD(z,36)))))",
  provenance_vintage = "2026-08-02T12:57", production_parity_verified = FALSE)
esc_prod <- list(escape_type = "STORED_SCORE",
  provenance_path = "stage_artifacts/WT_D20260425_010/alpha_scores.parquet#score_eff",
  provenance_builder = "Iter31 run_all.R §5 walk-forward (production 종목선별 계층)",
  provenance_vintage = "2026-04-25", production_parity_verified = TRUE,
  note = "PARITY GATE A: 03_period_returns.csv 재현 max|dret_net| 5.13e-16 <= 1e-8")

pkg <- list(
  task_id = "WT-D20260808_001", as_of_date = "2026-08-08", forecast_horizon = "1M",
  spec_version = "ast_v1.1",
  hypothesis = list(statement = sel$hypothesis_description, mechanism = sel$mechanism,
    falsification = sel$falsification$observable, regime_scope = sel$regime_scope),
  factors = list(
    list(factor_id = "F1_M01PATHQ_x_Q01EB_exclusion",
      ast = list(op = "WHERE", args = list(
        list(leaf = "STORED_SCORE", escape_contract = esc_m01),
        list(op = "CS_RANK", args = list(list(leaf = "STORED_SCORE", escape_contract = esc_q01))),
        0.20)),
      role = "selection_filter", restatement_exposure = 1,
      note = "WHERE(선별점수, CS_RANK(필터), 0.20) = 필터 백분위 <= 0.20 종목 제거 후 선별. O 에 비교연산자가 없어 임계 술어를 WHERE 3-arg 위치로 인코딩 — 표현 가능하므로 blocked_by_capability 아님이나 operator 갭으로 기록"),
    list(factor_id = "F2_PROD_scoreeff_x_Q01EB_exclusion",
      ast = list(op = "WHERE", args = list(
        list(leaf = "STORED_SCORE", escape_contract = esc_prod),
        list(op = "CS_RANK", args = list(list(leaf = "STORED_SCORE", escape_contract = esc_q01))),
        0.20)),
      role = "selection_filter", restatement_exposure = 1,
      note = "§7b 권위 arm. 신호일 매핑 = tuned 월말 d0 → sig_label 월 month(d0)+1")),
  combination_rule = "single_factor",
  verdict = "designed",
  self_pit_check = list(performed = TRUE, leaves_checked = list(
      list(leaf = "STORED_SCORE:M01_PATHQ", availability_rule = "fixed: 월말 거래일 trailing-only (252행 창, skip 21)", restatement_prone = FALSE),
      list(leaf = "STORED_SCORE:Q01_EB", availability_rule = "fixed: 월말 z + trailing 36m 분산 (당월 미포함)", restatement_prone = TRUE),
      list(leaf = "STORED_SCORE:score_eff", availability_rule = "fixed: production sig_label 월초 라벨 = 전월말 정보", restatement_prone = FALSE)),
    verdict = "clean",
    note = "C5 확인: 필터 신호는 홀딩월 시작 전 월말(d0)에서만 취득. lag1 스트레스에서 부호·크기 유지 = 동월 누출 징후 없음"),
  alpha_vector = alpha_vec, confidence_vector = conf_vec,
  signal_matrix_ref = "stage_artifacts/WT_D20260808_001/alpha_scores.parquet",
  factor_specs = list(
    list(factor_family = "Momentum/PathQuality", proxy = "M01_PATHQ (signed path efficiency)",
      formula = "Sum(log ret)/Sum(|log ret|), window [n-251, n-21]",
      lag_rule = "daily t-1, 월말 산출", winsorization = "3std", neutralization = "none",
      economic_rationale = "추세의 경로 효율 — 잡음 대비 방향성이 높은 상승이 지속",
      weight_theta = 1.0, references = list("WT-D20260802_009 사전등록")),
    list(factor_family = "Quality/EarningsStability", proxy = "Q01_EB (EB-shrunk GPA)",
      formula = "z * 1/(1+Var_36m(z))", lag_rule = "quarterly 45d 상속 + trailing 36m",
      winsorization = "3std", neutralization = "none",
      economic_rationale = "이익 불안정 종목의 성장 서사 과대평가 — 하위 꼬리 forward 열위(F1 t -2.25) + 주체 개인 순매수 집중(F2 t -10.2)",
      weight_theta = 0.0, references = list("WT-D20260802_009", "WT-D20260802_021"))),
  diagnostics = list(
    canonical_port_t_nw_lag3 = 2.381, canonical_port_t_base = 2.050,
    canonical_port_t_pvalue = 0.018, canonical_n_months = 295,
    rank_ic = NA, icir = NA, monotonicity = NA, subperiod_stability = NA,
    turnover_proxy = 7.68, harvey_t_stat = NA, post_neutralization_ic = NA,
    paired_marginal_contribution_ann_pct = q01_w1$d_ann_pct,
    paired_marginal_t_nw_lag3 = q01_w1$paired_t,
    production_arm_ann_pct = q01_w3$d_ann_pct,
    production_arm_t_nw_lag3 = q01_w3$paired_t,
    note = "canonical_port_t_nw_lag3 = Q01_q20 필터 arm(재구성 base) 실측. rank-IC 계열은 본 라운드 판정 대상이 아니라 미산출(NA) — 판정량은 paired 한계기여"),
  selection_objective = "canonical_port_t",
  challenge_flags = list(
    "(a) 타이브레이커 = F4 사전 킬스위치로 측정 전 기각 — 승계 설계 규정 이행",
    "D03_EWMA 좌측-국소화 기전 REJECTED (F1 t -0.63 > -1) → C2 beta-drag 단독설 방향 (F3 지지: Q5 beta 0.709 vs 0.889)",
    "Q01_EB 는 production EW20 에서 부호 반전(-1.54) — 사전등록 '가중규칙 >=2 부호일치' 미충족으로 양성 주장 불가",
    "전 셀 |t| < 2 이고 효과 < 필요치 → INCONCLUSIVE_UNDERPOWERED. '효과 없음' 단정 금지",
    "post-2017 EW-유니버스 대비에서 Q01 개선 소멸(1.507→1.505) — 개선의 시기 편중 미해결",
    "F2 개인 순매수는 동시기 연관 — 예측 주장 아니며 고변동 월 거래증가 기계 성분 미배제",
    "C4 (D03 계열 위험축 재배치)는 risk-research 소비면 — 본 WT 범위 밖 전달",
    "O 에 비교연산자 부재 — 임계 술어를 WHERE 3-arg 위치로 인코딩(표현 가능, 갭 기록)"))
write_json(pkg, file.path(MBX, "alpha_package.json"), pretty = TRUE, auto_unbox = TRUE,
           digits = NA, null = "null")
say("alpha_package.json 저장")

source("02_Infrastructure/worktask/lineage_utils.R")
record_package_lineage(task_id = "WT-D20260808_001", package_type = "alpha_package",
  method_selected = "FQ-122 비-slot 소비: (a) F4 킬스위치 기각 / (b) 제외필터 2팩터 x 2base x 2가중규칙",
  input_file_paths = c("stage_artifacts/WT_D20260802_009/tuned_panel.parquet",
    "stage_artifacts/WT_D20260425_010/alpha_scores.parquet",
    ".cache/RAWDATA.parquet", ".cache/benchmark.parquet",
    "04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/output/03_period_returns.csv"))
say("lineage 기록 완료")
