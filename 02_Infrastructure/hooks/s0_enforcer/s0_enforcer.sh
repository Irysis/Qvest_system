#!/usr/bin/env bash
# (v8.2.1 HOOK-P0-1) bare python3 → $QVEST_PY_BIN (Windows Store 스텁 fail-open 방지)
if [ -z "${QVEST_PY_BIN:-}" ]; then
  QVEST_PY_BIN="${QVEST_PY:-}"; QVEST_PY_BIN="${QVEST_PY_BIN//\//}"
  { [ -n "$QVEST_PY_BIN" ] && [ -x "$QVEST_PY_BIN" ]; } || QVEST_PY_BIN="/c/Users/99922/OneDrive/Quant_Module_Moltbot/.venv_qvest_ml/Scripts/python.exe"
  [ -x "$QVEST_PY_BIN" ] || QVEST_PY_BIN="$(command -v python.exe 2>/dev/null || echo python3)"
  export QVEST_PY_BIN
fi
#==============================================================================
# s0_enforcer.sh — Dispatcher (Phase C3.5 split of s0_debate_enforcer.sh)
#
# 역할: stdin tool_input 파싱 → DTYPE 분기 → state_machine.py 단일 호출 →
#       결과 JSON에서 hook_decision/telegram/post_actions 분리 → 외부 실행.
#
# 대체 대상: 02_Infrastructure/hooks/s0_debate_enforcer.sh (980L).
# settings.json은 이 파일 또는 기존 경로를 모두 지원하도록 shim 유지.
#==============================================================================

trap 'echo "{}"; exit 0' ERR

INPUT=$(cat)

# tool_input.file_path 파싱
FILE_PATH=$(printf '%s' "$INPUT" | "$QVEST_PY_BIN" -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('tool_input', {}).get('file_path', ''))
except Exception: print('')
" 2>/dev/null || echo "")

# DTYPE 분기
case "$FILE_PATH" in
  *s0_debate_r1_*.json) DTYPE="R1" ;;
  *s0_debate_r2_*.json) DTYPE="R2" ;;
  *s0_debate_r3_*.json) DTYPE="R3" ;;
  *S0_VERDICT*.json)    DTYPE="VERDICT" ;;
  *s0_debate_transcript*.json) echo '{}'; exit 0 ;;  # 검증 없이 통과
  *) echo '{}'; exit 0 ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
DIR=$(ls -d /c/Users/99922/OneDrive/Quant_Module_Moltbot /mnt/c/Users/99922/OneDrive/Quant_Module_Moltbot /g/Quant_Module_Moltbot /mnt/g/Quant_Module_Moltbot /mnt/c/Users/*/OneDrive/바탕\ 화면/Quant_Module_Moltbot 2>/dev/null | head -1 || echo "$PWD")
export QVEST_PROJECT_ROOT="$DIR"

# HYP_ID 추출 (파일명 → H_[A-Za-z0-9]+(_[A-Za-z0-9]+)* 패턴)
HYP_ID=$(basename "$FILE_PATH" | "$QVEST_PY_BIN" -c "
import sys, re
name = sys.stdin.read().strip()
stem = name.rsplit('.', 1)[0]
m = re.search(r'(H_[A-Za-z0-9]+(?:_[A-Za-z0-9]+)*)\s*$', stem)
print(m.group(1) if m else 'unknown')
" 2>/dev/null || echo "unknown")

# state_machine 호출 (stdin = 원본 INPUT 재주입)
RESULT=$(printf '%s' "$INPUT" | "$QVEST_PY_BIN" "$SCRIPT_DIR/state_machine.py" "$DTYPE" "$HYP_ID" 2>>/tmp/s0_debate_enforcer.log)

if [ -z "$RESULT" ]; then
  echo '{}'
  exit 0
fi

# 결과 파싱: hook_decision + telegram 배열 + post_actions
HOOK_DECISION=$(printf '%s' "$RESULT" | "$QVEST_PY_BIN" -c "
import sys, json
try:
    d = json.loads(sys.stdin.read())
    print(json.dumps(d.get('hook_decision', {}) or {}, ensure_ascii=False))
except Exception: print('{}')
" 2>/dev/null || echo '{}')

# Telegram 메시지 배열 → 순차 발송 (background)
source "$SCRIPT_DIR/telegram_async.sh"
printf '%s' "$RESULT" | "$QVEST_PY_BIN" -c "
import sys, json
try:
    d = json.loads(sys.stdin.read())
    for m in d.get('telegram', []) or []:
        print(m)
        print('---TG_SEP---')
except Exception: pass
" 2>/dev/null | awk -v RS='---TG_SEP---\n' 'NF {print $0; print "---MSG_END---"}' | while IFS= read -r line; do
  if [ "$line" = "---MSG_END---" ]; then
    if [ -n "${MSG_BUF:-}" ]; then
      tg_notify "$MSG_BUF"
      MSG_BUF=""
    fi
  else
    MSG_BUF="${MSG_BUF:+${MSG_BUF}
}${line}"
  fi
done

# Post-actions 처리
POST_ACTIONS_JSON=$(printf '%s' "$RESULT" | "$QVEST_PY_BIN" -c "
import sys, json
try:
    d = json.loads(sys.stdin.read())
    pa = d.get('post_actions', []) or []
    print(json.dumps(pa))
except Exception: print('[]')
" 2>/dev/null || echo '[]')

if [ "$POST_ACTIONS_JSON" != "[]" ]; then
  # 각 action 실행
  printf '%s' "$POST_ACTIONS_JSON" | "$QVEST_PY_BIN" -c "
import sys, json
for a in json.loads(sys.stdin.read()):
    t = a.get('type', '')
    adir = a.get('artifacts_dir', '')
    print(f'{t}\t{adir}')
" 2>/dev/null | while IFS=$'\t' read -r atype adir; do
    case "$atype" in
      codex_r2_trigger)
        nohup bash "$SCRIPT_DIR/codex_r2_trigger.sh" "$HYP_ID" "$adir" \
          > /dev/null 2>>/tmp/s0_debate_enforcer.log &
        disown 2>/dev/null || true
        ;;
      compact_factcheck)
        S0_RECORD=$(ls "$adir"/s0_record_*"${HYP_ID}"*.json 2>/dev/null | head -1)
        if [ -n "$S0_RECORD" ] && [ -f "$S0_RECORD" ]; then
          HYP_ID="$HYP_ID" nohup bash "$DIR/02_Infrastructure/tools/debate_helpers/academic_factcheck.sh" \
            "$S0_RECORD" > /dev/null 2>>/tmp/academic_factcheck_${HYP_ID}.log &
          HYP_ID="$HYP_ID" FC_CONTENT="$(cat "$S0_RECORD")" \
            nohup bash "$DIR/02_Infrastructure/tools/debate_helpers/quant_factcheck.sh" \
            "$S0_RECORD" > /dev/null 2>>/tmp/quant_factcheck_${HYP_ID}.log &
          echo "$(date +%H:%M:%S) ENFORCER: Compact factcheck hooks triggered for $HYP_ID" >> /tmp/s0_debate_enforcer.log
        else
          echo "$(date +%H:%M:%S) ENFORCER WARN: s0_record not found for $HYP_ID factcheck" >> /tmp/s0_debate_enforcer.log
        fi
        ;;
    esac
  done
fi

# hook_decision 출력 (Claude Code에 전달)
echo "$HOOK_DECISION"
exit 0
