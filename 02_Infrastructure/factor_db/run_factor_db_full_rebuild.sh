#!/usr/bin/env bash
#==============================================================================
# run_factor_db_full_rebuild.sh — 팩터 DB 전체 재빌드(월간 전 기간 + 일간 + 월간 IC) · 2026-11-09
#   (재무 원천 v2 전환 · 도훈 '보충 끝나면 전체 재빌드해줘' · 절차서
#    04_Research/01_reports/quantiwise_data_expansion_20261106/fundamentals_v2/SWITCH_RUNBOOK.md)
#
# 순서: ① 사전 점검 ② 월간 사본(.cache/factor_db → .cache/factor_db_backup/<tag>_<시각>/factor_db · 6~7 GB)
#       ③ 월간 전 기간 build_factor_db_monthly(force = TRUE) — 07-25 실측 7.9시간
#       ④ 일간 run_fdb_rebuild.sh(phase 6 · 7 · 8 · 단계마다 별도 프로세스) — 실측 ~48분
#       ⑤ 월간 IC compute_all_factor_ic_monthly() ⑥ 요약 JSON ⑦ 텔레그램 1통(성공 · 실패 모두)
# 사전 점검(걸리면 시작 안 함 · rc 3):
#   · 06_Registry/fundamental_source.json::active == --expect-source(기본 v2)
#   · 시작 시각 < --start-before(기본 13 시) — 00:03 정규 갱신 [6a] 전에 끝나게(--any-time 으로 끔)
#   · 리프레시 배리어(ops/refresh_barrier.sh — 정규 갱신 잠금 · RAWDATA 쓰기 잠금)가 free
#   · 다른 팩터 빌드 프로세스 없음
# 단계마다 시작 전에 배리어를 기다린다(최대 2시간) — RAWDATA 를 쓰는 중에 읽지 않는다.
# ★월간 빌더는 달마다 오류를 잡고 계속 간다(rc 0) — 그래서 로그의 [FATAL] 줄을 세어 단계 실패로 본다.
# 일간 DB 사본은 기본으로 뜨지 않는다(21 GB · OneDrive 동기화 · 되돌리기 = v1 원천으로 다시 짓기 ~48분). --backup-daily 로 켠다.
# 사용: bash run_factor_db_full_rebuild.sh [--tag fund_v2] [--expect-source v2] [--from monthly|daily|ic]
#                                         [--skip-backup] [--backup-daily] [--any-time] [--start-before 13] [--dry-run]
# 종료: 0 성공 · 1 단계 실패(요약 JSON 의 backup 경로에서 되돌린다) · 3 사전 점검 걸림
#==============================================================================
set -uo pipefail
TAG="fund_v2"; EXPECT="v2"; FROM="monthly"; SKIP_BACKUP=0; BACKUP_DAILY=0; ANY_TIME=0; START_BEFORE=13; DRY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --tag) TAG="$2"; shift 2 ;;
    --expect-source) EXPECT="$2"; shift 2 ;;
    --from) FROM="$2"; shift 2 ;;
    --skip-backup) SKIP_BACKUP=1; shift ;;
    --backup-daily) BACKUP_DAILY=1; shift ;;
    --any-time) ANY_TIME=1; shift ;;
    --start-before) START_BEFORE="$2"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    *) echo "unknown arg: $1"; exit 3 ;;
  esac
done
case "$FROM" in monthly|daily|ic) ;; *) echo "--from must be monthly|daily|ic"; exit 3 ;; esac

# 루트: 역슬래시를 '/' 로 고친 뒤 표식 파일로 검증(r-portability ③ · 정규화가 검사보다 먼저)
_root_ok() { [ -n "$1" ] && [ -f "$1/02_Infrastructure/hooks/qvest_hook_router.py" ]; }
ROOT=""
for c in "${QM_ROOT:-}" "${CLAUDE_PROJECT_DIR:-}" "$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd)"; do
  c=$(printf '%s' "$c" | tr '\\' '/')
  if _root_ok "$c"; then ROOT="$c"; break; fi
  [ -n "$c" ] && echo "[rebuild] 루트 후보 기각(표식 없음): $c" >&2
