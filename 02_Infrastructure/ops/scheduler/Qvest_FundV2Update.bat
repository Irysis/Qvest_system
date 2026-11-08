@echo off
rem Qvest_FundV2Update - Quantiwise fundamentals v2 rolling update (2026-11-09, Dohoon approved: regular refresh task).
rem   Re-fetches the last 8 quarters of each FundV2_*_upd DB and replaces that window in the parent parquet
rem   (.cache/qw_fund_v2/<parent>.parquet; value changes -> revisions.parquet). Contract = ops/qw_fund_v2_update.ps1 header
rem   (exit 0 done | 3 precondition / busy / kicked | 1 failure). Schedule = task XML _task_xml_backup/Qvest_FundV2Update.xml.
setlocal
set "QM_ROOT=C:\Users\99922\OneDrive\Quant_Module_Moltbot"
set "CLAUDE_PROJECT_DIR=%QM_ROOT%"
set "QVEST_UNATTENDED=1"
set "PYTHONUTF8=1"
set "QV_LOG=%QM_ROOT%\.cache\scheduler_logs\fund_v2_update.log"
cd /d "%QM_ROOT%"
echo [%DATE% %TIME%] Qvest_FundV2Update start>> "%QV_LOG%"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%QM_ROOT%\02_Infrastructure\ops\qw_fund_v2_update.ps1" >> "%QV_LOG%" 2>&1
set "QV_RC=%ERRORLEVEL%"
echo [%DATE% %TIME%] Qvest_FundV2Update end rc=%QV_RC%>> "%QV_LOG%"
exit /b %QV_RC%