#!/usr/bin/env bash
#==============================================================================
# ensure_data_current.sh — "브리핑이 최신영업일 데이터를 쓴다"를 실행 전에 보장한다
#
# 도훈 지시 2026-08-03: "모닝 브리핑들 최신영업일 데이터 자동반영 / 새벽에 컴퓨터
#   꺼두면 리프레시 누락 / 부팅 시점 재점검 / 이미 최신이면 실행하지 않게".
#
# ── 진단 (2026-08-03 실측, 오늘 로그) ────────────────────────────────────────
#   누락의 원인은 트리거 부재가 아니라 **경합**이었다. 트리거는 이미 있다:
#     Qvest_MorningReboot (로그온+3분) · Qvest_DailyRefresh (00:03, StartWhenAvailable)
#   PC 가 00:03 에 꺼져 있던 날의 실제 타임라인:
#     07:00:28  MorningReboot 실행
#     07:03:25  DailyRefresh **보충 실행 시작**
#     07:10:01  MorningBrief 발화   ← 리프레시가 아직 47분 남았다
#     07:50:03  DailyRefresh 완료
#   즉 브리핑은 "갱신 중인 디스크"를 읽고 렌더했다. morning_briefing.sh 의 self-heal
#   층(4.5)은 "daily_refresh 03:00 → 브리핑 07:10" 을 전제로 설계돼, 보충 실행이
#   브리핑 시각을 덮는 날에는 **동시에 돌면서** 서로를 못 본다.
#
# ── 설계 원칙 ────────────────────────────────────────────────────────────────
# ★"오늘 리프레시를 돌렸는가"로 판단하지 않는다 — **데이터가 실제로 최신인가**로 판단한다.
#   이 저장소가 반복해서 데인 계통이 정확히 "존재 검사로 정체성 검사를 대체"하는 것이고,
#   오늘이 그 실례다: DailyRefresh 는 완주해 "실패 0" 을 보고했는데 같은 아침 감사가
#   benchmark=MISSING · p3_forecast=STALE(lag 4d) 2건을 잡았다. 실행 = 최신 이 아니다.
# ★신선도 판정을 여기서 다시 구현하지 않는다. 정본은 freshness_audit.R 하나뿐이다
#   (as_of = 거래일 캘린더 기반 직전 영업일, 소스별 max_lag). 같은 값을 두 곳에서
#   만들면 반드시 갈라진다 — 벤치마크 2소스 사고와 같은 기전.
# ★진행 중인 리프레시가 있으면 **기다린다**. daily_refresh.sh 의 락은 중복 인스턴스를
#   `exit 0` 으로 끝내므로, 그냥 호출하면 "돌렸다"고 착각한 채 즉시 반환된다.
#
# ★부팅 규칙(도훈 2026-10-17 "복잡하게 가지말고 부팅시점에 최신화 안되어있으면 퀀티로그인해서 최신화시킨다로 정리해" ·
#   "공휴일정보 찾아서 붙여" · 결정 BOOT-QW-LOGIN-REFRESH-20261017): 위 감사에 **퀀티 최신성** 한 축을 더 본다 —
#   벤치 최신일 < 직전 거래일(KRX 공식 휴장일 06_Registry/krx_holidays.json · krx_holidays.py)이면 리프레시 대상('qw')이고,
#   리프레시(daily_refresh.sh [1pre])의 퀀티 수급이 단말을 띄우고 로그인한다. 호출 지점 = PC 부팅(morning_run.sh reboot ·
#   주말 포함) · 아침 브리핑 [0/5] · /qvest 부팅(백그라운드).
#
# 종료코드: 0 = 최신 보장됨(또는 no-op) / 3 = 리프레시 후에도 stale 잔존(브리핑은
#   계속하되 그 사실이 보고돼야 한다) / 1 = 실행 불가(루트/스크립트 부재)
#
# 사용:
#   ensure_data_current.sh                 # 감사 → 필요 시 refresh → 재감사
#   ensure_data_current.sh --check-only    # 감사만 (refresh 안 함)
#   ensure_data_current.sh --max-wait 3600 # 진행 중 refresh 대기 상한(초, 기본 2400)
#   ensure_data_current.sh --retry         # 같은 영업일 재시도 가드를 건너뛰고 다시 복구(원인을 고친 뒤 · 수동)
#==============================================================================
set -uo pipefail

