# Self-Adversarial Challenge — WT-R20260829_001 alpha 구간 (alpha-research)

Charter §8 No Silent Override. finalize 직전 수행. 분류 = ACCEPT / PARTIAL / REBUTTAL.
합리화 어휘 자동탐지 대상: "미미 / 관행적 / 실무적 / 보수적이면 OK / 대부분 결과 동일".

---

## ① 가장 약한 가정 — "min-rank 교집합"이 CJL1996 의 독립 2-way 정렬과 같은가 — **REBUTTAL**

**자기 비평**: 논문은 9셀을 만들고 셀 내 EW 를 잡는다. 나는 joint-top 셀 안에서 `min(pm, ps)` 로
상위 25 를 잘랐다. 이 절단이 논문에 없는 자유도이며, 사실상 연속 composite 를 몰래 들여온 것 아닌가.

**반박 근거**:
- **집합 동일성(수학)**: `min(a,b) ≥ 2/3 ⟺ a ≥ 2/3 ∧ b ≥ 2/3`. 즉 min 의 2/3 상위준위집합은
  독립 3분위 교집합과 **정확히 같은 집합**이다. 절단은 셀을 정의하는 데 쓰이지 않고, 셀 인구가
  25 를 넘는 달에만 순서를 준다.
- **합산과 다르다는 것이 요점**: WT 가 금지한 z-합산은 한 축의 강한 값이 다른 축의 약한 값을 **상쇄**한다.
  min 은 정의상 상쇄가 불가능하다(약한 축이 항상 지배). DIST-AR-007 이 소진한 구성과 갈라지는 지점이
  여기다.
- **정량 실측 3축**: (a) 배포 arm 은 셀 밖을 NA 로 두어 셀 인구 < 25 인 50/260 달에 25종 미만을 보유한다 —
  연속 composite 였다면 항상 25종을 채웠을 것이다. (b) zsum_control(실제 합산)을 별도 arm 으로 돌려
  PORT_t 1.014 vs joint2way 0.504 로 **다른 수치**임을 실증했다. (c) 두 arm 의 cor(active) 0.871 < 1.
- **L-code**: DIST-AR-007(다축 composite 내 모멘텀 성분 소진) — 본 구성은 그 목록에 없다.
- **문헌**: CJL1996 Section III.A p.12 (독립 3×3 정렬).

**남는 자유도**: 절단 규칙(min-rank) 자체는 논문에 없다. `paper_assumption_broken` 에 적지 않고
`construction.within_cell_truncation` 에 명시했다. 대안(SUE 순 절단·가격 순 절단)은 시험하지 않았다 —
시험했다면 method shopping 이 됐을 것이다.

---

## ② PIT 취약점 — C01_SUE same-day 허용 — **ACCEPT**

**자기 비평**: registry 가 명시한 `known_discrepancy`(코드 강제점 `Date <= sig_d`)를 알고도
"lag1 스트레스가 음성이니 괜찮다"로 넘기려 했다. 그것이 정확히 금지된 합리화 형태다.

**조치(ACCEPT)**:
- 정적 검증기 `ast_verify.py` 를 **실제로 돌렸고** verdict = `FAIL_LOOKAHEAD`(C01_SUE 4/4 occurrence,
  contract_failures 0, M02 위반 0).
- `self_pit_check.verdict` 를 `clean` → **`fail_lookahead_suspected`** 로 내렸다. 실증(lag1
  inflation_ratio 0.768 < 1)은 기록하되 **정적 판정을 덮는 근거로 쓰지 않는다**.
- 처분 명시: 본 라운드 결론은 이 의심과 **독립**이다(성과가 이미 음성이므로 PIT 를 더 엄히 걸면
  같은 방향으로만 움직인다). 그러나 같은 리프로 **양성** 결과가 나오는 라운드에서는 차단 사유다.

---

## ③ 과적합 — 5개 arm 을 돌리고 최고를 골랐나 — **REBUTTAL**

**자기 비평**: arm 5개면 DSR 게이트 대상 sweep 아닌가.

**반박 근거**:
- 배포안은 **착수 전** WT 사전등록이 `joint2way` 로 고정했다(request.json + alpha_hypothesis.json).
  나머지 4개는 argmax 후보가 아니라 **사전 지정된 대조군**이다: mom_only/sue_only = WT 가 병기를
  명령한 증분 분모, zsum_control = 금지 구성이 실제로 다른지 재는 대조, k200bp = 논문 NYSE-only
  breakpoint 의 KR 대응 강건성.
