#!/usr/bin/env Rscript
suppressPackageStartupMessages(library(jsonlite))
result_path <- "/mnt/c/Users/99922/OneDrive/Quant_Module_Moltbot/stage_artifacts/batch_434/20260612_codegen_direct_409/RC_70_iv_rv_result.rds"
dir.create(dirname(result_path), recursive = TRUE, showWarnings = FALSE)
res <- list(
  item_id = "RC_70_iv_rv",
  strategy_name = "IV-RV Spread Regime — VKOSPI vs RV 차이로 공포 프리미엄 국면",
  status = "NOT_BACKTESTED",
  execution_class = "BUILD_THEN_RUN",
  direct_status = "DATA_REQUIRED_NO_BACKTEST",
  reason = "Required external/non-cached data is unavailable. No synthetic backtest created.",
  spec_excerpt = "IV-RV Spread Regime — VKOSPI vs RV 차이로 공포 프리미엄 국면 RC_70_iv_rv regime_conditional explore Forge contract/spec requires code generation before backtest Forge contract/spec requires code generation before backtest RC_70 regime_conditional 30 VVV1(VRP)의 정밀화. IV-RV 스프레드 z > 1.5 → 공포 과다 → 역발상 공격. DD_med only + regime_engine_daily.R + VT 0.25",
  validation = list(parse_ok = TRUE, pit_status = "NOT_RUN", contract_status = "NO_SYNTHETIC_PROXY"),
  created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
)
saveRDS(res, result_path)
write_json(res, sub("\\.rds$", ".json", result_path), auto_unbox = TRUE, pretty = TRUE, na = "null")
cat("[codegen-runner] NOT_BACKTESTED RC_70_iv_rv: DATA_REQUIRED_NO_BACKTEST\\n")
