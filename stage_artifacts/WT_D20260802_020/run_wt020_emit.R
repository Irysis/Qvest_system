# =============================================================================
# run_wt020_emit.R — WT-D20260802_020 alpha_package + alpha_validation 발행
#   순서 의무: alpha_package write → record_package_lineage (L-194)
# 실행: Rscript -e 'source("stage_artifacts/WT_D20260802_020/run_wt020_emit.R")'
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260802_020")
MB  <- file.path(ROOT, "qepm/mailbox/worktask/WT-D20260802_020")
say <- function(fmt, ...) cat(sprintf(paste0("[wt020e] ", fmt, "\n"), ...))
R <- readRDS(file.path(OUT, "wt020_eval_results.rds"))

# ── alpha_vector: 최신 표본월(2026-03-31 d0) resid_zmax5 부호반전 (위험지표) ──
SIG <- as.data.table(read_parquet(file.path(OUT, "alpha_scores.parquet")))
SIG[, Date := as.Date(Date)]
last_d0 <- max(SIG$Date)
L <- SIG[Date == last_d0 & is.finite(resid_zmax5)]
L[, score := -resid_zmax5]                    # 높을수록 crash-위험 낮음 (위험지표 — 수익 기대값 아님)
L[, conf := 0.6 * pmin(1, abs(resid_zmax5) / 2 + 0.5)]   # 상한 0.6 (challenge C2 — 오소비 방지)
alpha_vec <- setNames(as.list(round(L$score, 5)), L$Ticker)
conf_vec  <- setNames(as.list(round(pmin(L$conf, 0.6), 3)), L$Ticker)
say("alpha_vector(위험지표 라벨): %s 기준 %d종", as.character(last_d0), nrow(L))

esc_max5 <- list(escape_type = "SPECIAL_OP",
  op_code_path = "stage_artifacts/WT_D20260802_010/ot_w1_lib.R::ot_stock_quantiles (max5 성분)",
  walk_forward = TRUE)

