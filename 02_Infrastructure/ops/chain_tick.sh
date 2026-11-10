#!/usr/bin/env bash
#==============================================================================
# chain_tick.sh — 강화 사슬(P4) 무인 틱 한 번 (v1 · 2026-11-10 · 결정 CHAIN-AUTOMATION-STANDING-BOARD-AND-TICK-20261110)
#
# 이미 등록된 열린 사슬마다 사람 없이 다음을 잇는다: ① 기준 칸 측정 ② 열린 걸음 측정 ③ 측정된 걸음 판정(등록된 규칙 · 결정론)
#   ④ 다음 걸음 설계(생성기 LLM 1회 = chain_gen_run.sh) → 산출 검사(chain_tick.R compile) → round.sh p4-step-open(최종 판정 = 코어)
# ★감독 아래 남는 것 — 틱은 부르지 않는다(허용 목록 밖 = 거부): 사슬 판 등록(p4-register) · 닫기(p4-close) · 생성기 새 판(p4-generator-review)
#   · 격리(p4-quarantine · outcomes-quarantine). 닫을 때가 되면(예산 · 연속 잡음 · 판 표식 · 생성기 판) '닫기 대기' 알림 한 통만 낸다.
# 다음 행동은 읽기 전용 계획기(02_Infrastructure/programs/chain_tick.R plan)가 원장(chain_steps.jsonl)을 매 행동 뒤 다시 읽어 정한다.
#   이 셸이 갖는 것은 허용 목록 · 순서 · 상한 집행뿐이다(판정 규칙 없음).
# 상한: 틱당 측정 = 설정 measures_per_tick · 생성 = 틱당 사슬 하나 · 그 사슬 1회. 측정할 수 없는 때(배리어 잠김 · 데이터 낡음 · 측정 예산 소진)에는
#   새 걸음을 열지 않는다(열고 못 재는 걸음 = Superfan reinforce_chain step_stalled 오경보).
# 보고: 걸음 판정 · 열기 · 측정 = 푸시 없음(로그만) · 닫기 대기 = 사슬 · 사유당 prep_send 1통 · 실패 · 차단 = sched_alert_emit(원인 하나 = 하루 한 통).
#
# 사용: bash 02_Infrastructure/ops/chain_tick.sh [--dry-run | --reset <chain_id>]
#   (인자 없음) 실제 실행 — 호출자 = 예약 작업 Qvest_StandingBoard(매시 37분 · standing_board_run.sh --send 다음)
#   --dry-run   계획 표만 출력(round.sh · 생성기 미호출 · 잠금 · 로그 없음 · 배리어 상태만 읽는다)
#   --reset ID  그 사슬의 틱 장부(생성 차단 · 연속 실패 · 판정 오류)만 지운다(원장 무접촉)
# 끄기: 06_Registry/chain_tick.json "enabled": false · 사슬 하나 = <사슬>/tick_hold 파일 · 한 번만 = QVEST_CHAIN_TICK=off
# 잠금 = <ROOT>/.cache/chain_tick.lock(mkdir · pid · standing_board_run.sh 와 같은 규칙) · 로그 = <ROOT>/.cache/scheduler_logs/chain_tick_<YYYYmmdd_HHMMSS>.log
# 장부 = <ROOT>/.cache/chain_tick/(원장 아님) · 생성기 작업 폴더 = <lanes_dir>/<chain_id>/k<k>_<ts>/
# 종료 = 0(정상 · 사슬 없음 · 잠금 건너뜀 · 꺼짐) · 1(어느 사슬 행동이 오류) · 2(인자 오류)
# 시험 주입: RC_ROOT_POSIX · RC_ROOT_WIN(round.sh 와 같은 뜻) · CT_RS · CT_HELPER · CT_RSCRIPT · CT_GEN · RB_SH · CT_STATE_DIR · CT_CFG · CT_NOW · QVEST_NO_ALERT · CT_LOCK_RACE_HOOK
# 재수리(11-10 독립 검증 2인): 측정 상태 줄 = 첫 ' — ' 뒤 토큰 · 닫힌 사슬 · tick_hold = 0단계 제외(무음) · 생성 뒤 재계획(hold · 경합) · 산출 없는 0 = 건너뜀 ·
#   쓰지 않은 작업 폴더 삭제 · 닫기 대기 알림 = 발송 성공 뒤 표식 · 정지 알림 = 하루 단위 표식 · 죽은 잠금 회수 = rename 뒤 재판정
#==============================================================================
set -u
ROOT=${RC_ROOT_POSIX:-/c/Users/99922/OneDrive/Quant_Module_Moltbot}
ROOT_WIN=${RC_ROOT_WIN:-C:/Users/99922/OneDrive/Quant_Module_Moltbot}
OPS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
SH=${BASH:-bash}                                   # 지금 도는 Git Bash 그대로(bare bash 금지 — WSL 가로챔 · 금칙 ⑦)
RS=${CT_RS:-$ROOT/04_Research/programs/_lib/round_core/round.sh}
HELPER=${CT_HELPER:-$ROOT/02_Infrastructure/programs/chain_tick.R}
RSCRIPT=${CT_RSCRIPT:-Rscript}
GEN=${CT_GEN:-$ROOT/02_Infrastructure/ops/chain_gen_run.sh}
RB=${RB_SH:-$ROOT/02_Infrastructure/ops/refresh_barrier.sh}
ALLOWED=" p4-base-measure p4-step-measure p4-step-decide p4-step-abandon p4-workdir p4-step-open p4-status fresh-check "   # ★허용 목록 — 이 밖 = 거부
DRY=0; RESET=""
usage(){ echo "usage: chain_tick.sh [--dry-run | --reset <chain_id>]" >&2; exit 2; }
while [ $# -gt 0 ]; do
  case "$1" in --dry-run) DRY=1 ;; --reset) RESET="${2:-}"; [ -n "$RESET" ] || usage; shift ;; *) usage ;; esac; shift
