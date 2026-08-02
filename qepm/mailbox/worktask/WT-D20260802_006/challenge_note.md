# Challenge Note — WT-D20260802_006 (Self-Adversarial, v8.2)

**작성**: 2026-08-02, alpha_package finalize 직전. Charter §8 No Silent Override.
**대상**: SIG_LEVY_PV_63 (경로 시그니처 Lévy area A_pv, 사전등록 primary)

## 실측 요약 (판정 재료)

| 지표 | 값 | 기준 |
|---|---|---|
| canonical PORT_t (cap-w, NW lag-3) | **+1.23** (p=0.221, n=259) | HARD 2.95 미달 |
| EW-uni PORT_t (진단) | +1.93 | 비바인딩 |
| 부기간 PORT_t | pre2015 **+3.69** / 2015-19 −0.35 / 2020+ −0.85 / post2017 −1.07 | decay-pattern |
| oos_retention_approx (EW-uni) | 0.055 | 게이트 권위 아님(진단) — 참혹 |
| rank-IC / ICIR / t | −0.0097 / −0.110 / −1.78 | advisory |
| turnover | **1578%/yr** | 제약 1100% 초과 |
| lag1 스트레스 | +1.23 → +0.24 | 붕괴 |
| placebo (증분 순서 셔플 5시드) | PORT_t ∈ [−1.16, +0.51] | primary가 범위 상단 밖이나 여유 얇음 |
| 반증 검정 (기전 flow-링크) | Q5−Q1 후속월 (외인+기관)/ADV 스프레드 NW t = **+4.08** | 기전 지지 |
| 직교성 (M01/D03/D41/D45/D55) | \|rho\| ≤ 0.11 | 구조 직교 주장 실측 성립 |

## Concern 분류 (devil's advocate ≥3)

### C1. lag1 붕괴(+1.23→+0.24) = 동월 누출 아닌가 — **PARTIAL**
- 반박 근거: 누출 기전이 구조적으로 부재 — 신호 창은 sig_date 종가까지의 (Close, Vol)만 사용(패널 빌더가 `Date <= sig_date` 하드 슬라이스), forward return은 sig_date 종가→익월말 종가(하네스 표준). C5 오버레이 타이밍 비발동(오버레이 아님). M01 라벨 방향 감사 +0.0107로 forward 방향 정상.
- 인정: 누출이 아니어도 **반감기 1개월 미만의 신호는 월간 리밸 배포에 부적합**하다는 사실은 남는다. TO 1578%와 정합 — 신호가 빠르게 소멸하므로 lag1에서 죽는 것. 취약성 자체는 유효한 결함.

### C2. placebo 분리 불충분 — **ACCEPT**
- placebo 5시드 PORT_t 범위 [−1.16, +0.51], primary +1.23은 범위 밖이나 시드 5개의 얇은 표본에서 여유가 좁다. **canonical PORT_t 단독으로는 '경로-순서 정보가 수익 원천'이라는 주장을 확립하지 못한다.** 신호 실재의 실질 근거는 (a) flow-링크 t=+4.08 (b) pre-2015 부기간 +3.69이며, 현행 config의 전기간 수익 신호력은 약하다고 정직 기재한다.

### C3. rank-IC 음수(−0.0097) vs PORT_t 양수 괴리 — 기전의 단조성 주장 미성립 — **PARTIAL**
- 인정: 사전등록 기전은 횡단면 광역 단조 효과를 함의했으나 monotonicity 0.14, IC 부호 음수 — **횡단면 벌크에서는 성립하지 않는다**. 효과는 top-tail(축적 극단 25종)에 국소.
- 반박(축소 아님): IC advisory 강등의 저장소 실측(rank-IC와 top-N 실현 alpha의 구조적 괴리 — measurement-graduation §3, FLOW 거짓탈락 전례)과 동형 현상. 판정 권위는 PORT_t이며 그 값으로 이미 미달 판정.

### C4. oos_retention_approx 0.055 = cohort-wide post-2017 감쇠와 동형 — **ACCEPT**
- decay-pattern 라벨(overfit-pattern 아님 — IS 구간 조회로 변형 선택을 한 바 없음, 사전등록 단일 primary). dual-basis 확인 의무 이행: EW-uni에서도 post2017 t=−0.07로 사망 — **mega-cap 벤치 아티팩트로 구제되지 않는다**(FQ-055 계단 단절 계열과 동형). cap-tier도 OTHER 93.4%(pool base ~90.4% 대비 lift 1.03)로 국소화 미미.

### C5. turnover 1578% > 1100% 제약 — **ACCEPT**
- Production Constraint 위반. 평활(TS_MEAN 3M)은 본 라운드에서 실측하지 않았다(사전등록 밖 — 실측하면 2-trial 선택 위험). next_probe NP-2로 사전등록 승계.

### C6. "수학적 복잡성" 주장 자체가 장식 아닌가 — **REBUTTAL (근거 3축)**
- ① 구현이 정리 수준에서 검증됨: 11/11 (선형 닫힌형 1e-16, 원호 π, Chen 항등식 1e-13, 재매개화 불변, 위상차 사인파 −π·sinφ, 위반 주입 검출). 스칼라 요약 인접 계열(Hurst/TE/hill_tail)이 갖지 못한 성질 — **재매개화 불변성이 거래일 결측을 원리적으로 처리**(zero-vol 스킵). ② 자유 파라미터 2개(창 63d, winsor 3sd)로 oos 게이트와 양립하는 최소-노브 설계 — 복잡성은 구조(불변량)에 있고 파라미터에 없음(AST ast_features: node 3, free_param 2). ③ 직교성 실측 성립(기존 5팩터 |rho|≤0.11) + 기전 flow-링크 t=4.08 — 불변량이 경제적으로 실재하는 것(축적)을 측정함을 성과와 독립으로 입증. 학술: Lévy area/rough path (Lyons 1998), signature features (Chevyrev-Kormilitzin 2016), lead-lag via signatures (Gyurkó-Lyons-Kontkowski-Field 2013).

### C7. 국면 경계 사전등록 부분 오류 — **ACCEPT**
- 사전등록 holds_in=[neutral, recovery] / weakens_in=[crisis]. 실측: RISK_ON +2.71(지지), CRISIS −1.13(지지), **NEUTRAL −2.47(반증)**. 경계 도출이 절반만 맞았다 — "공통 유동성 충격이 lead-lag를 소거"는 위기에서 성립하나, 무추세 국면에서 신호가 역전되는 기전은 사전 미도출.

## 합리화 자기검증
- answer-principles 회피표현 조항의 금지 관용구(영향 축소·관행 호소 계열) 미사용 확인. placebo·lag1·IC 괴리 전부 결함으로 명기(축소 서술 없음).

## Q-Lead escalate 판정
- HIGH severity: C2/C4/C5 3건 (<5), AX hard FAIL 0, PIT C1 위반 0 → **자동 escalate 비발동**. 정상 보고 경로.

## 라운드 판정
**config-scoped negative (자본 tier) + 기전-확인 positive (flow-링크)** — 현 config(63d Lévy area, top-25 cap-w EW, 15bps, 월간 리밸)에서 수익 alpha 미달. 단 불변량이 측정하는 '축적'은 후속 기관+외인 매집으로 실재 확인(t=4.08). 소비면·next_probe는 alpha_package verdict_summary 참조 — 판정 수집 + next_probe 4건 도출로 라운드 수렴.
