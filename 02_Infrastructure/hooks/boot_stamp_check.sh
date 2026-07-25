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

# ── 훅 집행 무결성 (2026-07-25 next_probe ②) ───────────────────────────────
# bootstrap 배선만으로는 /qvest 를 돌린 세션에서만 찍힌다 — worktree 를 만들고 바로
# 작업하면 라우터가 빠진 채로 진행될 수 있다(dispatch 18훅 무발화 = 게이트급 다수).
# SessionStart 는 모든 세션에서 발화하므로 여기서 열화만 경고한다(정상이면 침묵).
# 도구 탐색도 폴백한다 — 진단이 가장 필요한 트리(아직 main 을 병합 안 한 worktree)에
# 정작 도구가 없어 침묵하는 자기모순을 막는다(실측: worktree 에서 스킵됨).
HIC="$DIR/02_Infrastructure/ops/hook_integrity_check.sh"
if [ ! -f "$HIC" ]; then
  _QMR="${QM_ROOT:-}"; _QMR="${_QMR//\\//}"
  [ -n "$_QMR" ] && HIC="$_QMR/02_Infrastructure/ops/hook_integrity_check.sh"
fi
# ★감시의 감시(next_probe ④): 이 호출부는 '정상=침묵'이 설계라, 도구가 사라지거나
#   무출력이어도 침묵과 구분되지 않는다 — 감시가 조용히 없어지는 바로 그 형태다.
#   부재·무출력을 명시 경고로 분리한다(둘 다 드물어야 정상이므로 노이즈가 아니다).
if [ ! -f "$HIC" ]; then
  MSG="${MSG:+$MSG }[hook-integrity] 감시 도구 부재 — 훅 집행 상태를 확인할 수 없습니다(main 병합 또는 도구 복구 필요)."
else
  HIC_OUT=$(bash "$HIC" 2>&1) || true
  if [ -z "$HIC_OUT" ]; then
    MSG="${MSG:+$MSG }[hook-integrity] 감시 도구 무출력 — 정상이면 항상 1줄 이상 출력합니다(도구 이상)."
  fi
  case "$HIC_OUT" in
    *"ROUTER 열화"*)
      HL=$(printf '%s' "$HIC_OUT" | head -1)
      MSG="${MSG:+$MSG }[hook-integrity] $HL — 이 세션은 게이트 다수가 무발화 상태입니다. QM_ROOT/QVEST_PY 확인 또는 /qvest 실행."
      ;;
    *"폴백이 없습니다"*)
      MSG="${MSG:+$MSG }[hook-integrity] 이 트리 settings.json 에 worktree 폴백 미적용 — main 병합 권장(현재 라우터는 env 덕에 동작 중)."
      ;;
  esac
fi

if [ -n "$MSG" ]; then
  ESC=$(printf '%s' "$MSG" | sed 's/\\/\\\\/g; s/"/\\"/g')
  echo "{\"hookSpecificOutput\":{\"hookEventName\":\"SessionStart\",\"additionalContext\":\"$ESC\"}}"
else
  echo "{}"
fi
exit 0
