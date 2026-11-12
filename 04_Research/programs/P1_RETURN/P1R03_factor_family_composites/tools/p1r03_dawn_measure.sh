#!/usr/bin/env bash
# P1R03 새벽 측정 감시 셸(2026-11-12 · 도훈 D6 재결정 FACTOR-SPINE-D6-REVISE-20261112 '지금 등록 · 새벽 측정') — 세션 밖 분리 실행용.
#   자체 사양 엔진 15칸(CPU)을 자료가 신선해지는 대로 잰다. 측정 · 평가는 round_core 실행기(round.sh measure — 배리어 · 핀 · 신선도 · 칸 지문 · 평가 연쇄).
#   시작 조건(모두):
#     · 시작 창 04:30~06:00 · 18:00~22:00 — 예상 소요(아래)가 07:10 아침 체인 · 00:03 밤 체인 전에 끝나게. 낮(06:00~18:00) = 판 2 시드 창이라 비운다(격리 점검 v1 R-2).
#     · 밤/아침 체인 미실행 · 리프레시 배리어 free · 판 2 시드 감시 셸이 측정 중(M) 아님 · 가용 메모리 ≥ 10 GB(셀 워커 정점 7.45 GB · 11-03 실측)
#     · fresh-check 신선 · 결합용 뷰 마지막 달 ≥ 팩터 DB 마지막 달(뷰만 늦는 경우를 막는다 — 판단 T1 C-20261112-032 · 뷰는 칸 지문 · fresh-check 밖)
#     · 데이터 지문(equality + 결합용 뷰 record)이 10분 이상 그대로(점검 v1 R-3).
#   예상 소요 근거: 리허설 셀 워커 1.6분/칸(P1S02 rehearsal run 20261112_212912) + 결합용 뷰 월 읽기 0.15초 × 323달(11-12 23:2x 실측)
#     → 칸당 2.5~4분 × 15칸 = 40~60분(엔진마다 칸 1개 · 실행기는 엔진 묶음을 차례로 잰다 — --p 는 이 라운드에서 효과 없음).
#   끝나면: 측정 앞뒤 결합용 뷰 지문이 같으면 이정표 1통(푸시 · 측정 · 평가 끝 · 기계 판정 요약). 판정 보고(철학 P2 · 판단 T2 포함)는 세션이 낸다(점검 v1 R-4).
#     뷰가 바뀌었으면 상태 = 재측정 필요 · 이정표 1통(종료 7).
#   06:00 새벽 창이 시작 없이 닫히면(낡음 · 배리어 · 메모리 등 마지막 사유) 이정표 1통(푸시 · 07:10 아침 체인 자가 복구 · 다음 창 18:00 — 판단 T1 C-20261112-028) — 하루 1통.
#   종료: 0 = 측정 · 평가 끝 · 1 = measure 실패 · 6 = 대기 상한(기본 40시간) · 7 = 측정 중 결합용 뷰 바뀜.
main() {
  set -u
  local ROOTP=/c/Users/99922/OneDrive/Quant_Module_Moltbot; cd "$ROOTP" || exit 2
  local RD=04_Research/programs/P1_RETURN/P1R03_factor_family_composites RS=04_Research/programs/_lib/round_core/round.sh
  local FPS=04_Research/programs/_lib/round_core/v3/fingerprint.sh MS=04_Research/programs/P1_RETURN/P1R03_factor_family_composites/tools/p1r03_milestone.R
  local LOG=.cache/scheduler_logs/p1r03_dawn_measure_$(date +%Y%m%d_%H%M%S).log ST=.cache/scheduler_logs/p1r03_dawn_measure_state.txt
  local SEED_ST=.cache/scheduler_logs/p1s02_seed_watch_state.txt MAXW=${P1R03_MAX_WAIT_S:-144000} T0=$(date +%s) last=0
  local why nowm mg rc fp fp_prev="" fp_t=0 stale_day="" last_why="" vl dl v0 v1
  log() { printf '%s %s\n' "$(date '+%F %T')" "$*" >> "$LOG"; }
  st() { printf '%s\t%s\tlog=%s\n' "$(date '+%F %T')" "$*" "$LOG" > "$ST"; }
  running() { local s; s=$(timeout 90 powershell.exe -NoProfile -NonInteractive -Command "(Get-ScheduledTask -TaskName '$1').State" 2>/dev/null | tr -d '\r\n ')
    [ -z "$s" ] && return 0; [ "$s" = "Running" ]; }   # 판독 실패 = 실행 중으로 본다(닫힘 · 격리 점검 v2 S-7)
  viewfp() { bash "$FPS" record .cache/factor_combinable 2>/dev/null; }
  fpnow() { { bash "$FPS" equality; viewfp; } 2>/dev/null | md5sum | cut -c1-32; }
  ms() { timeout 300 Rscript "$MS" "$@" >> "$LOG" 2>&1 || log "이정표 발송 rc=$?"; }
  log "시작 · pid $$ · 창 04:30~06:00 · 18:00~22:00 · 메모리 ≥ 10 GB · 지문 10분 안정 · 뷰 마지막 달 ≥ 팩터 DB"; st "대기 — 시작"
  while :; do
    [ $(( $(date +%s) - T0 )) -gt "$MAXW" ] && { log "대기 상한"; st "대기 상한 — 끝"; exit 6; }
    why=""; nowm=$((10#$(date +%H) * 60 + 10#$(date +%M)))
    { { [ "$nowm" -ge 270 ] && [ "$nowm" -le 360 ]; } || { [ "$nowm" -ge 1080 ] && [ "$nowm" -le 1320 ]; }; } || why="시각 창 밖(${nowm}분)"
    [ -z "$why" ] && running Qvest_DailyRefresh && why="밤 체인 실행 중"
    [ -z "$why" ] && running Qvest_MorningBrief && why="아침 체인 실행 중"
    [ -z "$why" ] && { bash 02_Infrastructure/ops/refresh_barrier.sh status 2>/dev/null | grep -q "state=free" || why="리프레시 배리어 held"; }
    [ -z "$why" ] && grep -qE "M 측정 중|W\(follow\)|W 대기\(P1S02_E3_RX0\)" "$SEED_ST" 2>/dev/null && why="판 2 시드 측정 중 · E3 직후 대기(메모리 · 격리 점검 v2 N-4)"
    if [ -z "$why" ]; then mg=$(timeout 90 powershell.exe -NoProfile -NonInteractive -Command "[math]::Floor((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory/1MB)" 2>/dev/null | tr -d '\r\n ')
      { [ -n "$mg" ] && [ "$mg" -ge 10 ]; } 2>/dev/null || why="가용 메모리 ${mg:-?}GB < 10GB"; fi
    [ -z "$why" ] && { bash "$RS" - fresh-check >> "$LOG" 2>&1 || why="자료 낡음(fresh-check)"; }
    if [ -z "$why" ]; then
      vl=$(grep -o '"last": *"[0-9]\{6\}"' .cache/factor_combinable/fc_meta.json 2>/dev/null | grep -o '[0-9]\{6\}' | head -1)
      dl=$(ls .cache/factor_db/ 2>/dev/null | grep -E '^factor_db_[0-9]{6}\.parquet$' | sort | tail -1 | grep -o '[0-9]\{6\}')
      { [ -n "$vl" ] && [ -n "$dl" ] && [ "$vl" -ge "$dl" ]; } || why="결합용 뷰 마지막 달 ${vl:-?} < 팩터 DB ${dl:-?}"
    fi
    if [ -z "$why" ]; then
      fp=$(fpnow)
      if [ "$fp" != "$fp_prev" ]; then fp_prev=$fp; fp_t=$(date +%s); why="데이터 지문 새로 읽음 — 10분 안정 대기"
      elif [ $(( $(date +%s) - fp_t )) -lt 600 ]; then why="데이터 지문 안정 대기($(( $(date +%s) - fp_t ))초)"; fi
    else fp_prev=""; fi
    case "$why" in "시각 창 밖"*|"") ;; *) last_why=$why ;; esac
    if [ "$nowm" -ge 361 ] && [ "$nowm" -le 390 ] && [ "$stale_day" != "$(date +%F)" ] && [ -n "$last_why" ]; then stale_day=$(date +%F)
      ms stale "06:00 새벽 시작 창 마감 — 시작 못 함 · 마지막 사유: $last_why" "자료가 낡았으면 07:10 아침 체인이 ensure_data_current 로 자가 복구를 시도한다" "P1R03 다음 시작 창 = 18:00~22:00"; last_why=""; fi
    if [ -z "$why" ]; then
      v0=$(viewfp); log "조건 서면 — measure(--now) 시작 · 뷰 ${v0}"; st "측정 중 — 15칸"
      bash "$RS" "$RD" measure --now >> "$LOG" 2>&1; rc=$?
      v1=$(viewfp); log "measure rc=$rc · 뷰 끝 ${v1}"
      if [ "$rc" != "0" ]; then st "측정 실패 rc=$rc — 세션 확인"; ms failed "round.sh measure rc=$rc" "로그 $LOG"; exit 1; fi
      if [ "$v0" != "$v1" ]; then st "측정 중 결합용 뷰 바뀜 — 재측정 필요(세션)"; ms view_changed "시작 $v0" "끝 $v1"; exit 7; fi
      ms measured "측정 · 평가 끝(round.sh measure rc 0)" "로그 $LOG"
      st "끝 — 측정 · 평가(판정 해석 · 판단 T2 · 철학 P2 · 보고 · 닫기 = 세션)"; exit 0
    fi
    [ $(( $(date +%s) - last )) -ge 900 ] && { log "대기 — $why"; st "대기 — $why"; last=$(date +%s); }
    sleep 120
  done
}
main "$@"
exit $?
