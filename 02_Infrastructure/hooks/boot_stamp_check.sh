#!/usr/bin/env bash
#==============================================================================
# boot_stamp_check.sh — SessionStart 부트 카나리아 (2026-07-17 B2)
#   bootstrap.sh 완주가 남기는 .cache/boot_stamp.json 신선도 검사.
#   스탬프 부재 또는 24h 초과 = "풀 부트스트랩 미실행 — /qvest 권장" 컨텍스트 경고.
#   warn-only (차단 아님) — 07-05 이후 12일 무부트 세션 가동 실측 대응.
#   부수: 최근 부트가 DEGRADED(boot_fails>0)였으면 미해소 게이트 알림.
#==============================================================================
trap 'echo "{}"; exit 0' ERR
# SessionStart stdin(payload) 소비 — tty 수동 실행 시 블로킹 방지
[ -t 0 ] || cat >/dev/null 2>&1 || true

DIR="${CLAUDE_PROJECT_DIR:-${QM_ROOT:-}}"
DIR="${DIR//\\//}"
if [ -z "$DIR" ] || [ ! -d "$DIR" ]; then
  DIR=$(ls -d /c/Users/99922/OneDrive/Quant_Module_Moltbot /mnt/c/Users/99922/OneDrive/Quant_Module_Moltbot /g/Quant_Module_Moltbot /mnt/g/Quant_Module_Moltbot 2>/dev/null | head -1 || echo "$PWD")
fi

STAMP="$DIR/.cache/boot_stamp.json"
NOW=$(date +%s)
MSG=""
if [ ! -f "$STAMP" ]; then
  MSG="[boot-canary] boot_stamp.json 부재 — 풀 부트스트랩 미실행. /qvest 실행 권장 (게이트/캐시/메모리 health 미검증 상태로 세션 가동 중)."
else
  ST_EPOCH=$(grep -oE '"ts_epoch"[[:space:]]*:[[:space:]]*[0-9]+' "$STAMP" 2>/dev/null | grep -oE '[0-9]+$' || true)
  [ -n "$ST_EPOCH" ] || ST_EPOCH=$(stat -c %Y "$STAMP" 2>/dev/null || echo 0)
  AGE_H=$(( (NOW - ST_EPOCH) / 3600 ))
  if [ "$AGE_H" -ge 24 ] || [ "$AGE_H" -lt 0 ]; then
    MSG="[boot-canary] 마지막 풀 부트스트랩 ${AGE_H}h 경과 (24h 초과) — /qvest 실행 권장 (boot_stamp.json stale)."
  else
    BF=$(grep -oE '"boot_fails"[[:space:]]*:[[:space:]]*[0-9]+' "$STAMP" 2>/dev/null | grep -oE '[0-9]+$' || echo 0)
    if [ "${BF:-0}" -gt 0 ]; then
      MSG="[boot-canary] 최근 부트스트랩 DEGRADED (boot_fails=${BF}, ${AGE_H}h 전) — ERROR 게이트 미해소 가능. 부트 로그 확인 또는 /qvest 재실행 권장."
    fi
  fi
fi

if [ -n "$MSG" ]; then
  ESC=$(printf '%s' "$MSG" | sed 's/\\/\\\\/g; s/"/\\"/g')
  echo "{\"hookSpecificOutput\":{\"hookEventName\":\"SessionStart\",\"additionalContext\":\"$ESC\"}}"
else
  echo "{}"
fi
exit 0
