---
description: QEPM Work Task lifecycle 관리 — 생성/상태/전이/admission
---

# /worktask {subcommand} {args}

QEPM Work Task는 1 가설 = 1 QEPM Full Pipeline (Alpha → Risk → Optimizer → Forge → Judge → Governor).

## Subcommands

- `/worktask create "{hypothesis}"` — 신규 WT 생성 + request.json 발행. **생성 전 hypothesis_index 조회 의무**: `Rscript 02_Infrastructure/tools/hypothesis_index.R lookup <keyword>...` — FAIL/KILL 히트 시 차별점 명시 없인 진행 금지(INV-7 재도전 사유 기록). 상세: `.claude/skills/qvest-worktask/SKILL.md` §2
- `/worktask status {WT_id}` — 현 단계 + package 존재 확인
- `/worktask list` — 진행 중 WT 목록
- `/worktask advance {WT_id} {new_phase}` — 단계 수동 전이
- `/worktask promote {WT_id}` — Judge+Governor admission 트리거

## Example

```
/worktask create "Rate Hedge Defense — Duration-neutral Quality"
→ WT-D20260423_001 생성 (WT-D/P/S/H prefix). Alpha Agent 자동 spawn.

/worktask status WT-D20260423_001
→ Phase: SPEC_APPROVED / Packages: alpha ✗ risk ✗ opt ✗

/worktask promote WT-D20260423_001
→ Judge Gate + Governor PG0~PG3 자동 lifecycle
```

상세: `.claude/skills/qvest-worktask/SKILL.md` 참조 (구 worktask 스킬은 2026-07-24 삭제 — v8.1 state machine과 불일치하던 구버전 잔재).
