# 지식체계 점검 — 2026-08-16 (중간, 단독 측정분)

**요청**: 도훈 — ① 증류가 잘 일어나는지 ② Axiom 승격체계가 작동하는지 ③ 내 개입이 없어 멈춘 프로세스가 있는지
**추가 요청**: "실제로 만들어진 L-Code 들이 재귀적 자가발전에 기여하는지 — Axiom 엔진이 설계의도대로 작동하는지"

**★본 문서의 지위**: 아래는 전부 **Q-Lead 단독 측정**이며 **적대검증을 거치지 않았다**.
병렬 감사 3건(지식체계 8표면 · 인적 게이트 6영역 · Axiom 폐쇄루프 6구간)이 진행 중이고,
결과 도착 시 본 문서에 대조 절을 덧붙인다. **이 조사에서만 자기정정 2회 발생**(§6) — 수치를 인용할 때 그 사실을 함께 옮길 것.

**측정 시각**: 2026-08-16 14:58 ~ 15:50
**수치 규약**: 파일 경로 + 실제 값 인용. 재구성·추정 없음. 측정과 추론을 라벨로 구분.

---

## 0. 한 줄 요약

Axiom 엔진은 **3층 중 2층이 돌고, 3층째(Law)는 연료가 없어 멈춰 있다.**
그리고 그 정지는 **고장이 아니라 설계 정합**일 가능성이 높다 — 확정은 폐쇄루프 감사의 **행동 변경률** 수치에 달렸다.

---

## 1. ① 증류 — 주기는 건강하다

| digest | 크기 | 직전 간격 |
|---|---|---|
| 2026-07-05 | 5.7 KB | 최초 |
| 07-11 | 8.3 KB | 6d |
| 07-18 | 11.4 KB | 7d |
| 07-26 | 7.4 KB | 8d |
| 08-02 | 13.7 KB | 7d |
| 08-09 | 14.0 KB | 7d |
| 08-15 | 38.8 KB | 6d |

**7주 연속 · 결번 0 · 간격 6~8일.** 증류 절차 자체는 멈춘 적이 없다.

관찰 2건:
- **manifest 1건 결번** — digest 7편 vs `distill_manifest` 6건. **2026-07-26(W30)** 이 없다. 삭제 0건이어도 `deleted: []` 로 남는 게 규약이므로 단계 누락으로 보인다(그 주 세션 로그 미확인 — 확정 아님).
- **첫 manifest 스키마 드리프트** — `distill_manifest_20260704.json` 의 `week_of` 가 `None`. 이후 6건은 `2026-W28`~`W33` 정상.
- 08-15 digest 가 38.8 KB 로 직전 최대의 2.8배. 철저함인지 장황함인지는 판정 보류(작성자가 Q-Lead 자신).

**병목은 "일어나는지"가 아니라 카드 처리량**: `pending_5axis` 89건(어제 94→89), 그중 **54건이 supporting 1건**.

---

## 2. ② Axiom 승격 — 잣대를 바꿔야 한다

### 2.1 설계의도 (`02_Infrastructure/docs/rules/axiom-engine.md`)

- **3층 산출물 모델**: ①Ledger(L-code) → ②Distilled(DIST) → ③Law(AX)
- **INV-2 생성≠강제**: 자동 승격 = `enforcement_mode=documented`. *"엔진산 negative 지식의 차단 실효는 enforcement 자동 생성이 아니라 **주입·검색 경로(②Distilled)** 로 확보"*
- **INV-7**: negative 지식은 **Law가 아니라 Distilled 탐색-지도** — **5축 승격 게이트를 거치지 않는다**. Law 잔존은 process 규칙(polarity 없음)
- **INV-1**: global 승격은 supporting 전부 `backtested`

### 2.2 그래서 실제 승격 후보군

```
전체 후보                                        94
├ negative (INV-7 → Law 대상 아님)                43  (45.7%)
└ non-negative                                   51
   └ ∧ metric_type=backtested (INV-1 global 자격)   5

★ global AX 승격의 이론적 후보군 = 5건 / 94건 (5.3%)  — 전부 ramp 모드
```

