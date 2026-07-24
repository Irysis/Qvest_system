---
name: alpha-research
description: (수동 진입 스텁) QEPM alpha-research 에이전트 수동 spawn 진입점. 절차 SOT = qvest-worktask §3 Step 1 + alpha_research_init.md — 본 스텁은 리다이렉트만.
---

# /alpha-research {WT_id}

(2026-07-24 도훈 승인 C3 — 리다이렉트 스텁. 구 본문은 init 프롬프트의 축약 사본이라 드리프트 위험으로 제거, settings.json skillOverrides `user-invocable-only`로 모델 목록에서 제외. 역사 = git.)

QEPM alpha-research 단계 수동 트리거. **절차 정본 (Read 후 진행)**:

1. `.claude/skills/qvest-worktask/SKILL.md` §3 Step 1 — Agent tool spawn 패턴 (`subagent_type="alpha-research"`)
2. `02_Infrastructure/prompts/alpha_research_init.md` — 에이전트 시스템 프롬프트 SOT (7-step pipeline·selection_objective=canonical_port_t 1급·Self-Adversarial 의무)

입력: `qepm/mailbox/worktask/{WT_id}/request.json` · 산출: `alpha_package.json` + `challenge_note.md`.
경계: 공분산/weights 계산 절대 금지 (Hook block — role_objective_guard·method_shopping_limiter).
