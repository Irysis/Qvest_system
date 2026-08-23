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

# ── 훅 집행 무결성 호출 제거 (v9 Lean Loop, 2026-08-23) ─────────────────────
# 구판(2026-07-25 next_probe ②)은 여기서 ops/hook_integrity_check.sh 를 매 세션 호출해
# 라우터 열화·worktree 폴백 미적용을 경고했다. v9 에서 라우터 dispatch 가 폐지되고
# 자본·안전 게이트가 settings.json 에 직접 등록되면서, 그 진단은 판정 대상이 없어졌다 —
# 남겨두면 폴백 문자열('QM_ROOT//')이 사라진 새 settings.json 을 읽고 매 세션마다
# "worktree 폴백 미적용" 이라는 **거짓 경고**를 주입한다(v8 라우터 command 전용 지문).
# 훅 등록 상태 점검은 주간 health_full.sh / boot_currency_check.sh C6 로 이관한다.
# 되살릴 때는 hook_integrity_check.sh 의 폴백 판정부터 v9 등록 형태로 고칠 것.

if [ -n "$MSG" ]; then
  ESC=$(printf '%s' "$MSG" | sed 's/\\/\\\\/g; s/"/\\"/g')
  echo "{\"hookSpecificOutput\":{\"hookEventName\":\"SessionStart\",\"additionalContext\":\"$ESC\"}}"
else
  echo "{}"
fi
exit 0
