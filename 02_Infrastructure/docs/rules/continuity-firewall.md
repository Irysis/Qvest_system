# Continuity Firewall — 포기 원천차단 (Level 0 SOT)

> **SUSPENDED 2026-08-23 (v9)** — L1 Stop 차단 등록 해제; L3 계약은 L-code 발행(`run_alpha_search.R::.write_lcode`, `lcode_schema.R` v3)에서 검사; `continuity_gate.py`는 수동 감사 도구로 존치.
> 즉 아래 본문의 L1/L2 기계 차단 서술은 **현행이 아니다**(Stop 차단 훅 0). 계속-산출 요건은 lean 라운드에서 next_probe ≥ 2 + 부활 조건(`live_trigger`)으로 축소돼 L-code 발행 1지점에서만 검사되며, 미충족은 `[L-CODE WARN]` 후 발행(차단 아님)이다. 규범 위치 = `.claude/rules/lean-loop.md` "연속성 계약" 절.

**발효**: 2026-07-15 (도훈 mandate — "자체적으로 포기하지 않는 자가발전형 아키텍처. 누적 실패 후 '끝남 표현들'로 라운드를 마무리하려는 것을 원천차단"). **위반 = AX-002 동급.**
**계보**: answer-principles 연속성 6호(2026-07-13 헌법 승격) + research_continuity_guard.sh(warn) → **본 SOT가 block으로 승격·확장**. settings.json `_doc_research_continuity`가 예고한 "2주 관찰 후 block 승격"의 집행.

---

## 0. 문제와 원천차단 원칙

**문제(실측)**: 4번의 메모리 강화 + 헌법 승격 + 기계 가드(warn)에도, 2026-07-14 도훈이 종결어휘("종착·완결·끝")로 **3회 재적발**. 원인은 구조적이다 (아키텍처 연구 wf_2a348b0e, T3·T4 판정):
- **사후 넛지**: 기존 가드는 warn-only Stop 훅 — 종결 턴이 이미 나간 *뒤* 다음 턴에 컨텍스트만 주입. 현재 턴을 못 잡음.
- **regex 두더지잡기**: 순수 regex라 새 종결어휘를 발명하면 매번 우회(07-14 적발 3개가 정확히 패턴에 없던 신어).
- **semantic-primary 미배선**: §0.1은 "판정은 LLM 우선"이라는데 자동 판정 LLM이 어디에도 없음 → "semantic primary"의 실체 = 편향 당사자인 Q-Lead 자기-자가체크뿐(= 그게 4회 실패한 컴포넌트).

**원천차단 원칙**: 더 많은 넛지로는 안 풀린다. 원천차단 = **차단(block) + 독립 판정 + 자가발전 + 건설적 강제** 4개 동시.
**★핵심 전환**: "끝남 단어 금지"(어휘 발명에 매번 짐) → **"계속 산출물 요구"**(next_probe≥2·소비면을 실제로 냈나 — 단어교체로 못 속임).

**불변(막지 않는 것)**: 게이트는 *판정 자체*를 막지 않는다. negative·천장·config-scoped 결론은 정당하다(AX-000·INV-7). 막는 것은 오직 **계속을 생산하지 않는 종료**뿐. 즉 게이트 통과 = 정당한 라운드 수렴(config-scoped negative + frontier), 게이트 block = 계속-산출물 결측. INV-7의 "negative = 탐색지도(frontier+live_trigger)"가 곧 통과 조건이다.

---

## 1. 4-레이어 아키텍처

