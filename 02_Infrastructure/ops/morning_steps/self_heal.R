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

# RAWDATA(입력) freshness 판독 — (2026-10-17 · 결정 RAWDATA-QW-ONLY-20261017) 네이버 재수집 퇴역. RAWDATA 주가 원천 = 밤 퀀티 Update_File 단일
#   (daily_refresh.sh [1pre-qw] → [0b']) — 여기서 다른 원천으로 덧붙이지 않는다. stale 이면 경보 줄만 남기고(정본 감사 = [0/5] ensure_data_current ·
#   [5/5] freshness_audit) refit 은 그대로 진행한다(입력이 stale 이라는 사실이 로그에 남는다).
rawdata_stale <- is_stale(RAWDATA_CACHE, "Date", 1L)
if (rawdata_stale) {
  cat("  [ALERT] RAWDATA STALE — 보충 수집 없음(퀀티 단일 · 10-17). 밤 리프레시 [1pre-qw] 퀀티 수급 결과를 확인 · refit 은 stale 입력으로 진행\n")
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
  cat("  -> build_regime_signal_table() 재실행 (monthly + daily 양쪽) — 원장 경로\n")
  # ★C11 원장 경로(2026-09-25): 재생성본은 후보로만 쓰고 라이브는 원장 병합만 쓴다(regime_append_only.R ·
  #   fred_regime.R·daily_refresh 와 같은 함수). 구판은 여기서도 라이브를 원장 밖에서 덮었다(월요일마다 stale 판정 → 재빌드).
  tryCatch({
    source("02_Infrastructure/regime/regime_signal.R")
    source("02_Infrastructure/regime/regime_append_only.R")
    .rl_res <- regime_ledger_rebuild_publish(root = getwd())
    .rl_ok <- vapply(.rl_res, function(r) r$status %in% c(0L, 1L), logical(1))
    cat(sprintf("  unified_regime_signal REBUILD %s (monthly + daily · 원장 rc %s)\n",
                if (all(.rl_ok)) "PASS" else "FAIL", paste(vapply(.rl_res, function(r) as.integer(r$status), 0L), collapse = "/")))
  }, error = function(e) {
    cat(sprintf("  unified_regime_signal REBUILD FAIL: %s\n", e$message))
  })
}
