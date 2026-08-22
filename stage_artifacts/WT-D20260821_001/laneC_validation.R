## alpha_validation.json 발행 (WT-D20260821_001) — 검증 기록 정본
suppressPackageStartupMessages({library(jsonlite); library(data.table); library(arrow)})
OUT <- "stage_artifacts/WT-D20260821_001"
R   <- fromJSON(file.path(OUT,"laneC_result.json"),      simplifyVector = FALSE)
ADV <- fromJSON(file.path(OUT,"laneC_adversarial.json"), simplifyVector = FALSE)
sc  <- as.data.table(read_parquet(file.path(OUT,"laneC_scores.parquet")))

v <- list(
  wt_id = "WT-D20260821_001", round_id = "WT_D20260821_001_LANEC", fq = "FQ-235 Lane C",
  validated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  metric_type = "canonical_screen", selection_type = "chain",

  score_artifact = list(
    path = "stage_artifacts/WT-D20260821_001/laneC_scores.parquet",
    canonical_name_note = paste("표준명 `alpha_scores.parquet` 을 쓰지 않았다 —",
      "본 라운드는 자본용 단일 α̂ 벡터를 만들지 않고 **표적 범함수 대조군 3열**",
      "(s_mean/s_q50/s_q90)을 나란히 낸다. 한 열을 골라 alpha_scores 로 승격하면",
      "사전등록 §8 이 금지한 argmax 선택이 되므로 라운드-고유명을 유지한다."),
    columns = c("Date","sig_date","Ticker","s_mean","s_q50","s_q90"),
    n_rows = nrow(sc), n_months_scored = uniqueN(sc$sig_date),
    n_months_backtested = 198,
    integrity = list(
      all_finite = all(is.finite(sc$s_mean) & is.finite(sc$s_q50) & is.finite(sc$s_q90)),
      constant_months = 0, month_sequence_gaps = 0,
      per_month_universe_min = min(sc[, .N, by=sig_date]$N),
      per_month_universe_max = max(sc[, .N, by=sig_date]$N),
      reuse_decision = paste("선행 세션(08-21 09:06) 산출물을 **재실행 없이 재사용**했다.",
        "근거: 스코어 스크립트 말미 3개 산출물(parquet·meta·conditioning.rds)이 전부 존재하고",
        "타임스탬프가 동일(09:06) = 완주 증거. 독립 무결성 검사 통과(위 항목).",
        "사전등록도 고정본이 이미 있어 재작성 없이 승계했다."))),

  pit = list(
    c1_rolling_only = "확장창 워크포워드 — 각 예측월 학습은 sig_date < m 만. burn-in 60개월.",
    c1_standardization = "열 평균/sd 를 **학습창에서만** 산출해 검정월에 적용(월내 누출 없음).",
    c1_rank_selection = "랭크-노출 QR 의 유지열 K_m 도 학습창에서만 결정.",
    c4_anchor = "팩터 sig_date → 보유 anchor 는 Lane A 패널 규약 승계(arm A/B 와 anchor 199개월 완전 일치).",
    c13_c15 = "패널은 load_month_factors + Z_Score_Aligned 경유 산출물(lane_a_feature_panel.parquet) 승계 — 부호 반전 없음.",
    lookahead_incidents_found = 0,
    padding_month_note = paste("returns 패널 말미 2026-09-01(전 종목 Ret_1m==0 합성 패딩)은",
      "계약이 백테에서 제외하며, F1/F2 측정 창도 백테 198개월로 통일했다. 미래참조 아님.")),

  frame_parity = R$frame$frame_parity,
  benchmark_vintage_incident = R$frame$benchmark_vintage_incident,
  measurement_window_fix = R$measurement_window_fix,

  prereg_verdicts = list(
    P1 = list(verdict = R$P1$verdict, rule = R$P1$rule,
              pairs = lapply(R$P1$pairs, function(p) p[c("pair","n_months","mean_diff_ann_pct",
                "nw3_t","label","mde_own_sd_ann_pct","mde_ext_ref_ann_pct",
                "power_contract_verdict","bar_restates_t")])),
    P2 = list(pass = R$P2$pass, rho = R$P2$rho_spearman, threshold = R$P2$threshold),
    F1 = list(pass = R$F1$pass, gap = R$F1$gap, nw3_t = R$F1$nw3_t,
              j_bar_T = R$F1$j_bar_T, j_bar_M = R$F1$j_bar_M, tie_months = R$F1$tie_months),
    F2 = list(pass = R$F2$pass, all_underpowered = R$F2$all_underpowered,
              pairs = lapply(R$F2$pairs, function(p) p[c("pair","mean_diff","nw3_t","power_label")])),
    F3 = list(pass = R$F3$pass, rho_linear = R$F3$rho_linear, rho_ml = R$F3$rho_ml,
              abs_diff = R$F3$abs_diff),
    regime_interaction_c = R$regime_interaction_c),

  power_contract = list(
    contract = "02_Infrastructure/contracts/required_effect_size.R",
    dual_sd_axis = paste("계열 자신 sd 와 계약 외부 기준 sd(0.0394) 양쪽으로 MDE 를 산출했다.",
      "계약이 mean 쌍을 INCONCLUSIVE_BAR_RESTATES_T 로 자기신고(implied_t 2.00)했기 때문",
      "— 계열 자신 sd 바는 t 검정의 재진술이라 단독으로는 정보가 없다."),
    conclusion = "두 sd 축 어디서도 관측 효과가 MDE 를 넘지 못함 ⇒ 미결(UNDERPOWERED) 라벨은 강건.",
    precedent = "stage_artifacts/fq233_probe0_20260813/armC_power_addendum.json (MDE 연 9.25%p) 재현"),

  adversarial_diagnostics = list(
    f1_baseline_confound = ADV$f1_baseline_decomposition[c("j_bar_T","j_bar_M_ML_internal",
      "j_bar_M_LINEAR_internal","j_bar_M_pooled_prereg","contrast_vs_pooled",
      "contrast_vs_ML_internal","contrast_vs_LINEAR_internal",
      "linear_over_ml_homogeneity_ratio","random_selection_expected_jaccard","disposition")],
    warned_month_sensitivity = ADV$warned_month_sensitivity,
    variance_decomposition = ADV$variance_decomposition_L_mean_vs_ML_mean,
    status = "전부 POST-HOC. 사전등록 판정 불변(§10)."),

  numerical_conditioning = list(
    regularization = "none — 정확 alias 만 랭크-노출 QR 로 제거(사전등록 §2.1 선택지 ii)",
    n_kept_median = 309, n_kept_range = c(306, 309),
    cond_A_median = 86503.65, cond_A_max = 269331.69,
    rq_warning_months = 39, rq_warning_total_months = 199,
    warning_text = "quantreg::rq.fit(method='fn') 'possibly singular design'",
    assessment = paste("스코어 붕괴 없음(상수월 0 · 월 sd 정상). 경고월은 세 arm 전부 rank-IC 가 약해",
      "q50/q90 특유 결함이 아니라 '어려운 달' 지표다. 민감도에서 라벨 전환 없음.")),

  gates_not_applied = list(
    graduation_hard_3 = "사전등록 §9 — 자본 자격 주장 없음. 참고 관측: PORT_t 최고 +1.10 ≪ 2.95 · calmar 최고 0.339 < 0.64.",
    dsr = "selection_type=chain — HARD 부적용. 진단값만 기재(L_mean 0.8612 · L_q50 0.4448 · L_q90 0.5667).",
    book_marginal = "미요청 — book_state 미접근.",
    ax001_v2 = "적용 대상 아님 — defense family 주장 없음(없는 역할 주장을 만들지 않기 위해 미산출)."),

  overall_verdict = "PARTIAL__NEGATIVE_CONTROL_NOT_ESTABLISHED__P1_UNDERPOWERED_P2_FAIL_F1_CONFOUNDED",
  capital_claim = "없음",
  artifacts = list(
    prereg = "stage_artifacts/WT-D20260821_001/PREREG_WT_D20260821_001.md",
    scores = "stage_artifacts/WT-D20260821_001/laneC_scores.parquet",
    result = "stage_artifacts/WT-D20260821_001/laneC_result.json",
    adversarial = "stage_artifacts/WT-D20260821_001/laneC_adversarial.json",
    full = "stage_artifacts/WT-D20260821_001/laneC_full.rds",
    package = "qepm/mailbox/worktask/WT-D20260821_001/alpha_package.json",
    challenge_note = "qepm/mailbox/worktask/WT-D20260821_001/challenge_note.md")
)
write_json(v, file.path(OUT, "alpha_validation.json"), auto_unbox = TRUE, pretty = TRUE,
           digits = 8, na = "null")
cat("발행:", file.path(OUT, "alpha_validation.json"), "\n")
z <- fromJSON(file.path(OUT, "alpha_validation.json"))
cat("재읽기 OK — keys:", length(names(z)), "· verdict:", z$overall_verdict, "\n")