| 레이어 | 무엇 | 파일 | 원천차단 기여 |
|---|---|---|---|
| **L1 차단 실효** | Stop 훅이 `{"decision":"block"}` 발행 → 종결 턴을 되돌려 강제 속행 | `02_Infrastructure/hooks/research_continuity_guard.sh` | 사후 넛지가 아니라 그 턴을 못 끝내게 함 (T4 recommended_probe 집행) |
| **L2 독립 semantic 판정** | 케이스 결정론 + verdict-close 일반화(신어 커버) + 선택적 Haiku | `02_Infrastructure/axiom/continuity_gate.py` | 신어로 우회 불가·편향 당사자 self-certify 차단 (T3 갭 메움) |
| **L3 건설적 종료계약** | next_probe≥2 (+negative면 live_trigger)를 인자로 강제 | `02_Infrastructure/contracts/close_round.R` | "단어만 지우고 멈추기" 봉쇄 — 계속을 *생산*해야 종료 허용 |
| **L4 자가발전** | 케이스 라이브러리 성장 + 차단감사 + 주간 cleaner 승격 | `06_Registry/continuity_cases.json` · `.cache/continuity_blocks.jsonl` · `.cache/continuity_pending_cases.json` | 새 우회를 잡을수록 강해짐 (§0.1 원리 3·4·5) |

### L1 — 차단 실효 (research_continuity_guard.sh, Stop hook)
- `continuity_gate.py --transcript`로 판정을 받아 block JSON이면 그대로 전달(강제 속행) + 차단 이력을 `.cache/continuity_blocks.jsonl`에 append.
- pass면 W3(라운드 수집 후 layer_bottleneck_map 미갱신) warn만 잔존.
- **무한루프 방지 3중**: 게이트 내부 per-turn cap(기본 3, user_ts 키) + `stop_hook_active` + ERR trap → `{}`(fail-open). 포기억제가 목적이지 작업차단이 아니므로 어떤 오류든 통과.
- 등록: `.claude/settings.json` "Stop" 배열 (기존 warn 등록의 스크립트 내부 승격 — settings 재등록 불요).

### L2 — 독립 semantic 판정 (continuity_gate.py)
- `research_context(text)`: 리서치 라운드 턴에서만 발화(비-research "파일 저장 완료"는 통과).
- `detect_closure`: (a) 케이스 backstop 어휘 (b) waiting-posture (c) **verdict-close** = 마감 영역의 negative/종결-특정 토큰(신어에도 일반화, 조사-강건). "확정/완료" 같은 중립어는 제외 → progress 보고 오차단 방지.
- `check_contract`: **정밀도 원칙** — bald 포기 vs 정당 종료를 가르는 최고신호 = `next_probe≥2` (+negative면 `live_trigger`). 소비면 라우팅(연속성 4호)은 soft 권고(하드 강제는 L3 close_round 인자). fresh `close_round()` 마커면 계약 이미 충족.
- **판정 = detected AND NOT contract_satisfied → block.** (LLM 단계는 detection recall만 넓힘 — 계약이 객관 게이트라 LLM이 통과를 강제로 clear하지 못함 = self-certify 차단.)
- **선택적 Haiku**: `QVEST_CONTINUITY_LLM=1` + `ANTHROPIC_API_KEY` 시 독립 semantic 판정(few-shot=케이스). 기본 OFF(네트워크 비의존·graceful fallback). 결정론 판정기 자체가 케이스-라이브러리 구동 분류 + 계약 검사라 semantic-급.

### L3 — 건설적 종료계약 (close_round.R, paved path)
- `close_round(round_id, verdict_type, mechanism_diagnosis, next_probes, consumer_surfaces, frontier_update, live_trigger, layer, evidence_refs)`.
- **강제 검증(미충족=stop)**: verdict_type ∈ 6-enum(종결어휘 대신 구조화) · mechanism ≥20자 · **next_probes ≥2** · consumer_surfaces 또는 frontier ≥1 · **negative면 live_trigger 필수**.
- 통과 시 `.cache/last_round_closure.json` 마커 발행(→ L2 게이트 자동 통과) + `.cache/round_closures.jsonl` 감사 + **사람용 요약 반환**(Q-Lead가 이걸로 보고 → 구조화 필드 = 서술의 원천, "make the right thing the only expressible thing").