후보 metric_type 분포: `estimated 79 · backtested 9 · proxy 6`.

⇒ 실패축 히스토그램(`external 88 · independence 85 · falsification 76 · mechanism 48 · rigor 4`)은
**애초에 global 로 못 가는 후보들 위에서 매겨진 점수**다. 이를 승격 병목으로 읽으면 없는 병목을 본다.

⇒ **active Law 4건(AX-000/001/002/008)이 전부 process 규칙인 것은 설계대로**다.

### 2.3 연료(`backtested` L-code) 감소 — 단조

시간축 = L-code ID 내장 날짜(351/493건. 나머지 142건은 구 `L-NNN` 계열로 날짜 없음 → 제외).

| 월 | L-code | `backtested` | 비율 |
|---|---|---|---|
| 2026-06 | 164 | 86 | **52.4%** |
| 2026-07 | 117 | 41 | **35.0%** |
| 2026-08 | 70 | 9 | **12.9%** |

구성 이동: `unavailable` 0 → 6 → **18** · `canonical_screen` 0 → 56 → 16.
(08월은 16일까지라 **총량**은 부분값이나, 보는 것이 **비율**이라 영향 없음)

### 2.4 왜 연료가 마르나 — 파이프라인이 alpha 에서 끝난다

08-13 라운드 6건 전수 (`qepm/mailbox/worktask/WT-D20260813_*`):

| WT | phase | 보유 산출물 | 도달 |
|---|---|---|---|
| _001 | SPEC_APPROVED | hypothesis | 설계 |
| _002 | ALPHA_DONE | alpha_package + cert | alpha |
| _003 | ALPHA_DONE | alpha_package | alpha |
| _004 | SPEC_APPROVED | alpha_package + cert | alpha (**상태 미갱신**) |
| _005 | SPEC_APPROVED | alpha_package | alpha (**상태 미갱신**) |
| _006 | SPEC_APPROVED | hypothesis | 설계 |

`risk_package` · `optimization_package` · `forge_package` **전부 0건**.
최근 WT 40개 중 `forge_package` 보유 **0건**. 실제 WT mailbox 의 마지막 forge 산출물 = **`WT-AX008RERUN_20260612`**.

★**이건 대체로 옳다** — WT002 는 기전 관문(AUC 0.7143 < baseline 0.7472), WT003 은 VT2b(cov(e,r) −1.480%/yr)에서 죽었다. 죽은 알파에 forge 를 돌리는 건 낭비다. **규율이 작동한 것.**

부수 결함: _004·_005 가 `alpha_package.json` 보유인데 phase 가 `SPEC_APPROVED`. status 로 진행도를 세는 집계는 **과소계상**된다.

### 2.5 모드별 — "파이프라인 정지"는 QEPM 한정

| mode | L-code | 최신 | `backtested` 최신 |
|---|---|---|---|
| alpha_search | 165 | 08-13 | **08-09** |
| alpha_research | 76 | 08-10 | 07-19 |
| ramp | 60 | 08-02 | 07-15 |
| **QPM** (정식 풀파이프라인) | 5 | 08-13 | **없음** (전부 `unavailable`) |
| method_frontier | 12 | 08-09 | 없음 |
| factor_rotation | 1 | 08-09 | 08-09 |

경량 레인(alpha-search · factor-rotation)은 여전히 `backtested` 를 낸다. 멈춘 것은 **정식 QEPM 풀파이프라인**.

### 2.6 왜 alpha-search 의 backtested 가 global 후보를 못 만드나

alpha_search 후보 5건의 metric: `proxy 4 · estimated 1` — **`backtested` 0건**.
원인 = **거대 클러스터의 metric 희석**. `CAND_20260704_alpha_search_momentum_conditional` 이 supporting **507건**을 참조하고
그 분포가 `미발견 381 · proxy 84 · backtested 41 · canonical_screen 1` → candidate metric 이 최저값 `proxy` 로 내려앉는다.

