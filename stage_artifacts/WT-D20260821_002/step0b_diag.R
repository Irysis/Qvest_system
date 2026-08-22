## 재현 드리프트 진단 — 포트 레그(ret_net) vs 벤치 레그(benchmark_ret) 분리
suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)})
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
S <- readRDS("stage_artifacts/WT-D20260821_002/step0_inputs.rds")
A <- readRDS("stage_artifacts/fq233_probe0_20260813/armA_canonical_result.rds")
prA <- as.data.table(A$period_returns)
re <- canonical_screen_bt(scores_dt = S$panels$armA[, .(Date, Ticker, score = as.numeric(score))],
                          returns_dt = S$frd, bench_dt = S$bench_dt, top_n = 25L,
                          cost_bps_oneway = 15, strategy_id = "x", run_id = "x",
                          diag_dual_basis = FALSE)
pr2 <- as.data.table(re$period_returns)
j <- merge(prA[, .(date, ret_net_old = ret_net, bm_old = benchmark_ret)],
           pr2[, .(date, ret_net_new = ret_net, bm_new = benchmark_ret)], by = "date")
out <- list(
  n_overlap = nrow(j),
  n_old = nrow(prA), n_new = nrow(pr2),
  retnet_max_abs_diff = max(abs(j$ret_net_new - j$ret_net_old)),
  retnet_n_diff = sum(abs(j$ret_net_new - j$ret_net_old) > 1e-12),
  bm_max_abs_diff = max(abs(j$bm_new - j$bm_old)),
  bm_n_diff = sum(abs(j$bm_new - j$bm_old) > 1e-12),
  bm_diff_dates = as.character(j$date[abs(j$bm_new - j$bm_old) > 1e-12]),
  benchmark_parquet_mtime = format(file.info(".cache/benchmark.parquet")$mtime))
cat(toJSON(out, auto_unbox = TRUE, pretty = TRUE, digits = 12), "\n")
write_json(out, "stage_artifacts/WT-D20260821_002/step0b_repro_drift.json",
           auto_unbox = TRUE, pretty = TRUE, digits = 12)