#### ★마커 정체 계약 (2026-08-16 수리 — 교차-세션 누수)
- **결함**: 구 `marker_fresh` 는 마커의 **mtime 만** 봤다. 그 파일은 루트 단일 파일이고(main 의 `.cache` 는 `/c/qm_cache` **심볼릭 링크** = 머신 공유), settings.json 이 `DIR=${CLAUDE_PROJECT_DIR:-${QM_ROOT:-$PWD}}` 로 훅을 세우는데 **Bash/훅 환경에 `CLAUDE_PROJECT_DIR` 이 없어** 모든 워크트리 세션이 main 의 같은 마커를 읽고 쓴다. ⇒ 병렬 세션이 내 프롬프트 이후 아무 라운드나 닫으면 mtime 이 내 턴 안으로 들어와 **남이 생산한 계속으로 내 턴이 통과**했다. docstring 은 *"이번 턴에 쓴 마커"* 라 선언했고 `round_id` 를 읽기까지 했으나 **검증에 쓰지 않았다** — 존재/신선도 검사로 정체 검사를 대체한 계통(감사 §5 5번째 동류).
- **실측 재현**(2026-08-16, **실제 훅 경로 · user_ts 존재**): 같은 종결 텍스트가 `user_ts=07:25Z` → **PASS**(`marker_round_id=INFRA-WT-PURGE-20260816-P2`, 이 세션이 만든 라운드 아님) / `user_ts=07:35Z` → **BLOCK**. 갈린 것은 서술이 아니라 **남의 mtime**.
- **계약**: ① `close_round()` 가 마커·원장에 `session_id`(발행자 신고)를 쓴다 ② 게이트가 **자기 세션 id** 와 대조한다 — 훅 경로의 권위 출처는 **transcript 파일명**(`<CLAUDE_CODE_SESSION_ID>.jsonl`, 실측 확인), env 는 폴백 ③ 세션별 마커 `.cache/round_closure_by_session/<session_id>.json` 을 함께 발행한다 ④ 게이트는 자기 루트 + **공유 루트**(`QM_ROOT`/`CLAUDE_PROJECT_DIR`)를 함께 훑는다.
- **③이 왜 필수인가**: ①②만 넣으면 **역방향 회귀**가 난다 — 공유 파일은 마지막 1건만 담으므로 병렬 세션이 내 마커를 덮어쓰면 내가 **정당히 닫은 턴이 차단**된다. 세션별 파일이 포장도로를 보존한다.
- **④가 왜 필수인가 — ★쓰는 쪽과 읽는 쪽의 루트가 갈려 있었다 (2026-08-16 동반 발견)**: `close_round()` 는 **Bash 툴**에서 도는데 그 환경엔 `CLAUDE_PROJECT_DIR` 이 **없어** `QM_ROOT`(=main)의 `.cache` 에 쓰고, **Stop 훅**에는 `CLAUDE_PROJECT_DIR` 이 **설정돼** 게이트는 **워크트리 루트**의 `.cache` 를 읽는다. ⇒ 워크트리 세션에서는 정당하게 닫은 마커가 **원리적으로 게이트에 안 보인다**(포장도로 사망 = 상시 오차단 원천).
  - 실측 근거: 워크트리 `.cache` 에 게이트가 쓴 `continuity_blocks.jsonl`·`continuity_gate_counters` 는 **존재**하는데 closure 파일은 **0건**이고, 종료 기록 **468건 전부**가 main 의 `.cache`(→ `/c/qm_cache` 심볼릭 링크)에 있다. 즉 reader-root=워크트리 · writer-root=main 이 같은 시각에 공존한다.
  - **정체 검사가 있으므로 공유 루트를 훑어도 안전하다** — 남의 마커는 `foreign_session` 으로 떨어진다. *정체 없이 공유하면 누수, 정체가 있으면 공유 디렉토리는 그냥 공용 보관소다.* (검사 L2 가 이 안전성을 확인 — 루트 확장이 누수를 되열지 않는지.)