★단 이건 **계통이 아니다**: 후보 94건 중 **89건(94.7%)은 supporting 을 전부 조회 가능**하다.
집계 34.8%(1,116 참조 중 388 미발견)는 **이 한 병리적 후보가 만든 값**이다.

---

## 3. ③ 멈춘 프로세스 — 대기 중인 건 도훈이 아니다

### 3.1 알파 라운드가 3일째 파킹

`qepm/mailbox/worktask/WT-D20260813_006`:
```
current_phase        : SPEC_APPROVED
alpha_hypothesis.json: verdict "designed" (23.7 KB, 설계 완료)
challenge_note       : 작성됨
마지막 활동          : 2026-08-13 21:54
alpha_package.json   : 부재  ← alpha-research 미실행
```

인계 큐(`next_session_task.md`, 08-13 21:55) 첫 줄: *"WT-D20260813_006 alpha-research 로 바로 시작. … 다음 세션은 설계를 읽고 측정만 하면 된다."*

경과: **08-14 커밋 0건 · 08-15 /cleaner(도훈 호출) · 08-16 지식체계 감사(도훈 요청)**.
두 세션 다 도훈 직접 요청이라 자율적 인프라 표류는 아니다. 그러나 결과적으로 CLAUDE.md 존재의의 절의 기본값(*"세션 자원 배분의 기본값은 알파 라운드 전진"*)이 3일 밀렸고 **아무도 신호로 올리지 않았다**.

### 3.2 가시성 결함

부팅이 내는 것: `WT 누적: 266건 (진행중 아님. 진행 상태는 wt_list())` · `Inbox: alpha=n/a ...`
**"설계가 끝나 측정만 남은 WT 1건 대기"** 정보가 부팅 어디에도 없다. `alpha=n/a` 는 "대기 없음"처럼 읽히나 실제로는 "이 mailbox 구조를 안 읽는다"는 뜻.

⇒ 도훈 승인 대기(DIST 10건 · axiom confirm 18건)는 쌓여 있으나 **알파 라운드를 막지 않는다**. 실제로 막혀 있는 건 **집기만 하면 되는 알파 라운드**다.

---

## 4. ★핵심 질문 — 엔진이 설계의도대로 도는가

| 층 | 상태 | 근거 |
|---|---|---|
| **①Ledger** | 활발 | 493건 · 이번 주 25건 |
| **②Distilled** | 돈다 | 증류 7주 연속 · 카드 146건 · 08-15 5건 정제 |
| **③Law** | 2개월 정지 | 승격 0 · global 후보 5건 |

③의 정지는 INV-7(negative 면제) + INV-1(backtested 필요) + 연료 감소의 **합성 결과**이며,
엔진이 **없는 승격을 지어내지 않는 모습**이기도 하다.

⇒ ③이 구조적으로 못 도는 동안 자가발전의 전 부담은 **②의 주입·검색**이 진다(INV-2).
**따라서 판정 지점은 승격률이 아니라 소비율이다.**

### 4.1 확보된 긍정 증거 (n=1)

`WT-D20260813_006/alpha_hypothesis.json` 의 `prechecks.hypothesis_index_hits` —
alpha-hypothesis 에이전트가 착수 전 과거 지식을 조회하고 **설계를 실제로 바꿨다**:

- `L-AR-20260808_120900`(MAX5 = vol·size 대리, FMB t −5.42→**0.14**) 인용 → 월내-적률 후보를 "재포장"으로 절단
- `DIST-QPM-005`(개인 flow hidden clone, cor **0.897**) 인용 → **반증 F3 를 기계 검사로 내장**(월간 level 과 |cor|≥0.8 이면 기각)
- `FQ-029/R16` 인용 → cap-tier 국소화 리스크를 `regime_scope` 에 명기

★그리고 이건 **에이전트 성실성이 아니라 규약 의무**다 — `axiom-engine.md` 가 QEPM 에 대해
*"`/worktask` create 시 `hypothesis_index` lookup 의무 — FAIL/KILL/DISTILLED_NEG 히트 시 차별점 명시 없인 진행 금지"* 를 규정한다.

