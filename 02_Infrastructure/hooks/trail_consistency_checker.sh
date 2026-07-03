#!/bin/bash
# (v8.2.1 HOOK-P0-1) bare python3 → $QVEST_PY_BIN (Windows Store 스텁 fail-open 방지)
if [ -z "${QVEST_PY_BIN:-}" ]; then
  QVEST_PY_BIN="${QVEST_PY:-}"; QVEST_PY_BIN="${QVEST_PY_BIN//\//}"
  { [ -n "$QVEST_PY_BIN" ] && [ -x "$QVEST_PY_BIN" ]; } || QVEST_PY_BIN="/c/Users/99922/OneDrive/Quant_Module_Moltbot/.venv_qvest_ml/Scripts/python.exe"
  [ -x "$QVEST_PY_BIN" ] || QVEST_PY_BIN="$(command -v python.exe 2>/dev/null || echo python3)"
  export QVEST_PY_BIN
fi
#==============================================================================
# trail_consistency_checker.sh — PostToolUse[Write] Hook (v55 Tier 3.1)
#
# s0_record → s1_construction → s2_profile → ... 에서 trail 필드 전파 확인.
# 하위 stage artifact가 상위 s0_record의 trail과 다르면 WARN.
# trail 누락 시 자동 기본값 'standard' 적용 권고.
#==============================================================================

trap 'echo "{}"; exit 0' ERR

INPUT=$(cat)
LOG="/tmp/trail_consistency.log"

FILE=$(printf '%s' "$INPUT" | "$QVEST_PY_BIN" -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('tool_input', {}).get('file_path', ''))
except: print('')
" 2>/dev/null)

[ -z "$FILE" ] && { echo '{}'; exit 0; }

case "$FILE" in
  *stage_artifacts/s1_construction_*.json|*stage_artifacts/s2_profile_*.json|*stage_artifacts/s3_orthogonality_*.json|*stage_artifacts/s4_*.json|*stage_artifacts/s5_*.json|*stage_artifacts/s6_*.json)
    CHECK=$("$QVEST_PY_BIN" <<PYEOF
import json, os, glob, sys

try:
    with open('$FILE') as f: d = json.load(f)
except Exception as e:
    print(f'PARSE_ERROR|{e}')
    sys.exit(0)

# 이 stage artifact의 trail
current_trail = d.get('trail')

# 관련 s0_record 찾기
factor_id = d.get('factor_id', '')
strategy_id = d.get('strategy_id', '')

project_root = os.path.dirname(os.path.dirname(os.path.dirname('$FILE')))
s0_dir = os.path.join(project_root, 'stage_artifacts')

# s0_record 검색 (factor_id 또는 strategy_id 매칭)
s0_candidates = []
if factor_id:
    s0_candidates += glob.glob(os.path.join(s0_dir, f's0_record_*{factor_id}*.json'))
if strategy_id:
    s0_candidates += glob.glob(os.path.join(s0_dir, f's0_record_*{strategy_id}*.json'))

if not s0_candidates:
    print('SKIP|no_matching_s0_record')
    sys.exit(0)

# 가장 최신 s0_record
s0_candidates.sort(key=os.path.getmtime, reverse=True)
s0_file = s0_candidates[0]

try:
    with open(s0_file) as f: s0 = json.load(f)
except:
    print('SKIP|s0_parse_error')
    sys.exit(0)

s0_trail = s0.get('trail', 'standard')

if current_trail is None:
    print(f'WARN|trail 필드 누락. s0_record trail={s0_trail} 적용 권고.')
elif current_trail != s0_trail:
    print(f'MISMATCH|현재 trail={current_trail} != s0_record trail={s0_trail}')
else:
    print(f'PASS|trail={s0_trail} 전파 OK')
PYEOF
)
    STATUS=$(echo "$CHECK" | cut -d'|' -f1)
    MSG=$(echo "$CHECK" | cut -d'|' -f2-)

    case "$STATUS" in
      MISMATCH|WARN)
        echo "$(date +%H:%M:%S) TRAIL_CHECK $STATUS: $FILE — $MSG" >> "$LOG"
        ;;
      PASS)
        echo "$(date +%H:%M:%S) TRAIL_CHECK PASS: $FILE" >> "$LOG"
        ;;
    esac
    ;;
esac

echo '{}'