done
[ "${QVEST_CHAIN_TICK:-on}" = "off" ] && exit 0
H(){ CLAUDE_PROJECT_DIR="$ROOT_WIN" QM_ROOT="$ROOT_WIN" "$RSCRIPT" "$HELPER" "$@" 2>/dev/null | tr -d '\r'; return "${PIPESTATUS[0]}"; }
if [ -n "$RESET" ]; then H reset "$RESET"; exit $?; fi

# ── 0. 등록된 사슬(원장 첫 줄 = chain_registered) — 0개면 무음 0 종료(잠금 · 로그 · R 호출 없음) ──────────
CHAINS=()
for sp in "$ROOT"/04_Research/programs/P4_ASSEMBLY/*/chain_spec.json; do
  [ -f "$sp" ] || continue
  d=${sp%/chain_spec.json}; case "$(basename "$d")" in _*) continue ;; esac
  [ -f "$d/chain_steps.jsonl" ] || continue
  head -n 1 "$d/chain_steps.jsonl" | grep -q '"event":"chain_registered"' || continue
  # 닫힌 사슬(원장 마지막 = chain_closed · 코어는 닫힌 뒤 어떤 사건도 붙이지 않는다) · 세션 보류(tick_hold)는 여기서 뺀다 — 남은 것이 없으면 무음 0(재수리 11-10)
  tail -n 1 "$d/chain_steps.jsonl" | grep -q '"event":"chain_closed"' && continue
  [ -e "$d/tick_hold" ] && continue
  CHAINS+=("${d#"$ROOT"/}")
done
[ "${#CHAINS[@]}" -eq 0 ] && exit 0

LOG=""
log(){ if [ -n "$LOG" ]; then printf '%s\n' "$*" | tee -a "$LOG"; else printf '%s\n' "$*"; fi; }
alert(){ # $1 = 사유(마커 이름 · 사슬별이면 _<chain_id> 포함) $2 = 내용 $3 = 원인 키 $4 = 요약 — 원인 하나 = 하루 한 통(sched_alert_emit)
  log "[경보] $1 — $2"
  [ "$DRY" = "1" ] && return 0
  ( BASE="$ROOT"; TODAY="$(date +%Y%m%d)"; export BASE TODAY
    source "$OPS_DIR/_sched_failure_classify.sh" 2>/dev/null || exit 0
    command -v sched_alert_emit >/dev/null 2>&1 && sched_alert_emit "chain_tick" "$1" "$2" "$3" "$4" )
  return 0
}
once(){ # $1 = chain_id $2 = 표식 키 → 0 = 처음(알린다) · 1 = 이미 알림 — 사건 하나에 한 번(포기 · 차단)
  [ "$(H record "$1" mark "$2" | tail -n 1)" = "new" ]
}
once_daily(){ # 같은 뜻 · 하루 단위(판독 실패 · 정지 상태 — 회복 뒤 같은 사유로 다시 멈추면 다음 날 다시 알린다 · 재수리 11-10)
  [ "$(H record "$1" mark_daily "$2" | tail -n 1)" = "new" ]
}

# ── 1. 설정(판독 불가 = 아무것도 하지 않는다 · 경보 1통) ─────────────────────────────
EN=$(H config enabled); erc=$?; EN=$(printf '%s\n' "$EN" | tail -n 1)
if [ "$erc" != "0" ] || { [ "$EN" != "true" ] && [ "$EN" != "false" ]; }; then
  alert "config_unreadable" "06_Registry/chain_tick.json 판독 불가(rc $erc) — 틱이 아무것도 하지 않는다" "chain_tick:config_unreadable" "강화 사슬 무인 틱 설정을 읽지 못했습니다"; exit 0
fi
[ "$EN" = "true" ] || exit 0

barrier_state() {   # 출력 = state · rc 0 = 진행 · 10 = 막음(standing_board_run.sh 와 같은 판정 · 판정기 없음/오류 = 막음)
  if [ ! -f "$RB" ]; then echo missing; return 10; fi
  local line rc
  line=$("$SH" "$RB" status 2>/dev/null); rc=$?
  printf '%s\n' "$line" | sed -n 's/^RB\tstate=\([a-z]*\).*/\1/p' | head -n 1
  [ "$rc" = "10" ] && return 10
  [ "$rc" = "0" ] || return 10
  return 0
}
LOCKD="$ROOT/.cache/chain_tick.lock"
lock_holder() { # [$1 = 잠금 디렉터리(기본 LOCKD)] → 살아 있는 보유자 pid | fresh-empty | (없음 = 죽은 잠금)
  local d="${1:-$LOCKD}" op age
  [ -d "$d" ] || return 0
  op=$(head -n 1 "$d/pid" 2>/dev/null | tr -dc '0-9')
  if [ -n "$op" ]; then kill -0 "$op" 2>/dev/null && echo "$op"; return 0; fi
  age=$(( $(date +%s) - $(stat -c %Y "$d" 2>/dev/null || echo 0) ))
  [ "$age" -le 60 ] && echo "fresh-empty"
  return 0
}

