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
source "$(dirname "${BASH_SOURCE[0]:-$0}")/../ops/resolve_project.sh"
INFRA="$BASE/02_Infrastructure"

# ──────────────────────────────────────────────────────────────────────────────
# [0] QuantiWise xlsx 증분 체크
#     OHLCVS = 수정주가 → 전체 리빌드 + API 데이터 보존
#     Consensus/Fundamental/Investor/Universe_Support = mtime 기반 증분
# ──────────────────────────────────────────────────────────────────────────────
echo "[0/7] QuantiWise xlsx update check..."
cd "$INFRA"
Rscript --no-save -e '
  source("config.R")
  source("data/incremental_cache_update.R")
  incremental_update_all()
'

# ──────────────────────────────────────────────────────────────────────────────
# [1] Naver T+0 (PRIMARY — KRX T+1 lag 회피, 2026-04-24 변경)
#     Naver가 장중/장마감 직후 전일 종가 즉시 반영. RAWDATA 최신화 주력.
# ──────────────────────────────────────────────────────────────────────────────
echo "[1/7] Naver T+0 Primary Pipeline..."
cd "$INFRA"
Rscript --no-save -e '
  source("config.R")
  source("data/naver_data_collector.R")
  tryCatch(naver_run_pipeline(),
    error = function(e) cat(sprintf("Naver pipeline failed: %s\n", e$message)))
'

# ──────────────────────────────────────────────────────────────────────────────
# [2] KRX gap-fill (FALLBACK — Naver 미처리 gap만 보충)
#     KRX API는 T+1 lag 있으므로 Naver 이후 남은 gap만 채움.
# ──────────────────────────────────────────────────────────────────────────────
echo "[2/7] KRX gap-fill (fallback)..."
cd "$INFRA"
Rscript --no-save -e '
  source("config.R")
  source("data/krx_data_collector.R")
  source("data/krx_build_rawdata.R")
  gap <- krx_detect_gap()
  cat(sprintf("Post-Naver gap: %s → %s (%d days)\n",
              gap$last_rawdata_date, gap$end, gap$n_calendar_days))
  if (gap$n_calendar_days > 1) {
    # Naver가 전날까지 채웠으면 gap 0~1일. 2일 이상 gap일 때만 KRX fallback.
    cat("Gap > 1 day — KRX fallback 실행\n")
    tryCatch(krx_run_pipeline(),
             error = function(e) cat(sprintf("KRX skipped: %s\n", e$message)))
  } else {
    cat("Naver로 gap 충분 해소 — KRX skip\n")
  }
'

# ──────────────────────────────────────────────────────────────────────────────
# [3] Universe 갱신 + RAWDATA 메타 매핑
#     Layer 1: KRX API 기반 유니버스 (RAWDATA에서 월말 활성 종목)
#     Layer 2: Universe_Support.xlsx 메타 (있으면 roll join)
# ──────────────────────────────────────────────────────────────────────────────
echo "[3/7] Universe update + RAWDATA mapping..."
cd "$INFRA"
Rscript --no-save -e '
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
Rscript --no-save -e '
  source("config.R")
  source("data/krx_data_collector.R")
  source("data/krx_arrow_pipeline.R")
  tryCatch(krx_extend_arrow(),
    error = function(e) cat(sprintf("Arrow skipped: %s\n", e$message)))
'

# FRED (regime compute 비활성화 — v7.1 사용 중)
cd "$INFRA"
if [ -f "data/data_collector_fred.R" ]; then
  Rscript --no-save -e '
    source("config.R")
    source("data/data_collector_fred.R")
    tryCatch(fred_fetch_all(),
      error = function(e) cat(sprintf("FRED skipped: %s\n", e$message)))
  '
fi

# KTRI + Regime Signal
cd "$INFRA"
Rscript --no-save -e '
  source("config.R")
  source("data/krx_data_collector.R")
  source("data/ktri_index_collector.R")
  tryCatch(ktri_update_indices(),
    error = function(e) cat(sprintf("KTRI skipped: %s\n", e$message)))
