#!/usr/bin/env bash
# run_phaseF.sh — 일간 팩터 DB 단계 F(재무 팩터 덮어쓰기)를 세션과 떼어 돌리는 실행기(배당 수리 사슬 단계 9).
#   띄우기(PowerShell · WMI): Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{ CommandLine = '"C:\Program Files\Git\bin\bash.exe" "<이 파일 경로>"' }
#   로그 = .cache/scheduler_logs/div_gap_phaseF.log · 끝 줄 = 'RC=<코드> END <시각>' (run_fdb_rebuild.sh 의 단계 F 호출과 같은 방식)
cd /g/OneDrive/Quant_Module_Moltbot/02_Infrastructure || exit 2
{
  echo "START $(date)"
  "/c/Program Files/R/R-4.6.2/bin/Rscript.exe" -e "source('factor_db/factor_db_daily_phaseF_fundamental.R')"
  echo "RC=$? END $(date)"
} > ../.cache/scheduler_logs/div_gap_phaseF.log 2>&1
