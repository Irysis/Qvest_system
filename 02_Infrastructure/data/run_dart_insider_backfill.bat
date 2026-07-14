@echo off
REM DART Insider Backfill — Task Scheduler 진입점 (일 1회, resumable)
REM 2026-07-03 (감사 SC-05 후속): dart_insider_backfill.R 은 완료 월 체크포인트를
REM   skip 하므로 매일 재실행 = 이어서 수집. budget guard(DART_DAILY_BUDGET,
REM   기본 7000)는 스크립트 내장 — 여기서 가속 금지.
REM 로그: .cache\dart\insider_backfill\logs\run_YYYYMMDD.log
set QM_ROOT=C:/Users/99922/OneDrive/Quant_Module_Moltbot
REM 2026-07-14: BF_END 확장 2024-02(스크립트 기본) -> 2026-06 (task #44 도훈 mandate "2026-06까지"
REM   + R9 발사조건 연속 200501~202604). 완료 월 200501~202402(230월)은 체크포인트 skip —
REM   잔여 202403~202606만 수집. budget guard 불변.
set BF_END=2026-06
set RSCRIPT=C:\Program Files\R\R-4.5.2\bin\Rscript.exe
set LOGD=C:\Users\99922\OneDrive\Quant_Module_Moltbot\.cache\dart\insider_backfill\logs
if not exist "%LOGD%" mkdir "%LOGD%"
set TS=%DATE:~0,4%%DATE:~5,2%%DATE:~8,2%
set LOG=%LOGD%\run_%TS%.log

echo === DART insider backfill run %DATE% %TIME% === >> "%LOG%"
"%RSCRIPT%" --no-save "C:\Users\99922\OneDrive\Quant_Module_Moltbot\02_Infrastructure\data\dart_insider_backfill.R" >> "%LOG%" 2>&1
"%RSCRIPT%" --no-save "C:\Users\99922\OneDrive\Quant_Module_Moltbot\02_Infrastructure\data\dart_backfill_status.R" >> "%LOG%" 2>&1
echo === done %DATE% %TIME% === >> "%LOG%"
