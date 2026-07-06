#!/usr/bin/env bash
#==============================================================================
# overlay_pit_grep.sh — PostToolUse[Write/Edit] Hook (Level 2 soft advisory)
#
# 오버레이 신호 타이밍 PIT 위반 탐지 (pit.md C5 구체화, 2026-07-06 도훈 지시)
# 사건: BearProb 오버레이가 Date<anchor_date로 신호 로드 → 홀딩월 말 정보 = 동월 look-ahead
#       (Calmar 2.50→1.83 인플레). placebo/OOS/DSR 통과, lag1+strict-PIT A/B만 판별.
#
# 탐지:
#   OVERLAY_CODE  = 오버레이 구성 패턴 (apply_gate / beta_R05 / m4*ret_orig / gate( / Bear_Prob / 오버레이)
#   ANTIPATTERN   = Date < ...anchor_date | Date < ...realized_ym  (라벨date를 신호 컷오프로 = 버그)
#   GUARD         = overlay_pit_guard 소스 여부
#   SIGNAL_LOAD   = Date <  로 일별 신호 컷오프
#
# 경보(soft, log only, never block):
#   A) OVERLAY_CODE ∧ ANTIPATTERN            → ★강경보 (THE 버그 패턴)
#   B) OVERLAY_CODE ∧ SIGNAL_LOAD ∧ ¬GUARD   → soft 리마인더 (가드+lag1+strict-A/B 의무)
#
# 우회: QVEST_SKIP_OVERLAY_PIT=1 / 로그: /tmp/overlay_pit_grep.log
# 참조: .claude/rules/pit.md §오버레이 신호 타이밍 · 02_Infrastructure/validation/overlay_pit_guard.R
#==============================================================================
trap 'echo "{}"; exit 0' ERR
set -u
INPUT=$(cat 2>/dev/null || echo '{}')
LOG="/tmp/overlay_pit_grep.log"
TS="$(date '+%Y-%m-%d %H:%M:%S')"

[ "${QVEST_SKIP_OVERLAY_PIT:-0}" = "1" ] && { echo '{}'; exit 0; }

FILE_PATH=$(echo "$INPUT" | grep -oE '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
[ -z "$FILE_PATH" ] && { echo '{}'; exit 0; }
[ ! -f "$FILE_PATH" ] && { echo '{}'; exit 0; }
# .R 파일만
echo "$FILE_PATH" | grep -qE '\.R$' || { echo '{}'; exit 0; }

OVERLAY_CODE='apply_gate|beta_R05|beta_bear|m4[[:space:]]*\*[[:space:]]*ret_orig|ret_orig[[:space:]]*\*|[^a-z]gate\(|Bear_Prob|regime_jump|오버레이|overlay_beta|beta_total'
ANTIPATTERN='Date[[:space:]]*<[^,;)=]*anchor_date|Date[[:space:]]*<[^,;)=]*realized_ym|<[[:space:]]*p\$anchor_date|<[[:space:]]*anchor_date'
SIGNAL_LOAD='Date[[:space:]]*<[[:space:]]*'

grep -qE "$OVERLAY_CODE" "$FILE_PATH" 2>/dev/null || { echo '{}'; exit 0; }   # 오버레이 코드 아니면 skip

HAS_ANTI=$(grep -cE "$ANTIPATTERN" "$FILE_PATH" 2>/dev/null | tr -dc '0-9'); HAS_ANTI=${HAS_ANTI:-0}
HAS_GUARD=$(grep -cE 'overlay_pit_guard' "$FILE_PATH" 2>/dev/null | tr -dc '0-9'); HAS_GUARD=${HAS_GUARD:-0}
HAS_SIGLOAD=$(grep -cE "$SIGNAL_LOAD" "$FILE_PATH" 2>/dev/null | tr -dc '0-9'); HAS_SIGLOAD=${HAS_SIGLOAD:-0}

if [ "${HAS_ANTI:-0}" -ge 1 ] 2>/dev/null; then
  echo "[$TS] ★OVERLAY PIT LOOK-AHEAD 의심 (강) — $FILE_PATH" >> "$LOG"
  echo "[$TS]   Date<anchor_date/realized_ym = 라벨date를 신호 컷오프로 사용 = 홀딩월 말 정보(동월 누출)." >> "$LOG"
  echo "[$TS]   → 신호 컷오프는 first-day-of-holding-month. overlay_pit_guard::assert_overlay_pit + lag1 + strict-PIT A/B 의무." >> "$LOG"
  echo "[$TS]   ref: pit.md C5 §오버레이 신호 타이밍 / 02_Infrastructure/validation/overlay_pit_guard.R" >> "$LOG"
elif [ "${HAS_SIGLOAD:-0}" -ge 1 ] 2>/dev/null && [ "${HAS_GUARD:-0}" -eq 0 ] 2>/dev/null; then
  echo "[$TS] ⚠️  OVERLAY 신호 로드하나 overlay_pit_guard 미소스 (soft) — $FILE_PATH" >> "$LOG"
  echo "[$TS]   → source(02_Infrastructure/validation/overlay_pit_guard.R) + assert_overlay_pit + lag1/strict-A/B 권장." >> "$LOG"
fi

echo '{}'
exit 0
