# Self-Adversarial Challenge — alpha 구간 (WT-R20260829_002, v8.2)

by: alpha-research (opus) · 2026-08-29 · 대상 = `alpha_package.json` + `stage_artifacts/WT_R20260829_002/alpha_validation.json` (finalize 직전)
승계 원칙: `alpha_hypothesis.json` 의 mechanism / falsification / regime_scope 는 **재작성하지 않았다**(Charter 원칙 8). 아래 C6·C7 은 결함 지적이며 수정이 아니라 기록이다.

---

## C1 — 1급 판정이 문턱을 0.005 차로 비껴간 knife-edge 아닌가 (HIGH)

**제기**: `reject_if ①` 은 `|NW-t| < 2` 다. 실측 raw NW-t = **1.995**. 문턱을 0.005 차로 통과해 '기각' 이 나왔다. 창을 한 달만 늘리거나 유동성 자를 조금만 바꿔도 판정이 뒤집힌다면 이건 판정이 아니라 우연이다.

**판정: PARTIAL — 인정하되 판정은 유지**.
① 인정분: raw 축 단독으로는 knife-edge 가 맞다. 그래서 산출물에 raw 1.995 를 **그대로 노출**하고 "문턱을 0.005 차로 비껴간 것을 강도의 근거로 읽지 말라" 를 명시 필드(`identity_caveat`)로 박았다.
② 판정이 유지되는 이유는 raw 통계량이 **애초에 이 질문의 통계량이 아니기 때문**이다. 항등적으로 Δ(cell2−cell1) = (r_win) − (r_win − r_lose) = **r_lose**, 즉 패자 데실의 *총수익*이다. 그 raw 평균 +12.18%/yr 중 β 기여가 **+9.90%p (81%)** 이고 α 는 +2.28%p 뿐이다(β = 0.849). 설계가 β-통제 α 차 병기를 **의무**로 건 것이 정확히 이 자리이며, 그 값은 **t(α) = 0.557** 로 문턱에서 멀다. 두 기준이 갈리지 않는다(reject_if ① 의 "병기 일치" 조건 충족).
③ 잔여: 그럼에도 이것은 '효과 없음' 이 아니다 — `disposition_label = 미결(underpowered)`, β-통제 축 검정력 **22.5%**(ratio 0.430). 잔여 18회가 숏 축을 통계적으로 닫았다고 읽으면 안 된다.

## C2 — cell4 를 알파로 팔 위험 (settled-negative 재포장) (HIGH)

**제기**: cell4 PORT_t **+1.294** · β-통제 α **+5.14%/yr** · EW-유니버스 대비 **+1.426** (cap-w 보다 높다). 이 조합을 "형태를 고쳤더니 살아났다" 로 쓰면 DIST-AR-003/007/041 이 17건으로 소진한 경로를 한 번 더 도는 것이다.

**판정: ACCEPT — 반영 완료, 알파 청구 0건**.
- **무신호 대조가 닫는다**: cell4 vs 시총 상위 25종 cap-w(신호 미사용) = 차 **+4.08%/yr NW-t 0.751** · 상관 0.644 → `INDISTINGUISHABLE_FROM_NO_SIGNAL`. cell2 도 동일(+2.38%/yr, t 0.442). measurement-graduation §3 상 **screen-tier 등재 불가**이고, 산출물은 이를 `consequence` 로 명문화했다.
- **대조군 β 검증 통과**: 1.072(cap 1.00) / 1.026(cap 0.20). 1/20 의 홀딩월 라벨 오정렬(대조군 β 0.041)을 재발시키지 않았다 — 라벨을 시그널월 t 의 **다음 캘린더월(t+1)** 로 넘겼다.
- **DIST-AR-007 에스컬레이션 미발동**: 설계는 "cell4 가 통제를 통과한 양(+)이면 에스컬레이트" 였다. 통제를 통과하지 못했으므로 에스컬레이트하지 않는다. DIST 카드의 예측(비졸업)이 **맞았고**, 그것이 설계대로 '신호 회귀' 판정의 증거로 소비됐다.
- 보조 증거: OOS retention 근사 **−0.066**(<0.5 무조건 FAIL 구간) · P3(2020-2026) 활성수익 +1.4%/yr t 0.15 · rank-IC **0.0072**.

## C3 — EW-유니버스 대비가 cap-w 보다 높은 것을 '생존' 으로 읽는가 (MEDIUM)

**제기**: cell4 EW-유니버스 t **+1.426** > cap-w **+1.294**. 1/20 의 mom_only 는 EW-대비 −0.064 로 소멸했었다. "이번 신호는 다르다" 로 읽고 싶어지는 자리다.