fm <- R$fm; inc <- R$incidence
pkg <- list(
  task_id = "WT-D20260802_020",
  as_of_date = "2026-08-02",
  forecast_horizon = "1M",
  spec_version = "ast_v1.1",
  hypothesis = list(
    statement = "MAX5(63d 상위 5일 수익 평균)는 종목-레벨 crash(익월 횡단면 하위 10%) 발생을 현행 252d 위험 축(D01_IdioVol/D02_Beta/D03_RealVol/D45_Downside_Dev) 통제 후에도 예측한다 — 단 그 증분의 정체는 63d 최근창 꼬리-변동성 정보이며 MAX5 고유 정보가 아니다(동일창 vol63+dsd63 통제 시 소멸).",
    mechanism = list(
      agent = "복권선호 개인 수요(WT-014 반증검정 t +3.90 승계)가 만드는 고-MAX5 종목의 fat-tail 가격 경로 + 변동성 클러스터링(단기 변동성의 지속)",
      friction = "KR 공매도 제약(고평가 즉시 청산 불가) + 현행 위험 축의 252d 창 관성 — 최근 63d에 형성된 꼬리 위험이 1년 창 통계에 희석되어 위험모델에 미반영",
      path = "신호월까지 극단 상방일 발생 → 익월 양측 꼬리 동시 확대(crash 발생률 2.11배 + boom 발생률 1.54배) → crash-name 발생률로는 예측 가능하되 평균수익으로는 상쇄(스프레드 t −0.12)"
    ),
    falsification = "동일 63d 창 vol63/dsd63(가격 리프 파생) 통제 시 증분이 유지되면 'MAX5 고유 lottery 정보' 서사 채택, 소멸하면 '단기창 변동성 재포장' — 실측 소멸(t +0.95): 고유 정보 서사 기각, 단기창 정보 서사 채택",
    regime_scope = list(
      holds_in = list("RISK_ON", "NEUTRAL", "CAUTION", "CRISIS"),
      weakens_or_reverses_in = list("CRISIS/CAUTION에서의 평균수익-기반 소비(배제 필터·랭킹)"),
      boundary_rationale = "발생률 예측(위험지표 소비)은 전 국면 성립(b_max5 t: RISK_ON 13.44 / NEUTRAL 2.51 / CAUTION 3.45 / CRISIS 2.33). 반면 평균수익 소비는 스트레스 국면에서 역전 — CAUTION ret_spread +1.76%/월(t +2.08), boom_lift +7.4pp: 상방 꼬리(고베타/lottery 반등)가 crash를 상쇄. WT-014 CRISIS 배제 역효과(t −1.78)와 본 라운드 CRISIS 발생률 양수(t +3.89)가 동시 성립 — 긴장은 '발생률 vs 평균'의 소비 형태 분리로 해소"
    )
  ),
  factors = list(
    list(factor_id = "F1_max5_crash_incidence",
      ast = list(op = "CS_ZSCORE",
        args = list(list(leaf = "SPECIAL_OP",
          field = "max5_63d (63거래일 창 상위 5일 저장 Ret 평균 — WT-010 ot_panel 동결분 소비, 재계산 없음)",
          op_code_path = esc_max5$op_code_path, walk_forward = TRUE,
          escape_contract = esc_max5))),
      role = "risk_indicator",
      restatement_exposure = 0,
      restatement_note = "가격(저장 Ret) 리프 — 재무 재작성 비대상. rawdata Ret 방화벽 준수(재계산은 방향 검증 전용)."
    )
  ),
  combination_rule = "single_factor",
  verdict = "designed",
  self_pit_check = list(
    performed = TRUE,
    leaves_checked = list(
      list(leaf = "SPECIAL_OP:max5_63", availability_rule = "fixed: 저장 일간 Ret — 창 종점 d0(전월말), 홀딩월 시작 전 (C5, WT-014 판정 승계)", restatement_prone = FALSE),
      list(leaf = "D01_IdioVol/D02_Beta/D03_RealVol/D45_Downside_Dev", availability_rule = "fixed: load_month_factors(d0) 경유(C15) — 252d lookback, sig_date 이하 데이터만(connector PIT 계약)", restatement_prone = FALSE),
      list(leaf = "fwd Ret_1m (라벨 전용 — 신호 아님)", availability_rule = "forward 라벨: 독립 일간 재계산과 cor 1.0000(전체/월중앙/월최악) + 위반 주입 FAIL 발화 실증", restatement_prone = FALSE)
    ),
    verdict = "clean"
  ),
  alpha_vector = alpha_vec,
  confidence_vector = conf_vec,
  alpha_vector_label = "★risk-axis indicator — 평균수익 기대값 아님(top-decile 익월 스프레드 t −0.12). 랭킹/선별 소비 금지(WT-010 랭킹 전이 실패 PORT_t −1.616 실측). 검증된 소비 = crash 발생률(위험모델 진단) + 포트 노출 tripwire(monitoring).",
  signal_matrix_ref = "stage_artifacts/WT_D20260802_020/alpha_scores.parquet (Date,Ticker,max5,zmax5,resid_zmax5 — 256개월 신호 패널, 라벨 미포함)",
  factor_specs = list(list(
    factor_family = "Lottery/MAX (risk-axis 소비)",
    proxy = "MAX5_63 — 63d 창 상위 5일 저장 Ret 평균, 횡단면 z(3sd winsor) + 252d 위험 축 4종 잔차화",
    formula = "crash_{i,t+1} ~ z(max5) + z(D01)+z(D02)+z(D03)+z(D45) — 월별 횡단면 LPM, Fama-MacBeth",
    lag_rule = "price t-1 (창 종점 = 전월말 d0); 통제 = load_month_factors(d0)",
    winsorization = "3std (월별 횡단면)",
    neutralization = "252d 위험 축 4종 횡단면 잔차화 (resid_zmax5)",
    economic_rationale = "behavioral(복권수요 fat-tail) x 변동성 클러스터링 — 252d 축이 놓치는 63d 꼬리 정보. 동일창 통제 소멸 실측으로 'MAX5 고유' 서사는 기각(challenge C1)",
    weight_theta = 1.0,
    references = list("Bali, Cakici, Whitelaw 2011 JFE (Maxing Out)", "Fama, MacBeth 1973 JPE", "WT-D20260802_014/016 실측 승계")
  )),
  diagnostics = list(
    canonical_port_t_nw_lag3 = NA,
    canonical_port_t_note = "미산출 — 본 라운드는 포트폴리오 구성 없는 위험-축 특성화(FM 횡단면). 선별 소비의 canonical/weighted 실측은 WT-014(3.620/3.866)에 실재. 사유 challenge_flags 기록.",
    fm_full_mean_b = round(fm$full$mean_b, 5),
    fm_full_t_nw_lag3 = round(fm$full$t, 3),
    fm_full_n_months = fm$full$n,
    fm_univariate_t = round(fm$uni$t, 3),
    fm_same_window_t = round(fm$sw$t, 3),
    fm_same_window_note = "★동일 63d 창 vol63+dsd63 통제 시 증분 소멸(t +0.95) — 증분의 정체 = 단기창 변동성 정보 (challenge C1 ACCEPT)",
    fm_abs20_label_t = round(fm$abs$t, 3),
    fm_boom_t = round(fm$boom$t, 3),
    crash_incidence_top_decile = round(inc$summary[, mean(p_top)], 4),
    crash_incidence_base = round(inc$summary[, mean(p_base)], 4),
    crash_lift = round(inc$crash_lift, 4),
    crash_lift_t = round(inc$t_crash, 2),
    boom_lift = round(inc$boom_lift, 4),
    boom_lift_t = round(inc$t_boom, 2),
    ret_spread_monthly = round(inc$ret_spread, 5),
    ret_spread_t = round(inc$t_spread, 2),
    r2_ctrl_only = round(R$r2$ctrl_only, 4),
    r2_full = round(R$r2$full, 4),
    rank_ic = NA, icir = NA, monotonicity = "십분위 crash 발생률 단조 3.9%→21.6% (10/10 방향 일관)",
    subperiod_stability = NA, turnover_proxy = NA, harvey_t_stat = NA, post_neutralization_ic = NA
  ),
  selection_objective = "canonical_port_t",
  selection_objective_note = "형식 필드(schema enum) — 본 라운드는 후보 간 선택 없음(n_trials=1 사전등록 단일). 실측 판별 = 사전등록 decision_rule(FM NW lag-3 t >= 2.0). proxy 손계산 없음.",
  alpha_discovery_count = 1,
  challenge_flags = list(
    "canonical_port_t 미산출 — 포트 구성 없는 위험-축 특성화 라운드 (선별 실측은 WT-014 소유)",
    "동일창(vol63/dsd63) 통제 시 증분 소멸 t +0.95 — 'MAX5 고유 정보' 아님, 단기창 변동성 정보 (C1 ACCEPT)",
    "평균수익 스프레드 t −0.12 — alpha_vector는 위험지표이며 수익 랭킹 소비 금지 (C2 ACCEPT)",
    "CRISIS 셀 n=13 (t +2.33) — 저검정력, 4국면 방향 일관으로 보강 (C3 PARTIAL)",
    "DB-native 단기 vol(D34_RealVol_21d/D42_EWMA_Vol) 통제 미시험 — next_probe 1 (C4 PARTIAL)",
    "승계 패널 결함 2건 플래그: screen_inputs bench 최종월 부분월 절단 + bench 2소스 35개월 >1%p 괴리 — 본 측정 비오염 실증(REBUTTAL, cor 1.0000 + 위반주입 FIRED + 표본 밖) (C5)"
  ),
  verdict_summary = "특성화 positive(사전등록 판별 충족): 252d 위험 축 통제 후 crash 발생률 증분 실재 — FM t +13.15(기준 2.0), top-decile 발생률 21.4% vs base 10.1%(2.11배, t +17.7), 십분위 단조, 절대문턱(-20%) 라벨 강건(t +8.4), 전 국면 성립(CRISIS t +2.33 포함). ★해석 제약: 증분의 정체 = 63d 단기창 변동성 정보(동일창 통제 시 소멸 t +0.95) — MAX5 고유 아님. CRISIS 긴장 해소: 발생률 예측(전 국면 유효)과 평균수익 소비(스트레스 국면 역전 — 상방 꼬리 상쇄)의 분리. 자본 주장 없음.",
  method_shopping_log = list(alpha_agent = list(
    candidates_tried = 1,
    method_log = list(list(name = "MAX5_crash_prediction_FM_incremental",
                           fm_t_nw = round(fm$full$t, 3), selected = TRUE)),
    note = "사전등록 단일 primary — 동일창/절대문턱/boom/국면/tier는 사전등록 비선택 진단"
  ))
)
write_json(pkg, file.path(MB, "alpha_package.json"), pretty = TRUE, auto_unbox = TRUE, digits = 8)
say("alpha_package.json 발행")

