#!/usr/bin/env bash
# pit_v3_daemon.sh — PIT Engine v3 비동기 분석 데몬 (Phase C1)
#
# 역할: forge_code_guard.sh의 PreToolUse[Bash] critical path에서
#       Rscript 호출(~45s)을 분리. 백그라운드에서 PIT 분석 → 결과 flag 저장.
#
# 호출 패턴:
#   nohup bash pit_v3_daemon.sh "$STRAT_NAME" "$STRAT_DIR" "$CONTENT_HASH" \
#         > /tmp/pit_v3_daemon.log 2>&1 &
#
# 출력 flag:
#   /tmp/pit_v3_clean_${STRAT_NAME}_${CONTENT_HASH}.flag  — CLEAN (통과)
#   /tmp/pit_v3_BLOCK_${STRAT_NAME}_${CONTENT_HASH}.flag  — BLOCK (위반)
#     내용: "$PIT_SEV|$PIT_NV|$VIOLATIONS_BRIEF"
#
# 호출 측(forge_code_guard)은 next invocation 시 BLOCK flag 우선 확인 → 즉시 block.

set -uo pipefail
trap 'echo "{}"; exit 0' ERR

STRAT_NAME="${1:-}"
STRAT_DIR="${2:-}"
CONTENT_HASH="${3:-}"

[ -z "$STRAT_NAME" ] || [ -z "$STRAT_DIR" ] || [ -z "$CONTENT_HASH" ] && exit 0
[ -d "$STRAT_DIR" ] || exit 0

PROJ=$(ls -d /c/Users/99922/OneDrive/Quant_Module_Moltbot /mnt/c/Users/99922/OneDrive/Quant_Module_Moltbot /g/Quant_Module_Moltbot /mnt/g/Quant_Module_Moltbot /mnt/c/Users/*/OneDrive/바탕\ 화면/Quant_Module_Moltbot 2>/dev/null | head -1)
LOG="/tmp/pit_v3_daemon.log"
LOCK="/tmp/pit_v3_daemon_${STRAT_NAME}_${CONTENT_HASH}.lock"

# 동시 실행 방지 (10분 stale 후 재실행 허용)
if [ -f "$LOCK" ]; then
  LOCK_AGE=$(( $(date +%s) - $(stat -c %Y "$LOCK" 2>/dev/null || echo 0) ))
  [ "$LOCK_AGE" -lt 600 ] && exit 0
fi
touch "$LOCK"

CLEAN_FLAG="/tmp/pit_v3_clean_${STRAT_NAME}_${CONTENT_HASH}.flag"
BLOCK_FLAG="/tmp/pit_v3_BLOCK_${STRAT_NAME}_${CONTENT_HASH}.flag"

# 이미 결과 있으면 skip
[ -f "$CLEAN_FLAG" ] || [ -f "$BLOCK_FLAG" ] && { rm -f "$LOCK"; exit 0; }

echo "$(date +%H:%M:%S) DAEMON_START: $STRAT_NAME ($CONTENT_HASH)" >> "$LOG"

PIT_OUT=$(cd "$PROJ" && timeout 60 Rscript --no-save -e "
suppressMessages(source('02_Infrastructure/R/hook_batch_runner.R'))
hook_pit_gate('$STRAT_DIR')
" 2>&1)

PIT_STATUS=$(echo "$PIT_OUT" | grep '^PIT_RESULT|' | head -1 | cut -d'|' -f2)
PIT_SEV=$(echo "$PIT_OUT" | grep '^PIT_RESULT|' | head -1 | cut -d'|' -f3)
PIT_NV=$(echo "$PIT_OUT" | grep '^PIT_RESULT|' | head -1 | cut -d'|' -f4)

if [ "$PIT_STATUS" = "CLEAN" ]; then
  touch "$CLEAN_FLAG"
  echo "$(date +%H:%M:%S) DAEMON_CLEAN: $STRAT_NAME" >> "$LOG"
else
  VIOLATIONS_BRIEF=$(echo "$PIT_OUT" | grep '^  -' | head -5 | tr '\n' '|' | sed 's/"/\\"/g; s/|/ | /g')
  printf '%s|%s|%s' "${PIT_SEV:-UNKNOWN}" "${PIT_NV:-?}" "$VIOLATIONS_BRIEF" > "$BLOCK_FLAG"
  echo "$(date +%H:%M:%S) DAEMON_BLOCK: $STRAT_NAME severity=$PIT_SEV n=$PIT_NV" >> "$LOG"
  echo "$PIT_OUT" >> "$LOG"
fi

# 오래된 cache 정리 (1주 이상)
find /tmp -maxdepth 1 -name "pit_v3_clean_${STRAT_NAME}_*.flag" -mmin +10080 -delete 2>/dev/null
find /tmp -maxdepth 1 -name "pit_v3_BLOCK_${STRAT_NAME}_*.flag" -mmin +10080 -delete 2>/dev/null

rm -f "$LOCK"
exit 0
