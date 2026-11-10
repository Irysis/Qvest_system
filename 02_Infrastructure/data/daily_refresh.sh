#!/usr/bin/env bash
#==============================================================================
# Daily Data Refresh v2 — 매일 0시3분 실행
# crontab: 3 0 * * * bash "...daily_refresh.sh"
#
# 파이프라인 (v2 — Universe xlsx 의존 제거, Factor DB 연결):
#   [0] QuantiWise xlsx 증분 (OHLCVS/Consensus/Fundamental/Investor/Support)
#   [1pre] 벤치(KOSPI200 · 퀀티 정본) → [1pre-qw] 퀀티 Update_File 4종 매일 수급 → [0b'] 적재
#   ★(2026-10-17 도훈 · 결정 RAWDATA-QW-ONLY-20261017) RAWDATA 주가 원천 = 퀀티 단일 — 구 [1] Naver T+0 · [2] KRX gap-fill 퇴역(호출 0)
#   [3] Universe 갱신 (RAWDATA 월말 활성) + RAWDATA 메타 매핑
#   [4] Arrow/FRED/KTRI/Regime
#   [5] DART (월 1회)
#   [6] Factor DB 갱신
#   [7] Telegram + NAV
#==============================================================================
set -uo pipefail

# ── 실행 사본 (2026-11-10 감사 레인 A · P2) — bash 는 스크립트를 실행하면서 조금씩 읽는다. 돌고 있는 원본을 고치면
#   읽던 자리가 밀려 엉뚱한 줄을 실행한다(09-18 exit_2 · 11-10 10:08 편집 → 실행 중 후처리 구문 오류). 시작 때 자신을
#   임시 사본으로 떠서 사본을 exec 한다(같은 pid — 잠금 · 예약 작업 rc 불변). 원본 디렉터리는 QVEST_DR_SRC_DIR 로 넘긴다.
#   사본 실패면 원본으로 계속(막지 않는다). 끄기: QVEST_DR_NO_SNAPSHOT=1 · 시험: 08_Tests/scenarios/test_scn_data_refresh_heal.sh
if [ -z "${QVEST_DR_SNAPSHOT:-}" ] && [ "${QVEST_DR_NO_SNAPSHOT:-0}" != "1" ]; then
  _dr_self="${BASH_SOURCE[0]:-$0}"
  _dr_srcdir="$(cd "$(dirname "$_dr_self")" && pwd)"
  find "${TMPDIR:-/tmp}" -maxdepth 1 -name 'qm_dr_snapshot_*.sh' -mtime +2 -delete 2>/dev/null
  if _dr_snap="$(mktemp "${TMPDIR:-/tmp}/qm_dr_snapshot_XXXXXX.sh")" && cp "$_dr_self" "$_dr_snap"; then
    export QVEST_DR_SNAPSHOT="$_dr_snap" QVEST_DR_SRC_DIR="$_dr_srcdir"
    exec "${BASH:-bash}" "$_dr_snap" "$@"
  fi
fi
DR_SRC_DIR="${QVEST_DR_SRC_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)}"
DR_DRYRUN=0; for _a in "$@"; do [ "$_a" = "--dry-run" ] && DR_DRYRUN=1; done

if [ "$DR_DRYRUN" = "0" ]; then
LOGFILE="/tmp/qm_daily_refresh_$(date +%Y%m%d).log"
exec > >(tee -a "$LOGFILE") 2>&1
fi

echo "=== Daily Refresh v2 @ $(date) ==="
[ -n "${QVEST_DR_SNAPSHOT:-}" ] && echo "[snapshot] 실행 사본 $QVEST_DR_SNAPSHOT (원본 $DR_SRC_DIR/daily_refresh.sh — 실행 중 편집 무관)"

# ── 재진입 가드 (2026-06-11): 동시 2+ 인스턴스가 DART 쿼터 소진(10905종목 × N중복)·캐시 경합 유발 ──
#   실증: 2026-06-10 21:31/21:32 + 06-11 00:03/07:55/08:24 — 12시간 내 5중복 관측
LOCKDIR="/tmp/qm_daily_refresh.lock"
if [ "$DR_DRYRUN" = "1" ]; then
  echo "[dry-run] 잠금 · 적재 · 발송 없음 — 단계 계획만 출력"
elif mkdir "$LOCKDIR" 2>/dev/null; then
  echo $$ > "$LOCKDIR/pid"
  trap 'rm -rf "$LOCKDIR"' EXIT
else
  _oldpid=$(cat "$LOCKDIR/pid" 2>/dev/null)
  if [ -n "${_oldpid:-}" ] && kill -0 "$_oldpid" 2>/dev/null; then
    echo "[guard] daily_refresh 이미 실행 중 (PID=$_oldpid) — 중복 인스턴스 종료 (정상)"
    exit 0
  fi
  echo "[guard] stale lock (PID=${_oldpid:-?} 사망) — 인계"
  echo $$ > "$LOCKDIR/pid"
  trap 'rm -rf "$LOCKDIR"' EXIT
fi

source "$DR_SRC_DIR/../ops/resolve_project.sh"
INFRA="$BASE/02_Infrastructure"

# ── Telegram 실발송 가드 (v8.1.1 2026-06-10) ────────────────────────────────
#   QVEST_REFRESH_TG=0 (기본) → tg_send/telegram_alert/send_telegram 전부 skip, 로그만.
#   운영 cron만 1로 켬 (ops/scheduler/Qvest_DailyRefresh.bat에서 export).
export QVEST_REFRESH_TG="${QVEST_REFRESH_TG:-0}"
echo "[guard] QVEST_REFRESH_TG=$QVEST_REFRESH_TG (0=telegram 발송 skip)"

# ── Rscript 해석 (PATH 미등록 머신 fallback — v8.1.1) ────────────────────────
RSCRIPT="$(command -v Rscript || true)"
if [ -z "$RSCRIPT" ]; then
  for _r in "/c/Program Files/R/R-4.5.2/bin/Rscript.exe" "/c/Program Files/R"/R-*/bin/Rscript.exe; do
    [ -x "$_r" ] && RSCRIPT="$_r" && break
  done
fi
if [ -z "$RSCRIPT" ]; then
  echo "[FATAL] Rscript not found (PATH + /c/Program Files/R/*) — abort"
  exit 1
fi
echo "[env] RSCRIPT=$RSCRIPT"

# ── run_r: Windows Rscript 멀티라인 -e 함정(첫 줄만 실행) 회피 (v8.1.1) ──────
#   temp .R 파일 경유 실행. R 코드 본문은 호출부 single-quote 블록 그대로 보존.
#──────────────────────────────────────────────────────────────────────────────
# (2026-07-26 DR-01 수리, probe② 감사 확정 · 도훈 승인) run_r 은 rc 를 성실히 반환하지만
#   **검사하는 호출부가 0곳**이었다(22개 전부 미검사) + set -e 부재 + 마지막 명령이 echo
#   → 스크립트는 **항상 exit 0**. tryCatch 밖 실패(config.R source 실패, library(arrow)
#   로드 실패, Rscript 세그폴트 = 이 저장소의 실측 실패부류)가 나면 그 스텝의 R 에러만
#   로그에 남고 [7] 이 "[Daily Refresh v2 완료]" 를 무조건 발송하고 exit 0 한다.
#   소비자(.bat, bootstrap 백그라운드)는 exit code 를 안 읽으므로 실패 표면이 0개 —
#   스텝 절반이 죽어도 크론 관점에선 매일 성공이었다.
#   수리: 호출부 22곳을 건드리지 않고 run_r 자신이 실패를 누적한다(단일 지점).
#         종료 시 실패 목록을 이름으로 출력 + 비-0 종료 + 텔레그램 본문에도 병기.
#   (2026-11-06 · 적대 검토 #16 · #20) 선택 2번째 인자 = DR_FAILED 이름표. 주면 'r<N>(rc=..)' 대신 '<이름표>(rc=..)'
#     로 싣는다 — 스텝 번호는 앞에 블록이 늘면 밀려 [7] 실패 서명(dr_fail_signature.R)이 흔들리므로, 경보를 이름으로
#     읽어야 하는 블록(MSM as-of)만 쓴다. 이름표에 공백 금지(요약은 공백 구분). 인자 없는 호출부는 종전 그대로(r<N>).
#──────────────────────────────────────────────────────────────────────────────
DR_FAILED=()
DR_STEP=0
run_r() {
  local _tmp _rc _id
  DR_STEP=$((DR_STEP + 1))
  _id="${2:-r${DR_STEP}}"
  _tmp=$(mktemp /tmp/qm_refresh_XXXX.R) || {
    echo "[run_r] mktemp failed"; DR_FAILED+=("${_id}:mktemp"); return 1; }
  printf '%s\n' "$1" > "$_tmp"
  "$RSCRIPT" --no-save "$_tmp"
  _rc=$?
  rm -f "$_tmp"
  if [ "$_rc" -ne 0 ]; then
    DR_FAILED+=("${_id}(rc=$_rc)")
    echo "[run_r] ★r${DR_STEP}${2:+(${2})} FAILED rc=$_rc — 체인은 계속되나 최종 종료코드·요약에 반영됨"
  fi
  return $_rc
}
# 실패 요약 문자열 (set -u 안전 — 빈 배열 확장 회피)
dr_fail_summary() {
  if [ "${#DR_FAILED[@]}" -eq 0 ]; then printf '없음'; else printf '%s' "${DR_FAILED[*]}"; fi
}

