# Self-Adversarial Challenge — WT-D20260813_001 (q90 상방 분위 표적)

**작성**: alpha-research (Opus 4.8 native adversarial), finalize 직전. AX-008 3-source 중 1.
**대상**: `alpha_package.json` (research_verdict = NOT_SUPPORTED, 성과 미충족 · 기전 지지).

측정 요약 (구조화 산출물에서만):
- 성과 primary: q90 − arm A paired NW3 t = **+0.828** (< +2.0) → **NOT_SUPPORTED_NO_DIFFERENCE**
- 음성 대조 trim5 − arm A paired t = **−1.171** (개선 없음 — 기전 방향 정합)
- F1 tail-hit paired t = **+4.622** (PASS) · F2 diff −0.0091 (REJECT) · F3 hi−lo +1.694%p (PASS)
- β/vol: q90 D03 분위 0.139 vs arm A 0.350 (저변동 틸트) · β 0.781
- β-통제 α = +9.93%/yr · t(α)_NW = +1.384 · PORT_t 0.926 · MDD 67.0% · Calmar 0.231 · TO 10.61

---

## 자기 비평 (devil's advocate) — ≥3건

### C1. [사후선택 오염] q90 은 arm B 4-arm 관측 후에 골라졌다. '독립 사전등록' 라벨을 붙였어도 가설 자체가 데이터 스누핑의 산물이 아닌가?
**분류: PARTIAL (인정 + 통제)**
- 근거: 이 오염은 실재한다. q90 우위는 2026-08-13 arm B 의 secondary 관측에서 처음 보였고, 본 라운드는 그 관측이 없었으면 존재하지 않았다.
- 통제 실측: ① primary 를 q90 단독으로 사전 고정(PREREG §3, 교체 안 함) ② 파라미터를 arm A/B 와 **동일 시드·동일 값**으로 고정 — armB q90 parity **cor=1.0·max|Δ|=0** 으로 재현 확인(HPO 부재 실증) ③ method_shopping_log 에 4-arm(mean/q10/q50/q90) 이력 기재 → judge/graduation 이 다중검정 맥락으로 소비.
- 처리: **판정을 부풀리지 않는다.** 성과 primary 가 미달(t=0.828)이므로 사후선택이 만들 수 있는 최악(거짓 양성)이 실현되지 않았다 — 오히려 성과 축은 negative 다. 사후선택 위험이 가장 큰 곳은 '성과가 통과했을 때' 인데 통과하지 않았다. 남는 위험은 F1(기전) 발화의 사후선택인데, F1 은 성과와 독립 축이고 t=+4.62 로 우연 수준(|t|<2)을 크게 상회한다.

### C2. [β/vol 틸트가 total SR 우위를 만들었나] q90 의 total SR 0.6061 이 저변동 종목 편중의 아티팩트일 수 있다.
**분류: REBUTTAL (근거 제시)**
- 정량 3축: ① β-통제 α = +9.93%/yr, t(α)_NW = +1.384 — β 를 통제해도 α 는 양수(단 |t|<2, 자본 자격 아님) ② q90 β = 0.781 ≈ arm A β 0.776 (거의 동일 — 우위가 β 적재에서 오지 않음) ③ D03 분위 0.139 = arm A(0.350)보다 **낮다** — 우려한 '고변동 복권주 편중' 의 **반대**. total SR 우위가 있다면 그것은 고변동 레버리지가 아니라 **저변동 상방 후보 식별**에서 온다.
- 학술: 저변동 이상현상(Baker-Bradley-Wurgler 2011)과 정합 — 저변동인데 상방 꼬리를 실현하는 종목은 정확히 기전의 '비-salient 상방 후보'. 살리언스(고변동)로 관측되는 복권주가 아니라 다변량 조건부로만 식별.
- 단, 정직 라벨: t(α) |1.384| < 2 이므로 α 존재를 **주장하지 않는다**(measurement-graduation §2 — PORT_t 0.926 을 알파 근거로 인용 금지). β 기여 분해상 우위 자체가 유의하지 않다.

