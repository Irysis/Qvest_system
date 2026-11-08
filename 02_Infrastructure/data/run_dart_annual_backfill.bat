@echo off
REM DART 연간(사업보고서 11011) 과거 연도 보충 — 예약 작업 진입점 (일 1회 · 이어서 수집)
REM 2026-11-08: dart_annual_backfill.R --backfill. 가드는 스크립트 내장 — 여기서 가속 금지:
REM   시간 창 04:00~23:30 · 00:03 체인 실행 중이면 시작 안 함 · 원시 캐시 잠금 ·
REM   예산 = 일일 상한 10,000 - 오늘 쓴 콜(사용량 로그) - 예비 1,000 - 아직 안 돈 [5b]/[5a] 예정분.
REM   보충이 끝나면(요청 대상 0) fundamental_dart 재계산 + fundamental_merged 재생성 1회, 그 뒤 실행은 0콜.
REM 로그: .cache\dart\annual_backfill_logs\run_YYYYMMDD.log · 상태: .cache\dart\annual_backfill_status.json
set QM_ROOT=C:/Users/99922/OneDrive/Quant_Module_Moltbot
set CLAUDE_PROJECT_DIR=C:/Users/99922/OneDrive/Quant_Module_Moltbot
set "RSCRIPT=C:\Program Files\R\R-4.6.2\bin\Rscript.exe"
if defined QVEST_RSCRIPT set "RSCRIPT=%QVEST_RSCRIPT%"
set LOGD=C:\Users\99922\OneDrive\Quant_Module_Moltbot\.cache\dart\annual_backfill_logs
if not exist "%LOGD%" mkdir "%LOGD%"
set TS=%DATE:~0,4%%DATE:~5,2%%DATE:~8,2%
set LOG=%LOGD%\run_%TS%.log

echo === DART annual backfill run %DATE% %TIME% === >> "%LOG%"
"%RSCRIPT%" --no-save "C:\Users\99922\OneDrive\Quant_Module_Moltbot\02_Infrastructure\data\dart_annual_backfill.R" --backfill >> "%LOG%" 2>&1
echo === done %DATE% %TIME% rc=%ERRORLEVEL% === >> "%LOG%"