# ── 단계 · 실행 상태 (2026-11-10 감사 레인 A · 도훈 지시 '아침 자가 복구 = 실패한 단계만') ─────────────────────────
#   적재 구간을 단계 8개로 묶는다(순서 = 이 파일의 실행 순서): ingest([0a][0b]) · qw([1pre]~[1z] 벤치 · 신규 상장 · 퀀티 4종 · 재적재 ·
#   확장 · 벤치 게이트 · Size) · universe([3][3b]) · macro([4] Arrow · FRED · KTRI · MSM · 국면 · ECOS · [4gm] · 셀 감사) ·
#   dart([5a][5b]) · krf([5c]) · fdb([6a]~[6.5]) · nonret(국민연금 · 관세청). [0c] 적재 검증 · [7] 보고는 늘 돈다.
#   단계 끝마다 상태 파일(.cache/daily_refresh_state.json)에 '단계:ok|failed:초' 를 적는다 — 실패 = 그 단계 안에서 DR_FAILED 가 늘었다.
#   아침 자가 복구(ops/ensure_data_current.sh)는 이 파일을 data/dr_heal_plan.py 로 읽어 실패 · 미완 단계와 그 하류만
#   QVEST_DR_ONLY_STAGES=a,b,… 로 넘긴다(비면 전부). 모드 QVEST_DR_MODE=selfheal 이면 후처리([7.9]~[8.2] · NAV · 증류)와
#   시험 배터리([9])를 건너뛴다(밤 실행이 이미 돌렸다 · 아침 브리핑 지연 원인).
DR_MODE="${QVEST_DR_MODE:-full}"
DR_ONLY="${QVEST_DR_ONLY_STAGES:-}"
DR_STAGES_ORDER="ingest qw universe macro dart krf fdb nonret"
DR_STAGE_REC=(); DR_SKIPPED=(); DR_CUR=""; DR_CUR_N0=0; DR_CUR_T0=0; DR_REPORTED=0
DR_RUN_T0=$(date +%s); DR_RUN_DATE=$(date +%F); DR_RUN_AT=$(date '+%Y-%m-%dT%H:%M:%S')
dr_selected() { [ -z "$DR_ONLY" ] && return 0; case ",$DR_ONLY," in *",$1,"*) return 0 ;; esac; return 1; }
dr_want() {   # 단계를 돌릴지 — 건너뛰면 로그 1줄
  if dr_selected "$1"; then return 0; fi
  echo "[stage] $1 건너뜀 — 자가 복구 대상 아님(QVEST_DR_ONLY_STAGES=$DR_ONLY)"; DR_SKIPPED+=("$1"); return 1
}
dr_stage_begin() { DR_CUR="$1"; DR_CUR_N0=${#DR_FAILED[@]}; DR_CUR_T0=$(date +%s); echo "[stage] $1 시작 $(date +%H:%M:%S)"; }
dr_stage_end() {
  local st=ok; [ "${#DR_FAILED[@]}" -gt "$DR_CUR_N0" ] && st=failed
  DR_STAGE_REC+=("$DR_CUR:$st:$(( $(date +%s) - DR_CUR_T0 ))"); echo "[stage] $DR_CUR 끝 · $st · $(( $(date +%s) - DR_CUR_T0 ))초"
  dr_state_write running
}
_dr_js() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
dr_state_write() {   # $1 = running | done · $2 = 종료 코드(done 때)
  [ "$DR_DRYRUN" = "1" ] && return 0
  local f="${QVEST_DR_STATE:-$BASE/.cache/daily_refresh_state.json}" tmp i s="" fl=""
  for i in "${DR_STAGE_REC[@]+"${DR_STAGE_REC[@]}"}"; do s="$s${s:+,}{\"name\":\"${i%%:*}\",\"status\":\"$(printf '%s' "$i" | cut -d: -f2)\",\"sec\":${i##*:}}"; done
  for i in "${DR_FAILED[@]+"${DR_FAILED[@]}"}"; do fl="$fl${fl:+,}\"$(_dr_js "$i")\""; done
  tmp="$f.tmp$$"
  printf '{"schema":"daily_refresh_state_v1","run_date":"%s","started_at":"%s","mode":"%s","only":"%s","status":"%s","rc":%s,"reported":%s,"stages":[%s],"failed":[%s],"stale_names":"%s","updated_at":"%s"}\n' \
    "$DR_RUN_DATE" "$DR_RUN_AT" "$DR_MODE" "$(_dr_js "$DR_ONLY")" "$1" "${2:-null}" "$DR_REPORTED" "$s" "$fl" "$(_dr_js "${DR_STALE_NAMES:-}")" "$(date '+%Y-%m-%dT%H:%M:%S')" \
    > "$tmp" 2>/dev/null && mv -f "$tmp" "$f" 2>/dev/null || rm -f "$tmp" 2>/dev/null
}
# 배터리 층 — 평일 밤 = nightly · 토요일 밤 = weekly(전체). '밤' = 시작 6시간 전의 요일(00:03 일요일 실행 = 토요일 밤).
#   러너 계약(테스트 레인): QVEST_BATTERY_TIER=nightly|weekly. 층을 모르는 옛 러너는 변수를 무시하고 전체를 돈다(깨지지 않는다).
dr_battery_tier() {
  [ -n "${QVEST_BATTERY_TIER:-}" ] && { echo "$QVEST_BATTERY_TIER"; return; }
  local now_s dow; now_s=$(date -d "${QVEST_DR_NOW:-now}" +%s 2>/dev/null || date +%s)
  dow=$(date -d "@$(( now_s - 21600 ))" +%u 2>/dev/null || date +%u)
  [ "$dow" = "${QVEST_BATTERY_WEEKLY_DOW:-6}" ] && echo weekly || echo nightly
}
# Python — venv 우선 → QVEST_PY → 시스템 Python312 (구 [1pre] 안에 있던 해석을 단계 밖으로 — 단계를 건너뛰어도 뒤 단계가 쓴다)
QVENV_PY=""
for _c in "$BASE/.venv_qvest_ml/Scripts/python.exe" "$BASE/.venv_qvest_ml/bin/python" "/home/quant/.venvs/qvest_ml/bin/python" \
          "${QVEST_PY:-}" "/c/Users/99922/AppData/Local/Programs/Python/Python312/python.exe"; do
  [ -n "$_c" ] && [ -x "$_c" ] && QVENV_PY="$_c" && break
done
if [ "$DR_DRYRUN" = "1" ]; then
  echo "[dry-run] 모드=$DR_MODE · 단계 지정=${DR_ONLY:-전부} · 배터리=$([ "${QVEST_DR_SKIP_BATTERY:-0}" = "1" ] && echo 건너뜀 || dr_battery_tier) · python=${QVENV_PY:-없음}"
  for _s in $DR_STAGES_ORDER; do dr_selected "$_s" && echo "DR_PLAN	$_s	run" || echo "DR_PLAN	$_s	skip"; done
  echo "DR_PLAN	verify	run"; echo "DR_PLAN	report	run"
  [ "$DR_MODE" = "selfheal" ] && echo "DR_PLAN	post	skip" || echo "DR_PLAN	post	run"
  [ -n "${QVEST_DR_SNAPSHOT:-}" ] && rm -f "$QVEST_DR_SNAPSHOT" 2>/dev/null
  exit 0
fi

# ──────────────────────────────────────────────────────────────────────────────
# [0] QuantiWise 적재 — 2단 (2026-08-30 배선 수리)
#
# ★수리 배경 (실사고): 구판은 [0a] 하나만 불렀다. 그런데 qw_refresh.ps1 은
#   03_Universe/**Update_File/**_update.xlsx 에 쓰고, [0a] 모듈은 **베이스** xlsx
#   (03_Universe/Consensus.xlsx 등, 2026-06-08 이후 불변)의 mtime 만 본다.
#   → 매일 "not newer — skip" 5줄만 찍고 **적재가 한 번도 일어나지 않았다**.
#   실측: consensus/universe_support/investor_act 가 2026-07-24 에서 한 달 정지,
#   그 상태로 9월 리밸이 돌아 20종 중 9종이 잘못 선택됐다.
#   Update_File 을 읽는 모듈은 **이름이 같은 다른 파일**(incremental_update_file.R)이고
#   정규 경로에 배선돼 있지 않았다(마지막 실행 = 2026-07-25 수동 d1_* 스크립트).
#
# ★두 모듈은 의미가 다르다 — 둘 다 필요하고, 순서가 있다:
#   [0a] incremental_cache_update.R  = **베이스 교체 시 전체 재빌드** (드묾).
#        QuantiWise 에서 베이스 xlsx 를 새로 받아 갈아끼웠을 때만 발화한다.
#   [0b] incremental_update_file.R   = **일상 자동확장** (Update_File → parquet append).
#        데이터가 쌓일 때마다 늘어나야 하는 정상 경로. 이것이 빠져 있었다.
#   순서 = 베이스 재빌드 먼저, 그 위에 증분을 얹는다. 뒤집으면 증분이 지워진다.
#
# ★두 모듈은 incremental_update_all/consensus/investor/universe_support 를 **같은
#   이름으로** export 한다(사고 원인). run_r 은 호출마다 새 R 프로세스라 shadowing 이
#   없지만, 한 세션에서 둘을 source 하면 조용히 덮인다 — 아래 두 블록을 합치지 말 것.
# ──────────────────────────────────────────────────────────────────────────────
if dr_want ingest; then dr_stage_begin ingest   # ── 단계 ingest ──
echo "[0a/7] QuantiWise 베이스 xlsx 교체 검사 (전체 재빌드 경로)..."
cd "$INFRA"
run_r '
  source("config.R")
  source("data/incremental_cache_update.R")
  incremental_update_all()
'

echo "[0b/7] QuantiWise Update_File 자동확장 (증분 적재)..."
cd "$INFRA"
run_r '
  source("config.R")
  source("data/incremental_update_file.R")
  incremental_update_all()
'
dr_stage_end; fi   # ── 단계 ingest 끝 ──

# ── [0c] 적재 검증은 [7/7] 직전으로 옮겼다 (v10.4 2026-09-24 — **적재 후** 측정). 아래 '[0c] 적재 검증' 블록 참조.
#   이 자리(적재 전)에서 재면 [1pre] 벤치·[1] RAWDATA·[4/7] MSM·KTRI·국면이 아직 안 들어온 상태를 재서
#   화요일 00:03 마다 benchmark lag 3>2 거짓 양성이 났다(09-15·09-22 실측 — 같은 실행의 [1pre] 가 곧 전진시켰다).

# ──────────────────────────────────────────────────────────────────────────────
# [1pre] Benchmark (코스피200) — **정본 xlsx 중심** 체인
#
# ★2026-09-18 전면 재배선 (도훈 "공표값 인터넷에서 받지말고 우리 인프라 내에서").
#   정본 = 03_Universe/Benchmark_price.xlsx (QuantiWise IKS200) → build_index_cache.py.
#   그 경로는 **생 지수 포인트 그대로** benchmark.parquet / indices.parquet 을 만든다.
#
#   구판은 정본이 멈춘 것을 못 본 채 Naver 로 매일 때웠고, 그 때움이 옛 리베이스 체인
#   (지수 × 8.83) 위에 값을 얹으면서 배수를 매번 **추정**해야 했다. 추정이 미끄러진 날의
#   하루 수익률이 배수비를 통째로 삼킨다 — 07-27 · 07-29 · 2025-01-02 이 전부 같은 병이다.
#   indices.parquet 이 2026-06-30 에 멈춘 것도 같은 원인(그 xlsx 가 마지막 입력).
#
#   새 순서:
#     ① quantiwise_fetch.py    — 정본 수급. **이 PC 안의 퀀티 단말 + 엑셀 애드인**으로
#        Benchmark_price.xlsx 의 Refresh 를 눌러 받아온다(qw_excel_refresh.ps1).
#        rc=3 = 전제 부재(단말 로그인 창·애드인 미등록) — 사람이 로그인해야 하는 상태
#     ② 새 xlsx 가 있으면       — build_index_cache.py 로 benchmark+indices 재생성
#     ③ 없으면                  — **퀀티 단일(2026-10-17 도훈 '벤치마크도 퀀티 단일로 바꿔줘' · 결정 BENCHMARK-QW-ONLY-20261017)**:
#        네이버 이어붙이기 · 트립와이어 검증은 퇴역했다(naver_benchmark_update.py 호출 0). 정본이 안 들어온 밤은 벤치 · 거래일 캘린더가
#        그대로 멈추고(→ 퀀티 Update_File 목표일도 멈춘다 — qw_refresh.ps1 Get-Target = 이 벤치의 최신일) 아래 게이트가 그날 밤 신고한다
#        (축 A = 갱신기 rc · rc=3 전제 부재도 실패 · 축 D = 정본 xlsx 미갱신 N일). 다음 밤 정본이 들어오면 전 구간이 따라온다(손실 없음).
# ──────────────────────────────────────────────────────────────────────────────
if dr_want qw; then dr_stage_begin qw   # ── 단계 qw ──
echo "[1pre/7] Benchmark (정본 QuantiWise xlsx → 코스피200 포인트)..."
# Python 체인 (v8.1.1): venv 우선 → QVEST_PY env → 시스템 Python312 fallback
QVENV_PY=""
for _c in "$BASE/.venv_qvest_ml/Scripts/python.exe" "$BASE/.venv_qvest_ml/bin/python" "/home/quant/.venvs/qvest_ml/bin/python" \
          "${QVEST_PY:-}" "/c/Users/99922/AppData/Local/Programs/Python/Python312/python.exe"; do
  [ -n "$_c" ] && [ -x "$_c" ] && QVENV_PY="$_c" && break
done
_bm_rc=0
if [ -n "$QVENV_PY" ]; then
  # ① 정본 수급
  _qw_rc=0
  ( cd "$INFRA" && "$QVENV_PY" data/quantiwise_fetch.py ) || _qw_rc=$?
  case "$_qw_rc" in
    0) echo "  ★정본 xlsx 갱신됨 — benchmark/indices 재생성"
       ( cd "$INFRA" && "$QVENV_PY" data/build_index_cache.py ) || _bm_rc=$? ;;
    2) echo "  정본 xlsx 변경 없음 (원격 == 우리 것)" ;;
    3) echo "  ※정본 수급 전제 부재 — .cache/quantiwise_fetch_status.json 참조"
       "$QVENV_PY" -c "import json,sys;d=json.load(open(r'$BASE/.cache/quantiwise_fetch_status.json',encoding='utf-8'));print('   사유:', str(d.get('message') or d.get('result') or '?')[:160])" 2>/dev/null || true
       echo "   (퀀티 단말에 로그인하면 다음 밤부터 자동으로 정본이 들어온다 — 퀀티 단일이라 오늘 벤치 · 캘린더 · RAWDATA 는 멈춘다)"
       _bm_rc=3 ;;   # (10-17 퀀티 단일) 구판은 네이버가 메워 실패로 세지 않았다 — 이제 그날 밤 축 A 가 실패로 신고한다
    *) echo "!! 정본 수급 실패 rc=$_qw_rc — 기존 xlsx 유지"; _bm_rc=$_qw_rc ;;
  esac
  # ★(2026-10-17 · 부팅 규칙 BOOT-QW-LOGIN-REFRESH-20261017) 이번 수급이 새 정본을 안 가져왔어도(rc≠0), 정본 xlsx 가
  #   benchmark.parquet 보다 앞서 있으면 재생성한다. 구판은 rc=0 일 때만 재생성해, 다른 경로로 들어온 정본(실측 10-17 00:56
  #   xlsx 10-16 · 이전 런 중도 사망 · 수동 갱신)이 parquet 에 안 실린 채 남았다(그땐 네이버 이어붙이기가 덮어 안 보였다).
  #   갱신기 rc(_bm_rc)는 그대로 둔다 — 세션 문제는 세션 문제대로 축 A 가 신고한다.
  if [ "$_qw_rc" != "0" ]; then
    _xl_max=$("$QVENV_PY" -c "import json;print(json.load(open(r'$BASE/.cache/quantiwise_fetch_status.json',encoding='utf-8')).get('before',{}).get('date_max',''))" 2>/dev/null | tr -d '\r')
    _pq_max=$("$QVENV_PY" -c "import pyarrow.parquet as pq,pandas as pd;print(pd.to_datetime(pq.read_table(r'$BASE/.cache/benchmark.parquet',columns=['Date']).to_pandas()['Date']).max().date())" 2>/dev/null | tr -d '\r')
    if [[ -n "$_xl_max" && -n "$_pq_max" && "$_xl_max" > "$_pq_max" ]]; then
      echo "  ★정본 xlsx($_xl_max)가 benchmark.parquet($_pq_max)보다 앞서 있다 — benchmark/indices 재생성"
      _bx=0; ( cd "$INFRA" && "$QVENV_PY" data/build_index_cache.py ) || _bx=$?
      [ "$_bx" -ne 0 ] && _bm_rc=$_bx
    fi
  fi

  # ③ (퇴역 10-17 · BENCHMARK-QW-ONLY-20261017) 네이버 이어붙이기 · 검증 호출 0 — 정본이 안 들어오면 기존 cache 그대로(퀀티 단일)
  if [ "$_bm_rc" -ne 0 ]; then
    echo "  benchmark 갱신 FAILED rc=$_bm_rc (기존 cache 유지 — 보충 원천 없음 · 다음 밤 정본이 전 구간을 따라잡는다)"
  fi
else
  _bm_rc=127
  echo "  python 미발견 - benchmark 갱신 skipped (기존 cache 유지)"
fi

# --- [1pre-dk] 신규 상장 동기화 (2026-11-08 · 04_Research/01_reports/quantiwise_data_expansion_20261106/BUILD_20261108.md §1) ---------------
#   KRX 상장 목록(벤치 최신일 · data/krx_listing_snapshot.R) → 정본 종목 목록(06_Registry/qw_datakey_master.json · 추가만 · data/qw_datakey_master.py)
#   → 퀀티 DB DATA_Key 끝 붙이기(행 8 · 항목 시트 A열 정렬 검증 · 백업 · ops/qw_datakey_sync.ps1). 붙인 DB의 보충 시작일 =
#   .cache/qw_backfill_pending.json → 바로 아래 [1pre-qw] 래퍼가 -FromOverride 로 한 번 넘긴다(끝낸 DB는 대기열에서 지운다).
#   왜: DATA_Key 를 손으로 관리해 11-06 기준 신규 상장 46종이 RAWDATA 에 없었고, 3개 DB에 53종이 빠져 위생 표식이 NA 였다(PLAN F7).
#   실패해도 수급은 평소 창으로 진행한다(DR_FAILED 에만 싣는다). 끄기: QVEST_DK_SYNC=0 · 검사: 08_Tests/data/test_qw_datakey_sync.ps1
if [ "${QVEST_DK_SYNC:-1}" = "1" ] && [ -n "$QVENV_PY" ]; then
  echo "[1pre-dk] 신규 상장 동기화(KRX 상장 목록 → 정본 → 퀀티 DB DATA_Key)..."
  cd "$INFRA"
  "$RSCRIPT" --no-save data/krx_listing_snapshot.R; _dk_snap_rc=$?          # 0 저장 · 2 응답 없음(휴장 · 지연 → 직전 스냅숏 사용) · 1 오류
  [ "$_dk_snap_rc" -eq 1 ] && DR_FAILED+=("dk_krx_snapshot(rc=1)")
  "$QVENV_PY" -X utf8 data/qw_datakey_master.py --update; _dk_m_rc=$?
  if [ "$_dk_m_rc" -eq 1 ]; then
    DR_FAILED+=("dk_master(rc=1)")
  else
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w "$INFRA/ops/qw_datakey_sync.ps1")" -InChain; _dk_rc=$?
    [ "$_dk_rc" -ne 0 ] && DR_FAILED+=("dk_sync(rc=$_dk_rc)") && echo "!! [1pre-dk] DATA_Key 동기화 rc=$_dk_rc — DB는 저장되지 않았거나 일부만(평소 창으로 수급은 진행)"
  fi
