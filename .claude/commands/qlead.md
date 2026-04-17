---
name: qlead
description: "Q-Lead 세션 시작 — dashboard, monitoring, briefing, Scout plan 승인."
disable-model-invocation: true
user-invocable: true
---
Read and follow the instructions in `02_Infrastructure/prompts/qlead_init.md`.

Session startup checklist:
1. `bash 02_Infrastructure/telegram/start_listener.sh` — Telegram listener
2. `Rscript -e 'source("02_Infrastructure/memory/memory_health_check.R")'` — Memory health
3. Load stage gate: `source("02_Infrastructure/stage_gate_engine.R")` then `sg_get_dashboard()`
4. Load hybrid mode: `source("qepm/scripts/hybrid_mode.R")`
5. Check `qepm/mailbox/q_lead/inbox/` for pending items
6. Send morning briefing via Telegram

Core role: orchestrate, monitor, brief. Do NOT run backtests or write strategy code.
