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
- ~~**manifest 1건 결번**(W30) = 단계 누락~~ → **철회 (2026-08-16 정정, 자기정정 3번째)**.
  W30 sweep 은 `dry_run=TRUE` 로 실행돼 **실삭제 0건**이었고, W30 digest §4 가 *"실삭제는 W31 증류에서 참조 0 검증과 함께 수행한다"* 로 **명시적 이월**을 기록했다.
  `.cache/hygiene_manifest.log` 의 그 주 기록도 전부 `[DRY]` 태그. W31 manifest(`distill_manifest_20260802.json`)가 실제로 삭제 1건을 담았다.
  ⇒ **manifest 부재는 문서화된 이월이지 결함이 아니다.**
  ★오류 기전: digest 를 열지 않고 **파일 목록만 세서** 판단했다(= "인용은 복사가 아니라 대조" 위반).
  ★부수: 당시 digest 가 도훈 대기 항목을 기록해뒀으나(*"sweep dry-run 고정 — 실행 모드 전환은 도훈 판단, 무단 전환 금지"*) 본 문서 §3 이 못 잡았다. **다만 이미 해소** — W33 pending 은 `dry_run: false`.
- **첫 manifest 스키마 드리프트** — `distill_manifest_20260704.json` 의 `week_of` 가 `None`. 이후 6건은 `2026-W28`~`W33` 정상. (미해소)
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

## 5. 같은 뿌리 5건 — 정본↔소비처 대조 부재

| # | 정본 | 우회/미추종 소비처 | 증상 | 분류 |
|---|---|---|---|---|
| 1 | `check_constraint_firewall` | `close_round` 인라인 정규식 | 오탐 경고 (1,078자 떨어진 두 토큰을 1,338자 매치) | 위생 |
| 2 | 프론트매터 `name:` | 메모리 파일명 18개 | `[[wiki]]` 링크 80건 단절 | 위생 |
| 3 | `lcode_corpus`(493) | `hypothesis_index`·`knowledge_index`(492) | 신규 지식이 조회면 미도달 | **측정 신뢰** |
| 4 | `emit_lcode` 계약 | 직접 JSON 쓰기 **196/369건(53.1%)** | grade 비-enum 20건 → `polarity=unknown` 17건 | **측정 신뢰** |
| 5 | `close_round()` 종료 계약 | `marker_fresh` 가 마커를 **mtime 만** 대조 | 병렬 세션의 라운드 종료가 내 턴의 연속성 계약을 충족 (Level 0 게이트 무력화) | **거버넌스** |

**#5 의 기전 (2026-08-16 실측 재현 + 수리)**: `.cache/last_round_closure.json` 은 루트 단일
파일이고 main 의 `.cache` 는 `/c/qm_cache` **심볼릭 링크**다. 훅은
`DIR=${CLAUDE_PROJECT_DIR:-${QM_ROOT:-$PWD}}` 로 서는데 **Bash/훅 환경에 `CLAUDE_PROJECT_DIR`
이 없어** 모든 워크트리 세션이 main 의 같은 마커를 읽고 쓴다(부팅 기준 워크트리 다수).
게이트는 `round_id` 를 **읽기까지 하고 검증에 쓰지 않았다**.

**실측(실제 훅 경로 · `user_ts` 존재)** — 같은 종결 텍스트, 갈린 것은 서술이 아니라 남의 mtime:

| 픽스처 | user_ts | 마커 | 판정 |
|---|---|---|---|
| A | 07:25Z (마커보다 **앞**) | `INFRA-WT-PURGE-20260816-P2` (07:30:13Z, **타 세션**) | `{}` **PASS** |
| B | 07:35Z (마커보다 뒤) | 동일 | `{"decision":"block"}` |

⇒ #1~#4 와 같은 형태(**존재/신선도 검사로 정체 검사를 대체**)이나 **분류가 다르다** —
1·2 는 위생, 3·4 는 측정 신뢰, 5 는 **Level 0 규약의 차단 실효**가 병렬 세션 수만큼 열린다.

