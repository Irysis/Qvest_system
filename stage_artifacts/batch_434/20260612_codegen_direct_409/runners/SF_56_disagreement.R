#!/usr/bin/env Rscript
suppressPackageStartupMessages(library(jsonlite))
result_path <- "/mnt/c/Users/99922/OneDrive/Quant_Module_Moltbot/stage_artifacts/batch_434/20260612_codegen_direct_409/SF_56_disagreement_result.rds"
dir.create(dirname(result_path), recursive = TRUE, showWarnings = FALSE)
res <- list(
  item_id = "SF_56_disagreement",
  strategy_name = "Analyst Disagreement — EPS 전망치 분산 낮은 종목 선호",
  status = "NOT_BACKTESTED",
  execution_class = "DATA_FIRST",
  direct_status = "DATA_REQUIRED_NO_BACKTEST",
  reason = "Required external/non-cached data is unavailable. No synthetic backtest created.",
  spec_excerpt = "Analyst Disagreement — EPS 전망치 분산 낮은 종목 선호 SF_56_disagreement single_factor explore requires external/cache data collection or validation before backtest requires external/cache data collection or validation before backtest SF_56 single_factor 30 Diether et al.(2002): 애널리스트 의견 불일치 높은 종목 = 미래 수익 낮음. 낮은 disagreement 선호. z(-EPS_forecast_std / abs(EPS_forecast_mean)), sector neutral DD_med only + regime_engine_daily.R + VT 0.25",
  validation = list(parse_ok = TRUE, pit_status = "NOT_RUN", contract_status = "NO_SYNTHETIC_PROXY"),
  created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
)
saveRDS(res, result_path)
write_json(res, sub("\\.rds$", ".json", result_path), auto_unbox = TRUE, pretty = TRUE, na = "null")
cat("[codegen-runner] NOT_BACKTESTED SF_56_disagreement: DATA_REQUIRED_NO_BACKTEST\\n")