- **fail-closed**: 정체 확인 불가(세션 불명 · `session_id` 필드 없는 구판 마커 · 불일치)면 마커를 인정하지 않는다. 인라인 경로(next_probe≥2 + 부활조건)는 무영향이라 정당한 종료는 계속 통과한다. 차단 사유는 `contract.marker_why` ∈ {`own`,`foreign_session`,`unattributed`,`stale`,`no_marker`,`unknown_session`} 로 진단 가능하게 남는다.
- **검사**: `08_Tests/hooks/test_continuity_marker_identity.py` (배터리 등재, **31/31**) — 위반 주입 양방향(A 자기 마커 PASS · B 남의 마커 BLOCK · C 마커 없음 BLOCK) + D 구판 마커 · E stale · **F 덮어쓰기 회귀** · G fail-closed · H 인라인 무영향 · **I 돌연변이**(구 mtime-only 복원 시 B 가 PASS 로 뒤집힘 = B 의 차단이 정체 검사에서 온다는 실증) · **L 루트 갈림**(L1 다른 루트의 내 마커 발견 / L2 그래도 남의 것은 차단) · J 실훅 E2E 양방향 · K R 계약 도달.

#### ★판정 산출물 정체 계약 (2026-08-17 — 같은 뿌리의 **두 번째** 누수)
- **결함**: `turn_verdict_artifacts`(C1 운영-턴 판별)도 종료 기록 2종(`.cache/round_closures.jsonl`·`last_round_closure.json`)의 **mtime 만** 봤다. 같은 공유 파일이므로 **병렬 세션이 라운드를 닫으면 내 턴이 '판정 생산 턴'으로 오인**되고, 과거 판정 어휘를 인용만 한 운영/브리핑 턴이 차단된다.
- **왜 마커 수리에서 범위 밖이었나, 그리고 그 전제가 왜 깨졌나**: 방향이 반대다 — 마커 누수는 **우회**(남의 계속으로 내 종결이 통과), 이쪽은 **과차단(FP)**. 그래서 "재현율을 깎는 변경"으로 보고 먼저 재기로 했다. 그런데 실측이 뒤집었다: **같은 남의 종료가 `va=True` 로 탐지를 살리는 동시에 구 `marker_fresh` 를 `True` 로 만들어 계약을 충족시켜 통과시켰다 — 두 누수가 서로를 가렸다.** 마커 축만 고치면 가림막이 걷혀 **FP 가 무장된다.**
- **실측** (transcript 전수 163파일 · **1,282턴** 재판정 · 루트 조건부): 구판 차단 **276** → 마커만 수리 **302** → 두 축 다 수리 **297**. 차이 **5건 전부 main 루트 · 전부 '남의 종료만'**, 그리고 **제안이 현재를 넘어 막는 건 0**(단조 완화). 워크트리 `.cache` 엔 closure 파일이 0건이라 이 누수는 **main 루트 세션에만** 닿는다(962턴 중 5 = 0.52%). 노출은 큼 — 종료 원장 **473건/16일**(측정 시점 스냅샷) = 평균 **29.6/일**(최대 121/일).
  - ★**라벨은 '미결'도 '효과 없음'도 아닌 '가려진 실재(masked)'** — 실운영 차단 98건 중 `verdict_close` 단독 의존은 3건뿐이고 그 3건은 창 안 closure 가 없었다(**closure 축** 귀속 실차단 = 0). 그 0 은 결함 부재가 아니라 마커 누수가 가린 결과다. 처분이 다르다: 재기가 아니라 **즉시 수리**. ⚠**그 3건 중 2건은 아래 산출물 축이 실제로 만든 차단이다**(2026-08-17 후속 실측) — 축을 나눠 세지 않으면 '0' 이 표면 전체의 결백처럼 읽힌다.
