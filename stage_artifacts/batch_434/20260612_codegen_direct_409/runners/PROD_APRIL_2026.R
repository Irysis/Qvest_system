#!/usr/bin/env Rscript
suppressPackageStartupMessages(library(jsonlite))
result_path <- "/mnt/c/Users/99922/OneDrive/Quant_Module_Moltbot/stage_artifacts/batch_434/20260612_codegen_direct_409/PROD_APRIL_2026_result.rds"
dir.create(dirname(result_path), recursive = TRUE, showWarnings = FALSE)
res <- list(
  item_id = "PROD_APRIL_2026",
  strategy_name = "4월 실투 전략: STR_1060 기반, Daily Regime 없이, 월간 30종목 EW",
  status = "NOT_BACKTESTED",
  execution_class = "BUILD_THEN_RUN",
  direct_status = "DATA_REQUIRED_NO_BACKTEST",
  reason = "Required external/non-cached data is unavailable. No synthetic backtest created.",
  spec_excerpt = "4월 실투 전략: STR_1060 기반, Daily Regime 없이, 월간 30종목 EW PROD_APRIL_2026 NA production Forge contract/spec requires code generation before backtest Forge contract/spec requires code generation before backtest 2026년 4월 실투자 가능한 최적 포트폴리오 생성 30종목, 월간 리밸런싱, LIQ >= 2e8, commission 30bps STR_1060 (ALL-TIME HIGH Score 87.1, CAGR 22.66%, SR 1.333, MDD 24.8%) Daily Regime 없이 = 실시간 국면 감지 불필요 → 월간 리밸런싱만으로 실행 가능. regime_engine_daily.R 대신 월말 MRS 상태만 참조 월말 기준 MRS 상태(macro_regime.parquet 최신값) 확인. Crisis면 현금비중 확대(30~70%), Normal이면 full invest DD Brake 없음(L-508: Short DD 제거가 최적), VT 0.25 유지 6 -IdioVol - Beta (z-score EW) EW 6 Industry momentum 6m EW 6 SUE pure EW 6 Consensus + Defense gate EW 6 TP Gap + TP Momentum EW 30 Option A: ConsGate를 OCF_ROA sleeve로 대체 (ALPHA_13 활용) Option B: PiotroskiF < 3 gate 전체 유니버스에 적",
  validation = list(parse_ok = TRUE, pit_status = "NOT_RUN", contract_status = "NO_SYNTHETIC_PROXY"),
  created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
)
saveRDS(res, result_path)
write_json(res, sub("\\.rds$", ".json", result_path), auto_unbox = TRUE, pretty = TRUE, na = "null")
cat("[codegen-runner] NOT_BACKTESTED PROD_APRIL_2026: DATA_REQUIRED_NO_BACKTEST\\n")
