setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source("02_Infrastructure/contracts/close_round.R")
close_round(
  round_id = "R34 / FQ-050 / WT-D20260715_003 (insider net-buy tripwire 배선 + 북 de-risk 진단)",
  verdict_type = "capability_established",
  mechanism_diagnosis = "insider net-buy breadth 클러스터(INS02 z>=+1.0) = per-holding forward SAFE 신호가 북 보유(top-25 슬리브) 부분집합에서도 확증 — forward 수익 gap NW-t +2.50(restricted +2.68)·하방 -7.6% vs -8.3%·급락(<-15%) 4.7% vs 7.0%·flagged 전량 MEGA/MID(배포 tier)·lag1 robust(+1.89, 붕괴 아님=동월누출 아님). R33 universe 신호의 북-레벨 확장. tripwire를 filing_delay_watch.R Part C로 배선(부실=경보 / 순매수=안전 방향대비). 단 cohort-path MDD/vol은 flag가 오히려 악화(분산 아티팩트 2.5 vs 22.5종) = de-risk 값은 per-holding '유지 안전' 라벨이지 포트-path 저변동/sizing 신호 아님(자본 아님).",
  next_probes = c(
    "net-buy 클러스터 coverage 확장(현 북 flag 2.45/월 희소) — INS02+INS03 결합/breadth 임계 완화로 large-cap tier 안정성·표본 재검정",
    "net-buy SAFE tripwire live 발화 시 실효 OOS 추적 — flagged 보유 익월 실현위험을 monitoring_report에 누적 기록(현 0건 armed 대기)",
    "de-risk 예외 exit-timing 대칭 검정 — net-buy flag 소멸 시 forward 위험 재상승 여부(진입/청산 양측 정보성 + 추가 PIT 스트레스)"
  ),
  consumer_surfaces = c(
    "⑤monitoring: net-buy 클러스터 SAFE tripwire = filing_delay_watch.R Part C 배선 완료 (부실 창구 방향대비, 월간·보고만)",
    "⑧위험모델/감시: per-holding de-risk 예외 '유지 안전' 라벨 (자본/sizing 배선 금지)",
    "⑥선별라벨: net-sell(INS01) advisory only = R33 무정보 (경보 배선 금지 명시)"
  ),
  frontier_update = "FQ-050 insider de-risk tripwire: monitoring-면 배선 완료·북-레벨 per-holding 확증(capability_established). 자본-면(cohort-path·sizing)은 config-scoped negative(분산 아티팩트). coverage 확장·live OOS·exit 대칭이 잔존 프론티어. FQ-049 R33 P1 소비 완료.",
  live_trigger = NULL,
  layer = "⑤monitoring (net-buy SAFE tripwire 배선 완료) — ①재료/선별 벽과 무관 소비면. per-holding 위험특성화이지 성과 병목 해소 아님",
  evidence_refs = c(
    "stage_artifacts/WT_D20260715_003/verdict.json",
    "stage_artifacts/WT_D20260715_003/r34_results.json",
    "stage_artifacts/WT_D20260715_003/challenge_note_r34_20260715.md",
    "02_Infrastructure/reports/filing_delay_watch.R (Part C)",
    "02_Infrastructure/prompts/monitoring_init.md"
  )
)

## L-code emit (ledger 완결 — R33 패턴 정합)
source("02_Infrastructure/axiom/lcode_emit.R")
r <- emit_lcode(
  mode = "ramp",
  strategy_id = "R34_insider_derisk_tripwire_wiring",
  grade = "C",
  metric_type = "observational_monitoring",
  selection_type = "chain",
  lesson_text = "insider net-buy 클러스터(INS02 z>=+1.0) monitoring tripwire 배선 + 북-레벨 de-risk 진단(R33 P1 소비). 북 보유(score_eff top-25 슬리브) flag 종목 = per-holding forward SAFE: 수익 gap NW-t +2.50(restricted +2.68·ann +20.7%)·하방 -7.6% vs -8.3%·급락(<-15%) 4.7% vs 7.0%·flagged 전량 MEGA/MID(173/104, OTHER 0 = 배포 tier, 소형 아티팩트 아님)·lag1 robust(+1.89 붕괴 아님). ★단 cohort-path(sub-basket) MDD -34.5% vs -16.7%·vol 35.5% vs 22.5% = flag 오히려 악화 = 분산 아티팩트(2.5 vs 22.5종)이지 위험속성 아님 → de-risk 값은 per-holding '유지 안전'이지 포트-path 저변동/sizing 아님. tripwire를 filing_delay_watch.R Part C(부실=경보/순매수=안전 방향대비)+monitoring_init.md 배선. net-sell(INS01)=advisory only(R33 무정보). base=production clean T-1 §7b, insider 패널 재사용, DART API X, book_state 무변경.",
  mechanism_hypothesis = "정보-우위 임원의 지속 매집(breadth 클러스터)이 다음달 종목단 우편향 위험(고수익+급락회피)과 결합 — per-stock 위험 특성화(monitoring) 소비면에서 신호 보존. 선별-면 cap-tier 국소화 벽(R9)이 monitoring-면엔 안 걸림(R24/R25 선례 재현). 단 소수-이름 sub-basket 집중은 분산이익을 상쇄해 포트-path 위험 개선으로 전이되지 않음.",
  core_reference = "Cohen-Malloy-Pomorski 2012 (insider information content) + R33 verdict_r33_insider_consumption",
  metrics = list(
    derisk_gap_ret_nw_t = 2.50,
    derisk_gap_restricted_nw_t = 2.68,
    downside_flag = -0.0763, downside_nonflag = -0.0834,
    tail_lt_m15_flag = 0.047, tail_lt_m15_nonflag = 0.070,
    cohort_mdd_flag = -0.345, cohort_mdd_nonflag = -0.167,
    lag1_gap_nw_t = 1.89,
    flagged_held = 277L, flagged_held_pct = 4.14,
    tier_flagged = "MEGA 173 / MID 104 / OTHER 0",
    wiring_current_book_safe = 0L, wiring_holding_ym = 202607L,
    n_trials = 1L,
    verdict_type = "capability_established",
    next_probe = c("coverage 확장(INS02+INS03/breadth 완화)", "live SAFE 발화 OOS 추적", "exit-timing 대칭 검정"),
    consumer_surfaces = c("monitoring: filing_delay_watch Part C 배선", "위험감시: per-holding 유지-안전 라벨", "net-sell advisory only"),
    evidence = "stage_artifacts/WT_D20260715_003/verdict.json"
  )
)
cat("emitted:", if(is.list(r)) (if(!is.null(r$l_code)) r$l_code else "see-output") else as.character(r), "\n")
