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
  # ktri_indices.parquet 자동 update (도훈 mandate 2026-05-28: KRX API 07:10 시점 가용)
  # daily_refresh 03:00 시점 KRX 5/d 미가용 fallback
  source("02_Infrastructure/data/ktri_index_collector.R")
  tryCatch({
    ktri_update_indices()
    cat("ktri_indices.parquet updated\n")
  }, error = function(e) cat(sprintf("ktri_update_indices FAILED: %s\n", e$message)))
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

# 4.5. Self-healing refit — daily_refresh fail 대비 (도훈 mandate 2026-05-15)
# 캐시 stale 감지 시 자동 refit으로 사용자 개입 없이 정상화
# 구조: daily_refresh.sh 03:00 primary → morning_briefing.sh 07:10 self-heal layer
echo "[4.5/5] Self-healing refit (stale detection + auto-refit)..."
cd "$BASE"
Rscript --no-save -e '
  setwd("'"$BASE"'")
  source("02_Infrastructure/config.R")
  suppressPackageStartupMessages({library(data.table); library(arrow)})
  today <- Sys.Date()

  is_stale <- function(path, col, max_lag) {
    if (!file.exists(path)) return(TRUE)
    dt <- tryCatch(as.data.table(read_parquet(path)), error = function(e) NULL)
    if (is.null(dt) || !col %in% names(dt)) return(TRUE)
    last_d <- max(as.Date(dt[[col]]), na.rm = TRUE)
    as.integer(today - last_d) > max_lag
  }

  # [v8.0 fix 2026-05-29] RAWDATA(입력) freshness 선검증 — stale면 Naver refresh 먼저.
  # (기존 결함: downstream MSM refit이 stale RAWDATA로 돌아 stale 브리핑 산출 + 최종 audit 거짓 FRESH)
  rawdata_stale <- is_stale(RAWDATA_CACHE, "Date", 1L)
  if (rawdata_stale) {
    cat("  RAWDATA STALE → Naver refresh 선행 (downstream refit이 stale 입력으로 도는 것 방지)\n")
    tryCatch({
      source("02_Infrastructure/data/naver_data_collector.R")
      naver_run_pipeline()
      cat(sprintf("  RAWDATA Naver refresh PASS (max=%s)\n",
                  max(as.Date(as.data.table(read_parquet(RAWDATA_CACHE))$Date), na.rm = TRUE)))
    }, error = function(e)
      cat(sprintf("  [ALERT] RAWDATA refresh FAIL: %s — refit이 stale 입력으로 진행됨\n", e$message)))
  } else {
    cat("  RAWDATA FRESH (refit 입력 정상)\n")
  }

  # MSM (hybrid + daily 양쪽 stale 시 msm_update.R 단일 호출로 동시 갱신)
  msm_daily_stale <- is_stale(".cache/msm_daily_latest.parquet", "Date", 1L)
  msm_hybrid_stale <- is_stale(".cache/msm_hybrid_latest.parquet", "Date", 1L)
  unified_stale <- is_stale(".cache/unified_regime_signal.parquet", "Date", 1L)
  msm_refit_succeeded <- FALSE
  if (msm_daily_stale || msm_hybrid_stale) {
    cat(sprintf("  MSM STALE (daily=%s, hybrid=%s) → auto-refit via msm_update.R\n",
                msm_daily_stale, msm_hybrid_stale))
    tryCatch({
      source("02_Infrastructure/backtest_harness.R")
      source("04_Research/regime_comparison/msm_update.R")
      cat("  MSM REFIT PASS (hybrid + daily 양쪽 갱신)\n")
      msm_refit_succeeded <- TRUE
    }, error = function(e) {
      cat(sprintf("  MSM msm_update.R FAIL: %s — fallback msm_daily_refit\n", e$message))
      tryCatch({
        source("02_Infrastructure/regime/msm_daily_refit.R")
        compute_hmm_daily_signal()
        cat("  MSM fallback REFIT PASS (daily only)\n")
        msm_refit_succeeded <<- TRUE
      }, error = function(e2) {
        cat(sprintf("  MSM fallback FAIL: %s\n", e2$message))
      })
    })
  } else {
    cat("  MSM FRESH (daily + hybrid 모두, auto-refit skipped)\n")
  }

  # build_regime_signal_table — MSM refit 후 또는 unified stale 시 monthly + daily 양쪽 재build
  # (tg_regime_briefing 차트 = unified_regime_signal (monthly) + _daily 양쪽 읽음)
  unified_daily_stale <- is_stale(".cache/unified_regime_signal_daily.parquet", "Date", 1L)
  if (msm_refit_succeeded || unified_stale || unified_daily_stale) {
    cat("  → build_regime_signal_table() 재실행 (monthly + daily 양쪽)\n")
    tryCatch({
      source("02_Infrastructure/regime/regime_signal.R")
      build_regime_signal_table()
      build_regime_signal_table(daily = TRUE)
      cat("  unified_regime_signal REBUILD PASS (monthly + daily)\n")
    }, error = function(e) {
      cat(sprintf("  unified_regime_signal REBUILD FAIL: %s\n", e$message))
    })
  }
