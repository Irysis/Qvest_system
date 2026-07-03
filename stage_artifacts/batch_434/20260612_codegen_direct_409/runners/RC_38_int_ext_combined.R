#!/usr/bin/env Rscript
suppressPackageStartupMessages(library(jsonlite))
result_path <- "/mnt/c/Users/99922/OneDrive/Quant_Module_Moltbot/stage_artifacts/batch_434/20260612_codegen_direct_409/RC_38_int_ext_combined_result.rds"
dir.create(dirname(result_path), recursive = TRUE, showWarnings = FALSE)
res <- list(
  item_id = "RC_38_int_ext_combined",
  strategy_name = "Internal+External 결합 국면 — MRS(외부) + DD(내부) + Dispersion(내생) 3축 가중합",
  status = "NOT_BACKTESTED",
  execution_class = "BUILD_THEN_RUN",
  direct_status = "DATA_REQUIRED_NO_BACKTEST",
  reason = "Required external/non-cached data is unavailable. No synthetic backtest created.",
  spec_excerpt = "Internal+External 결합 국면 — MRS(외부) + DD(내부) + Dispersion(내생) 3축 가중합 RC_38_int_ext_combined regime_conditional exploit Forge contract/spec requires code generation before backtest Forge contract/spec requires code generation before backtest RC_38 regime_conditional 30 RC_07(Twin MRS×DD)의 3축 확장. 외부(MRS) + 내부(포트폴리오 DD) + 내생(Dispersion) 3축 연속 z-score 합산 = Composite Risk Score. CRS = 0.40*z(MRS) + 0.30*z(portfolio_dd) + 0.30*z(dispersion), all t-1 w_defense = 0.15 + 0.25*pmin(1, pmax(0, CRS/2)). 나머지 EW. VT 0.25",
  validation = list(parse_ok = TRUE, pit_status = "NOT_RUN", contract_status = "NO_SYNTHETIC_PROXY"),
  created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
)
saveRDS(res, result_path)
write_json(res, sub("\\.rds$", ".json", result_path), auto_unbox = TRUE, pretty = TRUE, na = "null")
cat("[codegen-runner] NOT_BACKTESTED RC_38_int_ext_combined: DATA_REQUIRED_NO_BACKTEST\\n")
