#!/usr/bin/env Rscript
suppressPackageStartupMessages(library(jsonlite))
result_path <- "/mnt/c/Users/99922/OneDrive/Quant_Module_Moltbot/stage_artifacts/batch_434/20260612_codegen_direct_409/RC_31_kr_internals_only_result.rds"
dir.create(dirname(result_path), recursive = TRUE, showWarnings = FALSE)
res <- list(
  item_id = "RC_31_kr_internals_only",
  strategy_name = "한국 내부 시그널 Only — ECOS+KRX 데이터만으로 국면 판단 (FRED 제외)",
  status = "NOT_BACKTESTED",
  execution_class = "DATA_FIRST",
  direct_status = "DATA_REQUIRED_NO_BACKTEST",
  reason = "Required external/non-cached data is unavailable. No synthetic backtest created.",
  spec_excerpt = "한국 내부 시그널 Only — ECOS+KRX 데이터만으로 국면 판단 (FRED 제외) RC_31_kr_internals_only regime_conditional exploit requires external/cache data collection or validation before backtest requires external/cache data collection or validation before backtest RC_31 regime_conditional 30 L-454: 한국 내부(cor=-0.460) > 글로벌 FRED(-0.137). regime_engine_daily.R의 FRED 축 제거, ECOS/KRX 4축만으로 국면 판단. KRW/USD 20d 변화율 (ECOS) 회사채AA-국고채3Y 스프레드 (ECOS) KOSPI200 외국인 순매수 20d (KRX) 횡단면 분산도 (RAWDATA) KMRS = mean(z(4 axes), expanding, t-1) KMRS 기반 soft ramp (KMRS 15→25 → exposure 100%→30%) MF_A1 7F composite DD_med only + VT 0.25 (KMRS가 MRS 대체)",
  validation = list(parse_ok = TRUE, pit_status = "NOT_RUN", contract_status = "NO_SYNTHETIC_PROXY"),
  created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
)
saveRDS(res, result_path)
write_json(res, sub("\\.rds$", ".json", result_path), auto_unbox = TRUE, pretty = TRUE, na = "null")
cat("[codegen-runner] NOT_BACKTESTED RC_31_kr_internals_only: DATA_REQUIRED_NO_BACKTEST\\n")
