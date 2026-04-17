#!/bin/bash
#==============================================================================
# Axiom Enforcement Hook — PreToolUse[Write|Edit] (v52 AX 배선)
# AX-code 위반 패턴을 탐지하고 차단한다.
# Level 0: AX-code > PIT C1-C15 > L-code > Signals
#==============================================================================

trap 'echo "{}"; exit 0' ERR

INPUT=$(cat)

TOOL_NAME=$(printf '%s' "$INPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('tool_name', ''))
except: print('')
" 2>/dev/null || echo "")

# Write/Edit만 검사
if [ "$TOOL_NAME" != "Write" ] && [ "$TOOL_NAME" != "Edit" ]; then
  echo '{}'
  exit 0
fi

FILE_PATH=$(printf '%s' "$INPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('tool_input', {}).get('file_path', ''))
except: print('')
" 2>/dev/null || echo "")

CONTENT=$(printf '%s' "$INPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    ti = d.get('tool_input', {})
    print(ti.get('content', ti.get('new_string', ''))[:3000])
except: print('')
" 2>/dev/null || echo "")

DIR=$(ls -d /mnt/c/Users/*/OneDrive/바탕\ 화면/Quant_Module_Moltbot 2>/dev/null | head -1)
LOG="/tmp/axiom_enforcement.log"

# ─── AX-001: Defense 전기간 SR 기준 금지 ─────────────────────────────────────
# hurdle_result.json 또는 s6_judge에서 defense 전략을 전기간 SR만으로 Grade F 판정
if echo "$FILE_PATH" | grep -qE "(hurdle_result|s6_judge|s7_).*\.json"; then
  if echo "$CONTENT" | grep -qiE "defense|Defence"; then
    if echo "$CONTENT" | grep -qiE '"grade".*"F"' && ! echo "$CONTENT" | grep -qiE "crisis|stress|conditional|bad_normal|regime"; then
      echo "$(date +%H:%M:%S) AX-001_WARN: $FILE_PATH — Defense Grade F without conditional eval" >> "$LOG"
      printf '{"decision":"block","reason":"[AX-001] Defense 전략을 전기간 SR만으로 Grade F 판정 금지. 위기 구간 alpha + Core 대비 MDD + bad/normal IC ratio 조건부 평가 필수."}'
      exit 0
    fi
  fi
fi

# ─── AX-002: 프로세스 우회 탐지 (금지 합리화 표현) ────────────────────────────
# S1 결과를 보고 S0 가설을 사후 정당화하는 패턴
if echo "$FILE_PATH" | grep -qE "s0_record.*\.json"; then
  if echo "$CONTENT" | grep -qiE "S1.*결과.*확인.*후|백테스트.*결과.*바탕|성과.*보고.*수정"; then
    echo "$(date +%H:%M:%S) AX-002_WARN: $FILE_PATH — s0_record에 S1 결과 기반 사후 수정 의심" >> "$LOG"
    # 경고만 (차단은 과도)
    echo "{\"additionalContext\":\"[AX-002 경고] s0_record에 S1 결과 기반 사후 수정 패턴 탐지. S0 가설은 S1 실행 전에 확정되어야 합니다.\"}"
    exit 0
  fi
fi

# ─── v53 Sprint 4 AX-P2: 동적 AX.enforcement 규칙 적용 ────────────────────
# 모든 active AX의 enforcement 필드를 regex 기반으로 적용
_ACTIVE_DIR="$DIR/qepm/memory/axioms/active"
if [ -d "$_ACTIVE_DIR" ]; then
  _VIOLATION=$(printf '%s' "$CONTENT" | python3 -c "
import sys, json, os, glob, re
content = sys.stdin.read()
file_path = '$FILE_PATH'
for f in sorted(glob.glob(os.path.join('$_ACTIVE_DIR', 'AX-*.json'))):
    try:
        ax = json.load(open(f))
    except Exception: continue
    enforcement = ax.get('enforcement') or ''
    if not enforcement: continue
    ax_id = ax.get('axiom_id') or ax.get('id') or os.path.basename(f)
    # enforcement 필드가 특정 regex 또는 조건을 담고 있는 경우
    # 형식: {regex: 'pattern', require: 'text_must_contain'}
    if isinstance(enforcement, dict):
        pat = enforcement.get('regex')
        req = enforcement.get('require')
        applies = enforcement.get('applies_to_files', ['.*'])
        if not any(re.search(a, file_path) for a in applies):
            continue
        if pat and re.search(pat, content, re.IGNORECASE | re.MULTILINE):
            # 패턴 감지 시 require 필드 존재 검증
            if req and req not in content:
                print(f'VIOLATION|{ax_id}|{enforcement.get(\"reason\", pat)}')
                sys.exit(0)
" 2>/dev/null)
  if [ -n "$_VIOLATION" ] && echo "$_VIOLATION" | grep -q "^VIOLATION|"; then
    AX_ID=$(echo "$_VIOLATION" | cut -d'|' -f2)
    AX_REASON=$(echo "$_VIOLATION" | cut -d'|' -f3-)
    echo "$(date +%H:%M:%S) AX_ENFORCE_BLOCK: $AX_ID $AX_REASON" >> "$LOG"
    printf '{"decision":"block","reason":"[%s Enforcement] %s. active axiom enforcement 규칙 위반."}' "$AX_ID" "$AX_REASON"
    exit 0
  fi
fi

echo '{}'
exit 0