'
cd "$BASE"
Rscript --no-save -e '
  tryCatch(source("04_Regime_Engine/KTRI_v3_reinforced.R"),
    error = function(e) cat(sprintf("KTRI v3.1 skipped: %s\n", e$message)))
'
cd "$INFRA"
Rscript --no-save -e '
  source("config.R")
  source("regime/regime_signal.R")
  tryCatch(build_regime_signal_table(),
    error = function(e) cat(sprintf("Regime signal skipped: %s\n", e$message)))
'

# ──────────────────────────────────────────────────────────────────────────────
# [5] DART 재무제표 (매월 1일만)
# ──────────────────────────────────────────────────────────────────────────────
DAY_OF_MONTH=$(date +%d)
if [ "$DAY_OF_MONTH" = "01" ]; then
  echo "[5/7] DART Fundamentals (monthly)..."
  cd "$INFRA"
  Rscript --no-save -e '
    source("config.R")
    source("data/data_collector_dart.R")
    tryCatch(dart_run_pipeline(years = as.integer(format(Sys.Date(), "%Y"))),
      error = function(e) cat(sprintf("DART skipped: %s\n", e$message)))
  '
else
  echo "[5/7] DART skipped (monthly: 1st only, today=$(date +%d))"
fi

# ──────────────────────────────────────────────────────────────────────────────
# [6] Factor DB 갱신 (월말 또는 데이터 변경 시)
# ──────────────────────────────────────────────────────────────────────────────
echo "[6/7] Factor DB update..."
cd "$INFRA"
Rscript --no-save -e '
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
  Rscript --no-save -e '
    tryCatch({
      source("portfolio/forward_weights_orchestrator.R")
      orchestrate_forward_weights(
        as_of_date = NULL,           # default = max schedule date
        apply_mandate_cap = "cap_0.20",
        send_telegram = TRUE
      )
    }, error = function(e) cat(sprintf("Forward weights orchestrator skipped: %s\n", e$message)))
  '
fi

# ──────────────────────────────────────────────────────────────────────────────
# [7] Telegram + NAV Tracking + Memory
# ──────────────────────────────────────────────────────────────────────────────
echo "[7/7] Telegram + NAV + Memory..."
cd "$INFRA"
Rscript --no-save -e '
  library(data.table)
  source("config.R")
  source("telegram/telegram_notify.R")
  raw <- as.data.table(arrow::read_parquet(RAWDATA_CACHE))
  last_d <- max(raw$Date)
  n_tickers <- uniqueN(raw[Date == last_d]$Ticker)
  msg <- sprintf("📅 Daily Refresh v2 완료\nRAWDATA: %s까지 (%d tickers)\n총 %s rows",
                 last_d, n_tickers, format(nrow(raw), big.mark=","))
  tryCatch(tg_send(msg), error = function(e) cat("TG send failed:", e$message, "\n"))
'

# NAV Tracking
WATCHLIST="$INFRA/nav_watchlist.json"
if [ -f "$WATCHLIST" ] && [ "$(cat "$WATCHLIST" | wc -c)" -gt 5 ]; then
  cd "$INFRA" && Rscript --no-save -e '
    source("config.R")
    source("telegram/telegram_notify.R")
    source("portfolio/daily_nav_tracker.R")
    nav_track()
    tryCatch(source("portfolio/regime_change_detector.R"), error=function(e) cat("regime_change_detector skipped\n"))
    detect_regime_change()
  ' 2>&1
fi

# Memory Distillation
cd "$BASE"
Rscript --no-save -e '
suppressMessages({
  source("02_Infrastructure/config.R")
  source("02_Infrastructure/memory/memory_logger.R")
})
tryCatch(update_memory_summary(), error = function(e) NULL)
cat("[distill] MEMORY.md updated\n")
' 2>/dev/null

echo "=== Daily Refresh v2 Done @ $(date) ==="