fi

# --- [1pre-qw] 퀀티 Update_File 4종 매일 수급 — RAWDATA 주가 원천 = 퀀티 단일 (2026-10-17 · 결정 RAWDATA-QW-ONLY-20261017) -------------
#   도훈 10-17 "이제 퀀티 실행 문제없이 되니까 주가관련 복잡한 규칙들 모두 없애고 Universe update 에 있는 파일들 매일 데이터 리프레시할 때
#   퀀티로 최신화시켜는걸로 Rawdata 관리하자" · "Consensus_update, Investor_Act_update 이것도 매일해". (구 QW-UPDATEFILE-UNATTENDED 안 A 의 확장)
#   로그인 클릭 없이(-SkipLogin — 08-29 계정 잠금 경로 없음) OHLCVS → Universe_Support → Investor_Act → Consensus 를 받는다(목표일 = 직전 거래일에
#   이미 닿은 파일은 드라이버가 건너뜀 — 주말 · 휴일은 곧바로 끝난다). 벤치 수급 rc=3(로그인 창 · 애드인 미등록)이면 건너뛴다.
#   ★보충 원천이 없다(네이버 · KRX 퇴역) — 미완료(done D<N · rc≠0)와 건너뜀은 DR_FAILED 로 싣는다(그날 RAWDATA 정체를 조용히 넘기지 않는다).
#   전진한 파일이 있으면 [0b'] 적재. 끄기: QVEST_QW_UPDATEFILE_UNATTENDED=0 · 검사: 08_Tests/data/test_qw_updatefile_unattended.R(스텁)
_qwuf_log="$(mktemp /tmp/qm_qwuf_XXXX.log)"
bash "$INFRA/data/qw_updatefile_unattended.sh" "${_qw_rc:-1}" "$QVENV_PY" 2>&1 | tee "$_qwuf_log"; _qwuf_rc=${PIPESTATUS[0]}
_qwuf_line="$(grep '^QWUF' "$_qwuf_log" | tail -n 1)"; rm -f "$_qwuf_log"
_qwuf_state="$(printf '%s' "$_qwuf_line" | sed -n 's/.*state=\([^[:space:]]*\).*/\1/p')"
_qwuf_done="$(printf '%s' "$_qwuf_line" | sed -n 's/.*done=\([^[:space:]]*\).*/\1/p')"
_qwuf_inc="$(printf '%s' "$_qwuf_line" | sed -n 's/.*incomplete=\([0-9]*\).*/\1/p')"
if [ "$_qwuf_state" = "skipped" ]; then
  DR_FAILED+=("qw_updatefile_skipped(bench_rc=${_qw_rc:-?})")
  echo "!! [1pre-qw] ★퀀티 Update_File 수급 건너뜀 — 오늘 RAWDATA 주가가 전진하지 않는다(보충 원천 없음 · 단말 로그인 확인)"
elif [ "${_qwuf_inc:-0}" = "1" ]; then
  DR_FAILED+=("qw_updatefile_incomplete(done=${_qwuf_done:-?})")
  echo "!! [1pre-qw] ★퀀티 Update_File 미완료(done=${_qwuf_done:-?}) — 목표일 미달 파일은 오늘 정체(다음 밤 같은 구간을 다시 받는다)"
fi
if [ "$_qwuf_rc" -eq 0 ]; then
  echo "[0b'/7] Update_File 재적재 (무인 수급 전진분)..."
  cd "$INFRA"
  run_r '
    source("config.R")
    source("data/incremental_update_file.R")
    incremental_update_all()
  '
fi

# --- [1pre-ext] 퀀티 확장 질의서(등록부 group=ext · glossary 코드로 만든 DB) 수급 · 적재 (2026-11-08 · BUILD_20261108.md §2) -----------
#   등록부 02_Infrastructure/data/qw_updatefile_registry.json 의 ext DB 중 **만들어진 DB만**(03_Universe/Update_File_ext/*.xlsx 존재) 같은 무인 래퍼로
#   받는다(QWUF_GROUP=ext → qw_refresh.ps1 -Group ext · 시작일 앵커 = 그 DB 출력 전부의 min(max)+1 · 신규 상장 보충도 같은 대기열).
#   전진하면 범용 적재기(data/qw_ext_ingest.py — 관문 G1 시트 종료일 동일 · G2 항목 코드 · G3 채움 · 끝 미공표 자르기)로 .cache/qw_ext/ 에 싣는다.
#   ★아직 소비자 없음(보고 전용) — 실패는 DR_FAILED 로 싣되 RAWDATA 체인은 막지 않는다. 끄기: QVEST_QW_EXT=0
#   검사: 08_Tests/data/test_qw_ext_ingest.py · test_qw_updatefile_unattended.R
if [ "${QVEST_QW_EXT:-1}" = "1" ] && [ -n "$QVENV_PY" ] && [ "${_qwuf_state:-}" != "skipped" ]; then
  _ext_books="$("$QVENV_PY" -X utf8 -c "import json,os,sys;b=sys.argv[1];r=json.load(open(os.path.join(b,'02_Infrastructure','data','qw_updatefile_registry.json'),encoding='utf-8'));print(','.join(x['name'] for x in r['books'] if x.get('group')=='ext' and x.get('layout')=='ts' and os.path.exists(os.path.join(b,*x['path'].split('/')))))" "$(cygpath -w "$BASE" 2>/dev/null || echo "$BASE")" 2>/dev/null | tr -d '\r')"
  if [ -n "$_ext_books" ]; then
    echo "[1pre-ext] 퀀티 확장 질의서 수급: $_ext_books"
    QWUF_GROUP=ext QWUF_ONLY="$_ext_books" QWUF_LOG="$BASE/.cache/qw_updatefile_unattended_ext.json" \
      bash "$INFRA/data/qw_updatefile_unattended.sh" "${_qw_rc:-1}" "$QVENV_PY"; _ext_rc=$?
    if [ "$_ext_rc" -eq 0 ]; then
      "$QVENV_PY" -X utf8 "$INFRA/data/qw_ext_ingest.py"; _ei_rc=$?
      { [ "$_ei_rc" -eq 1 ] || [ "$_ei_rc" -eq 3 ]; } && DR_FAILED+=("qw_ext_ingest(rc=$_ei_rc)") && echo "!! [1pre-ext] 확장 적재 rc=$_ei_rc(1 오류 · 3 관문 거부 — .cache/qw_ext/_ingest_state.json)"
    fi
  else
    echo "[1pre-ext] 만들어진 확장 질의서 없음 — 건너뜀"
  fi
fi

# --- BMG-01 거래일 지평선 게이트 (2026-08-20 신설) ---------------------------
#   trading_calendar.R 은 RAWDATA 자기참조의 순환오염을 끊으려고 .cache/benchmark.parquet
#   **하나만을** 거래일 권위로 삼는다(L45/L137). ★2026-09-18 정정: 그 파일의 writer 는
#   하나가 아니라 셋이다 — build_index_cache.py(정본 xlsx 경로) · naver_benchmark_update.py
#   (항등 이어붙이기) · rebuild_benchmark_canonical.py(축 재구축). 구 주석의 "유일 writer"
#   서술이 바로 그 착각이었다: 축을 선언하지 않은 채 writer 가 여럿이면 파이프라인이
#   bistable 해져 마지막에 쓴 쪽의 축이 굳는다. 지금은 **셋 다 같은 축**(지수 포인트)을
#   쓰고, 그 규약이 .cache/benchmark_axis.json 에 선언돼 있다.
#   (2026-10-17 BENCHMARK-QW-ONLY-20261017: naver_benchmark_update.py 이어붙이기 퇴역 → 밤 writer = build_index_cache.py 하나 ·
#    rebuild_benchmark_canonical.py 는 수동 축 재구축뿐)
#   ★그래서 이 스텝의 실패를 삼키면 결손이 **사라진다**: 캘린더가 얼고 -> Naver 는
#   "already >= target", KRX 는 "gap 0 days" 를 **정직하게** 보고하며 리프레시는
#   "실패 0" 으로 마감한다. 실측 2026-08-14~20: 거래일 3일(08-18/19/20)이 비었는데
#   6일 내내 매일 "성공"으로 끝났다 - fail-soft 가 지평선을 삼킨 것.
#   게이트는 A축(갱신기 rc)과 B축(파일 정체)을 따로 본다.
#   검사: 08_Tests/data/test_benchmark_currency_gate.R (위반 주입 11/11, 실사고 재현 포함)
#   ★2026-09-07 축 C 추가 — **레벨 축 정합**(BM_Close 대 공표 코스피200 레벨).
#     실측 사건: BM_Close 가 지수의 8.834448배 위에 있었는데 하루 사이 배수 점프가
#     0건이라 "연속이면 정상" 으로 보였고 두 달 넘게 안 걸렸다. 같은 불변식을 적어 둔
#     가드(build_cache.R)는 ①이 체인이 부르지 않는 찬 경로에 있고 ②방금 자기가 쓴
#     산출물을 비교하는 동어반복이라 발화할 수 없었다. 축 C 는 그 불변식을 **소비면에서
#     · 상시 경로에서 · 독립 소스로** 잰다.
#   ★2026-09-18 자기정정 — 그 축 C 는 **한 번도 통과한 적이 없다**(09-07 신설 이후 매일
#     FAIL). 체인 축 위에서 |배수-1|<=0.01 을 요구했으니 원리적으로 통과 불가였고,
#     상시 빨강은 상시 침묵이라 진짜 이음매를 가렸다. 파일을 축에 맞춘 뒤
#     (rebuild_benchmark_canonical.py) 이 검사는 참이 될 수 있는 명제가 됐다.
#     그리고 **이음매 축**(연속 공통일 사이 비율 변화)을 더했다 — 정합만 재면 통짜 이탈만
#     잡고 실제로 재발한 하루짜리 계단은 놓친다.
#   ★2026-09-18 축 D 추가 — **정본 xlsx 신선도**(WARN). 정본이 멈춘 것을 아무도 못 본 것이
#     모든 재발의 온상이었다. 소비면(.cache/indices.parquet 의 max Date)에서 센다.
#     검사: 08_Tests/data/test_benchmark_level_axis.R · test_benchmark_axis_rebuild.R
# ★v10.4 (2026-09-24) 라벨의 rc 는 **게이트** 종료코드와 **갱신기** 종료코드를 나눠 적는다. 구판 `(rc=$_bm_rc)` 는
#   갱신기 rc 만 적어 09-12~17 '(rc=0)' 인데 실패로 보이는 혼동을 만들었다(실제 실패 = 게이트 축 C).
_bg_rc=0
"$RSCRIPT" --no-save "$INFRA/data/benchmark_currency_gate.R" --updater-rc "$_bm_rc" || _bg_rc=$?
if [ "$_bg_rc" -ne 0 ]; then
  DR_FAILED+=("benchmark_currency(gate_rc=$_bg_rc,updater_rc=$_bm_rc)")
  echo "!! [1pre] ★거래일 지평선 이상 - 하류 gap 판정이 무의미해진다 (위 [bm-gate] 사유 참조)"
fi

# ── [1/7] Naver T+0 — 퇴역 (2026-10-17 도훈 '주가관련 복잡한 규칙들 모두 없애고 … 퀀티로 최신화' · 결정 RAWDATA-QW-ONLY-20261017) ──
#   RAWDATA 주가 원천 = 퀀티 Update_File 단일([1pre-qw] → [0b']). 구 경로(naver_run_pipeline · 수정주가 재조정 · 시총 스냅샷)는 호출 0 —
#   10-17 실측: 09-14 이후 네이버 종가가 퀀티 공식 종가와 종목·일 81% 에서 어긋났다(일치 19% · 일간 수익률 0.5%p 초과 차 52~73%).
#   모듈 data/naver_data_collector.R 은 퇴역 표기만 남긴다(복원 = git · 태그 pre-rawdata-qw-only-20261017).

dr_stage_end; fi   # ── 단계 qw 끝 ──

# (11-10) [1z] 는 universe 단계 머리에 둔다 — 08_Tests/data/test_rawdata_size_guard.R 가 '# ── [1z]' ~ 'echo "[3/7]' 를 잘라 실행하므로
#   그 구간에 단계 경계(if/fi)가 끼면 안 된다. Size 결측 실패는 universe 단계 실패로 계상된다(재실행 = universe 와 하류).
if dr_want universe; then dr_stage_begin universe   # ── 단계 universe ──
# ── [1z] RAWDATA 최근일 Size 채움률 경보 (2026-09-23 W-02 · 도훈 승인 처방 §3) ─────────
#   사고: Naver 시총 스냅샷이 09-12 부터 매 실행 디코드 예외로 죽어 RAWDATA.Size 가
#   09-10~22 100% 결측이었는데, 이 스텝은 "RAWDATA 전진" 만 봐서 매일 성공으로 끝났다.
#   행이 붙는 것과 값이 차는 것은 다른 명제다. 판정·문턱은 rawdata_fill_guard.R +
#   cache_registry.json::fill_rate(max_na_rate) 단일 정본 — 여기서 다시 구현하지 않는다.
#   rc 0 = 정상 · 3 = 결측률 초과 · 그 외 = 미측정(정상으로 접지 않는다).
_sz_out="$(QM_ROOT="$BASE" "$RSCRIPT" --no-save "$INFRA/data/rawdata_fill_guard.R" --cols Size 2>&1)"
_sz_rc=$?
printf '%s\n' "$_sz_out"
case "$_sz_rc" in
  0) echo "[1z] RAWDATA 최근일 Size 채움률 정상" ;;
  3) echo "!! [1z] ★RAWDATA 최근일 Size 결측률 초과 — 규모·가치 팩터(V*·S*·L26)가 0행으로 빠진다"
     DR_FAILED+=("rawdata_size_na") ;;
  *) echo "!! [1z] Size 채움률 미측정(rc=$_sz_rc) — 정상으로 접지 않는다"
     DR_FAILED+=("rawdata_size_na:unmeasured") ;;
