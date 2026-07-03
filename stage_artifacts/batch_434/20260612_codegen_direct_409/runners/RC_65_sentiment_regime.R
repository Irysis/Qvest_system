#!/usr/bin/env Rscript
suppressPackageStartupMessages(library(jsonlite))
result_path <- "/mnt/c/Users/99922/OneDrive/Quant_Module_Moltbot/stage_artifacts/batch_434/20260612_codegen_direct_409/RC_65_sentiment_regime_result.rds"
dir.create(dirname(result_path), recursive = TRUE, showWarnings = FALSE)
res <- list(
  item_id = "RC_65_sentiment_regime",
  strategy_name = "Sentiment Regime — 거래량+신용거래+IPO 종합 심리 지수 국면",
  status = "NOT_BACKTESTED",
  execution_class = "BUILD_THEN_RUN",
  direct_status = "DATA_REQUIRED_NO_BACKTEST",
  reason = "Required external/non-cached data is unavailable. No synthetic backtest created.",
  spec_excerpt = "Sentiment Regime — 거래량+신용거래+IPO 종합 심리 지수 국면 RC_65_sentiment_regime regime_conditional explore Forge contract/spec requires code generation before backtest Forge contract/spec requires code generation before backtest RC_65 regime_conditional 30 ZZZ1(센티먼트 프록시)의 국면 전환 버전. 3변수 종합 심리 지수로 과열/공포/정상 3-state. DD_med only + regime_engine_daily.R + VT 0.25",
  validation = list(parse_ok = TRUE, pit_status = "NOT_RUN", contract_status = "NO_SYNTHETIC_PROXY"),
  created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
)
saveRDS(res, result_path)
write_json(res, sub("\\.rds$", ".json", result_path), auto_unbox = TRUE, pretty = TRUE, na = "null")
cat("[codegen-runner] NOT_BACKTESTED RC_65_sentiment_regime: DATA_REQUIRED_NO_BACKTEST\\n")
