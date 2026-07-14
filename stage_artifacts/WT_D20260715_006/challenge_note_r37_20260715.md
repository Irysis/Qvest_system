# Self-Adversarial Challenge — R37 insider mega-tier(TOP30) thinness 진단 (WT-D20260715_006 / FQ-051)

**규약** (v8.2 Codex Round 대체 · Opus 4.8 native adversarial): finalize 직전 산출물을 스스로 적대 검증. 각 concern ACCEPT/PARTIAL/REBUTTAL 분류 + 근거 + self-rationalization 자기검증. Charter §8 No Silent Override.

**대상**: verdict.json (R37 power vs signal-death 판별). **면 = monitoring (non-capital)** — 자본 게이트 무관, cap-tier 신뢰 라벨 진단.

---

## Concern 1 — 효과크기 추정 불확실 (task 지정 ①)
**적대 제기**: power 계산이 "TOP30 관측 효과 3.8%/yr"와 그 SE에 전적으로 의존한다. TOP30 flag 2341개는 종목-월이지 독립관측 아님(같은 월 다수 종목 = 클러스터). 관측 효과·SE가 부정확하면 power 결론(P(mid효과 검출)=1.0)도 부정확. bootstrap CI[−1.9%, +9.7%]가 넓다 — 3.8% 점추정에 기댄 판정 아닌가?

**분류: PARTIAL**
- **인정**: 점추정 3.8%의 CI는 넓다([−1.9%, +9.7%]). power 곡선의 관측점 위치는 불확실. 종목-월 클러스터링은 NW-lag3(월별 gap 시계열)로 시간축은 흡수하나 월내 횡단 클러스터는 gap을 월별로 접어 완화(월 1관측화).
- **반박 근거**: **핵심 판정은 점추정에 의존하지 않는다.** ① 판정 축 = "P(TOP30 표본이 **mid 효과** 검출)=1.000" — 이건 TOP30의 **SE**(월별 gap 시계열 NW-SE=0.00243)와 **mid의 효과크기**(19.1%)만 쓰지 TOP30 점추정 3.8%를 안 씀. mid 19.1%는 문턱 훨씬 위(power 곡선 plateau) → SE가 2배 틀려도 power≈1 불변. ② 이질성 검정 (mid−TOP30) NW-t=+3.70은 점추정-독립 직접검정 — mid gap이 TOP30 gap을 공통월에서 유의 초과. ③ bootstrap CI가 **mid 19.1% 배제**(상단 9.7%<19.1%) = "효과 진짜 mid보다 작음"을 CI로도 확인. → 세 독립 경로가 같은 결론(attenuation).
- **보강**: verdict에 zero-대비(underpowered)와 mid-대비(death 확정)를 명시 분리. 점추정 3.8%는 "잔여 소효과의 크기 추정"으로만 쓰고, 판정 근거는 SE·이질성·CI-배제로 삼음. self-rationalization 없음.

## Concern 2 — mega 표본의 시대편중 (task 지정 ②)
**적대 제기**: TOP30 flag이 특정 레짐(2020+ 반도체 mega 집중)에 몰려 있으면, 그 시기의 mega 수익구조가 gap을 왜곡한다. 전기간 pooled 판정이 시대편중을 숨기지 않는가?

**분류: ACCEPT (핵심 caveat로 격상)**
- **전면 인정 + 실측**: era-gap 분해가 편중을 **드러냄** — 2005-2014 TOP30 F2 gap=−3.4%/yr(t−0.91) / 2015-2019 +7.9%(t2.02) / 2020-2026 +11.5%(t1.73). 잔여 양(+)은 **2015+ 최근 레짐 국한**, pre-2015는 null/음. flag 분포도 F0는 2005-14에 501개로 몰려 있고 F2는 고르나 gap 부호가 시대별로 갈림.
- **처리**: 은폐 않고 P1.era_concentration_challenge2로 격상 + synthesis에 "대형주 SAFE 잔여신호=최근-레짐 조건부(상시 아님)" 명기. next_probe #2로 "TOP30 잔여의 2015+ 조건부성·레짐 상호작용 검정" 예약. → **시대편중은 결론을 뒤집지 않고 오히려 강화**: 전기간 pooled로도 TOP30 t=1.30인데, 그 약한 양(+)마저 최근-레짐 국한 = mega SAFE는 더욱 취약(구조적 상시 신호 아님).
- **자기합리화 검사**: "대부분 결과 동일/영향 미미"로 편중을 무마했는가? → 검사 결과 무마 없음. era별 부호 반전(−0.91→+2.02→+1.73)을 정량 병기, "최근-레짐 국한"을 caveat이자 next_probe로 명시.