esac

# ── [2/7] KRX gap-fill — 퇴역 (2026-10-17 · 결정 RAWDATA-QW-ONLY-20261017) ──────────────────────────────────────────
#   보충 원천을 두지 않는다 — 퀀티 수급 미완료는 [1pre-qw] 가 DR_FAILED 로 싣고, 다음 밤 같은 구간(기준일 다음 날부터 전 구간)을 다시 받는다.
#   모듈 data/krx_build_rawdata.R 은 퇴역 표기만(KRX 지수 · 파생 수집 data/krx_data_collector.R 은 [4/7] Arrow · VKOSPI 가 계속 쓴다).

# ──────────────────────────────────────────────────────────────────────────────
# [3] Universe 갱신 + RAWDATA 메타 매핑
#     Layer 1: KRX API 기반 유니버스 (RAWDATA에서 월말 활성 종목)
#     Layer 2: Universe_Support.xlsx 메타 (있으면 roll join)
# ──────────────────────────────────────────────────────────────────────────────
echo "[3/7] Universe update + RAWDATA mapping..."
cd "$INFRA"
run_r '
  source("config.R")
  source("data/krx_update_universe.R")
  tryCatch(krx_update_universe(),
    error = function(e) cat(sprintf("Universe update skipped: %s\n", e$message)))

  source("data/apply_universe_mapping.R")
  tryCatch(apply_universe_mapping(),
    error = function(e) cat(sprintf("Universe mapping skipped: %s\n", e$message)))
'

# ── [3b] RAWDATA BM_Ret 동기화 — 단일 writer (2026-09-23 W-09 · 도훈 승인) ─────────────
#   사고: naver 일간 경로가 행을 append 하면서 BM_Ret 을 안 채워 2026-09-07~ 전량 결측이었고
#   (factor_db_202609 MA06 소실 · C18 332→110행) 어느 스텝도 그것을 보고하지 않았다.
#   정의·보호 날짜·상한 = data/rawdata_bm_ret_sync.R + rawdata_bm_ret_sync_config.json 단일 정본
#   (여기서 다시 구현하지 않는다). RAWDATA 를 쓰는 [0b]/[1]/[2]/[3] 이 끝난 뒤 · [6a] 팩터 빌드 전.
#   rc 0 = 정합 · 4 = 벤치 지연(그 날 NA 유지 — 추정 금지) · 3 = 위반(킬스위치 거부·벤치 결손 등)
#   · 그 외 = 미측정(정상으로 접지 않는다). 검사: 08_Tests/data/test_rawdata_bm_ret_sync.R (배선 절)
echo "[3b/7] RAWDATA BM_Ret 동기화 (정본 benchmark → 단일 writer)..."
_bms_out="$(QM_ROOT="$BASE" "$RSCRIPT" --no-save "$INFRA/data/rawdata_bm_ret_sync.R" --apply 2>&1)"
_bms_rc=$?
printf '%s\n' "$_bms_out"
_bms_line="$(printf '%s\n' "$_bms_out" | grep '^BM_RET_SYNC ' | tail -1)"
_bms_lag="$(printf '%s' "$_bms_line" | sed -n 's/.* lag_dates=\([^ ]*\).*/\1/p')"
_bms_viol="$(printf '%s' "$_bms_line" | sed -n 's/.* viol=\([^ ]*\).*/\1/p')"
case "$_bms_rc" in
  0) echo "[3b] RAWDATA BM_Ret 정합 — ${_bms_line:-?}" ;;
  4) echo "!! [3b] ★벤치 지연 — RAWDATA BM_Ret NA 유지(추정 금지): ${_bms_lag:-?}"
     DR_FAILED+=("rawdata_bm_ret:bench_lag(${_bms_lag:-?})") ;;
  3) echo "!! [3b] ★RAWDATA BM_Ret 동기화 위반 — ${_bms_viol:-?}"
     DR_FAILED+=("rawdata_bm_ret:violation(${_bms_viol:0:160})") ;;
  *) echo "!! [3b] RAWDATA BM_Ret 동기화 미측정(rc=$_bms_rc) — 정상으로 접지 않는다"
     DR_FAILED+=("rawdata_bm_ret:unmeasured(rc=$_bms_rc)") ;;
esac
dr_stage_end; fi   # ── 단계 universe 끝 ──

# ──────────────────────────────────────────────────────────────────────────────
# [4] Arrow / FRED / KTRI / Regime Signal
# ──────────────────────────────────────────────────────────────────────────────
if dr_want macro; then dr_stage_begin macro   # ── 단계 macro ──
echo "[4/7] Arrow + FRED + KTRI + Regime..."

# Arrow 확장
cd "$INFRA"
run_r '
  source("config.R")
  source("data/krx_data_collector.R")
  source("data/krx_arrow_pipeline.R")
  tryCatch(krx_extend_arrow(),
    error = function(e) cat(sprintf("Arrow skipped: %s\n", e$message)))
'

# FRED — fetch + compute regime (도훈 mandate 2026-05-15)
# fred_fetch_all → fred_macro.parquet (raw 시리즈)
# fred_compute_regime → macro_regime.parquet (Macro_Risk_Score 월별 — monthly path 핵심)
# 이전에 compute 누락으로 macro_regime.parquet 2개월 stale 발생 → 둘 다 호출
cd "$INFRA"
if [ -f "data/data_collector_fred.R" ]; then
  run_r '
    source("config.R")
    source("data/data_collector_fred.R")
    tryCatch(fred_run_pipeline(),
      error = function(e) cat(sprintf("FRED pipeline skipped: %s\n", e$message)))
  '
fi

# KTRI + Regime Signal
# krx_derivatives_collector를 ktri_index_collector보다 먼저 source — krx_vkospi()가
# 있어야 IKS221(VKOSPI) 수집됨 (없으면 exists() 가드로 조용히 영구 NA — 2026-06-11 발견)
cd "$INFRA"
run_r '
  source("config.R")
  source("data/krx_data_collector.R")
  source("data/krx_derivatives_collector.R")
  source("data/ktri_index_collector.R")
  tryCatch(ktri_update_indices(),
    error = function(e) cat(sprintf("KTRI skipped: %s\n", e$message)))
'
# KTRI v3 — 원본 04_Regime_Engine/KTRI_v3_reinforced.R 소실, 재구축 builder로 교체
# (2026-06-11 — morning_briefing.sh와 동일 경로. 구 참조는 매일 "skipped"만 찍고 있었음)
cd "$BASE"
run_r '
  setwd("'"$BASE"'")
  source("02_Infrastructure/config.R")
  source("02_Infrastructure/regime/ktri_v3_builder.R")
  tryCatch({
    out_path <- build_ktri_v3_safe()
    cat(sprintf("KTRI v3 signals regenerated: %s\n", out_path))
  }, error = function(e) cat(sprintf("KTRI v3 build FAILED: %s\n", e$message)))
'
# MSM — as-of 연말 재적합 경로 (2026-11-06 전환 · 결정 PIT-C1-MSM-PARAMS 안 A · MSM-ASOF-SWITCH-20261017)
#   생산자 = 02_Infrastructure/regime/msm_asof.R::msma_update(원장 06_Registry/msm_param_schedule.json ·
#   해가 바뀐 첫 실행에만 1행 적합 · 그 밖엔 .cache/msm_asof_daily.parquet 경로만 다시 쓴다).
#   ★폴백 없음: 구 msm_update.R(1990~2026-01 전 표본 고정 모수 = C1)와 msm_daily_refit(평활 HMM = C1 이중)은
#     운영 경로에서 뺐다. 실패하면 as-of 경로가 낡고 → 아래 regime_signal 로더가 stop → 후보 없음 →
#     원장 병합 없음(라이브 불변 · fail-closed). 구 캐시 msm_daily_latest · msm_hybrid_latest 는 더 갱신하지 않는다.
#   ★실패 = DR_FAILED 'msm_asof(rc=1)'(2026-11-06 · 적대 검토 #16 · #20): 오류를 cat 으로만 삼키면 Rscript rc=0 이라
#     run_r 이 못 센다 → 그날 밤 '실패 0' 요약과 함께 국면 갱신이 조용히 멈춘다. 처리기에서 quit(status = 1) 로 끝내고
#     run_r 이름표 msm_asof 로 싣는다(종료코드 · [7] 요약 · 실패 서명에 닿는다). 체인은 계속 — 뒤 국면 빌드가 낡은
#     as-of 경로로 stop 하면 아래 원장 루프가 regime_append:<계열>(rc=2) 를 따로 싣는다.
# 순서 critical: MSM 먼저 → build_regime_signal_table() 그 후 (unified_regime_signal stale 방지)
cd "$BASE"
run_r '
  setwd("'"$BASE"'")
  tryCatch({
    source("02_Infrastructure/regime/msm_asof.R")
    msma_update(getwd())
    cat("[daily_refresh] MSM as-of PASS — msm_asof_daily 갱신\n")
  }, error = function(e) {
    cat(sprintf("[daily_refresh] MSM as-of FAIL: %s — 국면 후보 빌드가 멈춘다(fail-closed · 라이브 불변)\n", e$message))
    quit(status = 1, save = "no")
  })
' msm_asof

# build_regime_signal_table — MSM 갱신 후 호출 (monthly + daily 양쪽 rebuild)
# 차트 (tg_regime_briefing)가 unified_regime_signal + _daily 양쪽 읽으므로 둘 다 재build
# ★C11 원장 경로(2026-09-25 · 판정서 pit_c11_20260924 · 결정 PIT-C11-REMEDIATION): 재생성본은 후보
#   (.cache/_regime_candidate/ — 라이브와 같은 basename)로만 쓴다. 라이브는 바로 아래 원장 병합(--from-candidate)만 쓴다.
#   빌드 실패 = 후보 부재(fresh=TRUE 가 어제 후보를 지움) = 병합 없음 = 라이브 불변(fail-closed). 아침 fred_regime.R 도 같은 경로.
cd "$INFRA"
run_r '
  source("config.R")
  source("regime/regime_signal.R")
  source(file.path(FUNC_PATH, "regime", "regime_append_only.R"))
  .cand <- regime_ledger_candidate_paths(PROJECT_ROOT, fresh = TRUE)
  tryCatch(build_regime_signal_table(save_path = .cand$monthly),               # monthly
    error = function(e) cat(sprintf("Regime signal (monthly) skipped: %s\n", e$message)))
  tryCatch(build_regime_signal_table(daily = TRUE, save_path = .cand$daily),   # daily
    error = function(e) cat(sprintf("Regime signal (daily) skipped: %s\n", e$message)))
'

# ─── 국면 계열 append-only 원장 (도훈 지시 2026-08-13 "1번 가자") ──────────────
#   위 rebuild 는 계열을 **전량 재생성**한다. 내부 생성 재서술(MSM 전체표본 디민)은
#   commit b514830e 로 수리했으나, **외부 개정은 코드로 못 막는다** — FRED 핀 스냅샷 실측:
#   2026-09 핀 → 라이브 과거 **3,000셀** 변경(Chi_Fin_Cond 1,320 · StL_Fin_Stress 1,361 ·
#   US_M2 312, 최초 2000-01-07). FRED 는 Regime_Score 합성의 35%(0.35*FRED_MRS)다.
#   ⇒ 발행 원장이 완료 구간을 동결하고, 재생성본의 과거 재서술은 보고만 하고 버린다.
#   ★진행 중인 구간(월간=당월, 일간=오늘)은 동결 대상이 아니다 — 매일 갱신이 정상이므로
#     그것까지 막으면 정상 갱신을 재서술로 오탐한다. 검증 19/19.
#   exit 1 = 동결 구간 재서술 시도(발행본 보존) → 경고만 하고 계속. 소비자는 안정된 이력을 본다.
#   ★C11(2026-09-25): 입력 = 위 후보(--from-candidate) · 병합은 표식 열(avail_date·c11_regime_key)·파일 속성 보존 ·
#   exit 3 = 발행 원장 epoch ≠ 후보 epoch(C11 이전 원장 · 규칙 키 변경) → 병합·기록 없음, 라이브 불변 — 재기준선
#   (regime_append_only.R --republish, dry-run 기본 → --execute)은 사람이 한다. exit 2 = 후보 부재·판독 불가 → 라이브 불변.
#   ★rc ∉ {0,1} = DR_FAILED 'regime_append:<계열>(rc=..)'(2026-11-06 · 적대 검토 #16 · #20): 구판은 echo 만 해서
#     라이브 동결(MSM · 국면 빌드 실패 → 후보 부재 rc=2 · 에폭 불일치 rc=3 · 프로세스 사망)이 종료코드 · [7] 요약에 안 닿았다.
#     rc=3 도 싣는다 — 재기준선 전까지(MSM 전환 2~3단계 창 포함) 매일 밤 실패로 보이는 것이 의도된 표면화다.
#     rc=1(재서술 검출 · 발행본 보존)은 종전대로 경고만. ※R 최상위 오류(구문 · 패키지 적재 실패)도 Rscript rc=1 이라
#     여기서는 경고로 접힌다(별건). ★이 루프에 '(rc=N)' 꼴 출력 줄을 더하지 말 것 — 08_Tests/regime/test_regime_ledger_c11.R
#     T5 가 루프 출력의 '(rc=2)' 줄 수(=2)를 센다(아래 누적은 출력 없음).
cd "$QM_ROOT" 2>/dev/null || cd "$INFRA/.."
for _series in monthly daily; do
  "$RSCRIPT" --no-save "$QM_ROOT/02_Infrastructure/regime/regime_append_only.R" --series "$_series" --root "$BASE" --from-candidate 2>&1
  _rc=$?
  case "$_rc" in
    0) echo "[regime-append/$_series] OK" ;;
    1) echo "!! [regime-append/$_series] 동결 구간 재서술 시도 검출 — 발행본 보존됨(상류 확인 필요)" ;;
    3) echo "!! [regime-append/$_series] epoch 불일치 — 병합 없음·라이브 불변 · 재기준선 필요(regime_append_only.R --republish)" ;;
    *) echo "XX [regime-append/$_series] 게이트 실패(rc=$_rc) — 라이브 불변 · 계열 신뢰 불가" ;;
  esac
  case "$_rc" in
    0|1) ;;
    *) DR_FAILED+=("regime_append:${_series}(rc=$_rc)") ;;
  esac
