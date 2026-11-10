#!/usr/bin/env bash
#==============================================================================
# run_factor_subset_repair.sh — 빌더 결함 수리 뒤 영향 팩터 전 기간 재계산 진행기
#   (2026-11-09 · decision_register FACTOR-DIRECTION-STORAGE-REPAIR-20261109 · 도훈 '재무DB v2 기준으로 팩터 계산 다시해')
#
# 순서:
#   ① 전체 재빌드 끝 대기 — 요약 JSON 이 생기고 재빌드 프로세스(run_factor_db_full_rebuild · factor_db_builder · daily phase)가 없을 때.
#      요약 result 가 '성공'이 아니면 멈춘다(부분 재빌드 위에 덧칠하지 않는다).
#   ② 달 목록 = 월 파일 전부 − 이번 달(일일 체인 [6a] 가 같은 파일을 쓰므로 뺀다) → 번갈아 N몫(작업자마다 옛 달 · 새 달이 섞여 시간이 고르다).
#      ★이번 달은 저절로 고쳐지지 않는다 — [6a](update_factor_db_daily)는 스냅샷이 7일 넘게 묵거나 월말일 때만 그 달을 다시 짓는다
#      (2026-11-10 총부채 수리에서 확인: 202611 이 옛 값 그대로였다). 끝나면 rebuild_factor_subset.R --months <이번 달> 로 따로 바꿔 끼운다.
#   ③ 작업자 N개 병렬(rebuild_factor_subset.R --months … --log 작업자별 --no-hash).
#   ④ 잃은 쓰기 검사(--verify: 쓴 직후 지문 대 지금 파일) → 다시 할 달을 한 작업자로 다시(최대 2회).
#      작업자가 '다른 팩터 빌드가 돌고 있다'로 거부하면(일일 체인 [6a] 등) 10분 기다렸다 다시(최대 18회 = 3시간).
#   ⑤ build_hash 1회 ⑥ 월간 IC 재계산(compute_all_factor_ic_monthly) ⑦ 일간 · 월간 대응표 재측정(daily_monthly_parity.py)
#   ⑧ 결합용 팩터 뷰 첫 전체 빌드(factor_combinable.R --build --full — 고친 등록부 · 팩터 DB · IC 위에서 · 실패해도 수리 결과는 유지)
#   ⑨ 요약 JSON + 텔레그램 1통(성공 = 무음 · 실패 = 알림).
#
# 사용: bash 02_Infrastructure/factor_db/run_factor_subset_repair.sh <전체 재빌드 요약 JSON 경로> [--workers 3]
#       QVEST_RFS_SPEC=<수리 명세 JSON> bash 02_Infrastructure/factor_db/run_factor_subset_repair.sh --no-wait [--workers 3]
#         전체 재빌드 없이 명세의 대상 팩터만(2026-11-10 · 명세 = {targets, modules, decision, title} · 예 04_Research/01_reports/factor_db_debt_fix_20261110/repair_spec.json)
#       bash 02_Infrastructure/factor_db/run_factor_subset_repair.sh --resume <STAMP>
#         재개 = ①~③ 건너뛰고 그 STAMP 의 작업자 기록으로 ④ 검사부터(⑤~⑧ 이 실패했을 때 · 같은 로그에 이어 쓰고 앞 요약은 .prev_* 로 남긴다)
# 띄우기 — 세션과 떼어서(★Claude 도구 셸의 Start-Process 는 도구가 끝날 때 함께 죽는다 · SWITCH_RUNBOOK §5 와 같이 WMI):
#   Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{ CommandLine = '"C:\Program Files\Git\bin\bash.exe" -c "cd /g/OneDrive/Quant_Module_Moltbot && bash 02_Infrastructure/factor_db/run_factor_subset_repair.sh <json> > .cache/scheduler_logs/<이름>.out.log 2>&1"' }
#==============================================================================
set -u
ROOT="${QM_ROOT_BASH:-/g/OneDrive/Quant_Module_Moltbot}"
# R 문자열 안에 넣으므로 슬래시로 — 사용자 환경변수 QM_ROOT 는 'C:\Users\…' 라 R 이 '\U' 를 이스케이프로 읽고 멈췄다
# (11-10 01:14 첫 실행 ⑤ build_hash · ⑥ IC · 텔레그램이 모두 이 오류로 실패)
QM_ROOT="${QM_ROOT:-G:/OneDrive/Quant_Module_Moltbot}"
export QM_ROOT="${QM_ROOT//\\//}"
RS="C:/Program Files/R/R-4.6.2/bin/Rscript.exe"
PY="$ROOT/.venv_qvest_ml/Scripts/python.exe"
TOOL="$ROOT/02_Infrastructure/factor_db/rebuild_factor_subset.R"
RESUME=""; NO_WAIT=""
if [ "${1:-}" = "--resume" ]; then
  RESUME="${2:?--resume 뒤에 STAMP(예 20261109_175958)가 필요하다}"; WAIT_JSON=""; shift 2