# lineage (write 후 — L-194 순서)
source("02_Infrastructure/worktask/lineage_utils.R")
record_package_lineage(
  task_id = "WT-D20260802_020",
  package_type = "alpha_package",
  method_selected = "MAX5 crash-incidence FM (preregistered single primary, 4-axis 252d controls via load_month_factors)",
  input_file_paths = c(
    "stage_artifacts/WT_D20260802_014/alpha_scores.parquet",
    "stage_artifacts/WT_D20260802_010/ot_panel.parquet",
    "stage_artifacts/WT_D20260714_004/screen_inputs.rds",
    file.path(OUT, "controls_panel.parquet")
  )
)
say("lineage 기록 완료")

# ── ast_features 사이드카 (기각분 포함 전량 로깅 의무 — 특성화 라운드도 기록) ──
source("02_Infrastructure/contracts/ast_sidecar.R")
ast_sidecar_log(
  lane = "fm_characterization",
  strategy_id = "WT-D20260802_020_MAX5_CRASH_INCIDENCE",
  ast_features = list(
    node_count = 3, max_depth = 2, free_param_count = 2,
    distinct_field_count = 1, conditional_op_count = 0, window_variety = 1,
    restatement_exposure = 0, escape_leaf_count = 1,
    escape_leaf_types = list("SPECIAL_OP"),
    note = "CS_ZSCORE(SPECIAL_OP:max5_63) + 252d 4축 잔차화. free_param = {window 63, crash q 0.10}"
  ),
  metrics = list(
    metric_type = "fm_cross_sectional",
    fm_t_nw_lag3 = round(fm$full$t, 3),
    fm_same_window_t = round(fm$sw$t, 3),
    crash_lift = round(inc$crash_lift, 4),
    ret_spread_t = round(inc$t_spread, 2)
  ),
  extra = list(run_id = "WT020_fm", n_months = fm$full$n,
               preregistered = TRUE, n_trials = 1)
)
say("ast_sidecar 기록 완료")