if [ "$DRY" = "1" ]; then
  bs=$(barrier_state); brc=$?
  echo "[사슬 틱 · 드라이런] 등록된 사슬 ${#CHAINS[@]} · 배리어 ${bs:-?}($([ "$brc" = "0" ] && echo 열림 || echo 잠김)) · 잠금 $(lock_holder | grep . || echo 없음) · 생성 물러남 $(H backoff-active | tail -n 1)"
  printf '사슬\tACTION\tk\treason\tdetail\tlast_served_at\n'
  H list
  exit 0
fi

# ── 2. 잠금 · 로그 ───────────────────────────────────────────────────────────────
mkdir -p "$ROOT/.cache"
if ! mkdir "$LOCKD" 2>/dev/null; then
  h=$(lock_holder)
  if [ -n "$h" ]; then echo "[사슬 틱] 다른 실행이 잠금을 쥐고 있다(pid $h) — 이번 틱 건너뜀"; exit 0; fi
  # 죽은 잠금 회수(재수리 11-10 · TOCTOU) — 판정과 삭제 사이에 다른 실행이 새 잠금을 만들 수 있다. 그래서 지우지 않고 고유 이름으로 옮긴 뒤(rename = 원자)
  #   옮겨 온 그 디렉터리를 다시 판정한다: 살아 있으면 되돌리고 건너뛴다 · 죽었으면 지운다. 시험 주입 CT_LOCK_RACE_HOOK = 판정과 회수 사이에 끼울 명령
  [ -n "${CT_LOCK_RACE_HOOK:-}" ] && "$SH" -c "$CT_LOCK_RACE_HOOK"
  RCL="$LOCKD.reclaim.$$"
  if mv -T "$LOCKD" "$RCL" 2>/dev/null; then
    h=$(lock_holder "$RCL")
    if [ -n "$h" ]; then
      mv -T "$RCL" "$LOCKD" 2>/dev/null || echo "[사슬 틱] 회수한 잠금을 되돌리지 못했다($RCL)"
      echo "[사슬 틱] 잠금 인계 경합(살아 있는 보유자 $h) — 이번 틱 건너뜀"; exit 0
    fi
    rm -rf "$RCL"
  fi
  mkdir "$LOCKD" 2>/dev/null || { echo "[사슬 틱] 잠금 인계 경합 — 이번 틱 건너뜀"; exit 0; }