**n=1 은 계통이 아니다.** 폐쇄루프 감사 segment 2 가 **행동 변경률**(인용이 설계를 실제로 바꾼 비율)을 재고 있다.

**사전등록한 판정 규칙** (결과 수신 전 고정):
- 행동 변경률 **≥50%** → ②층 `WORKING`. ③층 정지를 설계 정합으로 기록하고 **승격률을 건강 지표에서 내린다**.
- **<20%** → 주입·검색이 형식적. **그때가 진짜 엔진 정지**이고 수리 대상은 승격 게이트가 아니라 **소비 배선**.

---

## 5. 같은 뿌리 4건 — 정본↔소비처 대조 부재

| # | 정본 | 우회/미추종 소비처 | 증상 | 분류 |
|---|---|---|---|---|
| 1 | `check_constraint_firewall` | `close_round` 인라인 정규식 | 오탐 경고 (1,078자 떨어진 두 토큰을 1,338자 매치) | 위생 |
| 2 | 프론트매터 `name:` | 메모리 파일명 18개 | `[[wiki]]` 링크 80건 단절 | 위생 |
| 3 | `lcode_corpus`(493) | `hypothesis_index`·`knowledge_index`(492) | 신규 지식이 조회면 미도달 | **측정 신뢰** |
| 4 | `emit_lcode` 계약 | 직접 JSON 쓰기 **196/369건(53.1%)** | grade 비-enum 20건 → `polarity=unknown` 17건 | **측정 신뢰** |

**#4 의 비대칭 (실측)**: 2026-08-15 `emit_lcode("N/A_panel_statistic")` 은 **BLOCKED**.
같은 값이 08-13 에 직접 JSON 으로 쓰여 통과 —
`l_code_AR_fq233_r31r33_target_form_premise_20260813.json grade=N/A_panel_statistic`.
⇒ **계약은 함수를 호출하는 경로만 구속한다.**

**#4 의 하류 기전**: `cluster_extractor._polarity` 가 grade 분포로 polarity 를 추론.
비-enum grade → `unknown` → negative 도 positive 도 아니라 **어느 경로로도 안 감**.

### 5.1 배선 지도는 이미 있다 — 그러나 axiom 이 사각

`06_Registry/wiring_map.json` (2026-08-14, 60 표준): `wired 19 · thin 24 · orphan 17`.
`orphan` = 표준인데 소비자 0. 지도 자신의 정직 표기: *"산출물 식별 3/60 — 이 비율이 낮으면 정체 0 은 '건강'이 아니라 '미측정'"*.

**표준 dir 분포**: `contracts 30 · validation 26 · 06_Registry 4 · axiom **0**`.
조회 결과 `constraint_firewall` · `lcode_emit` · `distilled` **전부 목록에 없음** ⇒ 위 #1·#4 는 지도가 볼 수 없는 영역.

**탐지 방식의 사각**: `close_round.R` 은 지도에 있으나 `_unverified_n_reimpl: 0`.
재구현 탐지가 **심볼 호출 기반**이라 함수 안에 박힌 **인라인 정규식**은 안 잡힌다.

**정확도 경고**: `canonical_screen_bt.R` 의 reimpl **77** 중 첫 항목 `essence_score.R` 에 대해
3중 검사(파일명 리터럴 0 · `.canon_*` 정의 0 · 호출 0)로 **분류를 재현하지 못했다**.
`_unverified` 접두가 붙은 이유가 있다 — **사실로 취급 금지**.

**권고 순서 (수정본)**: ①표준 모집단에 `02_Infrastructure/axiom/` 추가 → ②`_unverified_reimplementers` 검증 → ~~③로직 복제 탐지 확장(보류)~~.
★확장 전에 **지금 정확한지부터**.

---

## 6. 이 조사에서 Q-Lead 가 틀린 것 (2회)

