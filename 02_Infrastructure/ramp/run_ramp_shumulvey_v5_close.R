## run_ramp_shumulvey_v5_close.R — FQ-239 라운드 마감: 원장 등재 + close_round 계약 (FQ-239 P1 수집)
suppressPackageStartupMessages({library(data.table)})
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/ramp/register_ramp_result.R")
source("02_Infrastructure/contracts/close_round.R")

M<-readRDS(".cache/_smv_v5_measure_f15_roll.rds")
e5<-M[[1]]$essence; e15<-M[[2]]$essence
gr<-e5$grade

ramp<-list(
  ramp_id="RAMP_SHUMULVEY_V5_20260820",
  alias="RAMP_02_V5",
  grade=gr,
  metric_type="backtested",
  stock_count_compliance="N/A — 7-인덱스 연구 측정(배포 형태 아님). 25종 직접 변환은 06-19 전수 음수 실측 유지(DIST-RAMP-014)",
  essence=list(
    port_t_capwt=e5$essence$portfolio_alpha_t_nw_lag3,
    oos_retention=e5$essence$oos_retention,
    calmar=e5$essence$calmar,
    net_sharpe=e5$essence$net_sharpe, net_ir=e5$essence$net_ir,
    dsr=e5$essence$dsr, mdd=e5$essence$mdd,
    port_t_capwt_15bps=e15$essence$portfolio_alpha_t_nw_lag3,
    oos_retention_15bps=e15$essence$oos_retention,
    placebo=list(m0_5bps_p=0.033, m0_5bps_real_ir_vsew=0.049, placebo_mean=-0.309, placebo_sd=0.219, n_seeds=30,
                 m0_15bps_p=0.000, d1_5bps_p=0.133),
    graduation="FAIL 3/3 — PORT_t 1.033<2.95 · oos_retention 0.163<0.5(무조건 FAIL) · calmar 0.394<0.64. 보정 회계(월말 결정→익월 적용)+신규 vintage+계약 채점(essence_score v2, chain, n_trials=16). ★6월 결함 회계 수치(BL_20260619 essence) 전면 대체. 신호 실재(placebo p=0.033) → screen-tier 소비면 라우팅. DIST-RAMP-014 live_trigger(b) 미발화(0.163<0.5)",
    arms="M0-fixed pt 0.79 / M0-roll pt 1.03(TE3) best셀 TE2 1.23 / D1 전 16셀 IR_vsEW 음수(기각) / f17 금리 피처 무기여~역기여"),
  correction_ref="RAMP_SHUMULVEY_BL_20260619.correction_20260820 (동월 적용 look-ahead 철회)",
  fq_id="FQ-239",
  prereg="outputs/ramp/smv_v5_prereg_20260820.json",
  pin_tag="smv_r2_20260820",
  factor_indices=c("Market","Value","Size","Momentum","Quality","LowVol","Growth"),
  mcode_specs=list(
    construction="7 KR 스타일지수(cap-w top-tercile, 신규 vintage r202608) → 팩터별 2-state SJM(f15, fixed λ50/κ²9.5 및 causal roll 3×3 grid) → 국면조건부 평균 active(±5%cap) 뷰 → BL(EW prior, δ2.5, 인과 ex-ante TE 캘리브) → long-only Σw=1 MVO",
    rebalance="monthly (보정 회계: 월말 결정 → 익월 적용). 일별 T+2 팔(D1)은 측정 후 기각",
    cost="5bps(논문 대조) + 15bps(Qvest 정본) 병행",
    test_period="2014-04 ~ 2026-07 (149mo)",
    indices_data="outputs/ramp/shumulvey_index_returns_202608.parquet"),
  report="04_Research/ramp/reports/shumulvey_v5_20260820.md",
  lcode="RAMP_SHUMULVEY_V5_20260820",
  paper="Shu & Mulvey 2024, arXiv 2410.14841",
  n_trials=16,
  as_of_date="2026-07-31",
  capital_state="not_eligible")

