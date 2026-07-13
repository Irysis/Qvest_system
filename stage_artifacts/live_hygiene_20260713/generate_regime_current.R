## ============================================================================
## generate_regime_current.R — task #48 item 2 일회성 복원 (2026-07-13)
## .cache/regime_current.json 을 .cache/unified_regime_signal_daily.parquet 최종행에서 생성.
## (판정: 애초 미배선 — 생성기 전무, 참조/리더만 존재. 상시 배선은 regime_signal.R
##  daily write_parquet 직후 emit으로 별도 패치 — 본 스크립트는 즉시 복원용 원샷.)
## 스키마·매핑 = regime_signal.R 패치의 emit과 동일 (Q-Lead 지시 A5 레시피).
## ============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
data.table::setDTthreads(1L)
arrow::set_cpu_count(1L); arrow::set_io_thread_count(2L)

ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
PARQ <- file.path(ROOT, ".cache/unified_regime_signal_daily.parquet")
OUT  <- file.path(ROOT, ".cache/regime_current.json")
stopifnot(file.exists(PARQ))

dt <- as.data.table(read_parquet(PARQ, col_select = c("Date", "Regime_Score", "Category")))
dt[, Date := as.Date(Date)]
last_row <- dt[which.max(Date)]
cat(sprintf("[gen] parquet 최종행: %s | Category=%s | Score=%.2f (rows=%d)\n",
            as.character(last_row$Date), last_row$Category, last_row$Regime_Score, nrow(dt)))

m4_map <- c(RISK_ON = "BULL", NEUTRAL = "NORMAL", CAUTION = "CAUTION",
            RISK_OFF = "CRISIS", CRISIS = "CRISIS")
tag <- as.character(last_row$Category)
tag_m4 <- unname(m4_map[tag]); if (is.na(tag_m4)) tag_m4 <- tag

write_json(list(
  regime_tag    = tag,
  regime_tag_m4 = tag_m4,
  date          = as.character(last_row$Date),
  score         = round(as.numeric(last_row$Regime_Score), 4),
  source        = "unified_regime_signal_daily.parquet",
  generated_at  = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  m4_map_note   = "RISK_ON→BULL, NEUTRAL→NORMAL, CAUTION→CAUTION, RISK_OFF→CRISIS(보수), CRISIS→CRISIS"
), OUT, auto_unbox = TRUE, pretty = TRUE)
cat(sprintf("[gen] 저장: %s (regime_tag=%s / m4=%s)\n", OUT, tag, tag_m4))
