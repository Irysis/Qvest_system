setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
Sys.setenv(QM_ROOT = "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source("02_Infrastructure/axiom/lcode_emit.R")
lesson <- paste0(
"[weighted_screen 실측, 현행 배포 book 기준] WT-D20260802_019 FQ-118: 실현-하락 nowcast 대체 라벨 — 트레일링 낙폭 상태(벤치 TR지수가 12M 고점 대비 -10% 이하 @ 홀딩 시작 직전 거래일)를 g=0.40 이진 노출로 소비(오라클 동일 스케줄, 파라미터 KR 비튜닝 외생 상수, n_trials=1 no-sweep). 판정 = settled negative — ★사전등록 순서대로 라벨 품질 사전 검정에서 성과 전 결론: BM<0 recall 0.351 <= base 0.413 (fisher p=0.795). ",
"★핵심 신규 지식(구조 판정): 트레일링 가격-상태 라벨 5변형 전부 KR 월간 실현-하락 판별 비유의 — DD10 0.351(p=0.795)/DD5 0.532(p=0.259, 유일 recall>base이나 precision 0.381<base=농축 없음)/DD15 0.180(p=0.754)/실현변동성 상위분위 0.081(p=0.465)/단월음수 0.441(p=0.616). 월간 granularity에서 KR BM<0은 트레일링 가격 상태와 사실상 독립 — WT-017 오라클 상금(+2.14%/yr, MDD 14.1pp)은 nowcast 축으로 접근 불가, 진짜 예측이 필요. ",
"★유해 규모의 비례 법칙(참고 성과, WT-017 대비): paired NW3 t=-3.77(-7.35%/yr)·dIR -0.439·EW기저 -4.17·비용반영 -3.80·NOWCAST_ONLY -3.53. MSM 라벨(ON 28개월, -2.38%/yr)의 3.3배 발화(ON 92개월)에 순손실도 ~3배 — 무판별 라벨의 감beta 유해는 발화 월수에 비례(BM>0월 비용 -4.87 지배, BM<0월 기계 이득 +1.81 불변 구조). ",
"★nowcast 구조 병리 실측(사전등록 honest posterior 그대로 실현): ON 92개월의 실현 벤치 연율 +10.4%, frac_bm_neg 0.424=base — 낙폭 상태는 하락 '중'만이 아니라 반등/회복 구간(2009 반등, 2020-04~06, 2024-10~2025-05, 2026-05 멜트업 +29.0%)에 대량 발화(고점 -10% 복귀까지 미해제). 짝 실기: 2026-04 폭락월 자체는 OFF(dd -0.011) — 초입 실기 + 반등 오발화가 nowcast의 쌍둥이 병리. AX-001 조건부: ON월 active book +25.4% -> cand +3.9%(반등 참여 차단), MDD 개선 1.1pp뿐(오라클 14.1pp). ",
"PIT: cutoff=홀딩 시작 직전 거래일(간격 median 1일 [1,4])·252d 창 종점=cutoff 직접 확인·assert_overlay_pit HARD PASS + 위반 주입(홀딩월말 cutoff) stop 발화 실증 + lag 스트레스 -3.92(leak 방향이 더 나쁨=누출 지문 없음) + strict A/B 인플레 0. 프레임 parity: BARE/BOOK/ORACLE/BOOK_EW가 WT-017과 자리수까지 일치(6.40/6.18/7.87/5.33) — 승계 프레임 정확 재현. ",
"방법론: WT-017 사전등록 프레임 완전 승계(carrier 269m production-parity + e_book=layer5 m4_weight_lag x beta_R05_V5 + weighted_screen_bt exposure_dt + paired NW3 판별 + 오라클 회수율 분모). 회수율 mandate: return축 -343%(상금 3.4배 파괴)·MDD축 +7.3% — 0% 아래 정직 보고. 회전 10.3/yr 상한 내, overlay 회전 증분 0.42/yr. ",
"next_probe: NP-1(FQ-117 강화) — 라벨 엔진 개보수의 관문 기준선 확립: 비가격 원천(FRED 크레딧/환율 스트레스) 포함 어떤 라벨이든 recall>base AND fisher p<0.05를 먼저 통과해야 소비 측정 자격(본 라운드 5-라벨 비유의가 비교 기준선); NP-2(granularity 축) — 하락 지속성이 일간/주간 스케일에 있고 월간 리밸이 소거하는지 벤치 일간 시계열 저비용 사전진단(DD_STATE -> 익일/익주 BM<0 농축 검정), 유의 시 월내 노출 조정 lane(구현 cadence 변경=도훈 결정); NP-3(심도-조건부, 저순위) — 심도 전용 라벨+온건 g(0.70) 미검, 단 DD15 recall 0.180으로 사전 posterior 부정적. 부활 조건 = ①어떤 라벨이든 recall>base(fisher p<0.05) 달성 시 동일 스케줄 재측정 ②NP-2 일간 농축 유의 시 cadence lane ③carrier 2026-07+ 재생성 시 7월 폭락 포함 재판정(단 2026-05 ON 오발화 -20.7% 선행 실측이 반대 증거)."
)
res <- emit_lcode(
  mode = "alpha_research",
  strategy_id = "WT_D20260802_019_FQ118_DDSTATE_NOWCAST_OVERLAY",
  grade = "F",
  lesson_text = lesson,
  metric_type = "canonical_screen",  # 실경로=weighted_screen_bt(동일 contract build_benchmark_compare NW3) — emit enum 계열 상위 라벨, 실경로는 construction_type/lesson 명기
  construction_type = "overlay_exposure_scalar_on_book_carrier (M4xR05 noLayer4 x DD_STATE 12M-10pct g40)",
  selection_type = "chain",
  mechanism_hypothesis = "하락 에피소드 군집성으로 트레일링 낙폭 상태가 익월 BM<0을 base 이상 포착하면 오라클 상금 일부 회수 — 기각. 트레일링 가격-상태 5변형 전부 판별 비유의(월간 BM<0은 트레일링 가격 상태와 사실상 독립). nowcast 쌍둥이 병리 실측: 초입 실기(2026-04 OFF) + 반등 오발화(ON월 벤치 연율 +10.4%).",
  portfolio_alpha_t = 4.18,
  oos_months = 269L,
  oos_retention = 0.41,   # .canon_oos_rough 진단치(CAND active — 권위는 essence_score)
  falsification_attempts = list(
    list(test = "라벨 품질 사전 검정(성과 전 fail_line)", result = "recall 0.351 <= base 0.413, fisher p=0.795 — FAIL", effect_retained = FALSE),
    list(test = "진단 변형 4종(DD5/DD15/VOL80/단월음수) 라벨 품질", result = "전부 fisher p>0.25 비유의 — 축 전체 기각", effect_retained = FALSE),
    list(test = "PIT 위반 주입(홀딩월말 cutoff)", result = "assert stop 발화 — 차단 실효 실증", effect_retained = NA),
    list(test = "lag 스트레스(cutoff 1개월 추가 지연)", result = "paired t -3.77 -> -3.92 (leak 방향이 더 나쁨 — 누출 지문 없음)", effect_retained = FALSE),
    list(test = "가중 기저 교차(EW basis) + 비용 스트레스", result = "paired t -4.17 / -3.80 — 기저·비용 무관 유해 방향", effect_retained = FALSE)
  ),
  core_reference = "FQ-118 (WT-017 NP-2 파생, 오라클 상금 정량화); WT-D20260802_017 프레임 승계(parity 자리수 일치); carrier_STR_1715_AR_on_M4_R05_overlay_PG2 (production parity); preregistration stage_artifacts/WT_D20260802_019/preregistration.json",
  tags = c("regime_overlay","overlay_consumption_surface","nowcast_label","drawdown_state",
           "trailing_price_state_family_null","label_pretest_first","label_realized_mismatch",
           "oracle_headroom_unreachable_by_nowcast","harm_proportional_to_fire_months",
           "m4_r05_overlay","book_carrier","paired_marginal_negative","settled_negative",
           "pit_clean","violation_injection_pass","fq_118","fq_117_gate_baseline","frontier_open_np"),
  metrics = list(
    label_recall = 0.351, label_precision = 0.424, bmneg_base_rate = 0.413, label_fisher_p = 0.795,
    diag_dd5_recall = 0.532, diag_dd5_fisher_p = 0.259, diag_dd15_recall = 0.180,
    diag_vol80_recall = 0.081, diag_m1neg_recall = 0.441,
    paired_marginal_t = -3.77, marginal_ann_pct = -7.35, delta_ir = -0.439,
    paired_ew_basis_t = -4.17, paired_lag_stress_t = -3.92, paired_cost_stress_t = -3.80,
    nowcast_only_paired_t = -3.53,
    book_port_t = 6.18, cand_port_t = 4.18, book_abs_sr = 1.711, cand_abs_sr = 1.605,
    book_mdd = -0.233, cand_mdd = -0.222, oracle_port_t = 7.87, oracle_mdd = -0.092,
    oracle_paired_t = 1.18, recovery_return_axis = -3.43, recovery_mdd_axis = 0.073,
    on_month_bench_ann = 0.104, on_month_frac_bm_neg = 0.424,
    crisis_alpha_book_ann = 0.254, crisis_alpha_cand_ann = 0.039,
    n_months = 269, n_label_fire_months = 92, turnover_equity = 10.3,
    overlay_churn_book = 1.01, overlay_churn_cand = 1.43
  )
)
cat("[wt019] emit_lcode 반환:\n"); str(res)
