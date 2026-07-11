# RAMP R4 Boruta — Self-Adversarial Challenge (v8.2, AX-008 source)

- config_hash: 34413993ed77c0ef | vintage: session_20260711 | 실측-only (canonical_screen_bt, cap-w authoritative)
- 판정: arm S 4/4 config graduation 미달 + base(all-11) 대비 paired NW-t 전부 음수 유의(-2.02~-2.51) → KILL, arm R 미착수.

핵심 결과가 "Boruta 선별이 도움이 안 되는 정도"가 아니라 "**base 대비 유의하게 손해**"라는 강한 음성이므로, 이 판정 자체의 약점을 적대적으로 검증한다.

## 제기한 약점 6건 + 분류

**W1 (pooled-panel 자기상관 → shadow-null 과대confirm) — PARTIAL ACCEPT.**
종목이 창 내 여러 달 반복 → effective n ≪ nominal n → 중요도 유의성 팽창(과대confirm). 그러나 방향: 과대confirm은 confirmed 집합을 all-11에 **가깝게** 만들어 arm S를 base로 수렴시킨다 → 음성 paired를 **약화**시키는 방향. 즉 헤드라인(Boruta가 손해)은 이 편향에 대해 보수적. 단 "어느 팩터가 살아남나"(방어형 편중)는 지속성(persistence) 아티팩트와 얽혀 있어 *기전 해석*엔 caveat. nmax=3000 서브샘플로 부분 완화(제거는 아님).

**W2 (Boruta 목적함수 ≠ authoritative 게이트) — ACCEPT (방법의 구조적 한계).**
Boruta target = 월내 z-scored forward-ret의 횡단 relevance(=rank-IC 계열). measurement-graduation §3에서 rank-IC는 **advisory**, PORT_t가 authoritative. Boruta는 advisory 기준으로 선별하는데, KR에서 IC→PORT_t 전이 벽이 확립됨. 즉 "all-relevant 선별"의 목적이 long-only cap-w 게이트와 구조적으로 어긋남 = 이 방법이 실패하는 정직한 구조적 이유(측정 결함 아님, 방법의 한계). 이 자체가 발견.

**W3 (RF in-sample 과적합) — REBUTTAL.**
shadow feature가 동일한 in-sample 과적합 기회를 갖는 permuted copy이므로 실팩터는 자기 그림자의 과적합을 이겨야 confirm. 게다가 배포는 strict walk-forward(confirmed → OOS 월). 과적합 두 겹 통제(shadow-null ∧ OOS). 음성의 동인 아님.

**W4 (confirmed 집합 불안정 turnover) — PARTIAL ACCEPT.**
집합 turnover(Jaccard) 0.32~0.38/semiannual — 매 재선별 ~1/3 교체. 그러나 포트 turnover_annual은 Boruta arm(9~10)이 base(11~14)보다 **낮음** — 소수 지속 방어군 집중으로 종목 churn 감소. → 음성은 거래비용 탓 아님(오히려 덜 매매). 집합 불안정은 해석 caveat이나 underperform의 원인 아님(구성·수익 문제).

**W5 (Boruta 하이퍼파라미터 단일) — PARTIAL ACCEPT.**
config 공간 사전등록 제약(≤6). Boruta strictness 축: looser(더 confirm) → base로 수렴(base도 1.66<2.95) / stricter(덜 confirm) → 방어 집중 심화 → 더 나쁨. 두 끝 모두 2.95 미달로 bracket. envelope 안 strictness 축에 대해 음성 robust. 단 다른 importance backend(ranger/extraTrees)·pValue는 미측정 — config-scoped 명시.

**W6 (prior-확인 편향 자기합리화) — 검출·기각.**
prior(return-derived 재조합=settled-negative)가 "arm S 실패"를 예측했고 실패함. 그러나 본 결과는 단순 "graduation 미달"(base도 미달)을 넘어 "**Boruta가 base보다 유의하게 손해**"라는 prior 밖의 신규 발견 + 특정 기전(방어형 과선별). 4/4 config 일관 + paired 유의. prior 패턴매칭 아닌 독립 증거. 단 기전 해석은 W1 caveat 하에 보류적으로 유지(과대주장 금지).

## 종합
- **REBUTTAL 1(W3) / PARTIAL 4(W1·W4·W5·W6) / ACCEPT 1(W2)**. verdict-change 없음.
- 헤드라인("Boruta all-relevant 선별은 KR long-only 팩터배분을 개선 못 하고 오히려 base 대비 유의 손해") = W1(보수적 방향)·W2(구조적 이유)·W3(과적합 통제)로 robust.
- caveat 명시: ① 자기상관 하 기전(방어 과선별) 해석은 지속성과 얽힘 ② config-scoped(nmax/ntree/maxRuns/backend 단일, 창 2·가중 2) ③ base 자체도 미졸업(substrate=screen-tier, R1/R2 정합) — Boruta는 그 위에서 추가로 악화.
- INV-7: 방향(family) 판결 아닌 경로(구성)-scoped. 부활신호 = importance backend/target을 PORT_t-정렬 기준으로 바꾼 선별(예: purged-CV IC or 직접 cap-w active 라벨) 재시도 시.
