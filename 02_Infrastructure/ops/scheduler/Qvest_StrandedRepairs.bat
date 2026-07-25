@echo off
REM Qvest_StrandedRepairs - stranded repair audit (unattended, read-only)
REM Detects repairs trapped in parallel-session worktrees that never reached main.
REM Emits 06_Registry/stranded_repairs.json; telegram alert on lost/collision (1/day throttle).
REM Prune is manual only (--prune). Never writes into worktrees.
REM 2026-07-25 new (dohoon approved next_probe 2)
"C:\Program Files\Git\bin\bash.exe" -c "export PATH='/c/Program Files/R/R-4.5.2/bin:'$PATH; export CLAUDE_PROJECT_DIR=C:/Users/99922/OneDrive/Quant_Module_Moltbot; export QM_ROOT=C:/Users/99922/OneDrive/Quant_Module_Moltbot; export PYTHONUTF8=1; bash /c/Users/99922/OneDrive/Quant_Module_Moltbot/02_Infrastructure/ops/stranded_repairs_audit.sh --quiet >> /c/Users/99922/OneDrive/Quant_Module_Moltbot/.cache/scheduler_logs/stranded_repairs.log 2>&1"
