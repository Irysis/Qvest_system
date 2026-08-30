#!/usr/bin/env bash
#==============================================================================
# Daily Data Refresh v2 — 매일 0시3분 실행
# crontab: 3 0 * * * bash "...daily_refresh.sh"
#
# 파이프라인 (v2 — Universe xlsx 의존 제거, Factor DB 연결):
#   [0] QuantiWise xlsx 증분 (OHLCVS/Consensus/Fundamental/Investor/Support)
#   [1] KRX API gap-fill (항상 실행)
#   [2] Naver T+0 보완
#   [3] Universe 갱신 (KRX API 기반) + RAWDATA 메타 매핑
#   [4] Arrow/FRED/KTRI/Regime
#   [5] DART (월 1회)
#   [6] Factor DB 갱신
#   [7] Telegram + NAV
#==============================================================================
set -uo pipefail
LOGFILE="/tmp/qm_daily_refresh_$(date +%Y%m%d).log"
exec > >(tee -a "$LOGFILE") 2>&1

echo "=== Daily Refresh v2 @ $(date) ==="

# ── 재진입 가드 (2026-06-11): 동시 2+ 인스턴스가 DART 쿼터 소진(10905종목 × N중복)·캐시 경합 유발 ──
#   실증: 2026-06-10 21:31/21:32 + 06-11 00:03/07:55/08:24 — 12시간 내 5중복 관측
LOCKDIR="/tmp/qm_daily_refresh.lock"
if mkdir "$LOCKDIR" 2>/dev/null; then
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

source "$(dirname "${BASH_SOURCE[0]:-$0}")/../ops/resolve_project.sh"
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
#──────────────────────────────────────────────────────────────────────────────
DR_FAILED=()
DR_STEP=0
run_r() {
  local _tmp _rc
  DR_STEP=$((DR_STEP + 1))
  _tmp=$(mktemp /tmp/qm_refresh_XXXX.R) || {
    echo "[run_r] mktemp failed"; DR_FAILED+=("r${DR_STEP}:mktemp"); return 1; }
  printf '%s\n' "$1" > "$_tmp"
  "$RSCRIPT" --no-save "$_tmp"
  _rc=$?
  rm -f "$_tmp"
  if [ "$_rc" -ne 0 ]; then
    DR_FAILED+=("r${DR_STEP}(rc=$_rc)")
    echo "[run_r] ★r${DR_STEP} FAILED rc=$_rc — 체인은 계속되나 최종 종료코드·요약에 반영됨"
  fi
  return $_rc
}
# 실패 요약 문자열 (set -u 안전 — 빈 배열 확장 회피)
dr_fail_summary() {
  if [ "${#DR_FAILED[@]}" -eq 0 ]; then printf '없음'; else printf '%s' "${DR_FAILED[*]}"; fi
}

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
echo "[0c/7] 적재 신선도 검증 (정본 감사기 경유)..."
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
s = o.get("stale_items") or []
print("OK" if not s else "STALE:" + ",".join(map(str, s)))
PYEOF
)"
  case "$_FA_ST" in
    OK) echo "[0c] 전 소스 FRESH — 소비면이 최신 거래일에 도달" ;;
    STALE:*) echo "[0c] ★적재 미달: ${_FA_ST#STALE:} — 하류가 낡은 축을 쓴다"
             DR_FAILED+=("ingest_freshness") ;;
    *) echo "[0c] 감사 판정 판독 불가 — 미측정(미달로 접지 않는다)"
       DR_FAILED+=("ingest_freshness:unreadable") ;;
  esac
else
  echo "[0c] venv python 부재 — 판정 판독 생략(미측정)"
  DR_FAILED+=("ingest_freshness:no_python")
fi
cd "$INFRA"

# ──────────────────────────────────────────────────────────────────────────────
# [1pre] Benchmark (KOSPI200) chart-API 단일 SOT — v8.0 fix (c) 2026-05-29
#   naver_kospi200_close() live 현재가+Sys.Date() 경로 폐기 (장중 phantom 방지).
#   benchmark.parquet은 여기서만 갱신 → 아래 [1] naver merge가 실제 종가로 BM_Ret lookup.
# ──────────────────────────────────────────────────────────────────────────────
echo "[1pre/7] Benchmark (KOSPI200 chart-API)..."
# Python 체인 (v8.1.1): venv 우선 → QVEST_PY env → 시스템 Python312 fallback
QVENV_PY=""
for _c in "$BASE/.venv_qvest_ml/Scripts/python.exe" "$BASE/.venv_qvest_ml/bin/python" "/home/quant/.venvs/qvest_ml/bin/python" \
          "${QVEST_PY:-}" "/c/Users/99922/AppData/Local/Programs/Python/Python312/python.exe"; do
  [ -n "$_c" ] && [ -x "$_c" ] && QVENV_PY="$_c" && break
