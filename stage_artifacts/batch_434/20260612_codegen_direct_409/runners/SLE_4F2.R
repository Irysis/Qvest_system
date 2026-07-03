#!/usr/bin/env Rscript
suppressPackageStartupMessages(library(jsonlite))
result_path <- "/mnt/c/Users/99922/OneDrive/Quant_Module_Moltbot/stage_artifacts/batch_434/20260612_codegen_direct_409/SLE_4F2_result.rds"
dir.create(dirname(result_path), recursive = TRUE, showWarnings = FALSE)
res <- list(
  item_id = "SLE_4F2",
  strategy_name = "Margin Gate (OPM bottom 10% 제거) + Score 50/30/20",
  status = "NOT_BACKTESTED",
  execution_class = "BUILD_THEN_RUN",
  direct_status = "DATA_REQUIRED_NO_BACKTEST",
  reason = "Required external/non-cached data is unavailable. No synthetic backtest created.",
  spec_excerpt = "Margin Gate (OPM bottom 10% 제거) + Score 50/30/20 SLE_4F2 stock_level_ensemble_gated explore Forge contract/spec requires code generation before backtest Forge contract/spec requires code generation before backtest stock_level_ensemble_gated STR_1053 KOSPI+KOSDAQ (LIQ >= 2e8, margin gate pass) monthly 30 영업이익률(OPM) 하위 10% 종목 사전 제거 후 score 앙상블 적용. L-403: quality는 gate(worst 제거)로만 유효, scoring 투입 시 defense 희석. L-306: CCC+DeltaAccrual dual gate Grade A 달성. 마진 gate는 수익성 악화 종목 제거 → 재무건전성 필터 STR_1048 factor_engine.R + DART OPM gate DART OPM(영업이익률) 하위 10% 종목 제거. expanding window median 기준. DART lag 45d (C4) 0.50 * z_defense + 0.30 * z_consensus + 0.20 * z_indmom (gate 통과 유니버스에서) EW 50 25 TRUE regime_engine_daily.R v7.1 + VT/DD t-1 lag N <= 30 LIQ >= 2e8 Gate only — OPM scoring 금지(L-403) PIT enforce",
  validation = list(parse_ok = TRUE, pit_status = "NOT_RUN", contract_status = "NO_SYNTHETIC_PROXY"),
  created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
)
saveRDS(res, result_path)
write_json(res, sub("\\.rds$", ".json", result_path), auto_unbox = TRUE, pretty = TRUE, na = "null")
cat("[codegen-runner] NOT_BACKTESTED SLE_4F2: DATA_REQUIRED_NO_BACKTEST\\n")
