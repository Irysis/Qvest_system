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
tryCatch(build_regime_signal_table(daily = FALSE), error = function(e)
  cat(sprintf("Regime signal monthly skipped: %s\n", e$message)))
tryCatch(build_regime_signal_table(daily = TRUE), error = function(e)
  cat(sprintf("Regime signal daily skipped: %s\n", e$message)))
# [추가 2026-06-19] regime_daily_v2.parquet 갱신 배선 — factor_db daily phase(6/7/9b)가 소비하나
#   morning 미배선으로 06-12 이후 stale였음(data.table 1.17 "argument n" 에러는 06-12 .rolling_zscore서 기수정).
if (file.exists("02_Infrastructure/regime/regime_engine_daily.R")) {
  source("02_Infrastructure/regime/regime_engine_daily.R")
  tryCatch(build_daily_regime(use_cache = FALSE), error = function(e)
    cat(sprintf("regime_daily_v2 build skipped: %s\n", e$message)))
}
