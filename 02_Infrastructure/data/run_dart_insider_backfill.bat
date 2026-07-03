@echo off
REM DART Insider Backfill — Task Scheduler 진입점 (일 1회, resumable)
REM 2026-07-03 (감사 SC-05 후속): dart_insider_backfill.R 은 완료 월 체크포인트를
REM   skip 하므로 매일 재실행 = 이어서 수집. budget guard(DART_DAILY_BUDGET,
REM   기본 7000)는 스크립트 내장 — 여기서 가속 금지.
REM 로그: .cache\dart\insider_backfill\logs\run_YYYYMMDD.log
set QM_ROOT=C:/Users/99922/OneDrive/Quant_Module_Moltbot
set RSCRIPT=C:\Program Files\R\R-4.5.2\bin\Rscript.exe
set LOGD=C:\Users\99922\OneDrive\Quant_Module_Moltbot\.cache\dart\insider_backfill\logs
if not exist "%LOGD%" mkdir "%LOGD%"
set TS=%DATE:~0,4%%DATE:~5,2%%DATE:~8,2%
set LOG=%LOGD%\run_%TS%.log

echo === DART insider backfill run %DATE% %TIME% === >> "%LOG%"
"%RSCRIPT%" --no-save "C:\Users\99922\OneDrive\Quant_Module_Moltbot\02_Infrastructure\data\dart_insider_backfill.R" >> "%LOG%" 2>&1
"%RSCRIPT%" --no-save "C:\Users\99922\OneDrive\Quant_Module_Moltbot\02_Infrastructure\data\dart_backfill_status.R" >> "%LOG%" 2>&1
echo === done %DATE% %TIME% === >> "%LOG%"
