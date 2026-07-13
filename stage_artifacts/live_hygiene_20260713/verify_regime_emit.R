## verify_regime_emit.R — task #48 item 2 배선 검증 (2026-07-13)
## regime_signal.R 패치(daily write_parquet 직후 regime_current.json emit) 실동작 확인:
## daily 빌드 1회 구동 → parquet 재생성 + JSON emit 로그 + 내용 정합 검사.
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
data.table::setDTthreads(1L)
arrow::set_cpu_count(1L); arrow::set_io_thread_count(2L)

ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(file.path(ROOT, "02_Infrastructure"))
source("config.R")
source(file.path(ROOT, "02_Infrastructure/regime/regime_signal.R"))

js_before <- fromJSON(file.path(ROOT, ".cache/regime_current.json"))
cat(sprintf("[verify] emit 전 JSON generated_at: %s\n", js_before$generated_at))

sig <- build_regime_signal_table(daily = TRUE)

js <- fromJSON(file.path(ROOT, ".cache/regime_current.json"))
last_row <- as.data.table(sig)[which.max(as.Date(Date))]
cat("\n[verify] ===== emit 정합 검사 =====\n")
cat(sprintf("  JSON: regime_tag=%s / m4=%s / date=%s / score=%s / generated_at=%s\n",
            js$regime_tag, js$regime_tag_m4, js$date, js$score, js$generated_at))
cat(sprintf("  parquet last row: Category=%s / Date=%s / Score=%.4f\n",
            last_row$Category, as.character(last_row$Date), last_row$Regime_Score))
ok <- identical(js$regime_tag, as.character(last_row$Category)) &&
      identical(js$date, as.character(as.Date(last_row$Date))) &&
      abs(js$score - round(last_row$Regime_Score, 4)) < 1e-9 &&
      !identical(js$generated_at, js_before$generated_at)
cat(sprintf("[verify] emit wiring: %s\n", if (ok) "PASS (JSON == parquet 최종행, generated_at 갱신)" else "FAIL - 확인 필요"))
if (!ok) quit(status = 1)