done
_bm_rc=0
if [ -n "$QVENV_PY" ]; then
  ( cd "$INFRA" && "$QVENV_PY" data/naver_benchmark_update.py --start_date "$(date -d '10 days ago' +%Y-%m-%d)" )     || _bm_rc=$?
  if [ "$_bm_rc" -ne 0 ]; then
    echo "  benchmark chart-API update FAILED rc=$_bm_rc (기존 cache 유지)"
  fi
else
  _bm_rc=127
  echo "  python 미발견 - benchmark chart-API update skipped (기존 cache 유지)"
fi

# --- BMG-01 거래일 지평선 게이트 (2026-08-20 신설) ---------------------------
#   위 갱신기는 .cache/benchmark.parquet 의 **유일한 writer** 이고(그 스크립트 L64 가
#   스스로 "저장 단일점"이라 선언), trading_calendar.R 은 RAWDATA 자기참조의 순환오염을
#   끊으려고 **그 파일만을** 거래일 권위로 삼는다(L45/L137).
#   ★그래서 이 스텝의 실패를 삼키면 결손이 **사라진다**: 캘린더가 얼고 -> Naver 는
#   "already >= target", KRX 는 "gap 0 days" 를 **정직하게** 보고하며 리프레시는
#   "실패 0" 으로 마감한다. 실측 2026-08-14~20: 거래일 3일(08-18/19/20)이 비었는데
#   6일 내내 매일 "성공"으로 끝났다 - fail-soft 가 지평선을 삼킨 것.
#   게이트는 A축(갱신기 rc)과 B축(파일 정체)을 따로 본다.
#   검사: 08_Tests/data/test_benchmark_currency_gate.R (위반 주입 11/11, 실사고 재현 포함)
if ! "$RSCRIPT" --no-save "$INFRA/data/benchmark_currency_gate.R" --updater-rc "$_bm_rc"; then
  DR_FAILED+=("benchmark_currency(rc=$_bm_rc)")
  echo "!! [1pre] ★거래일 지평선 이상 - 하류 gap 판정이 무의미해진다 (위 [bm-gate] 사유 참조)"
fi

# ──────────────────────────────────────────────────────────────────────────────
# [1] Naver T+0 (PRIMARY — KRX T+1 lag 회피, 2026-04-24 변경)
#     Naver가 장중/장마감 직후 전일 종가 즉시 반영. RAWDATA 최신화 주력.
# ──────────────────────────────────────────────────────────────────────────────
echo "[1/7] Naver T+0 Primary Pipeline..."
cd "$INFRA"
run_r '
  source("config.R")
  source("data/trading_calendar.R")   # [Track R fix 2026-06-12] 거래일 가드 활성화 (필수)
  source("data/naver_data_collector.R")
  suppressPackageStartupMessages({library(data.table); library(arrow)})
  before <- tryCatch(max(as.Date(as.data.table(read_parquet(RAWDATA_CACHE))$Date), na.rm=TRUE), error=function(e) NA)
  tryCatch(naver_run_pipeline(),
    error = function(e) cat(sprintf("Naver pipeline failed: %s\n", e$message)))
  # [v8.0 fix] 병합 실패 silent swallow 방지 — RAWDATA 미전진 시 명시 WARNING (07:10 self-heal 전 조기 감지)
  after <- tryCatch(max(as.Date(as.data.table(read_parquet(RAWDATA_CACHE))$Date), na.rm=TRUE), error=function(e) NA)
  if (is.na(after) || (!is.na(before) && after <= before && as.integer(Sys.Date() - after) > 1))
    cat(sprintf("[WARN] Naver RAWDATA NOT advanced (before=%s after=%s) — KRX fallback/self-heal 의존\n", before, after))
'

