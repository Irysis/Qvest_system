## WT-D20260822_004 · P9 — ast_spec_gate 정합 수리 (형식 재포장, 승계 자구 보존)
##  ①falsification 을 게이트 스키마(객체배열 + field_ref, field_dictionary 내)로 재포장
##    — 승계 원문은 hypothesis.falsification_inherited_verbatim 에 그대로 보존 (Charter par.8)
##  ②verdict 필드 = schema ast_v1.1 조건부 enum(designed|economic_void|blocked_by_capability) 준수.
##    라운드 판정은 별도 필드 round_verdict 로 분리 — 두 개념을 한 필드에 넣지 않는다.
suppressPackageStartupMessages({library(jsonlite)})
source("02_Infrastructure/config.R")
MB <- "qepm/mailbox/worktask/WT-D20260822_004"; OUT <- "stage_artifacts/WT-D20260822_004"
f <- file.path(MB, "alpha_package.json")
d <- fromJSON(f, simplifyVector = FALSE)

d$hypothesis$falsification <- list(
  list(id = "R1a_transport",
       field_ref = list("FDB-B6_fdb_daily_store", "FDB-B7_ic_history_monthly"),
       observable = "C0 top-25 편입 종목 중 solo-advocate 편입 비율 (advocate = argmax_k z_ik, leave-advocate-out 재랭킹 시 top-25 밖으로 밀리는 종목). 성과 무관.",
       threshold = "월별 중앙 >= 0.20 미달 시 기전 미수송 STOP",
       measured = 0.64, fired = FALSE,
       verdict = "수송 확인 — 25 slot 중 중앙 16 개가 solo-advocate 편입"),
  list(id = "R1b_transfer_negative_concentration",
       field_ref = list("FDB-B6_fdb_daily_store", "A1_RAWDATA_OHLCVS_daily"),
       observable = "solo-advocate 종목의 advocate 팩터 standalone canonical PORT_t 중앙값 vs 선별 풀 전체(103종) 중앙값",
       threshold = "solo 중앙 < 풀 중앙",
       measured = list(solo = -0.2797, pool = -0.3476, neg_share_solo = 0.720, neg_share_consensus = 0.751),
       fired = TRUE,
       verdict = "★미성립 — solo advocate 가 오히려 덜 전이-음성. FQ-116 귀속 미수송."),
  list(id = "R2_mediator_movement",
       field_ref = list("FDB-B6_fdb_daily_store"),
       observable = "처치 arm 의 월별 solo-advocate 편입 비율 (C0 대비 비)",
       threshold = "처치 <= 0.8 x C0",
       measured = list(C1 = 0.688, C2 = 0.938, C3 = 1.312), fired = FALSE,
       verdict = "C1 통과 · C2 미통과(NO_MEDIATOR_MOVEMENT) · C3 증폭(설계 의도)"),
  list(id = "R3_linkage",
       field_ref = list("A1_RAWDATA_OHLCVS_daily", "FDB-B2_registry_rawdata_price_daily"),
       observable = "C0 에서 solo-advocate 편입 종목의 월평균 fwd_ret_1m 마이너스 consensus 편입 종목 월평균 (NW lag-3 t)",
       threshold = "t <= -1.5 (FQ-116 대응 실측 -2.01)",
       measured = list(annual_pct = 1.483, t_nw3 = 0.2461, n_months = 216), fired = TRUE,
       verdict = "★연결 절단 — solo 가 오히려 연 +1.48%p 더 벌었다(무차별). 손실 원천을 이산 top-N 절단 마디(FQ-059)로 귀속 이전."),
  list(id = "R5_kurtosis_heterogeneity",
       field_ref = list("FDB-B6_fdb_daily_store"),
       observable = "월별 선별 K=5 팩터의 횡단면 z 초과첨도 IQR",
       threshold = "중앙 >= 1.0",
       measured = list(iqr_median = 6.9357, min_exkurt_median = -0.210, max_exkurt_median = 21.163),
       fired = FALSE,
       verdict = "friction 3 전제 성립 — 꼬리 두께 이질 대규모 실재(단 손실로 연결되지 않음)"),
  list(id = "R_regime_boundary_diagnostic",
       field_ref = list("E3_macro_regime_monthly", "E5_msm_crisis_prob"),
       observable = "승계 regime_scope 의 국면 경계(고분산 tercile · crisis) 조건부 처치 효과",
       threshold = "본 라운드 미측정 — primary 가 powered null 이라 국면 분해의 검정력이 없다",
       measured = NULL, fired = NA,
       verdict = "미측정 명시 (침묵 아님). R_SUB 2015-07 달력 분할은 era 교락으로 국면 주장 미승격.")
)
d$hypothesis$falsification_format_note <- "★게이트 스키마(객체배열 + field_dictionary 내 field_ref)로 형식만 재포장했다. 승계 원문 서술은 hypothesis.falsification_inherited_verbatim 에 자구 그대로 보존 — 내용 재작성 아님(Charter par.8 No Silent Override)."

