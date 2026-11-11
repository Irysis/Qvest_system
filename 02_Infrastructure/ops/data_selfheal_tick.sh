#!/usr/bin/env bash
#==============================================================================
# data_selfheal_tick.sh — 낮 시간 데이터 자가 복구 한 틱 (2026-11-11 도훈 "자가 복구 실행되게 배선해줘")
#
# 왜: 밤 일일 체인이 퀀티 미갱신으로 실패하면, 종전에는 부팅 · 아침 브리핑에서 한 번 더 해 보고 그날은 끝이었다
#   (같은 영업일 재시도 가드). 사람이 단말을 재로그인해도 다음 밤 00:03 까지 아무도 다시 받지 않았다(11-11 실례 — 수동 재실행).
#   이 틱이 낮 동안 매시 한 번 ensure_data_current.sh 를 불러, 그 스크립트의 재시도 규칙(퀀티 미갱신 = 마지막 시도 뒤
#   자가 복구 시간 상한이 지나면 다시 · 그 밖 = 같은 영업일 재시도 안 함)대로 스스로 복구하게 한다.
#
# 호출자 = 예약 작업 Qvest_StandingBoard(매시 37분 · 실행 상한 24시간 · 상설 판 틱 앞). 상설 판 · 사슬 측정은 최신 데이터가 전제다.
# 동작:
#   ① 리프레시 배리어(refresh_barrier.sh status)가 free 일 때만 부른다 — 밤 체인 · 다른 복구가 도는 중이면 건너뛴다
#      (기다리지 않는다 · 판정 불가 = 건너뜀).
#   ② ensure_data_current.sh 를 그대로 부른다(판정 · 복구 · 보고 규칙은 거기 하나) — 이미 최신이면 수 초 no-op.
#   ③ 틱의 종료 코드는 늘 0 — 복구 실패가 뒤따르는 상설 판 틱을 막지 않는다(실패 보고는 리프레시 체인의 몫).
# 끄기: QVEST_DATA_SELFHEAL_TICK=off(한 번) · 퀀티 재시도만 끄기 = QVEST_EDC_QW_RETRY=0
# 로그 = <ROOT>/.cache/scheduler_logs/data_selfheal_tick.log(틱마다 한 줄 · 복구를 돌린 틱은 본문 꼬리 20줄)
# 시험 주입: RC_ROOT_POSIX(루트) · RB_SH(배리어 판정기) · DST_EDC(ensure_data_current 경로)
#==============================================================================
set -u
ROOT=${RC_ROOT_POSIX:-/c/Users/99922/OneDrive/Quant_Module_Moltbot}
RB=${RB_SH:-$ROOT/02_Infrastructure/ops/refresh_barrier.sh}
EDC=${DST_EDC:-$ROOT/02_Infrastructure/ops/ensure_data_current.sh}
SH=${BASH:-bash}                                   # 지금 도는 Git Bash 그대로(bare bash 금지 — WSL 가로챔)
LOG="$ROOT/.cache/scheduler_logs/data_selfheal_tick.log"
[ "${QVEST_DATA_SELFHEAL_TICK:-on}" = "off" ] && exit 0
mkdir -p "$(dirname "$LOG")" 2>/dev/null
say() { printf '[%s] %s\n' "$(date '+%F %T')" "$*" >> "$LOG" 2>/dev/null; }

if [ ! -f "$RB" ] || [ ! -f "$EDC" ]; then say "skip — 배리어 판정기 또는 자가 복구 스크립트 없음"; exit 0; fi
ST="$("$SH" "$RB" status 2>/dev/null | tr -d '\r' | sed -n 's/.*state=\([A-Za-z_]*\).*/\1/p' | head -n 1)"
if [ "$ST" != "free" ]; then say "skip — 리프레시 배리어 state=${ST:-unknown}(도는 중이거나 판정 불가)"; exit 0; fi

OUT="$("$SH" "$EDC" 2>&1)"; RC=$?
LAST="$(printf '%s\n' "$OUT" | grep -E '^\[edc ' | tail -n 1 | cut -c1-200)"
case "$RC" in
  0) if printf '%s\n' "$OUT" | grep -q '이미 최신'; then say "ok — 이미 최신(no-op)"; else say "ok — 복구 뒤 최신 확보 · ${LAST}"; printf '%s\n' "$OUT" | tail -n 20 >> "$LOG" 2>/dev/null; fi ;;
  3) say "stale — 복구 생략 또는 복구 뒤에도 낡음(rc=3) · ${LAST}"; printf '%s\n' "$OUT" | grep -q '자가 복구 실행' && printf '%s\n' "$OUT" | tail -n 20 >> "$LOG" 2>/dev/null ;;
  *) say "error — ensure_data_current rc=${RC} · ${LAST}"; printf '%s\n' "$OUT" | tail -n 20 >> "$LOG" 2>/dev/null ;;
esac
exit 0
