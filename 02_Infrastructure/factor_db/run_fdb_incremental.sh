#!/usr/bin/env bash
#==============================================================================
# run_fdb_incremental.sh <YYYYMM> — 단일월 증분 (phase6+7+8, FDB_INCR_YM 모드)
#
# 전량 재빌드(run_fdb_rebuild.sh, ~48분·전파일삭제)의 단일월 버전(~2-4분).
#   - phase6: 삭제 스킵 + RW 윈도우(≥1300 거래일 룩백) + 단일월 출력 + 글로벌 registry 보존
#   - phase7/8: 단일월 파일만 merge + registry 보존
#   - 각 phase = 별도 R 프로세스 (arrow Windows 1224 회피 — run_fdb_rebuild.sh와 동일 원칙)
#   - FDB_INCR_YM 미설정 시 phase 스크립트는 기존 full-rebuild 동작 (가드 무해)
#
# 사용: bash 02_Infrastructure/factor_db/run_fdb_incremental.sh 202607
# 전제: 해당 월 이전 full-build 산출물이 이미 존재(additive merge 대상). 신규월은 새 파일 생성.
#==============================================================================
set -uo pipefail
YM="${1:?usage: run_fdb_incremental.sh YYYYMM}"
case "$YM" in [0-9][0-9][0-9][0-9][0-9][0-9]) ;; *) echo "bad YM: $YM (expect YYYYMM)"; exit 2;; esac
INFRA="C:/Users/99922/OneDrive/Quant_Module_Moltbot/02_Infrastructure"
RS="/c/Program Files/R/R-4.5.2/bin/Rscript.exe"
TS() { date '+%Y-%m-%d %H:%M:%S'; }
cd "$INFRA" || { echo "cannot cd $INFRA"; exit 2; }
[ -x "$RS" ] || { echo "Rscript not found: $RS"; exit 2; }
export FDB_INCR_YM="$YM"
echo "[incremental] FDB_INCR_YM=$YM @ $(TS)"
for P in 6 7 8; do
  echo "[incremental] ===== phase$P begin @ $(TS) ====="
  "$RS" -e "source('factor_db/factor_db_daily_phase${P}.R')"
  rc=$?
  if [ "$rc" -ne 0 ]; then echo "[incremental] !!! phase$P FAILED rc=$rc @ $(TS)"; exit "$rc"; fi
  echo "[incremental] ===== phase$P done rc=0 @ $(TS) ====="
done
echo "[incremental] DONE $YM @ $(TS)"