fi
echo "$$" > "$LOCKD/pid"
trap '[ "$(head -n 1 "$LOCKD/pid" 2>/dev/null | tr -dc 0-9)" = "$$" ] && rm -rf "$LOCKD"' EXIT     # 자기 잠금만 푼다
LOGD="$ROOT/.cache/scheduler_logs"; mkdir -p "$LOGD"
LOG="$LOGD/chain_tick_$(date +%Y%m%d_%H%M%S).log"
RC=0; NONSKIP=0      # NONSKIP = 건너뜀 말고 한 일이 있었나(없고 rc 0 이면 끝에서 로그 파일을 지운다 — 재수리 11-10)
log "== $(date '+%F %T') 강화 사슬 무인 틱 — 등록된 사슬 ${#CHAINS[@]} =="

RS_OUT=""
rs(){ # $1 = 사슬 $2 = 단계 [인자] — 허용 목록 밖 단계는 부르지 않는다
  case "$ALLOWED" in *" $2 "*) ;; *) log "[거부] 허용 목록 밖 단계: $2 ($1)"; alert "forbidden_stage" "틱이 허용 목록 밖 단계($2)를 부르려 했다 — 부르지 않았다" "chain_tick:forbidden_stage" "강화 사슬 틱이 감독 단계를 부르려 해 막았습니다"; RC=1; return 99 ;; esac
  local rc
  RS_OUT=$("$SH" "$RS" "$@" 2>&1); rc=$?
  printf '%s\n' "$RS_OUT" >> "$LOG"
  return "$rc"
}
ACT=""; K=""; RSN=""; DET=""
plan(){ local line; line=$(H plan "$1" | tail -n 1); IFS=$'\t' read -r ACT K RSN DET <<< "$line"; ACT=${ACT:-broken}; [ -n "$line" ] || RSN="plan_empty"; }
stage_of(){ case "$1" in decide) echo p4-step-decide ;; abandon) echo p4-step-abandon ;; measure_base) echo p4-base-measure ;; measure_step) echo p4-step-measure ;; *) echo "p4-$1" ;; esac; }

# ── 3. 배리어 status 한 번 — 잠김이면 계획 · 알림만(측정 · 판정 · 설계 건너뜀 · 기다리지 않는다) ─────────────
BS=$(barrier_state); BRC=$?
BARRIER_OK=1; [ "$BRC" = "0" ] || { BARRIER_OK=0; log "[배리어] ${BS:-?} — 이번 틱 측정 · 판정 · 설계 건너뜀(다음 틱)"; }