done
[ -n "$ROOT" ] || { echo "[rebuild] 오류: 프로젝트 루트를 찾지 못했다"; exit 3; }
INFRA="$ROOT/02_Infrastructure"
RS="${QVEST_RSCRIPT:-/c/Program Files/R/R-4.6.2/bin/Rscript.exe}"
[ -x "$RS" ] || { echo "[rebuild] 오류: Rscript 없음: $RS"; exit 3; }
STAMP=$(date '+%Y%m%d_%H%M%S')
BDIR="$ROOT/.cache/factor_db_backup/${TAG}_${STAMP}"
LOGDIR="$ROOT/.cache/scheduler_logs"; mkdir -p "$LOGDIR"
LOG="$LOGDIR/factor_db_full_rebuild_${STAMP}.log"
SUMMARY="$LOGDIR/factor_db_full_rebuild_${STAMP}.json"
TS() { date '+%Y-%m-%d %H:%M:%S'; }
say() { echo "[rebuild $(TS)] $*" | tee -a "$LOG"; }
declare -A RC DUR
T0=$(date +%s)

# ---- ① 사전 점검 ------------------------------------------------------------------------------------
pre_fail=""
SRC=$("$RS" --no-save -e "cat(jsonlite::fromJSON('$ROOT/06_Registry/fundamental_source.json')\$active)" 2>/dev/null)
[ "$SRC" = "$EXPECT" ] || pre_fail="${pre_fail}재무 원천 active=$SRC(기대 $EXPECT) · "
HOUR=$((10#$(date +%H)))
if [ "$ANY_TIME" -eq 0 ] && [ "$HOUR" -ge "$START_BEFORE" ]; then
  pre_fail="${pre_fail}시작 시각 ${HOUR}시 ≥ ${START_BEFORE}시(00:03 정규 갱신과 겹칠 수 있음 · --any-time) · "
fi
BAR=$(bash "$INFRA/ops/refresh_barrier.sh" status 2>&1 | tail -1); BAR_RC=$?
case "$BAR" in *state=held*) pre_fail="${pre_fail}리프레시 배리어 held($BAR) · " ;; esac
OTHERS=$(powershell.exe -NoProfile -Command "Get-CimInstance Win32_Process | Where-Object { \$_.Name -match '^(Rscript|R|Rterm)\.exe\$' -and \$_.CommandLine -match 'factor_db_builder|factor_db_daily_phase|run_fdb_rebuild' } | ForEach-Object { \$_.ProcessId }" 2>/dev/null | tr -d '\r' | xargs)
[ -n "$OTHERS" ] && pre_fail="${pre_fail}다른 팩터 빌드 실행 중(pid $OTHERS) · "
say "사전 점검: 원천=$SRC · 시각=${HOUR}시 · 배리어=[$BAR] · 다른 빌드=[${OTHERS:-없음}] · from=$FROM · tag=$TAG"
if [ -n "$pre_fail" ]; then say "시작 안 함 — ${pre_fail%· }"; exit 3; fi
if [ "$DRY" -eq 1 ]; then say "dry-run — 사전 점검 통과 · 아무것도 하지 않음"; exit 0; fi

wait_barrier() {
  local out; out=$(bash "$INFRA/ops/refresh_barrier.sh" wait 7200 60 2>&1 | tail -2 | tr '\n' ' ')
  case "$out" in *state=held*) say "배리어 2시간 대기 뒤에도 held — 중단: $out"; return 1 ;; esac
  return 0
}
finish() {  # $1 = 결과(성공 | 실패) · $2 = 한 줄 설명
  local secs=$(( $(date +%s) - T0 ))
  local nm nd
  nm=$(ls "$ROOT/.cache/factor_db" 2>/dev/null | grep -c '^factor_db_[0-9]\{6\}\.parquet$')
  nd=$(ls "$ROOT/.cache/factor_db_daily" 2>/dev/null | grep -c '^fdb_daily_[0-9]\{6\}\.parquet$')
  cat > "$SUMMARY" <<JS
{"schema": "factor_db_full_rebuild/v1", "tag": "$TAG", "stamp": "$STAMP", "result": "$1", "note": "$2",
 "source": "$SRC", "from": "$FROM", "backup": "$BDIR", "log": "$LOG", "seconds": $secs,
 "stages": {"backup": "${RC[backup]:-skip}", "monthly": "${RC[monthly]:-skip}", "monthly_fatal": "${RC[monthly_fatal]:-}",
            "daily": "${RC[daily]:-skip}", "ic": "${RC[ic]:-skip}"},
 "minutes": {"monthly": "${DUR[monthly]:-}", "daily": "${DUR[daily]:-}", "ic": "${DUR[ic]:-}"},
 "files": {"factor_db_monthly": $nm, "factor_db_daily": $nd}}
JS
  say "요약: $SUMMARY"
  local s_r l_r b_r
  s_r=$(printf '%s' "$SUMMARY" | tr '\\' '/'); l_r=$(printf '%s' "$LOG" | tr '\\' '/'); b_r=$(printf '%s' "$BDIR" | tr '\\' '/')
  local rfile="$LOGDIR/_tg_factor_db_full_rebuild_${STAMP}.R"
  cat > "$rfile" <<RS
suppressWarnings(suppressMessages(source(file.path("$ROOT", "02_Infrastructure", "telegram", "telegram_notify.R"))))
res <- tryCatch(tg_agent_brief(
  agent = "Q-Lead", title = "[데이터] 팩터 DB 전체 재빌드 $1 — 재무 원천 $SRC",
  relaxed = TRUE, force = TRUE, lock_scope = "factor_db_full_rebuild_$STAMP",
  sections = list(
    list(type = "summary", body = "$2"),
    list(type = "kv", heading = "단계", kv = list(
      "월간" = "rc ${RC[monthly]:-skip} · ${DUR[monthly]:-?}분 · FATAL ${RC[monthly_fatal]:-0}",
      "일간" = "rc ${RC[daily]:-skip} · ${DUR[daily]:-?}분",
      "IC" = "rc ${RC[ic]:-skip} · ${DUR[ic]:-?}분",
      "파일" = "월간 $nm · 일간 $nd",
      "사본" = "$b_r", "요약" = "$s_r", "로그" = "$l_r"))
  )), error = function(e) { cat("tg fail:", conditionMessage(e), "\n"); NULL })
RS
  "$RS" --no-save "$rfile" >> "$LOG" 2>&1 || say "텔레그램 발송 실패(요약 파일은 남음)"
}

