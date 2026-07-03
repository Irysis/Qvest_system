#!/usr/bin/env Rscript
suppressPackageStartupMessages(library(jsonlite))
result_path <- "/mnt/c/Users/99922/OneDrive/Quant_Module_Moltbot/stage_artifacts/batch_434/20260612_codegen_direct_409/MF_ZZZ1_SENTIMENT_PROXY_result.rds"
dir.create(dirname(result_path), recursive = TRUE, showWarnings = FALSE)
res <- list(
  item_id = "MF_ZZZ1_SENTIMENT_PROXY",
  strategy_name = "센티먼트 프록시 — 거래량 서프라이즈 + 신용거래 비율로 과열/공포 측정",
  status = "NOT_BACKTESTED",
  execution_class = "BUILD_THEN_RUN",
  direct_status = "DATA_REQUIRED_NO_BACKTEST",
  reason = "Required external/non-cached data is unavailable. No synthetic backtest created.",
  spec_excerpt = "센티먼트 프록시 — 거래량 서프라이즈 + 신용거래 비율로 과열/공포 측정 MF_ZZZ1_SENTIMENT_PROXY multifactor_sentiment explore Forge contract/spec requires code generation before backtest Forge contract/spec requires code generation before backtest MF_ZZZ1 multifactor_sentiment 30 Baker & Wurgler(2006): 투자자 심리가 팩터 프리미엄에 영향. NLP 센티먼트 대신 시장 데이터 프록시(거래량 서프라이즈, 신용거래 비율)로 심리 측정. 과열 시 Defense 강화, 공포 시 Momentum 강화. z(시장 전체 거래대금 / 20d MA) — 비정상 거래량 = 과열/공포 신용거래 잔고 / 시총 (KRX 데이터, 가용 시) 최근 3m IPO 건수 (과열 시 IPO 급증) z(volume_surprise) + z(margin_ratio) + z(ipo_count), z-scored sentiment > 1.0 Defense 40% + Quality 25% + Value 20% + Others 15% sentiment < -1.0 Momentum 30% + Consensus 25% + IndMom 20% + Others 25% MF_A1 Core DD_med only + regime_engine_daily.R + VT 0.25",
  validation = list(parse_ok = TRUE, pit_status = "NOT_RUN", contract_status = "NO_SYNTHETIC_PROXY"),
  created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
)
saveRDS(res, result_path)
write_json(res, sub("\\.rds$", ".json", result_path), auto_unbox = TRUE, pretty = TRUE, na = "null")
cat("[codegen-runner] NOT_BACKTESTED MF_ZZZ1_SENTIMENT_PROXY: DATA_REQUIRED_NO_BACKTEST\\n")
