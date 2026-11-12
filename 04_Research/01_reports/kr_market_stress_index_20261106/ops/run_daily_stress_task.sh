#!/usr/bin/env bash
# run_daily_stress_task.sh — 예약 작업(Qvest_StressDaily) 실행기. 도훈 11-06 결정 "별도 예약 작업" · 같은 날 "매일 아침 받아보고 싶다 · 노트북 활성화 · 메인 PC 에서도".
#   ① 데이터 준비를 감시한다(60초 간격 · 마감 STRESS_DEADLINE 기본 23:30 — 도훈 11-13 "데이터가 늦게 최신화되더라도 최신 데이터가 감지되면 자동으로 생성").
#      준비 = 셋 다 만족:
#      (a) 밤 데이터 리프레시 잠금(/tmp/qm_daily_refresh.lock)이 없다
#      (b) 벤치(퀀티) 최신일 ≥ KRX 직전 거래일 — 정본 판정 = 02_Infrastructure/data/krx_holidays.py currency(부팅 · ensure_data_current 와 같은 판정)
#         ★(b) 를 둔 이유: 04:00 에 리프레시가 아직 시작 전이면 잠금이 없어 (a) 만으로는 묵은 데이터로 일보가 나간다.
#      (c) RAWDATA 최신일 ≥ KRX 직전 거래일(아래 rawdata_state)
#   ② 준비되면 run_daily_stress.sh(ECOS/FRED 직접 수급 → 지수 v1 → 차트 → PDF · 엑셀 → 메일)를 돌린다.
#   ③ 그 뒤에도 마감까지 입력 캐시(RAWDATA · investor_wide · benchmark · indices)의 최신일을 지켜본다 — 새 데이터가 감지되면
#      체인을 다시 돌려 같은 기준일 일보를 최신 입력으로 갈아 끼운다(예: 외국인 수급이 RAWDATA 보다 늦게 들어오는 날 · 11-12 판 실측).
#      외국인 수급(investor_wide)까지 직전 거래일에 닿으면 끝낸다. 메일은 기준일당 1통(send_daily_mail.py 의 mail_sent.json)이라 다시 돌아도 중복 발송하지 않는다.
#   ④ 종료 코드 = 마지막 체인의 종료 코드(작업 스케줄러 LastTaskResult) · 마감까지 한 번도 준비되지 않으면 rc 7(그날 건너뜀 — 묵은 데이터로 일보를 내지 않는다).
#      '직전 거래일'은 오늘 이전 마지막 거래일이라 하루 안에서 바뀌지 않는다(krx_holidays.py::last_session_before).
#      로그 = 감싼 실행기 로그(.cache/scheduler_logs/stress_daily.log) + daily/logs/task_*.log.
#   예약 작업의 실행 상한(ExecutionTimeLimit)은 마감보다 길어야 한다(make_task_xml.ps1 = PT20H · 04:00 시작 → 24:00).
# 리프레시 · daily_refresh.sh 는 건드리지 않는다(원 세션 소유).
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REP="$(cd "$HERE/.." && pwd)"
ROOT="$(cd "$REP/../../.." && pwd)"
PY="$ROOT/.venv_qvest_ml/Scripts/python.exe"
LOCK="${QVEST_REFRESH_LOCK:-/tmp/qm_daily_refresh.lock}"
DEADLINE="${STRESS_DEADLINE:-23:30}"          # 같은 날 이 시각까지 감시(HH:MM · 다음 밤 리프레시 전)
MAX_WAIT_MIN="${STRESS_MAX_WAIT_MIN:-}"        # (선택) 시작 기준 분 단위 상한 — 마감과 둘 중 이른 쪽. 시험용(0 = 즉시 마감)
POLL_SEC="${STRESS_POLL_SEC:-60}"
CHAIN_CMD="${STRESS_CHAIN_CMD:-bash $REP/run_daily_stress.sh}"   # 시험 때만 바꾼다
CACHE="$ROOT/.cache"
RAW_PQ="${QVEST_STRESS_RAWDATA:-$CACHE/RAWDATA.parquet}"
INV_PQ="${QVEST_STRESS_INVESTOR:-$CACHE/investor_stock/investor_wide.parquet}"
BM_PQ="${QVEST_STRESS_BENCH:-$CACHE/benchmark.parquet}"
IX_PQ="${QVEST_STRESS_INDICES:-$CACHE/indices.parquet}"
LOG_DIR="$REP/daily/logs"; mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/task_$(date +%Y%m%d_%H%M%S).log"
say() { echo "[$(date '+%F %T')] $*" | tee -a "$LOG"; }
bench_state() {   # '0' 최신 · '1' 미최신 · 'NA' 판정 불가(판정 불가는 막지 않는다 — 리프레시 잠금이 1차 방어)
  [ "${STRESS_SKIP_BENCH_CHECK:-0}" = "1" ] && { echo "0|skip|skip"; return; }
  PYTHONUTF8=1 "$PY" "$ROOT/02_Infrastructure/data/krx_holidays.py" currency --no-fetch 2>/dev/null | tail -1
}

