#!/usr/bin/env bash
# 판 2(P1S02) 진행 상황 텔레그램 주기 보고 — 반복 셸(도훈 11-12 "텔레 주기적으로 보내" · 세션 밖 분리 실행용)
#   INTERVAL_S(기본 1800초)마다 p1s02_tg_progress.R 1회(상태가 바뀌었거나 HEARTBEAT(기본 2시간)가 지났을 때만 실제로 보낸다).
#   끝: R 이 10 으로 끝나면(시드 판정이 모두 끝나 마지막 1통을 보냈다) · 마감(기본 시작 + 60시간 → 마지막 1통) · 잠금 폴더에 stop 파일.
#   한 번에 하나: 잠금 폴더 .cache/p1s02_tg_progress.lock(pid) — 살아 있는 보유자가 있으면 그냥 끝난다.
#   측정 · 판정 · 원장 · 등록부 · 저널에 손대지 않는다(읽기 + 발송 + 상태 파일 하나).
# 띄우기(세션 밖 · 세션이 닫혀도 산다): powershell Invoke-CimMethod Win32_Process Create
#   "C:\Program Files\Git\bin\bash.exe" "C:/Users/99922/OneDrive/Quant_Module_Moltbot/04_Research/programs/_lib/detached_env.sh" <이 파일> <로그>
# 끄기: touch .cache/p1s02_tg_progress.lock/stop (다음 주기에 마지막 1통을 보내고 끝난다)
main() {
  local ROOTP=/c/Users/99922/OneDrive/Quant_Module_Moltbot
  cd "$ROOTP" || exit 2
  local HERE=04_Research/01_reports/portfolio_paper_layer_split_20261112/ops
  local INTERVAL_S=${P1S02_TG_INTERVAL_S:-1800} HOURS=${P1S02_TG_HOURS:-60}
  local DEADLINE=$(( $(date +%s) + HOURS * 3600 ))
  local LOCK=.cache/p1s02_tg_progress.lock LOG=.cache/scheduler_logs/p1s02_tg_progress.log rc op
  mkdir -p .cache/scheduler_logs
  if ! mkdir "$LOCK" 2>/dev/null; then
    op=$(cat "$LOCK/pid" 2>/dev/null)
    if [ -n "$op" ] && kill -0 "$op" 2>/dev/null; then echo "$(date '+%F %T') 이미 돈다(pid $op) — 끝" >> "$LOG"; exit 0; fi
    rm -rf "$LOCK"; mkdir "$LOCK" || exit 2
  fi
  echo $$ > "$LOCK/pid"
  trap 'rm -rf "$LOCK"' EXIT
  echo "$(date '+%F %T') 시작 · pid $$ · 주기 ${INTERVAL_S}s · 마감 ${HOURS}시간" >> "$LOG"
  while :; do
    if [ -e "$LOCK/stop" ]; then
      Rscript "$HERE/p1s02_tg_progress.R" --final "주기 보고를 껐다(stop 파일)" >> "$LOG" 2>&1
      echo "$(date '+%F %T') stop 파일 — 끝" >> "$LOG"; exit 0
    fi
    Rscript "$HERE/p1s02_tg_progress.R" >> "$LOG" 2>&1; rc=$?
    if [ "$rc" = "10" ]; then echo "$(date '+%F %T') 시드 판정 끝 · 마지막 보고 — 끝" >> "$LOG"; exit 0; fi
    if [ "$rc" != "0" ]; then echo "$(date '+%F %T') 1회분 rc=$rc(다음 주기에 다시)" >> "$LOG"; fi
    if [ "$(date +%s)" -ge "$DEADLINE" ]; then
      Rscript "$HERE/p1s02_tg_progress.R" --final "마감(${HOURS}시간) — 주기 보고 끝 · 남은 일은 세션이 이어 간다" >> "$LOG" 2>&1
      echo "$(date '+%F %T') 마감 — 끝" >> "$LOG"; exit 0
    fi
    sleep "$INTERVAL_S"
  done
}
main "$@"
exit $?