# ---- ② 사본 ------------------------------------------------------------------------------------------
if [ "$SKIP_BACKUP" -eq 0 ] && [ "$FROM" = "monthly" ]; then
  say "② 월간 사본 → $BDIR/factor_db"
  mkdir -p "$BDIR"
  W_SRC=$(cygpath -w "$ROOT/.cache/factor_db"); W_DST=$(cygpath -w "$BDIR/factor_db")
  MSYS2_ARG_CONV_EXCL='*' robocopy "$W_SRC" "$W_DST" /E /R:1 /W:1 /NFL /NDL /NJH /NP >> "$LOG" 2>&1; rr=$?
  if [ "$rr" -ge 8 ]; then RC[backup]="robocopy_$rr"; say "사본 실패(robocopy rc=$rr) — 재빌드하지 않는다"; finish "실패" "월간 사본 실패 — 팩터 DB 는 그대로"; exit 1; fi
  if [ "$BACKUP_DAILY" -eq 1 ]; then
    W_SRC=$(cygpath -w "$ROOT/.cache/factor_db_daily"); W_DST=$(cygpath -w "$BDIR/factor_db_daily")
    MSYS2_ARG_CONV_EXCL='*' robocopy "$W_SRC" "$W_DST" /E /R:1 /W:1 /NFL /NDL /NJH /NP >> "$LOG" 2>&1; rr=$?
    if [ "$rr" -ge 8 ]; then RC[backup]="robocopy_daily_$rr"; say "일간 사본 실패(rc=$rr) — 재빌드하지 않는다"; finish "실패" "일간 사본 실패 — 팩터 DB 는 그대로"; exit 1; fi
  fi
  RC[backup]=0