CHECK_ONLY=0
FORCE_RETRY=0
MAX_WAIT="${QVEST_EDC_MAX_WAIT:-2400}"     # 기본 40분 — 실측 완주 47분 중 잔여를 덮는 값
while [ "$#" -gt 0 ]; do
  case "$1" in
    --check-only) CHECK_ONLY=1 ;;
    --max-wait)   shift; MAX_WAIT="${1:-2400}" ;;
    --retry)      FORCE_RETRY=1 ;;   # 사람이 원인을 고친 뒤(예: 퀀티 재로그인) — 같은 영업일 재시도 가드를 건너뛴다
    *) echo "[edc] 알 수 없는 인자: $1" >&2 ;;
  esac
  shift
done

# 루트 해석 — ops 계열(QM_ROOT-first). daily_refresh.sh 와 같은 resolver 를 쓴다.
_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=/dev/null
source "$_SELF_DIR/resolve_project.sh" 2>/dev/null || true
BASE="${BASE:-${PROJECT:-}}"
if [ -z "${BASE:-}" ] || [ ! -f "$BASE/02_Infrastructure/hooks/qvest_hook_router.py" ]; then
  echo "[edc] ❌ 프로젝트 루트 해석 실패 — 표지 미확인" >&2
  exit 1
fi
cd "$BASE" || exit 1

AUDIT_JSON="$BASE/qepm/observability/morning_freshness_latest.json"
REFRESH_SH="$BASE/02_Infrastructure/data/daily_refresh.sh"
AUDIT_R="$BASE/02_Infrastructure/ops/morning_steps/freshness_audit.R"
LOCKDIR="/tmp/qm_daily_refresh.lock"
STAMP="$BASE/.cache/data_currency_stamp.json"
HEAL_MARK="$BASE/.cache/data_currency_last_heal"   # "<as_of> <epoch>" — 마지막으로 자가 복구를 실제로 띄운 시각(3b 재시도 규칙이 읽는다)
_now_epoch() { case "${QVEST_EDC_NOW_EPOCH:-}" in ""|*[!0-9]*) date +%s ;; *) printf "%s\n" "$QVEST_EDC_NOW_EPOCH" ;; esac; }   # 시험용 시각 주입
RSCRIPT="${RSCRIPT:-Rscript}"
mkdir -p "$BASE/.cache" 2>/dev/null || true

_ts() { date '+%Y-%m-%dT%H:%M:%S%z'; }
_log() { echo "[edc $(date '+%H:%M:%S')] $*"; }

[ -f "$AUDIT_R" ] || { _log "❌ 감사기 부재: $AUDIT_R"; exit 1; }

# ── 1) 진행 중 리프레시 대기 ────────────────────────────────────────────────
# 여기서 기다리지 않으면 아래 감사가 "갱신 중 스냅샷"을 재고, 그 판정으로 브리핑이 나간다.
EDC_WAITED_S=0
_wait_running() {
  local waited=0 pid
  while [ -d "$LOCKDIR" ]; do
    pid="$(cat "$LOCKDIR/pid" 2>/dev/null || echo '')"
    if [ -z "$pid" ] || ! kill -0 "$pid" 2>/dev/null; then
      _log "진행 중 리프레시 없음 (stale lock PID=${pid:-?}) — 계속"
      return 0
    fi
    if [ "$waited" -ge "$MAX_WAIT" ]; then
      _log "⚠ 리프레시(PID=$pid) 대기 상한 ${MAX_WAIT}s 초과 — 기다리지 않고 현 상태로 판정"
      return 2
    fi
    [ "$waited" = 0 ] && _log "리프레시 진행 중(PID=$pid) — 완료까지 대기 (상한 ${MAX_WAIT}s)"
    sleep 20; waited=$((waited + 20)); EDC_WAITED_S=$waited
  done
  [ "$waited" -gt 0 ] && _log "리프레시 완료 감지 (대기 ${waited}s)"
  return 0
}
_wait_running; WAIT_RC=$?