## Concern 3 — 복합 flag 다중검정 (task 지정 ③)
**적대 제기**: INS01+INS02 복합을 3형태(union/inter/addz) 시험했다. 그중 union이 t=1.97로 가장 높다. cherry-pick·다중검정 오염 아닌가? 하나쯤 우연히 t>2 나올 수도.

**분류: REBUTTAL (명시 근거)**
- **근거 1 (전제 자체가 데이터에서 붕괴)**: 복합의 논리적 전제 = "INS01·INS02 부분독립 → 정보 추가". 실측 corr=0.85(전체)·0.80(TOP30) = **高중복**. 부분독립성이 없으므로 복합은 원리적으로 TOP30를 못 올림 — 3형태 중 어느 것이 최고인지는 부차적(전제가 이미 falsified).
- **근거 2 (결과가 방향 일관)**: 3형태 TOP30 t = 1.97/1.24/1.21 **전부 <2**, cherry-pick할 winner 없음. union 1.97조차 문턱 미달 + P3 pooled(더 포괄적 union)도 NW-t 1.97 동일 수준. "하나쯤 t>2"가 **안 나온** 것이 결론(복합 무효).
- **근거 3 (chain·사전등록)**: 3복합형태는 prereg_r37.json(hash ae1b26f0)에 P2로 고정 열거, sweep-argmax로 최종안 고르는 구조 아님(chain, n_trials=1). DSR 게이트 부적용(monitoring-face·비-selection). 다중검정 우려의 실질 = "복합이 성공했다 주장하려 여럿 시험" 인데 **복합은 실패로 판정** → 우려 moot.

---

## Self-Rationalization 자동검사 (measurement-graduation §금칙 grep)
스캔 대상: "미미 / 관행적 / 실무적 / 보수적이면 OK / 대부분 결과 동일 / 영향 미미".
- verdict/challenge 전문 grep → **0건**. mega thinness를 "미미"로 무마하지 않고 power 1.0·het t 3.70·CI-배제 3경로로 정량 확증. 잔여 소효과를 "실무적 무시"가 아니라 "검출 문턱 이하·최근-레짐 국한"으로 정직 서술. **합리화 회피 PASS.**

## Q-Lead escalation trigger 검사
- HIGH severity ≥5 → **No** (Concern 2 ACCEPT는 caveat-격상이지 위반 아님; 1 PARTIAL·3 REBUTTAL).
- AX axiom hard FAIL ≥3 → **No**.
- PIT C1(lockbox/lookahead) 위반 → **No** (R36 uni 상속 = clean T-1 + insider m→m+1 C5 + lag1 통과 상속, 신규 데이터 접근 없음).
- **결론: escalation 불요.** monitoring-face 진단 + power/death 판별 + 한계(잔여 underpowered·최근-레짐 국한) 명시.

## AX-008 Verification Triangulation
self-adversarial(본 note) = 3-source(Forge·Architect·Self-Adversarial) 중 1. 본 라운드는 non-capital monitoring 진단으로 forge backtest·architect 진단 미소환(자본 판정 아님). self-adversarial 단독 + R36 uni 상속(parity 3.058) + 순열(pooled p=0.023)·bootstrap(B=2000)·이질성 NW-t 내부검증으로 무결성 확보. 자본 게이트 진입 시 3-source 재적용 의무.