- **계약**: 종료 기록 3종(세션별 마커 · 공유 마커 · 원장 꼬리 판독)에만 `session_id` 대조를 건다. `stage_artifacts/l_code/**` · `qepm/mailbox/**/verdict.json` 은 **mtime 판정 유지** — 정체 필드가 없으므로 **정체를 확인할 수 없는 표면에 정체 검사를 흉내내지 않는다**(그 흉내가 곧 존재검사=정체검사 대체의 재생산이다).
  - ⚠**정정 + 잔여 실측 (2026-08-17)**: 초판은 *"이 둘은 워크트리마다 자기 사본이라 공유 누수 표면이 아니다"* 라고 덧붙였는데 **main 루트에 대해 틀렸다**. 디렉토리는 실사본이 맞으나(심볼릭 링크 아님 — 전 트리 확인) **같은 main 트리에서 세션이 동시에 돈다**: main 세션 열림 **876h 중 68.9%가 동시 2세션 이상**(85 세션 · 겹치는 쌍 238). ⇒ 이 표면도 병렬 세션 간 공유다.
  - **잔여 FP 실측**: main 935턴 중 **2건**이 '남의 산출물만' 으로 갈렸고, 그 2건은 **실운영 차단 로그의 실제 차단**(2026-08-08 00:36·08:17)이다. ★즉 두 축의 실현 양상이 반대다 — closure 축은 marker 누수에 **가려져 0건 실현**, 산출물 축은 가릴 것이 없어 **2건 실현**. 규모는 작다(쓰기율 2.90건/일 vs 종료 원장 29.6건/일).
  - **수리 방향(범위 밖·별도 태스크)**: 탐지 휴리스틱(경로가 tool_inputs 에 있나)은 안 된다 — `emit_lcode` 가 파일명을 **함수 안에서** 만들어 호출자 인자에 안 나타나므로 포장도로가 오탐된다. 옳은 방향은 `close_round` 이 한 것과 같은 **생산자 쪽 정체 신고**(`emit_lcode` 가 `session_id` 를 찍게).
- **★fail 방향은 축마다 반대다 (의도)**: `marker_fresh` 는 귀속 불가 시 **미인정(fail-closed)**, `turn_verdict_artifacts` 는 귀속 불가 시 **증거로 셈(fail-open, 기존 선언 유지)**. 마커를 잘못 인정하면 **우회**(포기가 통과), 종료 기록을 잘못 무시하면 **재현율 손실** — 각 축을 자기 실패의 값싼 쪽으로 넘어뜨린다. 억제 사유는 `foreign_closure_only` 로 별도 라벨링(→ `passes_*.json` 에서 사후 FP율을 transcript 재발굴 없이 셀 수 있다).
- **★전이 구간 (2026-08-17 실측 — 수리는 무장됐으나 휴면)**: 이 수리의 실효는 `close_round()` 가 `session_id` 를 실제로 찍느냐에 달려 있다. 실운영 원장 꼬리 14건 중 **session_id 보유 0건**(오늘 쓰인 `IMPROVE_DRAIN_R1_20260817`·`KNOWLEDGE-SYSTEM-AUDIT-20260817` 포함) — 수리된 `close_round.R` 이 아직 main 에 없기 때문. 그동안 모든 종료 기록은 `unattributed` 로 떨어져 **fail-open = 구판 동작**이다(FP 가 그대로 살아 있다). ⇒ **게이트 수리와 `close_round.R` 수리는 함께 랜딩해야 의미가 있다**; 랜딩 후 첫 `close_round()` 호출부터 자동 치유된다. 쓰는 쪽 정체 출처(`CLAUDE_CODE_SESSION_ID`, Bash 툴 env)와 읽는 쪽(transcript 파일명)이 **같은 값임을 실측 확인**(`134faab0-…` 일치) — 두 축의 정체가 갈리지 않는다.
- **검사**: `08_Tests/hooks/test_continuity_verdict_artifact_identity.py` (배터리 등재, **28/28**) — **override 없이 실제 파일을 심는다**(케이스마다 새 임시 root). A 자기 종료 PASS · **B 남의 종료만 → 억제 PASS** · C 종료 없음 PASS · D 구판 기록 BLOCK(fail-open) · E 세션 불명 BLOCK · **F 명시 종결어휘는 va 무관 BLOCK**(재현율 불변) · G l_code 는 mtime 유지 · H 원장 단독 귀속 3종 · **I 돌연변이**(mtime-only 복원 시 B 가 BLOCK 으로 뒤집힘) · J 루트 갈림 양방향 · **K E2E**(실훅 `--transcript`, **K0 양성 대조** 선행).
  - ★이 배터리가 따로 필요한 이유 = 5-a 와 같은 기전의 재발: 기존 `test_continuity_gate.py`(31/31)는 `verdict_artifact_override` 로 이 축을 절연해 **함수 본문이 한 번도 실행되지 않는다**. **옳은 격리가 무커버 표면을 만든다** — 그 표면은 별도 배터리로 덮는다.
  - ★작성 중 자기 결함 1건: E2E 샌드박스에 케이스 사전을 안 심어 게이트가 `load_cases` 에서 죽고 **fail-open `{}`** 을 뱉었는데 '차단 안 됨'이 그대로 초록이 됐다(통과 축이 게이트를 돌리지도 않고 PASS). 반대 방향 축이 잡았고, **K0 양성 대조**(하네스가 차단을 낼 수 있는가)를 통과 주장 앞에 두어 재발을 막는다.