### C3. [rank-IC 음수인데 성과가 최고 = 측정 오류 아닌가]
**분류: REBUTTAL (근거 제시 — 이것이 가설의 핵심 관측)**
- 실측 재현: q90 rank-IC = **−0.0281** (armB q90 secondary 와 정확 일치, parity 1.0) · decile 단조성 = **+0.964** (dec1 0.38% → dec10 1.64%, 단조 증가) · total SR 최고.
- 화해: rank-IC 는 **월별 횡단면 Spearman 의 평균**(월 내 순위 안정성), decile 단조성은 **풀링된 분위-평균**(꼬리 흡수). 둘의 부호 상반 = q90 점수가 '월 내 중앙 순위' 는 못 맞히나 '상위 분위 풀 평균' 은 잘 맞힘 = 정확히 top-N EW 평균 소비와 정합. 이것은 오류가 아니라 **가설이 예측한 rank-IC↔소비 불일치의 실현-포트 직접 관측**.
- 3축 데이터: rank-IC −0.0281 / decile-mono +0.964 / F1 tail-hit t +4.62 — 세 통계가 같은 그림(순위력 낮음 ∧ 꼬리 식별 강함).

### C4. [F2 REJECT 는 기전 반증 아닌가]
**분류: PARTIAL (인정 — 부분 기각 축)**
- 실측: F2(상위-3 기여 집중도) q90 0.5919 vs arm A 0.6010, diff −0.0091 → REJECT(q90 이 근소하게 낮음).
- 해석: 기전은 'q90 이 낮지 않아야'(평균은 꼬리가 견인)를 요구했는데 근소하게 낮다. 그러나 F1(주 기각축)은 강하게 PASS. PREREG §5 규약대로 'F1 성립 ∧ (F2 또는 F3) 불성립' = 부분 기각 = '식별은 되나 소비 경로 일부 상이'. F3 은 PASS 이므로 F2 단독 REJECT.
- 처리: F2 를 침묵하지 않고 challenge_flag·falsification 산출물에 REJECT 로 명시. 근소 차(−0.009)를 '미미' 로 넘기지 않고 REJECT 로 정직 라벨.

### C5. [동일-config 재실행의 정보가치 — 새 데이터 없음]
**분류: ACCEPT (인정)**
- alpha_hypothesis challenge_flag 승계: armB q90 secondary 와 동일 패널·파라미터라 수치는 재현(parity 1.0). 신규 정보 = (a) 사전등록 primary 지위 (b) **F1~F3 기전 부수관측의 최초 측정** (c) **trim5 음성 대조**. (b)(c)가 본 라운드의 실질 산출 — 특히 trim5(paired t −1.17)와 F1(t +4.62)은 arm B 에 없던 새 측정이다.

---

## Self-rationalization auto-detection

금칙 표현("미미/관행적/보수적이면 OK/대부분 결과 동일") 스캔:
- F2 근소 차(−0.009)를 '미미' 로 처리하지 않고 REJECT 명시 — auto-review 통과.
- 성과 t=0.828 을 '거의 2.0' 로 반올림하지 않고 NOT_SUPPORTED 명시.
- β-통제 α +9.93%/yr 을 t(α)<2 이므로 '양수 알파' 로 주장하지 않음(measurement-graduation §2 준수).

## Q-Lead escalate trigger 점검
- HIGH severity concern ≥ 5? → No (PARTIAL 2·REBUTTAL 2·ACCEPT 1, 실 위반 0)
- AX axiom hard FAIL ≥ 3? → No
- PIT C1(lockbox/lookahead) 위반? → No (ast_verify WARN_RESTATEMENT, FAIL_LOOKAHEAD 없음; walk-forward sig_date < anchor 준수)
- **escalate 불요.**

## 결론
성과 축은 config-scoped negative(paired t 0.828 < 2.0)로 정직하게 닫는다. 기전 축은 F1 강발화·trim5 음성대조·저변동 틸트로 지지된다 — 병목은 표적이 아니라 **소비 마디(top-N 선별→평균)**. next_probe: expectile(C2)·FQ-237 선별 통계량·소비 형태 교체. 방향(target-form family) 판결로 확대 금지(INV-7).
