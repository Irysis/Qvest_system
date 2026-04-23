---
description: QEPM Alpha Research Agent spawn — Work Task alpha_package 생성
---

# /alpha-research {WT_id}

Alpha Research Agent를 Work Task에 spawn하여 alpha_package.json을 자율 생성합니다.

**사용법**:
```
/alpha-research WT20260423_001
```

**입력**: `qepm/mailbox/worktask/{WT_id}/request.json` (Work Task Spec)

**산출**: `qepm/mailbox/worktask/{WT_id}/alpha_package.json`

**실행 방식**: `Skill(alpha-research)` 또는 `Agent(subagent_type="alpha-research", prompt=...)`

상세: `.claude/skills/alpha-research/SKILL.md` 참조.