done
cd "$INFRA"

# ─── regime_daily_v2 (9-axis daily MRS) rebuild — FRED 직후 (2026-07-25 배선) ─────
#   기존엔 morning_briefing(07:10)만 rebuild → 머신 지연 기상/주말이면 macro_fred만 갱신되고
#   regime_daily_v2가 수영업일 뒤처짐 (AST 리프 맵 §3-3 실측 ~4영업일 — 07-25 실사례:
#   00:03 미스 후 07:17 지연 기동으로 FRED는 갱신, v2는 전일 채로 방치). daily_refresh에도
#   배선해 이중화 (idempotent full rebuild, 실측 소요 <1분). 소비: factor_db daily
#   phase6/7/9b + RAMP regime + SJM(VIX_z) + forecaster 계열.
cd "$BASE"
run_r '
  setwd("'"$BASE"'")
  source("02_Infrastructure/config.R")
  source("02_Infrastructure/regime/regime_engine_daily.R")
  tryCatch({
    rd <- build_daily_regime(use_cache = FALSE)
    cat(sprintf("[daily_refresh] regime_daily_v2 rebuilt: %d rows, max Date=%s\n",
                nrow(rd), max(as.Date(rd$Date))))
  }, error = function(e) cat(sprintf("regime_daily_v2 rebuild skipped: %s\n", e$message)))
'

# ─── SJM (Statistical Jump Model) BearProb 일간 refresh (2026-07-25 배선) ─────────
#   .cache/regime_jump_daily.parquet — walk-forward online(PIT-legitimate) 확정 자산인데
#   정기 리프레시 미배선으로 ~7주 스테일 방치 실측 (AST 리프 맵 §3-3, 종점 2026-06-04).
#   전량 walk-forward 재계산(restart별 고정 seed = 결정적, 실측 소요 2.0분/72 refit).
#   소비: RAMP regime bakeoff + axiom overlay selfdev + FR Track1. regime_daily_v2(VIX_z
#   feature) 뒤에 배치. refit_jm_daily 내부 tryCatch — 실패 시 기존 cache 유지 (fail-soft).
cd "$BASE"
run_r '
  setwd("'"$BASE"'")
  source("02_Infrastructure/config.R")
  source("02_Infrastructure/regime/regime_jump_model.R")
  jm <- refit_jm_daily()
  if (!is.null(jm)) {
    cat(sprintf("[daily_refresh] regime_jump_daily refreshed: %d rows, max Date=%s\n",
                nrow(jm), max(as.Date(jm$Date))))
  } else {
    cat("[daily_refresh][WARN] SJM regime_jump refresh FAILED (기존 cache 유지)\n")
  }
'

# ─── ECOS KRW/USD + Bond rates (도훈 audit 2026-05-15 KRW + 2026-06-17 bond 누락 fix) ──
#   bond rates(국고채/회사채/CD/CPI 7 series)는 ecos_fetch_bond_rates()가 따로 존재하나
#   daily_refresh가 호출하지 않아 ecos_bond_rates.parquet 30일 stale(05-18) 방치됨.
#   소비처: regime_forecaster_v3.R / sharpe_standard.R / bearish_forecast. 호출 추가.
cd "$INFRA"
run_r '
  source("config.R")
  source("data/data_collector_ecos.R")
  tryCatch(ecos_fetch_krw(),
    error = function(e) cat(sprintf("ECOS KRW skipped: %s\n", e$message)))
  tryCatch(ecos_fetch_bond_rates(),
    error = function(e) cat(sprintf("ECOS bond rates skipped: %s\n", e$message)))
'

# ─── [4gm] 거시 입력 2종 (2026-10-20 · THGNN 2601.04602 · 도훈 'DXY는 ECOS 프록시로' · 'WTI 일일 갱신까지 편입') ──────────
#   ① ECOS 731Y002 6통화 + DXY 프록시(ICE 공식) → .cache/ecos_fx_majors.parquet — 위 ECOS 블록과 달리 오류를 삼키지 않는다(실패 = r-step FAILED).
#   ② 퀀티 경제 질의서 03_Universe/Global_Macro.xlsx(WTI유(NYMEX) xcCHPRWDQWTI) — 벤치와 같은 수급기(quantiwise_fetch.py --dest) →
#      global_macro_ingest.py → .cache/qw_global_macro.parquet. 가용일 = 06_Registry/fred_availability_rules.json(QW_WTI_NYMEX · ECOS_DXY_PROXY).
#      벤치 수급이 세션 없음(rc=3)이면 건너뛴다(벤치 게이트가 이미 신고). ★스탬프만 바뀌고 값이 안 오는 밤 = 끊긴 세션(10-20 다른 PC 중복 로그인) —
#      지평선 불변은 rc=2 로 접히고, 적재기 신선도 검사(마지막 값 > 7역일 → rc=3)가 정체를 신고한다. 끄기: QVEST_QW_GLOBAL_MACRO=0
cd "$INFRA"
run_r '
  source("config.R")
  source("data/data_collector_ecos.R")
  ecos_fetch_fx_majors()
'
if [ -n "$QVENV_PY" ] && [ "${_qw_rc:-1}" != "3" ] && [ "${QVEST_QW_GLOBAL_MACRO:-1}" != "0" ]; then
  echo "[4gm] 퀀티 경제 질의서(Global_Macro.xlsx · WTI) 수급..."
  _gm_rc=0
  ( cd "$INFRA" && "$QVENV_PY" data/quantiwise_fetch.py --dest "$BASE/03_Universe/Global_Macro.xlsx" --timeout-sec 900 ) || _gm_rc=$?
  if [ "$_gm_rc" = "0" ] || [ "$_gm_rc" = "2" ]; then
    _gi_rc=0
    ( cd "$INFRA" && "$QVENV_PY" data/global_macro_ingest.py ) || _gi_rc=$?
    [ "$_gi_rc" -ne 0 ] && DR_FAILED+=("global_macro_ingest(rc=$_gi_rc)")
  else
    DR_FAILED+=("global_macro_fetch(rc=$_gm_rc)")
    echo "!! [4gm] 질의서 수급 실패 rc=$_gm_rc — 기존 xlsx · 캐시 유지"
  fi
else
  echo "[4gm] 퀀티 경제 질의서 건너뜀(벤치 수급 rc=${_qw_rc:-?} · QVEST_QW_GLOBAL_MACRO=${QVEST_QW_GLOBAL_MACRO:-1})"
fi

# ─── Cache Freshness Audit (도훈 mandate 2026-05-15 영구 보호망 L3) ─────────
# Registry 기반 stale + orphan 양방향 감지, Telegram alert
cd "$BASE"
run_r '
  setwd("'"$BASE"'")
  source("02_Infrastructure/data/cache_freshness_audit.R")
  .tg_on <- Sys.getenv("QVEST_REFRESH_TG", "0") == "1"   # v8.1.1 telegram guard
  if (!.tg_on) cat("[tg guard] QVEST_REFRESH_TG=0 — cache audit telegram_alert off\n")
  tryCatch(cache_freshness_audit(telegram_alert = .tg_on),
    error = function(e) cat(sprintf("Cache freshness audit skipped: %s\n", e$message)))
'
dr_stage_end; fi   # ── 단계 macro 끝 ──

# ──────────────────────────────────────────────────────────────────────────────
# [5] DART 재무제표 + Quarterly + Insider
#     (a) Annual 재무제표: 월 1회 — 이번 달에 아직 안 돌았으면(스탬프 .cache/dart/.annual_last_run_ym).
#         ★2026-10-08 수리: 구판은 '매월 1일만'이라 1일 실행을 놓치면 그 달 전체를 건너뛰었다
#           (10-01 미실행 → dart_raw_financials·fundamental_merged mtime 74일·38일 → 매일 CRITICAL).
#     (b) Quarterly 재무제표: 매일 (resume=TRUE incremental, 공시되는대로 즉시 반영)
#     (c) Insider 거래: 매일 (merge wrapper로 history 보존)
# ──────────────────────────────────────────────────────────────────────────────
DAY_OF_MONTH=$(date +%d)
if dr_want dart; then dr_stage_begin dart   # ── 단계 dart ──

# (a) Annual financials — monthly (첫 실행일 · 스탬프 기준)
DART_ANNUAL_STAMP="$BASE/.cache/dart/.annual_last_run_ym"
_DART_YM=$(date +%Y%m)
if [ "$(tr -d '\r\n ' < "$DART_ANNUAL_STAMP" 2>/dev/null)" != "$_DART_YM" ]; then
  echo "[5a/7] DART Annual Financials (monthly)..."
  cd "$INFRA"
  run_r '
    source("config.R")
    source("data/data_collector_dart.R")
    # years 미지정 = 제출창+커버리지 기반 후보집합 (2026-07-26 P2-01 수리).
    # 구 코드는 years = format(Sys.Date(), "%Y") 로 달력 현재연도 1개만 요청해
    # FY2025 사업보고서(2026-03 제출)를 영구 미수집 상태로 남겼다.
    # max_calls: 일 10,000콜 한도 중 이 스텝 예산 (fail-closed halt)
    tryCatch(dart_run_pipeline(max_calls = 3000),
      error = function(e) cat(sprintf("DART Annual skipped: %s\n", e$message)))
  '
  # fundamental_merged 월간 full rebuild (2026-07-17 배선 — registry는 monthly/35d SLA인데
  # 어느 스케줄에도 연결돼 있지 않아 매월 STALE_WARN 재발(반복 알림의 한 축)하던 gap 봉합)
  echo "[5a2/7] fundamental_merged monthly rebuild..."
  if "$RSCRIPT" --no-save "$INFRA/data/build_fundamental_derived.R"; then
    echo "$_DART_YM" > "$DART_ANNUAL_STAMP"   # 성공한 달만 찍는다 — 실패면 다음 날 재시도
  else
    echo "  [warn] build_fundamental_derived failed (fail-soft — 기존 cache 유지 · 스탬프 보류 → 내일 재시도)"
  fi
else
  echo "[5a/7] DART Annual + fundamental_merged skipped (이번 달 $_DART_YM 이미 실행)"
fi

# (b) + (c) Quarterly + Insider — daily incremental (도훈 mandate 2026-05-15)
echo "[5b/7] DART Quarterly + Insider Daily Incremental..."
cd "$INFRA"
run_r '
  source("config.R")
  source("data/dart_daily_incremental.R")
  tryCatch(dart_daily_incremental(),
    error = function(e) cat(sprintf("DART daily incremental skipped: %s\n", e$message)))
'
dr_stage_end; fi   # ── 단계 dart 끝 ──

# ──────────────────────────────────────────────────────────────────────────────
# [5c] 한국 FF 요인 수익(일간 · 월간) + 파마-맥베스 통제 특성(월간) 갱신 (2026-11-10 · 도훈 '팩터조정알파 및 파마-맥베스
#   분석에 쓰이는 기초데이터도 데일리로 최신화' · 빌더 data/build_kr_factor_returns.R · 설정 06_Registry/kr_factor_returns.json)
#   입력 = RAWDATA([1]) · 재무 v2 1단계 표 · CD91(ECOS) — 그래서 [5b] 뒤 · [6] 앞. 쓰기는 파일마다 원자적(임시 파일 → 이름
#   바꾸기)이라 실패해도 옛 파일이 남는다(fail-soft). 판 보관(kr_factor_returns_vintages/)은 월간 내용 md5 가 바뀔 때만 는다.
#   등급 노치(contracts/grade_v3.R::gv3_fa_ctx)는 meta md5 = 월간 내용 md5 일 때만 읽는다 — 둘이 어긋나면 노치를 계산하지 않는다.
# ──────────────────────────────────────────────────────────────────────────────
if dr_want krf; then dr_stage_begin krf   # ── 단계 krf ──
echo "[5c/7] 한국 FF 요인 수익 · 파마-맥베스 특성 갱신..."
( cd "$BASE" && QM_ROOT="$BASE" "$RSCRIPT" --no-save "$INFRA/data/build_kr_factor_returns.R" ); _krf_rc=$?
if [ "$_krf_rc" -ne 0 ]; then
  echo "!! [5c] FF 요인 갱신 실패(rc=$_krf_rc) — 옛 파일 유지"
  DR_FAILED+=("kr_factor_returns(rc=$_krf_rc)")
fi
dr_stage_end; fi   # ── 단계 krf 끝 ──

# ──────────────────────────────────────────────────────────────────────────────
# [6] Factor DB 갱신 (월간 [6a] + 일간 [6b]) — P1 수리 2026-06-10
#
#   ★ 함수명 혼동 주의 (이름과 실체가 어긋남 — 명문화):
#     - update_factor_db_daily()        [factor_db/factor_db_builder.R]
#         → "월간" Factor DB(.cache/factor_db/factor_db_YYYYMM.parquet)의 현재월
#           1파일을 빌드/스킵. 이름의 daily는 "cron 호출 주기"의 의미 (DB는 월간).
#     - update_daily_fdb(ym) / update_daily_fdb_current()
#                                       [factor_db/factor_db_daily_incremental.R]
#         → "일간" Factor DB(.cache/factor_db_daily/fdb_daily_YYYYMM.parquet) 갱신.
#           ⚠ update_daily_fdb(ym)는 미완 stub이며 내부에서 source(phase6)를 호출해
#           일간 DB "전 파일 삭제 후 1990~ 전체 재구축"을 트리거 (2026-06-10 검증,
#           factor_db_daily_incremental.R L41 + phase6 L42-48). update_daily_fdb_current()
#           역시 phase6+7+8 전체 재빌드(수시간). → cron 무인 자동호출 금지,
#           QVEST_FDB_DAILY_AUTOREBUILD=1 명시 시에만 실행 (기본 0 = stale WARN만).
# ──────────────────────────────────────────────────────────────────────────────
if dr_want fdb; then dr_stage_begin fdb   # ── 단계 fdb ──
echo "[6a/7] Factor DB update (monthly DB, current-month build)..."
cd "$INFRA"
run_r '
  source("config.R")
  source("factor_db/factor_db_builder.R")
  tryCatch({
    if (exists("update_factor_db_daily") && is.function(update_factor_db_daily)) {
      update_factor_db_daily()
    } else {
      cat("update_factor_db_daily() not found — skip.\n")
    }
  }, error = function(e) cat(sprintf("Factor DB update skipped: %s\n", e$message)))
