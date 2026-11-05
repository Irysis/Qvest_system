## P2R05 공용 규칙 상수 · 규칙 문장 — register.R(초안 · 등록)과 rehearse.R · evaluate_fixture.R 이 같은 정의를 쓴다(사전등록 final_selection_rule ·
##   rules 의 원천 · 평가는 사전등록 사본만 읽는다 — evaluate.R 은 이 파일을 읽지 않는다).
##   ① p2r05_final_selection_rule() = P2R04 round_rules.R::p2r04_final_selection_rule() 의 키 · 값 · 근거 문장 그대로(DESIGN §5 'P2R04 v3 상수 그대로' ·
##      §12) + 한 키: tail_instrument(⑮ 꼬리 계기 · 시험 조건 · DESIGN §5 ⑮ · §12 문자 그대로). 새 숫자 없음.
##   ② p2r05_rules() = P2R04 사전등록(stage_artifacts) rules 문장 승계 + ⑩ 개정 · ⑮ 신설 · 진단 읽기(§5.1 5종 + LV — 판단 Superfan T2 C-20261018-038) ·
##      기록 추가(§5.2 + 위기 유형별 β 짝 승패) · 결론 이름 규칙(§10.2 ~ 10.4 + LV) · 결론 범위(§10 + 결합 금지 문장 — Q 10-18).
##   숫자 출처: 등급 정본(constraint_defaults.json::tier_graduation · grade_v3.json) · 행동 카드 설정 사본(uc_floor · majority_share) · 헌장 빈칸 1 · 4 · 7 ·
##   문헌(빠른 급락 = Mishkin & White 2002) · ⑮(τ = 설계 §3.3 꼬리 10% · t_min = measurement-graduation §2 DISTRIBUTION_TARGET t_min_survive).
suppressPackageStartupMessages(library(jsonlite))
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

## 기록용 위기 목록의 원천(설계 입력 · 벤치만 · τ_D 까지 · 성과 무관) — P2R04 와 같은 노트 · 같은 줄(줄 머리말이 바뀌면 멈춘다 · fail-closed)
P2R05_STATE_TURN_NOTE <- "04_Research/programs/P2_DEFENSE/_design_notes/state_turn_classify.md"
P2R05_STATE_TURN_PREFIX <- "- 판정 창에서 최대 하락 구간이 상태 전환 전에 온 위기(빠른 · 느린 모두): "
## 규칙 문장 승계 원천 — P2R04 사전등록 정본(rules 문장만 읽는다 · 결과 파일 아님)
P2R05_P2R04_PREREG <- "stage_artifacts/programs/P2_DEFENSE/P2R04_defensive_holdings/prereg.json"
## P2R04 사전등록 rules 중 문장 그대로 잇는 키(DESIGN §5 머리말 목록 — 바뀌는 키는 아래에서 새로 쓴다)
P2R05_RULES_INHERITED <- c("remeasure", "common_window", "pins_at_evaluation", "decisive", "strength", "non_inferiority", "concentration", "recovery",
                           "selection_attribution", "test_window", "state_unturned")
## 칸 계획(DESIGN §12 + 판단 Superfan T2 C-20261018-038 비교 기준 LV 2칸 + 판단 T1 R-20261018-007 C-054 재시드 RX0S 2칸 · 16칸) — 규칙 문장의 칸 수 · 묶음 수를
##   이 표에서 센다(숫자를 박지 않는다) · RX0S control = "seed_pair"(측정 기계 칸 표와 같음 — Q 10-18 통합 정렬 1)
P2R05_CELL_PLAN <- data.frame(
  code = c("P2R05_E2_RX0", "P2R05_E2_V1", "P2R05_E2_V2", "P2R05_E2_Q50", "P2R05_E2_N1", "P2R05_E2_N2", "P2R05_E2_S1", "P2R05_E2_S2", "P2R05_E2_W2", "P2R05_E2_LV", "P2R05_E2_RX0S",
           "P2R05_E3_RX0", "P2R05_E3_V1", "P2R05_E3_V2", "P2R05_E3_LV", "P2R05_E3_RX0S"),
  engine = c(rep("E2", 11), rep("E3", 5)),
  component = c("RX0", "V1", "V2", "Q50", "N1", "N2", "S1", "S2", "W2", "LV", "RX0S", "RX0", "V1", "V2", "LV", "RX0S"),
  role = c("reference", "variant", "variant", rep("diagnostic", 8), "reference", "variant", "variant", "diagnostic", "diagnostic"),
  control = c(NA, NA, NA, "center_only", "tail_perm", "tail_perm", "vol_proxy", "vol_proxy", "capacity_pair", "lowvol_screen", "seed_pair", NA, NA, NA, "lowvol_screen", "seed_pair"),
  stringsAsFactors = FALSE)

## state_turn_classify.md 의 '판정 창에서 최대 하락 구간이 상태 전환 전에 온 위기' 줄 → 위기 키('고점 저점' · evaluate.R .p2_key 와 같은 형식) — P2R04 그대로
p2r05_state_unturned_crises <- function(root, note = P2R05_STATE_TURN_NOTE) {
  p <- file.path(root, note)
  if (!file.exists(p)) stop("[P2R05 규칙] 설계 입력 없음: ", note)
  L <- sub("\r$", "", readLines(p, warn = FALSE, encoding = "UTF-8"))
  s <- L[startsWith(L, P2R05_STATE_TURN_PREFIX)]
  if (length(s) != 1L) stop(sprintf("[P2R05 규칙] %s 에 '판정 창 … 상태 전환 전에 온 위기' 줄이 %d개(1개여야 함)", note, length(s)))
  v <- trimws(strsplit(substring(s, nchar(P2R05_STATE_TURN_PREFIX) + 1L), " · ", fixed = TRUE)[[1]])
  rx <- "^([0-9]{4}-[0-9]{2}-[0-9]{2}) → ([0-9]{4}-[0-9]{2}-[0-9]{2})$"
  if (!length(v) || !all(grepl(rx, v))) stop("[P2R05 규칙] 위기 표기 해석 실패(고점 → 저점): ", paste(v, collapse = " | "))
  list(keys = sub(rx, "\\1 \\2", v), md5 = unname(as.character(tools::md5sum(p))))
}

