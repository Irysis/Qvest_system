# memory_inbox — 무인 레인의 기억 후보 대기열

**발효**: 2026-09-24 (P0-M1 · 도훈 결정 "기억 무결성 전부 승인")
**처리**: 주간 `/cleaner` §1 ③b — 세션(Q)이 판정한다. 무인 레인은 여기에 **쓰기만** 한다.

## 왜 있나

무인 LLM 레인(`claude -p`)이 Claude 기억 디렉터리(`~/.claude/projects/<프로젝트>/memory/`)를 직접 쓰고 있었다.
2026-08-31~09-23 사이 무인 세션 27개가 카드 19장을 만들거나 고쳤고(09-24 transcript 전수 스캔 기준), 충실구현 레인 한 세션(5c9bd9b4, 09-07)은
`MEMORY.md` 를 통째로 다시 썼다. 같은 기간 무인 세션 519개 중 416개가 성과 수치가 든 `MEMORY.md` 를 자동으로
주입받았다 — 성과를 보지 않아야 하는 설계 레인까지 포함해서다(D7-02).

그래서 지금은 두 층으로 막는다.

1. **자동 기억 끔** — 무인 LLM 호출은 `02_Infrastructure/ops/rf_llm_env.sh::rf_llm_agent_run` 한 곳으로만 뜨고,
   그 함수가 `CLAUDE_CODE_DISABLE_AUTO_MEMORY=1` 을 싣는다. 기억을 읽지도, 기억 규약 안내를 받지도 않는다.
2. **쓰기 차단** — 같은 함수가 `QVEST_UNATTENDED_LANE=1` 을 싣고, 훅 `02_Infrastructure/hooks/safety_guard.sh`
   Rule 3 이 그 표식을 보면 기억 경로 쓰기(Write·Edit·Bash)를 막고 이 디렉터리로 안내한다.

남길 가치가 있는 교훈은 여기에 쌓이고, 사람 세션이 검토한 뒤에만 기억이 된다.

## 누가 쓰나

- **무인 레인 에이전트** — 레인 작업 중 다음 세션이 알아야 할 교훈을 발견했을 때.
- 세션(Q)은 여기에 쓰지 않는다. 기억에 직접 쓴다.

## 파일명

`<YYYYMMDD>_<레인>_<주제-kebab>.md`

레인 이름 = `06_Registry/reinforce_auto_config.json::llm.lanes` 의 키
(예: `replication` · `b1_design` · `b5_design` · `overlay_propose` · `paper_router` · `cleaner_distill`).

## 형식

```
---
lane: replication
subject: <논문 키 · base_id · 산출물 경로 중 하나>
kind: feedback | reference | project
proposed_title: 한 줄 제목
evidence: <근거 파일 경로(산출물·로그) — 없으면 none>
---
본문 5~15줄 — 무엇을 관측했나(사실) · 왜 중요한가(기전) · 다음에 무엇을 달리 할까(행동).
```

- 성과 수치(Grade · Calmar · SR 등)는 권위 산출물 경로(`authoritative_remeasure.json`)와 함께만 적는다. 진술은 증거가 아니다.
- 금지: 기존 기억 카드를 복사하거나 요약해 다시 올리는 것 · 성과 수치만 있는 항목 · 토큰·키 같은 비밀.

## 처리 (주간 `/cleaner` ③b)

1. 항목마다 셋 중 하나로 판정한다.
   - **승격**: 기억 카드로 옮긴다. 기존 카드와 겹치면 병합한다. front-matter 에 `source: unattended_lane` 과 `inbox: <파일명>` 을 적는다.
   - **L-code**: 리서치 교훈이면 기억이 아니라 L-code 가 정본이다(`lcode_emit.R::emit_lcode()`).
   - **기각**: 근거가 없거나, 일회성이거나, 성과 수치를 다시 옮긴 것뿐이면 사유를 한 줄 남긴다.
2. 처리한 파일은 `_processed/<YYYYMMDD>/` 로 옮긴다(삭제하지 않는다). 판정과 목적지는 `_processed/<YYYYMMDD>/verdicts.tsv` 에 한 줄씩 적는다.
3. 완료 보고에 `inbox 처리 n건(승격 a · L-code b · 기각 c)` 를 한 줄 넣는다.

## 검사

- `08_Tests/hooks/test_safety_guard_memory.sh` — 무인 표식이 있으면 기억 쓰기가 막히고 이 디렉터리 쓰기는 통과하는지, 표식이 없으면 기억 쓰기도 통과하는지(양방향 + 돌연변이).
- `08_Tests/ops/test_llm_single_entry.sh` — 무인 `claude -p` 가 전부 단일 진입을 거치는지(전수 parse) · 두 표식이 실제로 실리는지.