# (c) RAWDATA 최신일 ≥ KRX 직전 거래일 (2026-11-10 감사 레인 A · P6) — 벤치만 보면 RAWDATA 가 멈춘 날에도 시작한다.
#   11-10 실측: 벤치 11-09 · RAWDATA 11-06 인데 day=2026-11-09 일보가 나갔다 — 폭(B1~B3) · 유동성(L1 · L2) · 금융업(F1~F3) · 수급 축은
#   build_kr_stress_index.py::on_calendar 가 직전 관측(11-06)을 앞으로 채워 11-09 값으로 실었다(관측일 열에만 남는다).
#   직전 거래일 = (b) 판정의 세 번째 칸(krx_holidays.py currency). 판정 불가(NA)는 막지 않는다(bench_state 와 같은 규칙). 끄기: STRESS_SKIP_RAW_CHECK=1
rawdata_state() {   # $1 = 직전 거래일(YYYY-MM-DD) → '0|RAWDATA 최신일|직전 거래일' · '1|…' · 'NA|…'
  [ "${STRESS_SKIP_RAW_CHECK:-0}" = "1" ] && { echo "0|skip|skip"; return; }
  case "${1:-}" in [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;; *) echo "NA|?|${1:-?}"; return ;; esac
  PYTHONUTF8=1 "$PY" - "$RAW_PQ" "$1" <<'PYR' 2>/dev/null | tail -1 || echo "NA|unreadable|$1"
import sys, datetime as dt
try:
    import pyarrow.parquet as pq, pyarrow.compute as pc
    m = pc.max(pq.read_table(sys.argv[1], columns=["Date"])["Date"]).as_py()
    m = m.date() if isinstance(m, dt.datetime) else m
    e = dt.date.fromisoformat(sys.argv[2])
    print(("1" if m < e else "0") + "|" + m.isoformat() + "|" + e.isoformat())
except Exception as ex:
    print("NA|" + ex.__class__.__name__ + "|" + sys.argv[2])
PYR
}

# 입력 서명 = 네 입력 캐시의 최신일(RAWDATA · investor_wide · benchmark · indices). 바뀌면 '새 데이터'다.
input_sig() {
  PYTHONUTF8=1 "$PY" - "$RAW_PQ" "$INV_PQ" "$BM_PQ" "$IX_PQ" <<'PYS' 2>/dev/null | tail -1 || echo "NA|NA|NA|NA"
import sys, datetime as dt
out = []
for p in sys.argv[1:]:
    try:
        import pyarrow.dataset as ds, pyarrow.compute as pc
        m = pc.max(ds.dataset(p).to_table(columns=["Date"])["Date"]).as_py()
        out.append((m.date() if isinstance(m, dt.datetime) else m).isoformat())
    except Exception:
        out.append("NA")
print("|".join(out))
PYS
}

