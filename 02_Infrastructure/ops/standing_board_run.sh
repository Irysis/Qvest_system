#!/usr/bin/env bash
#==============================================================================
# standing_board_run.sh — 상설 판 정기 실행 한 틱 (v10.2 사다리 루프 4항 '상설 판 — 규칙은 한 번 등록 · 후보는 흐른다' · 2026-11-10)
#
# 등록된 상설 판마다 한 틱 = scan → (입구 통과 대기 항목이 있고 리프레시 배리어가 열려 있으면) standing-measure → standing-report
#   · 각 단계는 round_core 실행기(04_Research/programs/_lib/round_core/round.sh)를 그대로 부른다 — 판정 · R2 · 원장 규칙은 거기(v1/standing.R) 하나다.
#   · 보고는 기본 드라이런 — --send 일 때만 발송(qvest-telegram §0 — 통과 = 엔진마다 push · 미달 = 일 요약 무음).
#   · 배리어는 status 한 번만 본다(refresh_barrier.sh 단일 정본 · held = 이번 틱 측정 건너뜀 · 판정기 없음 = 막음 · fail-closed).
#     잠겨 있으면 기다리지 않는다 — 다음 틱이 그대로 잇는다(v10.2 5항 '막지 않는다').
#
# 등록된 판 = 04_Research/programs/*/*/round_spec.json 중 "standing": true 이고 사양의 round_id = 디렉터리 이름이며
#   사전등록 정본(<RC_SA_ROOT|ROOT>/stage_artifacts/programs/<program>/<round_id>/prereg.json)이 있는 것. 등록 전 판은 건너뛴다.
#   판이 없으면 조용히 0 종료(출력 · 로그 없음).
#
# 사용: bash 02_Infrastructure/ops/standing_board_run.sh [--dry-run] [--send]
#   --dry-run  무엇을 할지만 출력(round.sh · R 미호출 · 잠금 · 로그 없음 · 배리어 상태만 읽는다)
#   --send     standing-report 를 실제 발송으로(없으면 드라이런)
# 잠금 = <ROOT>/.cache/standing_board_run.lock(mkdir · pid) — 살아 있는 보유자가 있으면 건너뛰고 0 종료 · 죽은 pid = 인계 ·
#   빈 pid 는 만든 지 60초 안이면 보유 중으로 본다(mkdir 과 pid 기록 사이 창).
# 로그 = <ROOT>/.cache/scheduler_logs/standing_board_<YYYYmmdd_HHMMSS>.log
# 종료 코드 = 0(정상 · 판 없음 · 잠금 건너뜀) · 1(어느 판의 scan · pending · measure · report 실패 — 다른 판은 계속 돈다)
# 환경: RC_ROOT_POSIX · RC_ROOT_WIN · RC_SA_ROOT = round.sh 와 같은 뜻(다른 작업 트리 · 시험 임시 루트) · RB_SH = 배리어 판정기 경로(시험 주입)
# ★예약 작업 등록은 하지 않는다(이 스크립트만). 등록은 도훈 승인 뒤 별도.
#==============================================================================
set -u
ROOT=${RC_ROOT_POSIX:-/c/Users/99922/OneDrive/Quant_Module_Moltbot}
SA_ROOT=${RC_SA_ROOT:-$ROOT}
RS="$ROOT/04_Research/programs/_lib/round_core/round.sh"
RB=${RB_SH:-$ROOT/02_Infrastructure/ops/refresh_barrier.sh}
SH=${BASH:-bash}                                   # 지금 도는 Git Bash 그대로(bare bash 금지 — WSL 가로챔 · 금칙 ⑦)
DRY=0; SEND=0
for a in "$@"; do case "$a" in --dry-run) DRY=1 ;; --send) SEND=1 ;; *) echo "usage: standing_board_run.sh [--dry-run] [--send]" >&2; exit 2 ;; esac; done

