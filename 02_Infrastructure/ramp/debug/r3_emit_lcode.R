## r3_emit_lcode.R — RAMP R3 L-code 적립 (mode=ramp, backtested, sweep)
suppressPackageStartupMessages({library(data.table)})
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/config.R"); source("02_Infrastructure/ramp/ramp_loop.R")

les<-paste0(
"RAMP R3 — 지정 재도전 경로 2개(A tail 방어 sleeve / B V02_EP EW-가중 sleeve)를 국면-IC 가중 base(M_regdd, overlay-부재) 배분에 성분 추가 vs 제외 paired 측정. cap-w authoritative.\n",
"결과 = 둘 다 소진(EXHAUSTED). IS-선택 config full-period paired_t_capw: A3(tail regime-cond)=+1.54 / B2(V02_EP w=0.25)=+1.41, 사전등록 kill(<2.0) 미달. base cap-w PORT_t +1.77 → treatment 최대 A 1.94/B 2.37, HARD 2.95 전부 미달, oos_retention 전 config 음수(2017+ cohort decay).\n",
"후보 A(P3가 RAMP로 punt한 유일 return-derived 미해결): tail 방어 sleeve의 crisis 기여(raw z +0.101/yr, lag1 t+1.11~1.92)는 실재하나 **placebo(regime 12m 시프트)도 paired +2.18** = crisis 정렬이 기전 아님(시점-무관 미약 저-tail-risk 스타일 틸트). A4(FWL 잔차 tail)는 paired −1.64 음성 = 방어값은 raw 스타일 노출뿐. lag1(+2.52>원본)로 look-ahead 부재 확인. → crisis-conditional DEFENSE 기전 FALSIFIED, 배분 기여는 sub-threshold.\n",
"후보 B(FQ-008 재라우팅): EP sleeve가 EW-uni PORT_t(2.46→3.44, Δ~+1.0)를 cap-w(1.77→2.31, Δ~+0.54)보다 크게 올림 = cap-tier 트랩 배분-레벨 재현. cap-w 증분 sub-2.0.\n",
"INV-7 갱신 권고: (A) DIST-AR-001 재도전 조건을 '비-return 방어 데이터원 등재 시'로만 갱신 — overlay-부재 RAMP 국면배합(마지막 return-derived 경로)까지 measured-negative. (B) V02_EP는 벤치-상대 배포성 논의(FQ-009/D3)로 이월 확정. 구조 판결 아님(config/measurement-frame-scoped)."
)

ramp_document(
  strategy_id="RAMP_R3_SLEEVE_ADDITION_20260711",
  grade="B",
  lesson_text=les,
  construction_type="composite",
  selection_type="sweep",
  mechanism_hypothesis="국면-IC 가중 base 배분에 tail 방어 sleeve(A) 또는 V02_EP EW-가중 sleeve(B)를 성분 추가 시 cap-w 배분-레벨 paired 증분이 발생하는가 — A는 P3가 punt한 overlay-부재 환경 tail 기여, B는 EW-basis 생존(4.40)의 배분 재라우팅.",
  metrics=list(
    portfolio_alpha_t=1.54,            # 최선 paired 증분(A3 full-period, sub-2.0) — 절대 도달 아님
    paired_t_A3_full=1.54, paired_t_A3_is=1.43,
    paired_t_B2_full=1.41, paired_t_B2_is=1.26,
    base_port_t_capw=1.77, base_port_t_ew=2.46,
    treat_max_port_t_capw_A=1.94, treat_max_port_t_capw_B=2.37,
    treat_max_port_t_ew_B=3.44,
    oos_retention=-0.28,               # 최선 treatment(B4)도 음수
    calmar=0.36, n_months=257L, n_trials_per_candidate=4L, gate_paired_t=2.0),
  falsification_attempts=list(
    list(test="lag1-regime 스트레스(A3, 전월 regime → 당월 배분)", result="survived_stronger",
         detail="paired_t full +2.52 > 원본 +1.54 → 동월 look-ahead 아티팩트 부재(07-06 BearProb 대비)"),
    list(test="placebo(A3 regime 12m 시프트, crisis 정렬 파괴)", result="mechanism_falsified",
         detail="paired_t full +2.18 ≈ 원본 → crisis 조건부 방어 아닌 시점-무관 스타일 틸트"),
    list(test="A4 FWL 잔차 tail(스타일 제거)", result="negative",
         detail="paired_t −1.64 → 방어값은 raw 저-tail-risk 스타일 노출뿐, 잔차 tail은 해로움"),
    list(test="dual-basis(B, cap-w vs EW-uni)", result="captier_trap_reproduced",
         detail="EW-uni Δ+1.0 >> cap-w Δ+0.54 → 알파는 소형/OTHER tier, cap-w authoritable 미달")),
  oos_retention=-0.28,
  portfolio_alpha_t=1.54,
  oos_months=24L,
  record_type="performance",
  core_reference="RAMP R3 배분-레벨 소비 (run_ramp_r3_sleeve_addition.R · r3_summary_20260711.json · r3_challenge_note.md). DIST-AR-001 revival + P3(L-AR-20260710_150153_02) + FQ-008(L-AR-20260710_112721) 지정 소비."
)
cat("R3_EMIT_DONE\n")
