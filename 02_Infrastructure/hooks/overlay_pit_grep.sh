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

# ── 빠른 길 (WP4 2026-10-20 · 훅 지연 — 탐지 의미 불변) ────────────────────────────
# 증명: 이 훅은 출력이 항상 '{}' 이고, 부수효과(경보 로그)는 FILE_PATH 가 `\.R$`(grep 줄 의미 — MSYS grep 은
#   줄 끝 CR 앞에서도 `$` 가 걸린다: 실측 'x.R\r\r\n' 일치)에 걸린 뒤에만 생긴다. FILE_PATH 는 원문의
#   "file_path":"…" 따옴표 안 부분 문자열(해독 없음 · 닫는 따옴표 직전까지)이다 → `.R` 로(뒤에 CR 이 붙어도)
#   끝나려면 원문에 '.R"' 또는 '.R'+CR 이 있어야 한다. 둘 다 없으면 원래 경로도 로그 없이 '{}' 로 끝난다.
# 끄기: QVEST_HOOK_FASTPATH=0 (검사 08_Tests/hooks/test_hook_fastpath_equivalence.sh)
if [ "${QVEST_HOOK_FASTPATH:-1}" != "0" ]; then
  case "$INPUT" in
    *'.R"'*|*.R$'\r'*) : ;;
    *) echo '{}'; exit 0 ;;
  esac
fi

LOG="/tmp/overlay_pit_grep.log"
# (WP4 2026-10-20) 시각은 경보를 쓸 때만 잰다(아래 _ts) — 경보 없는 .R 편집마다 date 프로세스 1회를 쓰던 자리.
_ts() { TS="$(date '+%Y-%m-%d %H:%M:%S')"; }

[ "${QVEST_SKIP_OVERLAY_PIT:-0}" = "1" ] && { echo '{}'; exit 0; }

# (WP4 2026-10-20) FILE_PATH 추출 · .R 판정을 프로세스 없이 — 바이트 단위 로케일(C/POSIX · 미설정)이고 원문에 CR 이 없을 때만.
#   등가 근거: 구판 = echo | grep -oE | head -1 | sed. grep 은 줄 단위라 일치가 줄을 넘지 못하고([[:space:]] 는 줄 안에서
#   공백·탭·VT·FF·CR — CR 없음 전제로 [ \t\v\f]), 첫 줄의 첫(leftmost) 일치를 head 가 집는다 = 전체 문자열에서 줄을 넘지 않는
#   leftmost 일치(아래 정규식 — [^"\n] · [ \t\v\f] 로 줄 넘김을 막았다). 일치 길이는 시작점이 정하면 유일하다(닫는 따옴표까지).
#   sed 는 그 일치에서 따옴표 안을 꺼낸다 = BASH_REMATCH[1]. .R 판정: CR·LF 없는 값에서 grep '\.R$' ⟺ '.R' 로 끝남.
#   CR 이 있거나(MSYS grep 은 CR 을 줄 끝처럼 다룬다 — 실측) 멀티바이트 로케일이면 구판 파이프라인을 그대로 탄다.
_opg_bytewise() { case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in ""|C|POSIX) return 0 ;; *) return 1 ;; esac; }
if [ "${QVEST_HOOK_FASTPATH:-1}" != "0" ] && _opg_bytewise && [[ $INPUT != *$'\r'* ]]; then
  _opg_re=$'"file_path"[ \t\v\f]*:[ \t\v\f]*"([^"\n]*)"'
  if [[ $INPUT =~ $_opg_re ]]; then FILE_PATH="${BASH_REMATCH[1]}"; else FILE_PATH=""; fi
  [ -z "$FILE_PATH" ] && { echo '{}'; exit 0; }
  [ ! -f "$FILE_PATH" ] && { echo '{}'; exit 0; }
  case "$FILE_PATH" in *.R) : ;; *) echo '{}'; exit 0 ;; esac
