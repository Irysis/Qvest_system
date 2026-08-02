# =============================================================================
# FQ-108 run_07: verdict + charts + telegram
#   verdict → stage_artifacts/method_frontier/fq108_verdict.json (지정 경로)
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
})
data.table::setDTthreads(1)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
OUT_DIR <- file.path(ROOT, "stage_artifacts/method_frontier")
LANE <- file.path(ROOT, "04_Research/method_frontier/fq108_tailvol_risk_axis")

M  <- fromJSON(file.path(OUT_DIR, "fq108_metrics.json"))
TR <- fromJSON(file.path(OUT_DIR, "fq108_transfer.json"))
R3 <- fromJSON(file.path(OUT_DIR, "fq108_run03_meta.json"))
R2 <- fromJSON(file.path(OUT_DIR, "fq108_run02_meta.json"))
CADD <- tryCatch(fromJSON(file.path(OUT_DIR, "fq108_crowding_addendum.json")), error = function(e) NULL)
DM <- as.data.table(M$dm_tests); SUMM <- as.data.table(M$summary_by_cell)
PCTL <- as.data.table(M$positive_control)
PAIRS <- as.data.table(read_parquet(file.path(OUT_DIR, "fq108_pairs.parquet")))

gd <- function(pf, tg, es, tr, bl) {
  r <- DM[portfolio == pf & target == tg & est == es & treatment == tr & baseline == bl]
  if (!nrow(r)) return(list(diff = NA, t = NA, verdict = "absent"))
  list(diff = round(r$mean_qlike_diff, 5), t = round(r$dm_t, 3), n = r$n, verdict = r$verdict)
}
PF <- "real_book_overlaid"

# ---- 판정 (사전등록 규칙 그대로 적용) ---------------------------------------
prim <- gd(PF, "total", "lw_nls", "B_d35", "A_base")
prim_verdict <- if (is.na(prim$t)) "no_test" else
  if (prim$t <= -2.0) "WIRE_RECOMMEND" else if (prim$t >= 2.0) "DEGRADATION" else "NO_INCREMENT"

# 흡수: EW×total (lw_linear 대각이 가장 퇴화하는 셀 = 흡수 신호가 가장 잘 보이는 셀)
abs_nls <- gd("ew_top25", "total", "lw_nls",    "B_d35", "A_base")
abs_lin <- gd("ew_top25", "total", "lw_linear", "B_d35", "A_base")
absorbed_frac <- 1 - abs(abs_nls$diff) / abs(abs_lin$diff)