elif [ "${1:-}" = "--no-wait" ]; then
  # 2026-11-10: 전체 재빌드 없이 고친 코드 · 입력으로 대상만 다시(예: 총부채 수리) — ① 을 건너뛴다. 다른 빌드가 돌면 작업자가
  #   쓰기를 거부하고 10분마다 다시 시도한다(run_worker · 최대 3시간). 대상 · 모듈은 QVEST_RFS_SPEC 명세(rebuild_factor_subset.R).
  NO_WAIT=1; WAIT_JSON=""; shift
else
  WAIT_JSON="${1:?전체 재빌드 요약 JSON 경로가 필요하다(또는 --no-wait · --resume STAMP)}"; shift
fi
# 수리 명세(있으면): 결정 ID · 알림 제목 꼬리 — 없으면 11-09 수리의 값 그대로
RFS_DECISION="FACTOR-DIRECTION-STORAGE-REPAIR-20261109"; RFS_TITLE="재무 v2"
if [ -n "${QVEST_RFS_SPEC:-}" ]; then
  [ -f "$QVEST_RFS_SPEC" ] || { echo "수리 명세 파일이 없다: $QVEST_RFS_SPEC" >&2; exit 2; }
  RFS_DECISION=$("$PY" -I -c "import json,sys; print(json.load(open(sys.argv[1], encoding='utf-8')).get('decision') or '')" "$(cygpath -w "$QVEST_RFS_SPEC")" 2>/dev/null | tr -d '\r')
  RFS_TITLE=$("$PY" -I -c "import json,sys; print(json.load(open(sys.argv[1], encoding='utf-8')).get('title') or '')" "$(cygpath -w "$QVEST_RFS_SPEC")" 2>/dev/null | tr -d '\r')
  [ -n "$RFS_DECISION" ] || { echo "수리 명세에 decision 이 없다: $QVEST_RFS_SPEC" >&2; exit 2; }
  export QVEST_RFS_SPEC
fi
NW=3
if [ "${1:-}" = "--workers" ] && [ -n "${2:-}" ]; then NW="$2"; fi
STAMP="${RESUME:-$(date +%Y%m%d_%H%M%S)}"
LOGDIR="$ROOT/.cache/scheduler_logs"
LOG="$LOGDIR/factor_subset_repair_$STAMP.log"
SUMMARY="$LOGDIR/factor_subset_repair_$STAMP.json"
if [ -n "$RESUME" ]; then
  ls "$LOGDIR"/subset_worker_"${STAMP}"_r*_w*.jsonl > /dev/null 2>&1 || { echo "재개할 작업자 기록이 없다: $STAMP" >&2; exit 2; }
  [ -f "$SUMMARY" ] && mv "$SUMMARY" "${SUMMARY%.json}.prev_$(date +%Y%m%d_%H%M%S).json"
fi
T0=$(date +%s)
say() { echo "[$(date '+%m-%d %H:%M:%S')] $*" | tee -a "$LOG"; }