# ── 등록된 상설 판 찾기 ──────────────────────────────────────────────────────
BOARDS=()
for sp in "$ROOT"/04_Research/programs/*/*/round_spec.json; do
  [ -f "$sp" ] || continue
  grep -Eq '"standing"[[:space:]]*:[[:space:]]*true' "$sp" || continue
  d=$(dirname "$sp"); rid=$(basename "$d")
  grep -Eq "^  \"round_id\"[[:space:]]*:[[:space:]]*\"$rid\"" "$sp" || continue          # 사양 round_id = 디렉터리 이름(최상위 키)
  prog=$(sed -n 's/^  "program"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$sp" | head -n 1)
  [ -n "$prog" ] || prog=$(basename "$(dirname "$d")")
  [ -f "$SA_ROOT/stage_artifacts/programs/$prog/$rid/prereg.json" ] || continue        # 등록 전
  BOARDS+=("${d#"$ROOT"/}")
done
[ "${#BOARDS[@]}" -eq 0 ] && exit 0

barrier_state() {   # 출력 = state(free|stale|self|held|missing) · rc 0 = 진행 · 10 = 막음
  if [ ! -f "$RB" ]; then echo missing; return 10; fi
  local line rc
  line=$("$SH" "$RB" status 2>/dev/null); rc=$?
  printf '%s\n' "$line" | sed -n 's/^RB\tstate=\([a-z]*\).*/\1/p' | head -n 1
  [ "$rc" = "10" ] && return 10
  [ "$rc" = "0" ] || return 10                       # 판정기 오류 = 막음(fail-closed)
  return 0
}

LOCKD="$ROOT/.cache/standing_board_run.lock"
lock_holder() {     # 살아 있는 보유자 pid(또는 'fresh-empty') — 없으면 빈 출력
  [ -d "$LOCKD" ] || return 0
  local op age
  op=$(head -n 1 "$LOCKD/pid" 2>/dev/null | tr -dc '0-9')
  if [ -n "$op" ]; then kill -0 "$op" 2>/dev/null && echo "$op"; return 0; fi
  age=$(( $(date +%s) - $(stat -c %Y "$LOCKD" 2>/dev/null || echo 0) ))
  [ "$age" -le 60 ] && echo "fresh-empty"
  return 0
}

if [ "$DRY" = "1" ]; then
  bs=$(barrier_state); brc=$?
  h=$(lock_holder)
  echo "[상설 정기 · 드라이런] 등록된 판 ${#BOARDS[@]} · 배리어 ${bs:-?}($([ "$brc" = "0" ] && echo 열림 || echo 잠김)) · 잠금 ${h:-없음}"
  for b in "${BOARDS[@]}"; do
    echo "[드라이런] $b: scan → pending(입구 통과 대기 항목) → $([ "$brc" = "0" ] && echo "대기 있으면 standing-measure" || echo "배리어 잠김 — standing-measure 건너뜀") → standing-report$([ "$SEND" = "1" ] && echo " --send" || echo "(드라이런)")"
  done
  exit 0
fi

# ── 잠금 ─────────────────────────────────────────────────────────────────────
mkdir -p "$ROOT/.cache"
if ! mkdir "$LOCKD" 2>/dev/null; then
  h=$(lock_holder)
  if [ -n "$h" ]; then echo "[상설 정기] 다른 실행이 잠금을 쥐고 있다(pid $h) — 이번 틱 건너뜀"; exit 0; fi
  rm -rf "$LOCKD"
  mkdir "$LOCKD" 2>/dev/null || { echo "[상설 정기] 잠금 인계 경합 — 이번 틱 건너뜀"; exit 0; }
fi
echo "$$" > "$LOCKD/pid"
trap 'rm -rf "$LOCKD"' EXIT

LOGD="$ROOT/.cache/scheduler_logs"; mkdir -p "$LOGD"
LOG="$LOGD/standing_board_$(date +%Y%m%d_%H%M%S).log"
log() { printf '%s\n' "$*" | tee -a "$LOG"; }
run() { "$SH" "$RS" "$@" 2>&1 | tee -a "$LOG"; return "${PIPESTATUS[0]}"; }

log "== $(date '+%F %T') 상설 판 정기 실행 — 판 ${#BOARDS[@]}$([ "$SEND" = "1" ] && echo " · 발송" || echo " · 보고 드라이런") =="
RC=0
for b in "${BOARDS[@]}"; do
  log "-- [$b] scan"
  run "$b" scan || { log "[$b] scan 실패(rc $?) — 대기 항목 측정 · 보고는 계속 본다"; RC=1; }
  PEND=$("$SH" "$RS" "$b" pending 2>>"$LOG"); prc=$?
  NP=$(printf '%s\n' "$PEND" | grep -c '[^[:space:]]')
  if [ "$prc" != "0" ]; then log "[$b] pending 판독 실패(rc $prc) — 측정 건너뜀"; RC=1
  elif [ "$NP" -eq 0 ]; then log "[$b] 측정 대기 0 — 측정 없음"
  else
    bs=$(barrier_state); brc=$?
    if [ "$brc" != "0" ]; then log "[$b] 측정 대기 $NP · 리프레시 배리어 ${bs:-?} — 이번 틱 측정 건너뜀(다음 틱)"
    else
      log "-- [$b] standing-measure(대기 $NP · 배리어 ${bs:-?})"
      run "$b" standing-measure || { log "[$b] standing-measure 실패(rc $?)"; RC=1; }
      # 데이터 신선도 차단(11-10 · round_core v1/freshness.R) — 실행기가 대기 측정을 건너뛰면 센티널이 judged_data_stale · 요약 줄에 남긴다(rc 는 판정 결과 그대로)
      sent="${SENT_DIR:-$ROOT/.cache/round_core/state}/$(basename "$b").standing"
      if [ -f "$sent" ] && grep -q "status=judged_data_stale" "$sent"; then log "[$b] 데이터 신선도 미달 — 측정 대기 $NP 건너뜀(판정은 진행 · 다음 틱 재개)"; fi
    fi
  fi
  log "-- [$b] standing-report$([ "$SEND" = "1" ] && echo " --send")"
  if [ "$SEND" = "1" ]; then run "$b" standing-report --send; else run "$b" standing-report; fi || { log "[$b] standing-report 실패"; RC=1; }
done
log "== $(date '+%F %T') 끝 — rc $RC · 로그 ${LOG#"$ROOT"/} =="
exit "$RC"