verdict <- list(
  id = "FQ-108",
  title = "단기 꼬리-변동성의 위험-축 소비 판정 (risk forecast accuracy A/B)",
  lane = "method_frontier",
  round_type = "independent_research_round_not_WT",
  agent = "risk-research",
  finalized_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
  preregistration_ref = "04_Research/method_frontier/fq108_tailvol_risk_axis/preregistration.json",
  pin_tag = R3$pin_tag,
  metric_type = "risk_forecast_accuracy_diagnostic",
  selection_objective = "estimation_quality (QLIKE 예측손실 — R4 P3; SR/IR/PORT_t/alpha 미사용)",
  capital_claim = FALSE, graduation_claim = FALSE, weight_proposal = FALSE,
  alpha_modification = FALSE,

  headline = paste0(
    "PRIMARY(사전등록) = NO_INCREMENT. 실 book total-분산 채널에서 D35_RealVol_63d 항을 ",
    "현행 Σ 대각에 넣어도 QLIKE 개선 없음 (DM t = +0.724, n=173). ",
    "정직 posterior가 맞았다 — lw_nls 가 이미 흡수했다(EW-total 셀에서 개선폭 −1.951→−0.049, ",
    "t −6.17→−2.24 = 97.5% 흡수). 더 나아가 D35 의 factor-DB 횡단면 z 는 ",
    "같은 63일 창 실현분산 레벨(rv63) 위에 정보가 0 이다(계수 0.0045, FM-t 1.49; ",
    "두 재료 spearman 0.9967). 단 종목-레벨에서는 전이가 강하게 실재하고(증분 R² +0.172), ",
    "파라미터 없는 하이브리드(H_hybrid)는 4셀 중 3셀에서 유의 개선 — 대각 채널의 잔여 여지는 ",
    "실 book total 이 아니라 EW/분산형·TE 채널에 있다."),

  measurement_integrity = list(
    positive_control = list(
      spec = "lw_nls − lw_linear (A_base) — FQ-057 P1c 기지결과(실 book total DM-t ≈ −4.0) 재현 시험",
      real_book_total = as.list(PCTL[portfolio == PF & target == "total",
                                     .(mean_qlike_diff = round(mean_qlike_diff, 5), dm_t = round(dm_t, 3), n)]),
      ew_total = as.list(PCTL[portfolio == "ew_top25" & target == "total",
                              .(mean_qlike_diff = round(mean_qlike_diff, 5), dm_t = round(dm_t, 3), n)]),
      status = "PASS — 실 book total DM-t −3.748 (P1c −4.0 재현). 하네스가 '진짜 있는 Σ 개선'을 검출한다."),
    violation_injection = list(
      X_perfect = list(
        spec = "v̂_i = 홀딩월 t+1 의 실현 종목분산 (완전 미래참조)",
        real_book_total = gd(PF, "total", "lw_nls", "X_perfect", "A_base"),
        status = "FIRED — DM t −3.420. 가드 발화 실증."),
      X_oracle = list(
        spec = "확장창 회귀에 미래 월평균 log-RV 주입",
        real_book_total = gd(PF, "total", "lw_nls", "X_oracle", "A_base"),
        vs_same_machinery = gd(PF, "total", "lw_nls", "X_oracle", "A2_recal"),
        status = paste0("PARTIAL — A_base 대비 t −0.744(tie). 원인 = X_oracle 이 pooled-회귀 ",
                        "핸디캡(A2_recal 이 A_base보다 +0.132 열화)을 업고 있어서. 동일 머신러리 대조",
                        "(vs A2_recal)에서는 t −1.950. ∴ 약한 canary — 결정적 canary 는 X_perfect.")),
      pit_guards = list(
        factor_asof = sprintf("load_month_factors attr('factor_db_asof_date') 월별 assert %d/%d PASS (fail-closed stop)",
                              R2$n_months_ok, R2$n_months_total),
        train_window = sprintf("훈련 pool 최대 홀딩월 <= 결정월 assert %d회 PASS",
                               as.integer(gsub("\\D", "", R3$pit_guards[2]))),
        c15 = R2$c15_route),
    honesty_note = paste0("★사후 추가 고지: X_perfect(주입 canary 2)와 H_hybrid(파라미터 없는 운영형)는 ",
                          "사전등록 이후 추가됐다. X_perfect 는 사전등록 violation_injection 절이 요구한 ",
                          "가드의 강화판이고, H_hybrid 는 탐색 arm 으로 **사전등록 판정규칙(배선 권고)의 ",
                          "근거로 쓰지 않는다**. PRIMARY 판정은 사전등록 그대로 B_d35 vs A_base 다."))
  ),

  primary_verdict = list(
    cell = "real_book_overlaid × total × lw_nls (n=173, 201301..202606)",
    B_d35_vs_A_base = prim,
    decision = prim_verdict,
    decision_rule_applied = "|DM t| < 2.0 → 증분 없음 (사전등록 decision_rules.no_increment)",
    confound_control = list(
      A2_recal_vs_A_base = gd(PF, "total", "lw_nls", "A2_recal", "A_base"),
      B_d35_vs_A2_recal  = gd(PF, "total", "lw_nls", "B_d35", "A2_recal"),
      reading = paste0("A2_recal(pooled 확장창 재보정)이 그 자체로 유의 열화(t +3.255) — ",
                       "월별 레벨 추적을 잃기 때문. 그 핸디캡을 통제하면 D35 항은 유의 기여(t −3.729). ",
                       "∴ 'D35 정보 없음'이 아니라 '이 operationalization 이 현행 Σ 대각을 못 이긴다'."))
  ),

  H2_absorption = list(
    question = "개선이 lw_nls 위의 증분인가, lw_nls 가 이미 흡수했는가",
    answer = "ABSORBED — lw_nls 가 D35 정보의 대부분을 이미 포착한다",
    evidence_cell = "ew_top25 × total (lw_linear 대각이 μI 로 완전 퇴화 → 흡수 신호가 최대 대비로 보이는 셀)",
    under_lw_linear = abs_lin, under_lw_nls = abs_nls,
    absorbed_fraction = round(absorbed_frac, 4),
    mechanism = paste0("linear LW 는 p>n(중앙 p=301, n=60)에서 rho→1 로 Σ≈μ·I 퇴화 → 개별 분산이 ",
                       "전부 시장평균으로 뭉개진다(logsd 횡단면 분산 0.000). 거기에 D35 를 넣으면 ",
                       "'잃어버린 대각'을 되돌려주므로 개선이 거대하다(QLIKE 5.68→3.73). ",
                       "lw_nls 는 대각을 애초에 보존하므로(logsd 횡단면 분산 0.165) 되돌려줄 게 거의 없다."),
    real_book_total_note = paste0("실 book total 셀에서는 lw_linear 에서도 B_d35 가 개선을 못 냄(t +1.918) — ",
                                  "20종 집중 북의 총분산은 w'μI w ≈ μ·HHI 로 μI 근사가 우연히 덜 나쁘기 때문."),
    sigma_diagnostics = M$sigma_diagnostics
  ),

  H3_transfer = list(
    question = "crash 발생률 예측력(WT-020 NW t 17.66)이 2차 모멘트(분산) 예측으로 전이되는가",
    answer = "전이 O — 그러나 신규 정보 아님 (동일 63일 창 재료)",
    occurrence_channel = TR$transfer$occurrence_channel,
    variance_channel = TR$transfer$variance_channel,
    reading = paste0(
      "① 전이는 실재하고 강하다: 종목-레벨에서 g35 는 현행 Σ 대각 위에 log-RV 설명력을 ",
      "+17.2%p 올린다(FM-NW t 48.67). 발생률(crash lift +4.22pp on base 3.34% = 상대 +126%, t 12.10)과 ",
      "분산이 같은 잠재변수를 보고 있다. ",
      "② 그러나 같은 63일 창 실현분산(rv63)을 통제하면 증분 R² 는 +0.0099 로 붕괴하고 계수 부호가 ",
      "뒤집힌다(FM-t −8.66). 발생률 lift 도 rv63 통제 후 +4.22pp→+1.21pp(t 5.67)로 축소. ",
      "= D35 는 rv63 의 랭크 변환일 뿐 별도 정보원이 아니다(횡단면 spearman 0.9967). ",
      "③ 결정적으로, 종목-레벨 +17%p 개선이 **포트 총분산 예측 개선으로 이어지지 않는다**. ",
      "집중 20종 북의 총분산은 상관·시장 성분이 지배하므로 대각 개선의 한계가치가 작다. ",
      "'축은 맞는데 이 소비 지점(대각)이 병목이 아니다'가 실측 결론."),
    caveat = paste0("본 라운드의 crash 정의(월간 ret <= −20%)와 분위(상위 20%)는 WT-020 과 다르므로 ",
                    "lift 절대수치는 직접 비교 불가(WT-020 +11.2pp). 방향·유의성만 대조 유효.")
  ),

  exploratory_post_registration = list(
    note = "사전등록 이후 추가 — 배선 결정 근거 아님, 후속 사전등록 라운드의 재료",
    H_hybrid_def = "파라미터 없는 교과서 하이브리드: 상관 C = 60m 창 불변, 분산 = exp(0.5·log σ²_60m + 0.5·log rv63) (기하평균)",
    cells = list(
      real_book_total = gd(PF, "total", "lw_nls", "H_hybrid", "A_base"),
      real_book_te    = gd(PF, "te",    "lw_nls", "H_hybrid", "A_base"),
      ew_total        = gd("ew_top25", "total", "lw_nls", "H_hybrid", "A_base"),
      ew_te           = gd("ew_top25", "te",    "lw_nls", "H_hybrid", "A_base")),
    reading = "4셀 중 3셀 유의 개선(−3.588 / −2.756 / −2.374). 미달 셀 = PRIMARY(실 book total, −1.658).",
    factor_db_z_vs_rawdata_level = list(
      B_d35_vs_F_sv63 = gd(PF, "total", "lw_nls", "B_d35", "F_sv63"),
      G_full_vs_F_sv63 = gd(PF, "total", "lw_nls", "G_full", "F_sv63"),
      g35_coef_in_G_full = "0.00451 (FM-NW t 1.490) — rv63 가 들어가면 D35 z 의 기여는 사실상 0",
      structural_implication = paste0("★ load_month_factors 는 Z_Score_Aligned(횡단면 z)만 반환한다 — ",
        "레벨이 소거된다. 변동성/꼬리 계열 팩터(D34/D35/D36/D41/D42/D45/D47/D50, 8종)를 ",
        "**위험모델 입력**으로 쓰려면 factor-DB z 형태는 부적합하고 rawdata-파생 레벨이 필요하다. ",
        "'D35 소비자 0'의 일부는 무관심이 아니라 형태 불일치일 수 있다."))
  ),

  cap_tier_decomposition = TR$cap_tier_decomposition,
  regime_decomposition = TR$regime_decomposition,
  crowding = list(
    status = TR$crowding_status,
    aligned_end = TR$crowding_score_per_factor,
    high_vol_end = if (!is.null(CADD)) CADD$high_vol_end else "not_run",
    floor_reachability = if (!is.null(CADD)) CADD$floor_reachability else "not_run",
    flags = "crowding_score >= 0.75 도달 0건 → crowding_flags 없음. ★단 하향 편향(floor-biased) 라벨 필수 — 아래 caveat.",
    caveat = paste0("4 하위성분 중 vol_concentration 과 passive_overlap_proxy 가 9/9 셀에서 정확히 0. ",
                    "이는 측정값이 아니라 한쪽 바닥(clamp/폴백) — vol_concentration 은 top-20 거래량 점유가 ",
                    "중립비를 넘어야만 0 초과, passive_overlap_proxy 는 benchmark_tickers=NULL 폴백. ",
                    "∴ 'not crowded' 절대 단정 금지, 시점 간 상대 변화만 유효.")
  ),

  wiring_recommendation = list(
    strength = "CONDITIONAL_PENDING_PREREGISTERED_CONFIRMATION",
    pre_registered_decision = paste0("B_d35(factor-DB z) 배선 **불가** — PRIMARY t +0.724. ",
      "사전등록 규칙상 배선 권고 요건(t <= −2.0) 미충족."),
    exploratory_candidate = "H_hybrid (rawdata 63일 실현분산 레벨을 Σ 대각에 기하평균 혼합)",
    consumption_point = list(
      agent_step = "risk-research Step 3 Specific Risk Estimation → Step 4 Σ = BΩB' + D 재조립",
      artifact = "stage_artifacts/WT_{id}/specific_risk.parquet (대각 σ_i 산출 지점)",
      function_boundary = paste0("hrp_core::.get_cor_cov() 는 건드리지 않는다 — 상관 C 는 등재본(lw_nls) 그대로 쓰고, ",
        "대각만 risk agent 측에서 교체한 뒤 Σ = D^½ C D^½ 로 재조립. ",
        "즉 신규 estimator 등재(.get_cor_cov 확장)가 아니라 specific-risk 단계 처치."),
      risk_package_fields = c(
        "diagnostics.specific_risk_method = 'hybrid_60m_63d_geometric'",
        "diagnostics.specific_risk_source = 'rawdata rv63 (factor-DB z 아님 — 레벨 필요)'",
        "diagnostics.qlike_vs_base_dm_t (셀별)"),
      scope_limit = paste0("EW/분산형 포트와 TE(active) 채널에 한정. 실 book(집중 20종) total-분산 채널은 ",
                           "본 라운드에서 tie(−1.658) → 그 채널 권고 아님."),
      blocker = "후속 사전등록 확인 라운드(FQ-108a) 통과 전 배선 금지 — H_hybrid 는 사후 추가 arm."),
    do_not_do = c(
      "D35_RealVol_63d 를 load_month_factors 경유 z 형태로 위험모델 대각에 넣기 (정보 0, PRIMARY tie·B vs F_sv63 t +2.011로 열등)",
      "본 결과를 성과(SR/PORT_t) 개선 논거로 사용 — FQ-057 NP4 이래 'Σ 품질은 위험-축 레버이지 평균-축 레버 아님' 유지",
      "pooled 확장창 대각 재보정(A2_recal 계열) 단독 배선 — 그 자체로 유의 열화(t +3.255)")
  ),

  next_probe = list(
    list(id = "FQ-108a", title = "H_hybrid 사전등록 확인 라운드 (θ × horizon sweep)",
         spec = paste0("θ∈{0.25,0.5,0.75} × horizon∈{D34 21d, D35 63d, D36 126d} rawdata 레벨. ",
                       "PRIMARY cell 을 real_book_overlaid × TE 로 사전등록(본 라운드에서 유일하게 유의한 실 book 채널, t −2.374). ",
                       "sweep 이므로 DSR 게이트 적용(selection_type=sweep)."),
         why = "본 라운드 H_hybrid 는 사후 arm이라 배선 근거가 될 수 없다 — 확인 라운드가 배선의 전제."),
    list(id = "FQ-108b", title = "대각이 아니라 **상관** 채널 — 단기 꼬리-vol 이 공통 꼬리의존(TDC)을 예측하는가",
         spec = paste0("본 라운드는 C 를 전 arm 고정했다(처치=대각 국한, 설계상 의도). ",
                       "실 book total 에서 대각 개선이 안 먹힌 이유가 '상관·시장 성분 지배'라면 레버는 상관에 있다. ",
                       "regime-conditional 상관 shift + Joe-Clayton/Student-t TDC 를 단기 vol 로 조건화해 QLIKE/DM 재측정."),
         why = "PRIMARY tie 의 기전 진단이 직접 지목한 미측정 축."),
    list(id = "FQ-108c", title = "소비면 — 발생률 예측력을 분산이 아니라 CVaR/ES·stress·tripwire 로",
         spec = paste0("crash 발생률 lift +4.22pp (NW t 12.10) 는 2차 모멘트가 아니라 **사건 확률** 자체가 산출물인 ",
                       "소비면에서 그대로 쓸 수 있다. tail_risk_engine EVT-GPD threshold 의 국면조건화 / ",
                       "monitoring tripwire 발화 조건 / risk_package.stress_tests 시나리오 가중. ",
                       "CRISIS 국면 crash lift 는 n_months=2 로 검정 불가 → CAUTION(t 2.18) 부터."),
         why = "answer-principles 4호 소비면 순회에서 ⑤monitoring 신호 면이 미측정."),
    list(id = "FQ-108d", title = "vol/tail 계열 factor-DB 8종의 '형태 불일치' 일괄 진단",
         spec = paste0("D34/D35/D36/D41/D42/D45/D47/D50 — load_month_factors 가 레벨을 소거하므로 ",
                       "위험모델 입력으로는 구조적으로 부적합할 수 있다. 8종 각각에 대해 ",
                       "rawdata-파생 레벨 대비 z-형태의 정보 손실을 실측. 'D35 소비자 0'이 무관심인지 형태 불일치인지 확정."),
         why = "본 라운드가 D35 1건에서 실측한 손실(레벨 소거)이 계열 전체에 적용되는지 미확인.")
  ),

  consumption_faces_swept = list(
    "①factor_ranking" = "측정완료 — WT-D20260802_010 cap-w PORT_t −1.616 / EW-uni −2.274 (수익 전이 사망)",
    "②universe_filter" = "측정완료 — WT-D20260802_022 ΔIR −0.1489 paired t −1.976 (승자 컷)",
    "③overlay_regime_input" = "미측정 → FQ 등재 대상 (국면 오버레이 입력으로서의 단기 꼬리-vol)",
    "④risk_model_beta_budget" = "본 라운드 — 대각 채널 측정완료(NO_INCREMENT), 상관 채널 미측정 → FQ-108b",
    "⑤monitoring_signal" = "미측정 → FQ-108c (발생률 t 12.10 을 tripwire/ES 로)",
    "⑥screening_label" = "미측정",
    "⑦cross_mode_transplant" = "미측정 (RAMP 팩터군 입력)"
  ),

  revival_conditions_INV7 = c(
    "FQ-108b 상관-채널 라운드가 유의(DM t <= −2.0) → 단기 꼬리-vol 의 위험-축 소비 재개",
    "실 book 구조가 집중(20종 HHI 0.115)에서 EW/분산형으로 전환 → EW 셀 H_hybrid t −3.588 이 실 book 에 적용되므로 재판정",
    "21d/126d horizon 에서 real_book total 채널이 t <= −2.0 → 본 라운드의 63일 창 특정 negative 해제",
    "rawdata-파생 레벨 형태(z 아님)로 factor_db 가 vol 계열을 노출하게 되면(FQ-108d) 재측정"
  ),

  scope_compliance = list(
    lane_path = "04_Research/method_frontier/fq108_tailvol_risk_axis/ + stage_artifacts/method_frontier/fq108_*",
    wt_mailbox_untouched = "qepm/mailbox/worktask/ 무기록 — 본 라운드는 alpha 산출물이 없으며 WT 시퀀스 게이트 대상 아님",
    role_boundary = "Σ·위험예측 정확도 진단만 수행. alpha 시그널 추가 0 / alpha_vector 수정 0 / weight 제안 0 / 종목 우열 판단 0",
    production_readonly = "05_Production 읽기 전용 (score_eff cleanT1 + layer5_faith 읽기만). 01_Literature 미접근",
    method_shopping = list(covariance_estimators_tried = 2,
                           log = list(list(name = "lw_nls", cond_median = 98.14, selected = "PRIMARY"),
                                      list(name = "lw_linear", cond_median = 1.00, selected = "대조(흡수 분리)")),
                           note = "둘 다 .get_cor_cov 등재본. 신규 estimator 발굴 아님 → R2-C 상한 5 이내.")
  ),
  artifacts = list(
    preregistration = "04_Research/method_frontier/fq108_tailvol_risk_axis/preregistration.json",
    metrics = "stage_artifacts/method_frontier/fq108_metrics.json",
    transfer = "stage_artifacts/method_frontier/fq108_transfer.json",
    pairs = "stage_artifacts/method_frontier/fq108_pairs.parquet",
    stock_pred = "stage_artifacts/method_frontier/fq108_stock_pred.parquet",
    coef_panel = "stage_artifacts/method_frontier/fq108_coef_panel.parquet",
    asof_audit = "stage_artifacts/method_frontier/fq108_asof_audit.parquet",
    challenge_note = "04_Research/method_frontier/fq108_tailvol_risk_axis/challenge_note.md"
  )
)
write_json(verdict, file.path(OUT_DIR, "fq108_verdict.json"),
           auto_unbox = TRUE, pretty = TRUE, digits = 8, na = "null")