## final_selection_rule — P2R04 키 · 값 · 근거 문장 그대로(P2R04 round_rules.R 41~53행과 같은 식 · 같은 원천) + tail_instrument
p2r05_final_selection_rule <- function(root, bcfg_path) {
  TD <- fromJSON(file.path(root, "02_Infrastructure/worktask/constraint_defaults.json"), simplifyVector = FALSE)$tier_graduation
  GV <- fromJSON(file.path(root, "06_Registry/grade_v3.json"), simplifyVector = FALSE)
  BC <- fromJSON(bcfg_path, simplifyVector = FALSE)
  SU <- p2r05_state_unturned_crises(root)
  list(calmar_norm = TD$min_calmar, port_t_norm = TD$min_portfolio_alpha_t_nw, w_calmar = GV$weights$calmar, w_port_t = GV$weights$port_t,
       tie_eps = 0.02, tie_eps_role = "S 비열등 여유(P3R01 · P3R02 · P3R03 승계)",
       uc_floor = BC$uc_floor, uc_floor_source = "behavior_card_cfg_at_prereg.json uc_floor — 철학 '강세 참여 ≥ 55%' 절대 하한",
       majority_share = BC$majority_share, majority_share_source = paste0("behavior_card_cfg_at_prereg.json majority_share — ", BC$majority_share_source %||% ""),
       crisis_improve_min = 0.03, crisis_improve_min_evidence = "P2R01 R6 지속성 필터의 '기저 대비 0.03 이상 개선된 위기'(낙폭 포착 기준) 승계 · P3R03 동일 — 결과 전 고정",
       alpha_t_floor = -2, alpha_t_floor_evidence = "헌장 빈칸 4(C)(2026-10-16 도훈 확정) — 유의한 감소 없음(t > −2)",
       alpha_margin_frac = 0.2, alpha_margin_frac_evidence = "헌장 빈칸 4(C)(2026-10-16 도훈 확정) — 감소 ≤ 엔진 자체 보는 창 β-통제 알파의 20% · 엔진 알파 ≤ 0 이면 감소 허용 0",
       single_name_loss_floor = -0.10, single_name_loss_floor_evidence = "헌장 빈칸 1(2026-10-16 도훈 확정) — 깊은 위기 한 종목 기여 < −10% = 집중",
       bull_ratio = 0.8, bull_ratio_evidence = "헌장 빈칸 7(2026-10-17 도훈 확정 · CHARTER-GAPS-2) · 빈칸 4(B)의 80% — 강세 구간 과반에서 기준의 80% 이상",
       fast_window_days = 21L, fast_drop = -0.20,
       fast_evidence = "Mishkin & White (2002) U.S. Stock Market Crashes and Their Aftermath, NBER WP 8992 p.7 — 20% 하락 = 급락 · 속도 창 1일 · 5일 · 1개월 · 3개월 · 1년 중 1개월(≈ 21거래일)을 '빠름' 경계로(헌장 빈칸 6 — 사전 고정)",
       mc8_label_required = "selection_defense",
       mc8_label_required_evidence = paste0("DESIGN §5 ⑭ · §8.2 — 변형 칸 보는 창 패킷의 MC8 귀속 라벨(controls.attribution.label · matched_controls.R mc_attribution ",
                                            "nested_majority_placebo_v2)이 selection_defense = 크기 · 평균 노출 짝 플라시보를 위기 과반에서 넘음. size_defense · exposure_defense · ",
                                            "no_defense · insufficient · 라벨 없음 = 통과 불가(라벨 그대로 기록) — 방어 틸트는 대형주 쪽으로 기울 수 있어 크기 방어를 선택 방어로 세지 않는다(§4)"),
       state_unturned_max_drop_crises = SU$keys,
       state_unturned_max_drop_crises_evidence = sprintf(paste0("기록용 '상태 미전환 최대 하락 위기'(판정 아님 · DESIGN §5 기록 · 철학 P1 C-019 이름 — 구 '꼭대기 시작 손실 위기') — ",
                                                                "%s(벤치만 · τ_D 까지 · 전략 성과 무관 · md5 %s)의 '판정 창에서 최대 하락 구간이 상태 전환 전에 온 위기' 줄을 그대로 읽음",
                                                                "(최대 21거래일 하락 구간 직전 월말에 r252 ≥ 0 ∧ 낙폭 ≤ 확장창 중앙값). 깊은 위기로는 1건뿐이라 판정 조건으로 두지 않는다",
                                                                "(원칙 2 — 한 위기로 통과를 정하지 않는다)"), P2R05_STATE_TURN_NOTE, SU$md5),
       tail_instrument = list(tau = 0.1, ref = "constant_tau", nw_lag = 3, t_min = 2, t_min_source = "measurement-graduation §2 t_min_survive"))
}

## 칸 계획 셈(규칙 문장용) — 묶음(구성)별 칸 수 · 역할별 수
.p2r05_plan_counts <- function(plan = P2R05_CELL_PLAN) {
  list(group = table(plan$engine), n_variant = sum(plan$role == "variant"), n_reference = sum(plan$role == "reference"),
       n_diag = sum(plan$role == "diagnostic"), diag_codes = function(ctl, eng = NULL) plan$code[plan$role == "diagnostic" & plan$control %in% ctl & (is.null(eng) | plan$engine %in% eng)])
}

