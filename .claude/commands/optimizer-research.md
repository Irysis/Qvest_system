---
description: QEPM Optimizer Research Agent spawn — α̂ + Σ 수신해 SR-maximizing weights 자율 발견
---

# /optimizer-research {WT_id}

Optimizer Research Agent를 Work Task에 spawn합니다.

**Prerequisite**:
- `qepm/mailbox/worktask/{WT_id}/alpha_package.json`
- `qepm/mailbox/worktask/{WT_id}/risk_package.json`

**사용법**:
```
/optimizer-research WT20260423_001
```

**산출**: `optimization_package.json` (25종 hard + long-only + Σw=1 + method_comparison).

상세: `.claude/skills/optimizer-research/SKILL.md` 참조.