'

# 5. Freshness audit — 모든 source 최신 거래일 검증 + stale 시 Telegram alert
# 2026-05-13 도훈 mandate: 구조적 자동 검증 (silent fail 방지)
echo "[5/5] Freshness audit..."
cd "$BASE"
Rscript --no-save -e '
  setwd("'"$BASE"'")
  source("02_Infrastructure/config.R")
  suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)})
  today <- Sys.Date()
  # as_of = 직전 거래일 (benchmark KOSPI200 max). calendar today 대신 이걸 기준으로 lag 계산 → 월요일/연휴 오탐 제거 (도훈 2026-06-01 ①)
  as_of <- tryCatch(max(as.Date(as.data.table(read_parquet(".cache/benchmark.parquet"))$Date), na.rm = TRUE), error = function(e) today)
  if (length(as_of) != 1 || is.na(as_of) || as_of > today) as_of <- today
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
    lag_d <- as.integer(as_of - last_d)
    status <- if (lag_d <= max_lag_days) "FRESH" else "STALE"
    list(name=name, status=status, last_date=as.character(last_d), lag_days=lag_d, max_lag=max_lag_days)
  }
  audits$msm_daily       <- check_freshness("msm_daily",       ".cache/msm_daily_latest.parquet",        "Date", 3)
  audits$msm_hybrid      <- check_freshness("msm_hybrid",      ".cache/msm_hybrid_latest.parquet",       "Date", 3)
  audits$fred            <- check_freshness("fred",            ".cache/fred_macro.parquet",              "Date", 4)
  audits$ktri_indices    <- check_freshness("ktri_indices",    ".cache/ktri_indices.parquet",            "Date", 3)
  audits$ktri_v3_signals <- check_freshness("ktri_v3_signals", "04_Research/regime_comparison/output/ktri_v3_signals.csv", "DATE", 3)
  audits$regime_daily    <- check_freshness("regime_daily",    ".cache/unified_regime_signal_daily.parquet", "Date", 3)
  audits$benchmark       <- check_freshness("benchmark",       ".cache/benchmark.parquet",               "Date", 2)  # KOSPI200 종가 (도훈 mandate 2026-05-28)
  audits$p3_forecast     <- check_freshness("p3_forecast",     "04_Research/decision_framework/bearish_forecast_v3/03_models/daily_predictions/P3_daily.parquet", "Date", 3)  # P3 forecast (도훈 mandate 2026-06-01, 601 stale 감지)
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
                   as_of = as.character(as_of),
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
    # plain text (Markdown 파싱 오류 회피, 도훈 mandate 2026-05-28)
    msg <- sprintf("🚨 Morning Freshness Audit — %d stale\n\n%s\n\nbrief 07:30 송신 전 점검 필요",
                    length(stale_items),
                    paste(sprintf("- %s", stale_items), collapse="\n"))
    tryCatch(tg_send(msg), error = function(e)
      cat(sprintf("Telegram alert failed: %s\n", e$message)))
  } else {
    cat("\n✅ All sources FRESH — brief 07:30 발송 OK\n")
  }
'

echo "=== Morning Briefing Done @ $(date) ==="

# Step 3: Production strategy daily NAV report
# NOTE: sleeve_save_helper.R 제거됨. daily_portfolio_nav.R만으로 동작.
Rscript -e 'source("02_Infrastructure/config.R"); source("02_Infrastructure/backtest_harness.R"); source("02_Infrastructure/portfolio/daily_portfolio_nav.R"); tryCatch(daily_nav_report("STR_905"), error=function(e) cat("[NAV] Skip:", e$message, "\n"))' >> /tmp/qm_morning.log 2>&1