cat("[verdict] written:", file.path(OUT_DIR, "fq108_verdict.json"), "\n")
cat("  PRIMARY:", prim_verdict, " (DM t =", prim$t, ")\n")
cat("  absorbed_fraction:", round(absorbed_frac, 4), "\n")

# =============================================================================
# charts
# =============================================================================
png(file.path(OUT_DIR, "fq108_chart_qlike.png"), width = 1200, height = 760, res = 110)
par(mfrow = c(1, 2), mar = c(8, 4.5, 3.5, 1))
for (tg in c("total", "te")) {
  s <- SUMM[portfolio == PF & target == tg & est == "lw_nls"]
  ordv <- c("A_base", "A2_recal", "B_d35", "C_d45", "D_max", "F_sv63", "G_full", "H_hybrid", "X_perfect")
  s <- s[match(ordv, arm)][!is.na(arm)]
  cols <- ifelse(s$arm == "A_base", "grey35",
          ifelse(s$arm == "B_d35", "firebrick",
          ifelse(s$arm == "X_perfect", "purple",
          ifelse(s$arm %in% c("F_sv63", "H_hybrid"), "steelblue", "grey70"))))
  bp <- barplot(s$mean_qlike, names.arg = s$arm, las = 2, col = cols, border = NA,
                main = sprintf("QLIKE 예측손실 — 실 book × %s × lw_nls\n(낮을수록 정확, n=173)", toupper(tg)),
                ylab = "mean QLIKE", cex.names = 0.8, cex.main = 0.92)
  abline(h = s$mean_qlike[s$arm == "A_base"], lty = 2, col = "grey35")
  text(bp, s$mean_qlike, sprintf("%.3f", s$mean_qlike), pos = 3, cex = 0.66, xpd = NA)
}
dev.off()

