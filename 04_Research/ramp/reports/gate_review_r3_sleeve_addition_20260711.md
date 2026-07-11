# RAMP R3 Gate Review — 지정 재도전 경로 2개 배분-레벨 소비 (tail 방어 sleeve · V02_EP EW-가중 sleeve)

- **일자**: 2026-07-11
- **모드**: RAMP (소비 모드 — 지식엔진 지정 재도전 경로 소비, 신규 발굴 아님)
- **L-code**: L-RAMP-20260711_152314 (grade B, metric_type=backtested, selection_type=sweep)
- **판정**: **REWORK / 지정 재도전 경로 소진(EXHAUSTED)** — 자본 졸업 아님, frontier 갱신
- **자본 영향**: 없음 (governor 정지, book_state 무변경. 현 PG2 = STR_1715_on_M4_R05_noLayer4_PG2 불변)
- **vintage pin**: `ramp_r3_20260711_151048` (rawdata + factor_group_scores + pure_factor_scores mtime 2026-06-19 기록)

## 1. Observe / Step 0 — 소비 의무 + 중복 대조 (착수 전)

`ramp_observe` + hypothesis_index(866 entry) xmode 교차조회로 아래 기측정과의 차별을 확정. 차별 불가 부분은 skip.

| 기측정 | 본건과의 차별 (INV-7) | 판정 |
|---|---|---|
| **R1**(L-RAMP-20260705_184828) 11 경제 sleeve 개별·선택스택·soft-overlay | R1 sleeve = 11 **경제 family group_z**(neutralized). tail-CVaR **전용** sub-sleeve·V02_EP **단독** sleeve 미포함. 실측: cor(tail_def_z, R1 LowRisk)=0.132 · cor(V02_EP, R1 Value)=0.135 = 저중복 | **차별 성립** (전용 sub-sleeve 신규) |
| **R2**(lightgbm 국면조건부) | R2 = ML top-N/비선형. 본건 = tail/EP 성분-추가 paired 증분 | 차별 성립 |
| **06-18 M_regdd**(cap-w 2.37) | 동일 base(M_regdd)이나 그때는 성분 추가 없음. 본건 = tail/EP 성분 추가 증분 측정 | 차별 성립 |
| **P3**(L-AR-20260710_150153_02) tail slot-carve | P3 = 현 **book(M4×R05 overlay 포함)** book-marginal(paired −2.8). 본건 = **overlay-부재 RAMP 배분** allocation 성분(P3가 명시 punt한 유일 열린 질문) | 차별 성립 (환경·기전 상이) |
| **FQ-008**(L-AR-20260710_112721) V02_EP EW-생존 | FQ-008 = standalone dual-basis 특성화. next_action이 "V02_EP 재라우팅=RAMP EW-weight sleeve"로 본건 지정 | 지정 소비 |
| AX-003/DIST-QPM-006 (EP 단독 실패) | 본건 = standalone top-25 cap-w 아님. 배분-내 EW-가중 성분 + EW-basis 재프레임 | 차별 성립 (배분-내 성분) |

xmode FAIL/KILL 히트(tail): STR_AS Tail Quantile Risk·Tail Hedge 로테이션(alpha-search lean-lane, cap-w graduation 아님) — 배분-레벨 paired 측정과 상이.

## 2. 구성 (실측-only, cap-w authoritative)

- **base = M_regdd**: 국면-IC 가중 11-family composite(과거 IC `signal_date<dd` PIT-clean), canonical top-25 EW long-only · 15bps · cap-w(Size-가중) KOSPI200∪KQ150 active · 2005-01~2026-05 257m · 24m OOS 꼬리. run_ramp_graduation 재현.
- **성분 추가**: score = (1−w)·base + w·sleeve (월별 z, no hard switch). paired 증분 = treatment.ret_net − base.ret_net(동일 월) NW-t lag3.
- **후보 A** tail 방어 sleeve = mean 저-tail-risk 지향 z of {D47_CVaR_5pct, D48_VaR_5pct, R03_CVaR_95, R04_CVaR_99, R05_Tail_Risk}. 방향 = RealVol 참조(동시점 횡단, PIT-clean) 저-risk pole. 경제 사전지정 방어(C13 무위반, return-alpha 미주장). **4 config**(≤4): A1 raw static 0.15 / A2 raw static 0.25 / A3 raw regime-cond {N.05/CAU.25/CRI.40/B0} / A4 FWL-잔차 regime-cond.
- **후보 B** V02_EP EW-가중 sleeve(aligned z, approved rank_ic +0.009). **4 config**: B1 w=0.15 / B2 w=0.25 / B3 w=0.35 / B4 EP-composite(V02+V15) w=0.25.
- 선별 = **IS-only**(oos_cut 2024-06 이전 paired 증분 t 최대). n_trials=4/후보 사전등록.

## 3. 측정 결과 (실측, cap-w authoritative + EW-uni 진단 병기)

base M_regdd: **cap-w PORT_t +1.77** / EW-uni +2.46 / oos −0.59 / calmar 0.32.

