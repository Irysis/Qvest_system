#!/usr/bin/env bash
# P1R04 측정 감시 셸(2026-11-13 · 결합기 T1 · 15칸 CPU) — 세션 밖 분리 실행용. P1R03 새벽 셸(p1r03_dawn_measure.sh)을 본떴다.
#   측정 · 평가 = round_core 실행기(round.sh measure --now — 배리어 · 핀 · 신선도 · 칸 지문 · 평가 연쇄). 이 셸은 시작 조건과 지문 대조만 더한다.
#   시작 조건(모두):
#     · 시각 — 아침 체인(07:10) 앞뒤 05:55~08:00 · 밤 체인(00:03) 앞뒤 22:48~01:30 에는 시작하지 않는다(예상 소요 60분이 체인과 겹치지 않게).
#       판 2 시드 감시가 아직 일을 들고 있으면(상태 W · M) 그 낮 창 08:20~11:45 도 비운다(메모리 — 한 번에 무거운 작업 하나).
#     · 밤/아침 체인 미실행 · 리프레시 배리어 free · 판 2 시드 측정 중 아님 · 가용 메모리 ≥ 10 GB(셀 워커 정점 7.45 GB · 11-03 실측)
#     · fresh-check 신선 · 결합용 뷰 마지막 달 ≥ 팩터 DB 마지막 달
#     · 데이터 지문(equality + 결합용 뷰 record + IC 원장 md5)이 10분 이상 그대로 — 결합용 뷰는 칸 지문 밖 · IC 원장은 칸 지문 안이지만 기저 캐시 키 밖(T1 엔진의 두 입력).
#   예상 소요 근거: P1R03 실측 칸당 2.5~3.6분(11-13 06:43~07:28 · 15칸 45분) · 30칸(T1 15 + T0 기준 15) + T1 의 달마다 IC 접근자 호출(T1 토탈 48달 7초 실측) → 약 90분.
#   끝나면: 측정 앞뒤 뷰 · IC 원장 지문이 같으면 저위험 몫 사이드카(tools/p1r04_lowrisk_share.R) → 계보 짝 읽기(tools/p1r04_pair_reading.R) → 이정표 1통
#     (푸시 · 기계 판정 요약 '해석 전'). 판정 해석 · 판단 T2 · 철학 P2 · 정식 보고 · 닫기는 세션.
#   종료: 0 끝 · 1 measure 실패 · 6 대기 상한(기본 40시간) · 7 측정 중 뷰 · IC 원장 바뀜(재측정 — 기저 캐시까지 비운다 · DESIGN §8) · 8 시작 시한 지남.
#   환경 조정(11-14 · 원 세션 조율 — D1 뒤 같은 밤 재측정 · E2 는 캐시 채우기만 하고 판정은 내일 재측정분이라 함께 돌려도 된다):
#     P1R04_MIN_FREE_GB(기본 10) · P1R04_IGNORE_SEED=1(판 2 시드 측정 중 · 시드 낮 창 조건을 건너뜀) · P1R04_PAR(기본 2 → round.sh --p · 엔진 묶음마다 칸 1개라 사실상 순차)
#     P1R04_LATEST_START=HH:MM(그 시각이 지나도 조건이 안 서면 시작하지 않고 끝낸다 — 23:30 전 끝 · 칸 30 × 2.2~3.0분(11-13 실측) + 평가 · 사이드카 ≈ 100분).
#     P1R04_EARLIEST_START='YYYY-MM-DD HH:MM'(그 전에는 시작하지 않는다) · P1R04_MORNING_END=HH:MM(아침 체인 앞뒤 창의 끝 · 기본 08:00 — 원 세션 권고 '아침 체인 뒤 07:30' ·
#       아침 체인 실행 중 판독(Qvest_MorningBrief Running)은 그대로 막는다). 두 시각 모두 date -d 판독 · 둘 다 띄운 시점 기준 절대 시각.
#     P1R04_WAIT_VINTAGE_NOT=<판 표식 id>(06_Registry/factor_db_vintage.json 마지막 항목 id 가 이 값인 동안 시작하지 않는다 — D1 줄을 기다릴 때 · 판독 불가 = 대기).
main() {
  set -u
  local ROOTP=/c/Users/99922/OneDrive/Quant_Module_Moltbot; cd "$ROOTP" || exit 2
  local RD=04_Research/programs/P1_RETURN/P1R04_combiner_t1_icw RS=04_Research/programs/_lib/round_core/round.sh
  local FPS=04_Research/programs/_lib/round_core/v3/fingerprint.sh MS=04_Research/programs/P1_RETURN/P1R04_combiner_t1_icw/tools/p1r04_milestone.R
  local LRS=04_Research/programs/P1_RETURN/P1R04_combiner_t1_icw/tools/p1r04_lowrisk_share.R PRD=04_Research/programs/P1_RETURN/P1R04_combiner_t1_icw/tools/p1r04_pair_reading.R
  local ICL=.cache/factor_db/factor_ic_monthly.parquet
  local LOG=.cache/scheduler_logs/p1r04_measure_$(date +%Y%m%d_%H%M%S).log ST=.cache/scheduler_logs/p1r04_measure_state.txt
  local SEED_ST=.cache/scheduler_logs/p1s02_seed_watch_state.txt MAXW=${P1R04_MAX_WAIT_S:-144000} T0=$(date +%s) last=0
  local MINFREE=${P1R04_MIN_FREE_GB:-10} IGSEED=${P1R04_IGNORE_SEED:-0} PAR=${P1R04_PAR:-2} LATEST=${P1R04_LATEST_START:-} late=""
  if [ -n "$LATEST" ]; then late=$(date -d "$LATEST" +%s 2>/dev/null) || { echo "P1R04_LATEST_START 판독 불가: $LATEST" >&2; exit 2; }; fi   # 오늘 그 시각(띄운 날 기준 · 자정을 넘겨 다시 열리지 않게 절대 시각)
  local EARLY=${P1R04_EARLIEST_START:-} early="" MEND=${P1R04_MORNING_END:-08:00} mendm
  if [ -n "$EARLY" ]; then early=$(date -d "$EARLY" +%s 2>/dev/null) || { echo "P1R04_EARLIEST_START 판독 불가: $EARLY" >&2; exit 2; }; fi
  mendm=$((10#${MEND%%:*} * 60 + 10#${MEND##*:})) || exit 2
  local VNOT=${P1R04_WAIT_VINTAGE_NOT:-} vlast
  vtail() { timeout 60 python -c "import json;print(json.load(open('06_Registry/factor_db_vintage.json',encoding='utf-8'))['entries'][-1]['id'])" 2>/dev/null | tr -d '\r\n'; }
  local why nowm mg rc fp fp_prev="" fp_t=0 vl dl v0 v1 prl
  log() { printf '%s %s\n' "$(date '+%F %T')" "$*" >> "$LOG"; }
  st() { printf '%s\t%s\tlog=%s\n' "$(date '+%F %T')" "$*" "$LOG" > "$ST"; }
  running() { local s; s=$(timeout 90 powershell.exe -NoProfile -NonInteractive -Command "(Get-ScheduledTask -TaskName '$1').State" 2>/dev/null | tr -d '\r\n ')
    [ -z "$s" ] && return 0; [ "$s" = "Running" ]; }   # 판독 실패 = 실행 중으로 본다(닫힘)
  inpfp() { { bash "$FPS" record .cache/factor_combinable; md5sum "$ICL" | cut -c1-32; } 2>/dev/null | md5sum | cut -c1-32; }
  fpnow() { { bash "$FPS" equality; inpfp; } 2>/dev/null | md5sum | cut -c1-32; }
  ms() { timeout 300 Rscript "$MS" "$@" >> "$LOG" 2>&1 || log "이정표 발송 rc=$?"; }
  log "시작 · pid $$ · 체인 앞뒤 · 시드 창(시드 일 남았을 때 · 건너뜀=${IGSEED}) 제외 · 메모리 ≥ ${MINFREE} GB · 병렬 ${PAR} · 시작 시한 ${LATEST:-없음} · 이른 시작 ${EARLY:-없음} · 아침 창 끝 ${MEND} · 판 표식 대기 ${VNOT:-없음} · 지문(뷰 + IC 원장 포함) 10분 안정 · 뷰 마지막 달 ≥ 팩터 DB"; st "대기 — 시작"
  while :; do
    [ $(( $(date +%s) - T0 )) -gt "$MAXW" ] && { log "대기 상한"; st "대기 상한 — 끝"; exit 6; }
    why=""; nowm=$((10#$(date +%H) * 60 + 10#$(date +%M)))
    [ -n "$late" ] && [ "$(date +%s)" -gt "$late" ] && { log "시작 시한 ${LATEST} 지남 — 측정하지 않고 끝"; st "시작 시한 ${LATEST} 지남 — 끝(세션이 다음 창을 잡는다)"; exit 8; }
    [ -n "$early" ] && [ "$(date +%s)" -lt "$early" ] && why="시작 전 시각(${EARLY})"
    if [ -z "$why" ] && [ -n "$VNOT" ]; then vlast=$(vtail); { [ -n "$vlast" ] && [ "$vlast" != "$VNOT" ]; } || why="판 표식 대기(마지막 줄 ${vlast:-판독 불가})"; fi
    [ -z "$why" ] && [ "$nowm" -ge 355 ] && [ "$nowm" -lt "$mendm" ] && why="아침 체인 앞뒤(${nowm}분)"
    { [ "$nowm" -ge 1368 ] || [ "$nowm" -lt 90 ]; } && why="밤 체인 앞뒤(${nowm}분)"
    [ -z "$why" ] && [ "$IGSEED" != "1" ] && [ "$nowm" -ge 500 ] && [ "$nowm" -le 705 ] && grep -qE $'\t''(W|M)[ :(]' "$SEED_ST" 2>/dev/null && why="판 2 시드 낮 창(시드 일 남음 · ${nowm}분)"
    [ -z "$why" ] && running Qvest_DailyRefresh && why="밤 체인 실행 중"
    [ -z "$why" ] && running Qvest_MorningBrief && why="아침 체인 실행 중"
    [ -z "$why" ] && { bash 02_Infrastructure/ops/refresh_barrier.sh status 2>/dev/null | grep -q "state=free" || why="리프레시 배리어 held"; }
    [ -z "$why" ] && [ "$IGSEED" != "1" ] && grep -qE "M 측정 중|W\(follow\)|W 대기\(P1S02_E3_RX0\)" "$SEED_ST" 2>/dev/null && why="판 2 시드 측정 중 · E3 직후 대기"
    if [ -z "$why" ]; then mg=$(timeout 90 powershell.exe -NoProfile -NonInteractive -Command "[math]::Floor((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory/1MB)" 2>/dev/null | tr -d '\r\n ')
      { [ -n "$mg" ] && [ "$mg" -ge "$MINFREE" ]; } 2>/dev/null || why="가용 메모리 ${mg:-?}GB < ${MINFREE}GB"; fi
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
    if [ -z "$why" ]; then
      v0=$(inpfp); log "조건 서면 — measure(--now) 시작 · 입력(뷰 + IC 원장) ${v0} · 가용 메모리 ${mg}GB"; st "측정 중 — 30칸"
      bash "$RS" "$RD" measure --now --p="$PAR" >> "$LOG" 2>&1; rc=$?
      v1=$(inpfp); log "measure rc=$rc · 입력 끝 ${v1}"
      if [ "$rc" != "0" ]; then st "측정 실패 rc=$rc — 세션 확인"; ms failed "측정 실행 실패(종료 코드 $rc)" "로그 $LOG"; exit 1; fi
      if [ "$v0" != "$v1" ]; then st "측정 중 결합용 뷰 · IC 원장 바뀜 — 재측정 필요(세션)"; ms input_changed "측정 중 입력 데이터(팩터 점수 · 정보계수 이력)가 바뀌어 재측정이 필요하다" "로그 $LOG"; exit 7; fi
      ( cd 04_Research/strategies && timeout 1800 Rscript "$ROOTP/$LRS" "$RD" ) >> "$LOG" 2>&1 || log "저위험 몫 사이드카 rc=$?"
      prl=$( cd 04_Research/strategies && timeout 1800 Rscript "$ROOTP/$PRD" "$RD" 2>> "$LOG" | tail -n 1 ); log "짝 읽기: ${prl:-실패}"
      if [ -n "$prl" ]; then ms measured "측정 · 평가 완료(IS 판정 · 결합 개선 판정까지)"; else ms measured "측정 · 평가 완료" "결합 개선 판정 도구 실패 — 세션 확인"; fi
      st "끝 — 측정 · 평가(판정 해석 · 판단 T2 · 철학 P2 · 보고 · 닫기 = 세션)"; exit 0
    fi
    [ $(( $(date +%s) - last )) -ge 900 ] && { log "대기 — $why"; st "대기 — $why"; last=$(date +%s); }
    sleep 120
  done
}
main "$@"
exit $?
