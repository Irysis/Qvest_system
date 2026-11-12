#!/usr/bin/env bash
# P1R03 측정 — 11-10 자료로 지금(도훈 11-13 지시 "11/10 데이터만 가지고 1계층 리서치 계속 진행해" · 결정 MEASURE-P1R03-ON-1110-DATA-20261113)
#   round.sh measure 와 같은 절차에서 신선도 단계 한 줄만 뺀다.
#     정본 round.sh 를 읽어 그 한 줄(측정 분기의 fresh-check → 종료 6)만 지운 사본을 .cache/round_core/ 에 만들고,
#     사본과 정본의 차이가 정확히 그 한 줄(지움 1 · 더함 0)인지 단정한 뒤 사본으로 measure --now 를 돈다.
#     배리어 · 핀 사전 점검 · 칸 지문(시작 · 끝) · 묶음 재측정 · 평가 연쇄는 정본 그대로다. 코어 파일은 건드리지 않는다(핀 불변).
#   왜 판정에 닿지 않나: P1 자격 규칙은 보는 창(≤ 2022-12-31) 열만 쓴다. 빠진 거래일(11-11 · 11-12)은 시험 창 끝(보고 전용)이다.
#   측정 앞뒤 결합용 뷰 지문 대조 · 끝나면 이정표 1통(measured). 상태 = 새벽 셸과 같은 파일(.cache/scheduler_logs/p1r03_dawn_measure_state.txt).
#   종료: 0 끝 · 1 measure 실패 · 6 메모리 대기 상한 · 7 측정 중 뷰 바뀜 · 8 사본 단정 실패.
main() {
  set -u
  local ROOTP=/c/Users/99922/OneDrive/Quant_Module_Moltbot; cd "$ROOTP" || exit 2
  local RD=04_Research/programs/P1_RETURN/P1R03_factor_family_composites RS=04_Research/programs/_lib/round_core/round.sh
  local FPS=04_Research/programs/_lib/round_core/v3/fingerprint.sh MS=04_Research/programs/P1_RETURN/P1R03_factor_family_composites/tools/p1r03_milestone.R
  local LOG=.cache/scheduler_logs/p1r03_measure_1110_$(date +%Y%m%d_%H%M%S).log ST=.cache/scheduler_logs/p1r03_dawn_measure_state.txt
  local SEED_ST=.cache/scheduler_logs/p1s02_seed_watch_state.txt CP=.cache/round_core/round_nofresh_p1r03.sh T0=$(date +%s)
  local nd na mg v0 v1 rc
  log() { printf '%s %s\n' "$(date '+%F %T')" "$*" >> "$LOG"; }
  st() { printf '%s\t%s\tlog=%s\n' "$(date '+%F %T')" "$*" "$LOG" > "$ST"; }
  ms() { timeout 300 Rscript "$MS" "$@" >> "$LOG" 2>&1 || log "이정표 발송 rc=$?"; }
  mkdir -p .cache/round_core
  grep -vF 'Rscript "$DRV" "$RD" fresh-check ||' "$RS" > "$CP"
  nd=$(diff "$RS" "$CP" | grep -c '^<'); na=$(diff "$RS" "$CP" | grep -c '^>')
  if [ "$nd" != "1" ] || [ "$na" != "0" ]; then log "사본 단정 실패(지움 $nd · 더함 $na)"; st "사본 단정 실패 — 세션 확인"; exit 8; fi
  log "사본 $CP — 정본 대비 지움 1(측정 분기 fresh-check) · 더함 0 · 정본 md5 $(md5sum "$RS" | cut -c1-8)"
  while :; do   # 메모리(셀 워커 정점 7.45 GB · 11-03 실측) · 판 2 시드 측정 중 아님 — 최대 60분 기다린다
    mg=$(timeout 90 powershell.exe -NoProfile -NonInteractive -Command "[math]::Floor((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory/1MB)" 2>/dev/null | tr -d '\r\n ')
    if { [ -n "$mg" ] && [ "$mg" -ge 10 ]; } 2>/dev/null && ! grep -qE "M 측정 중|W\(follow\)|W 대기\(P1S02_E3_RX0\)" "$SEED_ST" 2>/dev/null; then break; fi
    [ $(( $(date +%s) - T0 )) -gt 3600 ] && { log "메모리 · 시드 대기 상한(가용 ${mg:-?}GB)"; st "대기 상한 — 세션 확인"; exit 6; }
    st "대기 — 가용 메모리 ${mg:-?}GB 또는 시드 측정 중"; sleep 120
  done
  v0=$(bash "$FPS" record .cache/factor_combinable 2>/dev/null)
  log "측정 시작(11-10 자료 · 가용 메모리 ${mg}GB) · 뷰 $v0"; st "측정 중 — 15칸(11-10 자료 · 도훈 11-13 지시)"
  bash "$CP" "$RD" measure --now >> "$LOG" 2>&1; rc=$?
  v1=$(bash "$FPS" record .cache/factor_combinable 2>/dev/null)
  log "measure rc=$rc · 뷰 끝 $v1"
  if [ "$rc" != "0" ]; then st "측정 실패 rc=$rc — 세션 확인"; ms failed "round.sh(신선도 단계만 뺀 사본) measure rc=$rc" "로그 $LOG"; exit 1; fi
  if [ "$v0" != "$v1" ]; then st "측정 중 결합용 뷰 바뀜 — 재측정 필요(DESIGN §8)"; ms view_changed "시작 $v0" "끝 $v1"; exit 7; fi
  ms measured "측정 · 평가 끝 — 자료 11-10 기준(도훈 11-13 지시 · 신선도 단계만 뺌 · 판정 창 ≤ 2022-12-31 무영향)" "로그 $LOG"
  st "끝 — 측정 · 평가(자료 11-10 기준) · 판정 해석 · T2 · P2 · 보고 · 닫기 = 세션"; exit 0
}
main "$@"
exit $?