## verdict 분리 — schema ast_v1.1 조건부 enum 준수
d$verdict <- "designed"
d$verdict_note <- "★AST v1.1 설계 판정 필드 (schema 조건부 enum: designed|economic_void|blocked_by_capability). 팩터 식이 연산자 집합 안에서 표현됐고 escape 계약이 충족됐다는 뜻이다. **라운드 성과 판정이 아니다** — 그것은 round_verdict 필드."
d$round_verdict <- "NON_ML_COMBINATION_POWERED_NULL"
d$round_verdict_detail <- "비-ML 결합 규칙 2종(C1 rank 평균 · C2 winsor-z 평균)이 C0 대비 IC→PORT_t 전이를 개선하지 못했다 — 둘 다 POWERED_NULL_NO_MATERIAL_EFFECT (CI95 상단 +3.01 / +1.49 %p/yr 로 MATERIAL 8.2228 배제). 음성 대조 C3(max-z)는 사전등록 R4 예측대로 유의 악화(t -2.08). 기전 귀속: M1 slot 잠식은 실재(R1a 16/25 slot)하나 잠식→손실 링크가 본 풀에 부재(R1b 미수송 + R3 부호 역전 t +0.25). ★증거력 비대칭 — C1 은 매월 9/25 종목을 교체하고도 무반응(강한 null), C2 는 3/25 교체에 그쳐(clip 이 셀의 3.4%만 건드림) 약한 null."
d$ml_reentry_judgment <- list(
  question = "비-ML 로 개선되지 않았다 — ML 결합기 재진입이 필요한가",
  constitutional_step = "헌법 재진입 순서 ① (비-ML 사전등록 비교) 충족 ⇒ 형식상 ② ML 결합기 자격 발생",
  recommendation = "★자격은 생겼으나 결합 마디에서의 ML 재진입은 권고하지 않는다 — 우선순위는 팩터 **선택** 마디다.",
  evidence = list(
    node_headroom = "ORACLE_K PORT_t 4.647 (paired +13.69%p/yr, t 4.29) — 매월 K=5 중 옳은 하나를 고르면 벽 2.95 를 넘는다. 즉 정보는 '어느 팩터를 언제 쓰느냐' 에 있다.",
    combination_form_is_inert = "그 정보는 결합 **함수형** 으로는 회수되지 않는다 — C1 이 포트폴리오의 36%를 바꾸고도 -0.41%p/yr(t -0.24). 마디가 죽은 게 아니라(C3 가 t -2.08 로 반응) 구성적 방향의 여유가 함수형에 없다.",
    performance_based_route_already_negative = "그 정보를 trailing 성과로 예측하는 경로는 두 번 측정 negative — RAMP R10 W-factor(paired -0.16, factor momentum timing NULL) + FQ-121(IS 최강 V01 +2.634 → OOS -0.389, 자격 반감기 < 운용 주기).",
    conclusion = "trailing-성과 피처 기반 ML 결합기는 이미 두 번 죽은 경로의 재탕이 된다. 미측정 축은 **상태 조건부**(국면·크라우딩·횡단면 분산 tercile) 팩터 선택이며 이는 v8.4 Lane D 와 직결된다 — next_probe NP2."),
  forbidden_here = "본 라운드에서 ML 결합기 미사용 (헌법 재진입 순서 ① 준수). 향후 ② 진입 시 사전등록·비-sweep 의무."
)
write_json(d, f, pretty = TRUE, auto_unbox = TRUE, digits = 8, na = "null")
cat("[patched]", f, "\n")

v <- file.path(OUT, "alpha_validation.json"); dv <- fromJSON(v, simplifyVector = FALSE)
dv$round_verdict <- d$round_verdict; dv$ml_reentry_judgment <- d$ml_reentry_judgment
dv$falsification_format_note <- d$hypothesis$falsification_format_note
write_json(dv, v, pretty = TRUE, auto_unbox = TRUE, digits = 8, na = "null")
cat("[patched]", v, "\nOK\n")