1. **"후보 94건 전원 pending = 승격 병목"** → 잣대 오류. negative 43건은 설계상 Law 대상이 아니고, INV-1 까지 적용하면 실제 후보는 5건.
2. **"백테 원장 6주 침묵 = 배관 결함"** → 철회. `backtest_registry.csv` 는 **QEPM 계약 전용**이고 alpha-search 는 `register_module` 경유 `module_performance.json`(08-14 갱신, 정상)에 남긴다. QEPM 이 forge 에 안 가니 비어 있는 게 정합.

부수 정정: 메모리 카드가 지목한 `02_Infrastructure/ops/wiring_map_build.py` 는 실제로 **`.R`** — 죽은 경로 13종 중 1종 해소.
근접 오류: "supporting 근거의 75% 조회 불가"를 계통으로 헤드라인 걸 뻔했으나, 후보 단위로는 94.7% 정상.

---

## 7. 메모리 계층 (감사 3건이 안 보는 표면)

- 카드 **331개** (`project 239 · feedback 50 · reference 37`)
- `MEMORY.md` **35,066 B → 5,956 B** 압축(08-13 세 섹션 아카이브 이관, 불릿 유실 **0**)
- **메모리↔원장 양방향 누수**: 08-10 카드 6 / L-code **0** ↔ 08-15 카드 0 / L-code **1**
- **지식그래프**: `[[wiki]]` 1,307건 중 정확일치 1,166(89.2%) · **명명 드리프트 80(6.1%)** · 룰 참조 48 · 미작성 8 · 정규식 오탐 5
  - 드리프트 방향 = **링크가 맞고 파일명이 낡음** (snake 18개 중 17개가 프론트매터 `name:` 은 이미 kebab)
- 저장소 경로 참조 293건 검사 → **부재 14건(4.8%, 고유 13종)**. 글롭·플레이스홀더 22건은 제외
- ⚠메모리 디렉터리는 **git 추적 밖** — rename 은 되돌리기 어려움. **수리 미실행**

---

## 8. 후속 (감사 결과 대조 후 확정)

1. **인덱스 재빌드** — 감사 종료 직후 첫 작업. 단 원인이 *순서*인지 *원천 분리*인지 먼저 확정(수리 대상이 다르다). 재빌드 후 corpus↔인덱스 차집합을 **다시 재서 0 확인**(재빌드했다는 것과 도달했다는 것은 다른 사건).
2. **부팅에 "착수 가능 WT" 라인 신설** — `SPEC_APPROVED` ∧ hypothesis designed ∧ `alpha_package` 부재. 인계 큐 연령도 노출.
3. **`emit_lcode` 우회 경로 처리** — 계약을 파일 쓰기에도 걸지, 아니면 harvester 가 비-enum grade 를 정규화할지. 후자가 싸다.
4. **`polarity=unknown` 17건** — 위 3번 해소 시 자동 해결되는지 확인.
5. **배선 지도 axiom 확장** — §5.1 순서대로.
6. **W30 manifest 결번 원인** — 단발이면 위생, 2회 이상이면 스윕 배선 결함.
7. **메모리 명명 드리프트 80건** — rename + 링크 동반 수정 + A/B 재측정(드리프트 80→0 ∧ 마크다운 부재 0 유지). 도훈 확인 후.

---

## 9. 미측정 (정직 기록)

- 폐쇄루프 **행동 변경률** — 이 문서의 핵심 공백. 감사 segment 2 소관
- 엔진이 **한 번이라도** 승격을 끝까지 돌린 적 있는지 (corpus `n_promoted=2` 가 단서) — 감사 segment 1
- INV-7 **부활 신호 발화 이력** — 감사 segment 4
- 주입 훅이 실제로 무엇을 읽어 무엇을 넣는지 — 감사 segment 5
- `_unverified_reimplementers` 오분류의 **정확한 기전** (1건 비재현까지만 확인)
- W30 manifest 결번의 세션 로그
- 08-15 digest 38.8 KB 가 과한지 — 작성자 자신이라 판정 보류
