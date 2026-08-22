# Self-Adversarial Challenge — WT-D20260821_001 가설설계 (alpha-hypothesis, fable)

날짜: 2026-08-21 / 대상: alpha_hypothesis.json (finalize 직전 자가 적대검증, 설계 축 4문항)

## 축 1 — 메커니즘이 사후 서술(story-fitting)인가

**제기**: 2×3 대응 설계는 Lane A arm A/B 결과(서열·역서열)를 본 뒤 세워졌다. "용량이 아니라 표적-기하"라는 서술은 arm B 의 mechanism_reading 을 그대로 확장한 것 아닌가 — 관찰을 설명하도록 지은 이야기일 위험.

**판정: PARTIAL**. 사후성은 제거 불능 — 정직 신고(challenge_flags 1항)로만 통제. 단 본 가설은 관찰 재서술에 그치지 않고 **신규 반증 가능 예측**을 낸다: P1(동일-표적 paired 등가)은 Lane A 가 측정한 적 없는 대비이고, F1(선택 집합이 표적 축으로 군집)은 관찰된 적 없는 비-성과 관측이다. P2 만이 순수 재현 검사라 secondary 로 격하했다. 잔여 위험 수용.

## 축 2 — 반증 조건이 성과 동어반복으로 위장됐나

**제기**: P1 자체가 성과(paired 수익 차분) 기반이다. "성과가 같으면 지지"는 동어반복 아닌가.

**판정: REBUTTAL(구조 분리) + PARTIAL(1건 잔여)**. P1 은 §support_criterion 에 격리된 '지지 판정' 축이고, 기전 반증은 F1~F3 — 전부 보유 명세·실현 분포·선택 집합의 비-성과 관측이며 field_dictionary 내 필드(A1/FDB-B2/A4/A9/E5)로 계산 가능하다. 핵심 기각 규칙("성과 등가 ∧ F1 위배 = 기하 결정론 기각")이 성과와 기전을 명시적으로 갈라놓는다. 잔여: F1 중첩 비교의 수치 문턱이 미고정 — handoff ④로 alpha-research 사전등록에 위임(측정 전 1회 고정 의무 명시). 또한 P1 의 null 채택은 powered-null 자격(required_effect_size.R)을 요구해 '미결'과 '종결'을 분리했다.

## 축 3 — 국면 경계가 메커니즘에서 도출됐나 (사후 데이터 관찰 아닌가)

**판정: PARTIAL**. crisis 약화는 임계 비선형(청산 연쇄 → threshold 구조) 도출이며, 검사를 E5_msm_crisis_prob **연속 상호작용**으로 사전 지정하고 이분 분할을 금지해 에피소드 붕괴·사후 컷 선택을 차단했다. 단 설계자는 arm B 의 q90 MDD 67% 관찰을 이미 본 상태다 — 오염 가능성을 명시 신고. overheat 경계는 WT-D20260813_001 소유 축이라 **주장하지 않음**(경계 범위의 정직 축소).

## 축 4 — settled-negative 의 재포장인가

**판정: ACCEPT(재포장 아님)**. lookup 7건 대조: Quantile Regression Forest(MARGINAL C — CVaR 리스크 소비·ML) / Tail Quantile Risk(FAIL — 하방 리스크) / Copula 결합(MARGINAL C — **결합기** 층) / Winsorized ensemble(PASS B — score 평균법) / Markov 계열 3건(MARGINAL C 이하 — 단독 신호) — 전부 소비 층이 다르다. v8.4 금지 4종 정합: L-mean 은 평균-표적이나 **비-ML 대조군**이고 금지 조항이 '대조군으로만 등장'을 명시 허용. ML 결합기·사이징 아님. 병렬 중복: WT-D20260813_001(ML q90)과는 상보(같은 프레임의 음성 대조 공급) — in-flight 인덱싱 확인 완료.

## 추가 자가 제기 (설계 외 축)

- **선형 정칙화 자유도가 '용량'과 혼동될 위험** — challenge_flags 6항: 사전등록 1회 고정 + 탐색 시 sweep 재선언 의무로 배관.
- **6-arm 다중성** — argmax 비선택 라운드로 chain 등록하되 자본 승격 시 sweep+DSR HARD 전환 의무 명시.
- **합리화 어휘 자가검사**: answer-principles 회피표현 목록 대조 — 본 설계 문서에 해당 어휘 미사용 확인.

## 결론

verdict = **designed** 유지. 약점 4건 제기 → ACCEPT 1 / PARTIAL 3 / REBUTTAL 1(부분). 잔여 위험은 전부 challenge_flags·handoff 에 명시 이관 — 침묵 항목 없음.