png(file.path(OUT_DIR, "fq108_chart_absorption.png"), width = 1150, height = 700, res = 110)
par(mar = c(5, 5, 4, 1))
cells <- data.table(
  lab = c("linear LW\n(대각 μI 퇴화)", "lw_nls\n(대각 보존)"),
  t   = c(abs_lin$t, abs_nls$t), d = c(abs_lin$diff, abs_nls$diff))
bp <- barplot(cells$t, names.arg = cells$lab, col = c("firebrick", "steelblue"), border = NA,
              ylim = c(min(cells$t) * 1.25, 1), ylab = "DM t  (B_d35 − A_base, 음수=개선)",
              main = "H2 흡수 — 같은 D35 항의 개선폭이 기저 추정기에 따라 붕괴\n(EW top-25 × total-분산, n=174)",
              cex.main = 0.95)
abline(h = -2, lty = 2, col = "grey30"); text(0.3, -2.25, "판정선 t = −2.0", cex = 0.72, pos = 4, col = "grey30")
text(bp, cells$t, sprintf("t=%.2f\nΔQLIKE=%.3f", cells$t, cells$d), pos = 3, cex = 0.78, xpd = NA)
mtext(sprintf("lw_nls 가 D35 정보의 %.1f%% 를 이미 흡수", absorbed_frac * 100), side = 1, line = 3.4, cex = 0.85)
dev.off()