# ──────────────────────────────────────────────────────────────────────────────
# Step 6: P3 (v3-fast Hansen, hparam-tuned) bearish forecast — daily inference + brief + 텔레그램 발송
# 도훈 mandate 2026-05-26: KOSPI 200 1일 분포 forecast (mu, sigma, nu, lam) + VaR/ES/P(폭락)
# P3 spec: α=6.68e-4, taus=11, train_min=3024 (~12y lookback) — Optuna trial 19
# ──────────────────────────────────────────────────────────────────────────────
echo "[6/6] P2 bearish forecast brief..."
P2_BF_DIR="$BASE/04_Research/decision_framework/bearish_forecast_v3"
P2_PY=""
for _c in "$BASE/.venv_dpl/Scripts/python.exe" "$BASE/.venv_dpl/bin/python" "$BASE/.venv_qvest_ml/Scripts/python.exe" "$BASE/.venv_qvest_ml/bin/python"; do
  [ -x "$_c" ] && P2_PY="$_c" && break
done
if [[ -x "$P2_PY" && -d "$P2_BF_DIR" ]]; then
  # 6_pre. Naver benchmark patch (KOSPI200 종가 자동 최신화, 도훈 mandate 2026-05-28)
  cd "$BASE"
  "$P2_PY" 02_Infrastructure/data/naver_benchmark_update.py --start_date $(date -d "7 days ago" +%Y-%m-%d) 2>&1 | tail -5 || true
  cd "$P2_BF_DIR"
  # 6a. daily inference (오늘 forecast 추가) — P3.
  # [2026-06-01 fix] 601 default(no --asof)는 ret_fwd-dropna로 마지막 행이 잘려 benchmark_max-1(1일 stale)을
  #   forecast → brief가 매일 1일 정체. benchmark 최신 종가일을 --asof로 명시(검증된 forecast-only 경로)해 재발 방지.
  ASOF_BM=$("$P2_PY" -c "import pandas as pd; print(pd.to_datetime(pd.read_parquet('$BASE/.cache/benchmark.parquet', columns=['Date'])['Date']).max().date())" 2>/dev/null)
  if [[ -n "$ASOF_BM" ]]; then
    echo "[6a] 601 inference --asof $ASOF_BM (benchmark 최신 종가일)"
    "$P2_PY" scripts/601_daily_inference.py --model P3 --asof "$ASOF_BM" 2>&1 | tail -5
  else
    echo "[6a] ASOF_BM 추출 실패 — default 경로 fallback"
    "$P2_PY" scripts/601_daily_inference.py --model P3 2>&1 | tail -5
  fi
  # 6a'. y_actual backfill (이전 forecast row의 realized 1d return 채움, 도훈 mandate 2026-05-28)
  "$P2_PY" -c "
import pandas as pd, numpy as np, sys, os
sys.path.insert(0, '$P2_BF_DIR/03_models')
import p1_hansen_skewt as HSK
p3_path = '$P2_BF_DIR/03_models/daily_predictions/P3_daily.parquet'
p3 = pd.read_parquet(p3_path); p3['Date'] = pd.to_datetime(p3['Date']); p3 = p3.sort_values('Date').reset_index(drop=True)
bm = pd.read_parquet('$BASE/.cache/benchmark.parquet'); bm['Date'] = pd.to_datetime(bm['Date']); bm = bm.sort_values('Date').reset_index(drop=True)
bm['log_ret'] = np.log(bm['BM_Close']).diff() * 100
fwd_map = bm.assign(ret_fwd=bm.log_ret.shift(-1)).set_index('Date')['ret_fwd'].to_dict()
n_filled = 0
for i, row in p3.iterrows():
    if pd.isna(row['y_actual']) and row['Date'] in fwd_map:
        fwd = fwd_map[row['Date']]
        if pd.notna(fwd):
            p3.loc[i, 'y_actual'] = fwd
            try:
                pit = HSK.pit_per_obs(np.array([fwd]), np.array([row['mu']]), np.array([row['sigma']]), np.array([row['nu']]), np.array([row['lam']]))[0]
                p3.loc[i, 'pit'] = pit
            except Exception: pass
            n_filled += 1