do_decide(){ # $1 = 사슬 $2 = k
  local cid; cid=$(basename "$1")
  if rs "$1" p4-step-decide --k "$2"; then H record "$cid" decide_ok >/dev/null; log "[$cid] 걸음 $2 판정 — $(printf '%s\n' "$RS_OUT" | grep '^\[p4-step-decide\]' | tail -n 1)"; return 0; fi
  case "$RS_OUT" in
    *"이미 판정"*) log "[$cid] 걸음 $2 이미 판정(세션이 먼저) — 무해" ;;
    *"판 표식"*) log "[$cid] 걸음 $2 판 표식 불일치 — 다음 계획이 닫기 대기" ;;
    *) local r; r=$(H record "$cid" decide_error "$2" | tail -n 1); RC=1
       alert "decide_error_$cid" "걸음 $2 판정 오류: $(printf '%s' "$RS_OUT" | tail -n 2 | tr '\n' ' ' | cut -c1-300)" "chain_tick:decide_error:$cid" "강화 사슬 걸음 판정이 실패했습니다"
       [ "$r" = "blocked" ] && once "$cid" "decide_failed:$2" && alert "decide_failed_$cid" "걸음 $2 판정 오류 상한 — 사람이 본다" "chain_tick:decide_failed:$cid" "강화 사슬 판정이 멈췄습니다(사람 확인)" ;;
  esac
  return 1
}
MEAS_LEFT=0
do_measure(){ # $1 = 사슬 $2 = measure_base|measure_step $3 = k
  local cid st rc; cid=$(basename "$1")
  [ "$MEAS_LEFT" -gt 0 ] || { log "[$cid] 이번 틱 측정 상한 소진 — 다음 틱"; return 1; }
  MEAS_LEFT=$((MEAS_LEFT - 1))
  if [ "$2" = "measure_base" ]; then rs "$1" p4-base-measure; else rs "$1" p4-step-measure --k "$3"; fi; rc=$?
  # 상태 토큰 = 상태 줄의 *첫* ' — ' 바로 뒤(driver.R '[p4-*-measure] <대상> — <status> · <reason>' · 사유 문구에도 ' — ' 가 든다 — 재수리 11-10)
  local ln rest; ln=$(printf '%s\n' "$RS_OUT" | grep -E '^\[p4-(base|step)-measure\] ' | tail -n 1); st=""
  if [ -n "$ln" ]; then rest=${ln#* — }; [ "$rest" != "$ln" ] && st=${rest%%[!a-z_]*}; fi
  log "[$cid] $2 k=${3:-0} → ${st:-?}(rc $rc)"
  case "$st" in
    measured|already|failed|barrier_held|data_stale|busy|vintage_in_progress|vintage_changed) : ;;
    vintage_unknown) alert "vintage_unknown" "팩터 DB 판 표식 판독 불가 — 사슬 측정을 못 한다" "chain_tick:vintage_unknown" "강화 사슬 측정이 판 표식을 읽지 못했습니다" ;;
    *) [ "$rc" = "4" ] || [ "$rc" = "6" ] || [ "$rc" = "7" ] || { RC=1; alert "measure_error_$cid" "$2 k=${3:-0} 실행 오류(rc $rc · 상태 줄 없음): $(printf '%s' "$RS_OUT" | tail -n 2 | tr '\n' ' ' | cut -c1-300)" "chain_tick:measure_error:$cid" "강화 사슬 측정 실행이 실패했습니다"; } ;;
  esac
  return 0
}
gen_fail(){ # $1 = chain_id $2 = 사유 코드 — 연속 실패 +1 · 상한이면 차단 + 알림 1회
  local r; r=$(H record "$1" gen_fail "$2" | tail -n 1); log "[$1] 생성 실패($2) — 장부 $r"
  if [ "$r" = "blocked" ] && once "$1" "gen_blocked"; then
    alert "gen_blocked_$1" "생성 연속 실패 상한 — 마지막 사유 $2 · 풀기 = bash 02_Infrastructure/ops/chain_tick.sh --reset $1" "chain_tick:gen_blocked:$1" "강화 사슬 다음 걸음 설계가 연속 실패해 멈췄습니다"
  fi
}
gen_step(){ # $1 = 사슬 $2 = k — 생성 → 검사 → 열기(성공 = 0)
  local cid lanes ts wrel ww grc out crc code; cid=$(basename "$1")
  lanes=$(H config lanes_dir | tail -n 1); [ -n "$lanes" ] || { log "[$cid] lanes_dir 판독 불가"; return 1; }
  ts=$(date +%Y%m%d_%H%M%S); wrel="$lanes/$cid/k${2}_$ts"; ww="$ROOT_WIN/$wrel"
  [ -e "$ROOT/$wrel" ] && { log "[$cid] 작업 폴더가 이미 있다: $wrel"; return 1; }
  if ! rs "$1" p4-workdir --out "$ww"; then
    alert "workdir_error_$cid" "생성기 작업 폴더 만들기 실패: $(printf '%s' "$RS_OUT" | tail -n 2 | tr '\n' ' ' | cut -c1-300)" "chain_tick:workdir_error:$cid" "강화 사슬 설계 입력을 만들지 못했습니다"; RC=1; return 1
  fi
  # 쓰지 않은 작업 폴더는 지운다(재수리 11-10 — 인증 · 가드 · 프롬프트 거부 · 경합 · 건너뜀이 이어지면 매시 폴더가 쌓였다) · 가드 탐침 로그는 틱 로그로 옮긴다
  drop_wdir(){ local g="$ROOT/$wrel.guard_probe.log"
    [ -f "$g" ] && { printf '%s\n' "--- 가드 탐침 로그($wrel) ---" >> "$LOG"; cat "$g" >> "$LOG"; rm -f "$g"; }
    chmod -R u+w "$ROOT/$wrel" 2>/dev/null; rm -rf "$ROOT/$wrel"; }
  still_open(){ # 생성 · 검사 뒤 다시 계획한다(재수리 11-10) — 그사이 세션이 tick_hold 를 두거나 걸음을 열었으면 열지 않는다(실패로 세지 않는다)
    plan "$1"; [ "$ACT" = "open" ] && [ "$K" = "$2" ] && return 0
    log "[$cid] 생성 뒤 계획이 바뀌었다($ACT k=$K ${RSN}) — 걸음 $2 을 열지 않는다(경합 · 실패로 세지 않는다)"; return 1; }
  if ! H prompt "$1" "$ww" >/dev/null; then log "[$cid] 프롬프트 조립 거부(생성기 판 파일 ≠ 사슬 판) — 다음 계획이 닫기 대기"; drop_wdir; return 1; fi
  log "[$cid] 생성기 호출 k=$2 · 작업 폴더 $wrel"
  "$SH" "$GEN" "$ww" "$1" >> "$LOG" 2>&1; grc=$?
  case "$grc" in
    0) if [ ! -f "$ROOT/$wrel/gen_result.json" ]; then   # 생성기는 잠금을 보고 건너뛸 때 산출 없이 0 으로 끝난다(chain_gen_run.sh) — 실패가 아니다
         log "[$cid] 생성기가 산출 없이 끝났다(다른 생성기 실행 중 · 건너뜀) — 실패로 세지 않는다"; drop_wdir; return 1
       fi ;;
    3) local u; u=$(H backoff-set usage_limit | tail -n 1); log "[$cid] 사용 한도 — 생성 물러남(~ $u · 측정 · 판정은 계속)"
       alert "llm_limit_usage_limit" "생성기 LLM 사용 한도 — $u 까지 사슬 설계만 멈춘다(측정 · 판정 계속)" "llm_limit:usage_limit" "LLM 사용 한도로 강화 사슬 설계를 쉬어 갑니다"; return 1 ;;
    4) alert "auth" "생성기 LLM 인증 사전점검 실패 — 다음 틱 재시도" "chain_tick:auth" "강화 사슬 생성기 인증이 실패했습니다"; drop_wdir; return 1 ;;
    5) alert "guard_probe" "생성기 읽기 경계 탐침 실패 — claude 를 부르지 않았다(탐침 로그 = 이 틱 로그)" "chain_tick:guard_probe" "강화 사슬 생성기 읽기 경계가 확인되지 않아 설계를 멈췄습니다"; drop_wdir; return 1 ;;
    *) gen_fail "$cid" "gen_exit_$grc"; return 1 ;;
  esac
  still_open "$1" "$2" || { drop_wdir; return 1; }
  out=$(H compile "$1" "$ww" "$2"); crc=$?; out=$(printf '%s\n' "$out" | tail -n 1)
  if [ "$crc" != "0" ]; then
    code=$(printf '%s' "$out" | awk '{print $2}'); log "[$cid] 산출 검사 거부: $out"
    case "$code" in race) log "[$cid] 세션과 경합 — 실패로 세지 않는다"; drop_wdir ;; *) gen_fail "$cid" "${code:-compile}" ;; esac
    return 1
  fi
  local o="$ROOT/$wrel/open"
  if ! still_open "$1" "$2"; then
    local cf0; cf0="$ROOT/$(cat "$o/cell.txt")"; chmod u+w "$cf0" 2>/dev/null; rm -f "$cf0"; drop_wdir; return 1     # 원장이 참조하지 않는 칸 사양
  fi
  if ! rs "$1" p4-step-open --k "$(cat "$o/k.txt")" --hypothesis "$(cat "$o/hypothesis.txt")" --mechanism "$(cat "$o/mechanism.txt")" \
        --block "$(cat "$o/block.txt")" --cell "$(cat "$o/cell.txt")" --parent "$(cat "$o/parent.txt")" --generator "$(cat "$o/generator.txt")"; then
    local cf; cf="$ROOT/$(cat "$o/cell.txt")"; chmod u+w "$cf" 2>/dev/null; rm -f "$cf"     # 원장이 참조하지 않는 칸 사양(열기 거부)
    case "$RS_OUT" in
      *"이미 쓴 칸 사양"*) gen_fail "$cid" duplicate ;;
      *"처방 입력 금지 정보"*) gen_fail "$cid" contaminated ;;
      *"예산 소진"*|*"앞 걸음이 판정되지 않았다"*|*"이미 열렸다"*) log "[$cid] 걸음 열기 경합(세션) — 실패로 세지 않는다" ;;
      *) gen_fail "$cid" invalid ;;
    esac
    return 1
  fi
  H record "$cid" gen_ok >/dev/null
  printf '{"chain":"%s","k":%s,"prompt_sha256":"%s","out_sha256":"%s","opened_at":"%s","preamble":"ct_preamble_v1"}\n' "$cid" "$2" \
    "$(sha256sum "$ROOT/$wrel/prompt.md" 2>/dev/null | cut -c1-64)" "$(sha256sum "$ROOT/$wrel/out.md" 2>/dev/null | cut -c1-64)" "$(date -Iseconds)" > "$ROOT/$wrel/tick_provenance.json"
  log "[$cid] 걸음 $2 열림"
  return 0
}