others() {
  powershell.exe -NoProfile -Command "Get-CimInstance Win32_Process | Where-Object { \$_.CommandLine -match 'factor_db_builder|factor_db_daily_phase|run_fdb_rebuild|run_factor_db_full_rebuild' -and \$_.CommandLine -notmatch 'Get-CimInstance|rebuild_factor_subset|run_factor_subset_repair' } | ForEach-Object { \$_.ProcessId }" 2>/dev/null | tr -d '\r' | xargs
}

finish() {  # $1 = 결과(성공/실패) $2 = 한 줄
  local secs=$(( $(date +%s) - T0 ))
  cat > "$SUMMARY" <<JS
{"schema": "factor_subset_repair/v1", "stamp": "$STAMP", "result": "$1", "note": "$2", "workers": $NW,
 "months_total": ${N_MONTHS:-0}, "redo_rounds": ${ROUNDS:-0}, "redo_left": "${REDO_LEFT:-}", "ic_rc": "${IC_RC:-skip}",
 "parity_rc": "${PAR_RC:-skip}", "combinable_rc": "${FC_RC:-skip}", "seconds": $secs, "log": "$(printf '%s' "$LOG" | tr '\\' '/')",
 "decision": "$RFS_DECISION", "spec": "$(printf '%s' "${QVEST_RFS_SPEC:-}" | tr '\\' '/')"}
JS
  say "요약: $SUMMARY"
  local mute="TRUE"; [ "$1" = "성공" ] || mute="FALSE"
  local rfile="$LOGDIR/_tg_factor_subset_repair_${STAMP}.R"
  cat > "$rfile" <<RS
suppressWarnings(suppressMessages(source(file.path("$QM_ROOT", "02_Infrastructure", "telegram", "telegram_notify.R"))))
res <- tryCatch(tg_agent_brief(
  agent = "Q-Lead", title = "[데이터] 팩터 DB 결함 수리 재계산 $1 — ${N_FAC:+영향 ${N_FAC}팩터 · }${RFS_TITLE}${RESUME:+ (재개)}",
  relaxed = TRUE, force = TRUE, mute = $mute, lock_scope = "factor_subset_repair_$STAMP",
  sections = list(
    list(type = "summary", body = "팩터 DB 결함 수리 재계산 $1 — ${RFS_TITLE}"),
    list(type = "text", heading = "결과", body = "$2"),
    list(type = "kv", heading = "단계", kv = list(
      "재계산" = "작업자 $NW · 달 ${N_MONTHS:-0} · 다시 한 회차 ${ROUNDS:-0} · 남은 달 ${REDO_LEFT:-없음}",
      "IC" = "rc ${IC_RC:-skip}", "대응표" = "rc ${PAR_RC:-skip}", "결합용 뷰" = "rc ${FC_RC:-skip}",
      "요약" = "$(printf '%s' "$SUMMARY" | tr '\\' '/')"))
  )), error = function(e) { cat("tg fail:", conditionMessage(e), "\n"); quit(save = "no", status = 1L) })
# 2026-11-10: 요약 줄(summary · 20~100자)에 긴 결과 문장을 넣어 11-10 09:01 실행의 알림이 102자로 거부됐다(tg fail 만 남고 rc 0 이라
#   아래 '발송 실패' 줄도 안 떴다) — 요약 = 짧은 제목 · 결과 문장 = text 섹션 · 발송 실패 = rc 1.
RS
  "$RS" --no-save "$rfile" >> "$LOG" 2>&1 || say "텔레그램 발송 실패(요약 파일은 남음)"
}

# ---- ① 전체 재빌드 끝 대기 ------------------------------------------------------------------
if [ -n "$NO_WAIT" ]; then
  say "① 전체 재빌드 대기 없음(--no-wait · 명세 ${QVEST_RFS_SPEC:-없음} · 결정 $RFS_DECISION) — 다른 빌드가 돌면 작업자가 기다린다"
