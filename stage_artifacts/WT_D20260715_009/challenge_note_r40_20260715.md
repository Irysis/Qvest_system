# Self-Adversarial Challenge — R40 insider SAFE 청산 검열-스트레스 (WT-D20260715_009 / FQ-053)

**대상 산출**: R40 검열편향 정량 — R38 "no hangover"(청산≠위험재상승)의 검열-조정 강건성.
**최종 verdict**: `no_hangover_horizon_limited` — 검열편향 immaterial(R38 caveat 기각) + protection은 단기(directional).
**규약**: Charter §8 No Silent Override. 각 concern ACCEPT/PARTIAL/REBUTTAL 분류 + 근거 + 합리화 자기검증.

본 challenge는 finalize 직전 **자기 산출을 적대적으로** 검증했고, 실제로 **verdict를 뒤집는 아티팩트를 자가검거**했다(concern 1). 이는 self-adversarial 프로세스가 형식이 아니라 작동함을 실증한다.

---

## Concern 1 [HIGH → ACCEPT, 수정 완료] — terminal-truncation을 검열로 오분류 (verdict 반전 catch)

**제기**: 초기 실행에서 MID "CENSORED" 27건 중 **25건이 j1=202605**에 집중. uni 패널은 hold_ym=202604에서 종료 → 202604의 모든 flag-ON event는 j1(202605)이 관측창 밖이라 자동으로 "패널 이탈(CENSORED)"로 분류됨. 이는 종목이 투자가능성에서 탈락한 informative censoring이 아니라 **관측창 종료에 의한 right-truncation**(연구 종료 시점의 표준 우측검열, 비정보성). 게다가 202605는 하락월이라 이들 return이 나빠(tail 40.7%) 초기 verdict를 `no_hangover_not_robust_both`(R38 반전)로 오도했다.

**분류**: **ACCEPT** (명백한 방법 결함). 초기 결론은 아티팩트 산물.

**처리**: `MAX_YM` 가드 도입 — j1>MAX_YM인 ON-event를 `right_truncated`로 분리(ALL 67·MID 25), census/차등검열/다중월 궤적에서 제외. 재실행 후:
- MID 검열 = **27→2건** (진성 검열: A008930 201008·A073240 201005 distress). ALL = 6건.
- 진성폐지(delisted_hard) = **0건** (21년 패널 전체).
- 차등검열: ON 이탈률 2.744%→**0.209%**, OFF 0.703%→0.107% (diff p 3.3e-8→**0.757 비유의**).
- verdict `no_hangover_not_robust_both` → **`no_hangover_horizon_limited`**.

**합리화 자기검증**: "202605를 그냥 두어도 대세 동일" 같은 회피 없이 명시 가드로 격리. 우측검열≠정보검열 구분은 생존분석 표준.

---

## Concern 2 [MEDIUM → PARTIAL] — 차등 이탈률 잔여 방향성 (composition effect)

**제기**: 수정 후에도 MID SAFE(ON) 이탈률 0.209% > OFF 0.107% (약 2배, 방향은 adverse). SAFE는 insider-covered 종목 = 필링 있는 mid/small 종목에 편중 → 구조적으로 유동성 경계에 가까워 패널 회전 높음. 즉 SAFE 신호가 이탈을 예측하는 게 아니라 SAFE 종목군의 composition이 그럴 수 있음. 검열이 no-hangover를 낙관편향시킬 잔여 여지?

**분류**: **PARTIAL** (방향 인정, 크기·유의성 부인).

**근거**: (a) 절대율 0.2% vs 0.1% = name-month당 매우 희소, (b) **prop.test p=0.757 비유의**(diff +0.10pp), (c) 폐지율 양측 0%. composition 설명은 타당하나 **크기가 immaterial** — 2건이 115-건 EXIT 분포를 못 흔든다(concern 4 참조). 보고서에 "directional adverse but non-significant·composition-consistent"로 명시 라벨. **낙관편향의 실질적 여지 없음**(worst-case wipeout까지 견고, concern 4).

**합리화 자기검증**: "미미하니 OK"로 넘기지 않고 p-value·절대율·worst-case 3중으로 정량 기각. verdict 로직도 절대율 threshold→**유의성(p) 기준**으로 교정(false-alarm leave_favorable=FALSE 제거).

---

## Concern 3 [MEDIUM → REBUTTAL(부분)] — 다중월 "지연 hangover"는 유의하지 않다