# ── 4. 가벼운 패스(모든 사슬 · 측정 · 생성 없음) ──────────────────────────────────────
HEAVY=()
for cd in "${CHAINS[@]}"; do
  cid=$(basename "$cd")
  for _i in 1 2; do
    plan "$cd"
    [ "$ACT" = "skip" ] || NONSKIP=1
    case "$ACT" in
      skip) log "[$cid] 건너뜀 — ${RSN} ${DET}"; break ;;
      broken) once_daily "$cid" "broken:$RSN" && alert "ledger_broken_$cid" "사슬 판독 불가($RSN) — $DET · 손대지 않음(격리 = 사람)" "chain_tick:ledger_broken:$cid" "강화 사슬 원장을 읽을 수 없습니다(사람 확인)"; break ;;
      close_stuck) once_daily "$cid" "close_stuck" && alert "close_stuck_$cid" "$DET" "chain_tick:close_stuck:$cid" "강화 사슬 닫기가 중간에 멈췄습니다"; break ;;
      blocked) case "$RSN" in gen_failures) log "[$cid] 생성 차단 중(--reset 으로 푼다)" ;;
                 *) once_daily "$cid" "blocked:$RSN" && alert "blocked_${RSN}_$cid" "$DET" "chain_tick:$RSN:$cid" "강화 사슬이 멈췄습니다(사람 확인)" ;; esac; break ;;
      close_wait) log "[$cid] 닫기 대기($RSN) — $DET"
                  nr=$(H notify "$cd" close_wait "$RSN"); nrc=$?; printf '%s\n' "$nr" >> "$LOG"; nr=$(printf '%s\n' "$nr" | tail -n 1)
                  # 발송 실패 = 표식 없음(다음 틱 재시도) · 경보는 원인 하나 = 하루 한 통 · 종료 1(재수리 11-10 — 감독 단계로 넘기는 유일한 신호다)
                  if [ "$nrc" != "0" ] || [ "$nr" = "failed" ] || [ -z "$nr" ]; then RC=1
                    alert "close_wait_notify_$cid" "닫기 대기($RSN) 알림 발송 실패(rc $nrc · ${nr:-출력 없음}) — 다음 틱에 다시 보낸다" "chain_tick:close_wait_notify:$cid" "강화 사슬 닫기 대기 알림이 나가지 않았습니다"
                  fi; break ;;
      wait) log "[$cid] 대기($RSN) — $DET"
            [ "$RSN" = "vintage_unknown" ] && alert "vintage_unknown" "$DET" "chain_tick:vintage_unknown" "강화 사슬 측정이 판 표식을 읽지 못했습니다"; break ;;
      measure_base|measure_step|open) HEAVY+=("$cd"); break ;;
      decide) [ "$BARRIER_OK" = "1" ] || break; do_decide "$cd" "$K" || break ;;
      abandon) [ "$BARRIER_OK" = "1" ] || break
               ar=$(H abandon-reason "$cd" "$K" | tail -n 1)
               if rs "$cd" p4-step-abandon --k "$K" --reason "$ar"; then once "$cid" "abandon:$K" && alert "step_abandoned_$cid" "걸음 $K 측정 실패 상한 — 포기 기록(가설 기각 아님)" "chain_tick:step_abandoned:$cid" "강화 사슬 걸음 하나가 측정 실패로 포기됐습니다"
               else RC=1; log "[$cid] 포기 기록 실패"; break; fi ;;
      *) st=$(stage_of "$ACT"); rs "$cd" "$st"; break ;;     # 모르는 행동 — 허용 목록이 막는다(부르지 않는다)
    esac
  done
