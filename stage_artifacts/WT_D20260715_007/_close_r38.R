setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
Sys.setenv(QM_ROOT="C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source("02_Infrastructure/contracts/close_round.R")
close_round(
  round_id = "R38 / FQ-052 / WT-D20260715_007 (insider SAFE 청산-타이밍 대칭검정)",
  verdict_type = "capability_established",
  mechanism_diagnosis = "insider net-buy SAFE 신호의 청산(flag-off) 거동 = asymmetric_benign_risk_sticky — 청산은 위험 재상승 아님(no hangover). 상태기계(ENTRY/SUSTAIN/EXIT/OFF, 연속월+양월 insider-covered+INS02 z>=1.0 교차)로 판별. ① 수익축: MID SUSTAIN vs OFF t=+3.63(유의)이나 ENTRY t=+1.05·EXIT vs OFF t=+1.57·EXIT vs SUSTAIN t=+0.69 전부 무유의 → SAFE 수익 premium은 flag이 켜지는/꺼지는 이벤트가 아니라 flag이 지속되는 상태(SUSTAIN 클러스터) 현상. 청산 시 premium 완만복귀. ② 위험축: MID EXIT downside −6.9%(OFF −8.6%)·tail(<-15%) 5.2%(OFF 7.9%) = 청산 후에도 하방/tail protection 점착(상태 간 단조순서 OFF>ENTRY>SUSTAIN≈EXIT, risk_sticky=TRUE·hangover=FALSE). ③ hold-duration: MID d1 vs OFF t=+0.05(단발 무신뢰)·d2_3 t=+2.38·d4plus t=+3.04 = 지속 flag이 더 신뢰(표본·안정성), freshness slope(dur→ret 월내demean) t=−1.32 무유의 = 신선도 절벽 없음. robustness: lag1 SUSTAIN +3.63→+3.40(동월누출 아님)·held 슬리브 SUSTAIN t=+2.78·EXIT t=+2.28(북 잔존종목 청산 후 위험재상승 없음 독립확증). ★한계: EXIT 표본 희소(MID 115·held 29)+수익축 무유의(risk_sticky는 유의검정 아닌 순서패턴)·검열편향(flag-off 동시 폐지/유동성붕괴 종목 검열 → no hangover는 투자가능 조건부). monitoring 함의: tripwire 청산규칙 불요(SOFT-LAG) — flag-off은 danger 아님, SAFE→SAFE_FADING 강도하향 + 지속flag 우선신뢰 권고. 자본/sizing 아님.",
  next_probes = c(
    "청산 후 다중월(t+1..t+3) forward 위험 궤적 + 패널이탈(폐지/유동성) 종목 worst-case 대입 검열-스트레스 — 'no hangover'의 검열편향 정량. R38 EXIT은 flag-off 다음달 잔존 조건부라 catastrophic exit 검열됨(Concern 2). feasible now(insider 패널+rawdata 재사용).",
    "SAFE_FADING 라벨 실배선 + dur-가중 신뢰(지속flag>단발) — filing_delay_watch.R Part C에 상태전이(SAFE→SAFE_FADING→cleared) 추가. R37 mid-cap 신뢰가중 + R38 청산규칙(SOFT-LAG) 통합. monitoring 태스크(자본 아님)."
  ),
  consumer_surfaces = c(
    "⑤monitoring: SAFE tripwire 청산규칙 확정 = SOFT-LAG(flag-off≠danger, SAFE→SAFE_FADING 강도하향, 지속flag 우선). filing_delay_watch.R Part C 상태전이 배선 권고(별도 태스크)",
    "⑧위험모델/감시: per-holding '유지 안전' 라벨은 청산 후에도 하방/tail protection 점착 — 라벨 즉시해제 불요(위험 재상승 아님). 단 투자가능 조건부(검열편향 caveat)",
    "⑥선별라벨: SAFE 수익 신호 = 지속(SUSTAIN)-클러스터 현상 — 단발 flag(dur=1 t=0.05)은 저신뢰, 진입/청산 이벤트 자체는 무정보축"
  ),
  frontier_update = "FQ-052 소비 완료(R34 P3/R37 P1 exit-timing 대칭): 청산=asymmetric_benign_risk_sticky(no hangover·protection 점착·수익 premium 지속-클러스터 현상). tripwire 청산규칙=SOFT-LAG(불요). insider 라인(R9~R38) exit-timing 마지막 진단. 잔여 프론티어 → 검열-스트레스(next_probe P1)·SAFE_FADING 실배선(P2). insider 재료 = monitoring 소비면 확립 완료(자본 미검 불변).",
  live_trigger = NULL,
  layer = "⑤monitoring (SAFE tripwire 청산규칙 판정) — 성과 병목 아님(소비면 진단). insider 라인 exit-timing 마지막 진단, ①재료/선별 벽과 무관",
  evidence_refs = c(
    "stage_artifacts/WT_D20260715_007/verdict.json",
    "stage_artifacts/WT_D20260715_007/r38_results.json",
    "stage_artifacts/WT_D20260715_007/challenge_note_r38_20260715.md",
    "stage_artifacts/WT_D20260715_007/_r38_objects.rds",
    "stage_artifacts/WT_D20260715_007/chart_A_entry_vs_exit.png",
    "stage_artifacts/WT_D20260715_007/chart_B_duration.png",
    "prereg config_hash 7d9d5f1a7ccfa754 (prereg_r38.json)",
    "parent: FQ-051 R37 verdict stage_artifacts/WT_D20260715_006/verdict.json"
  )
)

## L-code emit (ledger 완결)
source("02_Infrastructure/axiom/lcode_emit.R")
r <- emit_lcode(
  mode = "alpha_research",
  strategy_id = "R38_insider_safe_exit_timing_symmetry",
  grade = "B",
  metric_type = "observational_monitoring",
  construction_type = "insider_netbuy_safe_exit_timing + state_machine(ENTRY/SUSTAIN/EXIT/OFF) + hold_duration_decay + monthly_paired_NW + lag1_stress + held_confirm",
  selection_type = "chain",
  lesson_text = paste0(
"[monitoring 진단] R38 FQ-052 insider net-buy SAFE 청산-타이밍 대칭검정 — SAFE 진입 정보성(R33/R34 확립)이 청산(flag-off) 시 대칭 소멸/재상승/점착 판별. base=R36 _r36_objects.rds uni(production clean T-1 파생, production_parity_verified 3.058, PIT C5·lag1 검증 상속). insider 라인(R9~R38) exit-timing 마지막 진단. 자본 아님(monitoring 소비면). ",
"★판정: CAPABILITY_ESTABLISHED / symmetry=asymmetric_benign_risk_sticky — 청산은 위험 재상승 아님(no hangover). ",
"상태기계: ENTRY/SUSTAIN/EXIT/OFF (연속 hold_ym m-1→m + 양월 insider-covered + INS02 z>=1.0 교차, coverage-gap 아닌 z-level 전이). counts ALL: OFF 17096·SUSTAIN 2769·ENTRY 448·EXIT 434 / MID: OFF 4581·SUSTAIN 753·ENTRY 131·EXIT 115. ",
"P1 수익축(MID 월별-paired NW-lag3 vs OFF): SUSTAIN t=+3.63(유의)·ENTRY t=+1.05·EXIT vs OFF t=+1.57·EXIT vs SUSTAIN 전이델타 t=+0.69 전부 무유의 → SAFE 수익 premium은 진입/청산 이벤트 아닌 '지속(SUSTAIN) 클러스터' 현상. 청산 시 premium 완만복귀. ALL(mega 희석) EXIT vs OFF t=−0.17(완전복귀). ",
"P1 위험축(MID): EXIT downside −6.9%(OFF −8.6%)·tail(<-15%) 5.2%(OFF 7.9%) = 청산 후에도 하방/tail protection 점착. 상태 간 단조순서 OFF>ENTRY>SUSTAIN≈EXIT(risk_sticky=TRUE·hangover=FALSE). ",
"P2 hold-duration(MID vs OFF): d1 t=+0.05(단발 무신뢰)·d2_3 t=+2.38·d4plus t=+3.04 = 지속 flag이 더 신뢰(표본·안정성↑). freshness slope(dur→ret 월내demean) t=−1.32 무유의 = 신선도 절벽 없음. raw수익 신선할수록 약간↑·excess 지속할수록↑. ",
"robustness: lag1 스트레스 SUSTAIN t +3.63→+3.40(동월누출 아님)·EXIT +1.57→+1.24. held 슬리브(보유∩insider-covered 1880 nm) SUSTAIN vs OFF t=+2.78·EXIT vs OFF t=+2.28 독립 유의 → 북 잔존종목 청산 후 위험재상승 없음 확증. ",
"★한계: EXIT 표본 희소(MID 115·held 29)·수익축 무유의(risk_sticky=유의검정 아닌 순서패턴+lag1+held)·검열편향(flag-off 동시 폐지/유동성붕괴 종목 검열 → 'no hangover'는 투자가능 조건부). ",
"monitoring 함의: tripwire 청산규칙=SOFT-LAG(불요) — flag-off은 danger 아님(protection 점착), SAFE→SAFE_FADING 강도하향 + 지속flag 우선신뢰. filing_delay_watch.R Part C 상태전이 배선 권고(별도 태스크). ",
"방법론: R36 uni 상속(신규 데이터 접근 없음). state machine(shift+consec+both_cov)·월별-paired NW-lag3·dur run-length(cumsum newblk)·freshness NW회귀·lag1 shift. n_trials=1(chain·DSR 부적용, monitoring-face). book_state/05_Production/outputs.ramp 무변경·DART API 금지·cov/weights 미산출(역할경계). pin rawdata_r9_pin_20260715·prereg config_hash 7d9d5f1a. ",
"next_probe: P1(청산후 다중월 t+1..t+3 궤적 + 패널이탈 종목 worst-case 대입 검열-스트레스 — no hangover 검열편향 정량); P2(SAFE_FADING 라벨 실배선 + dur-가중 신뢰, filing_delay_watch Part C 상태전이)."),
  mechanism_hypothesis = "정보-우위 임원 매집 SAFE 신호가 소멸(flag-off)할 때 forward 위험이 대칭적으로 재상승하는가. 결과: asymmetric_benign_risk_sticky — 수익 premium은 완만복귀(무유의, 지속-클러스터 현상)하나 하방/tail protection은 점착(청산 후에도 OFF보다 안전)·hangover 없음. 지속 flag > 단발 flag(dur=1 무신뢰). monitoring 함의: 청산규칙 불요(SOFT-LAG). 검열편향으로 투자가능 조건부.",
  portfolio_alpha_t = 3.63,
  oos_months = 118L,
  core_reference = "FQ-052 (R34 P3/R37 P1 next_probe 계승); base R36 uni production_parity_verified 3.058; prereg config_hash 7d9d5f1a7ccfa754; parent verdict stage_artifacts/WT_D20260715_006/verdict.json; Cohen-Malloy-Pomorski 2012",
  metrics = list(
    symmetry_class = "asymmetric_benign_risk_sticky",
    exit_rule_needed = FALSE,
    mid_sustain_vs_off_t = 3.63, mid_entry_vs_off_t = 1.05,
    mid_exit_vs_off_t = 1.57, mid_exit_vs_sustain_t = 0.69,
    all_exit_vs_off_t = -0.17,
    mid_off_downside = -0.0864, mid_exit_downside = -0.0690,
    mid_off_tail = 0.079, mid_exit_tail = 0.052,
    risk_sticky = TRUE, risk_hangover = FALSE,
    dur_d1_vs_off_t = 0.05, dur_d2_3_vs_off_t = 2.38, dur_d4plus_vs_off_t = 3.04,
    freshness_slope_t = -1.32,
    lag1_sustain_t = 3.40, lag1_exit_t = 1.24,
    held_sustain_vs_off_t = 2.78, held_exit_vs_off_t = 2.28, held_name_months = 1880L,
    state_counts_mid = "OFF 4581 / SUSTAIN 753 / ENTRY 131 / EXIT 115",
    n_trials = 1L, verdict_type = "capability_established",
    next_probe = c("청산후 다중월+검열-스트레스 (P1)", "SAFE_FADING 라벨 실배선 dur-가중 (P2)"),
    consumer_surfaces = c("monitoring: 청산규칙 SOFT-LAG 확정", "위험감시: protection 점착 라벨 즉시해제 불요", "선별라벨: 지속-클러스터 현상·단발 저신뢰"),
    evidence = "stage_artifacts/WT_D20260715_007/verdict.json"
  ),
  tags = c("insider_netbuy","safe_tripwire","monitoring_face","exit_timing","exit_symmetry",
           "asymmetric_benign","risk_sticky","no_hangover","hold_duration","signal_freshness",
           "sustain_cluster","state_machine","lag1_robust","held_confirm","censoring_bias",
           "non_capital","capability_established","insider_line_exit_timing_final")
)
cat("emitted:", if(is.list(r)) (if(!is.null(r$l_code)) r$l_code else "see-output") else as.character(r), "\n")
