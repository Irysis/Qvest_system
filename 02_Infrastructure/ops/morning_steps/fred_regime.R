# [3/5] FRED + Regime Signal 업데이트 (monthly + daily build) (morning_briefing 외부화 2026-06-13)
source("02_Infrastructure/ops/morning_steps/_root.R")
# FRED robust fetch (22 series with retry/graceful)
if (file.exists("02_Infrastructure/regime/fred_robust.R")) {
  source("02_Infrastructure/regime/fred_robust.R")
  tryCatch(fred_robust_fetch_all(), error = function(e)
    cat(sprintf("FRED robust skipped: %s\n", e$message)))
} else if (file.exists("02_Infrastructure/data/data_collector_fred.R")) {
  source("02_Infrastructure/data/data_collector_fred.R")
  tryCatch(fred_fetch_all(), error = function(e)
    cat(sprintf("FRED update skipped: %s\n", e$message)))
}
# yfinance supplement — FRED 우선 정책 (NA cell 만 yfinance 로 채움; 다음 cron 에서 FRED 값으로 교체)
if (file.exists("02_Infrastructure/regime/fred_supplement_yfinance.R")) {
  source("02_Infrastructure/regime/fred_supplement_yfinance.R")
  tryCatch(supplement_fred_with_yfinance(lookback_days = 7L), error = function(e)
    cat(sprintf("FRED yfinance supplement skipped: %s\n", e$message)))
}
source("02_Infrastructure/regime/regime_signal.R")
# ★C11 원장 경로(2026-09-25 · 판정서 pit_c11_20260924 · 결정 PIT-C11-REMEDIATION): 구판은 여기서 새 코드로 전 이력을
#   다시 빌드해 라이브(.cache/unified_regime_signal*.parquet)를 원장 밖에서 덮었다 → 00:03 = 발행 원장 이력 /
#   07:10 = 재생성 이력으로 하루 두 번 교대. 재생성본은 후보(.cache/_regime_candidate/)로만 쓰고 라이브는 원장 병합
#   (regime_append_only.R::regime_ledger_append — daily_refresh 00:03 과 같은 함수)만 쓴다. 병합 거부·실패 = 라이브 불변.
source("02_Infrastructure/regime/regime_append_only.R")
tryCatch(regime_ledger_rebuild_publish(root = getwd()), error = function(e)
  cat(sprintf("Regime signal ledger publish skipped (라이브 불변): %s\n", e$message)))
# [추가 2026-06-19] regime_daily_v2.parquet 갱신 배선 — factor_db daily phase(6/7/9b)가 소비하나
#   morning 미배선으로 06-12 이후 stale였음(data.table 1.17 "argument n" 에러는 06-12 .rolling_zscore서 기수정).
if (file.exists("02_Infrastructure/regime/regime_engine_daily.R")) {
  source("02_Infrastructure/regime/regime_engine_daily.R")
  tryCatch(build_daily_regime(use_cache = FALSE), error = function(e)
    cat(sprintf("regime_daily_v2 build skipped: %s\n", e$message)))
}
