#!/usr/bin/env bash
# (v8.2.1 HOOK-P0-1) bare python3 → $QVEST_PY_BIN (Windows Store 스텁 fail-open 방지)
if [ -z "${QVEST_PY_BIN:-}" ]; then
  QVEST_PY_BIN="${QVEST_PY:-}"; QVEST_PY_BIN="${QVEST_PY_BIN//\//}"
  { [ -n "$QVEST_PY_BIN" ] && [ -x "$QVEST_PY_BIN" ]; } || QVEST_PY_BIN="/c/Users/99922/OneDrive/Quant_Module_Moltbot/.venv_qvest_ml/Scripts/python.exe"
  [ -x "$QVEST_PY_BIN" ] || QVEST_PY_BIN="$(command -v python.exe 2>/dev/null || echo python3)"
  export QVEST_PY_BIN
fi
# agent_stop_continuity_check.sh — Tier 5 agent stop incomplete escalate (L2)
#
# 이벤트: SubagentStop (Stop event 변형)
# 목적: agent stop 시 expected artifacts 미작성 detect → Q-Lead escalate
# 무한루프 회피: max 2 escalate cap (/tmp/qvest_escalate_count_*.txt)

set -euo pipefail
trap 'echo "{}"; exit 0' ERR

INPUT=$(cat)
EVENT=$(printf '%s' "$INPUT" | "$QVEST_PY_BIN" -c 'import json,sys; d=json.load(sys.stdin); print(d.get("hook_event_name",""))' 2>/dev/null || echo "")
AGENT_ID=$(printf '%s' "$INPUT" | "$QVEST_PY_BIN" -c 'import json,sys; d=json.load(sys.stdin); print(d.get("agent_id","") or d.get("subagent_id",""))' 2>/dev/null || echo "")
AGENT_NAME=$(printf '%s' "$INPUT" | "$QVEST_PY_BIN" -c 'import json,sys; d=json.load(sys.stdin); print(d.get("agent_name","") or d.get("subagent_type",""))' 2>/dev/null || echo "")

# Only act on stop events
if [[ "$EVENT" != "SubagentStop" && "$EVENT" != "Stop" ]]; then
  echo '{}'; exit 0
fi

PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-${QM_ROOT:-$(ls -d /c/Users/99922/OneDrive/Quant_Module_Moltbot /mnt/c/Users/99922/OneDrive/Quant_Module_Moltbot /g/Quant_Module_Moltbot /mnt/g/Quant_Module_Moltbot 2>/dev/null | head -1)}}"

# Detect WT_id from current working dir or env
WT_ID="${QVEST_CURRENT_WT_ID:-}"
if [[ -z "$WT_ID" ]]; then
  # try latest WT in mailbox
  WT_ID=$(ls -t "$PROJECT_ROOT/qepm/mailbox/worktask/" 2>/dev/null | grep -E '^WT-' | head -1 || echo "")
fi

[[ -z "$WT_ID" ]] && { echo '{}'; exit 0; }

WT_DIR="$PROJECT_ROOT/qepm/mailbox/worktask/$WT_ID"
[[ ! -d "$WT_DIR" ]] && { echo '{}'; exit 0; }

# Per-agent expected artifacts
INCOMPLETE=()
case "$AGENT_NAME" in
  alpha*)
    [[ ! -f "$WT_DIR/alpha_package.json" ]] && INCOMPLETE+=("alpha_package.json")
    [[ ! -f "$WT_DIR/factor_engine_proposal.R" ]] && INCOMPLETE+=("factor_engine_proposal.R")
    ;;
  risk*)
    [[ ! -f "$WT_DIR/risk_package.json" ]] && INCOMPLETE+=("risk_package.json")
    ;;
  optimizer*|opt_*)
    [[ ! -f "$WT_DIR/optimization_package.json" ]] && INCOMPLETE+=("optimization_package.json")
    [[ ! -f "$WT_DIR/weights.csv" ]] && INCOMPLETE+=("weights.csv")
    ;;
  forge*)
    [[ ! -f "$WT_DIR/forge_package.json" && ! -f "$WT_DIR/forge_phase4_package.json" ]] && INCOMPLETE+=("forge_package.json")
    ;;
  judge*)
    [[ ! -f "$WT_DIR/judge_verdict.json" ]] && INCOMPLETE+=("judge_verdict.json")
    ;;
  governor*)
    [[ ! -f "$WT_DIR/governor_admission.json" ]] && INCOMPLETE+=("governor_admission.json")
    ;;
  *)
    echo '{}'; exit 0
    ;;
esac

if [[ ${#INCOMPLETE[@]} -eq 0 ]]; then
  echo '{}'; exit 0
fi

# Escalate cap — max 2 attempts, then user manual intervention
ESCALATE_FILE="/tmp/qvest_escalate_count_${WT_ID}_${AGENT_NAME}.txt"
ESCALATE_COUNT=0
[[ -f "$ESCALATE_FILE" ]] && ESCALATE_COUNT=$(cat "$ESCALATE_FILE" 2>/dev/null || echo "0")
ESCALATE_COUNT=$((ESCALATE_COUNT + 1))
echo "$ESCALATE_COUNT" > "$ESCALATE_FILE"

INCOMPLETE_LIST=$(IFS=','; echo "${INCOMPLETE[*]}")

if [[ $ESCALATE_COUNT -ge 2 ]]; then
  ALERT_MSG="STOP_CONTINUITY_CAP (2+ escalate, user intervention required) | wt=$WT_ID agent=$AGENT_NAME incomplete=[$INCOMPLETE_LIST]"
  # Telegram alert (if available)
  if [[ -f "$PROJECT_ROOT/02_Infrastructure/telegram/telegram_notify.R" ]]; then
    nohup Rscript -e "
    setwd('$PROJECT_ROOT')
    source('02_Infrastructure/telegram/telegram_notify.R')
    tg_send('🚨 [Stop Continuity Cap] $ALERT_MSG', parse_mode='')
    " > /dev/null 2>&1 &
  fi
  echo "{}"
else
  echo "{}"
fi
