#!/bin/bash
#==============================================================================
# v54 Freeze Admission Rule Guard — PreToolUse[Write|Edit] Hook
# Tier: L3 (hard block)
#
# v54 Freeze Period (2026-04-18 ~ 2026-05-15) 동안 Admission Rule 수정 차단.
# Admission Rule v3.5.1 동결. 새 amendment는 하드 블로커 발생 시에만 허용.
#
# 대상 파일 패턴:
#   - .claude/skills/*admission*
#   - 02_Infrastructure/validation/admission_rule*.R
#   - qepm/mailbox/governor/outbox/*admission*
#   - 00_Lawbook/*admission*
#
# 예외: 파일 내 FREEZE_OVERRIDE_APPROVED_BY_QLEAD=true 주석 포함 시 허용
#
# 설치: settings.json PreToolUse[Write|Edit] hook으로 등록
# 관련: CLAUDE.md v54 Freeze Period, 00_Lawbook/v54_freeze_period_enforcement.md
#==============================================================================

trap 'echo "{}"; exit 0' ERR

INPUT=$(cat)

# ── Freeze 기간 확인 (KST 기준) ──────────────────────────────────────
FREEZE_START="2026-04-18"
FREEZE_END="2026-05-15"
TODAY_KST=$(TZ="Asia/Seoul" date +%Y-%m-%d 2>/dev/null || date +%Y-%m-%d)

# 날짜 비교 (lexicographic: YYYY-MM-DD 형식은 문자열 비교 가능)
if [[ "$TODAY_KST" < "$FREEZE_START" ]] || [[ "$TODAY_KST" > "$FREEZE_END" ]]; then
  echo '{}'
  exit 0
fi

# ── 도구 정보 파싱 ────────────────────────────────────────────────────
TOOL_NAME=$(printf '%s' "$INPUT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(d.get('tool_name', ''))
" 2>/dev/null || echo "")

FILE_PATH=$(printf '%s' "$INPUT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(d.get('tool_input', {}).get('file_path', ''))
" 2>/dev/null || echo "")

CONTENT=$(printf '%s' "$INPUT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
ti = d.get('tool_input', {})
print(ti.get('content', '') + ti.get('new_string', ''))
" 2>/dev/null || echo "")

LOG="/tmp/v54_freeze_guard.log"

# Write/Edit만 대상
if [ "$TOOL_NAME" != "Write" ] && [ "$TOOL_NAME" != "Edit" ]; then
  echo '{}'
  exit 0
fi

# ── Admission Rule 관련 파일 패턴 매칭 ────────────────────────────────
IS_ADMISSION_FILE=0

case "$FILE_PATH" in
  *.claude/skills/*admission*|*.claude/skills/*Admission*)
    IS_ADMISSION_FILE=1 ;;
  *02_Infrastructure/validation/admission_rule*|*02_Infrastructure/validation/Admission_rule*)
    IS_ADMISSION_FILE=1 ;;
  *qepm/mailbox/governor/outbox/*admission*|*qepm/mailbox/governor/outbox/*Admission*)
    IS_ADMISSION_FILE=1 ;;
  *00_Lawbook/*admission*|*00_Lawbook/*Admission*)
    IS_ADMISSION_FILE=1 ;;
  *admission_rule*|*Admission_Rule*)
    IS_ADMISSION_FILE=1 ;;
esac

if [ "$IS_ADMISSION_FILE" -eq 0 ]; then
  echo '{}'
  exit 0
fi

# ── FREEZE_OVERRIDE 예외 확인 ─────────────────────────────────────────
# 1. 새로 작성되는 콘텐츠에 override 주석이 있으면 허용
if echo "$CONTENT" | grep -q 'FREEZE_OVERRIDE_APPROVED_BY_QLEAD=true'; then
  echo "$(date +%H:%M:%S) V54_FREEZE: OVERRIDE accepted for $FILE_PATH" >> "$LOG"
  echo '{}'
  exit 0
fi

# 2. 기존 파일에 override 주석이 있으면 허용
if [ -n "$FILE_PATH" ] && [ -f "$FILE_PATH" ]; then
  if grep -q 'FREEZE_OVERRIDE_APPROVED_BY_QLEAD=true' "$FILE_PATH" 2>/dev/null; then
    echo "$(date +%H:%M:%S) V54_FREEZE: OVERRIDE (existing file) accepted for $FILE_PATH" >> "$LOG"
    echo '{}'
    exit 0
  fi
fi

# ── 차단 ──────────────────────────────────────────────────────────────
REASON="[v54 Freeze Guard] Admission Rule 수정 차단. Freeze Period ($FREEZE_START ~ $FREEZE_END) 동안 Admission Rule v3.5.1 동결. 하드 블로커 발생 시 Q-Lead 승인 필요: 파일에 FREEZE_OVERRIDE_APPROVED_BY_QLEAD=true 주석 추가 후 재시도."
echo "$(date +%H:%M:%S) V54_FREEZE BLOCK (admission_rule): $FILE_PATH" >> "$LOG"

ESCAPED=$(echo "$REASON" | sed 's/"/\\"/g')
printf '{"decision":"block","reason":"%s"}' "$ESCAPED"
exit 0
