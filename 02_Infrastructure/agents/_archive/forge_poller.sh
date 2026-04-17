#!/bin/bash
source "$(dirname "${BASH_SOURCE[0]:-$0}")/resolve_project.sh"
INBOX="$PROJECT/qepm/mailbox/forge/inbox"
SIGNAL="/tmp/forge_new_contract.flag"

while true; do
  COUNT=$(ls -1 "$INBOX"/*.json 2>/dev/null | wc -l)
  if [ "$COUNT" -gt 0 ]; then
    echo "$(date '+%H:%M:%S') — NEW CONTRACT(S): $COUNT file(s)"
    ls -1 "$INBOX"/*.json
    touch "$SIGNAL"
    break
  fi
  sleep 10
done
