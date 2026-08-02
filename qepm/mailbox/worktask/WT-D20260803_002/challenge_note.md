# Challenge Note — WT-D20260803_002 (FQ-127 base-의존성 재판정)

Self-Adversarial Challenge (v8.2, finalize 직전 수행). Concern 5건: ACCEPT 3 / PARTIAL 1 / REBUTTAL 1.

## C1. parity 재현 격차 (ew25 +1.516 vs 원 canonical +2.028) — **PARTIAL**

- 제기: 내 EW-25 근사 arm이 WT-009 canonical paired t를 정확 재현하지 못하면 tilt 재판정도 신뢰 불가 아닌가.
- 처리: 사전등록 허용치(동부호 ∧ |Δt| ≤ 0.7) **측정 전 고정** — 실측 |Δ| = 0.512로 PASS. 격차 기전 후보 3종 명기: ① 수익 윈도우 관습(sig→sig 거래일 복리 vs canonical ME-grid Ret_1m) ② liq 결측 처리(내 하네스 hard-fail vs canonical adv결측=통과) ③ 비용 적용 시점. **판정 도구는 하네스-내 가중 config 대조(내적 일관)이지 수준 재현이 아니다** — 동일 하네스 안에서 ew25→tilt20 이동 시 부호가 유지되는가가 질문이고, 그 대조에는 관습차가 양 config에 대칭 작용한다.
- 보강: WT-022 승계분(CL-4/5)은 production_parity_verified 재현 경로(GATE A 5.13e-16)의 실측이므로 본 concern 비적용.

## C2. CL-3 "부호 유지"의 오독 위험 — **ACCEPT**

- 제기: T1 부호 유지(tilt ΔIR +0.150)를 "PATHQ 교체 재개"로 읽힐 수 있다.
- 처리: 교체 철회 사유는 base-축이 아니라 **FQ-109 멤버십-섭동 취약**(paired 5-seed sd 0.378, 문턱 근방 단일 draw)이며 독립 존치. tilt 프레임에서도 paired t +1.556 < 2.0 (원 문턱 미달). 판정문·package challenge_flags 이중 기재로 오독 차단.

## C3. production rank-tilt의 CRISIS ub 0.10 생략 — **REBUTTAL (정량)**

- 제기: tilt20_tophi가 ub 0.20 고정이라 production 실코드와 다르다 — 국면 조건이 부호를 바꿀 수 있다.
- 반박 실측: unified_regime CRISIS 라벨월(25/295)에 ub 0.10 적용판 재측정 — T1 ΔIR +0.1436 (t +1.487), T2 +0.1730 (t +0.872). 기준판(+0.1496/+0.1824) 대비 부호·크기 안정. `fq127_adversarial_regime_ub.rds`.
- 잔여 정직 라벨: production의 regime 원천은 production alpha panel의 regime_state(256개월)이고 본 감응도는 unified 라벨(295개월 커버) — 라벨 원천 차이는 남는다. 단 개입 월수(25)와 효과 크기(Δ|ΔIR| ≤ 0.009)로 부호 반전 여지 없음.

## C4. POS2 in-sample 성분 선별 편향 승계 — **ACCEPT**

- T2의 POS2는 WT-021이 in-sample 라벨로 성분을 고른 probe — 그 편향은 4 config에 대칭 승계되므로 base-축 질문(가중 규칙 간 대조)에는 유효하나, **POS2 자체의 유효성 증거로 소비 금지** (WT-021 honesty 라벨 유지). T2 capnorm25 t +2.528도 진단 관측일 뿐 채택 후보 아님.

## C5. "부분 계통" 판정의 과대 일반화 위험 — **ACCEPT**

- 제기: 신규 재판정은 2건뿐 — "점수-교체는 강건"을 계열 전체로 확장하는 것은 표본 2의 귀납.
- 처리: 판정문 boundary_honesty에 한정 명시 — 부분 계통 판정은 검증 가능 B 4건에 한정. CL-1(WT-003, paired +2.569 — **base cap-w PORT_t 0.59의 약한 base 위 주장이라 경고 등급 최상**)은 패널 부재로 미검(C). NP-3에 반례 탐색(고상관 rerank 쌍의 꼬리 집중 가능성) 등재 — "rerank형 = 무조건 안전"이 아니라 "무게-비대칭이 없으면 보존"이 정확한 기전 서술.

## 합리화 자기검증

answer-principles 회피표현 조항의 금지 목록(`.claude/rules/answer-principles.md` §회피 표현 grep — 목록 자체는 리터럴 재인용하지 않음, 탐지기 오발화 방지)에 대해 본 라운드 산출물 전수 grep — 실사용 0건. C3는 서술 반박이 아니라 실측 반박으로 처리. 사후 재분류 0건 — 분류·대상·판별 기준 전부 preregistration.json에 측정 전 고정.

## Q-Lead escalate 판정

HIGH severity 0 / AX hard FAIL 0 / PIT C1 위반 0 — escalate 비발동.