### L4 — 자가발전 (§0.1 원리 3·4·5)
- 게이트가 **신어(backstop 사전 밖·verdict_close로만 잡힌)** 차단 시 `_capture_pending`이 `.cache/continuity_pending_cases.json`에 후보 자동 포착.
- 주간 `weekly_cleaner_sweep.R` step [3.7]가 `continuity_gate.py --review`를 호출해 pending을 `cleaner_pending.json` 다이제스트에 실음 → **/cleaner 세션이 category/why/reframe 정제 후 `--append-case`로 승격**.
- **★firewall 실패 회피**: 연구 T3이 밝힌 `append_firewall_case() caller 0건 → 코퍼스 07-04 정지`를 반복하지 않도록, (a) 게이트 자동 pending 포착 (b) cleaner 실배선 caller (c) 도훈 수동 적발 시 즉시 `--append-case`, 3중 caller로 성장 보장.

---

## 2. 통과/차단 규약 (Q-Lead 실무)

**차단당하지 않으려면 (= 정당한 라운드 종료)**:
1. `close_round()`를 호출한다(권장, paved path) — 마커가 게이트를 자동 통과시킴, 또는
2. 인라인으로: verdict를 구조화 어휘로 서술 + 기전 진단 + **next_probe ≥2** + (negative면) **부활 조건** + 소비면.

**금칙(종결어휘)**: 소진 판정/계열 소진/폐쇄 판정/종결/종착/완결(라운드·아크)/끝(끝났다·방향 끝)/막다른 길/재시도 가치 없 — `06_Registry/continuity_cases.json` categories 참조. 단 이 어휘가 있어도 **계약을 충족하면 통과**(어휘가 아니라 계약이 게이트).

**재프레이밍 맵** (continuity_cases.json `reframe_map`):
- "이 방향 끝" → "이 config는 (측정틀) 미달·수렴 — 미검 축 [X], 부활 조건 [Y]. next_probe: ①②"
- "아크 완결" → "이 아크의 소비형태 N종 실측 완료 — 확립 능력 [Z], 미검 소비면 [W]. next_probe: ①②"
- "계열 소진/재시도 금지" → "config-scoped 음-소진(차별점 없는 재탕 저EV) — 재도전 신호 [부활조건], 미검 인접 [frontier]"

---

## 3. AX-000/INV-7 정합 (막지 않는 것 재확인)