png(file.path(OUT_DIR, "fq108_chart_transfer.png"), width = 1150, height = 700, res = 110)
par(mar = c(6.5, 5, 4, 1))
vc <- TR$transfer$variance_channel
vals <- c(vc$incr_r2_g35_given_sigma_diag, vc$incr_r2_rv63_given_sigma_diag,
          vc$incr_r2_g35_given_sigma_diag_and_rv63)
bp <- barplot(vals, names.arg = c("D35 (현행 Σ 대각 위)", "rv63 (현행 Σ 대각 위)", "D35 (Σ 대각 + rv63 위)"),
              col = c("firebrick", "steelblue", "grey60"), border = NA, ylim = c(0, max(vals) * 1.25),
              ylab = "종목 log-분산 증분 R²",
              main = "H3 전이 — 전이는 실재하나 신규 정보 아님\n(종목-월 58,161개, 198개월 FM)", cex.main = 0.95, cex.names = 0.82)
text(bp, vals, sprintf("%+.4f", vals), pos = 3, cex = 0.85, xpd = NA)
mtext("D35 와 rv63 은 같은 63일 창 재료 (횡단면 spearman 0.9967)", side = 1, line = 4.6, cex = 0.85)
dev.off()
cat("[charts] 3 written\n")

# =============================================================================
# telegram (tg_agent_brief 단일 진입점)
# =============================================================================
source(file.path(ROOT, "02_Infrastructure/telegram/telegram_notify.R"))
qlike_tbl <- data.frame(
  arm = c("A_base 현행", "B_d35 +D35", "C_d45 +하방편차", "F_sv63 +63일레벨",
          "H_hybrid 사후", "X_perfect 주입"),
  `QLIKE / DM t` = c("0.2996 / 기준", "0.3289 / +0.72", "0.3749 / +1.98",
                     "0.2737 / -0.68", "0.2587 / -1.66", "0.1018 / -3.42"),
  check.names = FALSE, stringsAsFactors = FALSE)

