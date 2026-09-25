@echo off
REM v10 2026-08-29: unattended = collection only (recharge + router triage). Research/reinforce env removed (QVEST_ALPHA_QUEUE/FACTOR_RECHECK/PAPER_DISPATCH/ROUTER_AUTORUN) - session-driven now.
REM v8.3 2026-07-10: LC_ALL 'English_United States.utf8' to C.UTF-8 (invalid in Git Bash; bash parse crash on Korean scripts, morning_run.sh L83+).
REM v10.4 2026-09-24: LC_ALL=C.UTF-8 replaced by LANG=C.UTF-8 + LC_COLLATE=C + LC_TIME=C. Windows R cannot set C.UTF-8
REM   and fell back to the C locale for the whole reboot chain (Telegram header mojibake 'Q-Lead A.', Director cache cut
REM   mid-character, Hangul bit-masked in the B5 design prompt). bash keeps a UTF-8 CTYPE through LANG (07-10 fix intact);
REM   R now gets CTYPE=Korean_Korea.utf8 while COLLATE/TIME stay C (sort order and date format unchanged).
REM   This reverses the 2026-09-03 v10.1 choice (bat untouched, per-caller Rscript prefix): 5 new R callers regressed.
REM   Revert = put back 'export LC_ALL=C.UTF-8;' after LANG. Check: 08_Tests/ops/test_scheduler_bat_locale.sh
REM   NOTE: keep this .bat ASCII-only - cmd.exe reads it in CP949 and mangles UTF-8 comments.
"C:\Program Files\Git\bin\bash.exe" -c "export PATH='/c/Users/99922/AppData/Local/Microsoft/WinGet/Packages/astral-sh.uv_Microsoft.Winget.Source_8wekyb3d8bbwe:/c/Users/99922/AppData/Local/Programs/Python/Python312:/c/Program Files/R/R-4.5.2/bin:'$PATH; export CLAUDE_PROJECT_DIR=C:/Users/99922/OneDrive/Quant_Module_Moltbot; export QM_ROOT=C:/Users/99922/OneDrive/Quant_Module_Moltbot; export QVEST_UNATTENDED=1; export PYTHONUTF8=1; export LANG=C.UTF-8; export LC_COLLATE=C; export LC_TIME=C; export QVEST_PAPER_ROUTER_ENABLE=1; bash /c/Users/99922/OneDrive/Quant_Module_Moltbot/02_Infrastructure/ops/morning_run.sh reboot >> /c/Users/99922/OneDrive/Quant_Module_Moltbot/.cache/scheduler_logs/morning_reboot.log 2>&1"
