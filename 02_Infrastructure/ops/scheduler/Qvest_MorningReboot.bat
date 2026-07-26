@echo off
REM v8.3 2026-07-10: LC_ALL 'English_United States.utf8' -> C.UTF-8 (invalid in Git Bash;
REM   caused bash parse crash on Korean scripts, morning_run.sh L83+). R telegram locale is
REM   handled separately: telegram_notify.R sets LC_CTYPE itself + scripts prefix LC_ALL
REM   'English_United States.utf8' right before Rscript telegram calls.
REM   NOTE: keep this .bat ASCII-only - cmd.exe reads it in CP949 and mangles UTF-8 comments.
"C:\Program Files\Git\bin\bash.exe" -c "export PATH='/c/Users/99922/AppData/Local/Microsoft/WinGet/Packages/astral-sh.uv_Microsoft.Winget.Source_8wekyb3d8bbwe:/c/Users/99922/AppData/Local/Programs/Python/Python312:/c/Program Files/R/R-4.5.2/bin:'$PATH; export CLAUDE_PROJECT_DIR=C:/Users/99922/OneDrive/Quant_Module_Moltbot; export QM_ROOT=C:/Users/99922/OneDrive/Quant_Module_Moltbot; export QVEST_UNATTENDED=1; export PYTHONUTF8=1; export LANG=C.UTF-8; export LC_ALL=C.UTF-8; export QVEST_PAPER_ROUTER_ENABLE=1; export QVEST_PAPER_ROUTER_AUTORUN=1; export QVEST_PAPER_ROUTER_MAX_ALPHA=2; export QVEST_PAPER_DISPATCH_ENABLE=1; export QVEST_FACTOR_RECHECK_ENABLE=1; export QVEST_ALPHA_QUEUE_ENABLE=1; bash /c/Users/99922/OneDrive/Quant_Module_Moltbot/02_Infrastructure/ops/morning_run.sh reboot >> /c/Users/99922/OneDrive/Quant_Module_Moltbot/.cache/scheduler_logs/morning_reboot.log 2>&1"
