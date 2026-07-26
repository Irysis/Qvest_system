#!/bin/bash
# Q4 수리 완주 체인 (메인 세션 인계 — wf_1c333719 Q4 PARTIAL의 a~c 단계)
ROOT="/c/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT="$ROOT/stage_artifacts/q4_lag_repair_20260725"
MLOG="/c/Users/99922/AppData/Local/Temp/claude/C--Users-99922-OneDrive-Quant-Module-Moltbot/3b509214-77ce-48d2-bb53-b22e8c6cb724/tasks/b6qidm6qn.output"
CL="$OUT/q4_chain_main.log"
ts() { date "+%H:%M:%S"; }
echo "[$(ts)] chain start" >> "$CL"

# (a) 월간 재빌드 + IC 완료 대기 — 로그 idle 240s + 성공 판정
for i in $(seq 1 150); do
  sleep 60
  NOW=$(date +%s); MT=$(stat -c %Y "$MLOG" 2>/dev/null || echo 0)
  IDLE=$((NOW - MT))
  if [ "$IDLE" -gt 240 ]; then break; fi
done
FATALS=$(grep -ci "FATAL" "$MLOG" 2>/dev/null || echo 0)
NEWCNT=$(find "$ROOT/.cache/factor_db" -maxdepth 1 -name 'factor_db_*.parquet' -newermt "2026-07-25 14:00" | wc -l)
IC_MT=$(stat -c %Y "$ROOT/.cache/factor_db/factor_ic_monthly.parquet" 2>/dev/null || echo 0)
echo "[$(ts)] monthly wait done: idle=${IDLE}s fatals=$FATALS rebuilt_today=$NEWCNT ic_mtime=$IC_MT" >> "$CL"
if [ "$FATALS" -gt 0 ] || [ "$NEWCNT" -lt 400 ]; then
  echo "[$(ts)] ABORT: 월간 재빌드 실패 의심 (fatals=$FATALS rebuilt=$NEWCNT) — fdb_daily 미착수" >> "$CL"
  exit 1
fi

# (a2) fdb_daily 전량 재빌드 (정본 절차, ~48분)
echo "[$(ts)] fdb_daily rebuild start" >> "$CL"
bash "$ROOT/02_Infrastructure/factor_db/run_fdb_rebuild.sh" >> "$CL" 2>&1
RC=$?
echo "[$(ts)] fdb_daily rebuild exit=$RC" >> "$CL"

# (b) A/B new-side
cd "$ROOT" && AB_LABEL=new Rscript "$OUT/ab_canonical_port_q4.R" >> "$CL" 2>&1
echo "[$(ts)] AB new-side exit=$?" >> "$CL"

# (c) 팩터 레벨 diff (Feb/Mar pinned 52 + IC 대조)
cd "$ROOT" && Rscript "$OUT/ab_snapshot_diff_q4.R" >> "$CL" 2>&1
echo "[$(ts)] snapshot diff exit=$?" >> "$CL"
echo "[$(ts)] CHAIN COMPLETE" >> "$CL"