say "Qvest_StressDaily start · host=${COMPUTERNAME:-?} · lock=$LOCK · deadline=$DEADLINE${MAX_WAIT_MIN:+ · max_wait=${MAX_WAIT_MIN}m}"
# 오늘이 KRX 거래일이 아니면(주말 · 휴장일) 일보 · 메일 모두 건너뛴다(도훈 11-06 "주말이랑 휴장일엔 보낼 필요 없어").
#   직전 거래일 마감분은 다음 거래일 04:00 실행이 만든다(예: 금요일 마감 → 월요일 아침 · 휴장일 앞날 마감 → 휴장 다음 거래일 아침).
#   판정 = 06_Registry/krx_holidays.json(KRX 공시 목록 · 주말 아닌 휴장일). 그해가 등록부에 없으면 주말만 거른다(경고).
TODAY_ISO="${QVEST_KRX_TODAY:-$(date +%F)}"
sess="$(PYTHONUTF8=1 "$PY" - "$TODAY_ISO" "$ROOT/06_Registry/krx_holidays.json" <<'PYS' 2>/dev/null
import json, sys, datetime as dt
d = dt.date.fromisoformat(sys.argv[1]); reg = json.load(open(sys.argv[2], encoding="utf-8"))
hol, years = reg.get("holidays") or {}, {int(y) for y in reg.get("years") or []}
if d.weekday() >= 5: print("closed|주말")
elif d.isoformat() in hol: print("closed|" + hol[d.isoformat()])
elif d.year not in years: print("open|등록부에 " + str(d.year) + "년 없음(주말만 판정)")
else: print("open|거래일")
PYS
)"
case "$sess" in
  closed\|*) say "오늘($TODAY_ISO)은 휴장(${sess#closed|}) — 일보 · 메일 건너뜀"; exit 0 ;;
  open\|*)   say "오늘($TODAY_ISO) ${sess#open|} — 진행" ;;
  *)         say "★거래일 판정 실패(출력 '${sess}') — 진행(판정 불가는 막지 않는다)" ;;
esac

# 마감 시각(epoch 초) — 같은 날 DEADLINE · STRESS_MAX_WAIT_MIN 이 있으면 둘 중 이른 쪽
start_s=$(date +%s)
end_s=$(date -d "$(date +%F) $DEADLINE" +%s 2>/dev/null || echo $((start_s + 480 * 60)))
[ -n "$MAX_WAIT_MIN" ] && [ $((start_s + MAX_WAIT_MIN * 60)) -lt "$end_s" ] && end_s=$((start_s + MAX_WAIT_MIN * 60))
# 예약 작업 실행 상한(ExecutionTimeLimit)보다 15분 먼저 끝낸다 — 상한에 걸려 체인 도중 강제 종료되면 일보 파일이 반쯤 갱신된다.
#   11-13 등록본 상한 = PT9H12M(make_task_xml.ps1 이 PT20H 로 바뀌었지만 재등록 = install_task.ps1 · 관리자 · 도훈). 읽기 실패 = 상한 없음으로 본다.
if [ "${STRESS_SKIP_TASK_LIMIT:-0}" != "1" ]; then
  lim="$(powershell.exe -NoProfile -Command "(Get-ScheduledTask -TaskName Qvest_StressDaily -ErrorAction SilentlyContinue).Settings.ExecutionTimeLimit" 2>/dev/null | tr -d '\r' | tail -1)"
  lim_s="$(PYTHONUTF8=1 "$PY" -c "import re,sys; m=re.fullmatch(r'P(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?', sys.argv[1].strip()); print(0 if not m or not any(m.groups()) else sum(int(v or 0)*k for v,k in zip(m.groups(),(86400,3600,60,1))))" "${lim:-x}" 2>/dev/null || echo 0)"
  if [ "${lim_s:-0}" -gt 900 ] && [ $((start_s + lim_s - 900)) -lt "$end_s" ]; then
    end_s=$((start_s + lim_s - 900))
    say "예약 작업 실행 상한 ${lim} → 감시 마감을 $(date -d @"$end_s" '+%H:%M') 로 당김(상한 − 15분 · 늘리려면 install_task.ps1 재등록)"
  fi
