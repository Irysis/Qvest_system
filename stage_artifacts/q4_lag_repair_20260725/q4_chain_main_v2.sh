#!/bin/bash
# Q4 완주 체인 v2 (v1 결함 수리: grep -c 이중출력·대기상한 150분·임계 400)
ROOT="/c/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT="$ROOT/stage_artifacts/q4_lag_repair_20260725"
MLOG="/c/Users/99922/AppData/Local/Temp/claude/C--Users-99922-OneDrive-Quant-Module-Moltbot/3b509214-77ce-48d2-bb53-b22e8c6cb724/tasks/b6qidm6qn.output"
LAST="$ROOT/.cache/factor_db/factor_db_202607.parquet"
IC="$ROOT/.cache/factor_db/factor_ic_monthly.parquet"
CL="$OUT/q4_chain_main.log"
ts() { date "+%H:%M:%S"; }
echo "[$(ts)] chain v2 start" >> "$CL"

# (a) 완료 신호 = 마지막 월(202607)이 재빌드 체인에서 재기록(mtime > 14:00) + IC 재계산 + 로그 idle
DEADLINE=$(( $(date +%s) + 6*3600 ))
while [ "$(date +%s)" -lt "$DEADLINE" ]; do
  sleep 120
  L_MT=$(stat -c %Y "$LAST" 2>/dev/null || echo 0)
  I_MT=$(stat -c %Y "$IC" 2>/dev/null || echo 0)
  M_MT=$(stat -c %Y "$MLOG" 2>/dev/null || echo 0)
  NOW=$(date +%s)
  CUT=$(date -d "2026-07-25 14:00" +%s)
  if [ "$L_MT" -gt "$CUT" ] && [ "$I_MT" -gt "$L_MT" ] && [ $((NOW - M_MT)) -gt 300 ]; then break; fi
done
FATALS=$(grep -ci "FATAL" "$MLOG" 2>/dev/null | head -1)
FATALS=${FATALS:-0}
NEWCNT=$(find "$ROOT/.cache/factor_db" -maxdepth 1 -name 'factor_db_*.parquet' -newermt "2026-07-25 12:30" | wc -l)
L_OK=$([ "$(stat -c %Y "$LAST")" -gt "$(date -d '2026-07-25 14:00' +%s)" ] && echo 1 || echo 0)
echo "[$(ts)] monthly done-check: fatals=$FATALS rebuilt=$NEWCNT last202607_rewritten=$L_OK" >> "$CL"
if [ "$FATALS" -gt 0 ] || [ "$NEWCNT" -lt 435 ] || [ "$L_OK" != "1" ]; then
  echo "[$(ts)] ABORT: 완료조건 미충족 (fatals=$FATALS rebuilt=$NEWCNT last=$L_OK) — fdb_daily 미착수" >> "$CL"
  exit 1
fi

echo "[$(ts)] fdb_daily rebuild start" >> "$CL"
bash "$ROOT/02_Infrastructure/factor_db/run_fdb_rebuild.sh" >> "$CL" 2>&1
echo "[$(ts)] fdb_daily rebuild exit=$?" >> "$CL"

cd "$ROOT" && AB_LABEL=new Rscript "$OUT/ab_canonical_port_q4.R" >> "$CL" 2>&1
echo "[$(ts)] AB new-side exit=$?" >> "$CL"
cd "$ROOT" && Rscript "$OUT/ab_snapshot_diff_q4.R" >> "$CL" 2>&1
echo "[$(ts)] snapshot diff exit=$?" >> "$CL"
echo "[$(ts)] CHAIN COMPLETE" >> "$CL"
