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
run_r() {
  local _tmp _rc
  _tmp=$(mktemp /tmp/qm_refresh_XXXX.R) || { echo "[run_r] mktemp failed"; return 1; }
  printf '%s\n' "$1" > "$_tmp"
  "$RSCRIPT" --no-save "$_tmp"
  _rc=$?
  rm -f "$_tmp"
  return $_rc
}

# ──────────────────────────────────────────────────────────────────────────────
# [0] QuantiWise xlsx 증분 체크
#     OHLCVS = 수정주가 → 전체 리빌드 + API 데이터 보존
#     Consensus/Fundamental/Investor/Universe_Support = mtime 기반 증분
# ──────────────────────────────────────────────────────────────────────────────
echo "[0/7] QuantiWise xlsx update check..."
cd "$INFRA"
run_r '
  source("config.R")
  source("data/incremental_cache_update.R")
  incremental_update_all()
'

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
if [ -n "$QVENV_PY" ]; then
  ( cd "$INFRA" && "$QVENV_PY" data/naver_benchmark_update.py --start_date "$(date -d '10 days ago' +%Y-%m-%d)" ) \
    || echo "  benchmark chart-API update skipped (기존 cache 유지)"
else
  echo "  python 미발견 — benchmark chart-API update skipped (기존 cache 유지)"
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
    tryCatch(dart_run_pipeline(years = as.integer(format(Sys.Date(), "%Y"))),
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
echo "[7/7] Telegram + NAV + Memory..."
cd "$INFRA"
run_r '
  library(data.table)
  source("config.R")
  source("telegram/telegram_notify.R")
  raw <- as.data.table(arrow::read_parquet(RAWDATA_CACHE))
  last_d <- max(raw$Date)
  n_tickers <- uniqueN(raw[Date == last_d]$Ticker)
  msg <- sprintf("[Daily Refresh v2 완료]\nRAWDATA: %s까지 (%d tickers)\n총 %s rows",
                 last_d, n_tickers, format(nrow(raw), big.mark=","))
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
cd "$BASE"
run_r '
suppressMessages({
  source("02_Infrastructure/config.R")
  source("02_Infrastructure/memory/memory_logger.R")
})
tryCatch(update_memory_summary(), error = function(e) NULL)
cat("[distill] MEMORY.md updated\n")
' 2>/dev/null

# [7.9] Artifact hygiene audit (자동정리 log90d/scratch30d/빈디렉토리 + 위반감지 → 06_Registry/hygiene_report.json. fail-soft. 2026-07-04 파일위생 mandate)
"$RSCRIPT" --no-save "$INFRA/ops/artifact_hygiene_audit.R" || echo "[warn] artifact hygiene audit failed (fail-soft)"

# [8] Artifact index 재생성 (fail-soft — 실패해도 refresh 전체는 계속. 2026-07-04 저장규칙 재편)
"$RSCRIPT" --no-save "$INFRA/tools/build_artifact_index.R" || echo "[warn] artifact index rebuild failed (fail-soft)"

echo "=== Daily Refresh v2 Done @ $(date) ==="
