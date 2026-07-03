#!/usr/bin/env Rscript
suppressPackageStartupMessages(library(jsonlite))
item_id <- "ALPHA_02"
result_path <- "stage_artifacts/batch_434/20260612_codegen_409/ALPHA_02_result.rds"
dir.create(dirname(result_path), recursive = TRUE, showWarnings = FALSE)
res <- list(
  item_id = "ALPHA_02",
  strategy_name = "Option-Implied Vol Skew (VKOSPI) → 종목별 위험 프리미엄 Alpha",
  status = "DATA_BLOCKED",
  execution_class = "DATA_FIRST",
  mapping_quality = "DATA_REQUIRED_NO_BACKTEST",
  reason = "Required external/non-cached data is unavailable; no synthetic backtest created.",
  validation = list(parse_ok = TRUE, pit_status = "NOT_RUN_DATA_REQUIRED", contract_status = "NOT_CREATED"),
  created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
)
saveRDS(res, result_path)
write_json(res, sub("\\.rds$", ".json", result_path), auto_unbox = TRUE, pretty = TRUE, na = "null")
cat(sprintf("[codegen-runner] DATA_BLOCKED %s -> %s\n", item_id, result_path))