- **결정적 증거**: 만약 argmax 로 골랐다면 `mom_only`(PORT_t 1.224)를 배포안이라 했을 것이다.
  나는 그것보다 낮은 `joint2way`(0.504)를 배포안으로 유지했고, 그 격차(-3.08%/yr)를 **판정을 뒤집는
  근거로** 보고했다. sweep 이었다면 이 숫자가 나올 수 없다.
- 규범: measurement-graduation §3 — `selection_type="chain"`, DSR 은 진단 산출(0.825)이며 게이트 아님.
  n_trials=5 를 기록해 사후 감사 가능성을 남겼다.

---

## ④ short-leg / decay risk — **PARTIAL**

**자기 비평**: 부기간 t 가 2.14 / −1.14 / −0.39 다. 알파가 전부 2005~2014 에 있고 이후 소멸한다.
이걸 "전기간 PORT_t 0.504" 한 줄로 덮으면 decay 를 숨기는 것이다.

**조치(PARTIAL)**:
- `subperiod_stability` = 1/3 로 기록(3개 창 중 1개만 양의 NW-t). 진단 필드에 노출.
- dual-basis 가 같은 방향을 가리킨다: EW-유니버스 벤치 대비 `post2017_t_nw_lag3` = **−0.395**,
  `oos_retention_approx` = **−2.32**.
- 다만 이 decay 는 **본 라운드의 판정 근거가 아니다** — 판정은 T2 powered null 이 이미 확정했다.
  decay 는 "설령 T1 이 통과했더라도 자본 층에 못 갔을 것"이라는 부가 정보다.

---

## ⑤ 기전 부수관측(T4)의 교란 — **ACCEPT**

**자기 비평**: T4 가 t 19/17/14 로 강하게 통과했다. 이걸 "기전 확인됨"으로 쓰고 싶었다.
그러나 joint-top 은 **SUE 로 선택된 집합**이고 C02/C03/C04 는 SUE 와 상관된 개정 지표다.
t 시점 수준을 통제하지 않았으므로 **선택 변수의 지속**과 **새 상향 개정**이 분리되지 않는다.

**조치(ACCEPT)**: 패키지에 "기전 **확증** 근거로 인용 금지 — 사전등록 방향(부재 시 기각)으로만 유효"를
명시했다. 그리고 결정을 T2 로 넘겼다: 개정이 실제로 뒤따라와도 **가격 축 통제 후 초과수익으로
전이되지 않는다**(T2 powered null).

---

## ⑥ 판정 라벨 오용 — "효과 없음" 과 "미결" 의 혼동 — **ACCEPT**

**자기 비평**: T1 이 t=1.291 로 비유의다. 이를 "가격모멘텀이 KR 에서 작동 안 한다"로 읽으면 오류다 —
검정력이 45.5% 밖에 안 되므로 그 구간의 비유의는 **미결**이다.

**조치(ACCEPT)**: 두 검정에 **서로 다른 처분 라벨**을 붙였다.
- T1 → `FAIL_AS_PREREGISTERED` + `disposition_label: 미결(underpowered)` (ratio 0.6597 / 기대 t 1.848 / 검정력 45.5%)
- T2 → `REJECTED (powered null)` (ratio 1.9590 / 기대 t 5.488 / 검정력 100%)
그리고 **설계 전체의 처분은 T2 가 확정**한다고 명시했다 — T1 의 미결성이 설계를 되살리지 않는다.
반대로, T1 의 미결성 때문에 "가격모멘텀 재료 자체가 죽었다"고 선언하지도 않았다(다음 probe 로 남김).

---

## ⑦ 증분 방향의 자기기만 — **ACCEPT (가장 중요한 자기 비평)**

**자기 비평**: WT 는 "이익 축 단독 대비 2-way 의 증분"을 명령했다. 그 값은 **+4.91%/yr, NW-t 2.00** 으로
양수다. 이것만 보고하면 "2-way 가 증분을 냈다"는 결론이 나온다. 그런데 그 양수는 분모(`sue_only`)의
알파가 **−1.15%/yr 로 음수**이기 때문에 생긴 것이다. 낮은 기준선을 넘은 것을 성취로 보고하는 것은
자기기만이다.

