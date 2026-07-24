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