fi
[ "$end_s" -lt "$start_s" ] && end_s=$start_s      # 마감 뒤에 시작했으면 한 번만 본다

built=0; rc=7; last_sig=""; waited=0; next_note=0
while :; do
  bs="$(bench_state)"; st="${bs%%|*}"; expd="${bs##*|}"
  rs="NA|-|-"; rst="NA"; ready=0
  if [ ! -e "$LOCK" ] && [ "$st" != "1" ]; then
    rs="$(rawdata_state "$expd")"; rst="${rs%%|*}"
    [ "$rst" != "1" ] && ready=1
  fi
  if [ "$ready" = 1 ]; then
    sig="$(input_sig)"
    if [ "$sig" != "$last_sig" ]; then
      if [ "$built" = 0 ]; then
        say "데이터 준비 확인($(( $(date +%s) - start_s ))s 대기 · 벤치 ${bs} · 입력 RAWDATA|수급|벤치|지수 = ${sig}) — 30초 뒤 시작"; sleep 30
        sig="$(input_sig)"
      else
        say "새 입력 감지(${last_sig} → ${sig}) — 같은 기준일 일보를 다시 만든다"
      fi
      say "run_daily_stress.sh 시작"
      $CHAIN_CMD >> "$LOG" 2>&1; rc=$?
      built=$((built + 1)); last_sig="$sig"
      say "run_daily_stress.sh 종료 rc=$rc(${built}번째) · latest=$(tr -d '\n' < "$REP/daily/latest/latest.json" 2>/dev/null | cut -c1-160)"
    fi
    inv="$(echo "$last_sig" | cut -d'|' -f2)"
    case "$expd" in [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;; *) expd="" ;; esac
    if [ "$rc" = 0 ] && { [ -z "$expd" ] || [ "$inv" \> "$expd" ] || [ "$inv" = "$expd" ]; }; then
      say "입력 전부 최신(수급 ${inv} ≥ 직전 거래일 ${expd:-?}) — 종료"
      break
    fi
  fi
  if [ "$(date +%s)" -ge "$end_s" ]; then
    if [ "$built" -gt 0 ]; then
      say "마감($DEADLINE) — 일보 ${built}회 생성 · 마지막 rc=$rc · 입력 ${last_sig}(외국인 수급이 직전 거래일 ${expd:-?} 에 못 닿음 — 일보의 자료 시점 열에 표시됨)"
    else
      say "★마감($DEADLINE)까지 데이터 준비 안 됨(잠금 $([ -e "$LOCK" ] && echo 있음 || echo 없음) · 벤치 ${bs} · RAWDATA ${rs}) — 오늘은 건너뜀(묵은 데이터로 일보를 내지 않는다)"
      rc=7
    fi
    break
  fi
  if [ "$waited" -ge "$next_note" ]; then
    if [ "$built" = 0 ]; then say "대기 — 리프레시 잠금 $([ -e "$LOCK" ] && echo 있음 || echo 없음) · 벤치 상태 ${bs}(state|벤치 최신일|직전 거래일) · RAWDATA ${rs} · ${waited}s"
    else say "감시 — 일보 생성 뒤 새 입력 대기(입력 ${last_sig} · 직전 거래일 ${expd:-?}) · ${waited}s"; fi
    next_note=$((waited + 600))
  fi
  sleep "$POLL_SEC"; waited=$((waited + POLL_SEC))
done
exit $rc
