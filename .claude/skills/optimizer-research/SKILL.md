---
name: optimizer-research
description: (수동 진입 스텁) QEPM optimizer-research 에이전트 수동 spawn 진입점. 절차 SOT = qvest-worktask §3 Step 3 + optimizer_research_init.md — 본 스텁은 리다이렉트만.
---

# /optimizer-research {WT_id}

(2026-07-24 도훈 승인 C3 — 리다이렉트 스텁. 구 본문은 init 프롬프트의 축약 사본이라 드리프트 위험으로 제거, settings.json skillOverrides `user-invocable-only`로 모델 목록에서 제외. 역사 = git.)

QEPM optimizer-research 단계 수동 트리거. **절차 정본 (Read 후 진행)**:

1. `.claude/skills/qvest-worktask/SKILL.md` §3 Step 3 — Agent tool spawn 패턴 (`subagent_type="optimizer-research"`)
2. `02_Infrastructure/prompts/optimizer_research_init.md` — 에이전트 시스템 프롬프트 SOT (method_comparison ≥3·net-of-cost objective·selection_objective=net_ir)

입력: `alpha_package.json` + `risk_package.json` · 산출: `optimization_package.json`(+weights.csv) + `challenge_note.md`.
경계: alpha 재해석·Σ 재정의 절대 금지. 25종·long-only·[0,0.20]·Σw=1 hard (Hook block — worktask_constraint_enforcer).