- 게이트는 **성능 판정·자본 kill·negative 결론을 막지 않는다**. graduation HARD 3종(discovery_graduation_gate)·governor는 독립. 게이트는 *서술 형태*(계속 산출물 유무)만 본다.
- INV-7("negative = Distilled 탐색지도, 영구 판결 아님")이 요구하는 것(frontier+live_trigger)이 곧 게이트 통과 조건 → **게이트는 INV-7의 실무 집행자**.
- AX-000("소수 실패로 dead-end 단정 금지")의 lexical 백스톱을 넘어, **계속 산출물을 물리적으로 요구**함으로써 "포기 편향"을 성향(disposition)이 아니라 계약(contract) 레벨에서 차단.

---

## 4. 운영 노트

- **테스트**: `"$QVEST_PY" 02_Infrastructure/tests/test_continuity_gate.py` — **31/31 배터리**(2026-07-25 실측 현행화. 구 "12/12"는 케이스 확장 전 수치) — 역대 우회어 BLOCK·정당종료 PASS·신어 anti-whack-a-mole·paved-path·ADV 우회 10종·회귀 재현(RP) 케이스. bare `python`은 이 환경에서 Store 스텁이라 실행되지 않는다([[reference-python3-windows-stub-use-qvest-py]]).
  - **★배터리는 판정용 root를 임시 디렉토리로 격리한다** (2026-07-25 수리). 종전엔 `judge_text(root=<실제 저장소>)` 라 `marker_fresh()` 가 운영 마커 `.cache/last_round_closure.json` 을 조회했고, **마커가 fresh 인 동안 차단 케이스 22건이 전부 통과**했다(실측: 마커 존재 시 9/31 · 마커 격리 시 31/31). 게이트가 아니라 배터리가 오염된 것으로, 정상 운영 중 배터리를 돌리면 *"차단 능력이 있다"는 거짓 확신*을 준다 — 가드의 가드가 오염되는 계열이라 더 위험하다. 원칙: **테스트 결과가 운영 상태에 의존해선 안 된다.** 마커가 필요한 케이스는 `marker_override` 로 명시 주입(P6가 그 경로를 검증).
  - **⚠그 격리의 대가 (2026-08-16 발견)**: root 를 비우고 포장도로를 `marker_override=True` 로 주입한 결과, **`marker_fresh()` 본문이 이 배터리에서 한 번도 실행되지 않는다** — 교차-세션 정체 누수가 31/31 초록 아래에서 잠복한 이유다. 격리는 옳지만 그것만으로는 마커 경로가 **무커버**가 된다. ⇒ 마커 자체를 재는 축은 별도 suite 로 분리: `08_Tests/hooks/test_continuity_marker_identity.py`(케이스마다 새 임시 root 에 마커를 **정체·mtime 지정으로 심어** 실행하므로 운영 상태 비의존 원칙은 유지).
- **stats/review**: `continuity_gate.py --stats` / `--review` (pending 신어 후보).
- **수동 케이스 추가**: `continuity_gate.py --append-case <category> <caught_text> <why> <reframed_to>` (도훈이 새 우회 적발 시 즉시).
- **LLM 토글**: `QVEST_CONTINUITY_LLM=1` + `ANTHROPIC_API_KEY` (§0.1 semantic-primary 완전체. 기본 OFF).
- **fail-open**: 게이트/훅 오류는 전부 통과 — 원천차단이 목적이지 작업을 깨지 않는다.

### 4.1 적용 범위 = 리서치 턴 한정이 아니다 (2026-07-25 실측 판정, 도훈 승인 next_probe ④)

**판정: 인프라/하네스 턴에도 적용 유지.** 별도 인프라용 verdict enum은 만들지 않는다.

이 SOT는 리서치 라운드를 전제로 쓰였으나, 하네스 수리 턴에서 발화한 실사례가 **오발화가 아니라 정발화**임을 실측으로 보였다. 사례(hook 테스트 계측 사망 수리, `89551963`~`d6f70fcf`):

