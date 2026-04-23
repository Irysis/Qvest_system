#!/usr/bin/env bash
# forge_integration_audit.sh — Forge Integration Hash 감사 (Level 2)
# v6.1 R12 P4
#
# 이벤트: PostToolUse[Bash] after run_all.R 실행
# 목적: Forge 시작/종료 시 3-package hash 비교
#       Forge가 조용히 수정했는지 감지 (재해석 엔진化 방지)
#
# Hash 저장: /tmp/qvest_forge_hash_{wt_id}_{pre|post}.sha256

set -euo pipefail
trap 'exit 0' ERR

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_input",{}).get("command",""))' 2>/dev/null || echo "")

# run_all.R 실행 또는 Forge 백테 명령인지 확인
if ! echo "$COMMAND" | grep -qE 'run_all\.R|forge_integrate|Rscript.*worktask'; then
  exit 0
fi

# WT_id 추출
WT_ID=$(echo "$COMMAND" | grep -oE 'WT-[DP][0-9]{8}_[0-9]{3}|WT[0-9]{8}_[0-9]{3}' | head -1 || echo "")

if [[ -z "$WT_ID" ]]; then
  exit 0
fi

WT_DIR="qepm/mailbox/worktask/$WT_ID"

# 3-package hash 계산
HASH_FILE="/tmp/qvest_forge_hash_${WT_ID}_post.sha256"
{
  [[ -f "$WT_DIR/alpha_package.json" ]] && sha256sum "$WT_DIR/alpha_package.json"
  [[ -f "$WT_DIR/risk_package.json" ]] && sha256sum "$WT_DIR/risk_package.json"
  [[ -f "$WT_DIR/optimization_package.json" ]] && sha256sum "$WT_DIR/optimization_package.json"
} > "$HASH_FILE" 2>/dev/null

# Pre-hash 파일 있으면 비교
PRE_HASH_FILE="/tmp/qvest_forge_hash_${WT_ID}_pre.sha256"
if [[ -f "$PRE_HASH_FILE" ]]; then
  if ! diff -q "$PRE_HASH_FILE" "$HASH_FILE" > /dev/null 2>&1; then
    # Hash 변경 감지 → audit alert
    ALERT="/tmp/qvest_forge_audit_alert.log"
    echo "$(date -Iseconds) | $WT_ID | FORGE_MODIFIED_PACKAGES_DETECTED" >> "$ALERT"
    echo "=== pre-hash ===" >> "$ALERT"
    cat "$PRE_HASH_FILE" >> "$ALERT"
    echo "=== post-hash ===" >> "$ALERT"
    cat "$HASH_FILE" >> "$ALERT"
    echo "===" >> "$ALERT"
  fi
fi

exit 0