# ── 2) 신선도 감사 (정본 재사용) ────────────────────────────────────────────
# 사전 감사는 텔레그램 경보를 내지 않는다 — 이 단계는 "고칠지 말지" 결정용이고,
# 고쳐지면 사용자에게 갈 이유가 없다. 사후 감사에서만 알린다(중복 경보 방지).
# 감사기가 직접 뱉는 EDC_RESULT 줄만 읽는다 (판정 생산자 == 판정 보고자).
#   ★CRLF 제거 필수 — Windows R stdout 은 CRLF 라 CR 이 값에 남으면 "0" != "0\r" 로
#     비교가 조용히 어긋난다([[reference-rscript-stdout-crlf-bash-compare]]).
#   ★출력 없음(감사기 사망)은 "stale 0" 으로 내려앉히지 않는다 — NA 로 올려 보낸다.
_audit() { # $1=quiet(1/0)  → stdout: "<stale>|<as_of>|<items>"
  local out line
  out="$(QVEST_FRESHNESS_QUIET="$1" "$RSCRIPT" --no-save "$AUDIT_R" 2>&1 | tr -d '\r')"
  line="$(printf '%s\n' "$out" | grep -E '^EDC_RESULT ' | tail -1)"
  if [ -z "$line" ]; then
    printf '%s\n' "$out" | tail -5 >&2
    echo "NA|NA|-"; return 0
  fi
  printf '%s|%s|%s\n' \
    "$(printf '%s' "$line" | sed -n 's/.*stale=\([0-9]\+\).*/\1/p')" \
    "$(printf '%s' "$line" | sed -n 's/.*as_of=\([0-9-]\+\).*/\1/p')" \
    "$(printf '%s' "$line" | sed -n 's/.*items=\([^ ]*\).*/\1/p')"
}

# ── 리프레시가 **고칠 수 있는** 항목만 판단에 쓴다 ───────────────────────────
# ★모든 stale 을 한 덩어리로 세면 안 된다. p3_forecast 는 daily_refresh 의 산출물이
#   아니라 **morning_briefing 자신의 산출물**이다(step 6a 가 601_daily_inference.py
#   --model P3 로 만든다). 이걸 "리프레시가 필요하다"의 근거로 세면, 리프레시를
#   아무리 돌려도 값이 안 변하므로 **부팅할 때마다 47분짜리 전체 리프레시가 돈다**.
#   실측 근거(2026-08-03 브리핑 로그 901·906행): 07:10 브리핑이 benchmark.parquet
#   부재로 601 추론에 실패 → p3_forecast 가 07-27 에 멈춘 것. 즉 p3 는 *결과*이지
#   *원인*이 아니다. 원인(benchmark 등 입력)이 제때 있으면 브리핑이 스스로 만든다.
# 여기 목록은 "브리핑 하류 산출물" — 판단에서 제외하되 **보고에는 남긴다**.
DOWNSTREAM_OUTPUTS="p3_forecast"
_actionable() { # $1=items(csv) → stdout: "<n>|<actionable csv>|<excluded csv>"
  local items="$1" a="" x="" it
  [ "$items" = "-" ] && { echo "0||"; return 0; }
  IFS=',' read -r -a _arr <<< "$items"
  for it in ${_arr[@]+"${_arr[@]}"}; do
    [ -n "$it" ] || continue
    case " $DOWNSTREAM_OUTPUTS " in
      *" $it "*) x="$x${x:+,}$it" ;;
      *)         a="$a${a:+,}$it" ;;
    esac
  done
  local n=0
  [ -n "$a" ] && n=$(printf '%s' "$a" | tr ',' '\n' | grep -c .)
  printf '%s|%s|%s\n' "$n" "$a" "$x"
}

PRE="$(_audit 1)"
PRE_STALE="$(printf '%s' "$PRE" | cut -d'|' -f1)"
AS_OF="$(printf '%s' "$PRE" | cut -d'|' -f2)"
PRE_ITEMS="$(printf '%s' "$PRE" | cut -d'|' -f3)"
_ACT="$(_actionable "$PRE_ITEMS")"
PRE_ACT_N="$(printf '%s' "$_ACT" | cut -d'|' -f1)"
PRE_ACT="$(printf '%s' "$_ACT" | cut -d'|' -f2)"
PRE_EXCL="$(printf '%s' "$_ACT" | cut -d'|' -f3)"
_log "사전 감사: as_of=$AS_OF stale=$PRE_STALE (리프레시 대상 ${PRE_ACT_N}건${PRE_ACT:+: $PRE_ACT})"
[ -n "$PRE_EXCL" ] && _log "   ※ 하류 산출물이라 리프레시 대상 아님: $PRE_EXCL (브리핑 step 6a 가 생산 — 입력이 제때 있으면 스스로 갱신)"
# 판단은 '리프레시가 고칠 수 있는' 항목으로만 한다. 단 PRE_STALE 은 보고에 계속 쓴다.
[ "$PRE_STALE" = "NA" ] || PRE_STALE="$PRE_ACT_N"