'

# ── [6a-gate] 당월 배출 회귀 판독 (2026-09-23 W-02 · 도훈 승인 처방 §4) ────────────────
#   emission_guard.R 는 회귀(직전 빌드에선 났는데 이번엔 0행)를 emission_report_{ym}.json 에
#   정확히 적었지만 **읽는 코드가 0곳**이었다(202609 class_R=27 무보고). 빌드는 설계상
#   멈추지 않으므로 판정은 누군가 읽어야 경보가 된다 — 여기서 읽어 DR_FAILED 에 싣고,
#   [7] 텔레그램 본문(DR_FAILED_SO_FAR)에 이름 상위 5개가 실린다.
#   rc 0 = 회귀 0 · 3 = 회귀 N · 그 외 = 미측정(보고서 부재 등 — 정상으로 접지 않는다).
#   ★W-05 (2026-09-23): 판독 대상 달 = [6a] 가 실제로 빌드한 달(`_asof/_last_update.txt`).
#   구판 `date +%Y%m` 은 익월 1일에 전월 확정 빌드를 놓치고 빈 새 달을 읽었다.
#   빌드가 없던 날 = 데이터 경계 달(raw_ym) 재판독 · 상태 파일 부재([6a] 실패) = 오늘 달.
_eg_state="$BASE/.cache/factor_db/_asof/_last_update.txt"
_eg_yms="$(sed -n 's/^built=//p' "$_eg_state" 2>/dev/null | tr -d '\r')"
[ -n "${_eg_yms// /}" ] || _eg_yms="$(sed -n 's/^raw_ym=//p' "$_eg_state" 2>/dev/null | tr -d '\r')"
[ -n "${_eg_yms// /}" ] || { _eg_yms="$(date +%Y%m)"; echo "!! [6a-gate] 빌드 상태 파일 부재 — 오늘 달($_eg_yms)로 판독"; }
for _eg_ym in $_eg_yms; do
_eg_out="$(QM_ROOT="$BASE" "$RSCRIPT" --no-save "$INFRA/factor_db/emission_report_gate.R" --ym "$_eg_ym" 2>&1)"
_eg_rc=$?
printf '%s\n' "$_eg_out"
_eg_line="$(printf '%s\n' "$_eg_out" | grep '^EMISSION_GATE ' | tail -1)"
case "$_eg_rc" in
  0) echo "[6a-gate] $_eg_ym 배출 회귀 0" ;;
  3) _eg_n="$(printf '%s' "$_eg_line" | sed -n 's/.* n=\([0-9]*\).*/\1/p')"
     _eg_top="$(printf '%s' "$_eg_line" | sed -n 's/.* top=\([^ ]*\).*/\1/p')"
     echo "!! [6a-gate] ★$_eg_ym 팩터 배출 회귀 ${_eg_n:-?}종 — ${_eg_top:-?}"
     DR_FAILED+=("factor_emission_regress:$_eg_ym:${_eg_n:-?}(${_eg_top:-?})") ;;
  *) echo "!! [6a-gate] $_eg_ym 배출 판정 미측정(rc=$_eg_rc) — 정상으로 접지 않는다"
     DR_FAILED+=("factor_emission_regress:$_eg_ym:unmeasured") ;;
esac
done

echo "[6b/7] Daily Factor DB (fdb_daily) freshness + gated rebuild..."
export QVEST_FDB_DAILY_AUTOREBUILD="${QVEST_FDB_DAILY_AUTOREBUILD:-0}"
echo "[guard] QVEST_FDB_DAILY_AUTOREBUILD=$QVEST_FDB_DAILY_AUTOREBUILD (0=stale 감지+WARN만, 재빌드 안함)"
cd "$INFRA"
run_r '
  source("config.R")
  suppressPackageStartupMessages({library(arrow); library(data.table)})
  fdb_dir <- file.path(CACHE_DIR, "factor_db_daily")
  fs <- sort(list.files(fdb_dir, pattern = "^fdb_daily_[0-9]{6}\\.parquet$"))
  if (length(fs) == 0) {
    cat("[6b][WARN] fdb_daily 디렉토리 비어있음 — 일간 Factor DB 부재\n")
  } else {
    latest <- file.path(fdb_dir, fs[length(fs)])
    last_d <- tryCatch(
      max(as.Date(as.data.table(read_parquet(latest, col_select = "Date"))$Date), na.rm = TRUE),
      error = function(e) as.Date(NA))
    lag_d <- if (is.na(last_d)) NA_integer_ else as.integer(Sys.Date() - last_d)
    cat(sprintf("[6b] fdb_daily latest=%s max(Date)=%s lag=%s days (기대 ~3거래일)\n",
                fs[length(fs)], format(last_d), ifelse(is.na(lag_d), "NA", lag_d)))
    if (!is.na(lag_d) && lag_d > 5) {
      cat(sprintf("[6b][WARN] 일간 Factor DB stale (lag=%d일 > 5)\n", lag_d))
      if (Sys.getenv("QVEST_FDB_DAILY_AUTOREBUILD", "0") == "1") {
        cat("[6b] QVEST_FDB_DAILY_AUTOREBUILD=1 — update_daily_fdb_current() 실행 (phase6+7+8 전체 재빌드, 수시간 소요)\n")
        tryCatch({
          source("factor_db/factor_db_daily_incremental.R")
          update_daily_fdb_current()
        }, error = function(e) cat(sprintf("[6b] fdb_daily rebuild FAIL: %s\n", e$message)))
      } else {
        cat("[6b] 자동 재빌드 OFF (기본). 사유: update_daily_fdb(ym) 미완 stub이 phase6 전체재빌드(일간 DB 전파일 삭제 후 1990~ 재구축)를 source — cron 무인 실행 부적합 (2026-06-10 검증). 진짜 단일월 증분 구현 전까지 stale WARN만. 수동 갱신: QVEST_FDB_DAILY_AUTOREBUILD=1 또는 운영자 update_daily_fdb_range() 직접 실행.\n")
      }
    }
  }
'

# ──────────────────────────────────────────────────────────────────────────────
# [6d] 신규 팩터 이력 백필 — 예산제 scoped backfill (2026-09-01 도훈 지시 "업데이트까지 자동")
#   왜: [6a] 는 **당월 1파일**만 빌드한다. 생산자가 새로 생긴 계열(technical 12종)과 무인
#   등록된 논문 신호는 그래서 당월만 채워지고, 이력이 없으면 IC 가 안 서고, IC 가 없으면
#   B1 후보 풀에 못 들어간다 — "등재는 됐는데 아무도 못 쓴다" 가 그대로 재현된다.
#   ★전 구간 재빌드(수시간)를 스케줄에 넣는 것이 아니다. 빌더의 팩터 단위 scoped backfill 을
#   벽시계 예산까지만 돌리고, 안 끝나면 다음 밤이 이어받는다(진행 상태 = 이력 개월수, 커서 불요).
#   WARN: [6b] 의 fdb_daily 게이트와 다르다 — 그건 전 파일 삭제 후 1990~ 전체 재구축이다.
# ──────────────────────────────────────────────────────────────────────────────
echo "[6d/7] 신규 팩터 이력 백필 (예산제 scoped backfill)..."
export QVEST_FDB_BACKFILL_BUDGET_MIN="${QVEST_FDB_BACKFILL_BUDGET_MIN:-60}"
echo "[guard] QVEST_FDB_BACKFILL_BUDGET_MIN=$QVEST_FDB_BACKFILL_BUDGET_MIN (0=예산없음) · 정지=QVEST_FDB_NO_BACKFILL=1"
cd "$BASE"
if ! QM_ROOT="$BASE" Rscript "$BASE/02_Infrastructure/ops/rf_factor_backfill_tick.R"; then
  echo "[6d] 백필 tick 비정상 종료 — .cache/reinforce_auto_log.jsonl 참조(다음 밤이 이어받는다)"
fi

# ──────────────────────────────────────────────────────────────────────────────
# [6f] 등록부 방향 동기화 · 감시 (2026-11-09 · decision_register FACTOR-DIRECTION-TWO-VIEWS-20261109)
#   도훈 'C안으로 수정된 정책도 추후 팩터 DB 업데이트에 자동으로 반영되게끔'. 등록부 방향은 저장값 기준이고 위험 · 유동성 계열은
#   방어 방향을 따로 둔다. 새 팩터는 여러 길(add_factor.R · 세션이 고친 compute_*.R · 등록부를 다시 쓰는 R 도구)로 들어오므로
#   매일 같은 규칙으로 맞춘다: 새 엔트리 = 감사 표 자동 등재 + 필드 채움(소비자 direction 은 그대로) · 위험 계열 = 방어 방향 판정 대기 ·
#   손 편집 충돌 · 빌더 부호 드리프트 · 두 사본 불일치 = 고치지 않고 경보(DR_FAILED). 상세 = factor_db/DIRECTION_POLICY.md
#   rc 0 정상 · 3 경보 · 4 동시 변경(다음 밤) · 그 밖 = 미측정. 검사 = 08_Tests/factor_db/test_direction_sync.py
# ──────────────────────────────────────────────────────────────────────────────
echo "[6f/7] 등록부 방향 동기화 · 감시..."
if [ -n "$QVENV_PY" ]; then
  _ds_out="$(cd "$BASE" && QM_ROOT="$BASE" "$QVENV_PY" -I "$INFRA/factor_db/apply_direction_basis.py" --sync 2>&1)"
  _ds_rc=$?
  printf '%s\n' "$_ds_out" | head -40
  case "$_ds_rc" in
    0) : ;;
    3) DR_FAILED+=("direction_sync:alert($(printf '%s' "$_ds_out" | grep -m1 '^\[direction_sync\]' | sed 's/.*사본 \([a-z]*\).*충돌 \([0-9]*\).*드리프트 \([0-9]*\).*/사본 \1 · 충돌 \2 · 드리프트 \3/'))") ;;
    4) echo "  [6f] 읽은 뒤 등록부가 바뀌어(동시 쓰기) 쓰지 않음 — 다음 밤에 다시" ;;
    *) DR_FAILED+=("direction_sync:unmeasured(rc=$_ds_rc)") ;;
  esac
else
  echo "  [6f] QVENV_PY 부재 — 동기화 생략(미측정)"
  DR_FAILED+=("direction_sync:no_python")
fi

# ──────────────────────────────────────────────────────────────────────────────
# [6e] 결합용 팩터 뷰 증분 갱신 (2026-11-09 도훈 '결합용 뷰도 자동 업데이트 되게끔' · FACTOR-COMBINABLE-VIEW-20261109)
#   [6a] 당월 빌드 · [6d] 백필 · [6f] 등록부 동기화 뒤 — 바뀐 달 + 가장 최근 달 + 부호표 전부(등록부 방향 바뀜도 부호표가 흡수).
#   첫 전체 빌드는 별도(--build --full)이며 그 전에는 건너뛴다(fc_meta.json 없음). 다른 빌드가 잠금을 쥐면 건너뛴다(rc 5).
# ──────────────────────────────────────────────────────────────────────────────
if [ -f "$BASE/.cache/factor_combinable/fc_meta.json" ]; then
  echo "[6e/7] 결합용 팩터 뷰 증분 갱신..."
  ( cd "$BASE" && QM_ROOT="$BASE" "$RSCRIPT" --no-save "$INFRA/factor_db/factor_combinable.R" --build ); _fc_rc=$?
  case "$_fc_rc" in
    0) : ;;
    5) echo "  [6e] 다른 결합용 뷰 빌드가 잠금을 쥐고 있어 건너뜀(다음 밤)" ;;
    *) DR_FAILED+=("factor_combinable(rc=$_fc_rc)") ;;
  esac
else
  echo "[6e/7] 결합용 팩터 뷰 — 첫 전체 빌드 전(fc_meta.json 없음) · 건너뜀"
fi

# ──────────────────────────────────────────────────────────────────────────────
# [6g] 일간 · 월간 저장 대응표 월 1회 재측정 (2026-11-09 · FACTOR-DIRECTION-STORAGE-REPAIR-20261109)
#   load_daily_factors 가 월간 부호를 일간 값에 옮길 때 곱하는 표(06_Registry/factor_daily_monthly_parity.json). 새 팩터 · 빌더 정의
#   변경이 표에 들어오게 매달 다시 잰다(표에 없는 일간 팩터는 접근자가 정렬을 거부한다 — 안전한 기본값). 표가 27일 넘게 묵었을 때만.
# ──────────────────────────────────────────────────────────────────────────────
_par_json="$BASE/06_Registry/factor_daily_monthly_parity.json"
if [ -n "$QVENV_PY" ] && { [ ! -f "$_par_json" ] || [ -n "$(find "$_par_json" -mtime +27 2>/dev/null)" ]; }; then
  echo "[6g/7] 일간 · 월간 대응표 재측정(27일 경과)..."
  ( cd "$BASE" && QM_ROOT="$BASE" "$QVENV_PY" -I "$INFRA/factor_db/daily_monthly_parity.py" ) || DR_FAILED+=("daily_monthly_parity(rc=$?)")
else
  echo "[6g/7] 일간 · 월간 대응표 — 최근(27일 안) · 건너뜀"
fi

