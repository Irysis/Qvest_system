#!/usr/bin/env bash
# reproducibility_validator.sh — WT COMPLETED 시 reproducibility smoke test 플래그
# v6.1 R11
#
# 이벤트: PostToolUse[Write] on status.json (current_phase == COMPLETED)
# 목적: WT 완료 순간 reproducibility 필요 플래그 기록.
#       실제 재실행은 Q-Lead 또는 별도 cron이 수행 (Hook 내부 긴 작업 회피).

set -euo pipefail
trap 'exit 0' ERR

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_input",{}).get("file_path",""))' 2>/dev/null || echo "")
CONTENT=$(echo "$INPUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_input",{}).get("content",""))' 2>/dev/null || echo "")

case "$FILE_PATH" in
  */status.json)
    WT_ID=$(echo "$FILE_PATH" | grep -oE 'WT-[DP][0-9]{8}_[0-9]{3}|WT[0-9]{8}_[0-9]{3}' | head -1 || echo "")
    [[ -z "$WT_ID" ]] && exit 0

    PHASE=$(echo "$CONTENT" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("current_phase",""))' 2>/dev/null || echo "")

    if [[ "$PHASE" == "COMPLETED" ]]; then
      DIR=$(ls -d /g/Quant_Module_Moltbot /mnt/g/Quant_Module_Moltbot /mnt/c/Users/*/OneDrive/바탕\ 화면/Quant_Module_Moltbot 2>/dev/null | head -1 || echo "$PWD")
      FLAG="$DIR/qepm/mailbox/worktask/$WT_ID/reproducibility_pending.flag"
      echo "$(date -Iseconds) | WT=$WT_ID | smoke_reproduce() pending" > "$FLAG"
      echo "[reproducibility] $WT_ID flagged for smoke test" >> "/tmp/qvest_reproducibility.log"
    fi
    ;;
esac

exit 0