**조치(ACCEPT)**: 세 방향 증분을 **전부** 병기했다.
- vs sue_only: **+4.91%/yr** (t +2.00)  ← WT 가 명령한 값
- vs mom_only: **−3.08%/yr** (t −1.43)  ← **결정에 걸리는 값**
- vs zsum_control: −2.13%/yr (t −1.27)
그리고 "이 강화 시도가 묻는 것은 '기저(가격모멘텀)에 이익 축을 더하면 나아지는가' 이고 답은
**아니오**"라고 명시했다. 배제형 설계의 이득을 '잔류' 가 아니라 '대체' 대비로 재라는 규범
(measurement-graduation, WT-D20260822_010 소급무효 선례)의 같은 유형이다.

---

## ⑧ 계기 결함 — 무신호 대조 1차 산출 — **ACCEPT**

**자기 비평**: p3 1차 산출에서 대조군 beta 가 **0.041** 이었다. 시총 상위 25 cap-w 포트가 벤치와
무상관일 수 없다. 그런데 verdict(`INDISTINGUISHABLE_FROM_NO_SIGNAL`)가 내가 기대한 방향이라 그대로
넘길 뻔했다 — **"경고 0 을 보고 안심하는" 것의 거울상: 원하는 답이 나와서 계기를 안 본 것**.

**조치(ACCEPT)**: 지문을 추적해 결함을 특정했다 — `canonical_screen_bt` 의 `period_returns$date` 는
**신호월 t** 이고 `ret_net` 은 t+1 실현인데, `build_no_signal_control` 은 그 라벨을 **실현 캘린더월**로
해석한다. 홀딩월(t+1) 라벨로 재호출해 수리(대조군 beta 0.041 → **1.026**). 1차 값은 폐기했고 패키지의
값은 수리판이다. 수리 후에도 verdict 는 동일하나 **같은 결론에 도달한 경로가 다르다**.

---

## ⑨ 합리화 어휘 자기검사 — **PASS**

금칙어 스캔: "미미" 0 · "관행적" 0 · "실무적" 0 · "보수적이면 괜찮다" 0 · "대부분 결과 동일" 0 ·
"이미 반영되어 있었을 것" 0 · "백테스트 기간이 충분히 길어서 상쇄" 0.
"보수" 는 3회 등장하나 전부 **검증기의 보수 판정 규칙 서술**(`+1d 보수 fail-closed`)과
**skip 21일이 5일보다 보수적**이라는 사실 서술이며, 위반을 정당화하는 용법이 아니다 —
후자는 그 문장에서 곧바로 "그 자체가 다른 신호다"로 이어져 면제를 주지 않는다.

---

## ⑩ 역할 경계 자기검사 — **PASS**

공분산 추정 0 · target weights 제안 0 · 사전 최적화 0 · 오버레이 적용 0(S0/S1 금지) · 등급 선언 0.
`canonical_screen_bt` 의 top-N EW 는 고정 규격 스크리닝(계약이 명시)이지 비중 결정이 아니다.
승계분(mechanism / falsification / regime_scope) 재작성 0 — `falsification` 만 schema 요구 형태(객체배열)로
옮겨 담고 원문을 `falsification_source_verbatim` 에 보존했다.

---

## Q-Lead escalate 판정

**자동 escalate trigger 미해당**: HIGH severity ≥5 아님 · AX axiom hard FAIL ≥3 아님 ·
PIT C1(lookahead) **위반 확정** 아님(정적 의심 1건, 실증 음성).

**단, 수동 escalate 권고 2건**:
1. **하류 진행 여부** — 사전등록 1급 실패 + 역방향 powered null + 무신호 대조 구별 불가 3중.
   risk/optimizer 스폰은 이미 음성인 신호에 Σ 와 weight 를 붙이는 일이 된다. 강화 원장 attempt 1/20 을
   음성 마감하고 `next_probes` 로 attempt 2 를 여는 것을 권고.
2. **하네스 결함 2건 보고**(alpha 소관 밖):
   (a) `schema.json` ast_node 평문 스칼라 ↔ `ast_verify.py` `{"const":x}` 방언 분열 — 임계값 상수를
       쓰는 AST 는 두 계층을 동시에 만족할 수 없다(ALB-005 유형).
   (b) `build_no_signal_control(months=)` 이 `canonical_screen_bt$period_returns$date`(신호월)를
       실현 캘린더월로 해석 — 호출부가 1개월 어긋나기 쉽다. 계약 주석 또는 인자 검증 권고.
