---
description: BOOK 관리 (v10) — A등급 등록 전략·로테이션 규칙 목록 + 온디맨드 성과 트래킹 (governor/book_state 승계. 리서치 시스템 — 실투자 집행 없음)
---

# /book [track <book_id>|all]

**BOOK** = A등급 달성(+Judge PIT PASS) 전략·로테이션 규칙의 등록·사후 관리 장부.
정본 = `06_Registry/book/book_registry.json` (writer = `02_Infrastructure/book/book_registry.R`
경유만 — 직접 편집은 `book_write_guard.sh` 훅이 차단). 구 governor/`book_state.json` 은
v10 폐지 — legacy 동결 사료.

## 동작

1. **목록** (`/book`):
   `Rscript -e 'source("02_Infrastructure/book/book_registry.R"); b <- read_book(); for (e in b$entries) cat(sprintf("%s | %s | %s | L%s | %s | 등록 %s | 트래킹 %s\n", e$book_id, e$kind, e$strategy_id, e$layer, e$status, substr(e$registered_at,1,10), e$tracking$last_nav_date))'`
   표로 정리해 보고 (book_id · kind · 전략 · 등급근거 · status · 최신 트래킹일).

2. **트래킹** (`/book track <book_id>` 또는 도훈 지명) — 등록 당시 frozen 스펙 그대로
   최신 데이터까지 재실행:
   - `factor_strategy` → 해당 `code_path` 전략 디렉터리로 `cd` 후
     `Rscript -e 'source("run_all.R")'` (기존 bt 인프라 재사용 — 한글 경로 회피 규약) →
     `build_bt_result` 경유 최신 NAV/성과 → `update_book_tracking(book_id,
     list(last_nav_date=..., sharpe=..., cagr=..., mdd=..., artifacts=...))`.
   - `rotation_rule` → 등록 당시 사양(국면엔진 버전 + 배분규칙 + admitted pool)으로
     `run_wf_ensemble.R` forward 구간 재실행 → 동일 기록.
   - ★frozen 스펙 불변 — 트래킹은 재현이지 개선이 아니다. 스펙 변경 욕구 = 강화
     프로세스(새 리서치 단위)로.
3. **텔레그램(옵션)** — `tg_agent_brief(agent="Book", title="[BOOK] 트래킹 — {book_id} ({전략})")`
   + `tg_chart_pack_from_bt` 차트. 등록 이벤트는 `[BOOK] 등록 — {book_id}`.
4. **상태 변경** — `set_book_status(book_id, "suspended"|"retired", reason)` — 도훈 지시로만.
   엔트리 삭제 금지(append-only).

## 등록 (세션이 수동 — Judge PASS 후)

```r
source("02_Infrastructure/book/book_registry.R")
register_book_entry(kind="factor_strategy"|"rotation_rule", strategy_id=..., layer=1|2,
                    grade="A", grade_basis="essence_score(authoritative_remeasure.json)",
                    judge_verdict_path=..., source_papers=list(list(title=,url=)), ...)
```
- writer 가 judge_verdict 의 `pit_pass=true` 를 **실제로 읽어** 검증한다(진술 불가).
- mandate 예외 = `grade_basis="dohoon_mandate_YYYYMMDD"` (선례: BOOK_0001 = 구 PG2).
- **등록 전 도훈 confirm 필수** — 자동 등록 없음.

## 참조
`.claude/agents/book-tracker.md`(트래킹 실행 에이전트) · `02_Infrastructure/book/book_registry.R` ·
`06_Registry/live_track/`(holdout 자동 연장 대조 — measurement-graduation §3)
