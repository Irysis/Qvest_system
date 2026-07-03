# [1/5] KRX 데이터 최신화 (morning_briefing 외부화 2026-06-13)
source("02_Infrastructure/ops/morning_steps/_root.R")
source("02_Infrastructure/data/krx_data_collector.R")
source("02_Infrastructure/data/krx_build_rawdata.R")
gap <- krx_detect_gap()
cat(sprintf("Gap: %s -> %s (%d days)\n", gap$last_rawdata_date, gap$end, gap$n_calendar_days))
if (gap$n_calendar_days > 0) {
  krx_run_pipeline()
} else {
  cat("RAWDATA already up to date.\n")
}