# ── [6v] 팩터 DB 판 표식 원장 누락 감시 (2026-11-10 감사 레인 A · data/factor_db_vintage_coverage.py · 읽기 전용) ──────────
#   수리 실행기 요약(성공)이 06_Registry/factor_db_vintage.json 에 안 올랐거나(수리 전 측정이 '현행'으로 남는다),
#   원장 최신 수리 뒤 당월 파일이 다시 안 쓰였으면([6a] 는 데이터 상태만 보고 7일 묵힌다) DR_FAILED. 원장은 고치지 않는다(writer = Q).
if [ -n "$QVENV_PY" ] && [ -f "$INFRA/data/factor_db_vintage_coverage.py" ]; then
  _fdv_line="$( cd "$BASE" && "$QVENV_PY" -X utf8 "$INFRA/data/factor_db_vintage_coverage.py" --root "$BASE" 2>&1 | tr -d '\r' | grep '^FDV_COVERAGE' | tail -n 1 )"
  echo "[6v/7] ${_fdv_line:-FDV_COVERAGE 출력 없음}"
  case "$_fdv_line" in
    *status=OK*) : ;;
    *status=GAP*) DR_FAILED+=("factor_db_vintage_gap") ;;
    *) DR_FAILED+=("factor_db_vintage_unmeasured") ;;
  esac
fi

# ──────────────────────────────────────────────────────────────────────────────
# [6c] conditional_ic_matrix 주간 재계산 (월요일) — 2026-07-25 배선
#   .cache/conditional_ic_matrix.csv — pit.md V6 Gap-Directed 가설 조향 캐시.
#   기존 producer 경로(memory/monthly_distill.sh)는 ① Windows 스케줄러 task 미등록
#   ② 기본 base STR_1375 holdings 소실의 이중 결함으로 2026-06-08 이후 스테일
#   (AST 리프 맵 §3-3). daily_refresh 주간 배선 + base fallback(stage_gate_engine.R
#   2026-07-25 수리)으로 봉합. upstream factor_ic_monthly가 월간 갱신이라 주간이면 충분.
#   실측 소요 1.2분 (RAWDATA full read 포함).
# ──────────────────────────────────────────────────────────────────────────────
DAY_OF_WEEK=$(date +%u)
if [ "$DAY_OF_WEEK" = "1" ]; then
  echo "[6c/7] conditional_ic_matrix weekly recompute (Monday)..."
  cd "$BASE"
  run_r '
    setwd("'"$BASE"'")
    suppressMessages({
      source("02_Infrastructure/config.R")
      source("02_Infrastructure/stage_gate_engine.R")
    })
    tryCatch({
      cond <- sg_compute_conditional_ic()
      cat(sprintf("[daily_refresh] conditional_ic_matrix refreshed: %d factors\n", nrow(cond)))
    }, error = function(e) cat(sprintf("conditional_ic recompute skipped: %s\n", e$message)))
  '
else
  echo "[6c/7] conditional_ic_matrix skipped (weekly Monday only, today=$DAY_OF_WEEK)"
fi

# ──────────────────────────────────────────────────────────────────────────────
# [6.5] Forward Weights Orchestrator (월말/리밸런싱 sig_date)
#   - 매월 1일에 3 마일스톤 admitted 전략의 forward production weights 자동 산출
#   - cap_0.20 mandate 강제 + capacity check
#   - measurement_basis_primary = "forge_realized_share_based"
#   - Plan v1.0 2026-04-29 (도훈 정도 회복 명령)
# ──────────────────────────────────────────────────────────────────────────────
DAY_OF_MONTH=$(date +%d)
if [ "$DAY_OF_MONTH" = "01" ] || [ "$DAY_OF_MONTH" = "15" ]; then
  echo "[6.5/7] Forward Weights Orchestrator (DAY_OF_MONTH=$DAY_OF_MONTH)..."
  cd "$INFRA"
  run_r '
    tryCatch({
      source("portfolio/forward_weights_orchestrator.R")
      .tg_on <- Sys.getenv("QVEST_REFRESH_TG", "0") == "1"   # v8.1.1 telegram guard
      if (!.tg_on) cat("[tg guard] QVEST_REFRESH_TG=0 — forward weights send_telegram off\n")
      orchestrate_forward_weights(
        as_of_date = NULL,           # default = max schedule date
        apply_mandate_cap = "cap_0.20",
        send_telegram = .tg_on
      )
    }, error = function(e) cat(sprintf("Forward weights orchestrator skipped: %s\n", e$message)))
  '
fi
dr_stage_end; fi   # ── 단계 fdb 끝 ──

# ──────────────────────────────────────────────────────────────────────────────
# [7] Telegram + NAV Tracking + Memory
# ──────────────────────────────────────────────────────────────────────────────
if dr_want nonret; then dr_stage_begin nonret   # ── 단계 nonret ──
echo "[6c/7] 비-return 원천 리프레시 (FQ-064 국민연금 · FQ-073 관세청)..."
# 2026-07-25 도훈 지시 "지금 수집하는 데이터들 모두 자동 리프레시되도록 배선".
#   두 원천 모두 **월간** 갱신이라 매일 호출해도 대부분 no-op이다(멱등):
#     - NPS   : 파일 이력 목록에 신규 월이 있을 때만 다운로드 → append (기존 월 덮어쓰기 금지)
#     - 관세청: 이번 달 스냅샷이 이미 있으면 skip. 없으면 append-only vintage 스냅샷 적립
#   ★관세청은 개정이 무기한 반복(매월 15일경 과거 전체 현행화)되므로 최신판 덮어쓰기는
#     소급 정보주입이다 — vintage_store 스냅샷이 권위이고 latest는 파생이다
#     (PIT_plan_fq073 §2-b2). 스냅샷 2개↑ 쌓이면 개정폭을 자동 실측한다(§2-c).
#   실패해도 파이프라인을 멈추지 않는다(비-핵심 원천, advisory).
if [ -n "$QVENV_PY" ]; then
  ( cd "$BASE" && "$QVENV_PY" 02_Infrastructure/data/refresh_nonreturn_sources.py --source all ) \
    || echo "  비-return 리프레시 skipped (다음 실행에서 재시도 — status JSON 참조)"
else
  echo "  QVENV_PY 부재 — 비-return 리프레시 skip"
fi
dr_stage_end; fi   # ── 단계 nonret 끝 ──

DR_STALE_NAMES=""
# ── [0c] 적재 검증 — "돌렸다"가 아니라 "늘었나"를 잰다 ────────────────────────
#   구판에는 이 축이 아예 없었다. Gate A 는 **다운로드**(qw_refresh_state.json)만,
#   Gate B 는 팩터DB **앵커**만 보는데 그 앵커는 신선한 주가 축이 채운다 — 그래서
#   컨센서스가 한 달 멈춰도 둘 다 초록이었다.
#   ★판정을 여기서 다시 구현하지 않는다(도훈 지적 2026-08-30 "검사기를 굳이 왜 만드나").
#     신선도 정본은 morning_steps/freshness_audit.R 하나뿐이고, 전략 소비 패널 5종
#     (rawdata·consensus·investor_act·universe_support·fred_wide)을 거기 등재했다.
#     여기서는 그 감사기를 **호출하고 판정을 읽을 뿐**이다. 같은 값을 두 곳에서 만들면
#     반드시 갈라진다 — ensure_data_current.sh 헤더가 적어둔 그 원칙이다.
#   ★fail-soft: daily_refresh 는 브리핑·수집 체인이라 여기서 중단하면 무관한 하류가
#     다 죽는다. DR_FAILED 에 실려 종료코드·요약에 반영되고, **리밸 경로는
#     book_rebalance_preflight.py 가 같은 축을 fail-closed 로 다시 잰다**.
#   ★v10.4 (2026-09-24) 두 가지를 고쳤다(문턱은 그대로):
#     ① 측정 시점 = 적재 **후**. 원래 [0b] 직후(적재 전)에 있어 벤치·RAWDATA·MSM·KTRI·국면이 들어오기 전 상태를 쟀다.
#        로그 접두어 [0c] 는 유지한다(소비자 grep 호환 — 스텝 번호가 아니라 이 검증의 이름이다).
#     ② 하류 산출물 판정 제외(보고 줄은 유지). freshness_audit.R 이 role=downstream 으로 표시한 항목(p3_forecast —
#        브리핑 [6a] 산출물, 리프레시가 고칠 수 없다)은 DR_FAILED 에 싣지 않는다. 목록 원천 = 감사기 JSON downstream_items
#        하나(여기서 다시 적지 않는다). 키가 없는 구판 JSON 이면 종전대로 전부 판정(보수적). 선례: ensure_data_current.sh:128.
#        실측 09-23·09-24: P3 최대일이 09-18 로 돌아간 것(09-22 PC 절전 · 09-23 장중 행 제거)이 DR exit 1 로 둔갑했다.
echo "[0c/7] 적재 신선도 검증 (정본 감사기 경유 · 적재 후 측정)..."
cd "$BASE"
QVEST_FRESHNESS_QUIET=1 QM_ROOT="$BASE" "$RSCRIPT" --no-save \
  "$INFRA/ops/morning_steps/freshness_audit.R" \
  || echo "[0c] 감사기 rc!=0 — 판정은 아래 JSON 으로 읽는다"
_FA_JSON="$BASE/qepm/observability/morning_freshness_latest.json"
_FA_PY="$BASE/.venv_qvest_ml/Scripts/python.exe"
if [ -x "$_FA_PY" ]; then
  _FA_ST="$("$_FA_PY" - "$_FA_JSON" <<'PYEOF' 2>/dev/null
import io, json, sys
try:
    o = json.load(io.open(sys.argv[1], encoding="utf-8-sig"))
except Exception:
    print("UNREADABLE"); raise SystemExit
s = [str(x) for x in (o.get("stale_items") or [])]
ds = o.get("downstream_items")
ds = set([ds] if isinstance(ds, str) else [str(x) for x in ds]) if isinstance(ds, (list, str)) else set()
act = [x for x in s if x.split("(", 1)[0] not in ds]
exc = [x for x in s if x.split("(", 1)[0] in ds]
names = " ".join(sorted(set(x.split("(", 1)[0] for x in act)))
print(("OK" if not act else "STALE:" + ",".join(act)) + "|" + ",".join(exc) + "|" + names)
PYEOF
)"
  _FA_ST="${_FA_ST%$'\r'}"
  # 구분자 '|' — 탭은 IFS 공백류라 빈 칸이 접혀 필드가 밀린다(OK\t\tbenchmark → 제외목록=benchmark).
  IFS='|' read -r _FA_V _FA_EXCL DR_STALE_NAMES <<< "$_FA_ST"
  [ -n "${_FA_EXCL:-}" ] && echo "[0c] ※ 하류 산출물이라 판정 제외(보고만): $_FA_EXCL — 브리핑 [6a] 생산 · 사후 계기 p3_brief_send.R STALE-GATE / mrs_daily 재감사"
  case "$_FA_V" in
    OK) echo "[0c] 전 소스 FRESH — 소비면이 최신 거래일에 도달" ;;
    STALE:*) echo "[0c] ★적재 미달: ${_FA_V#STALE:} — 하류가 낡은 축을 쓴다"
             DR_FAILED+=("ingest_freshness") ;;
    *) echo "[0c] 감사 판정 판독 불가 — 미측정(미달로 접지 않는다)"
       DR_FAILED+=("ingest_freshness:unreadable") ;;
  esac
else
  echo "[0c] venv python 부재 — 판정 판독 생략(미측정)"
  DR_FAILED+=("ingest_freshness:no_python")
fi
cd "$INFRA"

# ── 데이터 갱신 완료 → 잠금 해제 (2026-10-08 도훈 지시 "업데이트 다 되면 그냥 끝내") ──────────────
#   이 잠금은 재진입 가드(중복 인스턴스의 DART 쿼터 소진·캐시 경합 방지)이자 무인 레인이 읽는 리프레시
#   대기 신호다. 둘 다 데이터 적재 구간([0]~[6] · [0c] 적재 감사)만 지키면 된다. 구판은
#   trap EXIT 로 후처리([7]~[9] 텔레그램·배선 지도·역할 재분류·위생 감사)까지 쥐어 충실구현·강화 레인을
#   1시간 넘게 막았다(2026-10-08 실측 68분+ · 그 사이 tick 전부 halt_refresh_lock).
rm -rf "$LOCKDIR"; trap - EXIT
echo "[lock] 데이터 갱신 완료 — 리프레시 잠금 해제(후처리는 잠금 없이 계속)"