# ── 2b) 퀀티 최신성 — 부팅 규칙(BOOT-QW-LOGIN-REFRESH-20261017) ─────────────────
# ★퀀티 단일에서는 거래일 캘린더(= 벤치)도 퀀티가 늘린다 — 퀀티가 멈추면 위 감사의 as_of 도 같이 멈춰 '최신'으로 읽힌다(순환).
#   그래서 캘린더를 안 쓰는 기준을 하나 더 본다: 벤치 최신일 < 직전 거래일(KRX 공식 휴장일) → 리프레시 대상 'qw'.
#   가드(3b) · 스탬프의 영업일 키도 KRX 직전 거래일로 둔다 — 퀀티가 멈춰도 다음 거래일엔 키가 바뀌어 다시 시도한다.
#   판정 불가(휴장일 미수록 · 판독 실패)는 이 축만 '미측정'으로 적고 위 감사 판정을 그대로 쓴다.
# venv 우선 — daily_refresh.sh [1pre] 와 같은 순서(사용자 환경변수 QVEST_PY 는 시스템 Python312 라 pandas · pyarrow 가 없다 · 10-17 실측)
PYX="$BASE/.venv_qvest_ml/Scripts/python.exe"; [ -x "$PYX" ] || PYX="${QVEST_PY:-python}"
_qw_state() { # → stdout: "<behind 0|1|NA>|<bench_max>|<expected 또는 사유>" — 판정 정본 = krx_holidays.py bench_currency
  local s; s="$("$PYX" "$BASE/02_Infrastructure/data/krx_holidays.py" currency 2>/dev/null | tr -d '\r' | tail -n 1)"
  case "$s" in [01]\|*|NA\|*) echo "$s" ;; *) echo "NA|?|판정기 무응답" ;; esac
}
QW="$(_qw_state)"; QW_BEHIND="${QW%%|*}"; _qr="${QW#*|}"; QW_BM="${_qr%%|*}"; QW_EXP="${_qr#*|}"
case "$QW_BEHIND" in
  1) _log "★퀀티 최신 아님 — 벤치 최신일 $QW_BM < 직전 거래일 $QW_EXP(KRX 휴장일 기준) → 리프레시 대상 'qw'(퀀티 로그인 · 최신화)"
     [ "$PRE_STALE" = "NA" ] || PRE_STALE=$((PRE_STALE + 1))
     PRE_ACT="${PRE_ACT}${PRE_ACT:+,}qw" ;;
  0) _log "퀀티 최신 — 벤치 최신일 $QW_BM ≥ 직전 거래일 $QW_EXP" ;;
  *) _log "⚠ 퀀티 최신성 미측정(직전 거래일=$QW_EXP · 벤치=$QW_BM) — 위 감사 판정만 쓴다" ;;
esac
case "$QW_EXP" in [0-9][0-9][0-9][0-9]-*) AS_OF="$QW_EXP" ;; esac

_stamp() { # $1=verdict $2=stale $3=note
  printf '{"ran_at":"%s","as_of":"%s","verdict":"%s","stale_count":%s,"note":"%s","qw":"%s"}\n' \
    "$(_ts)" "$AS_OF" "$1" "${2:-0}" "$3" "${QW:-NA}" > "$STAMP" 2>/dev/null || true
}

# ── 3) 이미 최신이면 실행하지 않는다 (도훈 지시의 가드) ──────────────────────
if [ "$PRE_STALE" = "0" ]; then
  _log "✅ 이미 최신 (as_of=$AS_OF) — 리프레시 실행 안 함"
  _stamp "already_current" 0 "no-op"
  exit 0
fi

