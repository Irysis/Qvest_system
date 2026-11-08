@echo off
REM Qvest_ClaudeCliUpdate - npm-global Claude Code CLI auto-update for the unattended lanes (daily 06:00, every machine)
REM 2026-11-07 new (dohoon: "auto-update the npm CLI the unattended lanes use whenever a new version ships" -> method 2)
REM
REM What it does (claude_cli_update.sh - its header has the full contract):
REM   compares the installed npm package version with npm dist-tags.latest; if different, waits (max 180 min)
REM   until no lane claude.exe runs from the npm path (claude_cli_procs.ps1), takes the update lock
REM   .cache\machine\claude_cli_update_<HOST>.lock\ so new lane starts wait (rf_llm_env.sh::rf_llm_agent_run),
REM   runs npm install -g @anthropic-ai/claude-code@<exact version>, verifies package.json + claude.exe --version,
REM   and on failure judges the final state: keeps npm's own rollback, otherwise reinstalls the previous version.
REM   Telegram only on version change / install failure / 3rd, 7th, 14th... consecutive skip.
REM Why not the CLI's own auto-updater: the npm package is a native bin\claude.exe; a running session keeps reading
REM   it from disk and an in-place npm upgrade deletes it (code.claude.com/docs/en/setup). The lanes therefore run
REM   with DISABLE_AUTOUPDATER=1 DISABLE_UPDATES=1 and this task is the only replacement path.
REM period local (machines.conf): each machine updates its own CLI - no main-priority gate.
REM rc: 0 = up to date / updated / skipped today (busy, offline) - 2 = install failed, previous version restored
REM     3 = install failed and restore failed (needs a person). scheduler_task_health.sh reads LastTaskResult.
REM Log: .cache\scheduler_logs\claude_cli_update_<HOST>.log (one SUMMARY line per run).
REM Test: bash 08_Tests/ops/test_claude_cli_update.sh
REM
REM REGISTER (once per machine, normal PowerShell in the project folder):
REM   powershell -NoProfile -ExecutionPolicy Bypass -File 02_Infrastructure\ops\machine\qvest_tasks.ps1 -Mode Apply -From 02_Infrastructure\ops\scheduler\_task_xml_backup -Name Qvest_ClaudeCliUpdate
REM   (the XML there is the unwrapped original; Apply rewrites the account to this machine and wraps it in the gated runner)
REM
REM NOTE: keep this .bat ASCII-only - cmd.exe reads it in CP949 and mangles UTF-8.
"C:\Program Files\Git\bin\bash.exe" -c "export PATH='/c/Program Files/nodejs:/c/Users/99922/AppData/Local/Programs/Python/Python315:/c/Program Files/R/R-4.6.2/bin:'$PATH; export CLAUDE_PROJECT_DIR=C:/Users/99922/OneDrive/Quant_Module_Moltbot; export QM_ROOT=C:/Users/99922/OneDrive/Quant_Module_Moltbot; export QVEST_UNATTENDED=1; export PYTHONUTF8=1; mkdir -p /c/Users/99922/OneDrive/Quant_Module_Moltbot/.cache/scheduler_logs; bash /c/Users/99922/OneDrive/Quant_Module_Moltbot/02_Infrastructure/ops/claude_cli_update.sh --quiet >> /c/Users/99922/OneDrive/Quant_Module_Moltbot/.cache/scheduler_logs/claude_cli_update_%COMPUTERNAME%.log 2>&1"
