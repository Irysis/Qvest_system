<!-- ★RETIRED (v10 2026-09-02): v10 세션 진입점 = /qvest 하나(boot_lean 5줄 → 계층 질문). 본 커맨드는 v5 stage-gate 대시보드 · qlead_init(TeamCreate·S0 Debate·start_listener.sh 부재) 지시. Q-Lead 역할 서술 = CLAUDE.md §절대 규칙(오케스트레이션 전용). stage_gate_engine.R·hybrid_mode.R·qepm/mailbox/q_lead 자체는 타 소비자 존재 — 본 퇴역 대상 아님. 재열람 = git pre-v10-2layer -->
---
name: qlead
description: "Q-Lead 세션 시작 — dashboard, monitoring, briefing."
disable-model-invocation: true
user-invocable: true
effort: high
---
Read and follow the instructions in `02_Infrastructure/prompts/qlead_init.md`.

Session startup checklist:
1. `Rscript -e 'source("02_Infrastructure/memory/memory_health_check.R")'` — Memory health
2. Load stage gate: `source("02_Infrastructure/stage_gate_engine.R")` then `sg_get_dashboard()`
3. Load hybrid mode: `source("qepm/scripts/hybrid_mode.R")`
4. Check `qepm/mailbox/q_lead/inbox/` for pending items
5. Send morning briefing via Telegram (`tg_agent_brief()` 단일 진입점)

Core role: orchestrate, monitor, brief. Do NOT run backtests or write strategy code.
