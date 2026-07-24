---
name: risk-research
description: (수동 진입 스텁) QEPM risk-research 에이전트 수동 spawn 진입점. 절차 SOT = qvest-worktask §3 Step 2 + risk_research_init.md — 본 스텁은 리다이렉트만.
---

# /risk-research {WT_id}

(2026-07-24 도훈 승인 C3 — 리다이렉트 스텁. 구 본문은 init 프롬프트의 축약 사본이라 드리프트 위험으로 제거, settings.json skillOverrides `user-invocable-only`로 모델 목록에서 제외. 역사 = git.)

QEPM risk-research 단계 수동 트리거. **절차 정본 (Read 후 진행)**:

1. `.claude/skills/qvest-worktask/SKILL.md` §3 Step 2 — Agent tool spawn 패턴 (`subagent_type="risk-research"`)
2. `02_Infrastructure/prompts/risk_research_init.md` — 에이전트 시스템 프롬프트 SOT (Σ=BΩB'+D·tail·stress·crowding_score_per_factor 의무)

입력: `alpha_package.json` · 산출: `risk_package.json`(+covariance.parquet·tail_risk.json) + `challenge_note.md`.
경계: alpha 수정·weights 제안 절대 금지 (Hook block).
