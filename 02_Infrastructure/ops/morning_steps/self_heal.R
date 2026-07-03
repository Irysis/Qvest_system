# [4.5/5] Self-healing refit — daily_refresh fail 대비 (morning_briefing 외부화 2026-06-13)
# 캐시 stale 감지 시 자동 refit. 구조: daily_refresh.sh 03:00 primary -> 본 07:10 self-heal layer.
source("02_Infrastructure/ops/morning_steps/_root.R")
suppressPackageStartupMessages({library(data.table); library(arrow)})
today <- Sys.Date()

is_stale <- function(path, col, max_lag) {
  if (!file.exists(path)) return(TRUE)
  dt <- tryCatch(as.data.table(read_parquet(path)), error = function(e) NULL)
  if (is.null(dt) || !col %in% names(dt)) return(TRUE)
  last_d <- max(as.Date(dt[[col]]), na.rm = TRUE)
  as.integer(today - last_d) > max_lag
}

# RAWDATA(입력) freshness 선검증 — stale면 Naver refresh 먼저 (downstream MSM refit이 stale 입력 방지).
rawdata_stale <- is_stale(RAWDATA_CACHE, "Date", 1L)
if (rawdata_stale) {
  cat("  RAWDATA STALE -> Naver refresh 선행 (downstream refit이 stale 입력으로 도는 것 방지)\n")
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
  cat(sprintf("  MSM STALE (daily=%s, hybrid=%s) -> auto-refit via msm_update.R\n",
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
unified_daily_stale <- is_stale(".cache/unified_regime_signal_daily.parquet", "Date", 1L)
if (msm_refit_succeeded || unified_stale || unified_daily_stale) {
  cat("  -> build_regime_signal_table() 재실행 (monthly + daily 양쪽)\n")
  tryCatch({
    source("02_Infrastructure/regime/regime_signal.R")
    build_regime_signal_table()
    build_regime_signal_table(daily = TRUE)
    cat("  unified_regime_signal REBUILD PASS (monthly + daily)\n")
  }, error = function(e) {
    cat(sprintf("  unified_regime_signal REBUILD FAIL: %s\n", e$message))
  })
}
