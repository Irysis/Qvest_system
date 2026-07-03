#!/usr/bin/env Rscript
suppressPackageStartupMessages(library(jsonlite))
item_id <- "RC_38_int_ext_combined"
result_path <- "stage_artifacts/batch_434/20260612_codegen_409/RC_38_int_ext_combined_result.rds"
dir.create(dirname(result_path), recursive = TRUE, showWarnings = FALSE)
res <- list(
  item_id = "RC_38_int_ext_combined",
  strategy_name = "Internal+External 결합 국면 — MRS(외부) + DD(내부) + Dispersion(내생) 3축 가중합",
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
