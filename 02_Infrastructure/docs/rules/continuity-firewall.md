# Continuity Firewall — 포기 원천차단 (Level 0 SOT)

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
- `.claude/rules/answer-principles.md` 리서치 연속성 6호(본 SOT가 6호의 집행 아키텍처)
- `02_Infrastructure/docs/rules/axiom-engine.md` §0.1(메커니즘 비-ossification)·INV-7
- 연구: `04_Research/01_reports/` 포기방식 아키텍처 연구(wf_2a348b0e, 2026-07-15) — 7표면·6긴장점
- 메모리: [[project-continuity-firewall-20260715]]

## Change log
- 2026-07-25 (2): 배터리 판정-root 격리 수리 + §4 현행화. 실측 마커존재 9/31 → 격리 후 **31/31**(마커 유무 무관 결정론). 구 문서 "12/12"는 케이스 확장 전 수치라 31로 정정, 실행 안내도 bare `python` → `$QVEST_PY` 로 교체. 도훈 승인 next_probe ①④.
- 2026-07-25: §4.1 추가 — 적용 범위가 리서치 턴 한정이 아님을 실측 판정(도훈 승인 next_probe ④). 하네스 수리 턴 발화 = 정발화 실증(대기-모드 마감을 막아 regime 0-total 위장 + 사전 분류 오류 2건 적발). 기존 enum(`capability_established`+`layer="harness"`)으로 표현 가능해 인프라용 별도 enum 미도입.
- 2026-07-15: 신규. warn→block 승격 + L2 독립 semantic 판정 + L3 건설적 종료계약(close_round) + L4 자가발전. 12/12 배터리·E2E(block/pass/paved-path)·cleaner 통합 검증. 도훈 mandate.
