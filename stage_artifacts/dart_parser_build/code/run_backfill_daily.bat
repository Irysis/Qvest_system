@echo off
REM DART insider 역사 백필 — 일일 재개 런처 (스케줄 태스크용)
REM resumable: 완료 월 parquet 존재 시 skip. 전 월 완료 시 즉시 no-op 종료.
REM budget 7000/day (daily_refresh DART 여유 ~3000 남김). 020 rate-limit 자동 halt.
REM 작성 2026-07-05 (exec-insider CMP frontier, detached 실행 필수 — harness bg 캡 회피).
setlocal
set QM_ROOT=C:\Users\99922\OneDrive\Quant_Module_Moltbot
set BF_START=2007-11
set BF_END=2024-11
set MODE=backfill
set DART_DAILY_BUDGET=7000
cd /d "%QM_ROOT%"
echo [%DATE% %TIME%] backfill daily run start >> "stage_artifacts\dart_parser_build\reports\backfill_scheduled.log"
"%QM_ROOT%\.venv_qvest_ml\Scripts\python.exe" -u "stage_artifacts\dart_parser_build\code\dart_backfill_pipeline.py" >> "stage_artifacts\dart_parser_build\reports\backfill_scheduled.log" 2>&1
echo [%DATE% %TIME%] backfill daily run end >> "stage_artifacts\dart_parser_build\reports\backfill_scheduled.log"
endlocal