register_ramp_result(ramp,
  regime_engine_version="smv_v5: per-factor SJM + 온라인 필터(기각)·causal rolling re-tune(T+1 L/S 상향). run_ramp_shumulvey_v5_daily.R",
  allocation_policy="BL long-only Σw=1, 보정 회계, 인과 c-캘리브. 헤드라인 M0-roll TE3")
cat("REGISTERED RAMP_SHUMULVEY_V5_20260820 grade=",gr,"\n")

close_round(
  round_id="FQ-239_smv_v5_20260820",
  verdict_type="screen_tier_routed",
  mechanism_diagnosis="동월 적용 결함(~1개월 look-ahead)이 6월 헤드라인의 약 2/3를 만들었고(shift A/B paired NW-t +5.1~+5.8), 보정 후 팩터-국면 타이밍 신호는 실재하나(placebo 30-seed p=0.033) 크기가 자본 게이트에 못 미친다(PORT_t 1.03 vs 2.95). 일별 온라인 필터는 상태 flip 노이즈가 신선도 이득을 압도(jump penalty 배수 증가가 단조 개선 = flip 노이즈 귀속 방증)하고 가치는 위기월에 국한(+0.57 vs +0.18 %/mo) — 상시 배분이 아니라 조건부 소비가 맞는 그릇이다.",
  next_probes=c(
    "P2ⓐ book overlay A/B — breadth=mean(bear_prob 6종) → exposure=1−0.30·breadth (사전등록 자유도 0, method_registry exposure adapter 경유, book_L5 대비 ΔIR)",
    "P2ⓑ Lane D 조건변수 실측 — FQ-236 핸드오프 적재 완료, bear_prob 조건부 비대칭(연속변수 의무)",
    "주간/이벤트-트리거 케이던스 — 일별(음수)·월간(약양성) 사이 미측정 축: 위기월 반응성만 취하는 조건부 리밸런싱",
    "P3 sleeve-배분층 변환(DIST-RAMP-014 frontier 1) — PORT_t 벽 완화 신호 발생 시"),
  consumer_surfaces=c(
    "오버레이/위험예산: smv_factor_regime_daily.parquet (신규 신호원, FQ-115 별개)",
    "Lane D 조건변수: FQ-236.handoff_smv_20260820",
    "monitoring: 위기월 조건부 반응성 신호(브리핑 보조)",
    "FR Track1 국면축 후보: 기존 엔진과 트레일링 IR 상관 측정 선행 조건"),
  frontier_update="FQ-239 measured_screen_tier — 단독 자본 경로 config-scoped 미달(보정 회계·계약 채점), 소비면 2경로(P2ⓐⓑ) 착수. 일별 케이던스 축은 f15/f17·λm 1·2·roll 전 구성 음수로 config-scoped negative",
  live_trigger=list(list(type="metric",
    condition="인과 rolling re-tune으로 oos_retention ≥ 0.5 재산출 시 DIST-RAMP-014 (b) 재판정 — 현 실측 0.163",
    monitored_source="essence_score/hurdle_result")),
  layer="신호층(국면 타이밍) — 신호 크기 부족이 병목. 재료(지수·피처)·배관(측정 계약) 정상. 회계층 결함은 본 라운드에서 수리 완료",
  evidence_refs=c(
    "04_Research/ramp/reports/shumulvey_v5_20260820.md",
    "outputs/ramp/smv_p02_shift_ab_20260820.csv",
    "outputs/ramp/smv_v5_results_f15.csv","outputs/ramp/smv_v5_results_f17.csv",
    "outputs/ramp/smv_v5_placebo_f15.csv","outputs/ramp/smv_v5_pair_f15.csv","outputs/ramp/smv_v5_shiftladder_f15.csv",
    ".cache/_smv_v5_measure_f15_roll.rds","outputs/ramp/smv_v5_prereg_20260820.json"))
cat("CLOSE_ROUND_DONE\n")