sections <- list(
  list(type = "summary", heading = "판정", emoji = "📌",
       body = "위험축 첫 측정 — 단기 꼬리변동성 증분 없음. 현행 추정기가 이미 97.5% 흡수."),
  list(type = "table", heading = "arm별 예측손실 (실 북 x 총분산)", emoji = "🔬",
       df = qlike_tbl,
       notes = c("QLIKE 는 분산 예측 오차 — 낮을수록 정확", "n=173개월 (2013-01~2026-06)")),
  list(type = "bullet", heading = "쉬운 설명", emoji = "📖",
       items = c(
         "시도: 급등락을 잘 맞히는 지표를 위험 예측에 쓸 수 있는지 처음 확인",
         "방법: 현행 위험모델에 그 항을 넣고 다음 달 실제 변동폭과 대조",
         "결과: 예측이 나아지지 않음 — 모델이 이미 알던 정보였음",
         "의미: 지표는 유효하나 위험모델의 그 자리는 소비처가 아니다")),
  list(type = "bullet", heading = "측정 무결성", emoji = "🛡",
       items = c(
         "양성 대조 통과 — 기존 추정기 개선을 하네스가 검출 (t -3.748)",
         "위반 주입 발화 — 미래 실현분산을 넣으면 t -3.420 으로 반응",
         "미래참조 가드 198/198 및 394/394 통과 (위반 시 즉시 중단)")),
  list(type = "bullet", heading = "기전", emoji = "🔎",
       items = c(
         "흡수: 같은 항이 구형 추정기 위 t -6.17, 현행 위 -2.24 (40배 축소)",
         "전이 있음: 종목 단위 분산 설명력 +17.2%p (Fama-MacBeth t 48.67)",
         "신규성 없음: 같은 63일 실현분산 통제 시 +0.99%p 로 붕괴",
         "두 재료 순위상관 0.9967 — 사실상 같은 재료의 순위 변환",
         "집중 20종 북의 총분산은 상관 성분이 지배 — 대각은 병목 아님",
         "팩터 창구는 횡단면 표준값만 반환 — 변동성의 절대수준이 소거됨")),
  list(type = "bullet", heading = "위험 신호 및 다음 라운드", emoji = "🚩",
       items = c(
         "군집도 최대 0.448 (문턱 0.75 미달). 단 하위 2성분 바닥 = 하향 편향",
         "다음1: 혼합비와 창길이 훑기 확인 라운드 (주 판정면 = 실 북 TE)",
         "다음2: 대각 아닌 상관 채널 — 단기 변동성으로 공통 꼬리의존 조건화",
         "다음3: 발생률 예측력을 CVaR 및 경보 소비면으로",
         "배선: 현 형태 불가. 혼합안은 확인 라운드 통과 전 배선 금지"))
)
res <- tryCatch(
  tg_agent_brief(agent = "Risk",
                 title = "FQ-108 RISK_DONE — 단기 꼬리-vol 위험축 판정: 증분 없음 (lw_nls 흡수)",
                 sections = sections,
                 charts = c(file.path(OUT_DIR, "fq108_chart_qlike.png"),
                            file.path(OUT_DIR, "fq108_chart_absorption.png"),
                            file.path(OUT_DIR, "fq108_chart_transfer.png"))),
  error = function(e) { cat("[tg] ERROR:", conditionMessage(e), "\n"); NULL })
cat("[tg] done\n")
cat("[done] run_07\n")