**판정: REBUTTAL(방향 정정 포함)**.
- 사실: 두 신호가 다르다는 것 자체는 맞다(6-6 vs M02) — 설계의 [제3축 경고]가 사후 확증됐고 그 사실은 기록한다.
- 그러나 **EW-basis 는 t 배율기**다(실측 se_EW/se_capw 중앙 0.729 ⇒ t 약 ×1.37). 여기서 관측된 배율은 1.426/1.294 = **1.10** 으로 전형값보다 **작다**. 배율을 걷어내면 EW-대비는 cap-w 대비보다 **강하지 않다**. "벤치를 바꿨더니 살아났다" 는 서술은 성립하지 않으며, 산출물에 `ew_basis_caveat` 로 명기했다.
- `reject_if ④` 는 연언(EW-대비 소멸 **∧** OTHER tier 지배)이라 미발동이지만, **후항은 성립한다**(OTHER 91.2%). 연언 미충족을 "소형주 노출이 아니다" 로 읽지 않는다 — 그 판정은 무신호 대조가 이미 내렸다.

## C4 — 국면·지문 분석이 순환(사후 라벨) 아닌가 (HIGH)

**제기**: recovery 는 **실현** BM 수익으로 정의된다. 패자 데실은 고β다. 그러면 "상승월에 숏이 손해" 는 정의상 참이고, t −4.403 은 기전의 증거가 아니라 β 의 재진술이다.

**판정: PARTIAL — 두 겹의 통제로 방어, 잔여 인정**.
① **BM 수익 통제**: `short_contrib ~ BM_Ret + recovery` 에서 recovery 계수 **−0.0427/월 · t −2.367** 로 생존한다. 시장 방향을 통제해도 반등월 특이 손실이 남는다.
② **시장 방향 거의 고정한 대조**: expansion(bm **+59.5%/yr**) vs recovery(bm **+62.8%/yr**) — BM 수준이 거의 같은데 패자 데실 수익은 **+34.9% vs +94.3% (2.7배)**, 승자는 +67.6% vs +80.7%(1.2배). 비대칭이 패자 쪽에만 있다.
③ 잔여: 라벨 자체가 사후이며 거래 불가다. 그래서 (i) 1차 판정은 무조건부 4셀 대비로 두었고 (ii) 이 라벨은 **어떤 셀의 비중에도 진입하지 않았다**(S0/S1 오버레이 금지 준수 — 산출물 `regime_definition.method` 에 명시).

## C5 — 4셀 공통 엔진이 canonical 경로 밖 자체합성 아닌가 (HIGH · measurement-graduation §1)

**제기**: `canonical_screen_bt()` 는 고정 top-N 롱온리다. 데실(가변 35종)과 롱숏 2셀은 그 함수로 표현 불가라 자체 엔진을 썼다. 이건 §1 이 금지한 proxy 손계산 아닌가.

**판정: REBUTTAL — 양성 대조로 실증**.
- cell4(top-25 롱온리)를 **같은 입력으로 `canonical_screen_bt(top_n=25)` 와 대조**: `max|Δret_net| = 0.000e+00` · `|ΔPORT_t| = 0.000e+00` · 259/259 개월 일치(`parity.verdict = PARITY_EXACT`).
- 즉 본 엔진은 canonical 경로의 **롱숏·가변데실 확장**이며, 확장분 외에는 비트 단위로 동일하다. 성능수치는 전부 계약 `build_benchmark_compare()` 를 경유하고 `metric_type="canonical_screen"` 을 단다.
- 이 양성 대조가 없었다면 셀 1·2·3 수치를 canonical 급으로 인용할 수 없었다 — "검사기는 양방향으로 재라" 규약의 적용점이다.

## C6 — 승계 산출물의 계약 표면 분열 2건 (기록 의무, 수정 아님)

**제기**: `alpha_hypothesis.json` 을 그대로 실으면 하류 계약이 깨진다.