# ──────────────────────────────────────────────────────────────────────────────
# [2] KRX gap-fill (FALLBACK — Naver 미처리 gap만 보충)
#     KRX API는 T+1 lag 있으므로 Naver 이후 남은 gap만 채움.
# ──────────────────────────────────────────────────────────────────────────────
echo "[2/7] KRX gap-fill (fallback)..."
cd "$INFRA"
run_r '
  source("config.R")
  source("data/trading_calendar.R")   # [Track R fix 2026-06-12] interior gap 감지 + 거래일 가드 활성화
  source("data/krx_data_collector.R")
  source("data/krx_build_rawdata.R")
  gap <- krx_detect_gap()
  # [v8.0 fix 2026-05-29 B4] interior gap 감지 추가 — Naver T+0가 최신 스냅샷만 추가해
  # 중간 영업일(예: 5/28) 누락 시 trailing gap은 작아도 hole 발생. interior 있으면 KRX backfill.
  interior <- tryCatch(krx_detect_interior_gaps(60L), error = function(e) character(0))
  cat(sprintf("Post-Naver gap: %s → %s (%d days) | interior gaps: %d\n",
              gap$last_rawdata_date, gap$end, gap$n_calendar_days, length(interior)))
  if (gap$n_calendar_days > 1 || length(interior) > 0) {
    # trailing 2일+ OR 중간 누락 → KRX fallback (trailing 1일은 정상 — 당일 미발행이라 미트리거)
    cat(sprintf("KRX fallback 실행 (trailing=%d days, interior=%d)\n",
                gap$n_calendar_days, length(interior)))
    tryCatch(krx_run_pipeline(),
             error = function(e) cat(sprintf("KRX skipped: %s\n", e$message)))
  } else {
    cat("Naver로 gap 충분 해소 (trailing + interior clean) — KRX skip\n")
  }
'

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

# ──────────────────────────────────────────────────────────────────────────────
# [4] Arrow / FRED / KTRI / Regime Signal
# ──────────────────────────────────────────────────────────────────────────────
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
# MSM Daily + Hybrid Refit (도훈 mandate 2026-05-15)
# Primary: 04_Research/regime_comparison/msm_update.R (Production-aligned, hybrid + daily 양쪽 write)
# Fallback: 02_Infrastructure/regime/msm_daily_refit.R (lightweight, daily only)
# 순서 critical: MSM 먼저 → build_regime_signal_table() 그 후 (unified_regime_signal stale 방지)
cd "$BASE"
run_r '
  setwd("'"$BASE"'")
  tryCatch({
    source("02_Infrastructure/config.R")
    source("02_Infrastructure/backtest_harness.R")
    source("04_Research/regime_comparison/msm_update.R")
    cat("[daily_refresh] MSM update.R PASS — hybrid + daily 양쪽 갱신\n")
  }, error = function(e) {
    cat(sprintf("[daily_refresh] msm_update.R FAIL: %s — fallback to msm_daily_refit\n", e$message))
    tryCatch({
      source("02_Infrastructure/regime/msm_daily_refit.R")
      compute_hmm_daily_signal()
      cat("[daily_refresh] msm_daily_refit fallback PASS\n")
    }, error = function(e2) cat(sprintf("[daily_refresh] MSM fallback FAIL: %s\n", e2$message)))
  })
'

# build_regime_signal_table — MSM 갱신 후 호출 (monthly + daily 양쪽 rebuild)
# 차트 (tg_regime_briefing)가 unified_regime_signal + _daily 양쪽 읽으므로 둘 다 재build
cd "$INFRA"
run_r '
  source("config.R")
  source("regime/regime_signal.R")
  tryCatch(build_regime_signal_table(),               # monthly
    error = function(e) cat(sprintf("Regime signal (monthly) skipped: %s\n", e$message)))
  tryCatch(build_regime_signal_table(daily = TRUE),   # daily
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
cd "$QM_ROOT" 2>/dev/null || cd "$INFRA/.."
for _series in monthly daily; do
  "$RSCRIPT" --no-save "$QM_ROOT/02_Infrastructure/regime/regime_append_only.R" --series "$_series" 2>&1
  _rc=$?
  case "$_rc" in
    0) echo "[regime-append/$_series] OK" ;;
    1) echo "!! [regime-append/$_series] 동결 구간 재서술 시도 검출 — 발행본 보존됨(상류 확인 필요)" ;;
    *) echo "XX [regime-append/$_series] 게이트 실패(rc=$_rc) — 계열 신뢰 불가" ;;
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

# ──────────────────────────────────────────────────────────────────────────────
# [5] DART 재무제표 + Quarterly + Insider
#     (a) Annual 재무제표: 매월 1일만 (45일 lag 분기 발표 후)
#     (b) Quarterly 재무제표: 매일 (resume=TRUE incremental, 공시되는대로 즉시 반영)
#     (c) Insider 거래: 매일 (merge wrapper로 history 보존)
# ──────────────────────────────────────────────────────────────────────────────
DAY_OF_MONTH=$(date +%d)

# (a) Annual financials — monthly (1st only)
if [ "$DAY_OF_MONTH" = "01" ]; then
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
  "$RSCRIPT" --no-save "$INFRA/data/build_fundamental_derived.R" \
    || echo "  [warn] build_fundamental_derived failed (fail-soft — 기존 cache 유지)"
else
  echo "[5a/7] DART Annual + fundamental_merged skipped (monthly 1st only, today=$DAY_OF_MONTH)"
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

