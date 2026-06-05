#!/usr/bin/env bash
# lockbox_post_judge_seal.sh — Judge verdict 저장 후 lockbox 봉인 (Level 2)
# v6.1 R2-B Hook 3
#
# 이벤트: PostToolUse[Write] on judge_verdict*.json
# 목적: Judge verdict 저장 순간 lockbox 데이터에 sealed=true flag
#       재접근 시 warn + 이유 기록 의무 (post-hoc selection bias 방지)

set -euo pipefail
trap 'exit 0' ERR

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_input",{}).get("file_path",""))' 2>/dev/null || echo "")

FP_LOWER=$(echo "$FILE_PATH" | tr '[:upper:]' '[:lower:]')

case "$FP_LOWER" in
  *judge_verdict*|*judge_ready*verdict*)
    WT_ID=$(echo "$FILE_PATH" | grep -oE 'WT-[DP][0-9]{8}_[0-9]{3}|WT[0-9]{8}_[0-9]{3}' | head -1 || echo "")
    [[ -z "$WT_ID" ]] && exit 0

    DIR=$(ls -d /g/Quant_Module_Moltbot /mnt/g/Quant_Module_Moltbot /mnt/c/Users/*/OneDrive/바탕\ 화면/Quant_Module_Moltbot 2>/dev/null | head -1 || echo "$PWD")
    WT_DIR="$DIR/qepm/mailbox/worktask/$WT_ID"
    [[ ! -d "$WT_DIR" ]] && exit 0

    SEAL_FILE="$WT_DIR/lockbox_sealed.json"
    TS=$(date -Iseconds)
    cat > "$SEAL_FILE" <<EOF
{
  "task_id": "$WT_ID",
  "sealed": true,
  "sealed_at": "$TS",
  "sealed_by": "judge",
  "reason": "judge_verdict_published",
  "post_seal_access_warning": "lockbox re-access after seal requires explicit rationale in /tmp/qvest_lockbox_access_${WT_ID}.log"
}
EOF
    echo "[lockbox_seal] $WT_ID sealed at $TS" >> "/tmp/qvest_lockbox_seal.log"
    ;;
esac

exit 0