p3.to_parquet(p3_path)
print(f'[y_actual backfill] {n_filled} rows filled')
" 2>&1 | tail -2
  # 6b. brief 생성 (markdown + dist.png + trend.png)
  "$P2_PY" scripts/600_morning_brief.py 2>&1 | grep -v "Glyph\|UserWarning" | tail -3
  # 6b'. Risk Pro 9-Quadrant 강화 대시보드 (도훈 mandate 2026-05-27)
  cd "$BASE"
  Rscript "$BASE/04_Research/decision_framework/bearish_forecast_v3/scripts/613_p3_9quad_riskpro.R" 2>&1 | tail -2 || true
  # 6c. 텔레그램 발송 (latest brief)
  cd "$BASE"
  Rscript --no-save -e '
    setwd("'"$BASE"'")
    source("02_Infrastructure/telegram/telegram_notify.R")
    brief_root <- "04_Research/decision_framework/bearish_forecast_v3/03_models/morning_brief"
    sub_dirs <- list.dirs(brief_root, recursive = FALSE)
    if (length(sub_dirs) == 0) {
      cat("[P2 brief] no brief dir found\n")
    } else {
      latest <- sort(sub_dirs, decreasing = TRUE)[1]
      # [B-gate 2026-06-01 도훈 mandate] freshness: 최신 brief dir 날짜가 직전 거래일(benchmark max Date)보다
      #   과거면 stale → stale brief 송출 보류 + 알림으로 대체 (조용한 stale 송출 차단).
      brief_date <- suppressWarnings(as.Date(basename(latest)))
      bm_max <- tryCatch(as.Date(max(as.data.frame(arrow::read_parquet(".cache/benchmark.parquet", col_select = "Date"))$Date, na.rm = TRUE)),
                         error = function(e) as.Date(NA))
      is_stale <- is.na(brief_date) || (!is.na(bm_max) && brief_date < bm_max)
    }
    if (length(sub_dirs) > 0 && is_stale) {
      msg <- sprintf("⚠️ 모닝브리핑 정체 — 최신 brief %s 가 직전 거래일 %s 보다 과거. P3 inference/brief 생성 정체 의심. stale brief 송출 보류 (601_daily_inference 점검 요).",
                     as.character(brief_date), as.character(bm_max))
      cat(sprintf("[P2 brief] STALE-GATE BLOCK: %s\n", msg))
      tryCatch(tg_send(msg), error = function(e) cat(sprintf("[P2 brief] stale alert fail: %s\n", e$message)))
    } else if (length(sub_dirs) > 0) {
      cat(sprintf("[P2 brief] sending from %s (fresh: brief %s >= bm %s)\n", latest, as.character(brief_date), as.character(bm_max)))
      brief_md <- file.path(latest, "brief.md")
      dist_png <- file.path(latest, "dist.png")
      trend_png <- file.path(latest, "trend.png")
      if (file.exists(brief_md)) {
        body <- paste(readLines(brief_md, encoding="UTF-8"), collapse="\n")
        # Telegram message limit 4096 chars — truncate if needed
        if (nchar(body) > 3900) body <- paste0(substr(body, 1, 3900), "\n...(truncated)")
        tryCatch(tg_send(body, parse_mode = "Markdown"),
                 error = function(e) cat(sprintf("[P2 brief] tg_send fail: %s\n", e$message)))
      }
      if (file.exists(dist_png)) {
        tryCatch(tg_send_photo(dist_png, caption = "P2 - 오늘 분포 forecast"),
                 error = function(e) cat(sprintf("[P2 brief] tg_send_photo dist fail: %s\n", e$message)))
      }
      if (file.exists(trend_png)) {
        tryCatch(tg_send_photo(trend_png, caption = "P2 - 22일 추세"),
                 error = function(e) cat(sprintf("[P2 brief] tg_send_photo trend fail: %s\n", e$message)))
      }
      riskpro_png <- file.path(latest, "p3_9quad_riskpro.png")
      if (file.exists(riskpro_png)) {
        tryCatch(tg_send_photo(riskpro_png, caption = "P3 Risk Manager Pro Dashboard"),
                 error = function(e) cat(sprintf("[P2 brief] tg_send_photo riskpro fail: %s\n", e$message)))
      }
      cat("[P2 brief] done\n")
    }
  ' >> /tmp/qm_morning.log 2>&1
else
  echo "[6/6] SKIP — venv or v3 dir missing"
fi

echo "=== Morning Briefing Full Done @ $(date) ==="

