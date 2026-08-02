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
# 종료코드: 0 = 최신 보장됨(또는 no-op) / 3 = 리프레시 후에도 stale 잔존(브리핑은
#   계속하되 그 사실이 보고돼야 한다) / 1 = 실행 불가(루트/스크립트 부재)
#
# 사용:
#   ensure_data_current.sh                 # 감사 → 필요 시 refresh → 재감사
#   ensure_data_current.sh --check-only    # 감사만 (refresh 안 함)
#   ensure_data_current.sh --max-wait 3600 # 진행 중 refresh 대기 상한(초, 기본 2400)
#==============================================================================
set -uo pipefail

CHECK_ONLY=0
MAX_WAIT="${QVEST_EDC_MAX_WAIT:-2400}"     # 기본 40분 — 실측 완주 47분 중 잔여를 덮는 값
while [ "$#" -gt 0 ]; do
  case "$1" in
    --check-only) CHECK_ONLY=1 ;;
    --max-wait)   shift; MAX_WAIT="${1:-2400}" ;;
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
RSCRIPT="${RSCRIPT:-Rscript}"
mkdir -p "$BASE/.cache" 2>/dev/null || true

_ts() { date '+%Y-%m-%dT%H:%M:%S%z'; }
_log() { echo "[edc $(date '+%H:%M:%S')] $*"; }

[ -f "$AUDIT_R" ] || { _log "❌ 감사기 부재: $AUDIT_R"; exit 1; }

# ── 1) 진행 중 리프레시 대기 ────────────────────────────────────────────────
# 여기서 기다리지 않으면 아래 감사가 "갱신 중 스냅샷"을 재고, 그 판정으로 브리핑이 나간다.
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
    sleep 20; waited=$((waited + 20))
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
_audit() { # $1=quiet(1/0)  → stdout: "<stale>|<as_of>"
  local out line
  out="$(QVEST_FRESHNESS_QUIET="$1" "$RSCRIPT" --no-save "$AUDIT_R" 2>&1 | tr -d '\r')"
  line="$(printf '%s\n' "$out" | grep -E '^EDC_RESULT ' | tail -1)"
  if [ -z "$line" ]; then
    printf '%s\n' "$out" | tail -5 >&2
    echo "NA|NA"; return 0
  fi
  printf '%s|%s\n' \
    "$(printf '%s' "$line" | sed -n 's/.*stale=\([0-9]\+\).*/\1/p')" \
    "$(printf '%s' "$line" | sed -n 's/.*as_of=\([0-9-]\+\).*/\1/p')"
}

PRE="$(_audit 1)"; PRE_STALE="${PRE%%|*}"; AS_OF="${PRE##*|}"
_log "사전 감사: as_of=$AS_OF stale=$PRE_STALE"

_stamp() { # $1=verdict $2=stale $3=note
  printf '{"ran_at":"%s","as_of":"%s","verdict":"%s","stale_count":%s,"note":"%s"}\n' \
    "$(_ts)" "$AS_OF" "$1" "${2:-0}" "$3" > "$STAMP" 2>/dev/null || true
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
if [ -f "$STAMP" ]; then
  _prev_as_of="$(sed -n 's/.*"as_of":"\([^"]*\)".*/\1/p' "$STAMP" 2>/dev/null)"
  _prev_verdict="$(sed -n 's/.*"verdict":"\([^"]*\)".*/\1/p' "$STAMP" 2>/dev/null)"
  if [ "$_prev_as_of" = "$AS_OF" ] && [ "$_prev_verdict" = "stale_after_refresh" ]; then
    _log "⚠ as_of=$AS_OF 는 이미 리프레시했으나 stale=$PRE_STALE 잔존 — **재시도하지 않음**"
    _log "   (리프레시로 고쳐지지 않는 항목이다. 생산자 배선을 봐야 한다: qepm/observability/morning_freshness_latest.json 의 stale_items)"
    _stamp "stale_unfixable_by_refresh" "$PRE_STALE" "재시도 생략(같은 영업일 재발)"
    exit 3
  fi
fi
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
_log "stale=$PRE_STALE — daily_refresh.sh 실행"
QVEST_REFRESH_TG="${QVEST_REFRESH_TG:-0}" bash "$REFRESH_SH"; RRC=$?
_log "daily_refresh 종료코드=$RRC"

# ── 5) 재감사 — ★"돌렸다"로 끝내지 않는다 ───────────────────────────────────
# 오늘 실측이 이 단계의 존재 이유다: 리프레시가 "실패 0" 으로 완주했는데도
# benchmark MISSING · p3_forecast STALE 이 남아 있었다. 실행을 성공으로 세면
# 그 2건은 영원히 안 보인다.
POST="$(_audit 0)"; POST_STALE="${POST%%|*}"; AS_OF="${POST##*|}"
if [ "$POST_STALE" = "0" ]; then
  _log "✅ 리프레시 후 최신 확보 (as_of=$AS_OF)"
  _stamp "refreshed_current" 0 "refresh rc=$RRC"
  exit 0
fi
_log "⚠ 리프레시 후에도 stale=$POST_STALE 잔존 (as_of=$AS_OF) — 브리핑에 그대로 표기돼야 함"
_stamp "stale_after_refresh" "$POST_STALE" "refresh rc=$RRC wait_rc=$WAIT_RC"
exit 3
