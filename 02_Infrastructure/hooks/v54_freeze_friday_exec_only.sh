#!/bin/bash
#==============================================================================
# v54 Freeze Friday Exec-Only Guard — PreToolUse[Write] Hook
# Tier: L3 (hard block)
#
# v54 Freeze Period 동안 금요일(KST)은 실행 전용일.
# 새 프로세스 파일 생성 차단 (백테스트/factor_engine/run_all/L-code 발의는 허용).
#
# 차단 대상 (금요일에 새로 Write하는 파일):
#   - *governance_doc*
#   - *admission_rule* / *admission_gate*
#   - *rev[0-9]* / *phase*_plan*
#   - *process_* / *workflow_* / *procedure_*
#   - 00_Lawbook/ 하위 신규 파일
#
# 허용 대상 (금요일에도 무조건 허용):
#   - 04_Research/strategies/ 내 모든 파일 (run_all.R, factor_engine.R 등)
#   - *L-[0-9]* / *L_[0-9]* (L-code)
#   - *hurdle_result* / *tail_risk_result*
#   - stage_artifacts/ (s1_construction, s2_profiling 등)
#   - .cache/ / /tmp/
#   - qepm/mailbox/ (TODO/DONE 파이프라인)
#
# 요일 판단: UTC+9 기준 금요일 (date +%u, 5=금요일)
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

# ── 금요일 판단 (KST 기준) ───────────────────────────────────────────
# %u: 1=월 ... 5=금 ... 7=일
DOW_KST=$(TZ="Asia/Seoul" date +%u 2>/dev/null || date +%u)

if [ "$DOW_KST" != "5" ]; then
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

LOG="/tmp/v54_freeze_guard.log"

# Write만 대상
if [ "$TOOL_NAME" != "Write" ]; then
  echo '{}'
  exit 0
fi

# ── 무조건 허용 (allowlist) ───────────────────────────────────────────
BASENAME=$(basename "$FILE_PATH" 2>/dev/null || echo "")

# 1. Strategy 디렉토리 내 모든 파일
if echo "$FILE_PATH" | grep -qE '04_Research/strategies/STR_[0-9]+'; then
  echo '{}'
  exit 0
fi

# 2. L-code 파일
if echo "$BASENAME" | grep -qE '^L-[0-9]+|^L_[0-9]+|methodology_memory'; then
  echo '{}'
  exit 0
fi

# 3. 허들 결과 / 테일 리스크 결과
if echo "$BASENAME" | grep -qiE 'hurdle_result|tail_risk_result'; then
  echo '{}'
  exit 0
fi

# 4. Stage artifacts (파이프라인 산출물)
if echo "$FILE_PATH" | grep -qE 'stage_artifacts/'; then
  echo '{}'
  exit 0
fi

# 5. Cache / tmp
if echo "$FILE_PATH" | grep -qE '\.cache/|/tmp/'; then
  echo '{}'
  exit 0
fi

# 6. Mailbox (TODO/DONE 파이프라인)
if echo "$FILE_PATH" | grep -qE 'qepm/mailbox/'; then
  echo '{}'
  exit 0
fi

# 7. 텔레그램 / 스냅샷 산출물
if echo "$FILE_PATH" | grep -qE '06_Registry/snapshots/|telegram'; then
  echo '{}'
  exit 0
fi

# 8. Hook / infra 코드 (실행 지원 인프라)
if echo "$FILE_PATH" | grep -qE '02_Infrastructure/hooks/|02_Infrastructure/factor_db/'; then
  echo '{}'
  exit 0
fi

# 9. Memory 파일 (L-code 적립)
if echo "$FILE_PATH" | grep -qE 'memory/.*\.md$'; then
  echo '{}'
  exit 0
fi

# ── 차단 대상 (blocklist) ────────────────────────────────────────────
IS_PROCESS_FILE=0

# 프로세스 파일 패턴
if echo "$BASENAME" | grep -qiE 'governance_doc|admission_rule|admission_gate'; then
  IS_PROCESS_FILE=1
fi

if echo "$BASENAME" | grep -qiE 'rev[0-9]+|phase[0-9]*_plan'; then
  IS_PROCESS_FILE=1
fi

if echo "$BASENAME" | grep -qiE '^process_|^workflow_|^procedure_|^policy_'; then
  IS_PROCESS_FILE=1
fi

# Lawbook 하위 신규 파일
if echo "$FILE_PATH" | grep -qE '00_Lawbook/'; then
  # 기존 파일 수정은 허용 (Write이지만 파일이 이미 존재)
  if [ ! -f "$FILE_PATH" ]; then
    IS_PROCESS_FILE=1
  fi
fi

# Governor 관련 신규 프로세스 문서
if echo "$BASENAME" | grep -qiE 'governor.*plan|consensus_taxonomy|structural_diagnosis'; then
  IS_PROCESS_FILE=1
fi

if [ "$IS_PROCESS_FILE" -eq 0 ]; then
  echo '{}'
  exit 0
fi

# ── FREEZE_OVERRIDE 예외 확인 ─────────────────────────────────────────
CONTENT=$(printf '%s' "$INPUT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
ti = d.get('tool_input', {})
print(ti.get('content', ''))
" 2>/dev/null || echo "")

if echo "$CONTENT" | grep -q 'FREEZE_OVERRIDE_APPROVED_BY_QLEAD=true'; then
  echo "$(date +%H:%M:%S) V54_FREEZE_FRI: OVERRIDE accepted for $FILE_PATH" >> "$LOG"
  echo '{}'
  exit 0
fi

# ── 차단 ──────────────────────────────────────────────────────────────
REASON="[v54 Freeze Friday Guard] 금요일은 실행 전용일. 새 프로세스 파일($BASENAME) 생성 차단. 백테스트/factor_engine/run_all/L-code 발의만 허용. Q-Lead 승인 필요: FREEZE_OVERRIDE_APPROVED_BY_QLEAD=true 추가 후 재시도."
echo "$(date +%H:%M:%S) V54_FREEZE_FRI BLOCK: $FILE_PATH (DOW=$DOW_KST)" >> "$LOG"

ESCAPED=$(echo "$REASON" | sed 's/"/\\"/g')
printf '{"decision":"block","reason":"%s"}' "$ESCAPED"
exit 0