else
FILE_PATH=$(echo "$INPUT" | grep -oE '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
[ -z "$FILE_PATH" ] && { echo '{}'; exit 0; }
[ ! -f "$FILE_PATH" ] && { echo '{}'; exit 0; }
# .R 파일만
echo "$FILE_PATH" | grep -qE '\.R$' || { echo '{}'; exit 0; }
fi

OVERLAY_CODE='apply_gate|beta_R05|beta_bear|m4[[:space:]]*\*[[:space:]]*ret_orig|ret_orig[[:space:]]*\*|[^a-z]gate\(|Bear_Prob|regime_jump|오버레이|overlay_beta|beta_total'
ANTIPATTERN='Date[[:space:]]*<[^,;)=]*anchor_date|Date[[:space:]]*<[^,;)=]*realized_ym|<[[:space:]]*p\$anchor_date|<[[:space:]]*anchor_date'
SIGNAL_LOAD='Date[[:space:]]*<[[:space:]]*'

grep -qE "$OVERLAY_CODE" "$FILE_PATH" 2>/dev/null || { echo '{}'; exit 0; }   # 오버레이 코드 아니면 skip

# (WP4 2026-10-20) `| tr -dc '0-9'` → 파라미터 확장 `${x//[!0-9]/}`(같은 숫자만 남기기 · globasciiranges 기본).
#   파이프가 사라지면 대입의 종료 코드가 grep 의 것(0건이면 1)이 되어 ERR trap 이 조기 종료시킨다 —
#   `|| true` 가 구판의 '파이프 끝 = tr 의 0' 을 대신한다. 프로세스 3쌍(서브셸·tr)을 덜 쓴다.
HAS_ANTI=$(grep -cE "$ANTIPATTERN" "$FILE_PATH" 2>/dev/null) || true; HAS_ANTI=${HAS_ANTI//[!0-9]/}; HAS_ANTI=${HAS_ANTI:-0}
HAS_GUARD=$(grep -cE 'overlay_pit_guard' "$FILE_PATH" 2>/dev/null) || true; HAS_GUARD=${HAS_GUARD//[!0-9]/}; HAS_GUARD=${HAS_GUARD:-0}
HAS_SIGLOAD=$(grep -cE "$SIGNAL_LOAD" "$FILE_PATH" 2>/dev/null) || true; HAS_SIGLOAD=${HAS_SIGLOAD//[!0-9]/}; HAS_SIGLOAD=${HAS_SIGLOAD:-0}

if [ "${HAS_ANTI:-0}" -ge 1 ] 2>/dev/null; then
  _ts
  echo "[$TS] ★OVERLAY PIT LOOK-AHEAD 의심 (강) — $FILE_PATH" >> "$LOG"
  echo "[$TS]   Date<anchor_date/realized_ym = 라벨date를 신호 컷오프로 사용 = 홀딩월 말 정보(동월 누출)." >> "$LOG"
  echo "[$TS]   → 신호 컷오프는 first-day-of-holding-month. overlay_pit_guard::assert_overlay_pit + lag1 + strict-PIT A/B 의무." >> "$LOG"
  echo "[$TS]   ref: pit.md C5 §오버레이 신호 타이밍 / 02_Infrastructure/validation/overlay_pit_guard.R" >> "$LOG"
elif [ "${HAS_SIGLOAD:-0}" -ge 1 ] 2>/dev/null && [ "${HAS_GUARD:-0}" -eq 0 ] 2>/dev/null; then
  _ts
  echo "[$TS] ⚠️  OVERLAY 신호 로드하나 overlay_pit_guard 미소스 (soft) — $FILE_PATH" >> "$LOG"
  echo "[$TS]   → source(02_Infrastructure/validation/overlay_pit_guard.R) + assert_overlay_pit + lag1/strict-A/B 권장." >> "$LOG"
fi

echo '{}'
exit 0