# ──────────────────────────────────────────────────────────────────────────────
# [7] Telegram + NAV Tracking + Memory
# ──────────────────────────────────────────────────────────────────────────────
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

echo "[7/7] Telegram + NAV + Memory..."
cd "$INFRA"
# (2026-07-26 DR-01) 지금까지의 실패 스텝을 R 로 넘겨 본문에 병기 — "완료" 만 보내던
#   구판은 스텝 절반이 죽어도 성공 통보였다. 이 시점까지의 누적을 쓴다(이후 [8][9]는 별도).
export DR_FAILED_SO_FAR="$(dr_fail_summary)"
run_r '
  library(data.table)
  source("config.R")
  source("telegram/telegram_notify.R")
  raw <- as.data.table(arrow::read_parquet(RAWDATA_CACHE))
  last_d <- max(raw$Date)
  n_tickers <- uniqueN(raw[Date == last_d]$Ticker)
  .fails <- Sys.getenv("DR_FAILED_SO_FAR", "없음")
  # 최상위 if/else 는 반드시 중괄호로 묶는다 — R 은 줄바꿈에서 if 문을 닫아버려
  # 다음 줄의 else 가 고아가 된다("unexpected else"). 이 블록이 죽으면 일일 성공/실패
  # 통보 자체가 발송되지 않는다(2026-08-02 실측: DailyRefresh rc=1 의 단독 원인).
  .hdr <- if (identical(.fails, "없음")) {
    "[Daily Refresh v2 완료]"
  } else {
    sprintf("[Daily Refresh v2 ★부분실패 — %s]", .fails)
  }
  msg <- sprintf("%s\nRAWDATA: %s까지 (%d tickers)\n총 %s rows",
                 .hdr, last_d, n_tickers, format(nrow(raw), big.mark=","))
  if (Sys.getenv("QVEST_REFRESH_TG", "0") == "1") {     # v8.1.1 telegram guard
    tryCatch(tg_send(msg), error = function(e) cat("TG send failed:", e$message, "\n"))
  } else {
    cat("[tg guard] QVEST_REFRESH_TG=0 — 발송 skip. msg:\n", msg, "\n")
  }
'

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

# [8.2] FR 모듈 성능 레지스트리 재생성 (2026-08-08, FQ-056) — screen-tier 재고를
#   factor-rotation 소비면에 도달시키는 배관. fail-soft.
#   ★왜 정기 실행이 필요한가: 이 스크립트는 배선돼 있었지만 **on-demand 진입점
#   (run_factor_rotation.R:32)에만** 매달려 있었다. 그 모드를 사람이 안 띄우면 갱신이 멈춘다 —
#   실측 2026-08-08: generated=2026-06-13 로 **56일 정지**, 재실행 시 모듈 192→209(+17).
#   "죽은 코드"도 "실행 실패"도 아닌 **호출 계기 부재**였다.
#   ★신선도 게이트를 일부러 두지 않는다: 이 저장소는 게이트가 영구-참이 되어 7주간
#   같은 캐시를 재보고한 실사고가 있다(project-paper-dispatch-risk-optimizer-never-research).
#   이 빌드는 멱등(재실행 209 동일)이고 수 분이므로 무조건 실행이 더 안전하다.
"$RSCRIPT" --no-save "$INFRA/regime/build_module_performance.R" >/dev/null 2>&1 \
  || echo "[warn] module_performance rebuild failed (fail-soft)"

# [9] 스위트 총계 수집 (2026-07-25) — 계측 사망은 '실패'가 아니라 '총계 감소'로 온다.
#     여기서 매일 수집해야 bootstrap 의 --check 가 최신값을 비교한다(수동 수집 의존 제거).
#     fail-soft: 러너가 죽어도 refresh 전체는 계속 — 다만 그 경우 null 로 기록되어
#     다음 --check 가 "수치 없음은 정상이 아니다"로 경고한다.
bash "$INFRA/ops/suite_totals_watch.sh" --collect || echo "[warn] suite totals collect failed (fail-soft)"

# (2026-07-26 DR-01) 실패 스텝을 이름으로 표면화 + 종료코드 반영.
#   "Done" 이 무조건 찍히던 구판은 크론·bootstrap 어느 쪽에도 실패 신호를 주지 못했다.
if [ "${#DR_FAILED[@]}" -gt 0 ]; then
  echo "=== Daily Refresh v2 Done — ★실패 ${#DR_FAILED[@]}스텝: $(dr_fail_summary) @ $(date) ==="
  exit 1
fi
echo "=== Daily Refresh v2 Done (실패 0) @ $(date) ==="