- Q-Lead가 승인 3건을 완료한 뒤 **잔여 8건을 "도훈 판단 대기"로 접고 마감**하려 했다 → 게이트 block(`finality_noun`, `waiting_posture_close`).
- 막힌 덕에 그 8건을 **실제로 실행**했고, 그 결과:
  - `08_Tests/regime/run_all.R` 이 `0 passed / 0 failed (of 0 total)` — 방금 고친 것과 **같은 계측 사망 위장이 현재 진행형으로 잔존**함을 발견(수리 → 5 total 복원).
  - Q-Lead의 사전 분류 **2건이 실측으로 반증**됨: `test_v8_readiness_gate.R` "무조건 사망" → 실제 12/12 PASS / regime 6건 "env 있으면 동작" → 실제 env 무관 전멸(가드가 env를 안 봄).
- 즉 게이트가 막지 않았다면 **현재 진행형 결함 1건 + 잘못된 보고 2건이 그대로 남았다.**

★일반화: 위험한 것은 '리서치 라운드'라는 주제가 아니라 **"코드 형태만 보고 상태를 추정한 뒤 대기 목록으로 접는 자세"** 다. 이 자세는 인프라 턴에서 오히려 더 흔하다(실행이 싸고 빠른데도 안 돌려본다). 연속성 1호(대기-모드 마감 금지)·3호(next_probe≥2)는 도메인 무관하게 유효하다.

**표현 방법**: 하네스 턴도 기존 enum으로 무리 없이 닫힌다 — `verdict_type="capability_established"` + `layer="harness"`, next_probe = 미측정 표면, live_trigger = 회귀 감시 조건(예: "배터리 총계가 직전 실측 대비 감소하면 회귀가 아니라 침묵 결손으로 의심"). 실제 발행 예: `HARNESS-20260725-hook-test-measurement`.

## 5. 참조
- `02_Infrastructure/docs/rules/answer-principles.md` 리서치 연속성 6호(본 SOT가 6호의 집행 아키텍처. 2026-08-23 v9 이동 — 구 경로 `.claude/rules/`)
- `02_Infrastructure/docs/rules/axiom-engine.md` §0.1(메커니즘 비-ossification)·INV-7
- 연구: `04_Research/01_reports/` 포기방식 아키텍처 연구(wf_2a348b0e, 2026-07-15) — 7표면·6긴장점
- 메모리: [[project-continuity-firewall-20260715]]

## Change log
- 2026-08-17: L2 §마커 정체 계약에 **판정 산출물 정체 계약** 추가 — `turn_verdict_artifacts` 의 같은-뿌리 두 번째 누수(공유 종료 기록 mtime → 남의 라운드 종료가 내 턴을 '판정 생산 턴' 으로 만듦) 수리. 1,282턴 재판정으로 **두 누수가 서로를 가리고 있었음**을 실측(구판 276 / 마커만 302 / 둘 다 297, 차이 5건 전부 main 루트). fail 방향을 축마다 반대로 두는 원칙 명문화(마커 fail-closed · 산출물 fail-open). 검사 `test_continuity_verdict_artifact_identity.py` **28/28** 신설·등재, 기존 31/31 × 2 불변.
- 2026-07-25 (2): 배터리 판정-root 격리 수리 + §4 현행화. 실측 마커존재 9/31 → 격리 후 **31/31**(마커 유무 무관 결정론). 구 문서 "12/12"는 케이스 확장 전 수치라 31로 정정, 실행 안내도 bare `python` → `$QVEST_PY` 로 교체. 도훈 승인 next_probe ①④.
- 2026-07-25: §4.1 추가 — 적용 범위가 리서치 턴 한정이 아님을 실측 판정(도훈 승인 next_probe ④). 하네스 수리 턴 발화 = 정발화 실증(대기-모드 마감을 막아 regime 0-total 위장 + 사전 분류 오류 2건 적발). 기존 enum(`capability_established`+`layer="harness"`)으로 표현 가능해 인프라용 별도 enum 미도입.
- 2026-07-15: 신규. warn→block 승격 + L2 독립 semantic 판정 + L3 건설적 종료계약(close_round) + L4 자가발전. 12/12 배터리·E2E(block/pass/paved-path)·cleaner 통합 검증. 도훈 mandate.
