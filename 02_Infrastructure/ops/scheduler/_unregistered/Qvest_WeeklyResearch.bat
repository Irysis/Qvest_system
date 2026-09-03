@echo off
REM RETIRED (unregistered, v10 2026-09-03) - not registered in Windows Task Scheduler; no code caller.
REM   Superseded by: Qvest_WeeklyCleaner (weekly_cleaner_sweep.R).
REM   Kept as history (not deleted). Re-register recipe = the command line in this file.
"C:\Program Files\Git\bin\bash.exe" -c "export PATH='/c/Users/99922/AppData/Local/Programs/Python/Python312:/c/Program Files/R/R-4.5.2/bin:'$PATH; export CLAUDE_PROJECT_DIR=C:/Users/99922/OneDrive/Quant_Module_Moltbot; export QM_ROOT=C:/Users/99922/OneDrive/Quant_Module_Moltbot; export QVEST_UNATTENDED=1; export PYTHONUTF8=1; bash /c/Users/99922/OneDrive/Quant_Module_Moltbot/02_Infrastructure/memory/weekly_research_collect.sh >> /c/Users/99922/OneDrive/Quant_Module_Moltbot/.cache/scheduler_logs/weekly_research.log 2>&1"
