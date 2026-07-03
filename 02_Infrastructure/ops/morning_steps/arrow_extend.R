# [2/5] Arrow + KTRI 연장 — RAWDATA arrow 데이터셋 확장.
# ★외부화 2026-06-19: 기존 인라인 멀티라인 `Rscript -e`(첫 줄 invisible(NULL)) no-op 트랩 수리 → 단일줄 source.
source("02_Infrastructure/ops/morning_steps/_root.R")
source("02_Infrastructure/data/krx_data_collector.R")
source("02_Infrastructure/data/krx_arrow_pipeline.R")
tryCatch({ krx_extend_arrow(); cat("Arrow extension complete.\n") },
         error = function(e) cat(sprintf("Arrow extension skipped: %s\n", e$message)))