**제기**: P1 다중월 궤적에서 h=2 tail 12.3%·h=3 10.5% (OFF 7.9% 초과), paired-t +1.89→+1.33→-0.03→-1.65. tail-threshold 플래그(>OFF×1.25)는 발화하나 이를 "지연 hangover 확인"으로 읽으면 과대주장 — **paired-t는 전 구간 |t|<2 (비유의)**.

**분류**: **REBUTTAL(방법)** — 나는 "유의 지연 hangover"를 주장하지 **않는다**. verdict는 `horizon_limited`(단기)이지 `horizon_limited_sig`(유의)가 아니다.

**근거 + 처리**: verdict 로직에 `survivor_sig_ok`(paired-t<-2 여부) 분리 도입. h2/h3 모두 비유의 → **directional only**로 보고. 해석: protection이 h=0-1에 집중되고 h2-3에 baseline 복귀 = R38 자신의 "SAFE premium은 SUSTAIN-cluster 현상" 기전과 **정합**. R38이 h=0 snapshot의 낮은 tail을 "protection 점착(무기한)"으로 과독한 것을 R40이 "~1개월 transient"로 교정. 이는 검열축(chartered)과 **독립**한 별개 refine.

**합리화 자기검증**: "tail이 올랐으니 hangover"의 유혹을 유의성 게이트로 차단. non-significant를 significant로 승격하지 않음(answer-principle 7 불확실성 명시).

---

## Concern 4 [MEDIUM → PARTIAL] — worst-case 강건성이 "검열 n=2"에 기인 (trivially robust?)

**제기**: wipeout(-100%) 대입해도 EXIT tail 6.0%<OFF 7.9%로 risk-sticky 유지 — 그러나 이는 검열종목이 2건뿐이라 115-건 분포를 못 움직이기 때문. "worst-case 견고"가 결론의 강점이 아니라 표본 희소의 부산물 아닌가?

**분류**: **PARTIAL** — 인정하되, 그것이 **바로 chartered 질문의 답**이다.

**근거**: R38 caveat는 "flag-off 동시 폐지/유동성붕괴 종목이 검열되어 no-hangover가 낙관"이었다. R40이 정량한 답 = **그런 종목이 거의 없다**(MID 2건·폐지 0). 검열이 immaterial한 이유가 "검열이 드물어서"인 것은 약점이 아니라 **답의 실체**. worst-case는 "만약 있었다면"의 상한(2건에 -100% 대입)을 보여 **상한조차 무해**함을 입증. 단 한계 명시: 이 결론은 **KR 대형/중형(mid-tercile) 투자가능 유니버스 조건부** — small-cap/비투자가능 영역의 폐지는 애초 uni 밖(부실 tripwire 소관, P3 경계).

**합리화 자기검증**: "표본 작아서 안전"을 결론으로 포장하지 않고, 검열 희소성 자체를 1급 실측(census)으로 보고 + 조건부(투자가능) 명시.

---

## Concern 5 [LOW → ACCEPT, immaterial] — rmon 재구성 vs uni 멤버십 convention 불일치

**제기**: 잔여 MID other_filter 1건(A008930 201008)은 rmon 동월 기준 index-내·유동적인데 uni가 제외 — uni(T-1 convention)와 내 rmon(동월) 멤버십 판정 불일치 가능. `other_filter` 라벨의 정밀도 한계.

**분류**: **ACCEPT** (known limitation, immaterial). 1건 규모라 census/verdict 무영향. 검열 방향 판정은 이 1건과 무관(전체 2건, 폐지 0). 보고서에 라벨 한계 명시.

---

## escalation 판정
- HIGH severity: concern 1(수정완료)·2(비유의로 완화). **잔여 HIGH open = 0** → Q-Lead auto-escalate trigger(HIGH≥5) 미해당.
- AX axiom hard FAIL: 없음. PIT C1(lockbox·lookahead): base=production clean T-1 상속, 검열은 forward 멤버십(미래참조 아님) → 위반 없음.
- **자본 주장 없음**(monitoring 진단). book_state/05_Production/outputs.ramp 무변경.

## 종합
self-adversarial이 verdict를 뒤집는 아티팩트(concern 1)를 검거 → 최종 결론은 R38 caveat를 **정량 기각**(검열 immaterial)하되 별개 refine(protection 단기·directional)을 정직 추가. 과대주장(반전)도 과소주장(caveat 무시)도 아닌 calibrated 판정.
