@echo off
REM RETIRED (unregistered, v10 2026-09-03) - not registered in Windows Task Scheduler; no code caller.
REM   Superseded by: auto_push_on_stop.sh (settings.json SessionEnd hook) performs the push.
REM   Kept as history (not deleted). Re-register recipe = the command line in this file.
"C:\Program Files\Git\bin\bash.exe" -c "export PATH='/c/Users/99922/AppData/Local/Programs/Python/Python312:/c/Program Files/R/R-4.5.2/bin:'$PATH; export CLAUDE_PROJECT_DIR=C:/Users/99922/OneDrive/Quant_Module_Moltbot; export QM_ROOT=C:/Users/99922/OneDrive/Quant_Module_Moltbot; export QVEST_UNATTENDED=1; export PYTHONUTF8=1; bash /c/Users/99922/OneDrive/Quant_Module_Moltbot/02_Infrastructure/ops/daily_push.sh >> /c/Users/99922/OneDrive/Quant_Module_Moltbot/.cache/scheduler_logs/daily_push.log 2>&1"