| config | port_t_capw(Δ) | port_t_ew | oos | paired_t full/IS | crisis_d(ann,t_lag1) | normal_d |
|---|---|---|---|---|---|---|
| **A1** raw 0.15 | +1.94(+0.17) | +2.65 | −0.42 | +0.87 / +0.47 | +0.099 (t+2.54) | +0.002 |
| A2 raw 0.25 | +1.67(−0.10) | +2.22 | −0.49 | +0.28 / +0.00 | +0.095 (t+1.68) | −0.003 |
| **A3** raw regime-cond ★IS선택 | +1.94(+0.17) | +2.61 | −0.44 | **+1.54** / +1.43 | +0.101 (t+1.92) | +0.002 |
| A4 잔차 regime-cond | +1.49(−0.28) | +2.10 | −0.72 | −1.64 / −1.87 | −0.108 (t−2.18) | −0.002 |
| **B1** V02_EP 0.15 | +2.21(+0.44) | +3.17 | −0.37 | +1.23 / +1.00 | +0.061 (t+2.06) | +0.007 |
| **B2** V02_EP 0.25 ★IS선택 | +2.31(+0.54) | +3.44 | −0.31 | **+1.41** / +1.26 | +0.037 | +0.014 |
| B3 V02_EP 0.35 | +2.34(+0.57) | +3.39 | −0.28 | +1.07 / +0.73 | +0.004 | +0.015 |
| B4 EP-comp 0.25 | +2.37(+0.60) | +3.38 | −0.28 | +1.43 / +0.97 | +0.027 | +0.016 |

- **IS-선택 후보 A = A3**: full paired_t_capw **+1.54 < 2.0** → EXHAUSTED. 절대 cap-w PORT_t 1.94 < 2.95.
- **IS-선택 후보 B = B2**: full paired_t_capw **+1.41 < 2.0** → EXHAUSTED. 절대 cap-w PORT_t 2.31 < 2.95.
- **HARD 3종**: 전 config cap-w PORT_t<2.95 · oos_retention<0(2017+ cohort decay) · calmar≤0.36<0.64. base·treatment 모두 미달.

## 4. Self-Adversarial Challenge (finalize 직전, `r3_challenge_note.md`)

약점 6건 자가제기 → 판정 강화. 핵심 2건:
- **look-ahead 부재(REBUTTAL)**: A3 lag1-regime(전월 적용) paired_t **+2.52 > 원본 +1.54** → 07-06 BearProb식 동월 look-ahead 아티팩트 아님(그 경우 lag1 붕괴).
- **crisis 기전 반증(ACCEPT)**: **placebo**(regime 12m 시프트, crisis 정렬 파괴) paired_t **+2.18 ≈ 원본** + crisis_d +0.101→+0.020·normal_d +0.002→+0.013 → "crisis 조건부 방어"가 아니라 **시점-무관 미약 저-tail-risk 스타일 틸트**. A4(FWL 잔차) paired −1.64 = 방어값은 raw 스타일 노출뿐. 자기합리화("crisis 기여 있음→A 살리기") 유혹을 placebo가 자가-반증.

## 5. Verdict — 두 지정 재도전 경로 모두 소진(config/measurement-frame-scoped, 구조 판결 아님)

- **후보 A(P3 punt 소비)**: overlay-부재 RAMP 국면배합에서 tail 방어 sleeve의 배분 기여 = **sub-threshold(paired +1.54<2.0)이며 crisis-conditional 기전 FALSIFIED(placebo)**. return-derived tail 축의 마지막 열린 경로(overlay-부재 환경)까지 measured-negative. → **INV-7 갱신: DIST-AR-001 재도전 조건을 '비-return 방어 데이터원 등재 시'로만 유지**(P3 권고 확정).
- **후보 B(FQ-008 재라우팅)**: EP sleeve가 cap-w(+0.54)보다 EW-uni(+1.0)를 크게 올림 = **cap-tier 트랩의 배분-레벨 재현**. cap-w 증분 +1.41<2.0. → **V02_EP는 벤치-상대 배포성 논의(FQ-009/D3)로 이월 확정**(QEPM/standalone cap-w graduation 대상 아님).
- **불변**: base M_regdd·R1·06-18과 동일 2017+ cohort decay 벽. cap-w authoritative(EW-uni는 진단). governor 정지·book 무변경.

## 6. 산출

- 측정: `02_Infrastructure/ramp/run_ramp_r3_sleeve_addition.R`
- 결과: `outputs/ramp/{r3_summary_20260711.json, r3_config_gates.parquet}`, `.cache/_ramp_r3.{rds,txt}`
- 적대검증: `02_Infrastructure/ramp/debug/r3_adversarial.R` (lag1·placebo·A4 잔차)
- challenge note: `outputs/ramp/r3_challenge_note.md`
- L-code: `stage_artifacts/l_code/ramp/l_code_RAMP_R3_SLEEVE_ADDITION_20260711.json` (L-RAMP-20260711_152314)
