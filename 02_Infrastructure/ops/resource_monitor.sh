#!/bin/bash
source "$(dirname "${BASH_SOURCE[0]:-$0}")/resolve_project.sh"
cd "$PROJECT"

while true; do
  R_COUNT=$(ps aux | grep 'R --no-echo' | grep -v grep | grep -v 'krx\|arrow\|daily' | wc -l)
  FORGE_INBOX=$(ls qepm/mailbox/forge/inbox/*.json 2>/dev/null | wc -l)
  RAM_PCT=$(free | awk '/Mem:/ {printf "%.0f", ($2-$7)/$2*100}')
  CPU_LOAD=$(uptime | awk -F'load average:' '{print $2}' | awk -F, '{printf "%.1f", $1}')
  
  echo "$(date +%H:%M): R=$R_COUNT inbox=$FORGE_INBOX RAM=${RAM_PCT}% CPU=$CPU_LOAD"
  
  # Forge 병목
  if [ $FORGE_INBOX -ge 3 ]; then
    echo "  → Forge 병목: inbox ${FORGE_INBOX}건 대기"
  fi
  
  # Scout 선행 필요
  if [ $FORGE_INBOX -lt 2 ] && [ $R_COUNT -ge 2 ]; then
    echo "  → Scout 선행 생산 필요"
  fi
  
  sleep 180
done