**★수리 중 동반 발견 — 쓰는 쪽과 읽는 쪽의 루트가 갈려 있었다**: `close_round()` 는
**Bash 툴**에서 도는데 그 환경엔 `CLAUDE_PROJECT_DIR` 이 **없어** `QM_ROOT`(=main)에 쓰고,
**Stop 훅**에는 `CLAUDE_PROJECT_DIR` 이 **설정돼** 게이트는 **워크트리 루트**를 읽는다.
실측: 워크트리 `.cache` 에 게이트 산출물(`continuity_blocks.jsonl`·`continuity_gate_counters`)은
**있는데** closure 파일은 **0건**이고, 종료 기록 **468건 전부**가 main 의 `.cache` 에 있다.
⇒ 워크트리 세션에선 정당하게 닫은 마커가 **원리적으로 안 보인다**(포장도로 사망 = 상시
오차단 원천). **이것이 누수(#5 본체)와 반대 방향의 결함이며, 같은 뿌리에서 동시에 나왔다** —
정체를 안 물으니 남의 것을 받고, 루트를 안 맞추니 제 것을 못 찾는다.

**수리**: ①`close_round()` 가 `session_id` 를 신고 ②게이트가 자기 세션(transcript 파일명)과
대조 ③세션별 마커 `.cache/round_closure_by_session/<sid>.json` 로 덮어쓰기 회귀 차단
④게이트가 자기 루트 + 공유 루트를 함께 훑음. **④가 안전한 이유가 ②다** — 정체 없이 공유하면
누수지만, 정체가 있으면 공유 디렉토리는 그냥 공용 보관소다.
검사 `08_Tests/hooks/test_continuity_marker_identity.py` **31/31** (배터리 등재).
★**기존 continuity 배터리 31/31 은 이 결함을 구조적으로 못 봤다** — 판정 root 를 빈 임시
디렉토리로 격리하고 포장도로를 `marker_override=True` 로 주입해 `marker_fresh()` 본문이
한 번도 실행되지 않았다. **초록의 범위를 초록 자신이 말해주지 않는다.**

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

## 6. 이 조사에서 Q-Lead 가 틀린 것 (3회)

1. **"후보 94건 전원 pending = 승격 병목"** → 잣대 오류. negative 43건은 설계상 Law 대상이 아니고, INV-1 까지 적용하면 실제 후보는 5건.
2. **"백테 원장 6주 침묵 = 배관 결함"** → 철회. `backtest_registry.csv` 는 **QEPM 계약 전용**이고 alpha-search 는 `register_module` 경유 `module_performance.json`(08-14 갱신, 정상)에 남긴다. QEPM 이 forge 에 안 가니 비어 있는 게 정합.
3. **"W30 manifest 결번 = 단계 누락"** → 철회. `dry_run=TRUE` 실행 + digest 에 명시된 W31 이월. §1 참조.

★**세 오류의 공통 기전**: 셋 다 **파일/개수만 보고 그 산출물이 선언한 맥락을 안 읽었다.**
①은 `axiom-engine.md` 의 INV-1/INV-7 을 안 읽고 후보 수만 셌고, ②는 `backtest-contract` 의 적용 범위를 안 읽고 mtime 만 봤고, ③은 W30 digest 를 안 열고 manifest 파일 목록만 셌다.
⇒ **원장을 세기 전에 그 원장이 무엇을 담기로 선언했는지 먼저 읽을 것.**

근접 오류(보고 전 자체 검출): "supporting 근거의 75% 조회 불가"를 계통으로 헤드라인 걸 뻔했으나, 후보 단위로는 94.7% 정상.
근접 오류 2: "정본↔소비처 쌍 열거 라운드를 새로 만들자" → `wiring_map.json` 이 이미 존재(08-14 갱신). **"이미 어디서 정의되나 먼저 검색" 규약이 69KB 재구축을 막았다.**

부수 정정: 메모리 카드가 지목한 `02_Infrastructure/ops/wiring_map_build.py` 는 실제로 **`.R`** — §7 죽은 경로 13종 중 1종 해소.

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
6. ~~W30 manifest 결번 원인~~ → **해소 (§1·§6-3)**. 대체 항목: `distill_manifest_20260704.json` 의 `week_of=None` 스키마 드리프트 — 단발이므로 위생.
7. **메모리 명명 드리프트 80건** — rename + 링크 동반 수정 + A/B 재측정(드리프트 80→0 ∧ 마크다운 부재 0 유지). 도훈 확인 후.

---

## 8b. ★대조 대상 사전 고정 (감사 결과 수신 **전** 작성)

감사가 도착했을 때 유리한 것만 고르지 않기 위해, **대조할 주장 12건을 미리 열거**한다.
§10 대조 절은 이 목록을 **전건 순회**하며 `확증 / 부분 / 기각 / 미언급` 중 하나를 붙인다.
목록에 없던 주장을 사후에 추가하지 않는다(추가가 필요하면 그 사실을 명시).

| # | 주장 | 출처 절 | 대조 담당 감사 |
|---|---|---|---|
| C1 | corpus 493 vs 두 인덱스 492 — 신규 L-code 미도달 | §5-#3 | 지식체계 return-path |
| C2 | global AX 승격 이론 후보 = 5건/94 (전부 ramp) | §2.2 | 폐쇄루프 seg1 |
| C3 | `backtested` 비율 52.4%→35.0%→12.9% 단조 감소 | §2.3 | 폐쇄루프 seg1 |
| C4 | 08-13 라운드 6건 전부 forge 미도달 · 최근 WT 40개 forge_package 0 | §2.4 | 인적게이트 worktask |
| C5 | 파이프라인 정지는 QEPM 한정(경량 레인은 08-09 backtested 산출) | §2.5 | 폐쇄루프 seg1 |
| C6 | `emit_lcode` 우회 196/369(53.1%) → grade 비-enum 20 → polarity unknown 17 | §5-#4 | 폐쇄루프 seg1/seg2 |
| C7 | 소비 긍정 사례 실재(WT-006 prechecks)이며 **규약 의무**이지 성실성 아님 | §4.1 | 폐쇄루프 seg2 |
| C8 | WT-D20260813_006 3일 파킹 · 부팅이 "착수 가능 WT"를 노출 안 함 | §3 | 인적게이트 worktask |
| C9 | 도훈 승인 큐(DIST 10 · axiom 18)는 알파 라운드를 **막지 않음** | §3 | 인적게이트 approval |
| C10 | `wiring_map` 표준 모집단에 `axiom/` 0건 (사각) | §5.1 | 지식체계 return-path |
| C11 | `_unverified_reimplementers` 최소 1건 비재현(essence_score) | §5.1 | 지식체계 |
| C12 | 증류 주기 7주 연속 결번 0 | §1 | 지식체계 distilled |

**판정 규칙 (고정)**: 감사와 내 수치가 다르면 **감사 쪽을 기본값으로 채택**한다 — 감사는 적대검증을 거쳤고 내 측정은 안 거쳤다.
단 감사가 **부재 주장**(“없다”)을 내면 내 실측 반례를 우선한다(부재 주장이 이 저장소에서 가장 자주 틀리는 부류).

---

## 10. 감사 대조 (§8b 사전 고정 목록 전건 순회) — 부분

**수신**: 감사 1(지식체계 8표면, agent 56·오류 0·63분) · 감사 2(인적 게이트 6영역, agent 36·오류 0·68분).
**미수신**: 감사 3(Axiom 폐쇄루프) — 최종 판정 1건 진행 중. C2·C3·C5·C6·C7 은 그 감사 소관이라 **보류**로 둔다.

| # | 주장 | 판정 | 근거 |
|---|---|---|---|
| C1 | corpus 493 vs 인덱스 492 — 신규 L-code 미도달 | **부분** | 감사 1 이 더 상류를 지목 — 문제는 인덱스 지연 단발이 아니라 **정정 역전파 부재** 전반. 인덱스는 자가치유 경로가 살아 있다고 판정됨(감사 2 실측: hypothesis_index generated 2026-08-16T15:09/15:29, 1216 entries) |
| C2 | global AX 후보 = 5건/94 (전부 ramp) | 보류 | 감사 3 |
| C3 | `backtested` 52.4%→35.0%→12.9% | 보류 | 감사 3 |
| C4 | 08-13 라운드 6건 forge 미도달 · 최근 WT 40개 forge_package 0 | **미언급** | 감사 2 worktask 영역이 WT 축을 다뤘으나 forge 도달률은 커버리지 갭으로 남음("stage_artifacts 요건 전수 미대조") |
| C5 | 파이프라인 정지는 QEPM 한정 | 보류 | 감사 3 |
| C6 | `emit_lcode` 우회 196/369 → polarity unknown 17 | 보류 | 감사 3 (단 감사 1 Rank5 가 인접 확인: dangling 388 이 `grade='?'`·`construction='unknown'` 조용한 default 로 채점 통과) |
| C7 | 소비 긍정 사례는 **규약 의무**이지 성실성 아님 | 보류 | 감사 3 — 이 감사의 핵심 |
| C8 | WT-006 3일 파킹 · 부팅이 착수가능 WT 미노출 | **기각(부분)** | 감사 2: *"QEPM 3일 무활동 · factor-rotation 7일 — **정상 리듬 범위**. 두 모드 모두 게이트에 걸려 있지 않다"*. 부팅 미노출은 유효하나 '파킹=병목' 프레이밍은 과함 |
| C9 | 도훈 승인 큐는 알파 라운드를 막지 않음 | **기각** | 감사 2 가 **blocks_alpha 4건**을 특정: FQ-009/D3(34일, V02_EP 유일 소비경로) · FQ-095(14일, 데이터게이트 없음·인적 판정 1건) · FQ-125(13일) · FQ-184(7일, `next_action` 이 후속 보류를 문자로 선언). + blocks_capital 1건(G2 현금캐리, 1억당 월 19만원) |
| C10 | `wiring_map` 표준 모집단에 `axiom/` 0건 | **미언급** | 감사 1 이 wiring_map 을 별도로 다루지 않음. 내 측정 유지(반증 없음) |
| C11 | `_unverified_reimplementers` 최소 1건 비재현 | **미언급** | 동상. 내 3중 검사 결과 유지 |
| C12 | 증류 주기 7주 연속 결번 0 | **확증** | 감사 1·2 모두 증류 절차 자체의 정지를 보고하지 않음 |

### 10.1 사전 고정 목록에 **없었던** 감사 발견 (추가 명시)

★§8b 규칙대로 "목록에 없던 주장을 사후 추가하지 않는다"를 지키되, **감사가 새로 찾은 것**은 아래에 별도 표기한다(내 주장이 아니므로 대조 대상이 아니었다).

1. **정정 역전파 부재 + 검사기 대리 지표** (감사 1 headline) — 내 §5 "정본↔소비처 대조 부재"보다 한 겹 깊다. *"정체를 잴 검사기가 전부 대리 지표를 본다: 지도 신선도 2종 mtime · promote crash 는 stdout grep · `[초안]` 마커는 필드 존재 · knowledge_index 는 stale 검사 0줄"* ⇒ **append 만으로 초록이 된다**. 반사실 실측: 08-13 헤더 45행 append(표 행 변경 0)가 감시기를 GREEN 으로 만들었고, 없었으면 82.37h 발화.
2. **layer_bottleneck_map L129 가 철회된 실측치를 게시 중** (감사 1 Rank1) — sha1 `4127c7d65c` 로 08-02 이후 13일·48커밋 바이트 동일. **본 세션이 그 사슬을 한 칸 늘렸다** → §10.2.
3. **INV-7 문서↔코드 시점 괴리** (감사 1 Rank4, CONFIRMED) — `axiom-engine.md:53` 은 negative 5축 면제인데 `promote.R:205-231` 에 polarity 분기 **0건**. 원인 = `promote.R:10` 헤더가 07-04 재정의 **이전 판**을 인코딩. negative 43 제외 교정 히스토그램: external 88→**46** · independence 85→**44** · rigor 4→**0**. ⇒ **내 §2.2 판독은 방향만 맞고 기전을 못 짚었다.**
4. **`Qvest_MonthlyDistill` 08-01 SIGINT 사망, 09-01까지 자동 재시도 없음** (감사 2 침묵정지) — 8월 한 달치 승격 심사가 통째로 미생산. 07-01 이후 신규 심사 0건. ⇒ **내 "승격 정지" 설명의 잃어버린 조각**.
5. **`factor_db` 재빌드 승인 6일 대기 — 정지가 아니라 악화** (감사 2 Rank1) — 445 파일 전부 수리 이전 vintage. 다음 당월 빌드가 **vintage seam** 을 만든다. ⇒ 내 FQ-198 L-code 의 하류를 안 따라갔다.
6. **`hypothesis_index` 가 미승인 카드 105건을 `DISTILLED_*` 로 서빙** (감사 2) — 코드는 `expired` 만 거른다. *"쌓인 게 아니라 **반대 방향으로 새는 것**"*.
7. **연령을 무응답으로 읽으면 안 된다** (감사 2 coverage_gap) — 승인 큐의 유일한 상시 노출면이 모닝브리핑 stdout, 부팅 노출 0건 ⇒ 상당수가 **미상신**.
8. **낡은 미결 표식 = 대기가 아니라 결함** (감사 2 영역5) — 예: `pit.md:25` C4 "xlsx Q4 +45d 수리 항목"이 2026-07-25 이미 집행. **Level 0 룰이 22일째 낙후**.
9. **`marker_fresh` 교차-세션 누수** (본 세션 실측, 감사 외) — `.cache/last_round_closure.json` 단일 공유 파일을 정체 확인 없이 소비. 다른 세션의 `INFRA-WT-PURGE-20260816`(16:01:18)이 본 세션 턴의 연속성 계약을 충족시켰다. 칩 `task_f0e493c1`. ⇒ §5 표의 **5번째 동류**. **[2026-08-16 수리 완료]** — 실제 훅 경로(`user_ts` 존재)에서 누수 재현 확인 후 정체 계약 도입(`session_id` 신고 + transcript 파일명 대조 + 세션별 마커). §5 #5 참조. 검사 `08_Tests/hooks/test_continuity_marker_identity.py` 28/28 배터리 등재.

### 10.2 본 세션이 만든 오염 1건 — 발견·수리

`DIST-AR-051`(2026-08-15 본 세션 초안, status=proposed) 이 **08-08 v49 가 이미 철회한 ΔIR +0.1692 를 "배제-필터 경로(통과)" 의 근거로** 삼고 있었다. 카드의 중심 명제가 그 수치 위에 서 있었으므로 각주 수정이 아니라 명제 재작성.

- 철회 원문 대조(감사 보고 복사 아님, `layer_bottleneck_map.md` L123 v49 직접 열람): production 실코드 n=256 에서 IR 1.5592→1.4103 · **ΔIR −0.1489** · paired t **−1.9763** · MDD −23.29%→**−26.20%**. 게이트 A/B/C PASS(max_dret 5.13e-16) = 측정 오류가 아니라 결과가 다름.
- 신규 지식(정정이 캐낸 것): **가중 규칙이 축** — `capnorm25_wt014_style +0.1579` 만 양수, 나머지 4셀 전부 음수. 그 유일한 양수 셀조차 **paired t −0.253** ⇒ ΔIR 은 가중 규칙 조건부 국소량.
- 2026-08-16 정정 완료(status=proposed 유지, 주입 안 됨). 카드에 정정 이력 절 삽입.

⇒ **이 카드 자체가 '정정 역전파 부재' 의 실례**이고, 본 세션이 그 사슬의 최신 항이었다.

### 10.3 본 세션이 해소한 것

- continuity `pending_novel` **4 → 0**(dismiss, suppressions 1→5). 감사 2 가 *"판정은 났는데 상태는 안 바뀐"* 으로 지목한 항목이며 **규칙상 /cleaner 세션 소관**(도훈 사안 아님 — `continuity-firewall.md:51`).
- 차단 실효 확인: dismiss 후 diag 에서 `closure.detected=true` + 3어휘 매치 ⇒ 탐지축 정상. 통과는 `contract.satisfied` 단일 사유였고 그것이 §10.1-9 결함.
- 감사 2 가 payload 절단으로 놓친 2영역(`영역 5`·`영역 6`)을 journal 에서 회수 — 절단은 본 세션의 워크플로 설계 실수(payload 180KB 상한).

---

## 9. 미측정 (정직 기록)

- 폐쇄루프 **행동 변경률** — 이 문서의 핵심 공백. 감사 segment 2 소관
- 엔진이 **한 번이라도** 승격을 끝까지 돌린 적 있는지 (corpus `n_promoted=2` 가 단서) — 감사 segment 1
- INV-7 **부활 신호 발화 이력** — 감사 segment 4
- 주입 훅이 실제로 무엇을 읽어 무엇을 넣는지 — 감사 segment 5
- `_unverified_reimplementers` 오분류의 **정확한 기전** (1건 비재현까지만 확인)
- W30 manifest 결번의 세션 로그
- 08-15 digest 38.8 KB 가 과한지 — 작성자 자신이라 판정 보류
