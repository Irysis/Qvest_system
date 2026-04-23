---
description: QEPM Risk Research Agent spawn — Alpha 수신 후 공분산 Σ + 리스크 진단 생성
---

# /risk-research {WT_id}

Risk Research Agent를 Work Task에 spawn합니다.

**Prerequisite**: `qepm/mailbox/worktask/{WT_id}/alpha_package.json` 존재.

**사용법**:
```
/risk-research WT20260423_001
```

**산출**: `qepm/mailbox/worktask/{WT_id}/risk_package.json` + covariance.parquet + tail_risk.json

상세: `.claude/skills/risk-research/SKILL.md` 참조.
