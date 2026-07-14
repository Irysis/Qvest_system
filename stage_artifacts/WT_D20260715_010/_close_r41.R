setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
Sys.setenv(QM_ROOT="C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source("02_Infrastructure/contracts/close_round.R")
close_round(
  round_id = "R41 / FQ-053 / WT-D20260715_010 (insider SAFE_FADING horizon-bounded 실배선)",
  verdict_type = "capability_established",
  mechanism_diagnosis = "R40 next_probe P1 소비 = SAFE_FADING horizon-bounded 실배선(measurement 아닌 wiring refine). R39의 '무기한 SOFT-LAG'(SAFE_FADING이 즉시전이 EXIT(m/m-1)에서만·이후 OFF)을 R40 실측(청산 후 protection = ~1개월 transient — MID EXIT cohort h0 tail 5.2%·h1 3.5%(<OFF 7.9%, 집중) / h2 12.3%·h3 10.5% baseline 복귀·paired-t 전구간 |t|<2 비유의)으로 교정. filing_delay_watch.R Part C에 months_since_off(청산=첫 off월 후 경과 홀딩월, exit월=0=R40 h; window {m-1,m-2,m-3}의 최근 ON offset k → mso=k-1) 추적 배선 + FADE_MAX_MSO=1L 상수(사전 고정·sweep 금지): SAFE_FADING = months_since_off ∈ {0,1}(R40 protection 창 h0-1) · months_since_off>=2 자동 해제(cleared→NEUTRAL). R37 tier 신뢰가중(MEGA_TOP30 저신뢰/MID_OTHER 강건 gap t 4.6~6.1) + dur-가중(SUSTAIN 지속>ENTRY 단발) 유지. R40 검열편향 정량 기각 내장(MID 검열 2건/0.2%·진성폐지 0·차등이탈 p=0.757·worst-case wipeout(-100%)에도 EXIT tail 6.0%<OFF 7.9% risk-sticky). catastrophic vs benign 경계 명시(R40 P3: benign exit 98.3%=SAFE_FADING 소관 / catastrophic 0.9%=부실 tripwire Part A/B 소관). ★검증(현 북 14보유): SAFE_FADING 2건(LG이노텍 A011070·신세계 A004170, 둘 다 mso=1·MID_OTHER robust) — R39 판정(SAFE_FADING 0)과 다름: R41 horizon 확장이 R39가 놓친 h1 protection 창을 포착. 두 종목 INS02 z: 202604=1.048(ON)·202605=1.014(ON)·202606=0.998(OFF=exit월 h0)·202607=0.912(OFF=h1) → 청산월 202606·현 홀딩월 202607=exit+1=R40 h1(mso=1)=SAFE_FADING(다음달 mso=2 auto-clear 예정). R39(m/m-1만)은 OFF로 오분류했으나 R40 실측상 h1은 protection 잔존 구간 → R41이 올바로 SAFE_FADING 유지(설계 목적 실증). insider_state(즉시전이)=OFF여도 insider_flag(horizon)=SAFE_FADING, mso 필드 투명 노출. 3파트(제출지연 WARN 0·감사 WARN 0·insider horizon 상태전이) 통합 리포트 정상 + JSON well-formed 검증(r40_verdict/exit_rule=HORIZON-BOUNDED/fade_horizon_rule/catastrophic_vs_benign/months_since_off 필드). book_state/05_Production/outputs.ramp 무변경·DART API 0·텔레그램 미발송(배선 태스크).",
  next_probes = c(
    "SAFE/SAFE_FADING live 발화 OOS 추적 배관 (FQ-053 P2 승계·현 SAFE_FADING 2건 발화로 armed→active) — flagged 보유(LG이노텍·신세계)의 익월(202608~) 실현 위험(하방/tail)을 monitoring_report에 tier별(mid/mega) 누적 기록해 R40 h0-1 protection 창의 out-of-sample 확증. mso=1→2 auto-clear 시점도 로그. feasible now(insider 패널+rawdata 재사용).",
    "부실 tripwire coverage 확장 (FQ-053 P2 / FQ-038 결합) — catastrophic exit(진성폐지/distress)은 투자가능 uni에서 ~1%뿐이나 pre-filter(small-cap/below-liq) 영역 집중. R40 census를 uni-이전 broader universe로 확장해 SAFE_FADING(투자가능-only)이 놓치는 부분을 R22~R24 지각제출/부실 라인과 소관 정합.",
    "catastrophic-exit 경계 명시 tripwire 형식화 (R39 P3 승계) — benign 98.3%/catastrophic 0.9% 경계를 execution 유니버스이탈감지와 명시 우선순위 규칙으로 형식화할지 검토(현 배선은 라벨·주석 경계)."
  ),
  consumer_surfaces = c(
    "⑤monitoring: SAFE_FADING horizon-bounded 실배선 완료 = filing_delay_watch.R Part C(months_since_off ∈ {0,1} fading·>=2 auto-clear·무기한 SOFT-LAG 폐지) + monitoring_init.md Part C horizon 규칙. 월간·보고만·자동조치 없음",
    "⑧위험모델/감시: per-holding SAFE_FADING에 months_since_off/clears_at_mso 노출 + R37 tier 신뢰 + dur 가중신뢰 유지. R40 검열-immaterial·benign 98.3%/catastrophic 0.9% 경계 내장. 자본/sizing 아님",
    "부실 tripwire(Part A/B): catastrophic exit(0.9%)=SAFE_FADING 소관 아님 명시(R40 정량) — benign 98.3%만 SAFE_FADING, 진성폐지/distress는 부실 tripwire 우선"
  ),
  frontier_update = "FQ-053 잔여 P1(SAFE_FADING horizon-bounded 실배선) 소비 완료 = R40 P1 배선. insider 라인(R9~R41) monitoring 소비면 확립 완료(자본 미검 불변). 무기한 SOFT-LAG → horizon-bounded(mso {0,1} fading·>=2 auto-clear) 정교화로 R38/R39/R40 exit-timing 진단 배선 종료. 잔여 프론티어 → live OOS 추적(P2, 현 SAFE_FADING 2건 발화로 active 대기)·부실 tripwire coverage 확장(FQ-038 결합)·catastrophic-exit 형식화(P3).",
  live_trigger = "현 SAFE_FADING 2건(LG이노텍·신세계 mso=1) → 익월 실현 위험 OOS 로그 발화(FQ-053 P2 active) · 복합 flag에서 mega tier t>2 관측 시 대형주 SAFE 신뢰 상향(R37) · 계약금액 magnitude 등 신규 insider 신호정의 등재 시(INV-7)",
  layer = "⑧위험모델/감시 (SAFE tripwire 청산규칙 horizon 정교화) — 성과 병목 아님(위생 배선 refine). insider 라인 R9~R41 monitoring 소비면 확립 완료, ①재료/선별 벽과 무관",
  evidence_refs = c(
    "02_Infrastructure/reports/filing_delay_watch.R (Part C horizon 확장: FADE_MAX_MSO·months_since_off·prev2/prev3)",
    "02_Infrastructure/prompts/monitoring_init.md (Part C horizon 규칙 + output_schema)",
    "stage_artifacts/WT_D20260715_010/verdict.json",
    "stage_artifacts/WT_D20260715_010/_r41_watch_run_log.txt",
    "stage_artifacts/WT_D20260715_010/_verify_mso.R (INS02 z 시계열 재확인)",
    "qepm/observability/filing_delay_watch_latest.json (insider_net_buy_safe horizon 섹션)",
    "06_Registry/layer_bottleneck_map.md (⑧ 행 v14)",
    "parent: R40 stage_artifacts/WT_D20260715_009/verdict.json (next_probe P1)"
  )
)

## L-code emit (ledger 완결) — mode=ramp, metric_type=canonical_screen (R34/R38/R39 monitoring 라인 emit 선례)
source("02_Infrastructure/axiom/lcode_emit.R")
r <- emit_lcode(
  mode = "ramp",
  strategy_id = "R41_insider_safe_fading_horizon_bounded_wiring",
  grade = "B",
  metric_type = "canonical_screen",
  record_type = "process",
  construction_type = "insider_safe_fading_horizon_bounded(months_since_off tracking, fading window {0,1}=R40 h0-1, auto-clear >=2) + R37 tier_confidence(MEGA_TOP30 low/MID_OTHER robust) + dur_trust(SUSTAIN>ENTRY) + catastrophic_vs_benign_boundary(98.3/0.9) + R40 censoring_immaterial",
  selection_type = "chain",
  mechanism_hypothesis = "청산(insider net-buy flag off) 후 SAFE_FADING 라벨을 무기한 유지하는 것은 R40 실측상 부정확 — protection은 ~1개월 transient(h0-1 집중, h2+ baseline 복귀). horizon-bounded(mso {0,1} fading, >=2 auto-clear)가 R40 실측 정합. R39 무기한 SOFT-LAG는 h1 창을 오히려 조기 clear(m/m-1 window 한계)했으므로 window {m-1,m-2,m-3} 확장으로 h1 protection 창 포착이 옳음. 검증서 현 북 h1 2건(LG이노텍·신세계) 실포착 = R39 미포착분. mega tier SAFE 저신뢰(R37). catastrophic exit(0.9%)은 별도 소관(부실 tripwire). 배선 검증 완료·자본 아님.",
  core_reference = "FQ-053 (R40 P1 SAFE_FADING horizon-bounded 실배선); R40 verdict stage_artifacts/WT_D20260715_009/verdict.json; R38 verdict WT_D20260715_007; R37 verdict WT_D20260715_006; wiring 02_Infrastructure/reports/filing_delay_watch.R Part C + monitoring_init.md",
  lesson_text = paste0(
"[monitoring 배선 refine] R41 FQ-053 insider SAFE_FADING horizon-bounded 실배선 (R40 P1 소비, wiring 태스크·새 canonical 측정 아님). R39의 무기한 SOFT-LAG → R40 실측(청산 후 protection ~1개월 transient) 반영해 horizon-bounded 교정. filing_delay_watch.R Part C + monitoring_init.md Part C. base=production clean T-1 holdings + insider_factor_scores.parquet(로컬 재사용·202606) + rawdata size 스냅샷. §7b 정합·DART API 0·book 무변경. ",
"★배선: months_since_off = 청산(첫 off월) 후 경과 홀딩월(exit월=0=R40 h; window {m-1,m-2,m-3}의 최근 ON offset k → mso=k-1) 추적 + FADE_MAX_MSO=1L 상수(사전 고정·sweep 금지). SAFE_FADING = months_since_off ∈ {0,1}(R40 protection 창 h0-1) · months_since_off>=2 자동 해제(cleared→NEUTRAL). R37 tier 신뢰가중(MEGA_TOP30 저신뢰/MID_OTHER 강건 gap t 4.6~6.1) + dur-가중(SUSTAIN 지속>ENTRY 단발) 유지. ",
"R40 실측 내장(verdict=capability_established/no_hangover_horizon_limited): 청산 후 protection = ~1개월 transient — MID EXIT cohort h0 tail 5.2%·h1 3.5%(<OFF baseline 7.9%, 집중) / h2 12.3%·h3 10.5%(baseline 복귀·paired-t 전구간 |t|<2 비유의). 검열편향 immaterial: MID 검열 2건/0.2%·진성폐지 0·차등이탈 p=0.757·worst-case wipeout(-100%)에도 EXIT tail 6.0%<OFF 7.9% risk-sticky → 'no hangover' 검열-조정 후에도 성립. self-adversarial이 terminal right-truncation 오분류(초기 no-hangover 반전)를 MAX_YM 가드로 finalize 전 검거. ",
"catastrophic vs benign 경계 명시(R40 P3 MID 117 off-transitions): benign exit 115(98.3%)=SAFE_FADING(monitoring) 소관 / catastrophic 1(0.9%)=부실 tripwire(distress/delisting) 소관 — 투자가능 유니버스 catastrophic ~1%뿐, SAFE_FADING 사실상 전량(99%) 소관이나 투자가능 조건부. ",
"★검증: 현 북 14보유 판정 = SAFE_FADING 2건(LG이노텍 A011070·신세계 A004170, 둘 다 mso=1·MID_OTHER robust). ★R39 판정(SAFE_FADING 0)과 다름 — R41 horizon 확장이 R39가 놓친 h1 protection 창 포착. 두 종목 INS02 z: 202604=1.048(ON)·202605=1.014(ON)·202606=0.998(OFF=exit월 h0)·202607=0.912(OFF=h1) → 청산월 202606·현 홀딩월 202607=exit+1=R40 h1(mso=1)=SAFE_FADING(다음달 202608 mso=2 auto-clear 예정). R39(m/m-1 window만)은 on_p(202606)=off·on_t(202607)=off → OFF로 오분류했으나 R40 실측상 h1은 protection 잔존 구간 → R41이 올바로 SAFE_FADING 유지(설계 목적 실증). insider_state(즉시전이 m/m-1)=OFF여도 insider_flag(horizon)=SAFE_FADING, mso 필드 투명 노출. ⚠ 태스크 지시문 '현 SAFE/FADING 0 armed'는 R39 behavior 기준 — R41 horizon 확장이 정확히 이 2건 드러냄(정직 보고). 3파트(제출지연 WARN 0·감사 WARN 0·insider horizon) 통합 리포트 정상 + JSON well-formed 검증(r40_verdict/exit_rule=HORIZON-BOUNDED/fade_horizon_rule/catastrophic_vs_benign/months_since_off). ",
"규율: wiring refine only·새 canonical 측정 없음·n_trials=1(chain·DSR 부적용, monitoring-face). book_state/05_Production/outputs.ramp 무변경·DART API 금지·cov/weights 미산출(역할경계)·텔레그램 미발송(배선). insider 라인 R9~R41 monitoring 소비면 확립 완료(자본 미검 불변). ",
"next_probe: P1(SAFE/SAFE_FADING live 발화 OOS 추적 배관 — 현 SAFE_FADING 2건 익월 실현 위험 tier별 누적·mso auto-clear 시점 로그, armed→active); P2(부실 tripwire coverage 확장 — pre-filter small-cap 진성폐지, FQ-038 결합); P3(catastrophic-exit 경계 명시 tripwire 형식화)."),
  metrics = list(
    task_class = "wiring_only_refine",
    verdict_type = "capability_established",
    r40_parent = "no_hangover_horizon_limited",
    fade_window = "months_since_off in {0,1} = R40 h0-h1 protection transient",
    fade_max_mso = 1L,
    auto_clear_at_mso = 2L,
    protection_transient = "R40 h0 tail 5.2 / h1 3.5 (<OFF 7.9) / h2 12.3 / h3 10.5 baseline return",
    censoring_immaterial = "MID cens 2/0.2pct, delist 0, diff-leave p=0.757, worst-case wipeout still risk-sticky",
    catastrophic_vs_benign = "benign 98.3pct=SAFE_FADING / catastrophic 0.9pct=distress tripwire",
    current_book_safe_fading = "2 (A011070 LG이노텍 mso1, A004170 신세계 mso1, both MID_OTHER robust)",
    determination_change_vs_r39 = "R39 SAFE_FADING 0 -> R41 SAFE_FADING 2 (h1 window caught, R39 missed)",
    n_net_buy_safe = 0L, n_safe_fading = 2L, n_no_insider_data = 3L,
    tier_split_mega_top30 = 4L, tier_split_mid_other = 10L,
    n_trials = 1L,
    next_probe = c("live OOS 추적 배관 (P2 active)", "부실 tripwire coverage 확장 (P2/FQ-038)", "catastrophic-exit 형식화 (P3)"),
    consumer_surfaces = c("monitoring: SAFE_FADING horizon-bounded 배선", "위험감시: mso/tier/dur 신뢰 라벨", "부실 tripwire: catastrophic 0.9pct caveat"),
    evidence = "stage_artifacts/WT_D20260715_010/verdict.json"
  ),
  tags = c("insider_netbuy","safe_tripwire","safe_fading","horizon_bounded","months_since_off",
           "auto_clear","monitoring_face","wiring_only","tier_confidence","mega_low_conf","midcap_robust",
           "censoring_immaterial","catastrophic_boundary","dur_weighted_trust","non_capital",
           "capability_established","insider_line_monitoring_established")
)
cat("emitted:", if(is.list(r)) (if(!is.null(r$l_code)) r$l_code else "see-output") else as.character(r), "\n")
