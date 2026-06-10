#!/bin/bash
#==============================================================================
# v53 Sprint 1: Mailbox Archive 스크립트
# - qepm/mailbox/*/inbox/ 의 누적 DONE/SKIP 파일을 processed/archive/YYYY-MM/로 이동
# - 주간 crontab 실행 추천 (매주 일요일 03:00)
#==============================================================================

set -u
source "$(dirname "${BASH_SOURCE[0]:-$0}")/resolve_project.sh" 2>/dev/null || {
  PROJECT_ROOT=$(ls -d /c/Users/99922/OneDrive/Quant_Module_Moltbot /mnt/c/Users/99922/OneDrive/Quant_Module_Moltbot /g/Quant_Module_Moltbot /mnt/g/Quant_Module_Moltbot /mnt/c/Users/*/OneDrive/바탕\ 화면/Quant_Module_Moltbot 2>/dev/null | head -1)
  export PROJECT_ROOT
}

MAILBOX="$PROJECT_ROOT/qepm/mailbox"
YM=$(date +%Y-%m)
TOTAL=0

[ ! -d "$MAILBOX" ] && { echo "[archive_mailbox] MAILBOX not found: $MAILBOX"; exit 1; }

echo "=== archive_mailbox ($(date +%F %H:%M)) ==="

for agent_dir in "$MAILBOX"/*/; do
  agent=$(basename "$agent_dir")
  inbox="$agent_dir/inbox"
  archive="$agent_dir/processed/archive/$YM"
  [ ! -d "$inbox" ] && continue
  mkdir -p "$archive" 2>/dev/null

  moved=0
  # DONE_* 또는 SKIP_* 파일 중 7일+ 된 것 → archive
  while IFS= read -r -d '' f; do
    mv "$f" "$archive/" 2>/dev/null && moved=$((moved + 1))
  done < <(find "$inbox" -maxdepth 1 \( -name "DONE_*" -o -name "SKIP_*" -o -name "ARCHIVED_*" \) -type f -mtime +7 -print0 2>/dev/null)

  if [ "$moved" -gt 0 ]; then
    echo "  $agent: $moved 건 archive → $archive"
    TOTAL=$((TOTAL + moved))
  fi
done

echo "총 이동: $TOTAL 건"

# /tmp 로그 90일+ 압축 후 .cache/logs_archive/로 이동
CACHE_LOGS="$PROJECT_ROOT/.cache/logs_archive/$YM"
mkdir -p "$CACHE_LOGS" 2>/dev/null
log_moved=0
for log_file in /tmp/pipeline_trigger.log /tmp/artifact_validation.log /tmp/qlead_supervisor.log /tmp/axiom_weekly.log /tmp/axiom_quarterly.log; do
  if [ -f "$log_file" ]; then
    age=$(( ($(date +%s) - $(stat -c %Y "$log_file")) / 86400 ))
    if [ "$age" -gt 90 ]; then
      gzip -c "$log_file" > "$CACHE_LOGS/$(basename "$log_file").$(date +%Y%m%d).gz" && \
        : > "$log_file" && log_moved=$((log_moved + 1))
    fi
  fi
done
[ "$log_moved" -gt 0 ] && echo "/tmp 로그 archive: $log_moved 건 → $CACHE_LOGS"

echo "=== archive_mailbox 완료 ==="