**판정: 기록 + 형식 전사만**(내용 재작성 0 — Charter 원칙 8).
1. **falsification 형상**: 설계는 `{observable, field_dictionary_refs, reject_if}` 객체인데 schema `#/definitions/ast_hypothesis` 는 **필드 지목 객체배열**을 요구한다. 내용을 바꾸지 않고 리프별로 분해 전사했다(원문 정본 = `alpha_hypothesis.json`).
2. **필드 참조 표기**: 설계의 `A1_RAWDATA_OHLCVS_daily:Ret`(group:field 형)은 `ast_spec_gate.sh` 가 **block** 한다 — 게이트의 field_dictionary 는 group_id 만 받는다(실측: 4/4 전건 block). `field="A1_RAWDATA_OHLCVS_daily"` + `field_column="Ret"` 로 전사해 통과시켰다. **게이트와 설계 문서의 표기 규약이 갈려 있다** — 후속 수리 대상.
3. **AST 방언 분열(신규 발견)**: schema 는 `args` 배열을, 정적검증기 `02_Infrastructure/ast/ast_verify.py` 는 `children` + 명명 파라미터(`k`/`window`)를 요구한다. schema 방언만 실었더니 검증기가 **리프 0개를 순회**하고 `노드 형상 오류(비 dict): 6` 을 냈다 — 즉 **PIT 정적검증이 실행되지 않은 채 게이트를 통과**했다. 두 방언을 함께 실어 실제 순회가 일어나게 했고(재실행 결과 게이트 출력 `{}` = 무경고 통과), 이 분열을 여기 기록한다. **빈 검증은 PASS 가 아니다**(ALB-007).

## C7 — 축 B 효과크기 앵커가 자기충족적이지 않은가 (MEDIUM)

**제기**: 축 B 의 implied effect 를 **IS-only(전반 86개월) 실측**으로 잡았다. 관측으로 바를 만들면 바가 t 검정의 재진술로 퇴화한다(required_effect_size.R 의 자기경고).

**판정: PARTIAL — 대안 부재를 명시**.
- IM2013 은 집중 형태(데실→top-25)의 효과크기를 제공하지 않는다. 논문 앵커가 없는 축에 논문 숫자를 지어내는 것이 더 큰 위반이므로, **출처를 `implied_source` 필드에 그대로 적고**(IS-only 86개월) ratio 0.571 / 기대 t 1.600 / 검정력 **35.9%** 3종을 병기했다.
- 퇴화 여부 점검: 바(MDE80 = 2.88%/yr)가 관측 효과(1.43%/yr)의 2.0배라 t 검정의 단순 재진술은 아니다(재진술이면 배율이 nw_inflation 수준인 ~1.0 이어야 한다).
- 축 A 는 논문 앵커가 있으므로(IM2013 Table 1 Down 포트 CAPM α −4.94%/yr) 그쪽은 이 문제에서 자유롭다.

## C8 — cell1 이 기저와 bit-parity 가 아니다 (MEDIUM)

**제기**: cell1 PORT_t −1.120 vs 기저 보고 −1.291. "기저 재현" 이라 부를 자격이 있나.

**판정: PARTIAL — 구간 포함 실증 + 라벨**.
- 차이 원인 3종: (a) 유동성필터 추가(기저는 `paper_faithful` = 미적용) (b) 벤치(cap-w 유니버스 프록시 vs KOSPI200 지수) (c) 일간 하네스 vs 월간 패널.
- 되돌림 4변형 실측: **−1.120 / −1.152 / −1.465 / −1.430** — 기저 −1.291 이 구간 안에 있다.
- 셋 다 **4셀에 공통**이라 축 대비에서 상쇄된다. 그래도 산출물에 "기저 수치를 인용할 때는 기저 산출물을 인용하라" 를 challenge_flag 로 남겼다.

---

## 합리화 어휘 자가 점검

"미미 / 관행적 / 실무적 / 보수적이면 OK / 대부분 결과 동일 / 이미 반영되어 있었을 것" — **사용 0건**. auto RE-VIEW 비발동.
특히 다음 두 자리에서 합리화 유혹이 있었고 대신 수치를 적었다: ① raw NW-t 1.995 를 "사실상 2" 로 쓰지 않고 knife-edge 로 명시 ② cell4 양(+)을 "형태 교정 효과" 로 쓰지 않고 무신호 대조 결과를 판정으로 채택.

## Q-Lead escalate trigger 점검

- HIGH severity ≥ 5 → **미발동** (HIGH 4: C1·C2·C4·C5 — 전부 반영·실증 완료)
- AX axiom hard FAIL ≥ 3 → **미발동**
- PIT C1(lookahead) 위반 → **미발동** (`detect_lookahead` CLEAN 0위반 · `ast_verify` 순회 후 무경고)

## 종합

ACCEPT 1 · PARTIAL 5 · REBUTTAL 2. 설계 유지, 판정 유지.
**단, 하류 소비자에게 넘기는 경고 1건**: 본 라운드는 risk/optimizer/forge 스폰 근거를 만들지 못했다 — 무신호 대조 구별불가 + 축 A 기각 + 축 B 미결. 등급은 선언하지 않는다(권위 = `essence_score.R` 하나).