# ── L-code 아티팩트 ──────────────────────────────────────────────────────────
lc <- list(
  l_code = paste0("L-AR-", format(Sys.time(), "%Y%m%d_%H%M%S")),
  strategy_id = "WT-D20260802_020_MAX5_CRASH_INCIDENCE",
  grade = NA,
  core_reference = "stage_artifacts/WT_D20260802_020/{alpha_validation.json, wt020_eval_results.rds, preregistration.json}",
  lesson_text = paste0(
    "MAX5의 위험-축 소비 특성화(FQ-112, 소비면 4): (1) 252d 표준 위험 축(D01/D02/D03/D45) 통제 후 종목-레벨 crash(익월 횡단면 하위 10%) 발생률 증분 실재 — FM NW t +13.15, top-decile 발생률 2.11배(21.4% vs 10.1%), 십분위 단조 3.9%→21.6%, 절대문턱(-20%) 강건 t +8.43. ",
    "(2) ★증분의 정체 = 63d 단기창 꼬리-변동성 정보 — 동일창 vol63+dsd63 통제 시 소멸(t +0.95). 'MAX5 고유 lottery 정보' 서사 기각: 위험모델 관점에서 필요한 것은 max5가 아니라 단기창 변동성 축. ",
    "(3) ★CRISIS 긴장 해소(WT-014 배제 역효과 t −1.78 vs crash 예측): 발생률 예측은 전 국면 성립(CRISIS t +3.89 lift +10.1pp)하되 평균수익은 스트레스 국면에서 상방 꼬리가 상쇄(CAUTION ret_spread +1.76%/월 t +2.08, boom_lift +7.4pp) — '발생률 vs 평균'의 소비 형태 분리가 정답. 배제 필터(평균 소비)는 NEUTRAL 국한, 위험지표(발생률 소비)는 전 국면. ",
    "(4) cap-tier: OTHER lift +11.0pp(t 17.0) / MID +5.3pp(t 3.4) / MEGA +4.7pp(t 2.5) — 소형 국소 아님(전 tier 유의, 강도는 소형 우세). ",
    "(5) 포트-레벨(진단): top-25 max5-z 노출이 하위 5% active 월 이전에 유의 상승(사전 노출 +0.273 vs −0.077, Wilcoxon p 0.001) — monitoring tripwire 근거. 선형 OLS는 무유의(t −0.75) — 문턱형 소비가 적합. ",
    "(6) 배관 발견 2건: screen_inputs(WT_D20260714_004) bench 최종 라벨월 = 빌드일 절단 부분월(-0.2001 vs 정본 -0.2363, d0>=2026-04-30 라벨 소비 금지 플래그) + bench 2소스 35개월 >1%p 괴리(worst 2026-03-31 4.49pp) — 본 측정 비오염(라벨 방향 독립 재계산 cor 1.0000 + 위반 주입 FIRED)."),
  tags = list("max5", "lottery", "crash_prediction", "risk_axis", "fama_macbeth", "short_window_vol", "regime_conditional", "fq112"),
  created_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
  research_mode = "alpha_research",
  created_by = "alpha-research (WT-D20260802_020)",
  metric_type = "fm_cross_sectional",
  construction_type = "risk_axis_characterization",
  mechanism_hypothesis = "복권수요 fat-tail x 변동성 클러스터링 — 252d 위험 축의 창 관성이 63d 꼬리 정보를 희석",
  lcode_schema_version = "v2",
  n_trials = 1,
  selection_type = "preregistered_single_primary",
  record_type = "consume_surface_characterization",
  fm_full_t = round(fm$full$t, 3),
  fm_same_window_t = round(fm$sw$t, 3),
  crash_lift = round(inc$crash_lift, 4),
  crash_lift_t = round(inc$t_crash, 2),
  boom_lift = round(inc$boom_lift, 4),
  ret_spread_t = round(inc$t_spread, 2),
  crisis_fm_t = 2.33,
  caution_ret_spread_t = 2.08,
  n_months = fm$full$n,
  falsification_attempts = 2,
  next_probe = list(
    "NP-1: DB-native 단기 vol 통제 재시험 — D34_RealVol_21d/D42_EWMA_Vol을 통제에 추가한 FM으로 'DB 기존 자원으로 충분한가' 판정 (충분하면 신규 팩터 불요, 배선만)",
    "NP-2: monitoring tripwire 사전등록 라운드 — 포트 max5-z 노출 문턱(예: +0.25) 발화 규칙의 hit rate/false alarm 실측 (Wilcoxon p 0.001 승계)",
    "NP-3(조건부): 스트레스 국면 lottery 보유 편익(CAUTION ret_spread t +2.08)의 국면-조건부 소비 — FR/RAMP 모드 이식 후보"),
  next_probe_note = "소비면 순회: 1(랭킹)=WT-010 기각 / 2(필터)=WT-014 / 3(오버레이)=WT-016 / 4(위험모델)=본 라운드 / 5(monitoring)=NP-2 / 6(선별 라벨)=WT-014 / 7(타 모드)=NP-3"
)
lc_dir <- "stage_artifacts/l_code/alpha_research"
if (!dir.exists(lc_dir)) dir.create(lc_dir, recursive = TRUE)
lc_path <- file.path(lc_dir, "l_code_WT_D20260802_020_FQ112_MAX5_CRASH_INCIDENCE.json")
write_json(lc, lc_path, pretty = TRUE, auto_unbox = TRUE, digits = 8)
say("L-code 아티팩트: %s", lc_path)

# ── status.json 갱신 + governance_log append ─────────────────────────────────
st <- fromJSON(file.path(MB, "status.json"), simplifyVector = TRUE)
st$current_phase <- "ALPHA_DONE"
st$updated_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
write_json(st, file.path(MB, "status.json"), pretty = TRUE, auto_unbox = TRUE)
gl_path <- file.path(MB, "governance_log.json")
gl <- tryCatch(fromJSON(gl_path, simplifyVector = FALSE), error = function(e) list())
gl[[length(gl) + 1]] <- list(
  ts = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  actor = "alpha-research",
  event = "ALPHA_DONE",
  note = "FQ-112 crash 예측력 특성화 완료 — FM t +13.15(252d 축 대비) / 동일창 소멸 t +0.95 / CRISIS 긴장 해소(발생률 vs 평균 분리). Self-Adversarial 7건(challenge_note.md). 자본 주장 없음."
)
write_json(gl, gl_path, pretty = TRUE, auto_unbox = TRUE)
say("status ALPHA_DONE + governance_log append 완료")
