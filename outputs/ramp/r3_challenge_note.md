# RAMP R3 Self-Adversarial Challenge (v8.2 — finalize 직전 자가 적대검증)

- **일자**: 2026-07-11
- **대상**: RAMP R3 배분-레벨 소비 (후보 A tail 방어 sleeve · 후보 B V02_EP EW-가중 sleeve)
- **측정 파일**: `02_Infrastructure/ramp/run_ramp_r3_sleeve_addition.R` · `outputs/ramp/r3_summary_20260711.json`
- **적대검증 스트레스**: `02_Infrastructure/ramp/debug/r3_adversarial.R`

## 자가 제기 약점 6건 → ACCEPT/PARTIAL/REBUTTAL

### W1 — 판정 프레임: base(cap-w +1.77)가 06-18 graduation base(+2.37)보다 낮다 → "2.95 미달"이 base 저조 탓 아닌가? [ACCEPT + 재프레임]
- 실측: base M_regdd cap-w +1.77(EW-uni +2.46). 06-18 대비 낮은 이유 = 측정창 2026-05까지 연장(2017+ 감쇠 구간 추가 반영). R1의 stack_EW_softRegimeOverlay(+1.77)와 정확히 동일 레벨.
- **교정**: 1급 판정지표는 절대 도달이 아니라 **paired 증분**(with-sleeve − without-sleeve, 동일 월). 증분은 base 레벨에 불변. 사전등록 kill = 증분 NW-t<2.0이며 base 레벨과 무관하게 성립. "2.95 도달" 프레임은 부차 참조로만.

### W2 — A3 crisis 기여(+0.101/yr, t+1.92)가 regime look-ahead 아티팩트? (07-06 BearProb 재발 우려) [REBUTTAL(look-ahead 부재)]
- lag1-regime 스트레스(전월 regime을 당월 배분에 적용, 보수적 PIT): paired_t full **+2.52 > 원본 +1.54**. look-ahead가 있었다면 lag1에서 붕괴했어야 함(BearProb 사례). **오히려 강해짐 → 동월 look-ahead 아티팩트 아님**. regime@dd 사용이 오히려 보수적.

### W3 — crisis-conditional DEFENSE 기전이 실재하는가? crisis n=18, 다중 config → t+1.9~2.5 spurious? [ACCEPT — 기전 반증]
- placebo(regime 라벨 12m 시프트 = crisis 정렬 파괴): paired_t full **+2.18**(원본 +1.54와 동등/상회). crisis_d +0.101→+0.020, normal_d +0.002→+0.013.
- **해석: 증분은 "crisis 정렬"에서 나오지 않는다** — 시점 무관 미약한 저-tail-risk 스타일 틸트. 크라이시스 조건부 방어 기전은 **FALSIFIED**. (역설적으로 정직에 유리: crisis 기여를 과대주장 방지.)

### W4 — config-scoped(후보당 ≤4), IS-only. B의 cap-tier-restricted(OTHER-tier 한정) EP sleeve 미측정 [PARTIAL]
- dual-basis가 이미 방향 제시: EP sleeve가 EW-uni PORT_t(2.46→3.44, Δ~+1.0)를 cap-w(1.77→2.31, Δ~+0.54)보다 훨씬 크게 올림 = **cap-tier 트랩의 배분-레벨 재현**. cap-tier-restricted 변형은 EW-uni를 더 부풀리나 cap-w authoritative에선 트랩 논리상 예측-음성. 미측정은 config-scope 한계로 명기(구조 판결 아님, INV-7).

### W5 — tail sleeve sign을 RealVol 참조로 정한 것이 은닉 sign-mining? [REBUTTAL]
- RealVol 상관은 **동시점 횡단면(forward return 미사용)** = outcome-mining 아님. 방어 지향(저-tail-risk)은 경제 사전지정. **A4(neutralized 잔차) = paired_t −1.64(음성)** 실측이 "positive만 골라냈다" 반증 — 잔차 tail은 오히려 해로움. (R05_Tail_Risk pole만 raw/neut 간 불안정(RealVol corr≈0.001 노이즈)이나 5팩터 평균 중 1/5 가중, 결론 불변.)

### W6 — base가 이미 LowRisk(A)·Value(B) family 포함 → sleeve 증분이 흡수되어 과소? [ACCEPT — 이것이 답]
- 차별 검증: cor(tail_def_z, R1 LowRisk group_z)=0.132 · cor(V02_EP, R1 Value group_z)=0.135 = 저중복(전용 sub-sleeve는 R1 미측정). 그러나 국면-IC 가중 base가 crisis에 LowRisk를, 전반에 Value를 이미 로딩 → **분산된 family가 tail/EP 내용 대부분을 이미 포착. 집중 sub-sleeve의 한계 기여가 작다는 것이 R3 질문의 실측 답**(아티팩트 아님).

## 종합
- 자기합리화 detect: "crisis 기여 있음"을 근거로 A를 살리려는 유혹 → **placebo가 자가-반증**(W3). 기전 아닌 스타일 잡음.
- 4렌즈 중 look-ahead(REBUTTAL)·sign-mining(REBUTTAL)은 측정 방어, crisis-기전(ACCEPT-반증)·config-scope(PARTIAL)·base-흡수(ACCEPT-답)은 verdict 강화.
- **판정 불변**: 두 후보 모두 IS-선택 config의 full paired_t<2.0 → 지정 재도전 경로 소진. 구조 판결 아님(config/measurement-frame-scoped, INV-7).
