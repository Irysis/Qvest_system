# WT-D20260803_001 — Self-Adversarial Challenge Note (v8.2)

**작성 시점**: finalize 직전 (alpha_package emission 전). 모델 = Fable 5 자체 적대검증 (Codex Round 대체).
**대상 산출물**: FM 상호작용 primary NW t = +0.234 → INCONCLUSIVE (사전등록 판정).

---

## Concern 1 — 국소성 반론: "full-frame FM이 top-20 마진의 진짜 효과를 희석했다"

**제기**: WT-022의 +1.16%/월은 top-20 마진 스왑(월 ~3.8종)의 국소 현상인데, 후보 프레임 전체(월 ~231종) FM 상호작용은 그 국소 신호를 나머지 ~200종의 무신호로 희석할 수 있다.

**분류: PARTIAL**
- 보완 실측 3갈래가 전부 같은 방향: ① d5 top-40 국소 검정 (rank 제거, 상위 안 max5 주효과) t = +0.34 (통제 전 −0.23) ② d9 rank-Q5분위 내 max5 Q5−Q1 스프레드 t = +1.54 (승계 t 1.54와 동형 재현 — 표본을 바꿔도 같은 크기) ③ 승계 직접 측정 자체가 t 1.54 문턱 미달.
- 인정하는 부분: top-20 "마진 스왑 표본 그 자체"의 재검정은 승계 수치 인용으로 갈음 (재계산 금지 mandate) — 독립 추가 표본은 없다. 단 세 프레임(전체/top-40/Q5분위)이 일관되게 t < 2이므로 "희석이 유의성을 숨겼다"는 가설은 관측과 불합치.

## Concern 2 — CAUTION 셀 (t +2.05) · MEGA 셀 (t +2.76)을 왜 승격하지 않는가 (역방향 적대)

**제기**: 진단 셀 두 개가 |t| ≥ 2 — 이를 근거로 "국면-조건부/mega-cap 조건부 승자 표지 확인"을 주장할 수도 있다. 승격하지 않는 것이 오히려 보수 편향 아닌가.

**분류: REBUTTAL (승격 거부 유지) — 정량 3축 + 학술 + L-계보**
- 다중검정: 사전등록 진단 셀 수 = 부기간 5 + 국면 4 + tier 4 + placebo 5 + lag1/ArmA/ArmC ≈ 20+ 셀. 그중 2개 |t|>2는 무효과 하에서도 기대 범위 (Harvey-Liu-Zhu 2016 — 문헌-레벨 다중검정이 PORT_t 2.95 허들의 근거인 시스템에서, 진단 셀 t 2.0을 판정으로 승격하는 것은 게이트 우회).
- 검정력/스펙: CAUTION n=13개월 (셀 극소) · MEGA는 축약 스펙 (n=10/월, 3모수, D35/D45 통제 불가) — MEGA 양성은 rank×단기변동성 교란 미배제 상태.
- 사전등록 규율: primary_immutability — 진단 arm은 어떤 결과여도 primary 교체 금지 (WT-022 준용). 승격 = sweep 재분류.
- 단, CAUTION은 WT-020 (CAUTION ret_spread +1.76%/월 t +2.08)과 **독립 2회 정합** — 버리지도 승격하지도 않고 next_probe 1순위로 사전등록 대상화 (L-계보: WT-020→022→본 라운드).

## Concern 3 — Arm C에서 b_int가 17배 커졌다 (+0.00014 → +0.00242, t 1.28)

**제기**: rank×D35/D45 병렬 투입 시 상호작용 계수가 커진 것은 "D35 통제가 오히려 MAX5 고유 신호를 드러낸다"는 신호 아닌가.

**분류: PARTIAL**
- 인정: 점추정 증가는 사실이고 기록한다. cor(zmax5, D35_aligned) = −0.918 — rank×max5와 rank×D35가 강공선이라 계수 분해가 불안정해지고 SE가 팽창한다 (t 1.28 < 2).
- 반박 유지: attribution gate는 primary 유의 시에만 발동하도록 사전등록됐고 primary가 미확정이므로 Arm C 해석으로 판정을 바꿀 수 없다. Arm C 양성 방향은 next_probe 설계 입력으로만 소비.

## Concern 4 — 라벨 윈도우 경계 (1거래일 시프트)

**제기**: FM 라벨 = 그리드 (d0, d0_next] 복리인데 production 홀딩 윈도우 = (start_d, end_d] — 1거래일 어긋난다. 소비 arm이 실행됐다면 FM 판정과 실코드 판정의 윈도우가 미세 불일치.

**분류: ACCEPT (문서화 + 한계 기록)**
- 신호(max5·score_eff·통제)는 전부 d0 이전 데이터 — PIT 위반 경로 아님 (방향 검증 cor 1.0000 + 위반 주입 발화 실증).
- 소비 arm 미실행 (trigger 미충족)이라 본 라운드 판정에 비관여. 향후 소비 arm 실행 시 실코드 하네스(WT-022)가 자체 윈도우를 쓰므로 불일치는 FM→실코드 전이 시 재확인 항목으로 명기.

## Concern 5 — 음의 결과의 성급한 일반화 (AX-000)

**제기**: "INCONCLUSIVE"가 "MAX5×rank 상호작용은 없다"로 읽히면 config-scoped 판정을 방향 판결로 오독하는 것.

**분류: ACCEPT (판정문 스코프 명시)**
- 본 판정 스코프 = 선형 z-상호작용 · 후보 프레임 전체 · 1M 지평 · D35/D45 통제. 미검 축 = 비선형/문턱형 상호작용, CAUTION 조건부, mega-cap 조건부, 다지평(3M) — 전부 next_probe/부활 조건에 명기.

---

## Self-rationalization auto-detection

answer-principles 회피표현 조항의 합리화 어휘 5종(영향 축소 표현·관행 인용·실무 핑계·보수성 면책·결과 동일성 주장)에 대해 본 문서·판정문 스캔: **미사용 확인**. 판정은 전부 사전등록 문턱 대비 실측 수치로만 서술.

## Q-Lead escalate trigger 점검

- HIGH severity concern ≥ 5: 해당 없음 (PARTIAL 2 / REBUTTAL 1 / ACCEPT 2 — 전부 판정 무효화 아님)
- AX axiom hard FAIL ≥ 3: 없음
- PIT C1 (lockbox/lookahead) 위반: 없음 (위반 주입 테스트 발화 실증, C14/C15 로더 경유)
→ escalate 불필요.

## D35 소비 배선 사실 (Q-Lead 지시 3 반영)

D35_RealVol_63d는 factor DB에 2026-03-24부터 등재·active 상태였으나 **소비자 0** (factor_db 내부 4곳 참조뿐 — compute_defense.R·phase6.R·registry·bak). WT-020이 vol63을 자체 계산한 것도, 본 라운드 이전까지 위험모델·랭킹 어디서도 안 쓴 것도 "없어서 못 쓴 게 아니라 있는데 안 쓴 것". 본 라운드가 D35의 첫 리서치 소비 사례다. 이 계통(생산은 되는데 소비 배선 부재)은 screen_route 라벨 소비자 0·lifecycle.status reader 0과 동형.
