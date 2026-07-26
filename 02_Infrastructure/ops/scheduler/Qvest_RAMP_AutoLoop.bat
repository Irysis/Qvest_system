@echo off
REM RAMP 완전자율 루프 무인 구동 (주간). Observe->grid 탐색->Document->surface. 자본=governor 정지(도훈 수동).
"C:\Program Files\Git\bin\bash.exe" -c "export PATH='/c/Program Files/R/R-4.5.2/bin:'$PATH; export CLAUDE_PROJECT_DIR=C:/Users/99922/OneDrive/Quant_Module_Moltbot; export QM_ROOT=C:/Users/99922/OneDrive/Quant_Module_Moltbot; export QVEST_UNATTENDED=1; export PYTHONUTF8=1; bash /c/Users/99922/OneDrive/Quant_Module_Moltbot/02_Infrastructure/ramp/run_ramp_autonomous.sh >> /c/Users/99922/OneDrive/Quant_Module_Moltbot/.cache/scheduler_logs/ramp_autoloop.log 2>&1"
