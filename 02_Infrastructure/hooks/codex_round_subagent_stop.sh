#!/usr/bin/env bash
#==============================================================================
# codex_round_subagent_stop.sh — v6.4 Codex Round SubagentStop check
#
# 이벤트: SubagentStop
# 목적: agent 종료 직전 final package + challenge_note 존재 검증.
#       missing 시 governance_log warn (block 안 함, agent already exited).
#
# Phase 6 (Sprint 2) — Codex Round v6.4 lifecycle 정합 (PostToolUse + PreToolUse + SubagentStop 3중)
#
# 작동:
#   - 입력 JSON에서 agent_role 추출
#   - active WT 디렉토리 스캔 (recently modified)
#   - 해당 role의 final package + (role-specific OR canonical) challenge_note 존재 확인
#   - missing 시 /tmp/codex_round_subagent_stop.log + governance_log warn entry
#==============================================================================

set -euo pipefail
LOG="/tmp/codex_round_subagent_stop.log"
trap 'echo "[$(date -Iseconds)] HOOK_ERR_TRAP" >> "$LOG"; echo "{}"; exit 0' ERR

INPUT=$(cat 2>/dev/null || echo "{}")

PROJ_DIR="${CLAUDE_PROJECT_DIR:-$(ls -d /mnt/c/Users/*/OneDrive/바탕*화면/Quant_Module_Moltbot 2>/dev/null | head -1 || echo "$PWD")}"
ROUTER="$PROJ_DIR/02_Infrastructure/hooks/qvest_hook_router.py"

# Agent role 추출 (JSON input에서)
AGENT_ROLE=$(printf '%s' "$INPUT" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
    # SubagentStop input format에서 agent type 추출 (best-effort)
    role = d.get("subagent_type", "") or d.get("agent_type", "") or ""
    role = role.replace("-research", "")  # alpha-research → alpha
    print(role)
except Exception:
    print("")
' 2>/dev/null || echo "")

if [[ -z "$AGENT_ROLE" ]] || [[ ! "$AGENT_ROLE" =~ ^(alpha|risk|optimizer|forge|judge|governor)$ ]]; then
  # 6 active role 외에는 skip (architect / blender / monitoring / execution 등)
  echo '{}'
  exit 0
fi

# Most recently modified WT 디렉토리 (agent가 마지막 작업한 곳 추정)
LATEST_WT=$(ls -t "$PROJ_DIR/qepm/mailbox/worktask/" 2>/dev/null | grep -E "^WT-[DPSH][0-9]{8}_[0-9]{3}$" | head -1 || echo "")

if [[ -z "$LATEST_WT" ]]; then
  echo '{}'
  exit 0
fi

# Router check
if [[ -f "$ROUTER" ]]; then
  RESULT=$(python3 "$ROUTER" check-codex-round-complete --wt-id "$LATEST_WT" --role "$AGENT_ROLE" 2>/dev/null || echo '{"complete":false,"reason":"router_call_failed"}')
  COMPLETE=$(echo "$RESULT" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("complete",False))' 2>/dev/null || echo "False")
  REASON=$(echo "$RESULT" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("reason",""))' 2>/dev/null || echo "")

  if [[ "$COMPLETE" == "True" ]]; then
    echo "[$(date -Iseconds)] PASS wt=$LATEST_WT role=$AGENT_ROLE | $REASON" >> "$LOG"
    echo '{}'
    exit 0
  else
    echo "[$(date -Iseconds)] WARN wt=$LATEST_WT role=$AGENT_ROLE | $REASON" >> "$LOG"
    # Append governance_log warn entry
    GOV_LOG="$PROJ_DIR/qepm/mailbox/worktask/$LATEST_WT/governance_log.json"
    if [[ -f "$GOV_LOG" ]]; then
      python3 - "$GOV_LOG" "$AGENT_ROLE" "$REASON" <<'PYEOF' 2>/dev/null || true
import json, sys, datetime
log_path, role, reason = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    with open(log_path, "r") as f:
        log = json.load(f)
    log.setdefault("events", []).append({
        "timestamp": datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
        "agent": "codex_round_subagent_stop",
        "action": "SUBAGENT_STOP_CODEX_ROUND_INCOMPLETE_WARN",
        "summary": f"role={role} | {reason}. Layer 2 sweep 권장: cert_backfill_audit.R --auto",
        "severity": "warn"
    })
    with open(log_path, "w") as f:
        json.dump(log, f, indent=2, ensure_ascii=False)
PYEOF
    fi
    echo "{}"
    exit 0
  fi
fi

# Router 부재 시 default allow
echo '{}'
exit 0
