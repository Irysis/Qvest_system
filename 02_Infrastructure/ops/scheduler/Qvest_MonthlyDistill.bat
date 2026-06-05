@echo off
"C:\Program Files\Git\bin\bash.exe" -c "export PATH='/c/Users/User/anaconda3:/c/Program Files/R/R-4.5.2/bin:'$PATH; export CLAUDE_PROJECT_DIR=G:/Quant_Module_Moltbot; export QM_ROOT=G:/Quant_Module_Moltbot; export PYTHONUTF8=1; bash /g/Quant_Module_Moltbot/02_Infrastructure/memory/monthly_distill.sh >> /g/Quant_Module_Moltbot/.cache/scheduler_logs/monthly_distill.log 2>&1"
