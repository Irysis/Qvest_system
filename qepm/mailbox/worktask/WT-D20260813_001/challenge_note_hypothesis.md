# Self-Adversarial Challenge — WT-D20260813_001 가설설계 구간 (alpha-hypothesis, v8.2 축소판)

발행: 2026-08-13 · 대상: `alpha_hypothesis.json` finalize 직전 · 축: 설계 축 4종만 (실측 축은 alpha-research 이후 소관)

## C-1. 메커니즘이 사후 서술(story-fitting)인가 — **PARTIAL**

**제기**: '개인 salience 복권수요 + 기관 mandate 회피 + 파생 부재' 기전은 q90 secondary 가 좋아 보인 **뒤에** 조립되었다. 결과를 보고 이야기를 맞춘 전형적 패턴 아닌가.

**판정 PARTIAL**: 기전 서사의 *조립 시점*은 사후가 맞다 — 이 점은 부정하지 않고 challenge_flags [사후선택 통제] 에 명시했다. 단 기전의 **핵심 수량 주장은 결과 관측과 독립 경로로 선행 실측**되어 있다: R32 의 cor(왜도기울기, 중앙값−평균 gap) = −0.728 은 320종 전수의 직접 측정이고, R33 의 Q1 프로파일(중앙값 −15.68% vs 평균 +10.54%·왜도 1.027)은 원천 재구축 독립 경로에서 R31 과 0.3%p 안쪽 일치다. 즉 '평균은 꼬리가 견인한다' 는 기전의 전반부는 q90 성과 관측 없이도 성립하는 실측이다. 사후 조립분은 후반부(누가 왜 안 지우나)이며, 그 검증을 위해 성과-독립 부수관측 F1~F3 을 반증 조건으로 박았다. 잔여 리스크: R32/R33 도 같은 세션·같은 패널 계열이라 완전 독립 아님 — alpha_hypothesis.json 승계 한정 라벨에 기재.

## C-2. 반증 조건이 성과 동어반복으로 위장됐나 — **REBUTTAL (일부 ACCEPT 반영)**

**제기**: F1(tail-hit rate)은 결국 '예측이 잘 맞나' 이므로 성과의 재포장 아닌가. tail 을 맞히면 top-N 평균도 대개 좋을 것이므로 PORT_t 와 사실상 같은 축이다.

**판정 REBUTTAL**: F1 과 포트 성과는 분리 가능한 축이다 — arm B 자체가 그 반례를 실측했다: q10/q50 은 rank-IC(예측 정확도 계열)가 **더 높은데** 실현 SR 은 더 낮았다. 즉 '맞히는 것' 과 '버는 것' 이 이 문제에서 체계적으로 갈린다는 것이 본 WT 의 출발 관측이고, F1 은 그 갈림의 어느 쪽이 죽는지를 성과 지표 없이 판별한다(꼬리는 맞히는데 못 벌면 소비 경로 기각 / 못 맞히는데 벌면 β 아티팩트 의심 → C-4 flag). **ACCEPT 반영분**: 초안의 F1 은 문턱이 없었다 — paired one-sided t ≥ 2.0 사전 문턱을 reject_if 에 고정했다. 또한 F1~F3 이 field_dictionary 리프(A1/FDB-B2/A4/A9)로 계산 가능함을 확인해 refs 를 기재했다.

## C-3. 국면 경계가 기전에서 도출됐나, 사후 데이터 관찰인가 — **PARTIAL**

**제기**: 'crisis 약화' 는 q90 arm MDD 67%(4 arm 최악)를 보고 거꾸로 쓴 것 아닌가.

**판정 PARTIAL**: crisis 경계의 도출 자체는 기전 전건에서 나온다 — 수익원이 idio 상방 점프이므로 공통요인·청산이 지배하는 국면에서 원천이 마르고 노출은 최악이 된다는 것은 관찰 없이도 따라온다. 단 MDD 67% 관찰이 서술 시점에 이미 알려져 있었다는 사실은 지울 수 없으므로, boundary_rationale 에 '도출 근거가 아니라 정합 확인' 으로 지위를 명시 강등했다. overheat 경계는 순수 기전 도출(선반영에 의한 연결 단절)이며 대응 실측이 아직 없다 — 측정 단계에서 국면 분해로 확인해야 할 예측이고, FQ-236(매크로 조건부 비대칭, UNCLAIMED)과 접점이 있음을 기록한다.

## C-4. settled-negative 의 재포장인가 — **ACCEPT (재포장 아님, 근거 실측)**

**제기**: 분위/꼬리 계열은 이미 여러 번 측정되지 않았나 — Tail Quantile Risk(FAIL), QRF→CVaR(MARGINAL), DIST-QPM-003.

**판정 ACCEPT(비-재포장 확인)**: hypothesis_index 전수 키워드 lookup(hits 7) 결과, 기존 2건은 모두 **하방** 꼬리를 리스크로 소비하는 축(crash_protection / CVaR 최소화)이고 본 WT 는 **상방** 분위를 예측 표적으로 소비하는 축 — 방향과 소비 형태가 모두 다르다. DIST-QPM-003 은 quality single-signal 실패로 직접 충돌 없음(R32 notable 의 '측정 형태 가능성' 은 본 WT 미검증 파생 함의로만 기재). arm B 의 q50 NOT_SUPPORTED 는 본 WT 와 같은 family 의 config-scoped negative 이나, q90 은 그 라운드에서 primary 로 검정된 적이 없다 — 재포장이 아니라 미검정 축의 최초 정면 검증이다.

## C-5. (추가 자가 제기) 설계 자체가 '거의 확실한 negative' 를 향하고 있지 않나 — **ACCEPT (정직 기재로 해소)**

**제기**: 관찰 효과크기(total SR +0.0022, PORT_t +0.31)가 지지 문턱(paired t ≥ +2.0)에 한참 못 미치므로, 동일 config 재실행은 NOT_SUPPORTED 가 사전에 예견된다. 이럴 거면 왜 도는가.

**판정 ACCEPT**: 사실이고, 숨기지 않고 selected.hypothesis_description 과 challenge_flags [동일-config 재실행의 정보가치 한계] 에 사전 기대를 명시했다. 본 라운드의 가치는 (a) 4-arm 사후관찰을 정식 사전등록 판정으로 전환해 축을 **깨끗이** 닫거나 열고, (b) F1~F3 기전 부수관측을 최초 측정하며, (c) 음성 대조(절사평균)로 꼬리 기전의 방향 판별을 얻는 것이다 — negative 로 닫혀도 FQ-237/arm C/C2-expectile 라우팅이 next_probe 로 사전 배선되어 있다(INV-7: family 판결 확대 금지).

---

**합리화 어휘 자가검사**: answer-principles 금칙 계열(축소·관행 합리화 어휘) 미사용 확인. 회피 표현 grep 대상어는 정직 라벨("검증 안 됨"/"미검증") 형태로만 사용.
**결론**: 5건 제기 → ACCEPT 2 · PARTIAL 2 · REBUTTAL 1(부분 ACCEPT 반영). 전부 alpha_hypothesis.json 본문에 반영 완료. finalize 승인.