elif [ -z "$RESUME" ]; then
  say "① 전체 재빌드 끝 대기: $WAIT_JSON"
  n=0
  until [ -f "$WAIT_JSON" ] && [ -z "$(others)" ]; do
    n=$((n + 1)); [ "$n" -gt 120 ] && { finish "실패" "전체 재빌드가 10시간 안에 끝나지 않았다 — 재계산 안 함"; exit 1; }
    sleep 300
  done
  RES=$("$PY" -I -c "import json,sys; print(json.load(open(sys.argv[1], encoding='utf-8')).get('result',''))" "$(cygpath -w "$WAIT_JSON")" 2>/dev/null | tr -d '\r')
  say "전체 재빌드 결과 = $RES"
  if [ "$RES" != "성공" ]; then finish "실패" "전체 재빌드 결과가 '$RES' — 부분 재빌드 위에 덧칠하지 않는다(재계산 안 함)"; exit 1; fi
else
  say "재개 — ①~③ 건너뜀(작업자 기록 $STAMP 그대로) · ④ 검사부터"
fi

# ---- ② 달 목록 ---------------------------------------------------------------------------------
CUR="${STAMP:0:6}"   # 이번 달 = 첫 실행의 달(재개가 달을 넘겨도 같은 달을 뺀다 · 그 뒤 생긴 달은 ④ 검사가 다시 할 달로 잡는다)
mapfile -t MONTHS < <(ls "$ROOT/.cache/factor_db" | sed -n 's/^factor_db_\([0-9]\{6\}\)\.parquet$/\1/p' | sort | grep -v "^$CUR\$")
N_MONTHS=${#MONTHS[@]}
say "② 달 ${N_MONTHS}개(이번 달 $CUR 제외) · 작업자 $NW"
declare -a LISTS
for i in "${!MONTHS[@]}"; do k=$(( i % NW )); LISTS[$k]="${LISTS[$k]:-}${LISTS[$k]:+,}${MONTHS[$i]}"; done

run_worker() {  # $1 = 작업자 번호 $2 = 달 목록 $3 = 회차 → rc 0 = 끝 · 2 = 다른 빌드로 거부(기다렸다 다시) · 1 = 실패
  local k="$1" ms="$2" r="$3" tries=0 rc out
  local wlog="$LOGDIR/subset_worker_${STAMP}_r${r}_w${k}.jsonl" wout="$LOGDIR/subset_worker_${STAMP}_r${r}_w${k}.out"
  local wlog_w; wlog_w=$(cygpath -m "$wlog")
  while :; do
    "$RS" --no-save "$(cygpath -m "$TOOL")" --months "$ms" --log "$wlog_w" --no-hash > "$wout" 2>&1; rc=$?
    if [ "$rc" -ne 0 ] && grep -q '다른 팩터 빌드가 돌고 있다' "$wout"; then
      tries=$((tries + 1)); [ "$tries" -gt 18 ] && { echo "[w$k] 3시간 기다려도 다른 빌드" >> "$LOG"; return 1; }
      sleep 600; continue
    fi
    return "$rc"
  done
}

# ---- ③ 작업자 병렬 ----------------------------------------------------------------------------
if [ -z "$RESUME" ]; then
  say "③ 작업자 $NW 개 시작"
  declare -a PIDS
  for k in $(seq 0 $((NW - 1))); do
    [ -n "${LISTS[$k]:-}" ] || continue
    run_worker "$k" "${LISTS[$k]}" 0 & PIDS[$k]=$!
  done
  WRC=0
  for k in "${!PIDS[@]}"; do wait "${PIDS[$k]}" || WRC=1; done
  say "③ 작업자 끝(rc 모음 $WRC — 1 이어도 ④ 검사가 판정한다)"
fi
# 대상 팩터 수 = 작업자 기록의 per_factor(알림 표제 · 끝 문장 — 손으로 적은 수는 어긋났다: '12' 대 실제 13)
N_FAC=$(tail -n 1 "$LOGDIR/subset_worker_${STAMP}_r0_w0.jsonl" 2>/dev/null \
  | "$PY" -I -c "import json,sys; print(len(json.loads(sys.stdin.read()).get('per_factor') or {}))" 2>/dev/null | tr -d '\r')
[ "${N_FAC:-0}" -gt 0 ] 2>/dev/null || N_FAC=""

# ---- ④ 잃은 쓰기 검사 → 다시 ---------------------------------------------------------------
ROUNDS=0; REDO_LEFT=""
for r in 1 2 3; do
  LOGS=$(ls "$LOGDIR"/subset_worker_"${STAMP}"_r*_w*.jsonl 2>/dev/null | tr '\n' ',' | sed 's/,$//')
  LOGS_W=$(echo "$LOGS" | tr ',' '\n' | while read -r f; do [ -n "$f" ] && cygpath -m "$f"; done | tr '\n' ',' | sed 's/,$//')
  REDO=$("$RS" --no-save "$(cygpath -m "$TOOL")" --verify "$LOGS_W" --exclude "$CUR" 2>>"$LOG" | sed -n 's/^REDO: *//p' | tr -d ' \r')
  if [ -z "$REDO" ]; then REDO_LEFT=""; break; fi
  REDO_LEFT="$REDO"
  [ "$r" -eq 3 ] && break
  ROUNDS=$r
  say "④ 다시 할 달 $(echo "$REDO" | tr ',' '\n' | wc -l)개 — 회차 $r"
  run_worker 9 "$REDO" "$r" || say "④ 회차 $r 작업자 실패"
done
if [ -n "$REDO_LEFT" ]; then finish "실패" "재계산 뒤에도 고치지 못한 달이 남았다: $(echo "$REDO_LEFT" | cut -c1-200)"; exit 1; fi
say "④ 모든 달 수리 확인(잃은 쓰기 없음)"

# ---- ⑤ build_hash · ⑥ IC · ⑦ 대응표 -------------------------------------------------------
"$RS" --no-save -e "setwd('$QM_ROOT/02_Infrastructure'); suppressMessages(source('config.R')); invisible(capture.output(source('factor_db/factor_db_builder.R'))); .write_build_hash()" >> "$LOG" 2>&1
say "⑥ 월간 IC 재계산 시작"
t6=$(date +%s)
"$RS" --no-save -e "setwd('$QM_ROOT/02_Infrastructure'); source('config.R'); source('factor_db/factor_db_builder.R'); compute_all_factor_ic_monthly()" >> "$LOG" 2>&1; IC_RC=$?
say "⑥ IC rc=$IC_RC · $(( ($(date +%s) - t6) / 60 ))분"
"$PY" -I "$ROOT/02_Infrastructure/factor_db/daily_monthly_parity.py" >> "$LOG" 2>&1; PAR_RC=$?
say "⑦ 대응표 rc=$PAR_RC"
if [ "$IC_RC" -ne 0 ]; then finish "실패" "재계산은 끝났으나 IC 재계산 실패(rc $IC_RC) — compute_all_factor_ic_monthly() 를 다시 돌릴 것"; exit 1; fi
say "⑧ 결합용 팩터 뷰 전체 빌드 시작"
t8=$(date +%s)
"$RS" --no-save "$(cygpath -m "$ROOT/02_Infrastructure/factor_db/factor_combinable.R")" --build --full >> "$LOG" 2>&1; FC_RC=$?
say "⑧ 결합용 뷰 rc=$FC_RC · $(( ($(date +%s) - t8) / 60 ))분"
finish "성공" "영향 ${N_FAC:-?}팩터를 고친 코드 · ${RFS_TITLE} 로 전 기간 다시 계산했다(달 $N_MONTHS · 이번 달 $CUR 은 빠졌다 — rebuild_factor_subset.R --months $CUR 로 따로) · IC · 대응표 갱신 · 결합용 뷰 rc ${FC_RC:-skip}"
exit 0