fi

cd "$INFRA" || { say "cd 실패: $INFRA"; exit 1; }
# ---- ③ 월간 전 기간 -------------------------------------------------------------------------------------
if [ "$FROM" = "monthly" ]; then
  wait_barrier || { RC[monthly]="barrier"; finish "실패" "월간 시작 전 배리어가 2시간 넘게 held"; exit 1; }
  say "③ 월간 전 기간 build_factor_db_monthly(force = TRUE) 시작"
  t=$(date +%s); MLOG="$LOGDIR/factor_db_full_rebuild_${STAMP}_monthly.log"
  "$RS" --no-save -e "source('config.R'); source('factor_db/factor_db_builder.R'); build_factor_db_monthly(force = TRUE)" > "$MLOG" 2>&1
  RC[monthly]=$?; DUR[monthly]=$(( ($(date +%s) - t) / 60 ))
  RC[monthly_fatal]=$(grep -a -c '\[FATAL\]' "$MLOG")
  say "③ 월간 끝 rc=${RC[monthly]} · FATAL ${RC[monthly_fatal]}개월 · ${DUR[monthly]}분 · 로그 $MLOG"
  if [ "${RC[monthly]}" -ne 0 ] || [ "${RC[monthly_fatal]}" -gt 0 ]; then
    grep -a '\[FATAL\]' "$MLOG" | head -5 | tee -a "$LOG"
    finish "실패" "월간 재빌드 실패(rc ${RC[monthly]} · FATAL ${RC[monthly_fatal]}개월) — 사본 $BDIR 에서 되돌릴 것"; exit 1
  fi
fi
# ---- ④ 일간 ------------------------------------------------------------------------------------------
if [ "$FROM" = "monthly" ] || [ "$FROM" = "daily" ]; then
  wait_barrier || { RC[daily]="barrier"; finish "실패" "일간 시작 전 배리어가 2시간 넘게 held"; exit 1; }
  say "④ 일간 run_fdb_rebuild.sh(phase 6 · 7 · 8) 시작"
  t=$(date +%s)
  bash "$INFRA/factor_db/run_fdb_rebuild.sh" >> "$LOG" 2>&1
  RC[daily]=$?; DUR[daily]=$(( ($(date +%s) - t) / 60 ))
  say "④ 일간 끝 rc=${RC[daily]} · ${DUR[daily]}분"
  [ "${RC[daily]}" -eq 0 ] || { finish "실패" "일간 재빌드 실패(rc ${RC[daily]}) — 일간 DB 는 부분 상태. 되돌리기 = 원인 수리 뒤 --from daily"; exit 1; }
fi
# ---- ⑤ 월간 IC ---------------------------------------------------------------------------------------
wait_barrier || { RC[ic]="barrier"; finish "실패" "IC 시작 전 배리어가 2시간 넘게 held"; exit 1; }
say "⑤ 월간 IC compute_all_factor_ic_monthly() 시작"
t=$(date +%s)
"$RS" --no-save -e "source('config.R'); source('factor_db/factor_db_builder.R'); compute_all_factor_ic_monthly()" >> "$LOG" 2>&1
RC[ic]=$?; DUR[ic]=$(( ($(date +%s) - t) / 60 ))
say "⑤ IC 끝 rc=${RC[ic]} · ${DUR[ic]}분"
[ "${RC[ic]}" -eq 0 ] || { finish "실패" "월간 IC 실패(rc ${RC[ic]}) — 월간 · 일간은 끝났다. --from ic 로 다시"; exit 1; }
finish "성공" "월간 · 일간 · IC 전부 끝 — 검사(절차서 §6)는 Q 가 이어서 한다"
exit 0