## 규칙 문장(사전등록 rules) — P2R04 사전등록 rules 의 승계 키는 문장 그대로 · 나머지는 DESIGN §5 · §10 표 문장 그대로 + 구현 규약(평가 코드가 하는 일)
p2r05_rules <- function(root, bcfg_path = NULL, p2r04_prereg = file.path(root, P2R05_P2R04_PREREG), plan = P2R05_CELL_PLAN) {
  if (!file.exists(p2r04_prereg)) stop("[P2R05 규칙] P2R04 사전등록 없음(규칙 문장 승계 원천): ", p2r04_prereg)
  P4 <- fromJSON(p2r04_prereg, simplifyVector = FALSE)$rules
  miss <- setdiff(c(P2R05_RULES_INHERITED, "record", "failure_semantics"), names(P4 %||% list()))
  if (length(miss)) stop("[P2R05 규칙] P2R04 사전등록 rules 키 결손: ", paste(miss, collapse = ", "))
  K <- .p2r05_plan_counts(plan)
  dj <- function(ctl, eng = NULL) paste(K$diag_codes(ctl, eng), collapse = " · ")
  R <- P4[P2R05_RULES_INHERITED]
  c(list(
    vocabulary = paste0("P2R04 사전등록에서 문장 그대로 이은 키(", paste(P2R05_RULES_INHERITED, collapse = " · "), ")의 '장치' = 이 라운드의 소비 규칙(V1 꼬리 거부 · V2 꼬리 순위) · ",
                        "'엔진' = 같은 DNN 기저의 구성(E2 · E3) · '장치 칸' = 변형 칸(P2R05_E*_V1 · _V2) · '방어 팩터 · 장치 팩터' = 해당 없음(처치 = 엔진 안 분위 학습 + 소비 규칙 — DESIGN §3) · ",
                        "판정 계산(①~⑭)의 코드 경로 · 상수는 P2R04 그대로(DESIGN §5) — 미통과 칸의 판정어 이름(라벨)만 P2R05 정의(rules.conclusion_names 판정어 순서 · 격리 교차 점검 v1 필수 1 — ",
                        "통과 조건 13개는 그대로) · V1 = Q50(같은 추첨 중앙값) 순위 보존형(설계 문장 'V1 = 엔진 보존형' 정정 — 철학 Superfan P1 R-20261018-008 C-063)"),
    tested = paste0("규칙 × 구성 판정은 다음을 모두 만족할 때만 — 아니면 미시험(반증 아님): ① 변형 · RX0 둘 다 평가됨(측정 ok ∧ 축 감사 ok) ② 구성 증거(⑩) ",
                    "③ 실효 시작 status = ok(두 칸) ④ 공통 창 사본 · 보는 창 패킷이 만들어짐 ⑤ 위기 짝 — 두 칸의 위기가 모두 짝지어짐(짝 없는 위기 0) ∧ ① 의 짝 ≥ 2 ∧ ② 의 깊은 위기 짝 ≥ 2 ",
                    "⑥ 판정 입력(①②⑤⑥⑨⑫⑬ · 알파 · 엔진 알파)이 모두 유한 ⑦ ⑮ 꼬리 계기 통과(시험 조건 — 미달 · 미측정 = 변형 칸 ", K$n_variant, "개 모두 '미시험(꼬리 계기)' · 반증 아님 · ",
                    "판정어 untested_tail_instrument · 판정 계산 결과는 기록으로 남긴다) — ⑭ 결손은 미시험이 아니다: ⑭ 미측정(판정됨 · 통과 불가 · 판정어 selection_unmeasured). ",
                    "측정 연기(워커 ok=FALSE · deferred)는 판정 전 같은 사양 재측정(rules.remeasure). 같은 선정 집합 조건은 두지 않는다 — 처치가 선택 자체를 바꾼다(⑩ 이 보유 차이를 요구한다)"),
    vintage_group = paste0("같은 구성의 칸은 함께 잰다(measure.sh — ", paste(sprintf("%s 묶음 %d칸", names(K$group), as.integer(K$group)), collapse = " → "),
                           " · 진단 · 비교 기준 칸 포함 · 묶음마다 RX0 먼저) · 칸마다 측정 시작 · 종료 데이터 지문(fingerprint.sh equality) — ",
                           "측정: 묶음 칸 지문이 갈리면 measure.sh 가 배리어 대기 뒤 그 묶음 전체를 1회 재측정 / 평가: 판정 칸(변형 + RX0) 지문이 모두 같아야 판정 · 다르거나 없으면 evaluate.R 이 평가 전체를 멈춘다 · ",
                           "진단 · 비교 기준 칸 지문이 그 구성 판정 칸 지문과 다르거나 없으면 그 칸만 미시험(판정 계속) · V1 전달량(≠ Q50) 대조는 Q50 지문이 그 구성 판정 칸 지문과 같을 때만(아니면 V1 ⑩ 미측정 = 미시험). ",
                           "평가 시점 지문을 함께 기록한다(이름 없는 문자열 비교)")),
    R[c("remeasure", "common_window", "pins_at_evaluation", "decisive", "strength", "non_inferiority")],
    list(construction = paste0("⑩ 구성 증거(개정 · DESIGN §5 ⑩): (a) 사양 base_signal.path md5 = 사전등록 핀 ∧ 워밍 센티널(분위 캐시 261/261 · 양성 대조 통과 · CODE_VERSION) ∧ 셀 로그에 기저 적재 줄(적중 또는 실행) ",
                               "(b) 템플릿 차분 대조 통과(§3.1) ∧ 같은 배치 변형 · RX0 셀 로그의 신호일 수(months=)가 같다(V1 신호 폭은 기록) (c) 전달량: 보는 창 리밸일 중 변형 보유 ≠ RX0 보유인 비율 > 0. ",
                               "V1 은 추가로 보유 ≠ Q50 보유인 비율 > 0(무처치 = 미시험) (d) 재배열 전 교차율 · q̂ 횡단면 표준편차를 기록한다 — 구현 규약: (a) 핀 = 사전등록 operational_pins.files 의 같은 저장소 상대 경로 md5 · ",
                               "워밍 센티널 = 측정에 묶인 사본 results/warm_sentinel.json(measure.sh 가 측정 때 복사 · 없을 때만 04_Research/programs/_lib/night_state/p2r05_warm.done · ",
                               "두 판이 다 있고 다르면 ⑩(a) 기록에 '센티널 판본 다름' — Q 10-18)(JSON — cache_months 완료(done = total · 설계 시점 261/261) · positive_control 통과 · code_version = DT_2002_06975/dnn_quantile/rev1 — ",
                               "분위 엔진 칸만) · 기저 적재 줄 = '[rf_cell_engine] 기저 캐시 적중 — base_v2_<엔진 md5 앞 12자>_…' 또는 '… 기저 캐시 미스 — 엔진 실행: <엔진 파일 이름> […]'(엔진 md5 앞 12자 = 핀) · ",
                               "W2 = 두 엔진 적재 줄 + engine_blend 줄 · 사양 = 같은 구성 RX0 사양에서 base_signal 만 바뀜(구성 키 동일 · 셀 로그 팩터 적재 = 사양) ",
                               "(b) 04_Research/strategies/DT_2002_06975/template_diff_check.R 를 평가 때 다시 실행해 rc 0(분위 엔진 칸만) (c) V1 ≠ Q50 은 같은 구성 Q50 칸이 있을 때만(E3 = 해당 없음 기록) · ",
                               "비교 기준 LV = P2R04 ⑩ 형식(사양 = RX0 factors + D03_RealVol 꼬리 · 셀 로그 팩터 적재 줄 · 혼합 몫 = 도구 상자 기본(E3 RX0 사양 base_weight 위 1회) · 기저 엔진 = RX0 엔진 핀) · ",
                               "PIT = 엔진 PIT 단언(파이썬 max_lab_i ≤ u_i · R 재단언) · LV 팩터 = load_month_factors(Usable_Date ≤ 신호일 · C14 · C15) · lag-1 스트레스판 없음(시점 신호 없음)")),
    R[c("concentration", "recovery", "selection_attribution")],
    list(tail_instrument = paste0("⑮ 꼬리 계기(신설 · 시험 조건 · DESIGN §5 ⑮): 보는 창 신호일(2005-01-31 ~ 2022-11-30 · 215개월)마다 표본 밖 5일 라벨 위의 분위 손실 차 ",
                                  "D_d = mean_i[ρ_0.1(y − 0.1) − ρ_0.1(y − q̂10)] 를 구한다. 라벨 = 시가 d+1 → 종가 d+5 · 그날 예측 종목 안 순위 재척도 · evaluate.R 이 RAWDATA 로 재도출. 조건 = D_d 의 NW(3) t > 2 — ",
                                  "⑮ 의 뜻: 예측 q10 이 상수 0.1(순위 표적의 무조건 10% 분위)보다 표본 밖 10% 분위를 더 잘 맞히는가(분위 기량 R¹(τ) = 1 − Σρ(y − q̂) / Σρ(y − τ) — Koenker & Machado 1999 형식 · ",
                                  "pinball = 분위의 일관 점수 — Gneiting 2011) · 못 넘으면 V 칸 4개가 모두 '미시험(꼬리 계기 실패)' — 원천 ① 반증이 아니라 '이 학습 설정이 종목 왼꼬리를 배우지 못했다' · ",
                                  "t > 2 = screening tier 생존 문턱 관례(measurement-graduation §2 DISTRIBUTION_TARGET t_min_survive |NW-t| ≥ 2.0)의 단측 · 기량 크기 문턱 없음(헌장 빈칸 13) — ",
                                  "구현 규약: 상수 = final_selection_rule.tail_instrument(τ · ref = constant_tau · nw_lag · t_min) · 보는 창 신호일 = 예측표 신호일 중 보유월(신호 다음 달) ≤ τ_D 의 달 · ",
                                  "RAWDATA · 예측표를 τ_D 에서 먼저 자른다 · y = 엔진 표적 정의 그대로(수정 시가 · 종가 · 종가 > 0 행만 · 시가 0 · 결측 = NA · 같은 (종목, 날짜) 첫 행 · 거래일 = RAWDATA 날짜 · ",
                                  "시가 열이 없으면 종가 d → 종가 d+5 · 엔진 .rank01(동률 평균 · ÷ 최대 순위) — 정의 대조 단정 = 분위 엔진 파일의 표적 줄 · 거래일 · 종가 필터 · 시가 센티널 · 중복 처리 줄 일치 + ",
                                  "엔진 파일의 표적 블록 자체를 합성 격자에 돌린 값 = 평가 라벨 함수 값(시가 있음 · 없음 두 경우) · .HORIZON · .rank01 은 엔진 파일에서 읽는다) · NW t = 정본 backtest_result_contract.R::.nw_t_mean ",
                                  "(Bartlett · 사본 금지 — 정의만 파싱해 적재) · 예측표 = 측정에 묶인 판 1개(격리 교차 점검 v1 필수 4): 측정에 묶인 워밍 센티널(results/warm_sentinel.json · ",
                                  "없을 때만 night_state 판)의 qpred = {path, md5} 파일만 읽는다(04_Research/strategies/DT_2002_06975/_work/qpred/<CODE_VERSION md5 8자>_<데이터 지문 8자>.parquet · ",
                                  "열 Date · Ticker · q10 · q50 · q90 · q10_raw · q50_raw · q90_raw · s_perm · s_sigma · sigma252 + 선택 s_hist) — md5 불일치 · 묶인 파일 없음 = 평가 중단(사유 = results/evaluation_halt.json) · ",
                                  "센티널에 qpred 경로 · md5 가 없으면 '예측표 미묶임' = ⑮ 미측정(변형 칸 미시험(계기) · 실패 의미 고정) · 같은 폴더의 다른 파일 = '판본 다른 예측표 n개'(기록만 · 읽지 않는다) · ",
                                  "셀 로그 대조(격리 교차 점검 v2 필수 1 — 측정 칸이 쓴 예측표 = 묶인 판): 분위 엔진 칸(사양 base_signal 에 DT 분위 엔진 · 재시드 짝 제외 — V1 · V2 · Q50 · N1 · N2 · S1 · S2 · ",
                                  "W2 의 V2 성분)의 셀 로그 '[DT qpred] path=' 줄이 있고 그 경로(정규화 — 저장소 상대 · 슬래시 · 대소문자) 또는 그 파일 md5 가 묶인 판과 다르면 평가 중단(사유 기록) · ",
                                  "줄이 없으면(기저 캐시 적중 = 엔진 미실행) '셀 로그 예측표 줄 없음(기저 캐시 적중)'으로 기록하고, 그 칸 기저 적재 줄의 캐시 파일(base_v2_<DT 엔진 md5 앞 12자>_<패널 지문>.rds)을 ",
                                  "같은 평가의 다른 칸이 이번 측정에서 실행으로 만들었고 그 칸의 예측표 줄이 묶인 판이면 '같은 기저 캐시(연쇄 대조 통과)' · 아니면 '⑮ 예측표 셀 로그 대조 불가' 꼬리표 ",
                                  "(⑮ 판정은 유지 — 워밍은 셀 기저 캐시를 시드하지 않는다 · 엔진 월별 DNN 캐시만 데운다) · 셀 로그 없는 칸 = 미측정(대조 대상 아님 · 칸 판정이 미측정으로 다룬다)")),
    list(pass = paste0("변형 칸 통과 = ① ∧ ② ∧ ③ ∧ ④ ∧ ⑤ ∧ ⑥ ∧ ⑦ ∧ ⑨ ∧ ⑩ ∧ ⑫ ∧ ⑬ ∧ ⑭ ∧ ⑮(시험 조건) · ⑧ 제외 아님 · ⑪ = 꼬리표 · ",
                       "규칙 검증 = 같은 규칙이 두 구성(E2 · E3) 모두에서 통과 ∧ ⑧ 제외 아님 · W2(V2 계열 용량 짝)의 '통과'도 같은 13조건(⑮ 포함) — 용량 읽기 입력"),
         selection = paste0("검증 규칙(두 구성 통과 ∧ 집중 제외 아님) 중 보는 창 S(v3)의 RX0 대비 증분(두 구성 평균)이 가장 큰 1개 · 동률(차 < 1e-12)이면 ③ · ④ 비율 합(두 구성 평균) · ",
                            "검증 0 = 선택 없음(P2R04 그대로) · 진단 · 비교 기준 칸은 선택 대상 아님 · 꼬리표: 회복 · ⑤ 수준 · 귀속(MC8 라벨 + 분해 선택 항 + β 짝) · 진단 읽기 · 결론 이름 · ",
                            "같은 추첨(선택된 규칙의 Q50 × k' 사본 깊은 위기 β 짝 승리가 과반 미만 또는 미측정 = '같은 추첨 미확인 — P4 · A 후보 전 도훈 확인' — 철학 P1 C-063 · 선택은 바뀌지 않는다 · ",
                            "같은 추첨 판독 = Q50 칸이 있는 구성(E2)만 · E3 = 해당 없음(꼬리표 판정에서 뺀다 — 격리 교차 점검 v1 권고 3))"),
         round_verdict = sprintf(paste0("supported = 검증 규칙 ≥ 1 · partial = 한 구성 통과 또는 두 구성 통과지만 집중 제외 · falsified = 판정된 변형 칸 중 통과 0 · ",
                                        "untested = 판정된 변형 칸 0(⑮ 미달 · 미측정 = '미시험(꼬리 계기)' 포함) — '판정(판정 칸/변형 칸 %d · 판정어별 칸 수)'으로 적는다(P2R04 문장 그대로) · ",
                                        "진단 · 비교 기준 %d칸은 분모 밖"), K$n_variant, K$n_diag),
         r7_reading = paste0("R7 판독(기계 · 사전 고정 · 판정 아님 · P2R04 정의 그대로 — 장치 → 규칙): 판정된 규칙 = 두 구성(E2 · E3) 모두에서 tested 이고 ③(β 짝 깊은 위기)이 측정된",
                             "(status ok · 짝 ≥ 2 · 비율 유한) 규칙 중 S 증분(두 구성 평균)도 유한한 규칙 · 판정된 규칙 < 2 = 판독 불가(NA — 부분 판정 · 측정 실패 · 계기 실패로 예산을 소모하지 않는다) · ",
                             "≥ 2 = 라운드 '잡음 이내' = 검증 0 ∧ 판정된 규칙 중 두 구성에서 ③ 비율 > majority_share 인 규칙 0 ∧ 판정된 규칙의 S 증분(두 구성 평균) 최대 < tie_eps · ",
                             "판정된 규칙 수와 빠진 규칙 · 이유를 함께 싣는다 — P2 라운드로 계상하되 '원천 ① 첫 측정 · R7 판독 분리'로 적는다(DESIGN §0b 결정 7) · ",
                             "두 성분을 함께 싣는다(철학 Superfan P2 R-20261018-006 C-045): (a) 등록 판독 = 위 정의(P2R04 그대로 — 검증 0 ∧ 두 구성 ③ 과반 규칙 0 ∧ S 증분 최대 < tie_eps) ",
                             "(b) 방어 성분 = 검증 0 ∧ 판정된 규칙(두 구성 tested ∧ ③ 측정 — S 무관) 중 두 구성 ③ 과반 규칙 0 · 판정된 규칙 < 2 = 판독 불가 — ",
                             "방어 성분 잡음이면 P2 정지(paused) · 도훈 보고 대상(P2R03 · P2R04 방어 성분 연속 2 — 체계 §4) · ",
                             "(b) 기계 판정형(판단 Superfan T1 R-20261018-007): defense_noise = (판정된 규칙 ≥ 2) ∧ (검증 규칙 수 = 0) ∧ (두 구성 모두 ③ 비율 > majority_share 인 규칙 수 = 0) → ",
                             "'방어 성분 잡음' — P2R03 · P2R04 에 이어 연속 3 이면 P2 정지 · 도훈 보고 · 두 성분 판독에 시드 미결 꼬리표 수(③ 위기 · ④ 위기 · S — rules.record 시드 띠)를 함께 싣는다"),
         diagnostics = paste0("진단 칸 ", sum(plan$role == "diagnostic" & !(plan$control %in% c("lowvol_screen", "seed_pair"))), "(E2 — 중앙값만 ", dj("center_only"), " · 무정보 꼬리 순열 짝 ", dj("tail_perm"),
                              " · 변동성 순위 대응 짝 ", dj("vol_proxy"), " · 용량 짝 ", dj("capacity_pair"), ") + 비교 기준 칸 ", sum(plan$control %in% "lowvol_screen"), "(", dj("lowvol_screen"),
                              " — 저용량 변동성 스크린 = P2R04 E2 · E3 W2 사양 사본 · D03_RealVol 몫 12.5% · 판단 Superfan T2 C-20261018-038) + 재시드 짝 ",
                              sum(plan$component %in% "RX0S"), "(", paste(plan$code[plan$component %in% "RX0S"], collapse = " · "),
                              " — RX0 와 시드만 다른 평균 DNN · 시드 띠 원천 · 판단 Superfan T1 R-20261018-007 C-054 · ⑩ = 사양이 RX0 와 base_signal 만 다름 ∧ RX0 엔진과 다른 파일 · 다른 md5 의 핀 된 평균 엔진 1개 ∧ ",
                              "기저 적재 줄 ∧ months= — 분위 캐시 워밍 · 템플릿 대조 해당 없음 · .SEED_BASE 상수는 기록) — 시행 수 무가산 · DSR 표본 아님 · 선택 대상 아님 · ",
                              "판정 표 밖 · 2계층 모듈 풀 미등재 · 같은 구성 묶음으로 재고 묶음 지문과 대조(다르거나 없으면 그 칸만 미시험) · 칸 평가 = 변형 칸과 같은 계약(보는 창 패킷 · 행동 카드) · ",
                              "같은 판정 계산(역할 diagnostic — 보유가 RX0 와 같아도 계속 · 크기 × β · 국면 월 · Dimson · 같은 추첨 기록 생략 · 위기 보유 유동성 십분위는 Q50 · S1 · S2 만(C-069) · ",
                              "유동성 3분위 귀속은 S1 · S2 · Q50 · LV(C-076) · ⑮ 적용 진단 칸 W2 는 ⑮ 미달이면 미시험(계기)) · 읽기 = rules.diagnostics_reading"),
         diagnostics_reading = paste0("진단 읽기(사전 고정 · 판정 아님 · DESIGN §5.1 · '승리' = 그 칸이 자기 β 짝 사본을 깊은 위기에서 tol 넘게 이김(③ 위기별)): ",
                                      "중심 효과 — Vk 가 β 짝을 이긴 깊은 위기에서 Q50 도 이겼다 = 그 승리 = '중심 표적(중앙값) 효과' — 꼬리 방어로 세지 않는다 / ",
                                      "희석 — Vk 의 ① 개선 위기 중 Nk 도 개선한 위기 = '무작위 제외(희석) 몫' — ① 위기 수 겹침(등록 판독) · 깊은 위기 겹침은 따로 기록 / ",
                                      "변동성 누출 — Vk 가 β 짝을 이긴 깊은 위기에서 Sk 도 이겼다 = '변동성 대리 방어'(DNN 꼬리의 증분 없음) / ",
                                      "꼬리 고유 — Vk 승리 ∧ 그 위기에서 Sk · Nk · Q50 모두 미승 ∧ 꼬리 증분(아래 — 설계 §5.1 'D^σ t > 2' 를 철학 P1 R-20261018-008 C-065 가 D^σ ∧ D^w ∧ D^H 로 넓힘) = ",
                                      "'꼬리 학습 방어' — 이 이름은 이때만 쓴다(진단 칸 표에 그 위기가 없으면 판독 불가) / ",
                                      "용량(V2) — E2_V2 통과 ∧ E3_V2 통과 = 같은 처치가 두 구성에서 통과 · E2_V2 통과 ∧ W2 미달 ∧ E3_V2 미달 = 용량 의존 · W2 통과 ∧ E3_V2 미달 = 구성 의존 · ",
                                      "셋 다 미달 = 이 형태 미달(위에서 아래로 첫 일치 · 네 경우 밖 = '표 밖'으로 적는다) — 한 구성 단독 실패로 원천 ① 을 닫지 않는다 / ",
                                      "저용량 변동성 스크린 대비(LV · 판단 Superfan T2 C-20261018-038 · 비교 범위 = 판단 T1 R-20261018-007 C-058) — 같은 구성 Vk 마다 Vk 와 LV 를 ",
                                      "'LV 가 자기 β 짝을 이긴 깊은 위기'에서만 포착을 비교한다(한 정의 — 사전등록 comparison.reading 정의 A · 격리 교차 점검 v1 필수 2): ",
                                      "'원천 ① 증분 없음(저용량 변동성 스크린과 같음)' ⇔ LV β 짝 승리 깊은 위기 ≥ 1 ∧ 그 위기들에서 Vk 가 LV 를 tol(crisis_improve_min) 넘게 못 이김 ∧ ",
                                      "Vk 의 β 짝 승리 깊은 위기 ≥ 1 ∧ Vk 승리 위기 ⊆ LV 승리 위기 · Vk 가 LV 가 못 이긴 깊은 위기를 이기거나(⊄) LV 승리 위기에서 Vk 포착 < LV 포착 − tol 이면 'LV 대비 증분 있음' · ",
                                      "Vk β 짝 승리 깊은 위기 0 = 'LV 대비 판독 해당 없음' · LV 승리 위기 0 이거나 그 밖(그 위기에 변형 포착 결손 · LV 미시험)이면 'LV 대비 판독 미결' — ",
                                      "이름은 첫 일치로 붙는다(격리 교차 점검 v2 권고 3 · 코드 순서): (1) 미결(변형 칸 · LV 판정 계산 없음 · LV 위기 표 없음 · LV 승리 위기 0 · 변형 포착 결손) (2) 해당 없음(Vk 승리 0) ",
                                      "(3) 증분 있음(⊄ ∨ tol 넘게 이김) (4) 증분 없음 · ",
                                      "기록: Vk 의 β 짝 승리 깊은 위기 목록 · LV 밖 승리 위기 · S 증분(Vk − RX0) 대 (LV − RX0) / ",
                                      "꼬리 증분(계기 → 다음 행동 표 · 꼬리 고유 · 판단 T1 C-059 · 철학 P1 C-065) = 기록 D^σ ∧ D^w ∧ D^H 의 NW t 가 모두 > t_min(⑮ 와 같은 t — 새 숫자 아님 · 하나라도 미측정 = 판독 불가) · ",
                                      "중심 · 희석 · 변동성 · 꼬리 고유 · 용량 읽기는 진단 칸이 있는 E2 만 · ",
                                      "진단을 판정 조건으로 두지 않는 이유: 진단 칸은 위기별 승패를 읽는 도구이고 깊은 위기는 4건뿐 — 위기별 지도로 통과를 정하면 '한 번의 행운'의 조립판이 된다(철학 C-015 · 판단 T2 C-003 (b))"),
         conclusion_names = paste0("결론 이름(판정 아님 · DESIGN §10.2 ~ 10.4): '방어'는 ③ ∧ ④ ∧ ⑤(수준) ∧ ⑭ 일 때만 쓴다 · '선택(특성) 방어'는 크기 × β 짝까지 넘을 때만 쓴다 · ",
                                   "'꼬리 학습 방어'는 §5.1 꼬리 고유 조건일 때만 쓴다 · 같은 위기를 S 짝이 이겼으면 '변동성 대리 방어', Q50 이 이겼으면 '중심 표적 효과', N 짝이 이겼으면 '희석 몫'이다 · ",
                                   "'꼬리 회피 기계(방어만 · 복리 없음)' = 판정어(defense_but_strength_or_path) · 결론 꼬리표가 함께 쓰는 한 정의(격리 교차 점검 v1 필수 1 · 결론 범위 2 · 3 순서): ",
                                   "⑮ 통과(⑮ 미달 = 미시험(계기)이 먼저 — 원천 ① 의 반증이 아니다 · 판정 칸과 ⑮ 적용 진단 칸 W2 모두) ∧ ① ∧ ②(결정 — 미달이면 '결정 미달') ∧ ③ ∧ ④ ∧ ⑭ ∧ ",
                                   "⑤(수준 ∧ Δ — 미달이면 꼬리 회피 기계가 아니라 'β 비대칭 미달' · '방어' 이름은 첫머리대로 ⑤ 수준만 본다 — Δ 만 미달인 칸은 방어 이름이 남는다) 를 넘었으나 ",
                                   "⑥ · ⑦ · ⑨ · ⑫ · ⑬ 중 하나라도 못 넘은 미통과 칸 · ",
                                   "판정어 순서(첫 일치): 통과 → ⑮ 미달 = 미시험(계기) → β 대조 미측정 → 빠른 급락 미측정 → 노출 방어(①② 통과 ∧ ③ 미달) → ⑭ 미측정 → 크기 · 노출 방어(⑭ 미달) → ",
                                   "결정 미달(① · ② · ③ · ④ 중 미달) → β 비대칭 미달(미통과 칸에서 ⑤ 수준 또는 Δ 미달 — ⑥ 등이 함께 미달이어도 이 이름이 먼저) → 꼬리 회피 기계 · ",
                                   "통과 조건(13개 · 그 ⑤ = Δ)은 바뀌지 않는다 — ⑤ 수준만 미달이고 나머지가 모두 통과면 그 칸은 통과다(⑤ 수준은 통과 조건 밖 · 결론 이름 '노출(β) 방어(⑤ 수준 역행)') · ",
                                   "⑤ Δ 만 미달 = 판정어 β 비대칭 미달 ∧ 방어 이름 유지(승계 이름 규칙 — 격리 교차 점검 v2 필수 2) · ",
                                   "(§10.2 에 덧붙임 · 판단 Superfan T2 C-20261018-038 · 범위 = 판단 T1 C-058 · 한 정의 = 격리 교차 점검 v1 필수 2) LV 이름 = rules.diagnostics_reading — ",
                                   "첫 일치(격리 교차 점검 v2 권고 3 · 코드 순서): (1) 변형 칸 · LV 판정 계산 없음 · LV 위기 표 없음 · LV β 짝 승리 깊은 위기 0 · 그 위기에 변형 포착 결손 = 'LV 대비 판독 미결' ",
                                   "(2) Vk β 짝 승리 깊은 위기 0 = 'LV 대비 판독 해당 없음' (3) Vk 승리 위기 ⊄ LV 승리 위기 ∨ LV 승리 위기에서 Vk 포착 < LV 포착 − tol = 'LV 대비 증분 있음' ",
                                   "(4) 그 밖(Vk 승리 ≥ 1 ∧ ⊆ LV 승리 위기 ∧ tol 안) = '원천 ① 증분 없음(저용량 변동성 스크린과 같음)' · ",
                                   "셀 로그 꼬리표(격리 교차 점검 v2 필수 1): 그 V 칸의 셀 로그 예측표 대조가 '대조 불가'면 '⑮ 예측표 셀 로그 대조 불가' 꼬리표(⑮ 판정 유지) · ",
                                   "시드 꼬리표(판단 T1 C-054 · 판정 불변): Vk 의 위기별 β 짝 결정(③ · ④)에서 |변형 포착 − 사본 포착| < 그 위기의 시드 띠 = '시드 미결' · |S 증분| < S 띠 = 'S 시드 미결' · ",
                                   "재시드 칸이 없거나 실패 = '시드 띠 미측정'(실패 아님 · DESIGN §10.8 '단일 시드 · 잡음 띠 미측정' 꼬리표와 같은 뜻) · ",
                                   "'꼬리 학습 방어' = 방어 이름 성립 ∧ 꼬리 증분(D^σ ∧ D^w ∧ D^H t > t_min) ∧ 위기별 조건(Vk 승 ∧ Sk · Nk · Q50 미승 — 철학 P1 C-065) · ",
                                   "③ 미통과 칸의 Sharpe 상승 = '평시 변동성 축소'(철학 P1 C-070) · 선택 꼬리표: 선택된 규칙의 같은 추첨 판독(Q50 × k' 사본) 깊은 위기 β 짝 승리가 과반 미만(또는 미측정)이면 ",
                                   "'같은 추첨 미확인 — P4 · A 후보 전 도훈 확인'(철학 P1 C-063 · 판정 불변 · 같은 추첨 판독 = Q50 칸이 있는 구성(E2)만 · E3 = 해당 없음 — 꼬리표 판정에서 뺀다) · ",
                                   "수평 꼬리표(결론 범위 5 · 격리 교차 점검 v1 권고 5 · 기존 기록 · 새 숫자 없음): 거부 집합의 다음 보유월 하위 분위 적중(record 전이 veto.bottom) ≤ 기저(base_rate = 1/분위 수)이면 ",
                                   "V 칸 결론에 '수평 불일치' · 전이 기록이 없으면 '수평 판독 미측정' · 결론 문장에 함께(결론 범위 11 · 14): 깊은 위기 보유 유동성 십분위 V · S(짝) · Q50 · RX0 나란히 · ",
                                   "보유 이름 겹침 RX0 대비 · Q50 대비(Q50 칸이 없는 구성 = NA) · ",
                                   "유동성 꼬리표(철학 Superfan P4 C-20261018-076 · 판정 불변): 꼬리 방어로 읽는 칸(판정 칸 V1 · V2 — 결론 이름이 붙는 칸)의 위기 개선(구간 손익 − 같은 구성 RX0 구간 손익 > 0)에서 ",
                                   "저 분위 기여 차가 그 개선의 과반(> majority_share)인 위기가 하나라도 있으면 '저유동 귀속(… n/m 개선 위기)' · 귀속을 계산 못 하면(산출물 결손 · 재구성 대조 불일치 등) ",
                                   "'유동성 귀속 미측정'을 의무로 붙인다(실패 아님 · 일부 위기만이면 그 수와 함께) · ",
                                   "미측정(③ · ④ · ⑤ 수준 · ⑭ · 크기 × β · 진단 칸 미시험 · LV 위기 표 결손)은 기전 이름으로 접지 않고 '보류'로 둔다"),
         instrument_action = paste0("계기 → 다음 행동(사전 고정 처분 안내 · 판정 아님 · 판단 Superfan T1 R-20261018-007 · 위에서 아래로 첫 일치 — 맞는 줄은 모두 기록 · evaluation_visible.json instrument_action): ",
                                    "A ⑮ 미달 → '이 학습 설정은 종목 왼꼬리를 배우지 못함(계기 실패 · 원천 ① 반증 아님)' 기록 · P2 정지 판독 / B ⑮ 통과 ∧ D^σ · D^w · D^H 증분 없음 → '꼬리 = 변동성 대리' · LV 대비 기록 · P2 정지 판독 / ",
                                    "C ⑮ 통과 ∧ 꼬리 증분 있음 ∧ ③ 미달 → 다음 장치 = 상태 조건부 꼬리 거부(V3 · 위기 진행 중 as-of 상태) · P2 가 멈추면 P4 부품 시험으로 / ",
                                    "D ③ 통과 → P3 의견서 · 후보 경로 — 꼬리 증분 = D^σ ∧ D^w ∧ D^H 의 NW t 모두 > t_min · ③ 통과 = 판정 계산이 된 변형 칸 중 ③ 통과 칸 ≥ 1 · ",
                                    "⑮ 미측정(계기 미측정) = 해당 줄 없음 · D^σ · D^w · D^H 중 미측정 = B · C 판독 불가"),
         expectations_appendix_a = paste0("기대(사전 고정 · 채점 대상 · 판정 아님 · DESIGN §6 + 부록 A · 철학 P1 R-20261018-008 C-065): E2 의 V2 상승 β > S2 상승 β ∧ ⑥ 강세 구간 비율 V2 ≥ S2 ",
                                          "(꼬리가 β 비대칭을 담으면 V2 는 변동성 순위 짝보다 상승 β 를 덜 잃는다) — evaluation_visible.json appendix_a 에 성립 여부를 기록"),
         pause_report = paste0("P2 정지 보고 4요소(철학 Superfan P1 R-20261018-008 C-064 · evaluation_visible.json pause_report 재료 블록 · 판정 아님): (1) 레버 × 위기 유형 승패 지도(이 라운드 칸 기준 · ",
                               "유형 = crisis_type_classify 경계 분리 판 + 상태 미전환 · 같은 줄에 ⑤ Δ · ⑭ — C-067) (2) 철학 머리 문장 성적표(위기 하락 포착 · 강세 참여 ≥ uc_floor 0.55 · 꾸준함 = 롤링 통과)와 ",
                               "미측정 형태 목록(주간 집행 = 셀 엔진 주간 신호 미구현 · 위기 진행 중 as-of 결합 = 상관 상태로는 반증(_design_notes/crisis_type_asof — 진행 중 ρ̄20 백분위가 두 묶음을 못 가름) · ",
                               "시작 시점 as-of 도 못 가름(crisis_type_classify) · 다른 기저 엔진 = 재료 큐) (3) P4 함의 1줄 자리 (4) 철학 P4 첨부 자리 · ",
                               "재료: 보유 겹침 V–RX0 · V–Q50 · Q50–RX0 · RX0–RX0S(R7 판독에도 — C-068) · 위기 보유 유동성 십분위 V · S · Q50 · RX0 나란히(C-069) · ",
                               "유동성 구간별 위기 손익 귀속 3분위 칸 × 위기 표(V1 · V2 · S1 · S2 · Q50 · RX0 · LV 나란히) + 판정 칸 저 분위 개선 몫(철학 P4 C-20261018-076)"),
         conclusion_scope = paste0("결론 범위(DESIGN §10): 이 결과는 2002.06975 DNN5 · 31 특징 · 순위 재척도 5일 표적의 조건부 분위(τ 0.1 · 0.5 · 0.9 · 합성 pinball · 단일 시드) × 두 소비 규칙(V1 거부 · V2 q10 순위) × ",
                                   "같은 DNN 기저의 두 구성 · 이 축 · 월간 집행의 효과다 — 분포 표적 학습 일반으로 넓히지 않는다 · 반증이면 교훈 카드 · hypothesis_index 에 '원천 ① 첫 측정 — 이 형태 반증'으로 적는다(C-009 의 금지 목록화 방지) · ",
                                   "5일 분포 예측을 월간 보유로 소비한다(엔진 changed(3) 승계) — 거부 집합의 다음 보유월 하위 분위 적중 ≤ 기저(1/분위 수)이면 결론에 '수평 불일치'를 적는다(rules.conclusion_names 수평 꼬리표) · ",
                                   "결합 금지: P2R03 D5 · D7 · P2R04 H2 · W2 와의 위기별 승패 합집합으로 결합 · 선택 규칙을 짜지 않는다 — 위기 유형은 사후로만 보인다(crisis_type_classify · crisis_type_asof — ",
                                   "시작 시점 · 진행 중 as-of 모두 못 가름) → 결합 기전 없음 · 결합은 별도 사전등록 · 결합 칸 자체 판정 · P4/A/BOOK 전 도훈 확인(Q 10-18 · 판단 Superfan T2 C-20261018-038 · 격리 교차 점검 v1 필수 3) · ",
                                   "기준점 둘(엔진 대비 · 시장 대비)을 함께 적는다 — 순위 표적은 등가중 횡단면 대비 상대 꼬리라서 시장(KOSPI200 · 시총가중) 대비 방어와 같지 않다 · ",
                                   "시드 띠 = 같은 구성 재시드 칸 2(RX0S 대 RX0 · 결론 범위 8) — 결정이 띠 안이면 '시드 미결' 꼬리표(rules.conclusion_names) · 재시드 칸이 없거나 실패면 '시드 띠 미측정' · ",
                                   "분위 모형 자체는 단일 시드(V 칸 · 격리 교차 점검 v1 필수 3) · 결론 문장에 희석 몫(①) · 위기 보유 유동성 십분위 V · S · Q50 · RX0 나란히 · 크기 십분위(변형 대 RX0) · ",
                                   "보유 겹침(RX0 대비 · Q50 대비)을 함께 적는다(DESIGN §0b 6 · 21 · C-068 · C-069)"),
         failure_semantics = paste0(P4$failure_semantics, " / (P2R05 추가) ⑮ 꼬리 계기 미달 · 미측정(예측표 없음 · 표적 정의 대조 실패 · 라벨 재도출 실패 · NW t 비유한 · 설정 해석 불가) = ",
                                    "변형 칸 4개 '미시험(꼬리 계기)'(반증 아님 · 판정어 untested_tail_instrument · ⑮ 적용 진단 칸 W2 도 같은 판정어) / 측정에 묶인 워밍 센티널에 예측표 경로 · md5 없음 = '예측표 미묶임' = ⑮ 미측정(위와 같은 미시험) / ",
                                    "묶인 예측표 없음 · md5 ≠ 센티널 · 셀 로그 '[DT qpred] path=' 줄의 경로 · md5 ≠ 묶인 판(격리 점검 v2 필수 1) · 판독 · 형식 실패 = 평가 중단(사유 기록 results/evaluation_halt.json · ",
                                    "센티널 status=eval_halted) / ⑩ 엔진 핀 · 사양 구성 키 · 기저 적재 줄 · 워밍 센티널 · 템플릿 차분 대조 · months= · 무처치 불일치 = 그 칸 미시험 / V1 전달량(≠ Q50) 미측정 = 그 V1 칸 미시험 / ",
                                    "진단 읽기 · 기록 계산 실패 = 그 기록만 미측정 꼬리표 · 위기 유형 분류 파일 없음 = '미분류'(실패 아님) · 분류 md5 ≠ 사전등록 design_inputs 핀 = '분류 판본 다름' 꼬리표(평가 중단 아님) · ",
                                    "유동성 3분위 귀속 계산 실패(산출물 · Ret 열 · 위생 멤버십 결손 · 집행 규약 판독 불가) · 재구성 대조 불일치 = '유동성 귀속 미측정' 꼬리표(의무 · 실패 아님 · 평가 중단 아님) · ",
                                    "분위 엔진 칸 셀 로그 예측표 줄 없음(기저 캐시 적중) = 기록 · 연쇄 대조를 못 하면 '⑮ 예측표 셀 로그 대조 불가' 꼬리표(실패 아님 · ⑮ 판정 유지)"),
         files = paste0("칸 평가 = results/<code>/visible/{diagnosis_packet.json, eval_visible.json} · results/<code>/full/{behavior_card.json, eval_full.json, NO_VISIBLE_REVIEW.txt} · ",
                        "전기간 산출이 들어가는 짝 평가 사본(results/<code>/original · common_* · rx0_beta_scaled · artifacts · rx0_artifacts)에 NO_VISIBLE_REVIEW.txt 표식(보는 창 = visible* 하위 폴더만) · ",
                        "종합 = results/evaluation_visible.json(schema p2r05_evaluation_visible_v1 · 보는 창 리뷰어 열람 가능 · τ_D 이후 날짜 가림 + 쓰기 전 전수 검사) · results/evaluation_full.json(사람 쪽 전용) · ",
                        "평가 센티널 = 04_Research/programs/_lib/night_state/p2r05_evaluated.done(P2R04 형식 'status=… rc=… at=… ok=…/…' · 종합 판정 실행만 쓴다) · 평가 중단 사유 = results/evaluation_halt.json")),
    R[c("test_window")],
    list(record = paste0(P4$record, " / (P2R05 · DESIGN §5.2 추가 — 판정 입력 아님) 꼬리 계기 · 기량: R¹(0.1 · 0.5 · 0.9)의 보는 창 월별 요약 · 적중 P(y ≤ q̂10) · P(y ≤ q̂90)(보정) · ",
                         "D^σ_d = mean_i[ρ_0.1(y − q̃10_σ) − ρ_0.1(y − q̂10)] 와 NW t(q̃10_σ = q̂50 − s_σ — DNN 꼬리 순서가 변동성 순서보다 10% 분위를 더 잘 맞히는가를 같은 주변분포 짝으로) · ",
                         "D^perm_d(건전성 · q̂50 − s_perm) · σ 10분위 층화 R¹(0.1) · D^w_d = mean_i[ρ_0.1(y − q̃10_w) − ρ_0.1(y − q̂10)] 와 NW(3) t(q̃10_w = q̂50 − (q̂90 − q̂50) — 같은 모델의 대칭 폭 짝 · ",
                         "양수 = 왼꼬리가 대칭 폭 이상의 비대칭 정보 · 판단 T1 C-059 · GPU 0) · D^H_d = mean_i[ρ_0.1(y − q̃10_H) − ρ_0.1(y − q̂10)] 와 NW(3) t(q̃10_H = q̂50 − s_hist — ",
                         "각 종목 직전 252거래일 자기 5일 순위 수익 하방 폭(중앙값 − 10% 분위) 순서로 s 재배정 · 예측표 선택 열 s_hist · 없으면 미측정 · 철학 P1 R-20261018-008 C-065) / ",
                         "같은 추첨 판독(철학 P1 C-063 · 같은 구성 Q50 칸이 있을 때만): k' = β(변형)/β(Q50)(RX0 β 짝과 같은 계산 경로) · Q50 × k' 현금 사본으로 깊은 위기 · 빠른 급락 β 짝 승패 · ",
                         "⑤ Δ · ⑥ 강세 구간 · ⑦ 증분 α 를 V − Q50 로도 · V–Q50 보유 겹침 / ",
                         "전이 · 귀속: 거부 집합 · V2 상위 25 의 다음 보유월 횡단면 하위 · 상위 5분위 적중률(월 수평 전이 — 분산만인지 왼꼬리인지) · ",
                         "깊은 위기 달의 적중률(꼬리 = 위기 꼬리인가) · 거부 집합의 크기 · 유동성 분위, σ 거부 집합과의 겹침(Jaccard) · Q50 상위 25 중 거부된 몫(V1 전달량) · ",
                         "E2 변형 보유와 예측표로 재현한 규칙 상위 25 의 일치율(구성 재현 · 불일치는 유동성 · 동률로 사유 분해) · 예측 비대칭 (q̂90 + q̂10 − 2q̂50) / (q̂90 − q̂10)(Kelley 십분위 왜도)의 ",
                         "보유 평균 V 대 RX0(복권형 쏠림 감시) · ⑩(d) 재배열 전 교차율 · q̂ 횡단면 표준편차 · V1 신호 폭 / 위기 유형별 β 짝 승패(DESIGN §0b 10 · 판단 Superfan T2 C-20261018-038 · Q 10-18): ",
                         "분류 파일 _design_notes/crisis_type_classify.json(type ∈ systemic · dispersed · rho_W 가 문턱 — 같은 파일 rule 의 'peak >= <날짜>' 위기들의 rho_W 중앙값을 파일 값으로 재계산 — 과 ",
                         "차 < 1e-9 인 위기 = '경계')이 있으면 칸마다 모든 짝 위기의 β 짝 승패를 유형별로 집계 — 경계 포함 판(쓰인 유형대로) · 경계 분리 판 두 판(깊은 위기 부분도 따로 · ",
                         "같은 줄에 ⑤ Δ · ⑭ 분해 선택 항 개선 — 철학 P1 C-067) · 없으면 '미분류'(실패 아님) · 위기 보유 유동성 십분위 = 판정 칸 + Q50 · S1 · S2(V · S · Q50 · RX0 나란히 — C-069) · ",
                         "파일 md5 를 사전등록 design_inputs 핀과 대조(다르면 '분류 판본 다름' 꼬리표 · 평가 중단 아님) · 시작 시점 분류 기록(_design_notes/onset_state_classify.json table from_top / not_from_top — ",
                         "결론 이름 아님 · 격리 교차 점검 v1 권고 1(b)) · 깊은 위기도 같은 방식으로 따로 · '상태 미전환 최대 하락 위기'(출처 = _design_notes/state_turn_classify.md — final_selection_rule ",
                         "state_unturned_max_drop_crises 근거와 같은 파일)의 β 짝 승패 = record state_unturned_max_drop · 판정 · 선택 · 결합 규칙에 쓰지 않는다 · ",
                         "RX0 동일성 = P2R04 같은 구성 RX0 대비(보유 · 수익 같음 · 다른 달 수 — 데이터 판본이 바뀌었으면 '다름'을 기록만) · ",
                         "판정 여유(철학 Superfan P2 R-20261018-006 N-⑤ — 새 문턱 없음 · 코드는 '경계'를 판정하지 않고 여유 숫자만 남긴다 · 양수 = 충족): ③ 위기별 (β 짝 사본 포착 − tol) − 변형 포착 · ",
                         "④ 같은 식(빠른 급락) · ⑭ 깊은 위기별 분해 차(변형 − RX0 선택 항 · 문턱 0) · ⑤ −Δ(RX0 하락/상승 β 비 − 변형 비) · ⑮ t − t_min · 비율 항목은 비율 − majority_share 도 함께 · ",
                         "시드 띠(판단 T1 R-20261018-007 C-054 · 기록): 같은 구성 재시드 칸(RX0S) 대 RX0 의 위기마다 |포착(RX0S) − 포착(RX0)| · S 띠 = |S(RX0S) − S(RX0)| · 변형 칸 위기별 · S 시드 미결 꼬리표(rules.conclusion_names) · ",
                         "LV ↔ P2R04 같은 구성 W2 보유 · 수익 동일성(RX0 동일성과 같은 식 · 같은 배치면 동일 · 판본이 바뀌었으면 다름 · 판단 T1 C-058) · ",
                         "Dimson β 짝 판(N-⑥ · 기록 · 판정 아님 · 변형 칸만): 변형 · RX0 의 Dimson β(보는 창 일수익 ret_net 을 같은 산출물 벤치 일수익의 lag −1 · 0 · +1 에 회귀한 계수의 합 — ",
                         "Dimson 1979 JFE 7(2) 'Risk measurement when shares are subject to infrequent trading')로 k_D = β_D(변형) / β_D(RX0) · k_D < 1 이면 RX0 × k_D 현금 사본(같은 계약 dp_build · ",
                         "RX0 수익의 스칼라 축척 — 새 측정 없음) · k_D ≥ 1 이면 사본 = RX0 · 깊은 위기 · 빠른 급락 β 짝 승패를 다시 기록(k 와 k_D 나란히 — 덜 유동적인 보유는 동시 β 가 낮게 잡혀 k 가 작아지는 경로의 감시) · ",
                         "유동성 구간별 위기 손익 귀속(철학 Superfan P4 C-20261018-076 · 기록 · 판정 · 선택에 쓰지 않는다 — 소형주 · 저유동 착시 감시): 구성마다 RX0 보는 창 패킷의 깊은 위기 · 빠른 급락 ",
                         "(고점, 저점] 마다 칸 V1 · V2 · S1 · S2 · Q50 · RX0 · LV(구성에 있는 칸) 나란히 — 보유 종목을 위기 고점일 t−1 20일 평균 거래대금(adv20_l1 · 고점일 당일 거래대금 제외 · C10)으로 ",
                         "그날 위생 멤버 유니버스(HYG ∧ adv20_l1 > 0) 3분위(저 · 중 · 고 · 경계 = 유니버스 1/3 · 2/3 분위)에 놓고 구간 포트폴리오 손익(측정 산출물 04_holdings 비중 → 계약 일별 시작 비중 ",
                         "tilt_attribution .ta_daily_weights(집행 규약 · buy-and-hold 드리프트) × 보는 창 RAWDATA 일수익의 구간 산술합 — 진단 패킷 위기 귀속과 같은 합산)을 분위별 기여로 분해 · ",
                         "단정: 분위 기여 합 = 구간 재구성 손익 · 재구성 손익 = 계약 03 ret_gross 의 같은 구간 합(|차| < 1e-10 — 진단 패킷 벤치 항등식 문턱 재사용 · 불일치 위기 = 미측정) · ",
                         "판정 칸 저 분위 개선 몫 = (저 분위 기여(칸) − 저 분위 기여(RX0)) / (구간 손익(칸) − 구간 손익(RX0)) · 개선 > 0 위기만 · ",
                         "이 기록의 보는 창 판은 τ_D 이후 행을 읽지 않고 만든다(RAWDATA · 예측표를 τ_D 에서 먼저 자른다) — 사람 쪽 판(시험 창 포함) = evaluation_full.json")),
    R[c("state_unturned")],
    list(leave_behind = paste0("검증 0 이어도 남길 것(DESIGN §10): 규칙 × 위기 실패 지도(β 짝 여유 · 크기 × β 짝 · Q50 · N · S · W2 · LV 읽기) · 꼬리 계기 · D^σ · 층화 기량 · 월 수평 전이 · 깊은 위기 달 적중 · ",
                               "거부 집합의 크기 · 유동성 · σ 겹침 · 예측 비대칭 · 교차율 · 분위 예측표(내용 주소 · 다음 라운드 재사용) — 다음 탐침 후보: 절대 수익 표적 · 하락 주 조건부 표적 · ",
                               "주간 집행(셀 엔진 주간 신호 구현 뒤) · 분위 정보를 P3 구성(꼬리 위험 최적화)의 입력으로")))
}
