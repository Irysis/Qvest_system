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

# MSM — as-of 경로(2026-11-06 전환 · PIT-C1-MSM-PARAMS 안 A): 낡으면 msm_asof.R::msma_update 로 갱신.
#   ★폴백 없음 — 구 msm_update.R(전 표본 고정 모수)·msm_daily_refit(평활 HMM)은 C1 이라 운영 경로에서 뺐다.
#   실패하면 아래 국면 재빌드의 로더가 stop 하고 원장 병합이 없다(라이브 불변 · fail-closed).
msm_asof_stale <- is_stale(".cache/msm_asof_daily.parquet", "Date", 1L)
unified_stale <- is_stale(".cache/unified_regime_signal.parquet", "Date", 1L)
msm_refit_succeeded <- FALSE
if (msm_asof_stale) {
  cat("  MSM(as-of) STALE -> msma_update\n")
  tryCatch({
    source("02_Infrastructure/regime/msm_asof.R")
    msma_update(getwd())
    cat("  MSM(as-of) PASS\n")
    msm_refit_succeeded <- TRUE
  }, error = function(e) {
    cat(sprintf("  MSM(as-of) FAIL: %s — 국면 재빌드는 로더가 멈춘다(fail-closed)\n", e$message))
  })
} else {
  cat("  MSM(as-of) FRESH (refit skipped)\n")
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