# ── 3b) 같은 영업일에 **이미 시도했고 안 고쳐진** 경우 재시도하지 않는다 ─────
# ★이 가드가 없으면 위 stale 조건이 영구 참이 되는 항목 하나 때문에 부팅할 때마다
#   47분짜리 전체 리프레시가 돈다. 실례: p3_forecast 는 저장소 안에 **생산자가 없다**
#   (P3_daily.parquet / P3_latest.json 둘 다 2026-07-27 21:39 임시 실행 산물, 이후
#   daily_refresh 어느 스텝도 이 파일을 쓰지 않는다). 리프레시로 고쳐질 수 없는 항목에
#   리프레시를 반복하는 것은 비용만 태우고 "고쳤다"는 착시만 만든다.
# ★단 **조용히 넘어가지 않는다** — 고쳐지지 않은 항목을 매번 로그에 남기고 rc=3 을 준다.
#   "재시도 안 함"이 "문제 없음"으로 읽히면 이 저장소가 반복해 데인 그 계통이다.
# ★(2026-11-11 도훈 "자가 복구 실행되게 배선해줘") 재시도 규칙을 둘로 가른다:
#   ① 리프레시로 안 고쳐지는 항목(생산자 없음 등) — 종전대로 같은 영업일에는 다시 돌지 않는다.
#      (종전 결함: 막을 때 표식을 stale_unfixable_by_refresh 로 바꿔 쓰는데 가드는 stale_after_refresh 만 봐서, 한 번 걸러 한 번 다시 돌았다.)
#   ② 퀀티 미갱신(벤치 최신일 < 직전 거래일) — 나중에 고쳐질 수 있는 원인이다(단말 재로그인 · 원격 값 도착). 마지막 복구 시도 뒤
#      자가 복구 시간 상한(QVEST_EDC_HEAL_TIMEOUT_MIN · 기본 150분 — 한 번의 복구가 쓸 수 있는 최대 시간)이 지나면 같은 영업일에도 다시 시도한다.
#      그 전에는 막는다(부팅 직후 · 아침 브리핑처럼 붙어 있는 호출이 연달아 퀀티 단말을 두드리지 않게). 끄기 = QVEST_EDC_QW_RETRY=0.
#      낮 시간 호출 지점 = ops/data_selfheal_tick.sh(예약 작업 Qvest_StandingBoard 매시 37분).
#   ③ --retry — 사람이 원인을 고친 뒤 수동으로: 가드를 건너뛴다.
RETRY_GAP_S="${QVEST_EDC_QW_RETRY_GAP_S:-$(( ${QVEST_EDC_HEAL_TIMEOUT_MIN:-150} * 60 ))}"
if [ -f "$STAMP" ] && [ "$FORCE_RETRY" != "1" ]; then
  _prev_as_of="$(sed -n 's/.*"as_of":"\([^"]*\)".*/\1/p' "$STAMP" 2>/dev/null)"
  _prev_verdict="$(sed -n 's/.*"verdict":"\([^"]*\)".*/\1/p' "$STAMP" 2>/dev/null)"
  if [ "$_prev_as_of" = "$AS_OF" ] && { [ "$_prev_verdict" = "stale_after_refresh" ] || [ "$_prev_verdict" = "stale_unfixable_by_refresh" ]; }; then
    _retry=0; _gap="-"
    if [ "$QW_BEHIND" = "1" ] && [ "${QVEST_EDC_QW_RETRY:-1}" != "0" ]; then
      _lh_as_of=""; _lh_ep=""
      [ -f "$HEAL_MARK" ] && read -r _lh_as_of _lh_ep < "$HEAL_MARK" 2>/dev/null
      case "$_lh_ep" in ""|*[!0-9]*) _lh_ep="" ;; esac
      if [ "$_lh_as_of" != "$AS_OF" ] || [ -z "$_lh_ep" ]; then
        # 이 거래일의 마지막 시도 시각을 모른다(규칙 도입 전 표식 등) → 지금부터 센다(바로 다시 돌지 않는다)
        _lh_ep="$(_now_epoch)"; printf '%s %s\n' "$AS_OF" "$_lh_ep" > "$HEAL_MARK" 2>/dev/null || true
      fi
      _gap=$(( $(_now_epoch) - _lh_ep ))
      [ "$_gap" -ge "$RETRY_GAP_S" ] && _retry=1
    fi
    if [ "$_retry" != "1" ]; then
      _log "⚠ as_of=$AS_OF 는 이미 리프레시했으나 stale=$PRE_STALE 잔존 — **재시도하지 않음**$( [ "$_gap" != "-" ] && echo " (퀀티 재시도까지 $(( RETRY_GAP_S - _gap ))초 남음)" )"
      _log "   (리프레시로 고쳐지지 않는 항목이다. 생산자 배선을 봐야 한다: qepm/observability/morning_freshness_latest.json 의 stale_items)"
    [ "$QW_BEHIND" = "1" ] && _log "   ★qw = 이 거래일($QW_EXP)의 퀀티 로그인 · 수급이 이미 한 번 실패했다 — 단말 로그인 확인(daily_refresh.log [1pre] · .cache/quantiwise_fetch_status.json). 다음 거래일 또는 00:03 밤 리프레시가 다시 시도한다"
      _stamp "stale_unfixable_by_refresh" "$PRE_STALE" "재시도 생략(같은 영업일 재발)"
      exit 3
    fi
    _log "↻ 같은 영업일 재시도 — 퀀티 미갱신은 나중에 고쳐질 수 있는 원인이다(마지막 복구 시도 뒤 ${_gap}초 ≥ ${RETRY_GAP_S}초)"
  fi
fi
[ "$FORCE_RETRY" = "1" ] && _log "↻ --retry — 같은 영업일 재시도 가드를 건너뛴다(수동)"
if [ "$PRE_STALE" = "NA" ]; then
  _log "⚠ 감사 결과를 읽지 못함 — 미상은 '최신'이 아니다. 리프레시로 진행"
fi

if [ "$CHECK_ONLY" = "1" ]; then
  _log "stale=$PRE_STALE 이나 --check-only 이므로 리프레시 생략"
  _stamp "stale_check_only" "$PRE_STALE" "check-only"
  exit 3
fi

# ── 4) 리프레시 ─────────────────────────────────────────────────────────────
[ -f "$REFRESH_SH" ] || { _log "❌ 리프레시 스크립트 부재: $REFRESH_SH"; exit 1; }
# ★(2026-11-10 감사 레인 A · 도훈 '아침 자가 복구 = 실패한 단계만') 11-10 실측: 07:14 자가 복구가 전 체인(DART 31분 · 후처리 · 시험
#   배터리 2시간 56분)을 다시 돌려 12:15 에 끝났고, 예약 작업 상한(3시간 12분) 초과로 MorningBrief 가 종료(267014)된 뒤에도 자식이
#   고아로 남았다. 실패 rc=1 은 QVEST_REFRESH_TG=0 이라 아무에게도 안 갔다. 이제:
#   ① 계획 = data/dr_heal_plan.py(밤 실행 상태 .cache/daily_refresh_state.json · 실패/미완 단계 + 하류 · 모르면 전부)
#   ② 자가 복구 모드(QVEST_DR_MODE=selfheal) — 후처리 · 시험 배터리 없음(QVEST_DR_SKIP_BATTERY=1)
#   ③ 보고 1통 = daily_refresh [7] 이 실패 서명 관문을 거쳐 보낸다(QVEST_DR_REPORT_TG=1 · 같은 원인 반복은 무음 요약) ·
#      그 보고가 나갔으면 아래 사후 감사는 발송하지 않는다(중복 방지) · 시간 상한 초과면 여기서 1통(_edc_notify)
#   ④ 시간 상한 = QVEST_EDC_HEAL_TIMEOUT_MIN(기본 150분) — 근거: daily_refresh.log 적재 구간(머리 → [7.9] 시작) 실측 15회 중
#      13회 ≤ 104분(10-05 33 · 10-07 37 · 10-06 39 · 10-20 42 · 10-10 47 · 10-17 49 · 11-10 61 · 10-04 69 · 10-08 69 · 11-08 69 · 10-16 72 ·
#      11-10 자가 복구 104 — 퀀티 kicked 대기 63분 포함), 예외 = 10-18 206 · 11-09 294 · 11-07 415(이전 직후 전체 수급). 예약 작업 상한
#      192분 − 150 = 42분을 사전 · 사후 감사(각 1분 안쪽)와 브리핑 본체(11-09 실측 약 4분)에 남긴다. 넘기면 자식 트리까지 끝낸다.
DR_STATE_JSON="$BASE/.cache/daily_refresh_state.json"
HEAL_PLAN="FULL"; HEAL_WHY="planner_absent"
PLANNER="$BASE/02_Infrastructure/data/dr_heal_plan.py"
if [ -f "$PLANNER" ]; then
  _qwb=0; [ "$QW_BEHIND" = "1" ] && _qwb=1
  _pl="$("$PYX" -X utf8 "$PLANNER" --state "$DR_STATE_JSON" --today "$(date +%F)" --stale "${PRE_ITEMS:--}" --qw-behind "$_qwb" 2>/dev/null | tr -d '\r' | grep '^DR_HEAL' | tail -n 1)"
  HEAL_PLAN="$(printf '%s' "$_pl" | sed -n 's/.*plan=\([^	]*\).*/\1/p')"; HEAL_WHY="$(printf '%s' "$_pl" | sed -n 's/.*reason=\(.*\)$/\1/p')"
  [ -n "$HEAL_PLAN" ] || { HEAL_PLAN="FULL"; HEAL_WHY="planner_no_output"; }
fi
_ONLY=""; [ "$HEAL_PLAN" != "FULL" ] && _ONLY="$HEAL_PLAN"
HEAL_TIMEOUT_S="${QVEST_EDC_HEAL_TIMEOUT_S:-$(( ${QVEST_EDC_HEAL_TIMEOUT_MIN:-150} * 60 ))}"
# (11-10 적대적 검토 2차) 상한은 예약 작업 상한(192분)에서 역산한 값이라, 앞서 진행 중 리프레시를 기다린 시간(최대 MAX_WAIT 40분)을 뺀다 —
#   안 빼면 대기 40 + 복구 150 + 감사 · 브리핑이 192분을 넘어 작업이 강제 종료되고 자손 정리 · 알림이 실행되지 않는다(11-10 사고 경로).
#   초 단위 상한을 직접 준 경우(QVEST_EDC_HEAL_TIMEOUT_S — 시험 · 수동)는 그 값을 그대로 쓴다. 남는 시간이 10분 미만이면 10분.
if [ -z "${QVEST_EDC_HEAL_TIMEOUT_S:-}" ] && [ "${EDC_WAITED_S:-0}" -gt 0 ]; then
  HEAL_TIMEOUT_S=$(( HEAL_TIMEOUT_S - EDC_WAITED_S )); [ "$HEAL_TIMEOUT_S" -lt 600 ] && HEAL_TIMEOUT_S=600
fi
_edc_notify() {   # 1통 — 모의 발송기(QVEST_EDC_TG_MOCK=<파일>) · 무인 실행(QVEST_UNATTENDED=1)만 실발송 · 그 밖은 로그만
  if [ -n "${QVEST_EDC_TG_MOCK:-}" ]; then printf '%s\n' "$1" >> "$QVEST_EDC_TG_MOCK"; return 0; fi
  [ "${QVEST_UNATTENDED:-0}" = "1" ] || { _log "(발송 생략 — 무인 실행 아님) $1"; return 0; }
  local rf; rf="$(mktemp "${TMPDIR:-/tmp}/qm_edc_tg_XXXX.R")" || return 0
  printf 'setwd("%s/02_Infrastructure")\nsource("config.R")\nsource("telegram/telegram_notify.R")\ninvisible(tryCatch(tg_send(Sys.getenv("QVEST_EDC_MSG")), error = function(e) cat("TG send failed:", conditionMessage(e), "\\n")))\n' "$BASE" > "$rf"
  QVEST_EDC_MSG="$1" "$RSCRIPT" --no-save "$rf" >/dev/null 2>&1; rm -f "$rf"
}
_desc_pids() {   # $1 = MSYS pid → 자손 MSYS pid 전부(ps PPID 재귀 — Git Bash 의 fork 는 윈도 부모 관계를 남기지 않을 때가 있다 · 11-10 시험 실측)
  local p; for p in $(ps -ef 2>/dev/null | awk -v pp="$1" 'NR > 1 && $3 == pp { print $2 }'); do echo "$p"; _desc_pids "$p"; done
}
_kill_tree() {   # $1 = MSYS pid — 자손(MSYS) 전부 + 각자의 윈도 트리(Rscript · python · powershell 의 네이티브 자식)까지 끝낸다
  local all p wp; all="$(_desc_pids "$1") $1"
  for p in $all; do wp="$(cat "/proc/$p/winpid" 2>/dev/null)"; [ -n "$wp" ] && taskkill //F //T //PID "$wp" >/dev/null 2>&1; done
  for p in $all; do kill -KILL "$p" 2>/dev/null; done
}
_log "stale=$PRE_STALE — daily_refresh.sh 자가 복구 실행 · 계획 ${HEAL_PLAN} (${HEAL_WHY}) · 상한 ${HEAL_TIMEOUT_S}s"
_launch_mark="$(mktemp "${TMPDIR:-/tmp}/qm_edc_launch_XXXX")"; touch -d "@$(( $(date +%s) - 1 ))" "$_launch_mark" 2>/dev/null   # 이번 실행 뒤에 쓰인 상태만 '보고됨'으로 읽는다
printf '%s %s\n' "$AS_OF" "$(_now_epoch)" > "$HEAL_MARK" 2>/dev/null || true   # 3b 재시도 규칙의 기준 시각
QVEST_REFRESH_TG="${QVEST_REFRESH_TG:-0}" QVEST_DR_MODE=selfheal QVEST_DR_ONLY_STAGES="$_ONLY" QVEST_DR_SKIP_BATTERY=1 \
  QVEST_DR_REPORT_TG="${QVEST_DR_REPORT_TG:-1}" bash "$REFRESH_SH" &
RPID=$!; _t0=$(date +%s); TIMED_OUT=0
while kill -0 "$RPID" 2>/dev/null; do
  if [ $(( $(date +%s) - _t0 )) -ge "$HEAL_TIMEOUT_S" ]; then
    TIMED_OUT=1; _log "⚠ 자가 복구 리프레시가 상한 ${HEAL_TIMEOUT_S}s 를 넘김 — 프로세스 트리 종료(PID=$RPID)"
    _kill_tree "$RPID"
    _lp="$(cat "$LOCKDIR/pid" 2>/dev/null)"; [ "$_lp" = "$RPID" ] && rm -rf "$LOCKDIR"   # 죽인 실행의 잠금만 치운다
    break
  fi
  sleep "${QVEST_EDC_POLL_S:-10}"
done
wait "$RPID" 2>/dev/null; RRC=$?
[ "$TIMED_OUT" = "1" ] && RRC=124
_log "daily_refresh 종료코드=$RRC"
REPORTED=0
if [ -f "$DR_STATE_JSON" ] && [ "$DR_STATE_JSON" -nt "$_launch_mark" ] && grep -q '"mode":"selfheal"' "$DR_STATE_JSON" \
   && grep -q '"reported":1' "$DR_STATE_JSON"; then REPORTED=1; fi
rm -f "$_launch_mark" 2>/dev/null
if [ "$TIMED_OUT" = "1" ]; then
  _edc_notify "[자가 복구] daily_refresh 가 ${HEAL_TIMEOUT_S}초 상한을 넘겨 중단했습니다 — 계획 ${HEAL_PLAN} · 데이터 기준일 ${AS_OF} · 로그 /tmp/qm_daily_refresh_$(date +%Y%m%d).log"
elif [ "$RRC" -ne 0 ] && [ "$REPORTED" = "0" ]; then
  _edc_notify "[자가 복구] daily_refresh 가 보고 단계 전에 끝났습니다(rc=$RRC) — 계획 ${HEAL_PLAN} · 로그 /tmp/qm_daily_refresh_$(date +%Y%m%d).log"
fi

# ── 5) 재감사 — ★"돌렸다"로 끝내지 않는다 ───────────────────────────────────
# 오늘 실측이 이 단계의 존재 이유다: 리프레시가 "실패 0" 으로 완주했는데도
# benchmark MISSING · p3_forecast STALE 이 남아 있었다. 실행을 성공으로 세면
# 그 2건은 영원히 안 보인다.
_post_quiet=0; { [ "$REPORTED" = "1" ] || [ "$TIMED_OUT" = "1" ] || [ "$RRC" -ne 0 ]; } && _post_quiet=1   # 보고 1통은 위에서 이미 나갔다
POST="$(_audit "$_post_quiet")"
POST_STALE="$(printf '%s' "$POST" | cut -d'|' -f1)"
AS_OF="$(printf '%s' "$POST" | cut -d'|' -f2)"
_PACT="$(_actionable "$(printf '%s' "$POST" | cut -d'|' -f3)")"
POST_ACT_N="$(printf '%s' "$_PACT" | cut -d'|' -f1)"
POST_ACT="$(printf '%s' "$_PACT" | cut -d'|' -f2)"
_log "사후 감사: stale=$POST_STALE (리프레시 대상 잔여 ${POST_ACT_N}건${POST_ACT:+: $POST_ACT})"
[ "$POST_STALE" = "NA" ] || POST_STALE="$POST_ACT_N"
QW="$(_qw_state)"; QW_BEHIND="${QW%%|*}"; _qr="${QW#*|}"; QW_BM="${_qr%%|*}"
case "$QW_EXP" in [0-9][0-9][0-9][0-9]-*) AS_OF="$QW_EXP" ;; esac
if [ "$QW_BEHIND" = "1" ]; then
  _log "⚠ 리프레시 후에도 퀀티 최신 아님 — 벤치 $QW_BM < 직전 거래일 $QW_EXP (퀀티 로그인 실패 또는 원격 미갱신 · daily_refresh.log [1pre] · .cache/quantiwise_fetch_status.json)"
  [ "$POST_STALE" = "NA" ] || POST_STALE=$((POST_STALE + 1))
fi
if [ "$POST_STALE" = "0" ]; then
  _log "✅ 리프레시 후 최신 확보 (as_of=$AS_OF)"
  _stamp "refreshed_current" 0 "refresh rc=$RRC"
  exit 0
fi
_log "⚠ 리프레시 후에도 stale=$POST_STALE 잔존 (as_of=$AS_OF) — 브리핑에 그대로 표기돼야 함"
_stamp "stale_after_refresh" "$POST_STALE" "refresh rc=$RRC wait_rc=$WAIT_RC"
exit 3
