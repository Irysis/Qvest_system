#!/usr/bin/env Rscript
suppressPackageStartupMessages(library(jsonlite))
item_id <- "MF_ZZZ1_SENTIMENT_PROXY"
result_path <- "stage_artifacts/batch_434/20260612_codegen_409/MF_ZZZ1_SENTIMENT_PROXY_result.rds"
dir.create(dirname(result_path), recursive = TRUE, showWarnings = FALSE)
res <- list(
  item_id = "MF_ZZZ1_SENTIMENT_PROXY",
  strategy_name = "센티먼트 프록시 — 거래량 서프라이즈 + 신용거래 비율로 과열/공포 측정",
  status = "DATA_BLOCKED",
  execution_class = "BUILD_THEN_RUN",
  mapping_quality = "DATA_REQUIRED_NO_BACKTEST",
  reason = "Required external/non-cached data is unavailable; no synthetic backtest created.",
  validation = list(parse_ok = TRUE, pit_status = "NOT_RUN_DATA_REQUIRED", contract_status = "NOT_CREATED"),
  created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
)
saveRDS(res, result_path)
write_json(res, sub("\\.rds$", ".json", result_path), auto_unbox = TRUE, pretty = TRUE, na = "null")
cat(sprintf("[codegen-runner] DATA_BLOCKED %s -> %s\n", item_id, result_path))