echo "[7/7] Telegram + NAV + Memory..."
cd "$INFRA"
# (2026-07-26 DR-01) 지금까지의 실패 스텝을 R 로 넘겨 본문에 병기 — "완료" 만 보내던
#   구판은 스텝 절반이 죽어도 성공 통보였다. 이 시점까지의 누적을 쓴다(이후 [8][9]는 별도).
export DR_FAILED_SO_FAR="$(dr_fail_summary)"
# ★v10.4 (2026-09-24) [0c] 가 낸 적재 미달 항목명(숫자 없는 이름) — [7] 실패 서명의 재료(dr_fail_signature.R).
export DR_STALE_NAMES="${DR_STALE_NAMES:-}"
run_r '
  library(data.table)
  source("config.R")
  source("telegram/telegram_notify.R")
  raw <- as.data.table(arrow::read_parquet(RAWDATA_CACHE, col_select = c("Date", "Ticker")))   # (11-10) 본문은 날짜 · 종목 수 · 행 수뿐 — 전 열 판독 생략
  last_d <- max(raw$Date)
  n_tickers <- uniqueN(raw[Date == last_d]$Ticker)
  .fails <- Sys.getenv("DR_FAILED_SO_FAR", "없음")
  # ★v10.4 (2026-09-24) 실패 서명 게이트 — 같은 원인 반복은 무음 요약(푸시 없음 · 채팅엔 남음), 원인이 바뀌면 경보,
  #   실패가 비면 해소 1회. 판정·상태 = data/dr_fail_signature.R (검사 08_Tests/data/test_dr_fail_signature.R).
  #   게이트를 못 읽으면 종전 헤더로 그대로 보낸다(통보 자체는 절대 막지 않는다).
  .sig_path <- file.path("..", ".cache", "dr_fail_signature.json")
  .dec <- tryCatch({
    source("data/dr_fail_signature.R")
    dr_sig_decide(.fails, Sys.getenv("DR_STALE_NAMES", ""), dr_sig_read(.sig_path))
  }, error = function(e) { cat("[7] 서명 게이트 판독 실패 — 종전 헤더로 발송:", conditionMessage(e), "\n"); NULL })
  # 최상위 if/else 는 반드시 중괄호로 묶는다 — R 은 줄바꿈에서 if 문을 닫아버려
  # 다음 줄의 else 가 고아가 된다("unexpected else"). 이 블록이 죽으면 일일 성공/실패
  # 통보 자체가 발송되지 않는다(2026-08-02 실측: DailyRefresh rc=1 의 단독 원인).
  .hdr <- if (!is.null(.dec)) {
    .dec$hdr
  } else if (identical(.fails, "없음")) {
    "[Daily Refresh v2 완료]"
  } else {
    sprintf("[Daily Refresh v2 ★부분실패 — %s]", .fails)
  }
  msg <- sprintf("%s\nRAWDATA: %s까지 (%d tickers)\n총 %s rows",
                 .hdr, last_d, n_tickers, format(nrow(raw), big.mark=","))
  # (11-10) 자가 복구 실행(ensure_data_current · QVEST_REFRESH_TG=0)도 이 보고 1통만은 서명 관문을 거쳐 보낸다 — QVEST_DR_REPORT_TG=1.
  #   그 밖의 발송(셀 감사 · 선행 비중 · NAV)은 QVEST_REFRESH_TG 를 따른다(자가 복구에선 꺼짐).
  if (Sys.getenv("QVEST_REFRESH_TG", "0") == "1" || Sys.getenv("QVEST_DR_REPORT_TG", "0") == "1") {     # v8.1.1 telegram guard
    # ★반환값을 읽는다(v10.4) — tg_send 는 HTTP 실패를 예외가 아니라 list(ok=FALSE) 로 돌려준다(TG-01).
    #   구판은 값을 버려 발송 실패가 성공과 구분되지 않았다. 아래 한 줄이 task_health 자기보고 면제의 증거다
    #   (scheduler_task_health.sh (C) — tg_sent=TRUE ∧ reported == Done 목록일 때만 DR exit_1 을 경보에서 뺀다).
    #   mute 인자를 모르는 구판 모듈이면(되돌림 등) mute 없이 보낸다 — 인자 불일치가 통보 자체를 죽이면 안 된다.
    .r <- tryCatch(if ("mute" %in% names(formals(tg_send))) tg_send(msg, mute = isTRUE(.dec$mute)) else tg_send(msg),
                   error = function(e) { cat("TG send failed:", e$message, "\n"); list(ok = FALSE) })
    .ok <- isTRUE(.r$ok)
    if (.ok && !is.null(.dec)) {
      tryCatch(dr_sig_commit(.sig_path, .dec$state),
               error = function(e) cat("[7] 서명 상태 기록 실패:", conditionMessage(e), "\n"))
    }
    cat(sprintf("[7] tg_sent=%s reported=%s\n", if (.ok) "TRUE" else "FALSE", .fails))
  } else {
    cat("[tg guard] QVEST_REFRESH_TG=0 — 발송 skip. msg:\n", msg, "\n")
    cat(sprintf("[7] tg_sent=SKIPPED reported=%s\n", .fails))
  }
'
DR_REPORTED=1; dr_state_write running

# ── 후처리 · 배터리 — 자가 복구 실행이면 건너뛴다(밤 실행이 이미 돌렸다 · 11-10 아침 브리핑 5시간 40분 지연의 대부분) ──
if [ "$DR_MODE" = "selfheal" ]; then
  echo "[post] 자가 복구 실행 — 후처리(NAV · 증류 · [7.9] 위생 · [8] 색인 · [8.1] 배선 지도 · [8.1r] 역할 · [8.2] 모듈 성능) 건너뜀"
  printf '%s\n' "[9] 시험 배터리 건너뜀(자가 복구 실행 · 모드 selfheal${QVEST_DR_SKIP_BATTERY:+ · QVEST_DR_SKIP_BATTERY=$QVEST_DR_SKIP_BATTERY})"
else

# NAV Tracking
WATCHLIST="$INFRA/nav_watchlist.json"
if [ -f "$WATCHLIST" ] && [ "$(cat "$WATCHLIST" | wc -c)" -gt 5 ]; then
  cd "$INFRA" && run_r '
    source("config.R")
    source("telegram/telegram_notify.R")
    # v8.1.1 telegram guard — QVEST_REFRESH_TG=0이면 tg_send를 로그 no-op으로 shadow
    if (Sys.getenv("QVEST_REFRESH_TG", "0") != "1")
      tg_send <- function(msg, ...) { cat("[tg guard] skip:", substr(msg, 1, 80), "\n"); invisible(NULL) }
    source("portfolio/daily_nav_tracker.R")
    nav_track()
    tryCatch(source("portfolio/regime_change_detector.R"), error=function(e) cat("regime_change_detector skipped\n"))
    detect_regime_change()
  ' 2>&1
fi

# Memory Distillation
# 2026-07-25 수리: 구 블록은 update_memory_summary()(현행 경로 부재 no-op이자 MEMORY.md
#   정규식 덮어쓰기 함수)를 호출하고 결과와 무관하게 "MEMORY.md updated"를 출력 —
#   침묵 성공 위장. 현행 Ledger(knowledge_index/hypothesis_index) 카운트 보고로 교체.
cd "$BASE"
run_r '
suppressMessages({
  source("02_Infrastructure/config.R")
  source("02_Infrastructure/memory/distill_stats.R")
})
s <- tryCatch(qv_ledger_stats(), error = function(e) NULL)
r <- tryCatch(qv_recent_research(1L), error = function(e) NULL)
if (is.null(s) || identical(s$source, "missing")) {
  cat("[distill] ledger 카운트 불가 — knowledge_index.json 부재/파싱실패\n")
} else {
  cat(sprintf("[distill] Ledger: Law %s / Distilled %s / L-code %s (idx %s)\n",
              s$law, s$distilled, s$lcode, substr(s$generated_at %||% "NA", 1, 10)))
}
if (!is.null(r)) cat(sprintf("[distill] 최근 1일 판정 %d건 [%s]\n", r$n, qv_verdict_line(r, 3L)))
' 2>&1

# [7.9] Artifact hygiene audit (자동정리 log90d/scratch30d/빈디렉토리 + 위반감지 → 06_Registry/hygiene_report.json. fail-soft. 2026-07-04 파일위생 mandate)
"$RSCRIPT" --no-save "$INFRA/ops/artifact_hygiene_audit.R" || echo "[warn] artifact hygiene audit failed (fail-soft)"

# [8] Artifact index 재생성 (fail-soft — 실패해도 refresh 전체는 계속. 2026-07-04 저장규칙 재편)
"$RSCRIPT" --no-save "$INFRA/tools/build_artifact_index.R" || echo "[warn] artifact index rebuild failed (fail-soft)"

# [8.1] 배선 지도 재생성 (2026-08-08 신설, 도훈 지시) — 표준↔소비자 지도 + 드리프트 감지.
#   왜 매일 돌리나: 정적 지도는 만든 순간부터 낡고 **낡은 지도는 "배선 완료"로 위장한다**.
#   exit 2 = 소비자 수가 기준선보다 감소(= 누군가 표준을 우회하기 시작) — 경고만, refresh 는 계속.
#   기준선 갱신(--set-baseline)은 자동으로 하지 않는다: 자동 갱신하면 악화가 매일 새 기준선으로
#   흡수돼 **드리프트가 영원히 안 잡힌다**(래칫이 래칫이 아니게 됨). 개선 반영은 수동 판단.
_wm_rc=0
"$RSCRIPT" --no-save "$INFRA/ops/wiring_map_build.R" || _wm_rc=$?
if [ "${_wm_rc:-0}" -eq 2 ]; then
  echo "[warn] ★배선 드리프트 — 표준 소비자 수 감소 (06_Registry/wiring_map.json drift 절 확인)"
elif [ "${_wm_rc:-0}" -ne 0 ]; then
  echo "[warn] wiring map rebuild failed rc=$_wm_rc (fail-soft)"
fi

# [8.1r] 전략 역할 재분류 + 역할 대표 등재 (2026-10-07 도훈 결정 — 2계층 풀 = 역할 대표 · strategy_role.json pool.mode)
#   왜 매일: [8.2] 풀이 06_Registry/strategy_roles.json 의 대표만 받는다. 재분류가 멈추면 강화 러너가 새로 만든
#   칸·신규 논문 기저가 풀에 영영 못 들어간다(호출 계기 부재 = [8.2] 의 56일 정지와 같은 기전).
#   순서: 분류(레지스트리 갱신) → 미등재 대표 카탈로그 등재 → [8.2] 풀 조립. fail-soft(실패해도 직전 레지스트리로 풀은 조립된다).
_role_log="/tmp/qm_role_classify_$(date +%Y%m%d).log"
if ( cd "$INFRA/ops" && "$RSCRIPT" -e 'source("rf_role_classify_all.R")' >"$_role_log" 2>&1 && \
     "$RSCRIPT" -e 'source("rf_role_register_reps.R")' >>"$_role_log" 2>&1 ); then
  grep -a "분류 \|풀 대표 고유\|레지스트리 기록\|대상 " "$_role_log" | sed 's/^/[8.1r] /' || true
else
  echo "[warn] [8.1r] 역할 재분류/등재 실패 (fail-soft — 직전 레지스트리로 풀 조립) — 로그 $_role_log"
  tail -n 5 "$_role_log" 2>/dev/null || true
fi

# [8.2] FR 모듈 성능 레지스트리 재생성 (2026-08-08, FQ-056) — screen-tier 재고를
#   factor-rotation 소비면에 도달시키는 배관. fail-soft.
#   ★왜 정기 실행이 필요한가: 이 스크립트는 배선돼 있었지만 **on-demand 진입점
#   (run_factor_rotation.R:32)에만** 매달려 있었다. 그 모드를 사람이 안 띄우면 갱신이 멈춘다 —
#   실측 2026-08-08: generated=2026-06-13 로 **56일 정지**, 재실행 시 모듈 192→209(+17).
#   "죽은 코드"도 "실행 실패"도 아닌 **호출 계기 부재**였다.
#   ★신선도 게이트를 일부러 두지 않는다: 이 저장소는 게이트가 영구-참이 되어 7주간
#   같은 캐시를 재보고한 실사고가 있다(project-paper-dispatch-risk-optimizer-never-research).
#   이 빌드는 멱등(재실행 209 동일)이고 수 분이므로 무조건 실행이 더 안전하다.
#   ★C11(2026-09-25): 출력을 /dev/null 로 버리지 않는다 — 국면 분할 성과(per_regime)의 C11 상태
#   (avail_annotated = 산출 · withheld_legacy_panel = 보류 null)가 이 스텝에서만 보인다(구판은 전부 null 을 침묵).
_bmp_log="/tmp/qm_module_performance_$(date +%Y%m%d).log"
if "$RSCRIPT" --no-save "$INFRA/regime/build_module_performance.R" >"$_bmp_log" 2>&1; then
  grep -a "★C11\|module_performance.json written\|편입 경로" "$_bmp_log" || true
  grep -o '"per_regime_pit_c11": *"[a-z_]*"' "$BASE/06_Registry/module_performance.json" 2>/dev/null \
    | sort | uniq -c | sed 's/^/[8.2] per_regime_pit_c11 /' || true
else
  echo "[warn] module_performance rebuild failed (fail-soft) — 로그 $_bmp_log"
  tail -n 5 "$_bmp_log" 2>/dev/null || true
fi

# [9] 스위트 총계 수집 (2026-07-25) — 계측 사망은 '실패'가 아니라 '총계 감소'로 온다.
#     여기서 매일 수집해야 bootstrap 의 --check 가 최신값을 비교한다(수동 수집 의존 제거).
#     fail-soft: 러너가 죽어도 refresh 전체는 계속 — 다만 그 경우 null 로 기록되어
#     다음 --check 가 "수치 없음은 정상이 아니다"로 경고한다.
#   ★(2026-11-10 · 도훈 '시험 배터리를 층으로') 평일 밤 = nightly 층 · 토요일 밤 = weekly(전체) — 러너 계약 QVEST_BATTERY_TIER.
#     11-10 실측: 전 배터리(10,975개)가 밤 2시간 30분 · 아침 2시간 56분. 층을 모르는 옛 러너는 변수를 무시하고 전체를 돈다.
if [ "${QVEST_DR_SKIP_BATTERY:-0}" = "1" ]; then
  printf '%s\n' "[9] 시험 배터리 건너뜀(QVEST_DR_SKIP_BATTERY=1)"
else
  _bt_tier="$(dr_battery_tier)"; _bt_t0=$(date +%s)
  printf '%s\n' "[9] 시험 배터리 층=$_bt_tier (QVEST_BATTERY_TIER — 토요일 밤 = weekly · 그 밖 = nightly)"
  QVEST_BATTERY_TIER="$_bt_tier" bash "$INFRA/ops/suite_totals_watch.sh" --collect || echo "[warn] suite totals collect failed (fail-soft)"
  printf '%s\n' "[9] 시험 배터리 끝 · $(( $(date +%s) - _bt_t0 ))초"
fi
fi   # ── 후처리 · 배터리(자가 복구면 건너뜀) 끝 ──

# (2026-07-26 DR-01) 실패 스텝을 이름으로 표면화 + 종료코드 반영.
#   "Done" 이 무조건 찍히던 구판은 크론·bootstrap 어느 쪽에도 실패 신호를 주지 못했다.
_dr_final_rc=0; [ "${#DR_FAILED[@]}" -gt 0 ] && _dr_final_rc=1
dr_state_write done "$_dr_final_rc"
[ -n "${QVEST_DR_SNAPSHOT:-}" ] && rm -f "$QVEST_DR_SNAPSHOT" 2>/dev/null   # 실행 사본 정리(실패해도 다음 실행이 2일 지난 사본을 지운다)
echo "[run] 총 소요 $(( $(date +%s) - DR_RUN_T0 ))초 · 모드 $DR_MODE${DR_ONLY:+ · 단계 $DR_ONLY}"
if [ "${#DR_FAILED[@]}" -gt 0 ]; then
  echo "=== Daily Refresh v2 Done — ★실패 ${#DR_FAILED[@]}스텝: $(dr_fail_summary) @ $(date) ==="
  exit 1
fi
echo "=== Daily Refresh v2 Done (실패 0) @ $(date) ==="
