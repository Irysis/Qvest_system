#!/bin/bash
#==============================================================================
# v54 Freeze Governor Rev Guard — PreToolUse[Write] Hook
# Tier: L3 (hard block)
#
# v54 Freeze Period (2026-04-18 ~ 2026-05-15) 동안 Governor 신규 rev 생성 차단.
# rev8-A-revised_v2 Scenario C 실행만 허용. 새 rev 파일 생성 금지.
#
# 대상 파일 패턴:
#   - qepm/mailbox/governor/outbox/*rev*
#   - stage_artifacts/*PG0_PLAN_rev*
#   - stage_artifacts/*governor_rev*
#
# 예외:
#   - 파일명에 scenario_C 또는 rev8-A-revised_v2 포함 시 허용
#   - 파일/콘텐츠에 FREEZE_OVERRIDE_APPROVED_BY_QLEAD=true 포함 시 허용
#   - 기존 파일 수정(Edit)은 허용, 새 rev 파일 Write만 차단
#
# 설치: settings.json PreToolUse[Write] hook으로 등록
# 관련: CLAUDE.md v54 Freeze Period, 00_Lawbook/v54_freeze_period_enforcement.md
#==============================================================================

trap 'echo "{}"; exit 0' ERR

INPUT=$(cat)

# ── Freeze 기간 확인 (KST 기준) ──────────────────────────────────────
FREEZE_START="2026-04-18"
FREEZE_END="2026-05-15"
TODAY_KST=$(TZ="Asia/Seoul" date +%Y-%m-%d 2>/dev/null || date +%Y-%m-%d)

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

# Write만 대상 (Edit은 기존 파일 수정이므로 허용)
if [ "$TOOL_NAME" != "Write" ]; then
  echo '{}'
  exit 0
fi

# ── Governor rev 관련 파일 패턴 매칭 ──────────────────────────────────
IS_GOV_REV=0
BASENAME=$(basename "$FILE_PATH" 2>/dev/null || echo "")

# Governor outbox rev 파일
if echo "$FILE_PATH" | grep -qE 'qepm/mailbox/governor/outbox/.*rev'; then
  IS_GOV_REV=1
fi

# Stage artifacts PG0 rev 파일
if echo "$FILE_PATH" | grep -qE 'stage_artifacts/.*PG0_PLAN_rev'; then
  IS_GOV_REV=1
fi

# Stage artifacts governor rev 파일
if echo "$FILE_PATH" | grep -qE 'stage_artifacts/.*governor_rev'; then
  IS_GOV_REV=1
fi

# 일반적인 rev 패턴 (governor 컨텍스트에서)
if echo "$FILE_PATH" | grep -qiE 'governor.*rev[0-9]|rev[0-9].*governor'; then
  IS_GOV_REV=1
fi

if [ "$IS_GOV_REV" -eq 0 ]; then
  echo '{}'
  exit 0
fi

# ── 허용 예외 1: scenario_C 또는 rev8-A-revised_v2 ────────────────────
if echo "$BASENAME" | grep -qiE 'scenario_C|scenario.C|rev8.A.revised.v2|rev8_A_revised_v2'; then
  echo "$(date +%H:%M:%S) V54_FREEZE: scenario_C/rev8 허용 — $FILE_PATH" >> "$LOG"
  echo '{}'
  exit 0
fi

# 콘텐츠 내에서도 scenario_C 참조 확인 (rev8 실행 산출물일 수 있음)
if echo "$CONTENT" | grep -qiE '"scenario"\s*:\s*"C"|scenario_C|rev8.A.revised.v2'; then
  echo "$(date +%H:%M:%S) V54_FREEZE: scenario_C content 허용 — $FILE_PATH" >> "$LOG"
  echo '{}'
  exit 0
fi

# ── 허용 예외 2: FREEZE_OVERRIDE ──────────────────────────────────────
if echo "$CONTENT" | grep -q 'FREEZE_OVERRIDE_APPROVED_BY_QLEAD=true'; then
  echo "$(date +%H:%M:%S) V54_FREEZE: OVERRIDE accepted for $FILE_PATH" >> "$LOG"
  echo '{}'
  exit 0
fi

if [ -n "$FILE_PATH" ] && [ -f "$FILE_PATH" ]; then
  if grep -q 'FREEZE_OVERRIDE_APPROVED_BY_QLEAD=true' "$FILE_PATH" 2>/dev/null; then
    echo "$(date +%H:%M:%S) V54_FREEZE: OVERRIDE (existing) accepted for $FILE_PATH" >> "$LOG"
    echo '{}'
    exit 0
  fi
fi

# ── 차단 ──────────────────────────────────────────────────────────────
REASON="[v54 Freeze Guard] Governor 신규 rev 생성 차단. Freeze Period ($FREEZE_START ~ $FREEZE_END) 동안 rev8-A-revised_v2 Scenario C 실행만 허용. 새 rev 파일 금지. Q-Lead 승인 필요: 파일에 FREEZE_OVERRIDE_APPROVED_BY_QLEAD=true 주석 추가 후 재시도."
echo "$(date +%H:%M:%S) V54_FREEZE BLOCK (governor_rev): $FILE_PATH ($BASENAME)" >> "$LOG"

ESCAPED=$(echo "$REASON" | sed 's/"/\\"/g')
printf '{"decision":"block","reason":"%s"}' "$ESCAPED"
exit 0