done

# ── 5. 무거운 패스(틱당 사슬 하나 — 마지막 처리가 가장 오래된 사슬) ─────────────────────────────
if [ "$BARRIER_OK" = "1" ] && [ "${#HEAVY[@]}" -gt 0 ]; then
  NONSKIP=1
  MEAS_LEFT=$(H config measures_per_tick | tail -n 1); case "$MEAS_LEFT" in ''|*[!0-9]*) MEAS_LEFT=0 ;; esac
  BACKOFF=$(H backoff-active | tail -n 1)
  PICK=""; PICK_AT=""
  for cd in "${HEAVY[@]}"; do
    at=$(H state "$(basename "$cd")" last_served_at | tail -n 1)
    if [ -z "$PICK" ] || [[ "$at" < "$PICK_AT" ]]; then PICK="$cd"; PICK_AT="$at"; fi
  done
  cid=$(basename "$PICK"); plan "$PICK"
  case "$ACT" in
    measure_base|measure_step) do_measure "$PICK" "$ACT" "$K" ;;
    open)
      if [ "$BACKOFF" = "yes" ]; then log "[$cid] 생성 물러남(사용 한도) — 이번 틱 설계 안 함"
      elif [ "$MEAS_LEFT" -lt 1 ]; then log "[$cid] 측정 예산 0 — 열고 못 재는 걸음을 만들지 않는다"
      elif ! rs "$PICK" fresh-check; then log "[$cid] 데이터 신선도 미달 — 새 걸음을 열지 않는다(다음 틱)"
      elif gen_step "$PICK" "$K"; then
        plan "$PICK"; [ "$ACT" = "measure_step" ] && do_measure "$PICK" measure_step "$K"
      fi ;;
  esac
  plan "$PICK"; [ "$ACT" = "decide" ] && do_decide "$PICK" "$K"
  H record "$cid" served >/dev/null
fi
if [ "$NONSKIP" = "0" ] && [ "$RC" = "0" ]; then rm -f "$LOG"; exit 0; fi
log "== $(date '+%F %T') 끝 — rc $RC · 로그 ${LOG#"$ROOT"/} =="
exit "$RC"
