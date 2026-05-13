#!/usr/bin/env bash
#==============================================================================
# Morning Regime Briefing — 매일 아침 7시
# 1) 데이터 최신화 (KRX + Naver T+0 + Arrow + KTRI + FRED + Regime Signal)
# 2) 텔레그램 레짐 브리핑 발송
#
# crontab: 10 7 * * 1-5 bash "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot/02_Infrastructure/morning_briefing.sh"
#==============================================================================
set -uo pipefail  # -e 제거: 개별 스텝 실패해도 나머지 계속 실행
LOGFILE="/tmp/qm_morning_briefing_$(date +%Y%m%d).log"
exec > >(tee -a "$LOGFILE") 2>&1

echo "=== Morning Briefing @ $(date) ==="
source "$(dirname "${BASH_SOURCE[0]:-$0}")/resolve_project.sh"
INFRA="$BASE/02_Infrastructure"

# 1. KRX 데이터 최신화
echo "[1/5] KRX Data Update..."
cd "$INFRA"
Rscript --no-save -e '
  source("config.R")
  source("data/krx_data_collector.R")
  source("data/krx_build_rawdata.R")
  gap <- krx_detect_gap()
  cat(sprintf("Gap: %s → %s (%d days)\n", gap$last_rawdata_date, gap$end, gap$n_calendar_days))
  if (gap$n_calendar_days > 0) {
    krx_run_pipeline()
  } else {
    cat("RAWDATA already up to date.\n")
  }
'

# 1.5 Naver T+0 보완 (KRX T+1 gap이 남아있으면 Naver로 채움)
echo "[1.5/5] Naver T+0 Supplement..."
cd "$INFRA"
Rscript --no-save -e '
  source("config.R")
  source("data/naver_data_collector.R")
  tryCatch({
    naver_run_pipeline()
  }, error = function(e) cat(sprintf("Naver pipeline skipped: %s\n", e$message)))
'

# 2. Arrow + KTRI 연장
echo "[2/5] Arrow + KTRI..."
cd "$INFRA"
Rscript --no-save -e '
  source("config.R")
  source("data/krx_data_collector.R")
  source("data/krx_arrow_pipeline.R")
  tryCatch({
    krx_extend_arrow()
    cat("Arrow extension complete.\n")
  }, error = function(e) cat(sprintf("Arrow extension skipped: %s\n", e$message)))
'
cd "$BASE"
# KTRI v3 signal rebuild — silent fail (04_Regime_Engine/KTRI_v3_reinforced.R 소실) 해소
# 2026-05-13 도훈 mandate: "매일 아침 제대로 최신화된 모닝 국면 브리핑 구조적 자동 해결"
# 정식 builder: 02_Infrastructure/regime/ktri_v3_builder.R::build_ktri_v3_safe()
# 출력: 04_Research/regime_comparison/output/ktri_v3_signals.csv (regime_signal L3 source)
Rscript --no-save -e '
  setwd("'"$BASE"'")
  source("02_Infrastructure/config.R")
  source("02_Infrastructure/regime/ktri_v3_builder.R")
  tryCatch({
    out_path <- build_ktri_v3_safe()
    cat(sprintf("KTRI v3 signals regenerated: %s\n", out_path))
  }, error = function(e) cat(sprintf("KTRI v3 build FAILED: %s\n", e$message)))
'

# 3. FRED + Regime Signal 업데이트 (monthly + daily 모두 build)
echo "[3/5] FRED + Regime Signal..."
cd "$INFRA"
Rscript --no-save -e '
  source("config.R")
  # FRED robust fetch (22 series with retry/graceful)
  if (file.exists("regime/fred_robust.R")) {
    source("regime/fred_robust.R")
    tryCatch(fred_robust_fetch_all(), error = function(e)
      cat(sprintf("FRED robust skipped: %s\n", e$message)))
  } else if (file.exists("data/data_collector_fred.R")) {
    source("data/data_collector_fred.R")
    tryCatch(fred_fetch_all(), error = function(e)
      cat(sprintf("FRED update skipped: %s\n", e$message)))
  }
  # yfinance supplement — FRED 우선 정책 (NA cell 만 yfinance 로 채움)
  # 다음 cron 에서 FRED publish 되면 자동으로 FRED 값으로 교체
  if (file.exists("regime/fred_supplement_yfinance.R")) {
    source("regime/fred_supplement_yfinance.R")
    tryCatch(supplement_fred_with_yfinance(lookback_days = 7L), error = function(e)
      cat(sprintf("FRED yfinance supplement skipped: %s\n", e$message)))
  }
  source("regime/regime_signal.R")
  tryCatch(build_regime_signal_table(daily = FALSE), error = function(e)
    cat(sprintf("Regime signal monthly skipped: %s\n", e$message)))
  tryCatch(build_regime_signal_table(daily = TRUE), error = function(e)
    cat(sprintf("Regime signal daily skipped: %s\n", e$message)))
'

