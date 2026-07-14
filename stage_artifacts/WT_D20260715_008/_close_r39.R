setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
Sys.setenv(QM_ROOT="C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source("02_Infrastructure/contracts/close_round.R")
close_round(
  round_id = "R39 / FQ-053 / WT-D20260715_008 (insider SAFE_FADING 상태전이 tripwire 실배선)",
  verdict_type = "capability_established",
  mechanism_diagnosis = "R38 next_probe P2 소비 = SAFE 상태기계 실배선(measurement 아닌 wiring). filing_delay_watch.R Part C에 상태전이(현 홀딩월 INS02 flag on_t × 직전 홀딩월 flag on_p, 양월 insider-covered에서만 전이) → ENTRY/SUSTAIN=NET_BUY_SAFE / EXIT=SAFE_FADING(강도 하향·SOFT-LAG·즉시해제 안 함) / OFF=해제 배선. R38 실측 사실 내장: 청산(flag off)=위험 재상승 아님(symmetry=asymmetric_benign_risk_sticky·no hangover) — EXIT downside -6.9% vs OFF -8.6%·tail 5.2% vs 7.9% protection 점착, 수익 premium은 SUSTAIN(vs OFF t+3.63) 클러스터 현상(ENTRY t+1.05·EXIT vs OFF t+1.57 무유의)·hold-dur d4plus t+3.04>d1 t+0.05 = 지속 flag 우선신뢰. R37 tier 신뢰 내장: SAFE=mid-cap 강건(gap t 4.6~6.1)/대형주 TOP30 저신뢰(genuine mega attenuation·death, het mid−TOP30 t+3.70·검정력 1.0) — 배포 유니버스 size-rank<=30=MEGA_TOP30 SAFE/SAFE_FADING 라벨 신뢰 하향. R38 검열 caveat 내장: catastrophic exit(상폐/유동성붕괴/유니버스이탈)은 EXIT 표본 검열 → 'no hangover'는 투자가능 종목 조건부 = SAFE_FADING 소관 아님(부실 tripwire Part A/B 우선). 검증: 현 북 14보유 판정 = 11 OFF·3 NO_INSIDER_DATA·SAFE/SAFE_FADING 0(armed·inactive) — 현 max INS02 +0.912<1.0·신세계/LG이노텍 직전월 0.998=문턱 1.0 미달로 on_p FALSE → EXIT 아닌 OFF(정직 near-miss). z>=0.5 완화 시 3건 flag(advisory 카운트만·active 문턱 1.0 frozen). tier split MEGA_TOP30 4(삼성전자 r1·SK하이닉스 r2·SK스퀘어 r3·SK r17)/MID_OTHER 10. RAWDATA 단일 read 공유(Part B composite_source_ok=TRUE 무회귀). 3파트(제출지연 WARN 0·감사 WARN 0·insider 상태전이) 통합 리포트 정상 실행 + JSON well-formed 검증. book_state/05_Production/outputs.ramp 무변경·DART API 0·텔레그램 미발송(배선 태스크).",
  next_probes = c(
    "검열-스트레스 정량 (R38 P1 미측정분 승계) — 청산 후 다중월(t+1..t+3) forward 위험 궤적 + 패널이탈(폐지/유동성붕괴) 종목 worst-case 대입으로 SAFE_FADING 'no hangover' 라벨의 검열-조정 강건성 확정. feasible now(insider 패널+rawdata 재사용, 새 데이터 접근 없음).",
    "SAFE/SAFE_FADING live 발화 OOS 추적 배관 — flagged 보유의 익월 실현 위험(하방/tail)을 monitoring_report에 tier별(mid/mega) 누적 기록해 out-of-sample 확증. 현 0건 armed 대기(FQ-050 P2 계승) — SAFE 또는 SAFE_FADING 최초 발화 시 실효 로그 배관.",
    "catastrophic-exit 경계 형식화 — 현재 catastrophic exit은 Part A/B 부실 tripwire + execution 유니버스이탈에 암묵 위임. SAFE_FADING과의 우선순위 규칙을 명시 tripwire로 형식화할지 검토(현 배선은 caveat 라벨로만 경계 표시)."
  ),
  consumer_surfaces = c(
    "⑤monitoring: SAFE 상태기계 실배선 완료 = filing_delay_watch.R Part C(ENTRY/SUSTAIN=NET_BUY_SAFE·EXIT=SAFE_FADING SOFT-LAG·OFF=해제) + monitoring_init.md Part C. 월간·보고만·자동조치 없음",
    "⑧위험모델/감시: per-holding SAFE/SAFE_FADING 라벨에 tier 신뢰(MEGA_TOP30 저신뢰/MID_OTHER 강건) + dur 가중신뢰(SUSTAIN>ENTRY) 내장. 자본/sizing 아님(cohort-path 분산 아티팩트)",
    "부실 tripwire(Part A/B): catastrophic exit 검열 caveat = SAFE_FADING 소관 아님 명시 — 부실/이탈 경보 우선"
  ),
  frontier_update = "FQ-053(R39) 소비 완료 = R38 P2 SAFE_FADING 실배선. insider 라인(R9~R39) monitoring 소비면 확립 완료(자본 미검 불변). 잔여 프론티어 → 검열-스트레스 정량(P1)·live OOS 추적(P2, armed 대기)·catastrophic-exit 형식화(P3). FQ-052 exit-timing 진단 → FQ-053 배선으로 종료.",
  live_trigger = "복합 flag에서 mega tier t>2 관측 시 대형주 SAFE 신뢰 상향(R37 잔여 2015+ 레짐 국한·현 검출문턱 이하) · 계약금액 magnitude 등 신규 insider 신호정의 등재 시(INV-7)",
  layer = "⑧위험모델/감시 (SAFE tripwire 상태전이 정교화) — 성과 병목 아님(위생 배선). insider 라인 R9~R39 monitoring 소비면 확립 완료, ①재료/선별 벽과 무관",
  evidence_refs = c(
    "02_Infrastructure/reports/filing_delay_watch.R (Part C 상태전이 확장)",
    "02_Infrastructure/prompts/monitoring_init.md (Part C 항목)",
    "stage_artifacts/WT_D20260715_008/verdict.json",
    "stage_artifacts/WT_D20260715_008/_r39_watch_run_log.txt",
    "qepm/observability/filing_delay_watch_latest.json (insider_net_buy_safe 상태전이 섹션)",
    "06_Registry/layer_bottleneck_map.md (⑧ 행 v13)",
    "parent: R38 stage_artifacts/WT_D20260715_007/verdict.json (next_probe P2)"
  )
)

## L-code emit (ledger 완결) — mode=ramp, metric_type=observational_monitoring (R34 monitoring 배선 analog)
source("02_Infrastructure/axiom/lcode_emit.R")
r <- emit_lcode(
  mode = "ramp",
  strategy_id = "R39_insider_safe_fading_state_transition_wiring",
  grade = "B",
  metric_type = "observational_monitoring",
  construction_type = "insider_safe_state_machine_wiring(ENTRY/SUSTAIN=NET_BUY_SAFE, EXIT=SAFE_FADING SOFT-LAG, OFF=cleared) + tier_confidence(MEGA_TOP30 low / MID_OTHER robust) + censoring_caveat + rawdata_single_read",
  selection_type = "chain",
  lesson_text = paste0(
"[monitoring 배선] R39 FQ-053 insider SAFE_FADING 상태전이 tripwire 실배선 (R38 P2 소비, wiring 태스크·새 측정 아님). filing_delay_watch.R Part C에 SAFE 상태기계 배선 + monitoring_init.md Part C 갱신. base=production clean T-1 holdings + insider_factor_scores.parquet(로컬 재사용·202606) + rawdata size 스냅샷. §7b 정합·DART API 0·book 무변경. ",
"★배선: 상태기계(현 홀딩월 INS02 flag on_t[z>=1.0] × 직전 홀딩월 flag on_p, 양월 insider-covered에서만 전이) → ENTRY(on_t∧¬on_p)=NET_BUY_SAFE 단발신뢰低 / SUSTAIN(on_t∧on_p)=NET_BUY_SAFE 지속신뢰高 / EXIT(¬on_t∧on_p)=SAFE_FADING(강도 하향·SOFT-LAG·즉시해제 안 함) / OFF=해제. ",
"R38 실측 내장(symmetry=asymmetric_benign_risk_sticky): 청산(flag off)=위험 재상승 아님(no hangover) — MID EXIT downside -6.9% vs OFF -8.6%·tail(<-15%) 5.2% vs 7.9% protection 점착, 수익 premium은 SUSTAIN(vs OFF t+3.63) 클러스터 현상(ENTRY t+1.05·EXIT vs OFF t+1.57 무유의)·hold-dur d4plus t+3.04>d1 t+0.05(지속>단발). ",
"R37 tier 신뢰 내장: SAFE=mid-cap 강건(gap t 4.6~6.1)/대형주 TOP30 저신뢰(genuine mega attenuation·death, het mid−TOP30 t+3.70·검정력 1.0=power 아님). 배포 유니버스 size-rank<=30=MEGA_TOP30 → SAFE/SAFE_FADING 신뢰 하향 명시. ",
"R38 검열 caveat 내장: catastrophic exit(상폐/유동성붕괴/유니버스이탈)은 EXIT 표본 검열 → SAFE_FADING의 'no hangover'는 투자가능 조건부 = SAFE_FADING 소관 아님(부실 tripwire Part A/B 우선). ",
"★검증: 현 북 14보유 판정 = 11 OFF·3 NO_INSIDER_DATA·SAFE/SAFE_FADING 0(armed·inactive). 현 max INS02 +0.912<1.0; 신세계/LG이노텍 직전월 INS02 0.998 = 문턱 1.0 바로 아래 미달로 on_p FALSE → EXIT(SAFE_FADING) 아닌 OFF(정직 near-miss). z>=0.5 완화 시 3건 flag(advisory 진단 카운트만·active 문턱 1.0 frozen·완화 배선 별도). tier split MEGA_TOP30 4(삼성전자 r1·SK하이닉스 r2·SK스퀘어 r3·SK r17)/MID_OTHER 10. RAWDATA 단일 read 공유(Part B composite + Part C tier)로 이중 read 회피, composite_source_ok=TRUE 무회귀. 3파트(제출지연 WARN 0·감사 WARN 0·insider 상태전이) 통합 리포트 정상 + JSON well-formed 검증. ",
"규율: wiring only·새 canonical 측정 없음·n_trials=1(chain·DSR 부적용, monitoring-face). book_state/05_Production/outputs.ramp 무변경·DART API 금지·cov/weights 미산출(역할경계)·텔레그램 미발송(배선). insider 라인 R9~R39 monitoring 소비면 확립 완료(자본 미검 불변). ",
"next_probe: P1(청산후 다중월 t+1..t+3 궤적 + 패널이탈 종목 worst-case 대입 검열-스트레스 — no hangover 검열편향 정량); P2(SAFE/SAFE_FADING live 발화 OOS 추적 배관 — flagged 보유 익월 위험 tier별 누적, 현 0건 armed 대기); P3(catastrophic-exit 경계 형식화)."),
  mechanism_hypothesis = "insider net-buy SAFE 신호의 진입(ENTRY/SUSTAIN)/청산(EXIT) 상태를 tripwire에 배선 시 청산은 즉시 SAFE 해제가 아니라 강도 하향(SAFE_FADING·SOFT-LAG)이 옳은가. R38 근거: 청산해도 위험 protection 점착(no hangover)·수익 premium만 소멸 → SAFE_FADING 강도하향이 정합. mega tier는 SAFE 저신뢰(R37 attenuation). catastrophic exit은 별도 소관(부실 tripwire). 배선 검증 완료·자본 아님.",
  core_reference = "FQ-053 (R38 P2 SAFE_FADING 실배선); R38 verdict stage_artifacts/WT_D20260715_007/verdict.json; R37 verdict stage_artifacts/WT_D20260715_006/verdict.json; wiring target 02_Infrastructure/reports/filing_delay_watch.R Part C + monitoring_init.md",
  metrics = list(
    task_class = "wiring_only",
    verdict_type = "capability_established",
    states_wired = "ENTRY/SUSTAIN=NET_BUY_SAFE, EXIT=SAFE_FADING(SOFT-LAG), OFF=cleared",
    tier_rule = "size_rank<=30=MEGA_TOP30(low conf) / MID_OTHER(robust)",
    current_book_state_counts = "OFF 11 / NO_INSIDER_DATA 3 / ENTRY 0 / SUSTAIN 0 / EXIT 0",
    n_net_buy_safe = 0L, n_safe_fading = 0L, n_no_insider_data = 3L,
    max_ins02_cur = 0.912, relaxed_z0p5_flag = 3L,
    tier_split_mega_top30 = 4L, tier_split_mid_other = 10L,
    r38_symmetry = "asymmetric_benign_risk_sticky",
    embedded_facts = "R38 SUSTAIN t+3.63 / EXIT no-hangover protection sticky / R37 mid t4.6-6.1 vs TOP30 death",
    n_trials = 1L,
    next_probe = c("검열-스트레스 정량 (P1)", "live 발화 OOS 추적 배관 (P2)", "catastrophic-exit 형식화 (P3)"),
    consumer_surfaces = c("monitoring: SAFE 상태기계 배선", "위험감시: tier+dur 신뢰 라벨", "부실 tripwire: catastrophic exit caveat"),
    evidence = "stage_artifacts/WT_D20260715_008/verdict.json"
  ),
  tags = c("insider_netbuy","safe_tripwire","safe_fading","state_transition","monitoring_face",
           "wiring_only","soft_lag","tier_confidence","mega_low_conf","midcap_robust",
           "censoring_caveat","dur_weighted_trust","non_capital","capability_established",
           "insider_line_monitoring_established")
)
cat("emitted:", if(is.list(r)) (if(!is.null(r$l_code)) r$l_code else "see-output") else as.character(r), "\n")