# 4. 레짐 브리핑 발송 — 제거됨 (2026-05-13 도훈 mandate, 2-fire 해소)
# mrs_daily_briefing.sh (07:30) 가 tg_regime_briefing() 단일 송신 담당.
# 본 morning_briefing.sh (07:10) 는 데이터 갱신만 (KRX/Naver/Arrow/KTRI/FRED/Regime).
# 07:10 갱신 → 07:30 송신 20분 buffer 로 차트 최신화 보장.
echo "[4/5] Regime briefing — skipped (mrs_daily_briefing.sh 07:30 SOT)"

# 5. Freshness audit — 모든 source 최신 거래일 검증 + stale 시 Telegram alert
# 2026-05-13 도훈 mandate: 구조적 자동 검증 (silent fail 방지)
echo "[5/5] Freshness audit..."
cd "$BASE"
Rscript --no-save -e '
  setwd("'"$BASE"'")
  source("02_Infrastructure/config.R")
  suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)})
  today <- Sys.Date()
  # 평일 거래일 lag tolerance (KR market):
  #   MSM/KTRI v3/Regime signal daily: <=1 trading day
  #   FRED: <=2 trading day
  #   KTRI sub-indices: <=2 trading day (KRX API 1d lag)
  audits <- list()
  check_freshness <- function(name, path, col, max_lag_days) {
    if (!file.exists(path)) return(list(name=name, status="MISSING", path=path))
    dt <- tryCatch(as.data.table(read_parquet(path)), error = function(e) NULL)
    if (is.null(dt)) {
      csv_try <- tryCatch(fread(path), error = function(e) NULL)
      if (!is.null(csv_try)) dt <- csv_try
    }
    if (is.null(dt) || !col %in% names(dt)) return(list(name=name, status="PARSE_FAIL", path=path))
    last_d <- max(as.Date(dt[[col]]), na.rm = TRUE)
    lag_d <- as.integer(today - last_d)
    status <- if (lag_d <= max_lag_days) "FRESH" else "STALE"
    list(name=name, status=status, last_date=as.character(last_d), lag_days=lag_d, max_lag=max_lag_days)
  }
  audits$msm_daily       <- check_freshness("msm_daily",       ".cache/msm_daily_latest.parquet",        "Date", 3)
  audits$msm_hybrid      <- check_freshness("msm_hybrid",      ".cache/msm_hybrid_latest.parquet",       "Date", 3)
  audits$fred            <- check_freshness("fred",            ".cache/fred_macro.parquet",              "Date", 4)
  audits$ktri_indices    <- check_freshness("ktri_indices",    ".cache/ktri_indices.parquet",            "Date", 3)
  audits$ktri_v3_signals <- check_freshness("ktri_v3_signals", "04_Research/regime_comparison/output/ktri_v3_signals.csv", "DATE", 3)
  audits$regime_daily    <- check_freshness("regime_daily",    ".cache/unified_regime_signal_daily.parquet", "Date", 3)
  cat("=== Freshness Audit ===\n")
  stale_items <- c()
  for (a in audits) {
    cat(sprintf("  %-18s [%s] last=%s lag=%dd (max %dd)\n",
      a$name, a$status, a$last_date %||% "n/a", a$lag_days %||% -1L, a$max_lag %||% -1L))
    if (isTRUE(a$status == "STALE") || isTRUE(a$status == "MISSING")) {
      stale_items <- c(stale_items, sprintf("%s(%s,lag=%dd)", a$name, a$status, a$lag_days %||% -1L))
    }
  }
  audit_path <- "qepm/observability/morning_freshness_latest.json"
  dir.create(dirname(audit_path), recursive = TRUE, showWarnings = FALSE)
  write_json(list(ran_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
                   audits = audits,
                   stale_count = length(stale_items),
                   stale_items = if (length(stale_items) > 0) I(as.character(stale_items)) else list()),
              audit_path, pretty = TRUE, auto_unbox = TRUE, null = "null")
  cat(sprintf("Audit saved: %s\n", audit_path))
  # Stale 시 Telegram alert (mrs_daily 의 07:30 brief 전에)
  if (length(stale_items) > 0) {
    cat(sprintf("\n⚠️ STALE detected (%d items): %s\n", length(stale_items),
        paste(stale_items, collapse=", ")))
    source("02_Infrastructure/telegram/telegram_notify.R")
    msg <- sprintf("🚨 *Morning Freshness Audit* — %d stale\n\n%s\n\nbrief 07:30 송신 전 점검 필요",
                    length(stale_items),
                    paste(sprintf("- %s", stale_items), collapse="\n"))
    tryCatch(tg_send(msg, parse_mode = "Markdown"), error = function(e)
      cat(sprintf("Telegram alert failed: %s\n", e$message)))
  } else {
    cat("\n✅ All sources FRESH — brief 07:30 발송 OK\n")
  }
'

echo "=== Morning Briefing Done @ $(date) ==="

# Step 3: Production strategy daily NAV report
# NOTE: sleeve_save_helper.R 제거됨. daily_portfolio_nav.R만으로 동작.
Rscript -e 'source("02_Infrastructure/config.R"); source("02_Infrastructure/backtest_harness.R"); source("02_Infrastructure/portfolio/daily_portfolio_nav.R"); tryCatch(daily_nav_report("STR_905"), error=function(e) cat("[NAV] Skip:", e$message, "\n"))' >> /tmp/qm_morning.log 2>&1
